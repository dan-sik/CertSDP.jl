module Adapters

using ..Kernel
using JSON3: JSON3
using SHA: sha256

export adapter_layer_marker,
       adapter_trusted_boundary,
       AdapterCandidate,
       adapter_candidate,
       certify_adapter_candidate,
       SparseSOSCertificateCandidate,
       import_tssos_artifact,
       certify_tssos_artifact,
       verify_tssos_certificate,
       tssos_artifact_hash,
       write_tssos_candidate,
       QuantumCertificateCandidate,
       import_nctssos_artifact,
       certify_nctssos_artifact,
       write_nctssos_candidate

adapter_layer_marker() = :certsdp3_untrusted_candidate_adapters

adapter_trusted_boundary() =
    "Adapters may translate candidates and metadata, but acceptance requires Kernel exact replay."

struct AdapterCandidate
    source::Symbol
    payload::Any
    metadata::Dict{Symbol, Any}
end

struct SparseSOSCertificateCandidate
    source::Symbol
    source_hash::String
    artifact_hash::String
    certificate::Kernel.SparseSOSCertificate
    metadata::Dict{Symbol, Any}
end

struct QuantumCertificateCandidate
    source::Symbol
    source_hash::String
    artifact_hash::String
    certificate::Kernel.QuantumBoundCertificate
    metadata::Dict{Symbol, Any}
end

function adapter_candidate(source::Symbol, payload; metadata=Dict{Symbol, Any}())
    return AdapterCandidate(source, payload,
                            Dict{Symbol, Any}(Symbol(key) => value
                                              for (key, value) in metadata))
end

function certify_adapter_candidate(candidate::AdapterCandidate)
    if candidate.payload isa Kernel.V3Certificate
        report = Kernel.verify_certificate(candidate.payload)
        report.accepted || return report
        return report
    end
    return Kernel.DiagnosticReport(false,
                                   :A,
                                   :adapter_candidate,
                                   :candidate_replay,
                                   "adapter candidate payload is not a CertSDP v3 certificate",
                                   :adapter_payload,
                                   nothing,
                                   nothing,
                                   nothing,
                                   nothing,
                                   nothing,
                                   nothing,
                                   Dict{Symbol, Any}(:source => String(candidate.source)))
end

function tssos_artifact_hash(path::AbstractString)
    parsed = _read_json_file(path)
    return _artifact_hash(parsed)
end

