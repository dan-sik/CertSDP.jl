const ALGEBRAIC_CERTIFICATE_TYPE = "algebraic_psd_certificate"
const BLOCK_ALGEBRAIC_CERTIFICATE_TYPE = "block_algebraic_psd_certificate"
const ALGEBRAIC_SOLUTION_TYPE = "rur"

"""
    AlgebraicPSDProof(method, matrix, principal_minors[, schur_zero])

Store a Type A algebraic PSD proof. `:principal_minors` uses the principal-minor
fallback proof; `:schur_zero` stores a facial-block proof.
"""
struct AlgebraicPSDProof
    method::Symbol
    matrix::Matrix{AlgebraicElement}
    principal_minors::Vector{PrincipalMinorProof{AlgebraicElement}}
    schur_zero::Union{Nothing, SchurZeroProof{AlgebraicElement}}
    ldl::Union{Nothing, LDLProof{AlgebraicElement}}
end

struct BlockAlgebraicPSDProof
    method::Symbol
    block_proofs::Vector{AlgebraicPSDProof}

    function BlockAlgebraicPSDProof(block_proofs::AbstractVector{AlgebraicPSDProof})
        isempty(block_proofs) &&
            throw(ArgumentError("blockwise algebraic PSD proof needs at least one block proof"))
        return new(Symbol(BLOCKWISE_PSD_METHOD), AlgebraicPSDProof[block_proofs...])
    end
end

function AlgebraicPSDProof(method::Symbol, matrix::Matrix{AlgebraicElement},
                           principal_minors::Vector{PrincipalMinorProof{AlgebraicElement}})
    return AlgebraicPSDProof(method, matrix, principal_minors, nothing, nothing)
end

function AlgebraicPSDProof(method::Symbol, matrix::Matrix{AlgebraicElement},
                           principal_minors::Vector{PrincipalMinorProof{AlgebraicElement}},
                           schur_zero::Union{Nothing, SchurZeroProof{AlgebraicElement}})
    return AlgebraicPSDProof(method, matrix, principal_minors, schur_zero, nothing)
end

"""
    AlgebraicCertificate(problem, root, solution; psd_method=:principal_minors, pivot_block=nothing)

Build a Type A certificate for an exact algebraic LMI solution over one
algebraic root representation.
"""
struct AlgebraicCertificate
    problem::LMIProblem
    root::AlgebraicRoot
    solution::Vector{AlgebraicElement}
    psd_proof::AlgebraicPSDProof
    hash::String
    provenance::Dict{Symbol, Any}
end

struct BlockAlgebraicCertificate
    problem::BlockLMIProblem
    root::AlgebraicRoot
    solution::Vector{AlgebraicElement}
    psd_proof::BlockAlgebraicPSDProof
    hash::String
    provenance::Dict{Symbol, Any}
end

function AlgebraicCertificate(P::LMIProblem, root::AlgebraicRoot, x::AbstractVector;
                              psd_method::Union{Symbol, AbstractString}=Symbol(RATIONAL_PSD_METHOD),
                              pivot_block=nothing,
                              provenance=Dict{Symbol, Any}())
    solution = AlgebraicElement[]
    for (i, value) in enumerate(x)
        element = if value isa AlgebraicElement
            value.root == root ||
                throw(ArgumentError("solution coordinate x$i does not use the certificate root"))
            value
        elseif value isa AbstractString
            AlgebraicElement(root, value)
        elseif value isa Integer || value isa Rational
            AlgebraicElement(root, value)
        else
            throw(ArgumentError("solution coordinate x$i must be an AlgebraicElement, rational string, integer, or rational"))
        end
        push!(solution, element)
    end

    length(solution) == num_variables(P) ||
        throw(DimensionMismatch("certificate solution has length $(length(solution)); expected $(num_variables(P))"))

    proof = algebraic_psd_proof(substitute(P, solution); method=psd_method, pivot_block)
    cert_without_hash = AlgebraicCertificate(P, root, solution, proof, "")
    return AlgebraicCertificate(P, root, solution, proof,
                                algebraic_certificate_hash(cert_without_hash),
                                _certificate_provenance_dict(provenance))
end

function AlgebraicCertificate(P::LMIProblem, x::AbstractVector{<:AlgebraicElement};
                              kwargs...)
    return AlgebraicCertificate(P, _common_algebraic_root(collect(x)), x; kwargs...)
end

function BlockAlgebraicCertificate(P::BlockLMIProblem,
                                   root::AlgebraicRoot,
                                   x::AbstractVector;
                                   psd_method::Union{Symbol, AbstractString}=:auto,
                                   block_pivot_blocks=nothing,
                                   pivot_block=nothing,
                                   provenance=Dict{Symbol, Any}())
    solution = AlgebraicElement[]
    for (i, value) in enumerate(x)
        element = if value isa AlgebraicElement
            value.root == root ||
                throw(ArgumentError("solution coordinate x$i does not use the certificate root"))
            value
        elseif value isa AbstractString
            AlgebraicElement(root, value)
        elseif value isa Integer || value isa Rational
            AlgebraicElement(root, value)
        else
            throw(ArgumentError("solution coordinate x$i must be an AlgebraicElement, rational string, integer, or rational"))
        end
        push!(solution, element)
    end

    length(solution) == num_variables(P) ||
        throw(DimensionMismatch("block algebraic certificate solution has length $(length(solution)); expected $(num_variables(P))"))

    proof = block_algebraic_psd_proof(substitute(P, solution);
                                      method=psd_method,
                                      block_pivot_blocks=isnothing(block_pivot_blocks) ?
                                                         pivot_block :
                                                         block_pivot_blocks)
    cert_without_hash = BlockAlgebraicCertificate(P, root, solution, proof, "",
                                                  Dict{Symbol, Any}())
    return BlockAlgebraicCertificate(P,
                                     root,
                                     solution,
                                     proof,
                                     block_algebraic_certificate_hash(cert_without_hash),
                                     _certificate_provenance_dict(provenance))
