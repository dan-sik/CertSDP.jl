const RATIONAL_CERTIFICATE_TYPE = "rational_psd_certificate"
const BLOCK_RATIONAL_CERTIFICATE_TYPE = "block_rational_psd_certificate"
const RATIONAL_SOLUTION_TYPE = "rational"
const RATIONAL_PSD_METHOD = "principal_minors"

"""
    RationalPSDProof(method, matrix, principal_minors)

Store the claimed exact substituted matrix and all principal minors for a
Type R rational certificate. The verifier recomputes these values.
"""
struct RationalPSDProof
    method::Symbol
    matrix::SymmetricRationalMatrix
    principal_minors::Vector{PrincipalMinorProof{Rational{BigInt}}}
    schur_zero::Union{Nothing, SchurZeroProof{Rational{BigInt}}}
    ldl::Union{Nothing, LDLProof{Rational{BigInt}}}
end

"""
    BlockRationalPSDProof(block_proofs)

Store one exact rational PSD proof per PSD block. The top-level method is always
`:blockwise`; each child proof is replayed independently by the verifier.
"""
struct BlockRationalPSDProof
    method::Symbol
    block_proofs::Vector{RationalPSDProof}

    function BlockRationalPSDProof(block_proofs::AbstractVector{RationalPSDProof})
        isempty(block_proofs) &&
            throw(ArgumentError("blockwise rational PSD proof needs at least one block proof"))
        return new(Symbol(BLOCKWISE_PSD_METHOD), RationalPSDProof[block_proofs...])
    end
end

function RationalPSDProof(method::Symbol, matrix::SymmetricRationalMatrix,
                          principal_minors::Vector{PrincipalMinorProof{Rational{BigInt}}})
    return RationalPSDProof(method, matrix, principal_minors, nothing, nothing)
end

function RationalPSDProof(method::Symbol, matrix::SymmetricRationalMatrix,
                          principal_minors::AbstractVector{<:PrincipalMinorProof})
    minors = PrincipalMinorProof{Rational{BigInt}}[]
    for minor in principal_minors
        push!(minors, PrincipalMinorProof(minor.indices, minor.determinant))
    end
    return RationalPSDProof(method, matrix, minors, nothing, nothing)
end

"""
    RationalCertificate(problem, x)

Build a Type R certificate for an exact rational LMI solution `x`.
"""
struct RationalCertificate
    problem::LMIProblem
    solution::Vector{Rational{BigInt}}
    psd_proof::RationalPSDProof
    hash::String
end

"""
    BlockRationalCertificate(problem, x)

Build a blockwise Type R certificate for an exact rational solution of a
`BlockLMIProblem`. The certificate proves every PSD block independently and the
verifier reports failures with block-local proof data.
"""
struct BlockRationalCertificate
    problem::BlockLMIProblem
    solution::Vector{Rational{BigInt}}
    psd_proof::BlockRationalPSDProof
    hash::String
end

function RationalCertificate(P::LMIProblem, x::AbstractVector;
                             psd_method::Union{Symbol, AbstractString}=Symbol(RATIONAL_PSD_METHOD),
                             pivot_block=nothing)
    solution = [_to_big_rational(value; name=Symbol("x", i)) for (i, value) in enumerate(x)]
    length(solution) == num_variables(P) ||
        throw(DimensionMismatch("certificate solution has length $(length(solution)); expected $(num_variables(P))"))

    proof = rational_psd_proof(substitute(P, solution); method=psd_method, pivot_block)
    cert_without_hash = RationalCertificate(P, solution, proof, "")
    return RationalCertificate(P, solution, proof,
                               rational_certificate_hash(cert_without_hash))
end

function RationalCertificate(P::BlockLMIProblem, x::AbstractVector;
                             psd_method::Union{Symbol, AbstractString}=:auto,
                             block_pivot_blocks=nothing,
                             pivot_block=nothing)
    return BlockRationalCertificate(P, x; psd_method,
                                    block_pivot_blocks=isnothing(block_pivot_blocks) ?
                                                       pivot_block :
                                                       block_pivot_blocks)
end

function BlockRationalCertificate(P::BlockLMIProblem, x::AbstractVector;
                                  psd_method::Union{Symbol, AbstractString}=:auto,
                                  block_pivot_blocks=nothing)
    solution = [_to_big_rational(value; name=Symbol("x", i)) for (i, value) in enumerate(x)]
    length(solution) == num_variables(P) ||
        throw(DimensionMismatch("block certificate solution has length $(length(solution)); expected $(num_variables(P))"))

    proof = block_rational_psd_proof(substitute(P, solution);
                                     method=psd_method,
                                     block_pivot_blocks)
    cert_without_hash = BlockRationalCertificate(P, solution, proof, "")
    return BlockRationalCertificate(P, solution, proof,
                                    block_rational_certificate_hash(cert_without_hash))
end