function import_tssos_artifact(path::AbstractString)::SparseSOSCertificateCandidate
    parsed = _read_json_file(path)
    _reject_trusted_metadata!(parsed, "root")
    _strict_object(parsed,
                   Set(Symbol[:certsdp_tssos_artifact_version,
                              :variables,
                              :objective_polynomial,
                              :constraints,
                              :cliques,
                              :monomial_bases,
                              :gram_blocks,
                              :localizing_blocks,
                              :coefficient_maps,
                              :bound,
                              :provenance,
                              :frontend_metadata,
                              :solver_metadata,
                              :source_raw_hash,
                              :artifact_hash]),
                   "root")
    String(parsed[:certsdp_tssos_artifact_version]) == Kernel.CERTSDP3_SCHEMA_VERSION ||
        throw(ArgumentError("root.certsdp_tssos_artifact_version must be 3.0"))
    artifact_hash = _artifact_hash(parsed)
    supplied_hash = String(parsed[:artifact_hash])
    supplied_hash == artifact_hash ||
        throw(ArgumentError("root.artifact_hash mismatch: supplied $supplied_hash computed $artifact_hash"))
    variables = _parse_symbol_vector(parsed[:variables], "root.variables")
    length(unique(variables)) == length(variables) ||
        throw(ArgumentError("root.variables contains duplicate names"))
    target_terms = _parse_terms(parsed[:objective_polynomial], length(variables),
                                "root.objective_polynomial")
    cliques = [_parse_symbol_vector(clique, "root.cliques[$i]")
               for (i, clique) in enumerate(parsed[:cliques])]
    bound = _parse_rational(parsed[:bound], "root.bound")
    problem = Kernel.SparseSOSProblem(variables, target_terms, cliques, bound)
    basis_by_id = Dict{Symbol, Vector{Vector{Int}}}()
    for basis in parsed[:monomial_bases]
        _strict_object(basis, Set(Symbol[:id, :exponents]), "root.monomial_bases[]")
        id = Symbol(String(basis[:id]))
        haskey(basis_by_id, id) &&
            throw(ArgumentError("root.monomial_bases has duplicate id $(String(id))"))
        basis_by_id[id] = _parse_exponent_rows(basis[:exponents], length(variables),
                                               "root.monomial_bases[$id].exponents")
    end
    coefficient_maps = _coefficient_maps(parsed[:coefficient_maps], length(variables))
    sos_blocks = Kernel.SparseSOSBlock[]
    for (i, block) in enumerate(parsed[:gram_blocks])
        push!(sos_blocks,
              _parse_sos_block(block, basis_by_id, coefficient_maps,
                               length(variables),
                               "root.gram_blocks[$i]"))
    end
    localizing = Kernel.LocalizingMatrixProof[]
    for (i, local_block) in enumerate(parsed[:localizing_blocks])
        _strict_object(local_block,
                       Set(Symbol[:id, :clique_id, :constraint_terms,
                                  :sos_block]),
                       "root.localizing_blocks[$i]")
        block = _parse_sos_block(local_block[:sos_block], basis_by_id,
                                 coefficient_maps, length(variables),
                                 "root.localizing_blocks[$i].sos_block")
        push!(localizing,
              Kernel.LocalizingMatrixProof(Symbol(String(local_block[:id])),
                                           Symbol(String(local_block[:clique_id])),
                                           _parse_terms(local_block[:constraint_terms],
                                                        length(variables),
                                                        "root.localizing_blocks[$i].constraint_terms"),
                                           block))
    end
    putinar = if isempty(localizing)
        nothing
    else
        identity_hash = _hash_payload((;
            bound=Kernel.rational_string(bound),
            localizing=[Kernel.localizing_matrix_proof_json(block)
                        for block in localizing]))
        Kernel.PutinarCertificate(localizing, bound, identity_hash)
    end
    cert = Kernel.make_sparse_sos_certificate(problem, sos_blocks;
                                              putinar=putinar)
    report = Kernel.verify_sparse_sos_certificate(cert)
    report.accepted ||
        throw(ArgumentError("TSSOS artifact does not replay as a sparse SOS certificate: $(report.reason)"))
    provenance = _symbol_dict(parsed[:provenance])
    return SparseSOSCertificateCandidate(:tssos,
                                         String(parsed[:source_raw_hash]),
                                         artifact_hash,
                                         cert,
                                         provenance)
end

function certify_tssos_artifact(path::AbstractString)
    candidate = try
        import_tssos_artifact(path)
    catch err
        failure = _bad_candidate_rejected(:candidate_rejected,
                                          sprint(showerror, err),
                                          :tssos_import,
                                          Dict{Symbol, Any}(:artifact_path => String(path)))
        return _failure_result(failure)
    end
    report = Kernel.verify_sparse_sos_certificate(candidate.certificate)
    if report.accepted
        return _certified_result(candidate.certificate;
                                 artifacts=Dict{Symbol, Any}(
                                     :source => candidate.source,
                                     :source_hash => candidate.source_hash,
                                     :artifact_hash => candidate.artifact_hash,
                                     :metadata => candidate.metadata,
                                 ))
    end
    failure = _bad_candidate_rejected(:candidate_rejected,
                                      report.reason,
                                      report.stage,
                                      Dict{Symbol, Any}(
                                          :artifact_path => String(path),
                                          :obligation_id => report.obligation_id,
                                          :artifact_hash => candidate.artifact_hash,
                                      ))
    return _failure_result(failure)
end

function verify_tssos_certificate(cert)
    payload = cert isa SparseSOSCertificateCandidate ? cert.certificate : cert
    payload isa Kernel.SparseSOSCertificate || return false
    return Kernel.verify_sparse_sos_certificate(payload).accepted
end