end

function BlockAlgebraicCertificate(P::BlockLMIProblem,
                                   x::AbstractVector{<:AlgebraicElement};
                                   kwargs...)
    return BlockAlgebraicCertificate(P, _common_algebraic_root(collect(x)), x;
                                     kwargs...)
end

function AlgebraicCertificate(P::LMIProblem,
                              root::AlgebraicRoot,
                              solution::Vector{AlgebraicElement},
                              proof::AlgebraicPSDProof,
                              hash::AbstractString)
    return AlgebraicCertificate(P, root, solution, proof, String(hash),
                                Dict{Symbol, Any}())
end

function BlockAlgebraicCertificate(P::BlockLMIProblem,
                                   root::AlgebraicRoot,
                                   solution::Vector{AlgebraicElement},
                                   proof::BlockAlgebraicPSDProof,
                                   hash::AbstractString)
    return BlockAlgebraicCertificate(P, root, solution, proof, String(hash),
                                     Dict{Symbol, Any}())
end

function _certificate_provenance_dict(value)
    if value isa Dict{Symbol, Any}
        return copy(value)
    elseif value isa AbstractDict
        return Dict{Symbol, Any}(Symbol(k) => v for (k, v) in value)
    elseif value isa NamedTuple
        return Dict{Symbol, Any}(Symbol(k) => v for (k, v) in pairs(value))
    elseif isnothing(value)
        return Dict{Symbol, Any}()
    end
    throw(ArgumentError("certificate provenance must be a dictionary, NamedTuple, or nothing"))
end

"""
    algebraic_psd_proof(A; method=:principal_minors, pivot_block=nothing) -> AlgebraicPSDProof

Create an exact algebraic PSD proof. Principal minors remain the default
fallback; `method=:schur_zero` requires a `pivot_block`.
"""
function algebraic_psd_proof(A;
                             method::Union{Symbol, AbstractString}=Symbol(RATIONAL_PSD_METHOD),
                             pivot_block=nothing,
                             max_size::Integer=DEFAULT_MAX_PSD_PRINCIPAL_MINOR_SIZE,
                             max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS)
    matrix = _as_psd_algebraic_matrix(A)
    plan = choose_psd_proof(matrix, nothing; method=Symbol(method), pivot_block,
                            max_size, max_refinements)
    plan.status === :accepted ||
        throw(ArgumentError("cannot create an algebraic PSD proof: $(_failure_message(PSDVerificationResult(false, plan.method, plan.failure)))"))
    return _algebraic_psd_proof_from_plan(plan)
end

function _algebraic_psd_proof_unchecked(matrix::AbstractMatrix)
    entries = _as_psd_algebraic_matrix(matrix)
    return AlgebraicPSDProof(Symbol(RATIONAL_PSD_METHOD), entries,
                             _principal_minor_proofs_algebraic(entries))
end

function _algebraic_psd_proof_from_plan(plan::PSDProofPlan)
    plan.status === :accepted ||
        throw(ArgumentError("cannot build algebraic PSD proof from a rejected plan"))
    entries = _as_psd_algebraic_matrix(plan.matrix)

    if plan.method === Symbol(RATIONAL_PSD_METHOD)
        return AlgebraicPSDProof(Symbol(RATIONAL_PSD_METHOD), entries,
                                 PrincipalMinorProof{AlgebraicElement}[plan.principal_minors...])
    elseif plan.method === Symbol(SCHUR_ZERO_PSD_METHOD)
        return AlgebraicPSDProof(Symbol(SCHUR_ZERO_PSD_METHOD), entries,
                                 PrincipalMinorProof{AlgebraicElement}[],
                                 plan.schur_zero, nothing)
    elseif plan.method === Symbol(LDL_PSD_METHOD)
        return AlgebraicPSDProof(Symbol(LDL_PSD_METHOD), entries,
                                 PrincipalMinorProof{AlgebraicElement}[],
                                 nothing, plan.ldl)
    elseif plan.method === Symbol(PIVOTED_LDL_PSD_METHOD)
        return AlgebraicPSDProof(Symbol(PIVOTED_LDL_PSD_METHOD), entries,
                                 PrincipalMinorProof{AlgebraicElement}[],
                                 nothing, plan.ldl)
    end

    throw(ArgumentError("unsupported algebraic PSD proof method $(plan.method)"))
end

function block_algebraic_psd_proof(blocks;
                                   method::Union{Symbol, AbstractString}=:auto,
                                   block_pivot_blocks=nothing,
                                   max_size::Integer=DEFAULT_MAX_PSD_PRINCIPAL_MINOR_SIZE,
                                   max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS)
    block_method = Symbol(method) === Symbol(BLOCKWISE_PSD_METHOD) ? :auto :
                   Symbol(method)
    plan = choose_psd_proof(blocks, nothing; method=:blockwise, block_method,
                            block_pivot_blocks, max_size, max_refinements)
    plan.status === :accepted ||
        throw(ArgumentError("cannot create a blockwise algebraic PSD proof: $(_failure_message(PSDVerificationResult(false, plan.method, plan.failure)))"))
    return _block_algebraic_psd_proof_from_plan(plan)