"""
    rational_psd_proof(A) -> RationalPSDProof

Create an exact principal-minor PSD proof for a small rational symmetric matrix.
"""
function rational_psd_proof(A;
                            method::Union{Symbol, AbstractString}=Symbol(RATIONAL_PSD_METHOD),
                            pivot_block=nothing,
                            max_size::Integer=DEFAULT_MAX_PSD_PRINCIPAL_MINOR_SIZE)
    matrix = SymmetricRationalMatrix(_as_psd_rational_matrix(A); name=:psd_proof_matrix)
    plan = choose_psd_proof(matrix, nothing; method=Symbol(method), pivot_block, max_size)
    plan.status === :accepted ||
        throw(ArgumentError("cannot create a rational PSD proof: $(_failure_message(PSDVerificationResult(false, plan.method, plan.failure)))"))
    return _rational_psd_proof_from_plan(plan)
end

"""
    block_rational_psd_proof(blocks; method=:auto)

Create exact blockwise rational PSD proof data from substituted rational PSD
blocks. `method` selects the per-block proof method unless it is `:blockwise`,
in which case each block uses the automatic planner.
"""
function block_rational_psd_proof(blocks;
                                  method::Union{Symbol, AbstractString}=:auto,
                                  block_pivot_blocks=nothing,
                                  max_size::Integer=DEFAULT_MAX_PSD_PRINCIPAL_MINOR_SIZE)
    block_method = Symbol(method) === Symbol(BLOCKWISE_PSD_METHOD) ? :auto :
                   Symbol(method)
    plan = choose_psd_proof(blocks, nothing; method=:blockwise, block_method,
                            block_pivot_blocks, max_size)
    plan.status === :accepted ||
        throw(ArgumentError("cannot create a blockwise rational PSD proof: $(_failure_message(PSDVerificationResult(false, plan.method, plan.failure)))"))
    return _block_rational_psd_proof_from_plan(plan)
end

function _block_rational_psd_proof_from_plan(plan::PSDProofPlan)
    plan.method === Symbol(BLOCKWISE_PSD_METHOD) ||
        throw(ArgumentError("block rational PSD proof requires a blockwise plan"))
    plan.status === :accepted ||
        throw(ArgumentError("cannot build block rational PSD proof from a rejected plan"))
    return BlockRationalPSDProof([_rational_psd_proof_from_plan(block_plan)
                                  for block_plan in plan.block_plans])
end

function _rational_psd_proof_unchecked(matrix::SymmetricRationalMatrix)
    return RationalPSDProof(Symbol(RATIONAL_PSD_METHOD), matrix,
                            _principal_minor_proofs_rational(matrix))
end

function _rational_psd_proof_from_plan(plan::PSDProofPlan)
    plan.status === :accepted ||
        throw(ArgumentError("cannot build rational PSD proof from a rejected plan"))
    matrix = plan.matrix
    matrix isa SymmetricRationalMatrix ||
        throw(ArgumentError("rational PSD proof plan does not contain a rational matrix"))

    if plan.method === Symbol(RATIONAL_PSD_METHOD)
        return RationalPSDProof(Symbol(RATIONAL_PSD_METHOD), matrix,
                                PrincipalMinorProof{Rational{BigInt}}[plan.principal_minors...])
    elseif plan.method === Symbol(SCHUR_ZERO_PSD_METHOD)
        return RationalPSDProof(Symbol(SCHUR_ZERO_PSD_METHOD), matrix,
                                PrincipalMinorProof{Rational{BigInt}}[],
                                plan.schur_zero, nothing)
    elseif plan.method === Symbol(LDL_PSD_METHOD)
        return RationalPSDProof(Symbol(LDL_PSD_METHOD), matrix,
                                PrincipalMinorProof{Rational{BigInt}}[],
                                nothing, plan.ldl)
    elseif plan.method === Symbol(PIVOTED_LDL_PSD_METHOD)
        return RationalPSDProof(Symbol(PIVOTED_LDL_PSD_METHOD), matrix,
                                PrincipalMinorProof{Rational{BigInt}}[],
                                nothing, plan.ldl)
    end

    throw(ArgumentError("unsupported rational PSD proof method $(plan.method)"))
end

"""
    rational_certificate_hash(cert) -> String

Return the stable SHA-256 hash of a Type R certificate, excluding the top-level
`hash` field itself.
"""
function rational_certificate_hash(cert::RationalCertificate)
    canonical = _canonical_rational_certificate_json(cert)
    return "sha256:" * bytes2hex(sha256(JSON3.write(canonical)))
end

function block_rational_certificate_hash(cert::BlockRationalCertificate)
    canonical = _canonical_block_rational_certificate_json(cert)
    return "sha256:" * bytes2hex(sha256(JSON3.write(canonical)))
end

"""
    rational_certificate_json(cert) -> NamedTuple

Return the JSON-ready Type R certificate object.
"""
function rational_certificate_json(cert::RationalCertificate)
    return merge(_canonical_rational_certificate_json(cert), (; hash=cert.hash))
end

function block_rational_certificate_json(cert::BlockRationalCertificate)
    return merge(_canonical_block_rational_certificate_json(cert), (; hash=cert.hash))
end