function write_tssos_candidate(candidate::SparseSOSCertificateCandidate,
                               path::AbstractString)
    payload = (;
        certsdp_sparse_sos_candidate_version=Kernel.CERTSDP3_SCHEMA_VERSION,
        source=String(candidate.source),
        source_hash=candidate.source_hash,
        artifact_hash=candidate.artifact_hash,
        certificate_hash=candidate.certificate.certificate_hash,
        problem_hash=candidate.certificate.problem.problem_hash,
        metadata=Dict(String(key) => value for (key, value) in candidate.metadata),
    )
    open(path, "w") do io
        JSON3.pretty(io, payload)
        println(io)
    end
    return path
end

function import_nctssos_artifact(path::AbstractString)::QuantumCertificateCandidate
    parsed = _read_json_file(path)
    _reject_trusted_metadata!(parsed, "root")
    _strict_object(parsed,
                   Set(Symbol[:certsdp_nctssos_artifact_version,
                              :variables,
                              :words,
                              :involution_convention,
                              :trace_cyclic,
                              :quotient_relations,
                              :block_bases,
                              :gram_blocks,
                              :coefficient_maps,
                              :objective_bound,
                              :provenance,
                              :frontend_metadata,
                              :solver_metadata,
                              :rewrite_witnesses,
                              :source_hash,
                              :artifact_hash]),
                   "root")
    String(parsed[:certsdp_nctssos_artifact_version]) == Kernel.CERTSDP3_SCHEMA_VERSION ||
        throw(ArgumentError("root.certsdp_nctssos_artifact_version must be 3.0"))
    artifact_hash = _artifact_hash(parsed)
    supplied_hash = String(parsed[:artifact_hash])
    supplied_hash == artifact_hash ||
        throw(ArgumentError("root.artifact_hash mismatch: supplied $supplied_hash computed $artifact_hash"))
    variables = _parse_symbol_vector(parsed[:variables], "root.variables")
    words = [_parse_symbol_vector(word, "root.words[$i]")
             for (i, word) in enumerate(parsed[:words])]
    relations = _parse_quantum_relations(parsed[:quotient_relations])
    trace_cyclic = Bool(parsed[:trace_cyclic])
    problem = Kernel.NPAProblem(variables, relations, words; trace_cyclic)
    basis_by_id = Dict{Symbol, Vector{Vector{Symbol}}}()
    for (i, basis) in enumerate(parsed[:block_bases])
        _strict_object(basis, Set(Symbol[:id, :words]), "root.block_bases[$i]")
        id = Symbol(String(basis[:id]))
        haskey(basis_by_id, id) &&
            throw(ArgumentError("root.block_bases has duplicate id $(String(id))"))
        basis_by_id[id] = [_parse_symbol_vector(word, "root.block_bases[$i].words[]")
                           for word in basis[:words]]
    end
    coefficient_maps = _nc_coefficient_maps(parsed[:coefficient_maps])
    isempty(parsed[:gram_blocks]) &&
        throw(ArgumentError("root.gram_blocks must contain at least one moment block"))
    block = parsed[:gram_blocks][1]
    _strict_object(block,
                   Set(Symbol[:id, :basis_id, :moment_matrix, :psd_proof]),
                   "root.gram_blocks[1]")
    basis_id = Symbol(String(block[:basis_id]))
    haskey(basis_by_id, basis_id) ||
        throw(ArgumentError("root.gram_blocks[1].basis_id references an unknown block basis"))
    matrix = Kernel.parse_sparse_matrix_object(block[:moment_matrix];
                                               strict=true,
                                               path="root.gram_blocks[1].moment_matrix")
    proof = Kernel._parse_low_rank_proof_object(block[:psd_proof],
                                                matrix;
                                                strict=true,
                                                path="root.gram_blocks[1].psd_proof")
    block_id = Symbol(String(block[:id]))
    haskey(coefficient_maps, block_id) ||
        throw(ArgumentError("root.gram_blocks[1].id is missing coefficient map"))
    haskey(parsed, :rewrite_witnesses) ||
        throw(ArgumentError("root.rewrite_witnesses is required; importer will not invent NC witnesses"))
    witnesses = _parse_rewrite_witnesses(parsed[:rewrite_witnesses],
                                         "root.rewrite_witnesses")
    isempty(witnesses) &&
        throw(ArgumentError("root.rewrite_witnesses must contain explicit witness chains"))
    moment = Kernel.NCMomentMatrixCertificate(problem, matrix, proof,
                                              coefficient_maps[block_id],
                                              witnesses)
    bound = _parse_rational(parsed[:objective_bound], "root.objective_bound")
    cert = Kernel.make_quantum_bound_certificate(problem, moment,
                                                 coefficient_maps[block_id],
                                                 bound)
    report = Kernel.verify_quantum_bound_certificate(cert)
    report.accepted ||
        throw(ArgumentError("NCTSSOS artifact does not replay as a quantum bound certificate: $(report.reason)"))
    return QuantumCertificateCandidate(:nctssos,
                                       String(parsed[:source_hash]),
                                       artifact_hash,
                                       cert,
                                       _symbol_dict(parsed[:provenance]))