end

function _block_algebraic_psd_proof_from_plan(plan::PSDProofPlan)
    plan.method === Symbol(BLOCKWISE_PSD_METHOD) ||
        throw(ArgumentError("block algebraic PSD proof requires a blockwise plan"))
    plan.status === :accepted ||
        throw(ArgumentError("cannot build block algebraic PSD proof from a rejected plan"))
    return BlockAlgebraicPSDProof([_algebraic_psd_proof_from_plan(block_plan)
                                   for block_plan in plan.block_plans])
end

"""
    schur_zero_psd_proof(A, pivot_block) -> AlgebraicPSDProof

Create an exact facial-block PSD proof by certifying the pivot block as
positive definite and the Schur complement as exactly zero.
"""
function schur_zero_psd_proof(A, pivot_block;
                              max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS)
    matrix = _as_psd_algebraic_matrix(A)
    verify_psd_schur_zero(matrix, pivot_block; max_refinements) ||
        throw(ArgumentError("cannot create a Schur-zero PSD proof: pivot block is not positive definite or Schur complement is nonzero"))
    return _schur_zero_psd_proof_unchecked(matrix, pivot_block)
end

function _schur_zero_psd_proof_unchecked(matrix::AbstractMatrix, pivot_block)
    entries = _as_psd_algebraic_matrix(matrix)
    schur_zero = _schur_zero_proof_algebraic_unchecked(entries, pivot_block)
    return AlgebraicPSDProof(Symbol(SCHUR_ZERO_PSD_METHOD), entries,
                             PrincipalMinorProof{AlgebraicElement}[], schur_zero,
                             nothing)
end

"""
    algebraic_certificate_hash(cert) -> String

Return the stable SHA-256 hash of a Type A certificate, excluding the top-level
`hash` field itself.
"""
function algebraic_certificate_hash(cert::AlgebraicCertificate)
    canonical = _canonical_algebraic_certificate_json(cert)
    return "sha256:" * bytes2hex(sha256(JSON3.write(canonical)))
end

function block_algebraic_certificate_hash(cert::BlockAlgebraicCertificate)
    canonical = _canonical_block_algebraic_certificate_json(cert)
    return "sha256:" * bytes2hex(sha256(JSON3.write(canonical)))
end

"""
    algebraic_certificate_json(cert) -> NamedTuple

Return the JSON-ready Type A certificate object.
"""
function algebraic_certificate_json(cert::AlgebraicCertificate)
    return merge(_canonical_algebraic_certificate_json(cert), (; hash=cert.hash))
end

function block_algebraic_certificate_json(cert::BlockAlgebraicCertificate)
    return merge(_canonical_block_algebraic_certificate_json(cert), (; hash=cert.hash))
end

"""
    algebraic_certificate_json_string(cert) -> String

Return a pretty-printed JSON representation of `cert`.
"""
function algebraic_certificate_json_string(cert::AlgebraicCertificate)
    io = IOBuffer()
    JSON3.pretty(io, algebraic_certificate_json(cert))
    println(io)
    return String(take!(io))
end

function block_algebraic_certificate_json_string(cert::BlockAlgebraicCertificate)
    io = IOBuffer()
    JSON3.pretty(io, block_algebraic_certificate_json(cert))
    println(io)
    return String(take!(io))
end

function write_certificate(path::AbstractString, cert::AlgebraicCertificate)
    open(path, "w") do io
        return write(io, certificate_json_v1_string(cert))
    end
    return path
end

function write_certificate(path::AbstractString, cert::BlockAlgebraicCertificate)
    open(path, "w") do io
        return write(io, certificate_json_v1_string(cert))
    end
    return path
end

function save_certificate(path::AbstractString, cert::AlgebraicCertificate)
    return write_certificate(path, cert)
end

function save_certificate(path::AbstractString, cert::BlockAlgebraicCertificate)
    return write_certificate(path, cert)
end

function _canonical_algebraic_certificate_json(cert::AlgebraicCertificate)
    coordinates = NamedTuple{Tuple(cert.problem.vars)}(Tuple(algebraic_element_string.(cert.solution)))
    return (;
            certsdp_version=LMI_JSON_VERSION,
            certificate_type=ALGEBRAIC_CERTIFICATE_TYPE,
            problem=merge(_canonical_lmi_problem_json(cert.problem),
                          (; hash=lmi_problem_hash(cert.problem))),
            solution=(;
                      type=ALGEBRAIC_SOLUTION_TYPE,
                      root_symbol="t",
                      minimal_polynomial=string(cert.root.f),
                      root_interval=[_rational_string(cert.root.interval.lower),
                                     _rational_string(cert.root.interval.upper)],
                      coordinates,),
            psd_proof=_algebraic_psd_proof_json(cert.psd_proof),)
end

function _canonical_block_algebraic_certificate_json(cert::BlockAlgebraicCertificate)
    coordinates = NamedTuple{Tuple(cert.problem.vars)}(Tuple(algebraic_element_string.(cert.solution)))
    return (;
            certsdp_version=LMI_JSON_VERSION,
            certificate_type=BLOCK_ALGEBRAIC_CERTIFICATE_TYPE,
            problem=merge(block_lmi_problem_json(cert.problem),
                          (; hash=block_lmi_problem_hash(cert.problem))),
            solution=(;
                      type=ALGEBRAIC_SOLUTION_TYPE,
                      root_symbol="t",
                      minimal_polynomial=string(cert.root.f),
                      root_interval=[_rational_string(cert.root.interval.lower),
                                     _rational_string(cert.root.interval.upper)],
                      coordinates,),
            psd_proof=_block_algebraic_psd_proof_json(cert.psd_proof, cert.problem),)