"""
    rational_certificate_json_string(cert) -> String

Return a pretty-printed JSON representation of `cert`.
"""
function rational_certificate_json_string(cert::RationalCertificate)
    io = IOBuffer()
    JSON3.pretty(io, rational_certificate_json(cert))
    println(io)
    return String(take!(io))
end

function block_rational_certificate_json_string(cert::BlockRationalCertificate)
    io = IOBuffer()
    JSON3.pretty(io, block_rational_certificate_json(cert))
    println(io)
    return String(take!(io))
end

"""
    write_certificate(path, cert)

Write a Type R rational certificate as JSON.
"""
function write_certificate(path::AbstractString, cert::RationalCertificate)
    open(path, "w") do io
        return write(io, certificate_json_v1_string(cert))
    end
    return path
end

function write_certificate(path::AbstractString, cert::BlockRationalCertificate)
    open(path, "w") do io
        return write(io, certificate_json_v1_string(cert))
    end
    return path
end

function save_certificate(path::AbstractString, cert::RationalCertificate)
    return write_certificate(path, cert)
end

function save_certificate(path::AbstractString, cert::BlockRationalCertificate)
    return write_certificate(path, cert)
end

"""
    read_certificate(path) -> RationalCertificate

Read a Type R rational certificate JSON file.
"""
function read_certificate(path::AbstractString)
    return parse_certificate_json(read(path, String))
end

load_certificate(path::AbstractString) = read_certificate(path)

"""
    parse_certificate_json(json_text)

Parse a certificate JSON file. Structural JSON problems raise `ArgumentError`;
mathematical validity is checked by `verify(cert)`.
"""
function parse_certificate_json(json_text::AbstractString)
    parsed = try
        JSON3.read(json_text)
    catch err
        throw(ArgumentError("invalid certificate JSON: $(sprint(showerror, err))"))
    end

    _require_object(parsed, "root")
    if haskey(parsed, :certsdp_artifact_version) &&
       String(parsed[:certsdp_artifact_version]) == CERTSDP_2_0_ARTIFACT_VERSION
        return _parse_exact_certificate_object(parsed)
    end
    if haskey(parsed, CERTSDP_CERTIFICATE_VERSION_KEY)
        return _parse_certificate_v1_object(parsed)
    end

    _require_value(parsed, :certsdp_version, LMI_JSON_VERSION, "root.certsdp_version")
    certificate_type = _require_string(parsed, :certificate_type, "root.certificate_type")

    if certificate_type == RATIONAL_CERTIFICATE_TYPE
        return _parse_rational_certificate_object(parsed)
    elseif certificate_type == BLOCK_RATIONAL_CERTIFICATE_TYPE
        return _parse_block_rational_certificate_object(parsed)
    elseif certificate_type == ALGEBRAIC_CERTIFICATE_TYPE
        return _parse_algebraic_certificate_object(parsed)
    elseif certificate_type == BLOCK_ALGEBRAIC_CERTIFICATE_TYPE
        return _parse_block_algebraic_certificate_object(parsed)
    elseif certificate_type == SOS_GRAM_CERTIFICATE_TYPE
        return _parse_sos_gram_certificate_object(parsed)
    elseif certificate_type == ALGEBRAIC_SOS_GRAM_CERTIFICATE_TYPE
        return _parse_algebraic_sos_gram_certificate_v1_object(parsed)
    end

    throw(ArgumentError("root.certificate_type must be `$RATIONAL_CERTIFICATE_TYPE`, `$BLOCK_RATIONAL_CERTIFICATE_TYPE`, `$ALGEBRAIC_CERTIFICATE_TYPE`, `$BLOCK_ALGEBRAIC_CERTIFICATE_TYPE`, or `$SOS_GRAM_CERTIFICATE_TYPE`; got `$certificate_type`"))
end

function _parse_rational_certificate_object(parsed)
    problem = _parse_lmi_problem_object(_require_key(parsed, :problem, "root"))
    solution = _parse_rational_solution(_require_key(parsed, :solution, "root"),
                                        num_variables(problem))
    proof = _parse_rational_psd_proof(_require_key(parsed, :psd_proof, "root"),
                                      matrix_size(problem))
    hash = _require_string(parsed, :hash, "root.hash")

    return RationalCertificate(problem, solution, proof, hash)
end

function _parse_block_rational_certificate_object(parsed)
    problem = _parse_block_lmi_problem_object(_require_key(parsed, :problem, "root"))
    solution = _parse_rational_solution(_require_key(parsed, :solution, "root"),
                                        num_variables(problem))
    proof = _parse_block_rational_psd_proof(_require_key(parsed, :psd_proof, "root"),
                                            block_sizes(problem))
    hash = _require_string(parsed, :hash, "root.hash")
    return BlockRationalCertificate(problem, solution, proof, hash)
end