end

function certify_nctssos_artifact(path::AbstractString)
    candidate = try
        import_nctssos_artifact(path)
    catch err
        failure = _bad_candidate_rejected(:candidate_rejected,
                                          sprint(showerror, err),
                                          :nctssos_import,
                                          Dict{Symbol, Any}(:artifact_path => String(path)))
        return _failure_result(failure)
    end
    report = Kernel.verify_quantum_bound_certificate(candidate.certificate)
    if report.accepted
        return _certified_result(candidate.certificate;
                                 artifacts=Dict{Symbol, Any}(
                                     :source => candidate.source,
                                     :source_hash => candidate.source_hash,
                                     :artifact_hash => candidate.artifact_hash,
                                     :metadata => candidate.metadata,
                                 ))
    end
    failure = _bad_candidate_rejected(:candidate_rejected,
                                      report.reason,
                                      report.stage,
                                      Dict{Symbol, Any}(
                                          :artifact_path => String(path),
                                          :obligation_id => report.obligation_id,
                                          :artifact_hash => candidate.artifact_hash,
                                      ))
    return _failure_result(failure)
end

function write_nctssos_candidate(candidate::QuantumCertificateCandidate,
                                 path::AbstractString)
    payload = (;
        certsdp_quantum_candidate_version=Kernel.CERTSDP3_SCHEMA_VERSION,
        source=String(candidate.source),
        source_hash=candidate.source_hash,
        artifact_hash=candidate.artifact_hash,
        certificate_hash=candidate.certificate.certificate_hash,
        problem_hash=candidate.certificate.problem.problem_hash,
        metadata=Dict(String(key) => value for (key, value) in candidate.metadata),
    )
    open(path, "w") do io
        JSON3.pretty(io, payload)
        println(io)
    end
    return path
end

function _parse_quantum_relations(values)
    values isa AbstractVector || throw(ArgumentError("root.quotient_relations must be an array"))
    relations = Kernel.AbstractQuantumRelation[]
    for (i, relation) in enumerate(values)
        _strict_object(relation, Set(Symbol[:kind, :id, :data]),
                       "root.quotient_relations[$i]")
        kind = String(relation[:kind])
        id = Symbol(String(relation[:id]))
        data = relation[:data]
        if kind == "ProjectionRelation"
            _strict_object(data, Set(Symbol[:symbol]),
                           "root.quotient_relations[$i].data")
            push!(relations, Kernel.ProjectionRelation(id,
                                                       Symbol(String(data[:symbol]))))
        elseif kind == "UnitaryRelation"
            _strict_object(data, Set(Symbol[:symbol]),
                           "root.quotient_relations[$i].data")
            push!(relations, Kernel.UnitaryRelation(id,
                                                    Symbol(String(data[:symbol]))))
        elseif kind == "CommutationRelation"
            _strict_object(data, Set(Symbol[:left_symbols, :right_symbols]),
                           "root.quotient_relations[$i].data")
            push!(relations,
                  Kernel.CommutationRelation(id,
                                             _parse_symbol_vector(data[:left_symbols],
                                                                  "root.quotient_relations[$i].data.left_symbols"),
                                             _parse_symbol_vector(data[:right_symbols],
                                                                  "root.quotient_relations[$i].data.right_symbols")))
        elseif kind == "TraceCyclicRelation"
            _strict_object(data, Set(Symbol[]),
                           "root.quotient_relations[$i].data")
            push!(relations, Kernel.TraceCyclicRelation(id))
        elseif kind == "StarInvolutionRelation"
            _strict_object(data, Set(Symbol[]),
                           "root.quotient_relations[$i].data")
            push!(relations, Kernel.StarInvolutionRelation(id))
        elseif kind == "NormalizationRelation"
            _strict_object(data, Set(Symbol[:value]),
                           "root.quotient_relations[$i].data")
            push!(relations,
                  Kernel.NormalizationRelation(id,
                                               _parse_rational(data[:value],
                                                               "root.quotient_relations[$i].data.value")))
        else
            throw(ArgumentError("root.quotient_relations[$i].kind is unsupported"))
        end
    end
    return relations