end

function _algebraic_psd_proof_json(proof::AlgebraicPSDProof)
    base = (;
            method=String(proof.method),
            substituted_matrix=_json_algebraic_matrix(proof.matrix),)

    if proof.method === Symbol(RATIONAL_PSD_METHOD)
        return merge(base,
                     (;
                      data=(;
                            principal_minors=_algebraic_principal_minors_json(proof.principal_minors),),
                      principal_minors=_algebraic_principal_minors_json(proof.principal_minors),))
    elseif proof.method === Symbol(SCHUR_ZERO_PSD_METHOD)
        isnothing(proof.schur_zero) &&
            throw(ArgumentError("schur_zero proof data is missing"))
        return merge(base,
                     (;
                      data=(;
                            pivot_block=proof.schur_zero.pivot_block,
                            positive_block=(;
                                            indices=proof.schur_zero.pivot_block,
                                            proof="sylvester_principal_minors_positive",
                                            leading_principal_minors=_algebraic_principal_minors_json(proof.schur_zero.positive_block_minors),),
                            schur_complement=(;
                                              status="zero",
                                              entries=_json_algebraic_matrix(proof.schur_zero.schur_complement),),),
                      pivot_block=proof.schur_zero.pivot_block,
                      positive_block=(;
                                      indices=proof.schur_zero.pivot_block,
                                      proof="sylvester_principal_minors_positive",
                                      leading_principal_minors=_algebraic_principal_minors_json(proof.schur_zero.positive_block_minors),),
                      schur_complement=(;
                                        status="zero",
                                        entries=_json_algebraic_matrix(proof.schur_zero.schur_complement),),))
    elseif proof.method === Symbol(LDL_PSD_METHOD) ||
           proof.method === Symbol(PIVOTED_LDL_PSD_METHOD)
        isnothing(proof.ldl) && throw(ArgumentError("LDL proof data is missing"))
        return merge(base,
                     (;
                      data=(;
                            pivots=[(;
                                     index=pivot.index,
                                     value=algebraic_element_string(pivot.value),
                                     sign=String(pivot.sign),)
                                    for pivot in proof.ldl.pivots],),))
    end

    throw(ArgumentError("unknown algebraic PSD proof method: $(proof.method)"))
end

function _block_algebraic_psd_proof_json(proof::BlockAlgebraicPSDProof,
                                         problem::BlockLMIProblem)
    length(proof.block_proofs) == num_blocks(problem) ||
        throw(ArgumentError("blockwise proof has $(length(proof.block_proofs)) blocks; expected $(num_blocks(problem))"))
    return (;
            method=String(proof.method),
            blocks=[merge(_algebraic_psd_proof_json(block_proof),
                          (;
                           block_index=i,
                           block_kind=String(problem.block_kinds[i]),
                           matrix_size=matrix_size(problem.blocks[i]),))
                    for (i, block_proof) in enumerate(proof.block_proofs)],)
end

function _algebraic_principal_minors_json(minors)
    return [(;
             indices=minor.indices,
             determinant=algebraic_element_string(minor.determinant),)
            for minor in minors]
end

function _json_algebraic_matrix(matrix::AbstractMatrix{AlgebraicElement})
    return [[algebraic_element_string(matrix[i, j]) for j in axes(matrix, 2)]
            for i in axes(matrix, 1)]
end

function _parse_algebraic_certificate_object(parsed)
    problem = _parse_lmi_problem_object(_require_key(parsed, :problem, "root"))
    solution_object = _require_key(parsed, :solution, "root")
    root, solution = _parse_algebraic_solution(solution_object, problem)
    proof = _parse_algebraic_psd_proof(_require_key(parsed, :psd_proof, "root"),
                                       matrix_size(problem), root)
    hash = _require_string(parsed, :hash, "root.hash")

    return AlgebraicCertificate(problem, root, solution, proof, hash)
end

function _parse_block_algebraic_certificate_object(parsed)
    problem = _parse_block_lmi_problem_object(_require_key(parsed, :problem, "root"))
    solution_object = _require_key(parsed, :solution, "root")
    root, solution = _parse_block_algebraic_solution(solution_object, problem)
    proof = _parse_block_algebraic_psd_proof(_require_key(parsed, :psd_proof, "root"),
                                             block_sizes(problem), root)
    hash = _require_string(parsed, :hash, "root.hash")
    return BlockAlgebraicCertificate(problem, root, solution, proof, hash)
end

function _parse_algebraic_solution(solution, problem::LMIProblem)
    _require_object(solution, "solution")
    _require_value(solution, :type, ALGEBRAIC_SOLUTION_TYPE, "solution.type")

    if haskey(solution, :root_symbol)
        root_symbol = _require_string(solution, :root_symbol, "solution.root_symbol")
        root_symbol == "t" ||
            throw(ArgumentError("solution.root_symbol must currently be `t`; got `$root_symbol`"))
    end

    f = parse_polynomial(_require_string(solution, :minimal_polynomial,
                                         "solution.minimal_polynomial"))
    interval_value = _require_key(solution, :root_interval, "solution")
    _require_array(interval_value, "solution.root_interval")
    length(interval_value) == 2 ||
        throw(ArgumentError("solution.root_interval must contain exactly two rational endpoints"))
    root = AlgebraicRoot(f,
                         RationalInterval(_parse_rational_string(interval_value[1],
                                                                 "solution.root_interval[1]"),
                                          _parse_rational_string(interval_value[2],
                                                                 "solution.root_interval[2]")))

    coordinates = _require_key(solution, :coordinates, "solution")
    _require_object(coordinates, "solution.coordinates")

    values = AlgebraicElement[]
    for var in problem.vars
        key = Symbol(String(var))
        haskey(coordinates, key) ||
            throw(ArgumentError("solution.coordinates is missing variable `$(String(var))`"))
        value = _require_string(coordinates, key, "solution.coordinates.$(String(var))")
        push!(values, AlgebraicElement(root, value))
    end

    return root, values