function _canonical_rational_certificate_json(cert::RationalCertificate)
    return (;
            certsdp_version=LMI_JSON_VERSION,
            certificate_type=RATIONAL_CERTIFICATE_TYPE,
            problem=merge(_canonical_lmi_problem_json(cert.problem),
                          (; hash=lmi_problem_hash(cert.problem))),
            solution=(;
                      type=RATIONAL_SOLUTION_TYPE,
                      x=[_rational_string(value) for value in cert.solution],),
            psd_proof=_rational_psd_proof_json(cert.psd_proof),)
end

function _canonical_block_rational_certificate_json(cert::BlockRationalCertificate)
    return (;
            certsdp_version=LMI_JSON_VERSION,
            certificate_type=BLOCK_RATIONAL_CERTIFICATE_TYPE,
            problem=merge(block_lmi_problem_json(cert.problem),
                          (; hash=block_lmi_problem_hash(cert.problem))),
            solution=(;
                      type=RATIONAL_SOLUTION_TYPE,
                      x=[_rational_string(value) for value in cert.solution],),
            psd_proof=_block_rational_psd_proof_json(cert.psd_proof, cert.problem),)
end

function _rational_psd_proof_json(proof::RationalPSDProof)
    base = (;
            method=String(proof.method),
            substituted_matrix=_json_matrix(proof.matrix),
            data=_rational_psd_proof_data_json(proof),)
    if proof.method === Symbol(RATIONAL_PSD_METHOD)
        return merge(base,
                     (;
                      principal_minors=_rational_principal_minors_json(proof.principal_minors),))
    end
    return base
end

function _block_rational_psd_proof_json(proof::BlockRationalPSDProof,
                                        problem::BlockLMIProblem)
    length(proof.block_proofs) == num_blocks(problem) ||
        throw(ArgumentError("blockwise proof has $(length(proof.block_proofs)) blocks; expected $(num_blocks(problem))"))
    return (;
            method=String(proof.method),
            blocks=[merge(_rational_psd_proof_json(block_proof),
                          (;
                           block_index=i,
                           block_kind=String(problem.block_kinds[i]),
                           matrix_size=matrix_size(problem.blocks[i]),))
                    for (i, block_proof) in enumerate(proof.block_proofs)],)
end

function _rational_psd_proof_data_json(proof::RationalPSDProof)
    if proof.method === Symbol(RATIONAL_PSD_METHOD)
        return (;
                principal_minors=_rational_principal_minors_json(proof.principal_minors),)
    elseif proof.method === Symbol(SCHUR_ZERO_PSD_METHOD)
        isnothing(proof.schur_zero) &&
            throw(ArgumentError("rational Schur-zero proof data is missing"))
        return (;
                pivot_block=proof.schur_zero.pivot_block,
                positive_block=(;
                                indices=proof.schur_zero.pivot_block,
                                proof="sylvester_principal_minors_positive",
                                leading_principal_minors=_rational_principal_minors_json(proof.schur_zero.positive_block_minors),),
                schur_complement=(;
                                  status="zero",
                                  entries=_json_rational_matrix(proof.schur_zero.schur_complement),),)
    elseif proof.method === Symbol(LDL_PSD_METHOD) ||
           proof.method === Symbol(PIVOTED_LDL_PSD_METHOD)
        isnothing(proof.ldl) && throw(ArgumentError("rational LDL proof data is missing"))
        return (;
                pivots=[(;
                         index=pivot.index,
                         value=_rational_string(pivot.value),
                         sign=String(pivot.sign),)
                        for pivot in proof.ldl.pivots],)
    end
    throw(ArgumentError("unknown rational PSD proof method: $(proof.method)"))
end

function _rational_principal_minors_json(minors)
    return [(;
             indices=minor.indices,
             determinant=_rational_string(minor.determinant),)
            for minor in minors]
end

function _json_rational_matrix(matrix::AbstractMatrix{<:Rational})
    return [[_rational_string(matrix[i, j]) for j in axes(matrix, 2)]
            for i in axes(matrix, 1)]
end

function _parse_rational_solution(solution, expected_length::Integer)
    _require_object(solution, "solution")
    _require_value(solution, :type, RATIONAL_SOLUTION_TYPE, "solution.type")
    x = _require_key(solution, :x, "solution")
    _require_array(x, "solution.x")
    length(x) == expected_length ||
        throw(ArgumentError("solution.x has length $(length(x)); expected $expected_length"))
    return [_parse_rational_string(value, "solution.x[$i]") for (i, value) in enumerate(x)]
end