end

function _nc_coefficient_maps(values)
    result = Dict{Symbol, Vector{Tuple{Vector{Symbol}, Rational{BigInt}}}}()
    for (i, entry) in enumerate(values)
        _strict_object(entry, Set(Symbol[:block_id, :terms]),
                       "root.coefficient_maps[$i]")
        id = Symbol(String(entry[:block_id]))
        haskey(result, id) &&
            throw(ArgumentError("root.coefficient_maps has duplicate block_id $(String(id))"))
        terms = Tuple{Vector{Symbol}, Rational{BigInt}}[]
        for (j, term) in enumerate(entry[:terms])
            _strict_object(term, Set(Symbol[:word, :coefficient]),
                           "root.coefficient_maps[$i].terms[$j]")
            push!(terms,
                  (_parse_symbol_vector(term[:word],
                                        "root.coefficient_maps[$i].terms[$j].word"),
                   _parse_rational(term[:coefficient],
                                   "root.coefficient_maps[$i].terms[$j].coefficient")))
        end
        result[id] = terms
    end
    return result
end

function _artifact_rewrite_witnesses(relations)
    projections = [relation for relation in relations
                   if relation isa Kernel.ProjectionRelation]
    commutations = [relation for relation in relations
                    if relation isa Kernel.CommutationRelation]
    witnesses = Kernel.NCRewriteWitness[]
    if !isempty(projections)
        relation = first(projections)
        push!(witnesses,
              Kernel.NCRewriteWitness([relation.symbol, relation.symbol],
                                      [Kernel.NCRewriteStep(relation.id,
                                                           :projection_idempotent,
                                                           [relation.symbol, relation.symbol],
                                                           [relation.symbol])],
                                      [relation.symbol],
                                      [relation.id],
                                      Vector{Symbol}[],
                                      Vector{Symbol}[]))
    end
    if !isempty(commutations)
        relation = first(commutations)
        !isempty(relation.left_symbols) && !isempty(relation.right_symbols) && begin
            left = first(relation.left_symbols)
            right = first(relation.right_symbols)
            push!(witnesses,
                  Kernel.NCRewriteWitness([left, right],
                                          [Kernel.NCRewriteStep(relation.id,
                                                               :commutation,
                                                               [left, right],
                                                               [right, left])],
                                          [right, left],
                                          [relation.id],
                                          Vector{Symbol}[],
                                          Vector{Symbol}[]))
        end
    end
    return witnesses
end

function _parse_rewrite_witnesses(values, path::AbstractString)
    values isa AbstractVector || throw(ArgumentError("$path must be an array"))
    witnesses = Kernel.NCRewriteWitness[]
    for (i, witness) in enumerate(values)
        wpath = "$path[$i]"
        _strict_object(witness,
                       Set(Symbol[:input_word, :steps, :final_word,
                                  :relation_ids_used, :trace_rotations,
                                  :star_steps]),
                       wpath)
        steps = Kernel.NCRewriteStep[]
        for (j, step) in enumerate(witness[:steps])
            spath = "$wpath.steps[$j]"
            _strict_object(step,
                           Set(Symbol[:relation_id, :rule, :before, :after]),
                           spath)
            push!(steps,
                  Kernel.NCRewriteStep(Symbol(String(step[:relation_id])),
                                       Symbol(String(step[:rule])),
                                       _parse_symbol_vector(step[:before],
                                                            "$spath.before"),
                                       _parse_symbol_vector(step[:after],
                                                            "$spath.after")))
        end
        push!(witnesses,
              Kernel.NCRewriteWitness(_parse_symbol_vector(witness[:input_word],
                                                           "$wpath.input_word"),
                                      steps,
                                      _parse_symbol_vector(witness[:final_word],
                                                           "$wpath.final_word"),
                                      Symbol.(String.(witness[:relation_ids_used])),
                                      [_parse_symbol_vector(row,
                                                            "$wpath.trace_rotations[]")
                                       for row in witness[:trace_rotations]],
                                      [_parse_symbol_vector(row,
                                                            "$wpath.star_steps[]")
                                       for row in witness[:star_steps]]))
    end
    return witnesses
