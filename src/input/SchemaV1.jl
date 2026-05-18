const SCHEMA_V1_VERSION = "1.0"
const CERTSDP_PROBLEM_VERSION_KEY = :certsdp_problem_version
const CERTSDP_CERTIFICATE_VERSION_KEY = :certsdp_certificate_version
const CERTSDP_FAILURE_REPORT_VERSION_KEY = :certsdp_failure_report_version

"""
    read_problem(path) -> LMIProblem or BlockLMIProblem

Read a public CertSDP problem JSON file or an SDPA sparse file. The public JSON
problem schema is v1.0, while the v0.1 LMI JSON reader remains available as a
compatibility layer. SDPA sparse files are accepted as an input frontend.
"""
function read_problem(path::AbstractString)
    _is_sdpa_path(path) && return read_sdpa(path)
    return parse_problem_json(read(path, String))
end

"""
    write_problem(path, problem)

Write an LMI problem using the public schema v1.0, or SDPA sparse when the path
extension is `.dat-s`, `.dats`, or `.sdpa`.
"""
function write_problem(path::AbstractString, P::LMIProblem)
    _is_sdpa_path(path) && return write_sdpa(P, path)
    open(path, "w") do io
        return write(io, problem_json_v1_string(P))
    end
    return path
end

function write_problem(path::AbstractString, P::BlockLMIProblem)
    _is_sdpa_path(path) && return write_sdpa(P, path)
    open(path, "w") do io
        return write(io, problem_json_v1_string(P))
    end
    return path
end

"""
    parse_problem_json(json_text) -> LMIProblem

Parse either a v1.0 public problem JSON document or a legacy v0.1 LMI wrapper.
"""
function parse_problem_json(json_text::AbstractString)
    parsed = _read_json_document(json_text, "problem")
    _require_object(parsed, "root")

    if haskey(parsed, CERTSDP_PROBLEM_VERSION_KEY)
        return _parse_problem_v1_document(parsed)
    elseif haskey(parsed, :certsdp_version)
        return parse_lmi_json(json_text)
    end

    throw(ArgumentError("problem JSON must contain `certsdp_problem_version` or legacy `certsdp_version`"))
end

"""
    migrate_problem_json(json_text) -> String

Convert a legacy v0.1 LMI problem JSON document to schema v1.0. v1.0 inputs
are parsed and re-emitted in canonical v1.0 form.
"""
function migrate_problem_json(json_text::AbstractString)
    return problem_json_v1_string(parse_problem_json(json_text))
end