function _parse_rational_psd_proof(proof, expected_size::Integer)
    _require_object(proof, "psd_proof")
    method_string = _require_string(proof, :method, "psd_proof.method")
    matrix = SymmetricRationalMatrix(_parse_rational_matrix(_require_key(proof,
                                                                         :substituted_matrix,
                                                                         "psd_proof"),
                                                            expected_size,
                                                            "psd_proof.substituted_matrix");
                                     name=:psd_proof_matrix,)
    data = haskey(proof, :data) ? _require_key(proof, :data, "psd_proof") : proof
    _require_object(data, "psd_proof.data")

    if method_string == RATIONAL_PSD_METHOD
        minors_value = _require_key(data, :principal_minors, "psd_proof.data")
        _require_array(minors_value, "psd_proof.data.principal_minors")
        minors = [_parse_principal_minor(entry, i, expected_size,
                                         "psd_proof.data.principal_minors")
                  for (i, entry) in enumerate(minors_value)]
        return RationalPSDProof(Symbol(RATIONAL_PSD_METHOD), matrix, minors)
    elseif method_string == SCHUR_ZERO_PSD_METHOD
        schur_zero = _parse_rational_schur_zero_proof(data, expected_size)
        return RationalPSDProof(Symbol(SCHUR_ZERO_PSD_METHOD), matrix,
                                PrincipalMinorProof{Rational{BigInt}}[],
                                schur_zero, nothing)
    elseif method_string == LDL_PSD_METHOD
        ldl = _parse_rational_ldl_proof(data, expected_size; sequential=true)
        return RationalPSDProof(Symbol(LDL_PSD_METHOD), matrix,
                                PrincipalMinorProof{Rational{BigInt}}[],
                                nothing, ldl)
    elseif method_string == PIVOTED_LDL_PSD_METHOD
        ldl = _parse_rational_ldl_proof(data, expected_size; sequential=false)
        return RationalPSDProof(Symbol(PIVOTED_LDL_PSD_METHOD), matrix,
                                PrincipalMinorProof{Rational{BigInt}}[],
                                nothing, ldl)
    end

    throw(ArgumentError("psd_proof.method must be `$RATIONAL_PSD_METHOD`, `$SCHUR_ZERO_PSD_METHOD`, `$LDL_PSD_METHOD`, or `$PIVOTED_LDL_PSD_METHOD`; got `$method_string`"))
end

function _parse_block_rational_psd_proof(proof,
                                         block_sizes_value::AbstractVector{<:Integer})
    _require_object(proof, "psd_proof")
    _require_value(proof, :method, BLOCKWISE_PSD_METHOD, "psd_proof.method")
    blocks_value = _require_key(proof, :blocks, "psd_proof")
    _require_array(blocks_value, "psd_proof.blocks")
    length(blocks_value) == length(block_sizes_value) ||
        throw(ArgumentError("psd_proof.blocks has length $(length(blocks_value)); expected $(length(block_sizes_value))"))

    block_proofs = RationalPSDProof[]
    for (i, block_entry) in enumerate(blocks_value)
        path = "psd_proof.blocks[$i]"
        _require_object(block_entry, path)
        block_index = _require_integer(block_entry, :block_index, "$path.block_index")
        block_index == i ||
            throw(ArgumentError("$path.block_index must be $i; got $block_index"))
        push!(block_proofs,
              _parse_rational_psd_proof(block_entry, Int(block_sizes_value[i])))
    end
    return BlockRationalPSDProof(block_proofs)
end

function _parse_principal_minor(entry, i::Integer, matrix_size_value::Integer,
                                base_path::AbstractString="psd_proof.principal_minors")
    path = "$base_path[$i]"
    _require_object(entry, path)

    indices_value = _require_key(entry, :indices, path)
    _require_array(indices_value, "$path.indices")
    isempty(indices_value) && throw(ArgumentError("$path.indices must not be empty"))

    indices = Int[]
    for (j, index_value) in enumerate(indices_value)
        index_value isa Integer ||
            throw(ArgumentError("$path.indices[$j] must be an integer"))
        index = Int(index_value)
        1 <= index <= matrix_size_value ||
            throw(ArgumentError("$path.indices[$j] is out of range for matrix size $matrix_size_value"))
        push!(indices, index)
    end
    issorted(indices) || throw(ArgumentError("$path.indices must be sorted"))
    length(unique(indices)) == length(indices) ||
        throw(ArgumentError("$path.indices must be unique"))

    determinant = _parse_rational_string(_require_key(entry, :determinant, path),
                                         "$path.determinant")
    return PrincipalMinorProof(indices, determinant)
end

function _parse_rational_schur_zero_proof(proof, expected_size::Integer)
    pivot_value = _require_key(proof, :pivot_block, "psd_proof.data")
    pivots = _validate_pivot_block(pivot_value, expected_size)

    positive_block = _require_key(proof, :positive_block, "psd_proof.data")
    _require_object(positive_block, "psd_proof.data.positive_block")
    positive_indices = _validate_pivot_block(_require_key(positive_block, :indices,
                                                          "psd_proof.data.positive_block"),
                                             expected_size)
    positive_indices == pivots ||
        throw(ArgumentError("psd_proof.data.positive_block.indices must match psd_proof.data.pivot_block"))
    _require_value(positive_block, :proof, "sylvester_principal_minors_positive",
                   "psd_proof.data.positive_block.proof")

    minors_value = _require_key(positive_block, :leading_principal_minors,
                                "psd_proof.data.positive_block")
    _require_array(minors_value,
                   "psd_proof.data.positive_block.leading_principal_minors")
    length(minors_value) == length(pivots) ||
        throw(ArgumentError("psd_proof.data.positive_block.leading_principal_minors has length $(length(minors_value)); expected $(length(pivots))"))
    minors = [_parse_principal_minor(entry, i, expected_size,
                                     "psd_proof.data.positive_block.leading_principal_minors")
              for (i, entry) in enumerate(minors_value)]
    for (i, minor) in enumerate(minors)
        expected_indices = pivots[1:i]
        minor.indices == expected_indices ||
            throw(ArgumentError("psd_proof.data.positive_block.leading_principal_minors[$i].indices must be $(expected_indices); got $(minor.indices)"))
    end

    schur_value = _require_key(proof, :schur_complement, "psd_proof.data")
    _require_object(schur_value, "psd_proof.data.schur_complement")
    _require_value(schur_value, :status, "zero",
                   "psd_proof.data.schur_complement.status")
    expected_schur_size = expected_size - length(pivots)
    schur = _parse_rational_rectangular_matrix(_require_key(schur_value, :entries,
                                                            "psd_proof.data.schur_complement"),
                                               expected_schur_size,
                                               expected_schur_size,
                                               "psd_proof.data.schur_complement.entries")
    return SchurZeroProof{Rational{BigInt}}(pivots, minors, schur)