end

function _parse_sos_block(block, basis_by_id, coefficient_maps,
                          variable_count::Int, path::AbstractString)
    _strict_object(block,
                   Set(Symbol[:id, :clique_id, :basis_id, :gram_matrix,
                              :psd_proof]),
                   path)
    id = Symbol(String(block[:id]))
    basis_id = Symbol(String(block[:basis_id]))
    haskey(basis_by_id, basis_id) ||
        throw(ArgumentError("$path.basis_id references an unknown monomial basis"))
    matrix = Kernel.parse_sparse_matrix_object(block[:gram_matrix];
                                               strict=true,
                                               path="$path.gram_matrix")
    proof = Kernel._parse_low_rank_proof_object(block[:psd_proof],
                                                matrix;
                                                strict=true,
                                                path="$path.psd_proof")
    haskey(coefficient_maps, id) ||
        throw(ArgumentError("$path.id is missing a coefficient map"))
    return Kernel.SparseSOSBlock(id,
                                 Symbol(String(block[:clique_id])),
                                 basis_by_id[basis_id],
                                 matrix,
                                 proof,
                                 coefficient_maps[id])
end

function _coefficient_maps(values, variable_count::Int)
    result = Dict{Symbol, Vector{Kernel.PolynomialTerm}}()
    for (i, entry) in enumerate(values)
        _strict_object(entry, Set(Symbol[:block_id, :terms]),
                       "root.coefficient_maps[$i]")
        id = Symbol(String(entry[:block_id]))
        haskey(result, id) &&
            throw(ArgumentError("root.coefficient_maps has duplicate block_id $(String(id))"))
        result[id] = _parse_terms(entry[:terms], variable_count,
                                  "root.coefficient_maps[$i].terms")
    end
    return result
end

function _parse_terms(values, variable_count::Int, path::AbstractString)
    values isa AbstractVector || throw(ArgumentError("$path must be an array"))
    terms = Kernel.PolynomialTerm[]
    for (i, value) in enumerate(values)
        _strict_object(value, Set(Symbol[:exponents, :coefficient]), "$path[$i]")
        exponents = _parse_exponents(value[:exponents], variable_count,
                                     "$path[$i].exponents")
        push!(terms, Kernel.PolynomialTerm(exponents,
                                           _parse_rational(value[:coefficient],
                                                           "$path[$i].coefficient")))
    end
    return terms
end

function _parse_exponent_rows(values, variable_count::Int, path::AbstractString)
    values isa AbstractVector || throw(ArgumentError("$path must be an array"))
    return [_parse_exponents(row, variable_count, "$path[$i]")
            for (i, row) in enumerate(values)]
end

function _parse_exponents(values, variable_count::Int, path::AbstractString)
    values isa AbstractVector || throw(ArgumentError("$path must be an array"))
    length(values) == variable_count ||
        throw(ArgumentError("$path length must match variable count"))
    exponents = Int[]
    for (i, value) in enumerate(values)
        value isa Integer || throw(ArgumentError("$path[$i] must be an integer"))
        value >= 0 || throw(ArgumentError("$path[$i] must be nonnegative"))
        push!(exponents, Int(value))
    end
    return exponents
end

function _parse_symbol_vector(values, path::AbstractString)
    values isa AbstractVector || throw(ArgumentError("$path must be an array"))
    symbols = Symbol[]
    for (i, value) in enumerate(values)
        value isa AbstractString || throw(ArgumentError("$path[$i] must be a string"))
        push!(symbols, Symbol(String(value)))
    end
    return symbols
end