end

function _parse_block_algebraic_solution(solution, problem::BlockLMIProblem)
    _require_object(solution, "solution")
    _require_value(solution, :type, ALGEBRAIC_SOLUTION_TYPE, "solution.type")

    if haskey(solution, :root_symbol)
        root_symbol = _require_string(solution, :root_symbol, "solution.root_symbol")
        root_symbol == "t" ||
            throw(ArgumentError("solution.root_symbol must currently be `t`; got `$root_symbol`"))
    end

    f = parse_polynomial(_require_string(solution, :minimal_polynomial,
                                         "solution.minimal_polynomial"))
    interval_value = _require_key(solution, :root_interval, "solution")
    _require_array(interval_value, "solution.root_interval")
    length(interval_value) == 2 ||
        throw(ArgumentError("solution.root_interval must contain exactly two rational endpoints"))
    root = AlgebraicRoot(f,
                         RationalInterval(_parse_rational_string(interval_value[1],
                                                                 "solution.root_interval[1]"),
                                          _parse_rational_string(interval_value[2],
                                                                 "solution.root_interval[2]")))
    coordinates = _require_key(solution, :coordinates, "solution")
    _require_object(coordinates, "solution.coordinates")
    values = AlgebraicElement[]
    for var in problem.vars
        key = Symbol(String(var))
        haskey(coordinates, key) ||
            throw(ArgumentError("solution.coordinates is missing variable `$(String(var))`"))
        value = _require_string(coordinates, key, "solution.coordinates.$(String(var))")
        push!(values, AlgebraicElement(root, value))
    end
    return root, values
end

function _parse_algebraic_psd_proof(proof, expected_size::Integer, root::AlgebraicRoot)
    _require_object(proof, "psd_proof")
    method_string = _require_string(proof, :method, "psd_proof.method")

    matrix = _parse_algebraic_matrix(_require_key(proof, :substituted_matrix, "psd_proof"),
                                     expected_size,
                                     root,
                                     "psd_proof.substituted_matrix")
    data = haskey(proof, :data) ? _require_key(proof, :data, "psd_proof") : proof
    _require_object(data, "psd_proof.data")

    if method_string == RATIONAL_PSD_METHOD
        minors_value = _require_key(data, :principal_minors, "psd_proof.data")
        _require_array(minors_value, "psd_proof.data.principal_minors")
        minors = [_parse_algebraic_principal_minor(entry, i, expected_size, root,
                                                   "psd_proof.data.principal_minors")
                  for (i, entry) in enumerate(minors_value)]

        return AlgebraicPSDProof(Symbol(RATIONAL_PSD_METHOD), matrix, minors)
    elseif method_string == SCHUR_ZERO_PSD_METHOD
        schur_zero = _parse_schur_zero_proof(data, expected_size, root)
        return AlgebraicPSDProof(Symbol(SCHUR_ZERO_PSD_METHOD), matrix,
                                 PrincipalMinorProof{AlgebraicElement}[], schur_zero)
    elseif method_string == LDL_PSD_METHOD
        ldl = _parse_algebraic_ldl_proof(data, expected_size, root; sequential=true)
        return AlgebraicPSDProof(Symbol(LDL_PSD_METHOD), matrix,
                                 PrincipalMinorProof{AlgebraicElement}[], nothing,
                                 ldl)
    elseif method_string == PIVOTED_LDL_PSD_METHOD
        ldl = _parse_algebraic_ldl_proof(data, expected_size, root; sequential=false)
        return AlgebraicPSDProof(Symbol(PIVOTED_LDL_PSD_METHOD), matrix,
                                 PrincipalMinorProof{AlgebraicElement}[], nothing,
                                 ldl)
    end

    throw(ArgumentError("psd_proof.method must be `$RATIONAL_PSD_METHOD`, `$SCHUR_ZERO_PSD_METHOD`, `$LDL_PSD_METHOD`, or `$PIVOTED_LDL_PSD_METHOD`; got `$method_string`"))
end

function _parse_block_algebraic_psd_proof(proof,
                                          block_sizes_value::AbstractVector{<:Integer},
                                          root::AlgebraicRoot)
    _require_object(proof, "psd_proof")
    _require_value(proof, :method, BLOCKWISE_PSD_METHOD, "psd_proof.method")
    blocks_value = _require_key(proof, :blocks, "psd_proof")
    _require_array(blocks_value, "psd_proof.blocks")
    length(blocks_value) == length(block_sizes_value) ||
        throw(ArgumentError("psd_proof.blocks has length $(length(blocks_value)); expected $(length(block_sizes_value))"))

    block_proofs = AlgebraicPSDProof[]
    for (i, block_entry) in enumerate(blocks_value)
        path = "psd_proof.blocks[$i]"
        _require_object(block_entry, path)
        block_index = _require_integer(block_entry, :block_index, "$path.block_index")
        block_index == i ||
            throw(ArgumentError("$path.block_index must be $i; got $block_index"))
        push!(block_proofs,
              _parse_algebraic_psd_proof(block_entry, Int(block_sizes_value[i]),
                                         root))
    end
    return BlockAlgebraicPSDProof(block_proofs)