end

function _parse_rational_ldl_proof(proof, expected_size::Integer; sequential::Bool=true)
    pivots_value = _require_key(proof, :pivots, "psd_proof.data")
    _require_array(pivots_value, "psd_proof.data.pivots")
    length(pivots_value) == expected_size ||
        throw(ArgumentError("psd_proof.data.pivots has length $(length(pivots_value)); expected $expected_size"))
    pivots = LDLPivotProof{Rational{BigInt}}[]
    for (i, pivot_value) in enumerate(pivots_value)
        path = "psd_proof.data.pivots[$i]"
        _require_object(pivot_value, path)
        index = _require_integer(pivot_value, :index, "$path.index")
        if sequential
            index == i || throw(ArgumentError("$path.index must be $i; got $index"))
        else
            1 <= index <= expected_size ||
                throw(ArgumentError("$path.index is out of range for matrix size $expected_size"))
        end
        value = _parse_rational_string(_require_key(pivot_value, :value, path),
                                       "$path.value")
        sign = Symbol(_require_string(pivot_value, :sign, "$path.sign"))
        push!(pivots, LDLPivotProof(index, value, sign))
    end
    sequential || length(unique(pivot.index for pivot in pivots)) == expected_size ||
        throw(ArgumentError("psd_proof.data.pivots must contain each pivot index exactly once"))
    return LDLProof(pivots)
end

function _parse_rational_rectangular_matrix(value, expected_rows::Integer,
                                            expected_cols::Integer,
                                            path::AbstractString)
    _require_array(value, path)
    length(value) == expected_rows ||
        throw(ArgumentError("$path has $(length(value)) rows; expected $expected_rows"))
    matrix = Matrix{Rational{BigInt}}(undef, expected_rows, expected_cols)
    for (i, row) in enumerate(value)
        row_path = "$path[$i]"
        _require_array(row, row_path)
        length(row) == expected_cols ||
            throw(ArgumentError("$row_path has $(length(row)) entries; expected $expected_cols"))
        for (j, entry) in enumerate(row)
            matrix[i, j] = _parse_rational_string(entry, "$row_path[$j]")
        end
    end
    return matrix
end

"""
    verify(cert::RationalCertificate; io=nothing) -> Bool

Verify a Type R rational certificate by recomputing its hash, substitution,
principal minors, and exact rational PSD condition.
"""
function verify(cert::RationalCertificate; io::Union{Nothing, IO}=nothing,
                cache::Bool=true, cache_object=nothing, strict::Bool=false)
    if strict
        return _strict_verify_certificate_object(certificate_json_v1(cert); io,
                                                 cache, cache_object)
    end
    return _with_verification_cache(; cache, cache_object) do
        return _verify_rational_certificate(cert, io)
    end
end

function verify(cert::BlockRationalCertificate; io::Union{Nothing, IO}=nothing,
                cache::Bool=true, cache_object=nothing, strict::Bool=false)
    if strict
        return _strict_verify_certificate_object(certificate_json_v1(cert); io,
                                                 cache, cache_object)
    end
    return _with_verification_cache(; cache, cache_object) do
        return _verify_block_rational_certificate(cert, io)
    end
end

function verify(path::AbstractString; io::Union{Nothing, IO}=nothing, kwargs...)
    return verify(read_certificate(path); io, kwargs...)
end