function _parse_rational(value, path::AbstractString)
    value isa AbstractString || throw(ArgumentError("$path must be a rational string"))
    text = strip(String(value))
    match_result = match(r"^([+-]?\d+)(?:/(\d+))?$", text)
    isnothing(match_result) &&
        throw(ArgumentError("$path is not a valid rational string"))
    num = parse(BigInt, match_result.captures[1])
    den = isnothing(match_result.captures[2]) ? BigInt(1) :
          parse(BigInt, match_result.captures[2])
    den != 0 || throw(ArgumentError("$path has zero denominator"))
    return num // den
end

function _read_json_file(path::AbstractString)
    return JSON3.read(read(path, String))
end

function _artifact_hash(parsed)
    if parsed isa AbstractDict && !(parsed isa JSON3.Object)
        for key in (:artifact_hash, "artifact_hash")
            if haskey(parsed, key)
                supplied = parsed[key]
                if supplied isa AbstractString && startswith(String(supplied), "sha256:")
                    return String(supplied)
                end
            end
        end
    end
    payload = Any[]
    for key in sort!(collect(keys(parsed)); by=String)
        string_key = String(key)
        string_key == "artifact_hash" && continue
        push!(payload, (; key=string_key, value=_json_value(parsed[key])))
    end
    return _hash_payload(payload)
end

function _hash_payload(payload)
    return "sha256:" * bytes2hex(sha256(JSON3.write(payload)))
end

function _json_value(value)
    if value isa JSON3.Object || value isa AbstractDict
        return Dict(String(key) => _json_value(value[key]) for key in sort!(collect(keys(value)); by=String))
    elseif value isa NamedTuple
        return Dict(String(key) => _json_value(getfield(value, key))
                    for key in sort!(collect(keys(value)); by=String))
    elseif value isa AbstractVector
        return [_json_value(entry) for entry in value]
    elseif value isa Symbol
        return String(value)
    elseif value isa Rational
        return Kernel.rational_string(value)
    end
    return value
end

function _symbol_dict(object)
    object isa JSON3.Object || object isa AbstractDict ||
        throw(ArgumentError("provenance must be an object"))
    return Dict{Symbol, Any}(Symbol(key) => _json_value(object[key])
                             for key in keys(object))
end

function _strict_object(object, allowed::Set{Symbol}, path::AbstractString)
    object isa JSON3.Object || object isa AbstractDict ||
        throw(ArgumentError("$path must be a JSON object"))
    for key in keys(object)
        symbol = Symbol(key)
        symbol in allowed ||
            throw(ArgumentError("$path contains unknown field $(String(symbol))"))
    end
    for key in allowed
        haskey(object, key) || throw(ArgumentError("$path is missing key $(String(key))"))
    end
    return true
end

function _reject_trusted_metadata!(value, path::AbstractString)
    forbidden = Kernel.FORBIDDEN_TRUST_KEYS
    if value isa JSON3.Object || value isa AbstractDict
        for key in keys(value)
            symbol = Symbol(key)
            symbol in (:frontend_metadata, :solver_metadata, :provenance) && continue
            symbol in forbidden &&
                throw(ArgumentError("$path.$(String(symbol)) is forbidden in imported TSSOS artifacts"))
            _reject_trusted_metadata!(value[key], "$path.$(String(symbol))")
        end
    elseif value isa AbstractVector
        for (i, entry) in enumerate(value)
            _reject_trusted_metadata!(entry, "$path[$i]")
        end
    elseif value isa AbstractFloat
        throw(ArgumentError("$path contains floating JSON data"))
    end
    return true
end

function _bad_candidate_rejected(reason::Symbol, message::AbstractString,
                                 stage::Symbol,
                                 diagnostics::Dict{Symbol, Any})
    return getfield(parentmodule(@__MODULE__),
                    :BadCandidateRejected)(reason, String(message), stage,
                                           diagnostics)
end

function _failure_result(failure)
    return getfield(parentmodule(@__MODULE__), :FailureResult)(failure)
end

function _certified_result(certificate; artifacts=Dict{Symbol, Any}())
    return getfield(parentmodule(@__MODULE__),
                    :CertifiedResult)(certificate; artifacts)
end

end