"""
    validate_problem_schema(json_text) -> true

Validate the public problem schema v1.0. This is a structural validation plus
the same exact rational/symmetry/hash checks used by the parser.
"""
function validate_problem_schema(json_text::AbstractString)
    parsed = _read_json_document(json_text, "problem")
    _require_object(parsed, "root")
    _require_value(parsed, CERTSDP_PROBLEM_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.certsdp_problem_version")
    _parse_problem_v1_document(parsed)
    return true
end

function validate_block_problem_schema(json_text::AbstractString)
    parsed = _read_json_document(json_text, "block problem")
    _require_object(parsed, "root")
    _require_value(parsed, CERTSDP_PROBLEM_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.certsdp_problem_version")
    P = _parse_block_lmi_problem_v1_document(parsed)
    return P isa BlockLMIProblem
end

function problem_json_v1(P::LMIProblem)
    return (;
            certsdp_problem_version=SCHEMA_V1_VERSION,
            type=LMI_PROBLEM_TYPE,
            field=LMI_FIELD,
            variables=String.(P.vars),
            matrix_size=matrix_size(P),
            A0=_json_matrix(P.A0),
            A=[(;
                var=String(var),
                matrix=_json_matrix(matrix),)
               for (var, matrix) in zip(P.vars, P.A)],
            metadata=(;
                      created_by="CertSDP.jl",
                      schema="problem_v1",),
            hash=lmi_problem_hash(P),)
end

function problem_json_v1(P::BlockLMIProblem)
    return merge((;
                  certsdp_problem_version=SCHEMA_V1_VERSION,),
                 block_lmi_problem_json(P),
                 (;
                  metadata=(;
                            created_by="CertSDP.jl",
                            schema="block_problem_v1",),
                  hash=block_lmi_problem_hash(P),))
end

function problem_json_v1_string(P::Union{LMIProblem, BlockLMIProblem})
    io = IOBuffer()
    JSON3.pretty(io, problem_json_v1(P))
    println(io)
    return String(take!(io))
end

function _parse_problem_v1_document(parsed)
    _require_value(parsed, CERTSDP_PROBLEM_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.certsdp_problem_version")
    type = _require_string(parsed, :type, "root.type")
    if type == LMI_PROBLEM_TYPE
        return _parse_lmi_problem_v1_document(parsed)
    elseif type == SDPA_PROBLEM_TYPE
        return _parse_block_lmi_problem_v1_document(parsed)
    end
    throw(ArgumentError("root.type must be `$LMI_PROBLEM_TYPE` or `$SDPA_PROBLEM_TYPE`; got `$type`"))
end

function _parse_lmi_problem_v1_document(parsed)
    _require_value(parsed, CERTSDP_PROBLEM_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.certsdp_problem_version")
    _require_value(parsed, :type, LMI_PROBLEM_TYPE, "root.type")
    _require_value(parsed, :field, LMI_FIELD, "root.field")

    matrix_size_value = _require_integer(parsed, :matrix_size, "root.matrix_size")
    matrix_size_value > 0 || throw(ArgumentError("root.matrix_size must be positive"))

    variables_value = _require_key(parsed, :variables, "root")
    _require_array(variables_value, "root.variables")
    variables = Symbol[]
    for (i, entry) in enumerate(variables_value)
        entry isa AbstractString ||
            throw(ArgumentError("root.variables[$i] must be a string"))
        isempty(entry) && throw(ArgumentError("root.variables[$i] must not be empty"))
        push!(variables, Symbol(String(entry)))
    end
    length(unique(variables)) == length(variables) ||
        throw(ArgumentError("root.variables must be unique"))

    A0 = _parse_rational_matrix(_require_key(parsed, :A0, "root"), matrix_size_value,
                                "root.A0")
    A_entries = _require_key(parsed, :A, "root")
    _require_array(A_entries, "root.A")
    length(A_entries) == length(variables) ||
        throw(ArgumentError("root.A has length $(length(A_entries)); expected $(length(variables))"))

    matrices = Matrix{Rational{BigInt}}[]
    for (i, entry) in enumerate(A_entries)
        path = "root.A[$i]"
        _require_object(entry, path)
        var_name = _require_string(entry, :var, "$path.var")
        var_name == String(variables[i]) ||
            throw(ArgumentError("$path.var must be `$(String(variables[i]))`; got `$var_name`"))
        push!(matrices,
              _parse_rational_matrix(_require_key(entry, :matrix, path), matrix_size_value,
                                     "$path.matrix"))
    end

    if haskey(parsed, :metadata)
        _require_object(_require_key(parsed, :metadata, "root"), "root.metadata")
    end

    P = try
        LMIProblem(A0, matrices; vars=variables)
    catch err
        throw(ArgumentError("invalid v1.0 LMI problem data: $(sprint(showerror, err))"))
    end

    if haskey(parsed, :hash)
        expected_hash = _require_string(parsed, :hash, "root.hash")
        actual_hash = lmi_problem_hash(P)
        expected_hash == actual_hash ||
            throw(ArgumentError("root.hash mismatch: expected $expected_hash, computed $actual_hash"))
    end

    return P
end

function _parse_block_lmi_problem_v1_document(parsed)
    _require_value(parsed, CERTSDP_PROBLEM_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.certsdp_problem_version")
    return _parse_block_lmi_problem_object(parsed; path="root")
end

"""
    migrate_certificate_json(json_text) -> String

Convert a legacy v0.1 LMI certificate to certificate schema v1.0. v1.0 inputs
are parsed and re-emitted. The v1.0 certificate schema freezes LMI Type R and
Type A/F certificates; SOS Gram certificates remain accepted through the legacy
verifier until the production SOS schema is finalized.
"""
function migrate_certificate_json(json_text::AbstractString)
    cert = parse_certificate_json(json_text)
    return certificate_json_v1_string(cert)
end

"""
    validate_certificate_schema(json_text) -> true

Validate the public LMI certificate schema v1.0. Mathematical acceptance is
still the job of `verify(cert)`.
"""
function validate_certificate_schema(json_text::AbstractString)
    parsed = _read_json_document(json_text, "certificate")
    _require_object(parsed, "root")
    _require_value(parsed, CERTSDP_CERTIFICATE_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.certsdp_certificate_version")
    _parse_certificate_v1_object(parsed)
    return true
end

function certificate_json_v1_string(cert)
    io = IOBuffer()
    JSON3.pretty(io, certificate_json_v1(cert))
    println(io)
    return String(take!(io))
end

function certificate_json_v1(cert::RationalCertificate)
    return _lmi_certificate_v1(cert,
                               RATIONAL_CERTIFICATE_TYPE,
                               (;
                                field=LMI_FIELD,
                                representation="coordinates",
                                coordinates=_rational_solution_coordinates(cert),),
                               _rational_psd_proof_json(cert.psd_proof))
end

function certificate_json_v1(cert::BlockRationalCertificate)
    return (;
            certsdp_certificate_version=SCHEMA_V1_VERSION,
            certificate_type=BLOCK_RATIONAL_CERTIFICATE_TYPE,
            certificate_id=cert.hash,
            problem_hash=block_lmi_problem_hash(cert.problem),
            problem=(;
                     embedded=true,
                     type=SDPA_PROBLEM_TYPE,
                     data=problem_json_v1(cert.problem),),
            solution=(;
                      field=LMI_FIELD,
                      representation="coordinates",
                      coordinates=_block_rational_solution_coordinates(cert),),
            rank_profile=_block_certificate_rank_profile_v1(cert),
            proof=(;
                   linear_constraints=(;
                                       method="exact_substitution",
                                       status="claimed",
                                       blocks=[(;
                                                block_index=i,
                                                status="claimed",)
                                               for i in 1:num_blocks(cert.problem)],),
                   psd=_block_rational_psd_proof_json(cert.psd_proof,
                                                      cert.problem),),
            provenance=(;
                        certsdp_version=string(package_version()),
                        julia_version=string(VERSION),
                        schema_version=SCHEMA_V1_VERSION,),
            verification=(;
                          verifier_version=string(package_version()),
                          verified_at_creation=nothing,),)
end

function certificate_json_v1(cert::BlockAlgebraicCertificate)
    return (;
            certsdp_certificate_version=SCHEMA_V1_VERSION,
            certificate_type=BLOCK_ALGEBRAIC_CERTIFICATE_TYPE,
            certificate_id=cert.hash,
            problem_hash=block_lmi_problem_hash(cert.problem),
            problem=(;
                     embedded=true,
                     type=SDPA_PROBLEM_TYPE,
                     data=problem_json_v1(cert.problem),),
            solution=(;
                      field="QQbar",
                      representation=ALGEBRAIC_SOLUTION_TYPE,
                      root_symbol="t",
                      minimal_polynomial=string(cert.root.f),
                      root_interval=[_rational_string(cert.root.interval.lower),
                                     _rational_string(cert.root.interval.upper)],
                      coordinates=_block_algebraic_solution_coordinates(cert),),
            rank_profile=_block_certificate_rank_profile_v1(cert),
            proof=(;
                   linear_constraints=(;
                                       method="exact_substitution",
                                       status="claimed",
                                       blocks=[(;
                                                block_index=i,
                                                status="claimed",)
                                               for i in 1:num_blocks(cert.problem)],),
                   psd=_block_algebraic_psd_proof_json(cert.psd_proof,
                                                       cert.problem),),
            provenance=_certificate_provenance_v1(cert),
            verification=(;
                          verifier_version=string(package_version()),
                          verified_at_creation=nothing,),)
end

function _block_rational_solution_coordinates(cert::BlockRationalCertificate)
    return NamedTuple{Tuple(cert.problem.vars)}(Tuple(_rational_string.(cert.solution)))
end

function _block_algebraic_solution_coordinates(cert::BlockAlgebraicCertificate)
    return NamedTuple{Tuple(cert.problem.vars)}(Tuple(algebraic_element_string.(cert.solution)))
end

function certificate_json_v1(cert::AlgebraicCertificate)
    return _lmi_certificate_v1(cert,
                               ALGEBRAIC_CERTIFICATE_TYPE,
                               (;
                                field="QQbar",
                                representation=ALGEBRAIC_SOLUTION_TYPE,
                                root_symbol="t",
                                minimal_polynomial=string(cert.root.f),
                                root_interval=[_rational_string(cert.root.interval.lower),
                                               _rational_string(cert.root.interval.upper)],
                                coordinates=_algebraic_solution_coordinates(cert),),
                               _algebraic_psd_proof_json(cert.psd_proof))
end

certificate_json_v1(cert::SOSGramCertificate) = sos_gram_certificate_json(cert)

function _lmi_certificate_v1(cert, certificate_type::AbstractString, solution, psd_proof)
    return (;
            certsdp_certificate_version=SCHEMA_V1_VERSION,
            certificate_type,
            certificate_id=cert.hash,
            problem_hash=lmi_problem_hash(cert.problem),
            problem=(;
                     embedded=true,
                     type=LMI_PROBLEM_TYPE,
                     data=problem_json_v1(cert.problem),),
            solution,
            rank_profile=_certificate_rank_profile_v1(cert),
            proof=(;
                   linear_constraints=(;
                                       method="exact_substitution",
                                       status="claimed",),
                   psd=psd_proof,),
            provenance=_certificate_provenance_v1(cert),
            verification=(;
                          verifier_version=string(package_version()),
                          verified_at_creation=nothing,),)
end

function _certificate_provenance_v1(cert)
    base = Dict{Symbol, Any}(:certsdp_version => string(package_version()),
                             :julia_version => string(VERSION),
                             :schema_version => SCHEMA_V1_VERSION)
    if (cert isa AlgebraicCertificate || cert isa BlockAlgebraicCertificate) &&
       !isempty(cert.provenance)
        for (key, value) in cert.provenance
            base[key] = _provenance_json_value(value)
        end
    end
    return NamedTuple{Tuple(keys(base))}(Tuple(values(base)))
end

function _provenance_json_value(value)
    if value isa AlgebraicBackendProvenance
        return algebraic_backend_provenance_json(value)
    elseif value isa AlgebraicBackendFailure
        return algebraic_backend_failure_json(value)
    elseif value isa AbstractDict
        return Dict(String(key) => _provenance_json_value(val) for (key, val) in value)
    elseif value isa AbstractVector
        return [_provenance_json_value(item) for item in value]
    elseif value isa NamedTuple
        return Dict(String(key) => _provenance_json_value(val)
                    for (key, val) in pairs(value))
    elseif value isa Symbol
        return String(value)
    elseif value isa BigFloat || value isa Rational
        return string(value)
    elseif value isa Integer || value isa AbstractString || value isa Bool ||
           isnothing(value)
        return value
    end
    return string(value)
end

function _rational_solution_coordinates(cert::RationalCertificate)
    return NamedTuple{Tuple(cert.problem.vars)}(Tuple(_rational_string.(cert.solution)))
end

function _algebraic_solution_coordinates(cert::AlgebraicCertificate)
    return NamedTuple{Tuple(cert.problem.vars)}(Tuple(algebraic_element_string.(cert.solution)))
end

function _certificate_rank_profile_v1(cert::RationalCertificate)
    if cert.psd_proof.method === Symbol(SCHUR_ZERO_PSD_METHOD) &&
       !isnothing(cert.psd_proof.schur_zero)
        return (;
                status="recorded",
                method=SCHUR_ZERO_PSD_METHOD,
                rank=length(cert.psd_proof.schur_zero.pivot_block),
                pivot_block=cert.psd_proof.schur_zero.pivot_block,)
    end

    return (;
            status="not_recorded",
            method="not_recorded",
            pivot_block=Int[],)
end

function _block_certificate_rank_profile_v1(cert::BlockRationalCertificate)
    blocks = Any[]
    for (i, proof) in enumerate(cert.psd_proof.block_proofs)
        if proof.method === Symbol(SCHUR_ZERO_PSD_METHOD) && !isnothing(proof.schur_zero)
            push!(blocks,
                  (;
                   block_index=i,
                   status="recorded",
                   method=SCHUR_ZERO_PSD_METHOD,
                   rank=length(proof.schur_zero.pivot_block),
                   pivot_block=proof.schur_zero.pivot_block,))
        elseif proof.method === Symbol(LDL_PSD_METHOD) && !isnothing(proof.ldl)
            positive_rank = count(pivot -> pivot.sign === :positive, proof.ldl.pivots)
            push!(blocks,
                  (;
                   block_index=i,
                   status="recorded",
                   method=LDL_PSD_METHOD,
                   rank=positive_rank,
                   pivot_block=Int[],))
        else
            push!(blocks,
                  (;
                   block_index=i,
                   status="not_recorded",
                   method=String(proof.method),
                   pivot_block=Int[],))
        end
    end
    return (;
            status="blockwise",
            method=BLOCKWISE_PSD_METHOD,
            blocks,)
end

function _block_certificate_rank_profile_v1(cert::BlockAlgebraicCertificate)
    blocks = Any[]
    for (i, proof) in enumerate(cert.psd_proof.block_proofs)
        if proof.method === Symbol(SCHUR_ZERO_PSD_METHOD) && !isnothing(proof.schur_zero)
            push!(blocks,
                  (;
                   block_index=i,
                   status="recorded",
                   method=SCHUR_ZERO_PSD_METHOD,
                   rank=length(proof.schur_zero.pivot_block),
                   pivot_block=proof.schur_zero.pivot_block,))
        elseif (proof.method === Symbol(LDL_PSD_METHOD) ||
                proof.method === Symbol(PIVOTED_LDL_PSD_METHOD)) &&
               !isnothing(proof.ldl)
            positive_rank = count(pivot -> pivot.sign === :positive, proof.ldl.pivots)
            push!(blocks,
                  (;
                   block_index=i,
                   status="recorded",
                   method=String(proof.method),
                   rank=positive_rank,
                   pivot_block=Int[],))
        else
            push!(blocks,
                  (;
                   block_index=i,
                   status="not_recorded",
                   method=String(proof.method),
                   pivot_block=Int[],))
        end
    end
    return (;
            status="blockwise",
            method=BLOCKWISE_PSD_METHOD,
            blocks,)
end

function _certificate_rank_profile_v1(cert::BlockRationalCertificate)
    return _block_certificate_rank_profile_v1(cert)
end

function _certificate_rank_profile_v1(cert::AlgebraicCertificate)
    if cert.psd_proof.method === Symbol(SCHUR_ZERO_PSD_METHOD) &&
       !isnothing(cert.psd_proof.schur_zero)
        return (;
                status="recorded",
                method=SCHUR_ZERO_PSD_METHOD,
                rank=length(cert.psd_proof.schur_zero.pivot_block),
                pivot_block=cert.psd_proof.schur_zero.pivot_block,)
    end

    return (;
            status="not_recorded",
            method="not_recorded",
            pivot_block=Int[],)
end

function _parse_certificate_v1_object(parsed)
    _require_value(parsed, CERTSDP_CERTIFICATE_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.certsdp_certificate_version")
    certificate_type = _require_string(parsed, :certificate_type,
                                       "root.certificate_type")
    if certificate_type == SOS_GRAM_CERTIFICATE_TYPE
        return _parse_sos_gram_certificate_v1_object(parsed)
    elseif certificate_type == ALGEBRAIC_SOS_GRAM_CERTIFICATE_TYPE
        return _parse_algebraic_sos_gram_certificate_v1_object(parsed)
    elseif certificate_type == RATIONAL_FUNCTION_SOS_CERTIFICATE_TYPE ||
           certificate_type == POSITIVSTELLENSATZ_CERTIFICATE_TYPE ||
           certificate_type == PERTURBATION_COMPENSATION_CERTIFICATE_TYPE
        return _parse_positive_certificate_v1_object(parsed, certificate_type)
    end

    certificate_id = _require_string(parsed, :certificate_id, "root.certificate_id")
    _validate_sha256_identifier(certificate_id, "root.certificate_id")

    problem = _parse_certificate_problem_v1(_require_key(parsed, :problem, "root"))
    expected_problem_hash = problem isa BlockLMIProblem ?
                            block_lmi_problem_hash(problem) :
                            lmi_problem_hash(problem)
    supplied_problem_hash = _require_string(parsed, :problem_hash, "root.problem_hash")
    supplied_problem_hash == expected_problem_hash ||
        throw(ArgumentError("root.problem_hash mismatch: expected $supplied_problem_hash, computed $expected_problem_hash"))

    proof = _require_key(parsed, :proof, "root")
    _require_object(proof, "root.proof")
    linear = _require_key(proof, :linear_constraints, "root.proof")
    _require_object(linear, "root.proof.linear_constraints")
    _require_value(linear, :method, "exact_substitution",
                   "root.proof.linear_constraints.method")
    haskey(linear, :status) ||
        throw(ArgumentError("root.proof.linear_constraints is missing required key `status`"))
    psd = _require_key(proof, :psd, "root.proof")

    if haskey(parsed, :rank_profile)
        _require_object(_require_key(parsed, :rank_profile, "root"), "root.rank_profile")
    end
    provenance_block = _require_key(parsed, :provenance, "root")
    _require_object(provenance_block, "root.provenance")
    _require_object(_require_key(parsed, :verification, "root"), "root.verification")

    if certificate_type == RATIONAL_CERTIFICATE_TYPE
        problem isa LMIProblem ||
            throw(ArgumentError("root.problem.data must be a single-block LMI problem for `$RATIONAL_CERTIFICATE_TYPE`"))
        solution = _parse_rational_solution_v1(_require_key(parsed, :solution, "root"),
                                               problem)
        psd_proof = _parse_rational_psd_proof(psd, matrix_size(problem))
        return RationalCertificate(problem, solution, psd_proof, certificate_id)
    elseif certificate_type == BLOCK_RATIONAL_CERTIFICATE_TYPE
        problem isa BlockLMIProblem ||
            throw(ArgumentError("root.problem.data must be a block LMI problem for `$BLOCK_RATIONAL_CERTIFICATE_TYPE`"))
        solution = _parse_block_rational_solution_v1(_require_key(parsed, :solution,
                                                                  "root"),
                                                     problem)
        psd_proof = _parse_block_rational_psd_proof(psd, block_sizes(problem))
        return BlockRationalCertificate(problem, solution, psd_proof,
                                        certificate_id)
    elseif certificate_type == BLOCK_ALGEBRAIC_CERTIFICATE_TYPE
        problem isa BlockLMIProblem ||
            throw(ArgumentError("root.problem.data must be a block LMI problem for `$BLOCK_ALGEBRAIC_CERTIFICATE_TYPE`"))
        root, solution = _parse_block_algebraic_solution_v1(_require_key(parsed,
                                                                         :solution,
                                                                         "root"),
                                                            problem)
        psd_proof = _parse_block_algebraic_psd_proof(psd, block_sizes(problem), root)
        return BlockAlgebraicCertificate(problem, root, solution, psd_proof,
                                         certificate_id,
                                         _json_object_to_symbol_dict(provenance_block))
    elseif certificate_type == ALGEBRAIC_CERTIFICATE_TYPE
        problem isa LMIProblem ||
            throw(ArgumentError("root.problem.data must be a single-block LMI problem for `$ALGEBRAIC_CERTIFICATE_TYPE`"))
        root, solution = _parse_algebraic_solution_v1(_require_key(parsed, :solution,
                                                                   "root"),
                                                      problem)
        psd_proof = _parse_algebraic_psd_proof(psd, matrix_size(problem), root)
        return AlgebraicCertificate(problem, root, solution, psd_proof, certificate_id,
                                    _json_object_to_symbol_dict(provenance_block))
    end

    throw(ArgumentError("root.certificate_type must be `$RATIONAL_CERTIFICATE_TYPE`, `$BLOCK_RATIONAL_CERTIFICATE_TYPE`, `$ALGEBRAIC_CERTIFICATE_TYPE`, `$BLOCK_ALGEBRAIC_CERTIFICATE_TYPE`, or `$SOS_GRAM_CERTIFICATE_TYPE`; got `$certificate_type`"))
end

function _json_object_to_symbol_dict(value)
    value isa JSON3.Object || return Dict{Symbol, Any}()
    result = Dict{Symbol, Any}()
    for key in keys(value)
        result[Symbol(String(key))] = _json_to_plain_value(value[key])
    end
    return result
end

function _json_to_plain_value(value)
    if value isa JSON3.Object
        return Dict{Symbol, Any}(Symbol(String(key)) => _json_to_plain_value(value[key])
                                 for key in keys(value))
    elseif value isa JSON3.Array || value isa AbstractVector
        return [_json_to_plain_value(item) for item in value]
    elseif value isa AbstractString || value isa Integer || value isa Bool ||
           isnothing(value)
        return value
    end
    return string(value)
end

function _parse_certificate_problem_v1(problem_block)
    _require_object(problem_block, "root.problem")
    embedded = _require_key(problem_block, :embedded, "root.problem")
    embedded === true || throw(ArgumentError("root.problem.embedded must be true"))
    problem_type = _require_string(problem_block, :type, "root.problem.type")
    data = _require_key(problem_block, :data, "root.problem")
    _require_object(data, "root.problem.data")
    if problem_type == LMI_PROBLEM_TYPE
        return _parse_lmi_problem_v1_document(data)
    elseif problem_type == SDPA_PROBLEM_TYPE
        return _parse_block_lmi_problem_v1_document(data)
    end
    throw(ArgumentError("root.problem.type must be `$LMI_PROBLEM_TYPE` or `$SDPA_PROBLEM_TYPE`; got `$problem_type`"))
end

function _parse_sos_gram_certificate_v1_object(parsed)
    certificate_id = _require_string(parsed, :certificate_id, "root.certificate_id")
    _validate_sha256_identifier(certificate_id, "root.certificate_id")
    supplied_problem_hash = _require_string(parsed, :problem_hash, "root.problem_hash")
    problem = _parse_sos_gram_problem_object(_require_key(parsed, :sos_problem, "root"))
    expected_problem_hash = sos_gram_problem_hash(problem)
    supplied_problem_hash == expected_problem_hash ||
        throw(ArgumentError("root.problem_hash mismatch: expected $supplied_problem_hash, computed $expected_problem_hash"))

    proof = _require_key(parsed, :proof, "root")
    _require_object(proof, "root.proof")
    coefficient_matching = _require_key(proof, :coefficient_matching, "root.proof")
    _require_object(coefficient_matching, "root.proof.coefficient_matching")
    _require_value(coefficient_matching, :method, "exact_coefficient_matching",
                   "root.proof.coefficient_matching.method")
    haskey(coefficient_matching, :status) ||
        throw(ArgumentError("root.proof.coefficient_matching is missing required key `status`"))
    psd = _require_key(proof, :psd, "root.proof")
    _require_object(psd, "root.proof.psd")
    _require_value(psd, :method, "embedded_rational_psd_certificate",
                   "root.proof.psd.method")
    _require_object(_require_key(parsed, :provenance, "root"), "root.provenance")
    _require_object(_require_key(parsed, :verification, "root"), "root.verification")

    cert = _parse_sos_gram_certificate_object(parsed)
    cert.hash == certificate_id ||
        throw(ArgumentError("root.certificate_id must match the SOS certificate hash"))
    return cert
end

function _parse_rational_solution_v1(solution, problem::LMIProblem)
    _require_object(solution, "root.solution")
    _require_value(solution, :field, LMI_FIELD, "root.solution.field")
    _require_value(solution, :representation, "coordinates",
                   "root.solution.representation")
    coordinates = _require_key(solution, :coordinates, "root.solution")
    _require_object(coordinates, "root.solution.coordinates")

    values = Rational{BigInt}[]
    for var in problem.vars
        key = Symbol(String(var))
        haskey(coordinates, key) ||
            throw(ArgumentError("root.solution.coordinates is missing variable `$(String(var))`"))
        push!(values,
              _parse_rational_string(_require_key(coordinates, key,
                                                  "root.solution.coordinates"),
                                     "root.solution.coordinates.$(String(var))"))
    end
    return values
end

function _parse_block_rational_solution_v1(solution, problem::BlockLMIProblem)
    _require_object(solution, "root.solution")
    _require_value(solution, :field, LMI_FIELD, "root.solution.field")
    _require_value(solution, :representation, "coordinates",
                   "root.solution.representation")
    coordinates = _require_key(solution, :coordinates, "root.solution")
    _require_object(coordinates, "root.solution.coordinates")

    values = Rational{BigInt}[]
    for var in problem.vars
        key = Symbol(String(var))
        haskey(coordinates, key) ||
            throw(ArgumentError("root.solution.coordinates is missing variable `$(String(var))`"))
        push!(values,
              _parse_rational_string(_require_key(coordinates, key,
                                                  "root.solution.coordinates"),
                                     "root.solution.coordinates.$(String(var))"))
    end
    return values
end

function _parse_algebraic_solution_v1(solution, problem::LMIProblem)
    _require_object(solution, "root.solution")
    _require_value(solution, :field, "QQbar", "root.solution.field")
    _require_value(solution, :representation, ALGEBRAIC_SOLUTION_TYPE,
                   "root.solution.representation")

    if haskey(solution, :root_symbol)
        root_symbol = _require_string(solution, :root_symbol, "root.solution.root_symbol")
        root_symbol == "t" ||
            throw(ArgumentError("root.solution.root_symbol must currently be `t`; got `$root_symbol`"))
    end

    f = parse_polynomial(_require_string(solution, :minimal_polynomial,
                                         "root.solution.minimal_polynomial"))
    interval_value = _require_key(solution, :root_interval, "root.solution")
    _require_array(interval_value, "root.solution.root_interval")
    length(interval_value) == 2 ||
        throw(ArgumentError("root.solution.root_interval must contain exactly two rational endpoints"))
    root = AlgebraicRoot(f,
                         RationalInterval(_parse_rational_string(interval_value[1],
                                                                 "root.solution.root_interval[1]"),
                                          _parse_rational_string(interval_value[2],
                                                                 "root.solution.root_interval[2]")))

    coordinates = _require_key(solution, :coordinates, "root.solution")
    _require_object(coordinates, "root.solution.coordinates")
    values = AlgebraicElement[]
    for var in problem.vars
        key = Symbol(String(var))
        haskey(coordinates, key) ||
            throw(ArgumentError("root.solution.coordinates is missing variable `$(String(var))`"))
        value = _require_string(coordinates, key,
                                "root.solution.coordinates.$(String(var))")
        push!(values, AlgebraicElement(root, value))
    end

    return root, values
end

function _parse_block_algebraic_solution_v1(solution, problem::BlockLMIProblem)
    _require_object(solution, "root.solution")
    _require_value(solution, :field, "QQbar", "root.solution.field")
    _require_value(solution, :representation, ALGEBRAIC_SOLUTION_TYPE,
                   "root.solution.representation")

    if haskey(solution, :root_symbol)
        root_symbol = _require_string(solution, :root_symbol, "root.solution.root_symbol")
        root_symbol == "t" ||
            throw(ArgumentError("root.solution.root_symbol must currently be `t`; got `$root_symbol`"))
    end

    f = parse_polynomial(_require_string(solution, :minimal_polynomial,
                                         "root.solution.minimal_polynomial"))
    interval_value = _require_key(solution, :root_interval, "root.solution")
    _require_array(interval_value, "root.solution.root_interval")
    length(interval_value) == 2 ||
        throw(ArgumentError("root.solution.root_interval must contain exactly two rational endpoints"))
    root = AlgebraicRoot(f,
                         RationalInterval(_parse_rational_string(interval_value[1],
                                                                 "root.solution.root_interval[1]"),
                                          _parse_rational_string(interval_value[2],
                                                                 "root.solution.root_interval[2]")))

    coordinates = _require_key(solution, :coordinates, "root.solution")
    _require_object(coordinates, "root.solution.coordinates")
    values = AlgebraicElement[]
    for var in problem.vars
        key = Symbol(String(var))
        haskey(coordinates, key) ||
            throw(ArgumentError("root.solution.coordinates is missing variable `$(String(var))`"))
        value = _require_string(coordinates, key,
                                "root.solution.coordinates.$(String(var))")
        push!(values, AlgebraicElement(root, value))
    end

    return root, values
end

function _validate_sha256_identifier(value::AbstractString, path::AbstractString)
    occursin(r"^sha256:[0-9a-f]{64}$", value) ||
        throw(ArgumentError("$path must be a sha256 identifier"))
    return true
end

"""
    failure_report_json(failure) -> NamedTuple

Return the public failure report schema v1.0 for a certification failure.
"""
function failure_report_json(failure::CertificationFailure)
    return (;
            certsdp_failure_report_version=SCHEMA_V1_VERSION,
            status=CERTIFICATION_FAILURE_STATUS,
            failure_type=failure_type(failure),
            reason=String(failure.reason),
            summary=failure.message,
            stage=String(failure.stage),
            details=_certification_diagnostics_json(failure.diagnostics),
            suggestions=_failure_suggestions(failure.reason),
            provenance=_failure_provenance_v1(failure),)
end

failure_report_json(result::FailureResult) = failure_report_json(result.failure)

function _failure_provenance_v1(failure::CertificationFailure)
    base = Dict{Symbol, Any}(:certsdp_version => string(package_version()),
                             :julia_version => string(VERSION),
                             :schema_version => SCHEMA_V1_VERSION)
    if haskey(failure.diagnostics, :backend_provenance)
        base[:algebraic_backend] = _provenance_json_value(failure.diagnostics[:backend_provenance])
    elseif haskey(failure.diagnostics, :backend_failure) &&
           failure.diagnostics[:backend_failure] isa AlgebraicBackendFailure
        base[:algebraic_backend] = algebraic_backend_provenance_json(failure.diagnostics[:backend_failure].provenance)
    end
    return NamedTuple{Tuple(keys(base))}(Tuple(values(base)))
end

"""
    diagnose(failure) -> failure report

Return a public v1.0 failure report or numerical approximation diagnostic.
Failure-report shape remains schema-stable and also covers approximate quality
reports.
"""
diagnose(failure::CertificationFailure) = failure_report_json(failure)
diagnose(result::FailureResult) = failure_report_json(result.failure)
function diagnose(result::CertifiedResult)
    return (;
            status=verify(result) ? "verified" : "rejected",
            certificate_type=string(typeof(result.certificate)),)
end
diagnose(approx::ApproxSolution) = approx_quality_report_json(approx)
diagnose(report::ApproxQualityReport) = approx_quality_report_json(report)

function diagnose(result)
    if result isa FailureResult
        return diagnose(result)
    elseif result isa CertifiedResult
        return diagnose(result)
    elseif result isa CertificationFailure
        return diagnose(result)
    elseif result isa ApproxSolution
        return diagnose(result)
    elseif result isa ApproxQualityReport
        return diagnose(result)
    elseif result isa RationalCertificate || result isa AlgebraicCertificate ||
           result isa SOSGramCertificate || result isa BlockRationalCertificate ||
           result isa BlockAlgebraicCertificate
        return (;
                status=verify(result) ? "verified" : "rejected",
                certificate_type=string(typeof(result)),)
    end
    throw(ArgumentError("diagnose expects a CertificationResult, CertificationFailure, ApproxSolution, ApproxQualityReport, or certificate"))
end

function validate_failure_report_schema(json_text::AbstractString)
    parsed = _read_json_document(json_text, "failure report")
    _require_object(parsed, "root")
    _require_value(parsed, CERTSDP_FAILURE_REPORT_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.certsdp_failure_report_version")
    _require_value(parsed, :status, CERTIFICATION_FAILURE_STATUS, "root.status")
    failure_type = _require_string(parsed, :failure_type, "root.failure_type")
    isempty(failure_type) && throw(ArgumentError("root.failure_type must not be empty"))
    if haskey(parsed, :reason)
        reason = _require_string(parsed, :reason, "root.reason")
        isempty(reason) && throw(ArgumentError("root.reason must not be empty"))
    end
    summary = _require_string(parsed, :summary, "root.summary")
    isempty(summary) && throw(ArgumentError("root.summary must not be empty"))
    stage = _require_string(parsed, :stage, "root.stage")
    isempty(stage) && throw(ArgumentError("root.stage must not be empty"))
    _require_object(_require_key(parsed, :details, "root"), "root.details")
    suggestions = _require_key(parsed, :suggestions, "root")
    _require_array(suggestions, "root.suggestions")
    for (i, suggestion) in enumerate(suggestions)
        suggestion isa AbstractString ||
            throw(ArgumentError("root.suggestions[$i] must be a string"))
    end
    _require_object(_require_key(parsed, :provenance, "root"), "root.provenance")
    return true
end

function parse_failure_report_json(json_text::AbstractString)
    parsed = _read_json_document(json_text, "failure report")
    validate_failure_report_schema(json_text)
    reason = if haskey(parsed, :reason)
        Symbol(_require_string(parsed, :reason, "root.reason"))
    else
        Symbol(_require_string(parsed, :failure_type, "root.failure_type"))
    end
    message = _require_string(parsed, :summary, "root.summary")
    stage = Symbol(_require_string(parsed, :stage, "root.stage"))
    details = _json_object_to_symbol_dict(_require_key(parsed, :details, "root"))
    return CertificationFailure(reason, message, stage, details)
end

read_failure_report(path::AbstractString) = parse_failure_report_json(read(path, String))

function write_failure_report(path::AbstractString,
                              failure::Union{CertificationFailure, FailureResult})
    open(path, "w") do io
        JSON3.pretty(io, failure_report_json(failure))
        return println(io)
    end
    return path
end

function _failure_suggestions(reason::Symbol)
    reason in (:numerical_solver_unavailable,
               :numerical_solver_failed,
               :numerical_solver_status,
               :unsupported_numerical_solver,
               :clarabel_setup_failed,
               :clarabel_solve_failed,
               :clarabel_solution_invalid,
               :user_solution_invalid) &&
        return ["check the numerical solver status and residuals",
                "try another supported solver or provide a user-supplied approximation",
                "rerun with higher precision or random objective restarts"]
    reason === :rank_profile_unstable &&
        return ["rerun the numerical solver with higher precision",
                "try random objective restarts",
                "force a candidate rank only if independent diagnostics justify it"]
    reason in (:system_too_large, :incidence_system_too_large) &&
        return ["lower the requested rank/search size or simplify the input LMI",
                "try facial reduction or block decomposition before algebraic solving",
                "increase system-size limits only after checking backend feasibility"]
    reason in (:msolve_failed, :backend_failed, :unsupported_backend,
               :msolve_positive_dimensional) &&
        return ["check that msolve is installed and executable",
                "rerun with a smaller incidence system or longer timeout",
                "inspect backend logs before trusting any candidate"]
    reason in (:no_real_algebraic_solution,
               :no_nearby_real_solution,
               :no_candidate_verified,
               :root_selection_failed,
               :msolve_empty_solution_set) &&
        return ["rerun the numerical solver with higher precision",
                "try random objective restarts or a different rank profile",
                "inspect candidate root boxes and residuals before forcing a root"]
    reason in (:invalid_psd_proof_method, :psd_verification_failed,
               :certificate_build_failed) &&
        return ["try a different PSD proof method such as principal_minors or schur_zero",
                "inspect the reported block/minor/pivot data",
                "recompute the approximation or choose a more stable pivot block"]
    reason in (:sos_matching_failed, :sos_psd_failed, :sos_certificate_failed) &&
        return ["check exact coefficient matching between the polynomial and Gram matrix",
                "verify the monomial basis order and Gram matrix dimensions",
                "use a rational Gram matrix or export the solver result exactly"]
    reason in (:approximation_residual_too_large,
               :approximation_symmetry_residual_too_large,
               :approximation_psd_violation_too_large,
               :approximation_problem_mismatch,
               :approximation_dimension_mismatch,
               :approximation_matrix_size_mismatch) &&
        return ["provide a higher precision approximate solution",
                "check that the solution file matches the problem hash",
                "tighten or recompute the LMI residual"]
    return ["inspect the failure details",
            "try a higher precision approximation",
            "verify any generated candidate with the exact verifier"]
end

function _read_json_document(json_text::AbstractString, kind::AbstractString)
    return try
        JSON3.read(json_text)
    catch err
        throw(ArgumentError("invalid $kind JSON: $(sprint(showerror, err))"))
    end
end