function _verify_rational_certificate(cert::RationalCertificate, io::Union{Nothing, IO})
    try
        _check_or_report(io, cert.hash == rational_certificate_hash(cert),
                         "certificate hash matches") || return false
        _check_or_report(io,
                         lmi_problem_hash(cert.problem) ==
                         _canonical_problem_hash_from_certificate(cert),
                         "problem hash matches") || return false

        substituted = substitute(cert.problem, cert.solution)
        _check_or_report(io,
                         rational_matrix(substituted) ==
                         rational_matrix(cert.psd_proof.matrix),
                         "substituted matrix matches rational solution") || return false

        if cert.psd_proof.method === Symbol(RATIONAL_PSD_METHOD)
            expected_proof = _rational_psd_proof_unchecked(substituted)
            _check_or_report(io,
                             _principal_minor_proofs_equal(cert.psd_proof.principal_minors,
                                                           expected_proof.principal_minors),
                             "principal-minor proof matches recomputation") || return false
            _check_or_report(io,
                             all(minor.determinant >= 0
                                 for minor in cert.psd_proof.principal_minors),
                             "all principal minors are nonnegative") || return false
            _check_or_report(io, verify_psd_rational(substituted),
                             "PSD verified over QQ") ||
                return false
        elseif cert.psd_proof.method === Symbol(SCHUR_ZERO_PSD_METHOD)
            _verify_rational_schur_zero_psd(substituted, cert.psd_proof, io) ||
                return false
        elseif cert.psd_proof.method === Symbol(LDL_PSD_METHOD)
            _verify_rational_ldl_psd(substituted, cert.psd_proof, io) || return false
        elseif cert.psd_proof.method === Symbol(PIVOTED_LDL_PSD_METHOD)
            _verify_rational_pivoted_ldl_psd(substituted, cert.psd_proof, io) ||
                return false
        else
            _fail(io, "unknown rational PSD proof method: $(cert.psd_proof.method)")
            return false
        end

        _ok(io, "certificate accepted")
        return true
    catch err
        _fail(io, "certificate verification error: $(sprint(showerror, err))")
        return false
    end
end

function _verify_block_rational_certificate(cert::BlockRationalCertificate,
                                            io::Union{Nothing, IO})
    try
        _check_or_report(io, cert.hash == block_rational_certificate_hash(cert),
                         "certificate hash matches") || return false
        _check_or_report(io,
                         block_lmi_problem_hash(cert.problem) ==
                         _canonical_problem_hash_from_certificate(cert),
                         "problem hash matches") || return false
        _check_or_report(io,
                         length(cert.psd_proof.block_proofs) == num_blocks(cert.problem),
                         "blockwise proof count matches problem blocks") || return false

        substituted_blocks = substitute(cert.problem, cert.solution)
        for (block_index, (substituted, proof)) in
            enumerate(zip(substituted_blocks, cert.psd_proof.block_proofs))
            _verify_rational_psd_proof_for_block(substituted, proof, io;
                                                 block_index) || return false
        end

        _ok(io, "blockwise certificate accepted")
        return true
    catch err
        _fail(io, "blockwise certificate verification error: $(sprint(showerror, err))")
        return false
    end
end

function _canonical_problem_hash_from_certificate(cert::RationalCertificate)
    return _require_string(_canonical_rational_certificate_json(cert).problem, :hash,
                           "problem.hash")
end

function _canonical_problem_hash_from_certificate(cert::BlockRationalCertificate)
    return _require_string(_canonical_block_rational_certificate_json(cert).problem,
                           :hash, "problem.hash")
end

function _verify_rational_psd_proof_for_block(substituted::SymmetricRationalMatrix,
                                              proof::RationalPSDProof,
                                              io::Union{Nothing, IO};
                                              block_index::Integer)
    block_label = "block $(Int(block_index))"
    _check_or_report(io,
                     rational_matrix(substituted) == rational_matrix(proof.matrix),
                     "$block_label substituted matrix matches rational solution") ||
        return false

    if proof.method === Symbol(RATIONAL_PSD_METHOD)
        expected_proof = _rational_psd_proof_unchecked(substituted)
        mismatch = _principal_minor_proof_mismatch(proof.principal_minors,
                                                   expected_proof.principal_minors)
        _check_or_report(io, isnothing(mismatch),
                         isnothing(mismatch) ?
                         "$block_label principal-minor proof matches recomputation" :
                         "$block_label principal_minors minor$mismatch") || return false
        result = _verify_principal_minors_rational_result(rational_matrix(substituted);
                                                          block_index=Int(block_index))
        _check_or_report(io, result.accepted,
                         result.accepted ?
                         "$block_label PSD verified over QQ by principal_minors" :
                         _failure_message(result)) || return false
        return true
    elseif proof.method === Symbol(SCHUR_ZERO_PSD_METHOD)
        _verify_rational_schur_zero_psd(substituted, proof, io;
                                        block_index=Int(block_index)) || return false
        _ok(io, "$block_label PSD verified over QQ by schur_zero")
        return true
    elseif proof.method === Symbol(LDL_PSD_METHOD)
        _verify_rational_ldl_psd(substituted, proof, io;
                                 block_index=Int(block_index)) || return false
        _ok(io, "$block_label PSD verified over QQ by ldl")
        return true
    elseif proof.method === Symbol(PIVOTED_LDL_PSD_METHOD)
        _verify_rational_pivoted_ldl_psd(substituted, proof, io;
                                         block_index=Int(block_index)) || return false
        _ok(io, "$block_label PSD verified over QQ by pivoted_ldl")
        return true
    end

    _fail(io, "$block_label unknown rational PSD proof method: $(proof.method)")
    return false