end

function _parse_algebraic_matrix(value, expected_size::Integer, root::AlgebraicRoot,
                                 path::AbstractString)
    matrix = _parse_algebraic_rectangular_matrix(value, expected_size, expected_size, root,
                                                 path)
    _check_algebraic_symmetric(matrix; name=Symbol(path))
    return matrix
end

function _parse_algebraic_rectangular_matrix(value, expected_rows::Integer,
                                             expected_cols::Integer, root::AlgebraicRoot,
                                             path::AbstractString)
    _require_array(value, path)
    length(value) == expected_rows ||
        throw(ArgumentError("$path has $(length(value)) rows; expected $expected_rows"))

    matrix = Matrix{AlgebraicElement}(undef, expected_rows, expected_cols)
    for (i, row) in enumerate(value)
        row_path = "$path[$i]"
        _require_array(row, row_path)
        length(row) == expected_cols ||
            throw(ArgumentError("$row_path has $(length(row)) entries; expected $expected_cols"))
        for (j, entry) in enumerate(row)
            entry isa AbstractString ||
                throw(ArgumentError("$row_path[$j] must be an algebraic rational-function string"))
            matrix[i, j] = AlgebraicElement(root, entry)
        end
    end

    return matrix
end

function _parse_algebraic_principal_minor(entry, i::Integer, matrix_size_value::Integer,
                                          root::AlgebraicRoot,
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

    determinant = AlgebraicElement(root,
                                   _require_string(entry, :determinant,
                                                   "$path.determinant"))
    return PrincipalMinorProof(indices, determinant)
end

function _parse_schur_zero_proof(proof, expected_size::Integer, root::AlgebraicRoot)
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
    minors = [_parse_algebraic_principal_minor(entry, i, expected_size, root,
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
    schur = _parse_algebraic_rectangular_matrix(_require_key(schur_value, :entries,
                                                             "psd_proof.data.schur_complement"),
                                                expected_schur_size,
                                                expected_schur_size,
                                                root,
                                                "psd_proof.data.schur_complement.entries")

    return SchurZeroProof{AlgebraicElement}(pivots, minors, schur)
end

function _parse_algebraic_ldl_proof(proof, expected_size::Integer,
                                    root::AlgebraicRoot; sequential::Bool=true)
    pivots_value = _require_key(proof, :pivots, "psd_proof.data")
    _require_array(pivots_value, "psd_proof.data.pivots")
    length(pivots_value) == expected_size ||
        throw(ArgumentError("psd_proof.data.pivots has length $(length(pivots_value)); expected $expected_size"))
    pivots = LDLPivotProof{AlgebraicElement}[]
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
        value = AlgebraicElement(root, _require_string(pivot_value, :value,
                                                       "$path.value"))
        sign = Symbol(_require_string(pivot_value, :sign, "$path.sign"))
        push!(pivots, LDLPivotProof(index, value, sign))
    end
    sequential || length(unique(pivot.index for pivot in pivots)) == expected_size ||
        throw(ArgumentError("psd_proof.data.pivots must contain each pivot index exactly once"))
    return LDLProof(pivots)
end

"""
    verify(cert::AlgebraicCertificate; io=nothing) -> Bool

Verify a Type A algebraic certificate by recomputing its hash, substitution,
principal minors, and certified algebraic PSD condition.
"""
function verify(cert::AlgebraicCertificate; io::Union{Nothing, IO}=nothing,
                cache::Bool=true, cache_object=nothing, strict::Bool=false)
    if strict
        return _strict_verify_certificate_object(certificate_json_v1(cert); io,
                                                 cache, cache_object)
    end
    return _with_verification_cache(; cache, cache_object) do
        return _verify_algebraic_certificate(cert, io)
    end
end

function verify(cert::BlockAlgebraicCertificate; io::Union{Nothing, IO}=nothing,
                cache::Bool=true, cache_object=nothing, strict::Bool=false)
    if strict
        return _strict_verify_certificate_object(certificate_json_v1(cert); io,
                                                 cache, cache_object)
    end
    return _with_verification_cache(; cache, cache_object) do
        return _verify_block_algebraic_certificate(cert, io)
    end
end

function _verify_algebraic_certificate(cert::AlgebraicCertificate, io::Union{Nothing, IO})
    try
        _check_or_report(io, cert.hash == algebraic_certificate_hash(cert),
                         "certificate hash matches") || return false
        _check_or_report(io,
                         lmi_problem_hash(cert.problem) ==
                         _canonical_problem_hash_from_certificate(cert),
                         "problem hash matches") || return false
        _check_or_report(io, _algebraic_root_interval_verified(cert.root),
                         "algebraic root interval isolates one real root") || return false
        _check_or_report(io, all(value.root == cert.root for value in cert.solution),
                         "algebraic solution uses one root representation") || return false

        substituted = substitute(cert.problem, cert.solution)
        _check_or_report(io, _algebraic_matrices_equal(substituted, cert.psd_proof.matrix),
                         "substituted matrix matches algebraic solution") || return false

        if cert.psd_proof.method === Symbol(RATIONAL_PSD_METHOD)
            _verify_algebraic_principal_minor_psd(substituted, cert.psd_proof, io) ||
                return false
        elseif cert.psd_proof.method === Symbol(SCHUR_ZERO_PSD_METHOD)
            _verify_algebraic_schur_zero_psd(substituted, cert.psd_proof, io) ||
                return false
        elseif cert.psd_proof.method === Symbol(LDL_PSD_METHOD)
            _verify_algebraic_ldl_psd(substituted, cert.psd_proof, io) || return false
        elseif cert.psd_proof.method === Symbol(PIVOTED_LDL_PSD_METHOD)
            _verify_algebraic_pivoted_ldl_psd(substituted, cert.psd_proof, io) ||
                return false
        else
            _fail(io, "unknown algebraic PSD proof method: $(cert.psd_proof.method)")
            return false
        end

        _ok(io, "certificate accepted")
        return true
    catch err
        _fail(io, "certificate verification error: $(sprint(showerror, err))")
        return false
    end
end

function _verify_block_algebraic_certificate(cert::BlockAlgebraicCertificate,
                                             io::Union{Nothing, IO})
    try
        _check_or_report(io, cert.hash == block_algebraic_certificate_hash(cert),
                         "certificate hash matches") || return false
        _check_or_report(io,
                         block_lmi_problem_hash(cert.problem) ==
                         _canonical_problem_hash_from_certificate(cert),
                         "problem hash matches") || return false
        _check_or_report(io, _algebraic_root_interval_verified(cert.root),
                         "algebraic root interval isolates one real root") || return false
        _check_or_report(io, all(value.root == cert.root for value in cert.solution),
                         "algebraic solution uses one root representation") || return false
        _check_or_report(io,
                         length(cert.psd_proof.block_proofs) == num_blocks(cert.problem),
                         "blockwise proof count matches problem blocks") || return false

        substituted_blocks = substitute(cert.problem, cert.solution)
        for (block_index, (substituted, proof)) in
            enumerate(zip(substituted_blocks, cert.psd_proof.block_proofs))
            _verify_algebraic_psd_proof_for_block(substituted, proof, io;
                                                  block_index) || return false
        end

        _ok(io, "blockwise algebraic certificate accepted")
        return true
    catch err
        _fail(io,
              "blockwise algebraic certificate verification error: $(sprint(showerror, err))")
        return false
    end
end

function _canonical_problem_hash_from_certificate(cert::AlgebraicCertificate)
    return _require_string(_canonical_algebraic_certificate_json(cert).problem, :hash,
                           "problem.hash")
end

function _canonical_problem_hash_from_certificate(cert::BlockAlgebraicCertificate)
    return _require_string(_canonical_block_algebraic_certificate_json(cert).problem,
                           :hash, "problem.hash")
end

function _algebraic_root_interval_verified(root::AlgebraicRoot)
    return isnothing(_refinable_root_interval_error(root))
end

function _algebraic_matrices_equal(a::AbstractMatrix{AlgebraicElement},
                                   b::AbstractMatrix{AlgebraicElement})
    size(a) == size(b) || return false
    for index in eachindex(a, b)
        a[index] == b[index] || return false
    end
    return true
end

function _principal_minor_proofs_equal(a::Vector, b::Vector)
    length(a) == length(b) || return false
    for (left, right) in zip(a, b)
        left.indices == right.indices || return false
        left.determinant == right.determinant || return false
    end
    return true
end

function _algebraic_nonnegative(value::AlgebraicElement)
    sign = certified_sign(value)
    return sign === :zero || sign === :positive
end

function _algebraic_positive(value::AlgebraicElement)
    return certified_sign(value) === :positive
end

function _verify_algebraic_principal_minor_psd(substituted::AbstractMatrix{AlgebraicElement},
                                               proof::AlgebraicPSDProof,
                                               io::Union{Nothing, IO})
    expected_proof = _algebraic_psd_proof_unchecked(substituted)
    _check_or_report(io,
                     _principal_minor_proofs_equal(proof.principal_minors,
                                                   expected_proof.principal_minors),
                     "principal-minor proof matches recomputation") || return false
    _check_or_report(io,
                     all(_algebraic_nonnegative(minor.determinant)
                         for minor in proof.principal_minors),
                     "all principal minors are certified nonnegative") || return false
    _check_or_report(io, verify_psd_algebraic(substituted),
                     "PSD verified over QQ(alpha)") || return false
    return true
end

function _verify_algebraic_psd_proof_for_block(substituted::AbstractMatrix{AlgebraicElement},
                                               proof::AlgebraicPSDProof,
                                               io::Union{Nothing, IO};
                                               block_index::Integer)
    block_label = "block $(Int(block_index))"
    _check_or_report(io, _algebraic_matrices_equal(substituted, proof.matrix),
                     "$block_label substituted matrix matches algebraic solution") ||
        return false

    if proof.method === Symbol(RATIONAL_PSD_METHOD)
        expected_proof = _algebraic_psd_proof_unchecked(substituted)
        mismatch = _principal_minor_proof_mismatch(proof.principal_minors,
                                                   expected_proof.principal_minors)
        _check_or_report(io, isnothing(mismatch),
                         isnothing(mismatch) ?
                         "$block_label principal-minor proof matches recomputation" :
                         "$block_label principal_minors minor$mismatch") || return false
        result = _verify_principal_minors_algebraic_result(substituted;
                                                           block_index=Int(block_index))
        _check_or_report(io, result.accepted,
                         result.accepted ?
                         "$block_label PSD verified over QQ(alpha) by principal_minors" :
                         _failure_message(result)) || return false
        return true
    elseif proof.method === Symbol(SCHUR_ZERO_PSD_METHOD)
        _verify_algebraic_schur_zero_psd(substituted, proof, io) || return false
        _ok(io, "$block_label PSD verified over QQ(alpha) by schur_zero")
        return true
    elseif proof.method === Symbol(LDL_PSD_METHOD)
        _verify_algebraic_ldl_psd(substituted, proof, io) || return false
        _ok(io, "$block_label PSD verified over QQ(alpha) by ldl")
        return true
    elseif proof.method === Symbol(PIVOTED_LDL_PSD_METHOD)
        _verify_algebraic_pivoted_ldl_psd(substituted, proof, io) || return false
        _ok(io, "$block_label PSD verified over QQ(alpha) by pivoted_ldl")
        return true
    end

    _fail(io, "$block_label unknown algebraic PSD proof method: $(proof.method)")
    return false
end

function _verify_algebraic_schur_zero_psd(substituted::AbstractMatrix{AlgebraicElement},
                                          proof::AlgebraicPSDProof, io::Union{Nothing, IO})
    if isnothing(proof.schur_zero)
        _fail(io, "Schur-zero proof data is missing")
        return false
    end

    pivots = proof.schur_zero.pivot_block
    positive = _verify_positive_definite_algebraic_result(substituted[pivots, pivots];
                                                          pivot_indices=pivots)
    _check_or_report(io, positive.accepted,
                     positive.accepted ? "Schur-zero pivot block is nonsingular" :
                     _failure_message(positive)) || return false

    expected_schur = _schur_zero_proof_algebraic_unchecked(substituted,
                                                           proof.schur_zero.pivot_block)
    mismatch = _schur_zero_proof_mismatch(proof.schur_zero, expected_schur)
    _check_or_report(io, isnothing(mismatch),
                     isnothing(mismatch) ? "Schur-zero proof matches recomputation" :
                     mismatch) || return false
    _check_or_report(io,
                     all(_algebraic_positive(minor.determinant)
                         for minor in proof.schur_zero.positive_block_minors),
                     "pivot block is certified positive definite") || return false
    _check_or_report(io, _iszero_algebraic_matrix(proof.schur_zero.schur_complement),
                     "Schur complement is exact zero") || return false
    _check_or_report(io, verify_psd_schur_zero(substituted, proof.schur_zero.pivot_block),
                     "Schur-zero PSD verified over QQ(alpha)") || return false
    return true
end

function _verify_algebraic_ldl_psd(substituted::AbstractMatrix{AlgebraicElement},
                                   proof::AlgebraicPSDProof,
                                   io::Union{Nothing, IO})
    if isnothing(proof.ldl)
        _fail(io, "LDL proof data is missing")
        return false
    end
    expected_ldl, result = _ldl_algebraic_proof(substituted)
    _check_or_report(io, result.accepted,
                     result.accepted ? "LDL pivots recomputed" :
                     _failure_message(result)) || return false
    _check_or_report(io, _ldl_proofs_equal(proof.ldl, expected_ldl),
                     "LDL proof matches recomputation") || return false
    _check_or_report(io,
                     all(pivot.sign in (:positive, :zero) &&
                             _algebraic_nonnegative(pivot.value)
                         for pivot in proof.ldl.pivots),
                     "LDL pivots are certified nonnegative") || return false
    _check_or_report(io, verify_psd_ldl(substituted),
                     "LDL PSD verified over QQ(alpha)") || return false
    return true
end

function _verify_algebraic_pivoted_ldl_psd(substituted::AbstractMatrix{AlgebraicElement},
                                           proof::AlgebraicPSDProof,
                                           io::Union{Nothing, IO})
    if isnothing(proof.ldl)
        _fail(io, "pivoted LDL proof data is missing")
        return false
    end
    expected_ldl, result = _pivoted_ldl_algebraic_proof(substituted)
    _check_or_report(io, result.accepted,
                     result.accepted ? "pivoted LDL pivots recomputed" :
                     _failure_message(result)) || return false
    _check_or_report(io, _ldl_proofs_equal(proof.ldl, expected_ldl),
                     "pivoted LDL proof matches recomputation") || return false
    _check_or_report(io,
                     all(pivot.sign in (:positive, :zero) &&
                             _algebraic_nonnegative(pivot.value)
                         for pivot in proof.ldl.pivots),
                     "pivoted LDL pivots are certified nonnegative") || return false
    _check_or_report(io, verify_psd_pivoted_ldl(substituted),
                     "pivoted LDL PSD verified over QQ(alpha)") || return false
    return true
end

function _schur_zero_proofs_equal(a::SchurZeroProof, b::SchurZeroProof)
    return isnothing(_schur_zero_proof_mismatch(a, b))
end

function _schur_zero_proof_mismatch(a::SchurZeroProof, b::SchurZeroProof)
    a.pivot_block == b.pivot_block ||
        return "Schur-zero pivot block matches recomputation"
    _principal_minor_proofs_equal(a.positive_block_minors, b.positive_block_minors) ||
        return "Schur-zero positive-block minors match recomputation"
    _matrix_entries_equal(a.schur_complement, b.schur_complement) ||
        return "Schur-zero Schur complement matches recomputation"
    return nothing
end

function _matrix_entries_equal(a::AbstractMatrix, b::AbstractMatrix)
    size(a) == size(b) || return false
    for index in eachindex(a, b)
        a[index] == b[index] || return false
    end
    return true
end