end

function _principal_minor_proof_mismatch(actual, expected)
    length(actual) == length(expected) ||
        return " count mismatch: expected $(length(expected)), got $(length(actual))"
    for (i, (left, right)) in enumerate(zip(actual, expected))
        if left.indices != right.indices
            return " #$i indices mismatch: expected $(right.indices), got $(left.indices)"
        elseif left.determinant != right.determinant
            return " at indices $(left.indices): expected $(right.determinant), got $(left.determinant)"
        end
    end
    return nothing
end

function _verify_rational_schur_zero_psd(substituted::SymmetricRationalMatrix,
                                         proof::RationalPSDProof,
                                         io::Union{Nothing, IO};
                                         block_index::Union{Nothing, Int}=nothing)
    if isnothing(proof.schur_zero)
        _fail(io, "Schur-zero proof data is missing")
        return false
    end
    entries = rational_matrix(substituted)
    pivots = proof.schur_zero.pivot_block
    positive = _verify_positive_definite_rational_result(entries[pivots, pivots];
                                                         pivot_indices=pivots,
                                                         block_index)
    _check_or_report(io, positive.accepted,
                     positive.accepted ? "Schur-zero pivot block is nonsingular" :
                     _failure_message(positive)) || return false
    expected = _schur_zero_proof_rational_unchecked(substituted,
                                                    proof.schur_zero.pivot_block)
    mismatch = _schur_zero_proof_mismatch(proof.schur_zero, expected)
    _check_or_report(io, isnothing(mismatch),
                     isnothing(mismatch) ? "Schur-zero proof matches recomputation" :
                     mismatch) || return false
    _check_or_report(io,
                     all(minor.determinant > 0
                         for minor in proof.schur_zero.positive_block_minors),
                     "pivot block is certified positive definite") || return false
    _check_or_report(io, all(iszero, proof.schur_zero.schur_complement),
                     "Schur complement is exact zero") || return false
    result = _verify_schur_zero_rational_result(entries, proof.schur_zero.pivot_block;
                                                block_index)
    _check_or_report(io, result.accepted,
                     result.accepted ? "Schur-zero PSD verified over QQ" :
                     _failure_message(result)) || return false
    return true
end

function _verify_rational_ldl_psd(substituted::SymmetricRationalMatrix,
                                  proof::RationalPSDProof,
                                  io::Union{Nothing, IO};
                                  block_index::Union{Nothing, Int}=nothing)
    if isnothing(proof.ldl)
        _fail(io, "LDL proof data is missing")
        return false
    end
    expected_ldl, result = _ldl_rational_proof(rational_matrix(substituted))
    if !result.accepted && !isnothing(block_index)
        result = _with_failure_block(result, block_index)
    end
    _check_or_report(io, result.accepted,
                     result.accepted ? "LDL pivots recomputed" :
                     _failure_message(result)) || return false
    _check_or_report(io, _ldl_proofs_equal(proof.ldl, expected_ldl),
                     "LDL proof matches recomputation") || return false
    _check_or_report(io,
                     all(pivot.sign in (:positive, :zero) &&
                             pivot.value >= 0 for pivot in proof.ldl.pivots),
                     "LDL pivots are nonnegative") || return false
    _check_or_report(io, verify_psd_ldl(substituted), "LDL PSD verified over QQ") ||
        return false
    return true
end

function _verify_rational_pivoted_ldl_psd(substituted::SymmetricRationalMatrix,
                                          proof::RationalPSDProof,
                                          io::Union{Nothing, IO};
                                          block_index::Union{Nothing, Int}=nothing)
    if isnothing(proof.ldl)
        _fail(io, "pivoted LDL proof data is missing")
        return false
    end
    expected_ldl, result = _pivoted_ldl_rational_proof(rational_matrix(substituted))
    if !result.accepted && !isnothing(block_index)
        result = _with_failure_block(result, block_index)
    end
    _check_or_report(io, result.accepted,
                     result.accepted ? "pivoted LDL pivots recomputed" :
                     _failure_message(result)) || return false
    _check_or_report(io, _ldl_proofs_equal(proof.ldl, expected_ldl),
                     "pivoted LDL proof matches recomputation") || return false
    _check_or_report(io,
                     all(pivot.sign in (:positive, :zero) &&
                             pivot.value >= 0 for pivot in proof.ldl.pivots),
                     "pivoted LDL pivots are nonnegative") || return false
    _check_or_report(io, verify_psd_pivoted_ldl(substituted),
                     "pivoted LDL PSD verified over QQ") || return false
    return true
end

function _check_or_report(io::Union{Nothing, IO}, condition::Bool, message::AbstractString)
    condition ? _ok(io, message) : _fail(io, message)
    return condition
end

function _ok(io::Union{Nothing, IO}, message::AbstractString)
    return isnothing(io) || println(io, "[OK] $message")
end

function _fail(io::Union{Nothing, IO}, message::AbstractString)
    return isnothing(io) || println(io, "[FAIL] $message")
end
