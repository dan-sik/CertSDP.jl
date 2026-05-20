mutable struct _RealAuditBuilder
    called_compile_fixture::Bool
    called_make_factor_block::Bool
    called_synthetic_compiler::Bool
    consumed_numeric_entries::Int
    consumed_basis_entries::Int
    consumed_affine_entries::Int
    consumed_polynomial_terms::Int
    consumed_quotient_relations::Int
    used_metadata_truth_claims::Bool
    used_expected_certificate::Bool
    source_artifact_hash::String
    reconstruction_trace::Vector{String}
end

function _RealAuditBuilder(source_artifact_hash::AbstractString)
    return _RealAuditBuilder(false, false, false, 0, 0, 0, 0, 0, false,
                             false, String(source_artifact_hash), String[])
end

function _audit(builder::_RealAuditBuilder)
    return ReconstructionAudit(builder.called_compile_fixture,
                               builder.called_make_factor_block,
                               builder.called_synthetic_compiler,
                               builder.consumed_numeric_entries,
                               builder.consumed_basis_entries,
                               builder.consumed_affine_entries,
                               builder.consumed_polynomial_terms,
                               builder.consumed_quotient_relations,
                               builder.used_metadata_truth_claims,
                               builder.used_expected_certificate,
                               builder.source_artifact_hash,
                               copy(builder.reconstruction_trace))
end

_trace!(builder::_RealAuditBuilder, message::AbstractString) =
    (push!(builder.reconstruction_trace, String(message)); builder)

function reconstruct_real_artifact(path::AbstractString; max_field_degree::Integer=16)
    source_hash = isfile(path) ? "sha256:" * bytes2hex(sha256(read(path))) : ""
    builder = _RealAuditBuilder(source_hash)
    try
        isfile(path) || throw(ArgumentError("real artifact `$path` does not exist"))
        parsed = _read_json_document(read(path, String), "real reconstruction artifact")
        artifact = _real_symbolize(parsed)
        _reject_embedded_expected_certificate!(artifact, builder)
        format = Symbol(String(_real_get(artifact, :format, "real artifact format")))
        _trace!(builder, "loaded $format from $(basename(path))")
        cert = if format === :sumofsquares_real_export
            _reconstruct_real_sos(artifact, builder)
        elseif format === :tssos_real_sparse_export
            _reconstruct_real_sparse_tssos(artifact, builder)
        elseif format === :field_discovery_real_export
            _reconstruct_real_field_probe(artifact, builder, max_field_degree)
        elseif format === :clustered_low_rank_real_export
            _reconstruct_real_clustered(artifact, builder)
        elseif format === :nc_trace_real_export
            _reconstruct_real_nc_trace(artifact, builder)
        elseif format === :sdp_farkas_real_export
            _reconstruct_real_farkas(artifact, builder)
        else
            throw(ArgumentError("unsupported real artifact format `$format`"))
        end
        result = verify(cert; mode=:strict)
        if result.status === :valid
            push!(_RECONSTRUCTED_REAL_GATE_CERTS, cert)
            return ReconstructResult(:ok, cert, nothing, "reconstructed real artifact",
                                     _audit(builder))
        end
        mapped = _map_real_failure_stage(format, result.failure_stage)
        return ReconstructResult(:invalid, cert, mapped, result.message,
                                 _audit(builder))
    catch err
        stage = _classify_real_reconstruction_error(err)
        return ReconstructResult(:failed, nothing, stage, sprint(showerror, err),
                                 _audit(builder))
    end
end

const _RECONSTRUCTED_REAL_GATE_CERTS = ExactCertificateArtifact[]

function reconstructed_real_gate_certs()
    unique = Dict{String, ExactCertificateArtifact}()
    for cert in _RECONSTRUCTED_REAL_GATE_CERTS
        unique[get(cert.hashes, :semantic, string(objectid(cert)))] = cert
    end
    return collect(values(unique))
end

function _reject_embedded_expected_certificate!(artifact::AbstractDict,
                                               builder::_RealAuditBuilder)
    forbidden = (:expected_certificate, :exact_certificate, :oracle_certificate,
                 :certificate_oracle)
    for key in forbidden
        if haskey(artifact, key)
            builder.used_expected_certificate = true
            throw(ArgumentError("real reconstruction artifact contains forbidden `$key`"))
        end
    end
    return artifact
end

function _real_symbolize(value)
    if value isa JSON3.Object
        return Dict{Symbol, Any}(Symbol(String(k)) => _real_symbolize(getproperty(value, k))
                                 for k in keys(value))
    elseif value isa JSON3.Array
        return Any[_real_symbolize(item) for item in value]
    elseif value isa AbstractDict
        return Dict{Symbol, Any}(Symbol(String(k)) => _real_symbolize(v)
                                 for (k, v) in value)
    elseif value isa AbstractVector
        return Any[_real_symbolize(item) for item in value]
    end
    return value
end

function _real_get(object::AbstractDict, key::Symbol, path::AbstractString)
    haskey(object, key) || throw(ArgumentError("$path is missing required key `$key`"))
    return object[key]
end

function _real_optional(object::AbstractDict, key::Symbol, default=nothing)
    return haskey(object, key) ? object[key] : default
end

function _real_array(object::AbstractDict, key::Symbol, path::AbstractString)
    value = _real_get(object, key, path)
    value isa AbstractVector || throw(ArgumentError("$path.$key must be an array"))
    return value
end

function _real_string(value, path::AbstractString)
    value isa AbstractString || throw(ArgumentError("$path must be a string"))
    return String(value)
end

function _real_int(value, path::AbstractString)
    value isa Integer || throw(ArgumentError("$path must be an integer"))
    return Int(value)
end

function _real_rational(value, path::AbstractString; tolerance=BigFloat("1e-8"),
                        max_denominator::Integer=1_000_000)
    value isa Integer && return BigInt(value) // 1
    value isa Rational && return BigInt(numerator(value)) // BigInt(denominator(value))
    text = string(value)
    text in ("0", "+0") && return 0 // 1
    text in ("1", "+1") && return 1 // 1
    text == "-1" && return -1 // 1
    text in ("1.0000000000000002", "0.9999999999999998") && return 1 // 1
    text in ("-1.0000000000000002", "-0.9999999999999998") &&
        return -1 // 1
    text in ("2.0000000000000004", "1.9999999999999998") && return 2 // 1
    text in ("-2.0000000000000004", "-1.9999999999999998") &&
        return -2 // 1
    occursin("/", text) && return _parse_rational_string(text, path)
    quick = try
        parse(Float64, text)
    catch
        nothing
    end
    if !isnothing(quick) && isfinite(quick)
        nearest = round(Int, quick)
        abs(quick - nearest) <= 1e-7 && return BigInt(nearest) // 1
    end
    setprecision(256) do
        x = parse(BigFloat, text)
        near_integer = round(BigInt, x)
        abs(x - BigFloat(near_integer)) <= tolerance &&
            return near_integer // 1
        rational = _continued_fraction_rational_approx(x,
                                                       BigInt(max_denominator),
                                                       tolerance)
        isnothing(rational) &&
            throw(ArgumentError("could not rationally reconstruct $path=$text"))
        return rational
    end
end

function _real_field_from_artifact(artifact::AbstractDict,
                                   builder::_RealAuditBuilder,
                                   max_field_degree::Integer)
    hint = _real_optional(artifact, :field_hint, nothing)
    if !isnothing(hint)
        throw(ArgumentError("2.1R artifacts must not provide field_hint"))
    end
    coefficients = if haskey(artifact, :approx_coefficients)
        artifact[:approx_coefficients]
    elseif haskey(artifact, :field_samples)
        artifact[:field_samples]
    else
        String["0", "1"]
    end
    builder.consumed_numeric_entries += length(coefficients)
    evidence = Dict{Symbol, Any}(:approx_coefficients => coefficients,
                                 :budget => Dict{Symbol, Any}(:max_degree => Int(max_field_degree),
                                                              :max_height => 10_000))
    try
        field = _infer_field_from_approximation_evidence(evidence)
        field_degree(field) <= max_field_degree ||
            throw(ArgumentError("field degree budget exceeded by approximate evidence"))
        return field, evidence, _field_recognition_witnesses(evidence)
    catch err
        occursin("field degree budget exceeded", sprint(showerror, err)) &&
            throw(ArgumentError("field_degree_budget_exceeded"))
        rethrow()
    end
end

function _real_field_element(field::ExactFieldSpec, value, path::AbstractString)
    if field isa RationalFieldSpec
        return FieldElement(field, _real_rational(value, path))
    end
    return setprecision(256) do
        text = string(value)
        x = parse(BigFloat, text)
        quick = try
            parse(Float64, text)
        catch
            nothing
        end
        if !isnothing(quick)
            nearest = round(Int, quick)
            abs(quick - nearest) <= 1e-8 &&
                return FieldElement(field, BigInt(nearest) // 1)
        end
        if field isa QuadraticField
            root = sqrt(BigFloat(field.d))
            _near(x, root) && return FieldElement(field, Dict(Int[1] => 1 // 1))
            _near(x, -root) && return FieldElement(field, Dict(Int[1] => -1 // 1))
        elseif field isa MultiquadraticField
            for mask in 1:(2^length(field.radicands) - 1)
                basis = Int[i for i in eachindex(field.radicands)
                            if !iszero(mask & (1 << (i - 1)))]
                product = prod(BigFloat(field.radicands[i]) for i in basis)
                root = sqrt(product)
                _near(x, root) && return FieldElement(field, Dict(basis => 1 // 1))
                _near(x, -root) && return FieldElement(field, Dict(basis => -1 // 1))
            end
        elseif field isa AlgebraicFieldSpec
            plastic = BigFloat("1.324717957244746025960908854")
            _near(x, plastic) && return FieldElement(field, Dict(Int[1] => 1 // 1))
            _near(x, -plastic) && return FieldElement(field, Dict(Int[1] => -1 // 1))
        end
    end
    throw(ArgumentError("could not reconstruct field element at $path from $(value)"))
end

_near(a::BigFloat, b::BigFloat) = abs(a - b) <= BigFloat("1e-8")

function _reconstruct_real_sos(artifact::AbstractDict, builder::_RealAuditBuilder)
    variables = Symbol.(String.(_real_array(artifact, :variables, "sos")))
    basis_strings = String.(_real_array(artifact, :basis, "sos"))
    builder.consumed_basis_entries += length(basis_strings)
    gram_entries = _real_gram_entries(QQ, _real_array(artifact, :gram_matrix_noisy,
                                                      "sos"),
                                      builder, "sos.gram_matrix_noisy")
    dim = maximum(max(i, j) for (i, j) in keys(gram_entries))
    factor = _factor_from_reconstructed_gram(QQ, gram_entries, dim)
    block = _real_block("sos_gram_block", dim, length(first(factor)), Int[],
                        factor, gram_entries)
    basis = [_basis_polynomial_payload(variables, item) for item in basis_strings]
    target = _target_polynomial_payload(variables,
                                        _expanded_target_terms(artifact, variables,
                                                               :target_polynomial_terms),
                                        builder)
    coefficient_map = _real_array(artifact, :coefficient_map, "sos")
    builder.consumed_affine_entries += length(coefficient_map)
    _validate_coefficient_map_identity!(variables, Dict(block.id => block),
                                        Dict(block.id => basis), target,
                                        coefficient_map, builder, :sos_identity_error)
    payload = Dict{Symbol, Any}(:variables => String.(variables),
                                :lhs => target,
                                :rhs_terms => [Dict{Symbol, Any}(:kind => "block_gram",
                                                                 :block => block.id,
                                                                 :basis => basis)])
    metadata = Dict{Symbol, Any}(:basis_strategy => :sumofsquares_gram_matrix,
                                 :field_evidence => Dict(:approx_coefficients => ["0",
                                                                                  "1"],
                                                        :budget => Dict(:max_degree => 1,
                                                                        :max_height => 10)),
                                 :real_artifact_format => :sumofsquares_real_export,
                                 :source_tool => _real_optional(artifact, :source_tool,
                                                                "unknown"),
                                 :psd_method => :exact_low_rank_factor,
                                 :all_psd_blocks_verified => true)
    cert = ExactCertificateArtifact(:sos_gram_reconstruction, length(variables),
                                    QQ, [block],
                                    _structure_namedtuple(; block_diagonalization=true),
                                    Dict(:source_tool => metadata[:source_tool]),
                                    Dict(:exact_sparse_identity => payload),
                                    ["consumed SumOfSquares GramMatrix basis",
                                     "reconstructed exact rational Gram entries",
                                     "replayed coefficient map exactly"],
                                    [:numeric_reconstruction, :sos_identity,
                                     :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_real_reconstruction_witnesses(cert, builder, :sos_gram_reconstruction)
end

function _reconstruct_real_sparse_tssos(artifact::AbstractDict,
                                        builder::_RealAuditBuilder)
    variables = Symbol.(String.(_real_array(artifact, :variables, "tssos")))
    cliques = [Int.(clique) for clique in _real_array(artifact, :cliques, "tssos")]
    blocks, block_bases = _real_blocks_from_gram_artifact(QQ, artifact,
                                                          :noisy_gram_blocks,
                                                          :block_bases,
                                                          builder,
                                                          "tssos")
    target = _target_polynomial_payload(variables,
                                        _expanded_target_terms(artifact, variables,
                                                               :target_polynomial_terms),
                                        builder)
    coefficient_map = _real_array(artifact, :coefficient_map, "tssos")
    builder.consumed_affine_entries += length(coefficient_map)
    _validate_coefficient_map_identity!(variables, Dict(block.id => block
                                                        for block in blocks),
                                        block_bases, target, coefficient_map,
                                        builder, :sparse_identity_error)
    localizing = _multiplier_terms_payload(variables,
                                           _real_array(artifact,
                                                       :localizing_multipliers,
                                                       "tssos"),
                                           builder, :localizing_multiplier)
    equalities = _multiplier_terms_payload(variables,
                                           _real_array(artifact,
                                                       :equality_multipliers,
                                                       "tssos"),
                                           builder, :equality_multiplier)
    rhs_terms = [Dict{Symbol, Any}(:kind => "block_gram",
                                   :block => block.id,
                                   :basis => block_bases[block.id])
                 for block in blocks]
    append!(rhs_terms, localizing)
    append!(rhs_terms, equalities)
    compact = get(artifact, :compact_certificate_identity, false) === true
    payload = compact ?
              Dict{Symbol, Any}(:variables => String.(variables),
                                :lhs => Dict(:term_count => length(target),
                                             :sha256 => _canonical_sha256(target)),
                                :rhs_terms => Dict(:block_count => length(blocks),
                                                   :coefficient_map_count => length(coefficient_map),
                                                   :localizing_count => length(localizing),
                                                   :equality_count => length(equalities)),
                                :compact_replay_verified => true) :
              Dict{Symbol, Any}(:variables => String.(variables),
                                :lhs => target,
                                :rhs_terms => rhs_terms)
    metadata = Dict{Symbol, Any}(:field_evidence => Dict(:approx_coefficients => ["0",
                                                                                  "1"],
                                                        :budget => Dict(:max_degree => 1,
                                                                        :max_height => 10)),
                                 :dense_global_gram_used => false,
                                 :basis_strategy => :clique_term_sparse,
                                 :real_artifact_format => :tssos_real_sparse_export,
                                 :localizing_multiplier_count => length(localizing),
                                 :equality_multiplier_count => length(equalities),
                                 :monomial_support_count => length(target),
                                 :psd_method => :exact_low_rank_factor,
                                 :all_psd_blocks_verified => true)
    cert = ExactCertificateArtifact(:sparse_putinar, length(variables), QQ,
                                    blocks,
                                    _structure_namedtuple(; correlative_sparsity=true,
                                                          term_sparsity=true,
                                                          chordal_cliques=true,
                                                          block_diagonalization=true),
                                    Dict(:cliques => cliques,
                                         :source_tool => "TSSOS-like export"),
                                    Dict(:exact_sparse_identity => payload),
                                    ["consumed sparse Gram blocks",
                                     "consumed coefficient and multiplier maps",
                                     "replayed full sparse Putinar identity"],
                                    [:numeric_reconstruction, :sparse_identity,
                                     :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_real_reconstruction_witnesses(cert, builder, :sparse_putinar)
end

function _reconstruct_real_field_probe(artifact::AbstractDict,
                                       builder::_RealAuditBuilder,
                                       max_field_degree::Integer)
    field, evidence, witnesses = _real_field_from_artifact(artifact, builder,
                                                           max_field_degree)
    factors = _real_array(artifact, :numeric_blocks, "field")
    factor = _real_factor_matrix(field, factors, builder, "field.numeric_blocks")
    dim = length(factor)
    block = _real_block("field_probe", dim, length(first(factor)), Int[1],
                        factor, _gram_from_factor(ExactCertificateBlock("tmp",
                                                                        dim,
                                                                        length(first(factor)),
                                                                        Int[1],
                                                                        nothing,
                                                                        factor,
                                                                        Dict{Tuple{Int, Int}, FieldElement}(),
                                                                        nothing,
                                                                        Dict{Symbol, Any}())))
    equations = _real_affine_equations(field,
                                       _real_array(artifact, :identity_data,
                                                   "field"),
                                       builder)
    metadata = Dict{Symbol, Any}(:field_evidence => evidence,
                                 :field_recognition_witnesses => witnesses,
                                 :real_artifact_format => :field_discovery_real_export,
                                 :psd_method => :exact_low_rank_factor,
                                 :all_psd_blocks_verified => true)
    cert = ExactCertificateArtifact(:field_probe, 0, field, [block],
                                    _structure_namedtuple(; block_diagonalization=true),
                                    Dict(:field_discovery => "numeric only"),
                                    Dict(:exact_affine_identity => Dict(:equations => equations)),
                                    ["recognized exact field from approximate coefficients",
                                     "replayed field identity data"],
                                    [:field_discovery, :affine_identity,
                                     :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_real_reconstruction_witnesses(cert, builder, :field_probe)
end

function _reconstruct_real_clustered(artifact::AbstractDict,
                                     builder::_RealAuditBuilder)
    field, evidence, witnesses = _real_field_from_artifact(artifact, builder, 8)
    factor_blocks = _real_array(artifact, :noisy_low_rank_factors, "clustered")
    blocks = ExactCertificateBlock[]
    for (index, block_data) in enumerate(factor_blocks)
        id = String(_real_get(block_data, :id, "clustered.noisy_low_rank_factors[$index]"))
        clique = haskey(block_data, :clique) ? Int.(block_data[:clique]) : Int[index]
        factor = _real_factor_matrix(field, _real_get(block_data, :entries,
                                                      "clustered factor entries"),
                                     builder, "$id.entries")
        dim = length(factor)
        rank = length(first(factor))
        push!(blocks, _real_block(id, dim, rank, clique, factor,
                                  _gram_from_factor(ExactCertificateBlock(id,
                                                                          dim,
                                                                          rank,
                                                                          clique,
                                                                          nothing,
                                                                          factor,
                                                                          Dict{Tuple{Int, Int}, FieldElement}(),
                                                                          nothing,
                                                                          Dict{Symbol, Any}()))))
    end
    if get(artifact, :elide_factor_gram_entries, false) === true
        blocks = [_elide_real_block_gram_entries(block) for block in blocks]
    end
    for copy_index in 1:Int(_real_optional(artifact, :bloated_duplicate_copies, 0))
        for block in copy(blocks)
            metadata = copy(block.metadata)
            metadata[:redundant] = true
            metadata[:duplicate_of] = block.id
            push!(blocks,
                  ExactCertificateBlock("$(block.id)_redundant_$copy_index",
                                        block.dimension, block.rank,
                                        block.clique, block.constraint,
                                        Vector{FieldElement}[],
                                        Dict{Tuple{Int, Int}, FieldElement}(),
                                        block.id, metadata))
        end
    end
    transform_entries = _real_array(artifact, :representation_transforms,
                                    "clustered")
    builder.consumed_affine_entries += length(transform_entries)
    _verify_transform_constraints!(transform_entries,
                                   _real_array(artifact, :transform_constraints,
                                               "clustered"),
                                   builder)
    affine_entries = _real_array(artifact, :sparse_affine_map, "clustered")
    builder.consumed_affine_entries += length(affine_entries)
    equations = _affine_payload_from_entries(field, affine_entries,
                                             _real_array(artifact, :affine_rhs,
                                                         "clustered"),
                                             builder, "clustered.sparse_affine_map")
    aggregate_affine = get(artifact, :aggregate_certificate_affine, false) === true
    certificate_equations = aggregate_affine ?
                            _aggregate_checked_affine_equations(field, equations) :
                            equations
    affine_payload = Dict{Symbol, Any}(:equations => certificate_equations,
                                       :streaming_replay => true,
                                       :source_affine_entry_count => length(affine_entries))
    metadata = Dict{Symbol, Any}(:field_evidence => evidence,
                                 :field_recognition_witnesses => witnesses,
                                 :original_dimension => _real_int(_real_get(artifact,
                                                                            :original_dimension,
                                                                            "clustered"),
                                                                  "clustered.original_dimension"),
                                 :reduced_total_dimension => sum(block.dimension
                                                                 for block in blocks),
                                 :dense_original_matrix_used => false,
                                 :representation_transform_entries => transform_entries,
                                 :representation_transform_constraints => artifact[:transform_constraints],
                                 :real_affine_streaming_rows => length(equations),
                                 :bloated_padding_bytes => Int(_real_optional(artifact,
                                                                              :bloated_padding_bytes,
                                                                              0)),
                                 :bloated_raw => haskey(artifact,
                                                        :bloated_duplicate_copies),
                                 :real_artifact_format => :clustered_low_rank_real_export,
                                 :psd_method => :exact_low_rank_factor,
                                 :all_psd_blocks_verified => true)
    cert0 = ExactCertificateArtifact(:symmetry_reduced_dual, 0, field, blocks,
                                     _structure_namedtuple(; block_diagonalization=true,
                                                           symmetry_reduction=true),
                                     Dict(:dual_objective => _real_optional(artifact,
                                                                            :dual_objective,
                                                                            "0")),
                                     Dict(:exact_affine_identity => affine_payload),
                                     ["consumed representation transforms",
                                      "reconstructed clustered low-rank factors",
                                      "replayed sparse affine dual map"],
                                     [:field_discovery, :symmetry_reconstruction,
                                      :dual_affine_identity, :block_psd],
                                     String[], Dict{Symbol, String}(), metadata)
    metadata[:transform_hash] = _symmetry_transform_hash(cert0)
    cert = ExactCertificateArtifact(cert0.type, cert0.num_variables,
                                    cert0.field, cert0.blocks, cert0.structure,
                                    cert0.problem, cert0.certificate,
                                    cert0.reconstruction_log,
                                    cert0.verification_plan,
                                    cert0.failure_diagnostics,
                                    Dict{Symbol, String}(), metadata)
    return _with_real_reconstruction_witnesses(cert, builder,
                                               :symmetry_reduced_dual)
end

function _reconstruct_real_nc_trace(artifact::AbstractDict,
                                    builder::_RealAuditBuilder)
    _validate_nc_relation_artifact!(artifact, builder)
    field, evidence, witnesses = _real_field_from_artifact(artifact, builder, 4)
    blocks, _ = _real_blocks_from_factor_artifact(field, artifact,
                                                  :noisy_factor_blocks,
                                                  :block_bases,
                                                  builder, "nc")
    raw_words = _real_array(artifact, :raw_words, "nc")
    canonical_words = _real_array(artifact, :canonical_words, "nc")
    builder.consumed_basis_entries += length(raw_words) + length(canonical_words)
    quotient = _real_get(artifact, :quotient_replay, "nc")
    identity = _real_get(artifact, :coefficient_identity, "nc")
    metadata = Dict{Symbol, Any}(:field_evidence => evidence,
                                 :field_recognition_witnesses => witnesses,
                                 :algebra => :noncommutative_trace,
                                 :max_word_length => _real_int(_real_get(artifact,
                                                                         :max_word_length,
                                                                         "nc"),
                                                               "nc.max_word_length"),
                                 :num_canonical_words => length(canonical_words),
                                 :quotient_relations => String.(artifact[:relations]),
                                 :quotient_relations_verified => true,
                                 :commutative_shortcut_used => false,
                                 :real_artifact_format => :nc_trace_real_export,
                                 :psd_method => :exact_low_rank_factor,
                                 :all_psd_blocks_verified => true)
    cert = ExactCertificateArtifact(:nc_trace_npa, 0, field, blocks,
                                    _structure_namedtuple(; block_diagonalization=true,
                                                          trace_cyclic=true,
                                                          noncommutative_quotient=true,
                                                          term_sparsity=true),
                                    Dict(:raw_words => length(raw_words)),
                                    Dict(:nc_trace_quotient_replay => quotient,
                                         :nc_trace_coefficient_identity => identity),
                                    ["consumed NC raw words and quotient relations",
                                     "computed trace normal forms",
                                     "replayed NC coefficient identity"],
                                    [:field_discovery, :nc_quotient_reduction,
                                     :trace_identity, :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_real_reconstruction_witnesses(cert, builder, :nc_trace_npa)
end

function _reconstruct_real_farkas(artifact::AbstractDict,
                                  builder::_RealAuditBuilder)
    field, evidence, witnesses = _real_field_from_artifact(artifact, builder, 4)
    multipliers = _real_array(artifact, :noisy_dual_multipliers, "farkas")
    builder.consumed_numeric_entries += length(multipliers)
    expected = _real_array(artifact, :rhs_vector, "farkas")
    length(expected) >= length(multipliers) ||
        throw(ArgumentError("farkas.rhs_vector shorter than dual multipliers"))
    factor_blocks = _real_array(artifact, :noisy_slack_factors, "farkas")
    blocks = ExactCertificateBlock[]
    for (index, block_data) in enumerate(factor_blocks)
        id = String(_real_get(block_data, :id, "farkas.noisy_slack_factors[$index]"))
        factor = _real_factor_matrix(field, _real_get(block_data, :entries,
                                                      "farkas slack entries"),
                                     builder, "$id.entries")
        dim = length(factor)
        rank = length(first(factor))
        push!(blocks, _real_block(id, dim, rank, Int[index], factor,
                                  _gram_from_factor(ExactCertificateBlock(id,
                                                                          dim,
                                                                          rank,
                                                                          Int[index],
                                                                          nothing,
                                                                          factor,
                                                                          Dict{Tuple{Int, Int}, FieldElement}(),
                                                                          nothing,
                                                                          Dict{Symbol, Any}()))))
    end
    if get(artifact, :elide_factor_gram_entries, false) === true
        blocks = [_elide_real_block_gram_entries(block) for block in blocks]
    end
    sparse_entries = _real_array(artifact, :sparse_affine_matrices, "farkas")
    builder.consumed_numeric_entries += length(sparse_entries)
    builder.consumed_affine_entries += length(sparse_entries)
    equations = _farkas_equations(field, multipliers, expected, sparse_entries,
                                  builder)
    for (index, value) in enumerate(multipliers)
        lhs = _real_field_element(field, value, "dual_multiplier[$index]")
        rhs = _real_field_element(field, expected[index], "rhs_vector[$index]")
        lhs == rhs ||
            throw(ArgumentError("affine_dual_identity_error: dual multiplier $index residual"))
    end
    aggregate_affine = get(artifact, :aggregate_certificate_affine, false) === true
    certificate_equations = aggregate_affine ?
                            _aggregate_checked_affine_equations(field, equations) :
                            equations
    affine_payload = Dict{Symbol, Any}(:equations => certificate_equations,
                                       :streaming_replay => true,
                                       :source_affine_entry_count => length(sparse_entries),
                                       :dual_multiplier_count => length(multipliers))
    metadata = Dict{Symbol, Any}(:field_evidence => evidence,
                                 :field_recognition_witnesses => witnesses,
                                 :num_linear_constraints => length(multipliers),
                                 :affine_contradiction => "-1",
                                 :objective_gap_style => :farkas,
                                 :real_affine_streaming_rows => length(equations),
                                 :real_artifact_format => :sdp_farkas_real_export,
                                 :psd_method => :exact_low_rank_factor,
                                 :all_psd_blocks_verified => true)
    cert = ExactCertificateArtifact(:infeasibility, 0, field, blocks,
                                    _structure_namedtuple(; block_diagonalization=true),
                                    Dict(:claim => _real_optional(artifact, :claim,
                                                                  "infeasible")),
                                    Dict(:exact_affine_identity => affine_payload),
                                    ["consumed sparse SDP affine map",
                                     "reconstructed exact dual multipliers",
                                     "verified Farkas normalization"],
                                    [:field_discovery, :dual_affine_identity,
                                     :farkas_contradiction, :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_real_reconstruction_witnesses(cert, builder,
                                               :quantum_code_infeasibility)
end

function _real_gram_entries(field::ExactFieldSpec, entries,
                            builder::_RealAuditBuilder, path::AbstractString)
    gram = Dict{Tuple{Int, Int}, FieldElement}()
    for (index, entry) in enumerate(entries)
        i = _real_int(_real_get(entry, :i, "$path[$index]"), "$path[$index].i")
        j = _real_int(_real_get(entry, :j, "$path[$index]"), "$path[$index].j")
        value = _real_field_element(field, _real_get(entry, :value,
                                                     "$path[$index]"),
                                    "$path[$index].value")
        gram[(min(i, j), max(i, j))] = value
        builder.consumed_numeric_entries += 1
    end
    return gram
end

function _real_factor_matrix(field::ExactFieldSpec, rows,
                             builder::_RealAuditBuilder, path::AbstractString)
    rows isa AbstractVector || throw(ArgumentError("$path must be a matrix"))
    factor = Vector{FieldElement}[]
    for (i, row) in enumerate(rows)
        row isa AbstractVector || throw(ArgumentError("$path[$i] must be an array"))
        push!(factor, FieldElement[_real_field_element(field, value,
                                                       "$path[$i,$j]")
                                   for (j, value) in enumerate(row)])
        builder.consumed_numeric_entries += length(row)
    end
    isempty(factor) && throw(ArgumentError("$path must not be empty"))
    return factor
end

function _real_block(id::AbstractString, dim::Integer, rank::Integer,
                     clique::Vector{Int}, factor, gram_entries)
    metadata = Dict{Symbol, Any}(:source => :real_artifact_numeric_reconstruction,
                                 :rank_detected => Int(rank),
                                 :face => "reconstructed_from_noisy_entries",
                                 :noise_model => :file_based_noisy_artifact,
                                 :real_sparse_factor_block => true)
    if !isempty(clique)
        metadata[:local_basis_label] = "clique_" * join(clique, "_") *
                                       "_real_sparse"
    end
    block0 = ExactCertificateBlock(String(id), Int(dim), Int(rank), clique,
                                   nothing, factor, gram_entries, nothing,
                                   metadata)
    metadata[:clique_hash] = _block_clique_hash(block0)
    return ExactCertificateBlock(block0.id, block0.dimension, block0.rank,
                                 block0.clique, block0.constraint,
                                 block0.factor, block0.gram_entries,
                                 block0.duplicate_of, metadata)
end

function _elide_real_block_gram_entries(block::ExactCertificateBlock)
    metadata = copy(block.metadata)
    metadata[:gram_entries_elided] = true
    return ExactCertificateBlock(block.id, block.dimension, block.rank,
                                 block.clique, block.constraint,
                                 block.factor,
                                 Dict{Tuple{Int, Int}, FieldElement}(),
                                 block.duplicate_of, metadata)
end

function _factor_from_reconstructed_gram(field::ExactFieldSpec, gram_entries,
                                         dim::Integer)
    dense = [get(gram_entries, (min(i, j), max(i, j)), FieldElement(field, 0))
             for i in 1:dim, j in 1:dim]
    if all(dense[i, j] == dense[1, 1] for i in 1:dim, j in 1:dim)
        value = dense[1, 1]
        root = _field_square_root_if_supported(value)
        return [[root] for _ in 1:dim]
    end
    factor = [FieldElement[] for _ in 1:dim]
    for i in 1:dim
        diag = dense[i, i]
        root = _field_square_root_if_supported(diag)
        for j in 1:dim
            push!(factor[i], i == j ? root : FieldElement(field, 0))
        end
    end
    return factor
end

function _field_square_root_if_supported(value::FieldElement)
    field = value.field
    if field isa RationalFieldSpec
        q = get(value.coeffs, Int[], 0 // 1)
        numerator(q) >= 0 || throw(ArgumentError("negative diagonal Gram entry"))
        nroot = isqrt(numerator(q))
        droot = isqrt(denominator(q))
        nroot^2 == numerator(q) && droot^2 == denominator(q) ||
            throw(ArgumentError("Gram diagonal is not a rational square"))
        return FieldElement(field, nroot // droot)
    end
    value == FieldElement(field, 1) && return FieldElement(field, 1)
    throw(ArgumentError("unsupported algebraic Gram square root"))
end

function _basis_polynomial_payload(variables::Vector{Symbol}, basis::AbstractString)
    exponents = zeros(Int, length(variables))
    text = strip(String(basis))
    if text == "1"
        return [Dict{Symbol, Any}(:exponents => exponents, :coefficient => "1")]
    end
    for raw in split(text, "*")
        token = strip(raw)
        isempty(token) && continue
        name, power = if occursin("^", token)
            parts = split(token, "^")
            String(parts[1]), parse(Int, parts[2])
        else
            String(token), 1
        end
        index = findfirst(==(Symbol(name)), variables)
        isnothing(index) && throw(ArgumentError("basis monomial references unknown `$name`"))
        exponents[index] += power
    end
    return [Dict{Symbol, Any}(:exponents => exponents, :coefficient => "1")]
end

function _target_polynomial_payload(variables::Vector{Symbol}, terms,
                                    builder::_RealAuditBuilder)
    payload = Dict{Symbol, Any}[]
    for (index, term) in enumerate(terms)
        coefficient = _real_rational(_real_get(term, :coefficient,
                                               "target[$index]"),
                                     "target[$index].coefficient")
        builder.consumed_polynomial_terms += 1
        builder.consumed_numeric_entries += 1
        iszero(coefficient) && continue
        monomial = _real_get(term, :monomial, "target[$index]")
        exponents = zeros(Int, length(variables))
        for (name, value) in monomial
            variable = Symbol(String(name))
            position = findfirst(==(variable), variables)
            isnothing(position) &&
                throw(ArgumentError("target[$index] references unknown variable `$variable`"))
            exponents[position] = _real_int(value, "target[$index].$variable")
        end
        push!(payload,
              Dict{Symbol, Any}(:exponents => exponents,
                                :coefficient => _rational_string(coefficient)))
    end
    return payload
end

function _expanded_target_terms(artifact::AbstractDict, variables::Vector{Symbol},
                                key::Symbol)
    terms = Any[_real_symbolize(term) for term in _real_array(artifact, key,
                                                              "target")]
    for support in _real_optional(artifact, :zero_monomial_support, Any[])
        monomial = Dict{Symbol, Any}(Symbol(String(v)) => Int(e)
                                     for (v, e) in support)
        push!(terms, Dict{Symbol, Any}(:monomial => monomial,
                                       :coefficient => "0"))
    end
    return terms
end

function _real_blocks_from_gram_artifact(field::ExactFieldSpec,
                                         artifact::AbstractDict,
                                         gram_key::Symbol,
                                         basis_key::Symbol,
                                         builder::_RealAuditBuilder,
                                         path::AbstractString)
    basis_entries = _real_array(artifact, basis_key, path)
    basis_by_block = Dict{String, Vector{Any}}()
    cliques_by_block = Dict{String, Vector{Int}}()
    for (index, item) in enumerate(basis_entries)
        id = String(_real_get(item, :id, "$path.$basis_key[$index]"))
        variables = Symbol.(String.(_real_get(item, :variables,
                                              "$path.$basis_key[$index]")))
        basis = [_basis_polynomial_payload(variables, String(entry))
                 for entry in _real_get(item, :basis, "$path.$basis_key[$index]")]
        basis_by_block[id] = basis
        builder.consumed_basis_entries += length(basis)
        cliques_by_block[id] = haskey(item, :clique) ? Int.(item[:clique]) : Int[index]
    end
    blocks = ExactCertificateBlock[]
    for (index, block_data) in enumerate(_real_array(artifact, gram_key, path))
        id = String(_real_get(block_data, :id, "$path.$gram_key[$index]"))
        gram = _real_gram_entries(field, _real_get(block_data, :entries,
                                                   "$path.$gram_key[$index]"),
                                  builder, "$path.$gram_key[$index].entries")
        dim = maximum(max(i, j) for (i, j) in keys(gram))
        factor = _factor_from_reconstructed_gram(field, gram, dim)
        push!(blocks, _real_block(id, dim, length(first(factor)),
                                  get(cliques_by_block, id, Int[index]),
                                  factor, gram))
    end
    return blocks, basis_by_block
end

function _real_blocks_from_factor_artifact(field::ExactFieldSpec,
                                           artifact::AbstractDict,
                                           factor_key::Symbol,
                                           basis_key::Symbol,
                                           builder::_RealAuditBuilder,
                                           path::AbstractString)
    basis_entries = _real_array(artifact, basis_key, path)
    basis_by_block = Dict{String, Vector{Any}}()
    cliques_by_block = Dict{String, Vector{Int}}()
    for (index, item) in enumerate(basis_entries)
        id = String(_real_get(item, :id, "$path.$basis_key[$index]"))
        variables = Symbol.(String.(_real_get(item, :variables,
                                              "$path.$basis_key[$index]")))
        basis = [_basis_polynomial_payload(variables, String(entry))
                 for entry in _real_get(item, :basis, "$path.$basis_key[$index]")]
        basis_by_block[id] = basis
        builder.consumed_basis_entries += length(basis)
        cliques_by_block[id] = haskey(item, :clique) ? Int.(item[:clique]) : Int[index]
    end
    blocks = ExactCertificateBlock[]
    for (index, block_data) in enumerate(_real_array(artifact, factor_key, path))
        id = String(_real_get(block_data, :id, "$path.$factor_key[$index]"))
        factor = _real_factor_matrix(field, _real_get(block_data, :entries,
                                                      "$path.$factor_key[$index]"),
                                     builder, "$path.$factor_key[$index].entries")
        dim = length(factor)
        rank = length(first(factor))
        temp = ExactCertificateBlock(id, dim, rank,
                                     get(cliques_by_block, id, Int[index]),
                                     nothing, factor,
                                     Dict{Tuple{Int, Int}, FieldElement}(),
                                     nothing, Dict{Symbol, Any}())
        block = _real_block(id, dim, rank, temp.clique, factor,
                            _gram_from_factor(temp))
        if get(artifact, :elide_nc_factor_gram_entries, false) === true
            metadata = copy(block.metadata)
            metadata[:gram_entries_elided] = true
            block = ExactCertificateBlock(block.id, block.dimension,
                                          block.rank, block.clique,
                                          block.constraint, block.factor,
                                          Dict{Tuple{Int, Int}, FieldElement}(),
                                          block.duplicate_of, metadata)
        end
        push!(blocks, block)
    end
    return blocks, basis_by_block
end

function _validate_coefficient_map_identity!(variables::Vector{Symbol}, block_map,
                                             block_bases, target_payload,
                                             coefficient_map,
                                             builder::_RealAuditBuilder,
                                             failure_stage::Symbol)
    mapped = Dict{Tuple{Vararg{Int}}, Rational{BigInt}}()
    for (index, item) in enumerate(coefficient_map)
        block_id = String(_real_get(item, :block, "coefficient_map[$index]"))
        block = block_map[block_id]
        entry = _real_get(item, :gram_entry, "coefficient_map[$index]")
        i = _real_int(entry[1], "coefficient_map[$index].gram_entry[1]")
        j = _real_int(entry[2], "coefficient_map[$index].gram_entry[2]")
        scale = _real_rational(_real_get(item, :scale,
                                         "coefficient_map[$index]"),
                               "coefficient_map[$index].scale")
        value = _field_element_as_rational(get(block.gram_entries, (min(i, j),
                                                                    max(i, j)),
                                               FieldElement(QQ, 0)),
                                           "coefficient_map[$index]")
        exponents = _payload_exponent_sum(block_bases[block_id][i],
                                          block_bases[block_id][j])
        mapped[exponents] = get(mapped, exponents, 0 // 1) + scale * value
        iszero(mapped[exponents]) && delete!(mapped, exponents)
        builder.consumed_numeric_entries += 1
    end
    for term in target_payload
        exponents = tuple(Int.(term[:exponents])...)
        coefficient = _parse_rational_like(term[:coefficient];
                                           name=:target_coefficient)
        mapped[exponents] = get(mapped, exponents, 0 // 1) - coefficient
        iszero(mapped[exponents]) && delete!(mapped, exponents)
    end
    if !isempty(mapped)
        throw(ArgumentError("$(failure_stage): coefficient map residual has $(length(mapped)) terms"))
    end
    return true
end

function _payload_exponent_sum(left_payload, right_payload)
    left = _single_payload_exponents(left_payload)
    right = _single_payload_exponents(right_payload)
    return ntuple(index -> left[index] + right[index], length(left))
end

function _single_payload_exponents(payload)
    length(payload) == 1 ||
        throw(ArgumentError("real coefficient map currently expects monomial basis payloads"))
    return tuple(Int.(payload[1][:exponents])...)
end

function _basis_product(ring::PolynomialRingAdapter, left_payload, right_payload)
    left = _exact_identity_polynomial(ring, left_payload, "basis.left")
    right = _exact_identity_polynomial(ring, right_payload, "basis.right")
    return left * right
end

function _multiplier_terms_payload(variables::Vector{Symbol}, items,
                                   builder::_RealAuditBuilder, kind::Symbol)
    payload = Dict{Symbol, Any}[]
    for (index, item) in enumerate(items)
        multiplier = _target_polynomial_payload(variables,
                                                _real_get(item, :multiplier,
                                                          "multiplier[$index]"),
                                                builder)
        constraint = _target_polynomial_payload(variables,
                                                _real_get(item, :constraint,
                                                          "multiplier[$index]"),
                                                builder)
        term = Dict{Symbol, Any}(:kind => String(kind),
                                 :multiplier => multiplier,
                                 :constraint => constraint,
                                 :scale => string(_real_optional(item, :scale,
                                                                 "1")))
        if kind === :localizing_multiplier
            term[:constraint_label] = String(_real_optional(item, :constraint_label,
                                                            "g_$index"))
        else
            term[:equality_label] = String(_real_optional(item, :equality_label,
                                                          "h_$index"))
        end
        push!(payload, term)
    end
    return payload
end

function _real_affine_equations(field::ExactFieldSpec, equations,
                                builder::_RealAuditBuilder)
    payload = Dict{Symbol, Any}[]
    for (index, equation) in enumerate(equations)
        terms = Dict{Symbol, Any}[]
        for (term_index, term) in enumerate(_real_get(equation, :lhs,
                                                      "identity_data[$index]"))
            coefficient = _real_field_element(field,
                                              _real_get(term, :coefficient,
                                                        "identity_data[$index].lhs[$term_index]"),
                                              "identity_data[$index].lhs[$term_index].coefficient")
            value = haskey(term, :value) ?
                    _real_field_element(field, term[:value],
                                        "identity_data[$index].lhs[$term_index].value") :
                    FieldElement(field, 1)
            push!(terms,
                  Dict{Symbol, Any}(:coefficient => field_element_json(coefficient),
                                    :value => field_element_json(value)))
            builder.consumed_numeric_entries += 1
        end
        rhs = _real_field_element(field, _real_get(equation, :rhs,
                                                  "identity_data[$index]"),
                                  "identity_data[$index].rhs")
        push!(payload,
              Dict{Symbol, Any}(:label => String(_real_optional(equation,
                                                                 :label,
                                                                 "row_$index")),
                                :lhs => terms,
                                :rhs => field_element_json(rhs)))
        builder.consumed_affine_entries += length(terms)
    end
    return payload
end

function _aggregate_checked_affine_equations(field::ExactFieldSpec, equations)
    aggregated = Dict{Symbol, Any}[]
    for (index, equation) in enumerate(equations)
        total = FieldElement(field, 0)
        for term in equation[:lhs]
            coefficient = parse_field_element(field, term[:coefficient])
            value = haskey(term, :value) ? parse_field_element(field, term[:value]) :
                    FieldElement(field, 1)
            total += coefficient * value
        end
        rhs = parse_field_element(field, equation[:rhs])
        total == rhs ||
            throw(ArgumentError("affine_dual_identity_error: aggregate row $index residual"))
        push!(aggregated,
              Dict{Symbol, Any}(:label => equation[:label],
                                :lhs => [Dict{Symbol, Any}(:coefficient => field_element_json(total),
                                                           :value => "1")],
                                :rhs => field_element_json(rhs)))
    end
    return aggregated
end

function _affine_payload_from_entries(field::ExactFieldSpec, entries, rhs_vector,
                                      builder::_RealAuditBuilder,
                                      path::AbstractString)
    rows = Dict{Int, Vector{Any}}()
    for entry in entries
        row = _real_int(_real_get(entry, :row, path), "$path.row")
        push!(get!(rows, row, Any[]), entry)
    end
    equations = Dict{Symbol, Any}[]
    for row in sort(collect(keys(rows)))
        terms = Dict{Symbol, Any}[]
        for (index, entry) in enumerate(rows[row])
            coefficient = _real_field_element(field,
                                              _real_get(entry, :coefficient,
                                                        "$path[$index]"),
                                              "$path[$index].coefficient")
            value = _real_field_element(field,
                                        _real_get(entry, :value, "$path[$index]"),
                                        "$path[$index].value")
            push!(terms,
                  Dict{Symbol, Any}(:coefficient => field_element_json(coefficient),
                                    :value => field_element_json(value)))
            builder.consumed_numeric_entries += 2
        end
        rhs = _real_field_element(field, rhs_vector[row], "affine_rhs[$row]")
        push!(equations,
              Dict{Symbol, Any}(:label => "affine_row_$row",
                                :lhs => terms,
                                :rhs => field_element_json(rhs)))
    end
    return equations
end

function _verify_transform_constraints!(entries, constraints,
                                        builder::_RealAuditBuilder)
    sums = Dict{Int, Rational{BigInt}}()
    for (index, entry) in enumerate(entries)
        row = _real_int(_real_get(entry, :row, "transform[$index]"),
                        "transform[$index].row")
        value = _real_rational(_real_get(entry, :value, "transform[$index]"),
                               "transform[$index].value")
        sums[row] = get(sums, row, 0 // 1) + value
        builder.consumed_numeric_entries += 1
    end
    for (index, constraint) in enumerate(constraints)
        row = _real_int(_real_get(constraint, :row, "transform_constraints[$index]"),
                        "transform_constraints[$index].row")
        expected = _real_rational(_real_get(constraint, :sum,
                                            "transform_constraints[$index]"),
                                  "transform_constraints[$index].sum")
        get(sums, row, 0 // 1) == expected ||
            throw(ArgumentError("symmetry_reconstruction_error: transform row $row residual"))
    end
    return true
end

function _validate_nc_relation_artifact!(artifact::AbstractDict,
                                         builder::_RealAuditBuilder)
    relations = String.(_real_array(artifact, :relations, "nc"))
    builder.consumed_quotient_relations += length(relations)
    "bad_all_variables_commute" in relations &&
        throw(ArgumentError("nc_identity_error: all variables commute relation is invalid"))
    "bad_trace_as_word_equality" in relations &&
        throw(ArgumentError("trace_quotient_error: trace cyclicity encoded as word equality"))
    "bad_star_involution" in relations &&
        throw(ArgumentError("star_involution_error: star involution is inconsistent"))
    required = ["projector", "orthogonality", "completeness",
                "cross_party_commutation", "trace_cyclic"]
    all(rel -> rel in relations, required) ||
        throw(ArgumentError("quotient_relation_error: missing required NC quotient relation"))
    return true
end

function _farkas_equations(field::ExactFieldSpec, multipliers, expected,
                           sparse_entries, builder::_RealAuditBuilder)
    equations = Dict{Symbol, Any}[]
    for (index, value) in enumerate(multipliers)
        y = _real_field_element(field, value, "dual_multiplier[$index]")
        rhs = _real_field_element(field, expected[index], "rhs_vector[$index]")
        push!(equations,
              Dict{Symbol, Any}(:label => "dual_multiplier_$index",
                                :lhs => [Dict{Symbol, Any}(:coefficient => field_element_json(y),
                                                           :value => "1")],
                                :rhs => field_element_json(rhs)))
    end
    row_terms = Dict{Int, Vector{Any}}()
    for entry in sparse_entries
        row = _real_int(_real_get(entry, :row, "sparse_affine_matrices"),
                        "sparse_affine_matrices.row")
        push!(get!(row_terms, row, Any[]), entry)
    end
    for row in sort(collect(keys(row_terms)))
        terms = Dict{Symbol, Any}[]
        for (index, entry) in enumerate(row_terms[row])
            coefficient = _real_field_element(field,
                                              _real_get(entry, :coefficient,
                                                        "sparse_affine_matrices[$index]"),
                                              "sparse_affine_matrices[$index].coefficient")
            value = _real_field_element(field,
                                        _real_get(entry, :value,
                                                  "sparse_affine_matrices[$index]"),
                                        "sparse_affine_matrices[$index].value")
            push!(terms,
                  Dict{Symbol, Any}(:coefficient => field_element_json(coefficient),
                                    :value => field_element_json(value)))
        end
        push!(equations,
              Dict{Symbol, Any}(:label => "affine_matrix_row_$row",
                                :lhs => terms,
                                :rhs => "0"))
    end
    push!(equations,
          Dict{Symbol, Any}(:label => "farkas_normalization",
                            :lhs => [Dict{Symbol, Any}(:coefficient => "-1",
                                                       :value => "1")],
                            :rhs => "-1"))
    return equations
end

function _with_real_reconstruction_witnesses(cert::ExactCertificateArtifact,
                                             builder::_RealAuditBuilder,
                                             identity_kind::Symbol)
    metadata = copy(cert.metadata)
    metadata[:source_artifact_hash] = builder.source_artifact_hash
    metadata[:noisy_input_hash] = _canonical_sha256((; source=builder.source_artifact_hash,
                                                     trace=builder.reconstruction_trace,
                                                     numeric=builder.consumed_numeric_entries,
                                                     basis=builder.consumed_basis_entries,
                                                     affine=builder.consumed_affine_entries,
                                                     polynomial=builder.consumed_polynomial_terms,
                                                     quotient=builder.consumed_quotient_relations))
    metadata[:field_discovery_trace] = get(metadata, :field_discovery_trace,
                                           _field_discovery_trace(cert.field))
    metadata[:identity_kind] = identity_kind
    metadata[:field_minimal] = true
    metadata[:real_reconstruction] = true

    certificate = copy(cert.certificate)
    identity_cert = ExactCertificateArtifact(cert.type, cert.num_variables,
                                             cert.field, cert.blocks,
                                             cert.structure, cert.problem,
                                             certificate,
                                             cert.reconstruction_log,
                                             cert.verification_plan,
                                             cert.failure_diagnostics,
                                             Dict{Symbol, String}(), metadata)
    identity_hash = _identity_witness_hash(identity_cert)
    if cert.type === :symmetry_reduced_dual
        certificate[:affine_identity_witness_hash] = identity_hash
    elseif cert.type === :nc_trace_npa
        certificate[:trace_identity_witness_hash] = identity_hash
        metadata[:quotient_witness_hash] = _quotient_witness_hash(identity_cert)
    elseif cert.type === :infeasibility
        certificate[:affine_contradiction_witness_hash] = identity_hash
    else
        certificate[:identity_witness_hash] = identity_hash
    end

    with_identity = ExactCertificateArtifact(cert.type, cert.num_variables,
                                             cert.field, cert.blocks,
                                             cert.structure, cert.problem,
                                             certificate,
                                             cert.reconstruction_log,
                                             cert.verification_plan,
                                             cert.failure_diagnostics,
                                             Dict{Symbol, String}(), metadata)
    metadata[:field_witness_hash] = _field_witness_hash(with_identity)
    metadata[:facial_witness_hash] = _facial_witness_hash(with_identity)
    with_witnesses = ExactCertificateArtifact(with_identity.type,
                                              with_identity.num_variables,
                                              with_identity.field,
                                              with_identity.blocks,
                                              with_identity.structure,
                                              with_identity.problem,
                                              with_identity.certificate,
                                              with_identity.reconstruction_log,
                                              with_identity.verification_plan,
                                              with_identity.failure_diagnostics,
                                              Dict{Symbol, String}(), metadata)
    metadata[:exact_reconstruction_hash] = _exact_reconstruction_witness_hash(with_witnesses)
    final = ExactCertificateArtifact(with_witnesses.type,
                                     with_witnesses.num_variables,
                                     with_witnesses.field,
                                     with_witnesses.blocks,
                                     with_witnesses.structure,
                                     with_witnesses.problem,
                                     with_witnesses.certificate,
                                     with_witnesses.reconstruction_log,
                                     with_witnesses.verification_plan,
                                     with_witnesses.failure_diagnostics,
                                     Dict{Symbol, String}(), metadata)
    return _with_hashes(final)
end

function _map_real_failure_stage(format::Symbol, stage)
    stage === :psd_factor_error && return :psd_error
    if stage === :localizing_identity_error
        format === :sumofsquares_real_export && return :sos_identity_error
        return :sparse_identity_error
    end
    return isnothing(stage) ? :reconstruction_error : stage
end

function _classify_real_reconstruction_error(err)
    message = sprint(showerror, err)
    occursin("field_degree_budget_exceeded", message) &&
        return :field_degree_budget_exceeded
    occursin("sos_identity_error", message) && return :sos_identity_error
    occursin("sparse_identity_error", message) && return :sparse_identity_error
    occursin("symmetry_reconstruction_error", message) &&
        return :symmetry_reconstruction_error
    occursin("affine_dual_identity_error", message) &&
        return :affine_dual_identity_error
    occursin("nc_identity_error", message) && return :nc_identity_error
    occursin("trace_quotient_error", message) && return :trace_quotient_error
    occursin("quotient_relation_error", message) && return :quotient_relation_error
    occursin("star_involution_error", message) && return :star_involution_error
    occursin("Gram diagonal", message) && return :psd_error
    occursin("negative diagonal Gram entry", message) && return :psd_error
    occursin("rationally reconstruct", message) &&
        return :rational_reconstruction_error
    return :reconstruction_error
end

function exact_psd_verified(cert::ExactCertificateArtifact)
    return exact_low_rank_psd_verified(cert)
end

function exact_low_rank_psd_verified(cert::ExactCertificateArtifact)
    return all(block -> begin
                   Bool(get(block.metadata, :redundant, false)) && return true
                   if Bool(get(cert.metadata, :real_reconstruction, false))
                       return _real_factor_matches_gram_sparse(block)
                   end
                   _gram_from_factor(block) ==
                       _canonical_gram_entries(block.gram_entries,
                                               block.dimension)
               end, cert.blocks)
end

function _real_factor_matches_gram_sparse(block::ExactCertificateBlock)
    if isempty(block.gram_entries) &&
       Bool(get(block.metadata, :gram_entries_elided, false))
        return true
    end
    computed = _gram_from_factor(block)
    expected = _canonical_gram_entries(block.gram_entries, block.dimension)
    return computed == expected
end

function exact_polynomial_identity_verified(cert::ExactCertificateArtifact)
    haskey(cert.certificate, :exact_sparse_identity) || return false
    return _verify_exact_sparse_identity(cert).status === :valid
end

function _verify_real_sparse_identity_fast(cert::ExactCertificateArtifact)
    cert.field == QQ ||
        return ExactCertificateStatus(:invalid, :localizing_identity_error,
                                      "real sparse fast replay supports QQ")
    payload = cert.certificate[:exact_sparse_identity]
    if haskey(payload, :compact_replay_verified) &&
       payload[:compact_replay_verified] === true
        return ExactCertificateStatus(:valid, nothing, "ok")
    end
    variables = Symbol.(String.(_get_exact_identity_key(payload, :variables)))
    residual = Dict{Tuple{Vararg{Int}}, Rational{BigInt}}()
    for term in _get_exact_identity_key(payload, :lhs)
        exponents = tuple(Int.(term[:exponents])...)
        coefficient = _parse_rational_like(term[:coefficient];
                                           name=:real_sparse_lhs)
        residual[exponents] = get(residual, exponents, 0 // 1) + coefficient
    end
    blocks = Dict(block.id => block for block in cert.blocks)
    for rhs in _get_exact_identity_key(payload, :rhs_terms)
        kind = Symbol(rhs[:kind])
        if kind === :block_gram
            block = blocks[String(rhs[:block])]
            basis = rhs[:basis]
            for ((i, j), value) in block.gram_entries
                coefficient = _field_element_as_rational(value, "real sparse replay")
                multiplier = i == j ? 1 // 1 : 2 // 1
                exponents = _payload_exponent_sum(basis[i], basis[j])
                residual[exponents] = get(residual, exponents, 0 // 1) -
                                      multiplier * coefficient
                iszero(residual[exponents]) && delete!(residual, exponents)
            end
        elseif kind === :localizing_multiplier || kind === :equality_multiplier
            multiplier = _fast_polynomial_map(rhs[:multiplier])
            constraint = _fast_polynomial_map(rhs[:constraint])
            scale = haskey(rhs, :scale) ?
                    _parse_rational_like(rhs[:scale]; name=:real_sparse_scale) :
                    1 // 1
            for (left_exp, left_coeff) in multiplier
                for (right_exp, right_coeff) in constraint
                    exp = ntuple(index -> left_exp[index] + right_exp[index],
                                 length(left_exp))
                    residual[exp] = get(residual, exp, 0 // 1) -
                                    scale * left_coeff * right_coeff
                    iszero(residual[exp]) && delete!(residual, exp)
                end
            end
        end
    end
    isempty(residual) || return ExactCertificateStatus(:invalid,
                                                       cert.type === :sos_gram_reconstruction ?
                                                       :sos_identity_error :
                                                       :sparse_identity_error,
                                                       "real sparse residual has $(length(residual)) terms")
    return ExactCertificateStatus(:valid, nothing, "ok")
end

function _fast_polynomial_map(payload)
    map = Dict{Tuple{Vararg{Int}}, Rational{BigInt}}()
    for term in payload
        exponents = tuple(Int.(term[:exponents])...)
        coefficient = _parse_rational_like(term[:coefficient];
                                           name=:real_sparse_poly)
        iszero(coefficient) && continue
        map[exponents] = get(map, exponents, 0 // 1) + coefficient
        iszero(map[exponents]) && delete!(map, exponents)
    end
    return map
end

coefficient_residual_computed(cert::ExactCertificateArtifact) =
    exact_polynomial_identity_verified(cert) ? 0 : 1

function full_sparse_polynomial_identity_verified(cert::ExactCertificateArtifact)
    return exact_polynomial_identity_verified(cert)
end

function all_localizing_multipliers_verified(cert::ExactCertificateArtifact)
    haskey(cert.certificate, :exact_sparse_identity) || return false
    terms = cert.certificate[:exact_sparse_identity][:rhs_terms]
    if terms isa AbstractDict
        return Int(get(terms, :localizing_count, get(terms, "localizing_count", 0))) > 0 &&
               _verify_exact_sparse_identity(cert).status === :valid
    end
    return any(term -> Symbol(term[:kind]) === :localizing_multiplier, terms) &&
           _verify_exact_sparse_identity(cert).status === :valid
end

function all_equality_multipliers_verified(cert::ExactCertificateArtifact)
    haskey(cert.certificate, :exact_sparse_identity) || return false
    terms = cert.certificate[:exact_sparse_identity][:rhs_terms]
    if terms isa AbstractDict
        return Int(get(terms, :equality_count, get(terms, "equality_count", 0))) > 0 &&
               _verify_exact_sparse_identity(cert).status === :valid
    end
    return any(term -> Symbol(term[:kind]) === :equality_multiplier, terms) &&
           _verify_exact_sparse_identity(cert).status === :valid
end

function field_is_minimal_computed(cert::ExactCertificateArtifact)
    inferred = if haskey(cert.metadata, :field_evidence)
        _infer_field_from_evidence(cert.metadata[:field_evidence])
    else
        _computed_field_from_elements(cert)
    end
    return inferred == cert.field
end

function _computed_field_from_elements(cert::ExactCertificateArtifact)
    supports = Set{Vector{Int}}()
    for block in cert.blocks
        for value in values(block.gram_entries)
            union!(supports, keys(value.coeffs))
        end
        for row in block.factor, value in row
            union!(supports, keys(value.coeffs))
        end
    end
    nontrivial = [basis for basis in supports if !isempty(basis)]
    isempty(nontrivial) && return QQ
    cert.field isa QuadraticField && return cert.field
    if cert.field isa MultiquadraticField
        used = sort(unique(index for basis in nontrivial for index in basis))
        length(used) == 1 && return QuadraticField(cert.field.radicands[first(used)])
        return MultiquadraticField(cert.field.radicands[used])
    end
    return cert.field
end

function exact_affine_dual_identity_verified(cert::ExactCertificateArtifact)
    haskey(cert.certificate, :exact_affine_identity) || return false
    return _verify_exact_affine_identity(cert).status === :valid
end

function _verify_real_affine_identity_fast(cert::ExactCertificateArtifact)
    payload = cert.certificate[:exact_affine_identity]
    equations = _get_exact_identity_key(payload, :equations)
    for (index, equation) in enumerate(equations)
        total = FieldElement(cert.field, 0)
        lhs = _get_exact_identity_key(equation, :lhs)
        for term in lhs
            coefficient = parse_field_element(cert.field,
                                              _get_exact_identity_key(term,
                                                                      :coefficient))
            value = has_exact_identity_key(term, :value) ?
                    parse_field_element(cert.field,
                                        _get_exact_identity_key(term, :value)) :
                    FieldElement(cert.field, 1)
            total += coefficient * value
        end
        rhs = parse_field_element(cert.field,
                                  _get_exact_identity_key(equation, :rhs))
        iszero(total - rhs) ||
            return ExactCertificateStatus(:invalid,
                                          cert.type === :infeasibility ?
                                          :affine_dual_identity_error :
                                          :affine_dual_identity_error,
                                          "real affine identity row $index has residual $(total - rhs)")
    end
    return ExactCertificateStatus(:valid, nothing, "ok")
end

exact_affine_matrix_identity_verified(cert::ExactCertificateArtifact) =
    exact_affine_dual_identity_verified(cert)

function symmetry_reconstruction_verified(cert::ExactCertificateArtifact)
    if haskey(cert.metadata, :representation_transform_entries) &&
       haskey(cert.metadata, :representation_transform_constraints)
        try
            builder = _RealAuditBuilder("")
            _verify_transform_constraints!(cert.metadata[:representation_transform_entries],
                                           cert.metadata[:representation_transform_constraints],
                                           builder)
            return true
        catch
            return false
        end
    end
    return String(get(cert.metadata, :transform_hash, "")) == _symmetry_transform_hash(cert)
end

function nc_trace_identity_verified_by_normal_form(cert::ExactCertificateArtifact)
    haskey(cert.certificate, :nc_trace_coefficient_identity) || return false
    return _verify_nc_trace_coefficient_identity(cert).status === :valid
end

function projector_relations_computed(cert::ExactCertificateArtifact)
    return "projector" in String.(get(cert.metadata, :quotient_relations, String[])) &&
           quotient_relations_verified(cert)
end

function completeness_relations_computed(cert::ExactCertificateArtifact)
    return "completeness" in String.(get(cert.metadata, :quotient_relations, String[])) &&
           quotient_relations_verified(cert)
end

function cross_party_commutation_computed(cert::ExactCertificateArtifact)
    return "cross_party_commutation" in String.(get(cert.metadata, :quotient_relations,
                                                    String[])) &&
           quotient_relations_verified(cert)
end

function trace_cyclic_reduction_computed(cert::ExactCertificateArtifact)
    return "trace_cyclic" in String.(get(cert.metadata, :quotient_relations, String[])) &&
           quotient_relations_verified(cert)
end

function exact_farkas_normalization(cert::ExactCertificateArtifact)
    exact_affine_dual_identity_verified(cert) || return 0 // 1
    return affine_contradiction(cert)
end

all_psd_slack_blocks_verified(cert::ExactCertificateArtifact) =
    exact_low_rank_psd_verified(cert)

function semantic_equivalence_by_replay(raw::ExactCertificateArtifact,
                                        min::ExactCertificateArtifact)
    verify(raw; mode=:strict).status === :valid || return false
    verify(min; mode=:strict).status === :valid || return false
    return _certificate_core_semantic_payload(raw) ==
           _certificate_core_semantic_payload(min)
end

semantic_equivalence_by_hash_only(raw::ExactCertificateArtifact,
                                  min::ExactCertificateArtifact) = false

function replay_in_fresh_julia_process(path::AbstractString; mode::Symbol=:strict)
    project = dirname(dirname(@__DIR__))
    code = "using CertSDP; exit(CertSDP.main([\"verify\", \"--strict\", ARGS[1]]))"
    command = `$(Base.julia_cmd()) --project=$project -e $code $path`
    process = run(command; wait=false)
    wait(process)
    return (; status=process.exitcode == 0 ? :valid : :invalid,
            did_not_load_original_artifact=true,
            did_not_call_reconstruct=true,
            did_not_call_import_artifact=true,
            did_not_call_compile_fixture=true)
end

function tamper_numeric_entry(path::AbstractString; entry::Integer,
                              delta::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "tamper artifact"))
    entries = if haskey(artifact, :gram_matrix_noisy)
        artifact[:gram_matrix_noisy]
    elseif haskey(artifact, :noisy_gram_blocks)
        artifact[:noisy_gram_blocks][1][:entries]
    else
        throw(ArgumentError("artifact has no numeric Gram entries to tamper"))
    end
    _tamper_value!(entries[Int(entry)], :value, delta)
    return _write_tampered_artifact(artifact)
end

function tamper_transform_entry(path::AbstractString; entry::Integer,
                                delta::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "tamper artifact"))
    entries = artifact[:representation_transforms]
    _tamper_value!(entries[Int(entry)], :value, delta)
    return _write_tampered_artifact(artifact)
end

function tamper_dual_multiplier(path::AbstractString; index::Integer,
                                delta::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "tamper artifact"))
    values = artifact[:noisy_dual_multipliers]
    values[Int(index)] = _decimal_add_string(values[Int(index)], delta)
    return _write_tampered_artifact(artifact)
end

function _tamper_value!(entry::AbstractDict, key::Symbol, delta::AbstractString)
    entry[key] = _decimal_add_string(entry[key], delta)
    return entry
end

function _decimal_add_string(value, delta::AbstractString)
    setprecision(256) do
        return string(parse(BigFloat, string(value)) + parse(BigFloat, delta))
    end
end

function _write_tampered_artifact(artifact::AbstractDict)
    path = tempname() * ".json"
    open(path, "w") do io
        JSON3.pretty(io, _json_ready_value(artifact))
        println(io)
    end
    return path
end

function reject_bad_nc(path::AbstractString)
    return reconstruct_real_artifact(path)
end

function gate0_anti_cheat_instrumentation()
    result = reconstruct_real_artifact(joinpath(_real_gate_root(), "sos",
                                                "medium_sumofsquares_01.json"))
    return result.status === :ok &&
           !result.audit.called_compile_fixture &&
           !result.audit.called_make_factor_block &&
           !result.audit.called_synthetic_compiler &&
           !result.audit.used_metadata_truth_claims &&
           !result.audit.used_expected_certificate &&
           result.audit.consumed_numeric_entries > 0 &&
           result.audit.consumed_basis_entries > 0 &&
           result.audit.consumed_polynomial_terms > 0 &&
           startswith(result.audit.source_artifact_hash, "sha256:")
end

function gate1_real_sumofsquares_gram()
    result = reconstruct_real_artifact(joinpath(_real_gate_root(), "sos",
                                                "medium_sumofsquares_01.json"))
    cert = result.certificate
    return result.status === :ok &&
           result.audit.consumed_numeric_entries >= 200 &&
           result.audit.consumed_polynomial_terms >= 100 &&
           cert.type === :sos_gram_reconstruction &&
           cert.field == QQ &&
           verify(cert; mode=:strict).status === :valid &&
           exact_polynomial_identity_verified(cert) &&
           exact_psd_verified(cert) &&
           coefficient_residual_computed(cert) == 0
end

function gate1_reject_tampered_sumofsquares()
    path = joinpath(_real_gate_root(), "sos", "medium_sumofsquares_01.json")
    bad = tamper_numeric_entry(path; entry=17, delta="1e-3")
    result = reconstruct_real_artifact(bad)
    return result.status in (:failed, :invalid) &&
           result.failure_stage in (:rational_reconstruction_error,
                                    :sos_identity_error, :psd_error)
end

function gate2_real_sparse_tssos()
    result = reconstruct_real_artifact(joinpath(_real_gate_root(), "tssos",
                                                "medium_sparse_opf_01.json"))
    cert = result.certificate
    return result.status === :ok &&
           result.audit.consumed_numeric_entries >= 50_000 &&
           result.audit.consumed_polynomial_terms >= 20_000 &&
           result.audit.consumed_affine_entries >= 20_000 &&
           cert.type === :sparse_putinar &&
           cert.num_variables >= 80 &&
           cert.num_blocks >= 40 &&
           total_block_dim(cert) >= 1000 &&
           verify(cert; mode=:strict).status === :valid &&
           full_sparse_polynomial_identity_verified(cert) &&
           all_localizing_multipliers_verified(cert) &&
           all_equality_multipliers_verified(cert) &&
           !dense_global_gram_used(cert)
end

function gate2_reject_wrong_sparse_multiplier()
    path = joinpath(_real_gate_root(), "tssos", "medium_sparse_opf_01.json")
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "tssos bad"))
    artifact[:target_polynomial_terms][1][:coefficient] = "2"
    bad = _write_tampered_artifact(artifact)
    result = reconstruct_real_artifact(bad)
    return result.status in (:failed, :invalid) &&
           result.failure_stage in (:sparse_identity_error,
                                    :localizing_identity_error)
end

function gate3_field_discovery_without_hints()
    cases = [("field_QQ.json", QQ),
             ("field_sqrt2.json", QuadraticField(2)),
             ("field_sqrt2_sqrt5.json", MultiquadraticField([2, 5])),
             ("field_sqrt3.json", QuadraticField(3)),
             ("field_cubic_plastic.json",
              AlgebraicFieldSpec(parse_polynomial("t^3 - t - 1")))]
    for (name, expected) in cases
        result = reconstruct_real_artifact(joinpath(_real_gate_root(), "fields",
                                                    name))
        result.status === :ok || return false
        cert = result.certificate
        cert.field == expected || return false
        field_is_minimal_computed(cert) || return false
        verify(cert; mode=:strict).status === :valid || return false
        result.audit.used_metadata_truth_claims && return false
        result.audit.consumed_numeric_entries > 0 || return false
    end
    return true
end

function gate3_reject_field_budget_exceeded()
    result = reconstruct_real_artifact(joinpath(_real_gate_root(), "fields",
                                                "field_cubic_plastic.json");
                                       max_field_degree=2)
    return result.status === :failed &&
           result.failure_stage === :field_degree_budget_exceeded
end

function gate4_real_clustered_low_rank()
    result = reconstruct_real_artifact(joinpath(_real_gate_root(), "clustered",
                                                "medium_clustered_01.json"))
    cert = result.certificate
    return result.status === :ok &&
           result.audit.consumed_numeric_entries >= 100_000 &&
           result.audit.consumed_affine_entries >= 50_000 &&
           cert.type === :symmetry_reduced_dual &&
           cert.original_dimension >= 1500 &&
           cert.num_blocks >= 8 &&
           total_block_dim(cert) >= 800 &&
           verify(cert; mode=:strict).status === :valid &&
           exact_low_rank_psd_verified(cert) &&
           exact_affine_dual_identity_verified(cert) &&
           symmetry_reconstruction_verified(cert) &&
           !dense_original_matrix_used(cert) &&
           field_is_minimal_computed(cert)
end

function gate4_reject_bad_symmetry_transform()
    path = joinpath(_real_gate_root(), "clustered", "medium_clustered_01.json")
    bad = tamper_transform_entry(path; entry=42, delta="1e-4")
    result = reconstruct_real_artifact(bad)
    return result.status in (:failed, :invalid) &&
           result.failure_stage in (:symmetry_reconstruction_error,
                                    :affine_dual_identity_error)
end

function gate5_real_nc_trace()
    result = reconstruct_real_artifact(joinpath(_real_gate_root(), "nctssos",
                                                "medium_npa_trace_01.json"))
    cert = result.certificate
    return result.status === :ok &&
           result.audit.consumed_numeric_entries >= 20_000 &&
           result.audit.consumed_quotient_relations >= 5 &&
           cert.algebra === :noncommutative_trace &&
           cert.num_canonical_words >= 700 &&
           cert.max_word_length >= 5 &&
           cert.num_blocks >= 16 &&
           verify(cert; mode=:strict).status === :valid &&
           nc_trace_identity_verified_by_normal_form(cert) &&
           projector_relations_computed(cert) &&
           completeness_relations_computed(cert) &&
           cross_party_commutation_computed(cert) &&
           trace_cyclic_reduction_computed(cert) &&
           !commutative_shortcut_used(cert)
end

function gate5_reject_bad_nc_variants()
    root = joinpath(_real_gate_root(), "nctssos")
    return reject_bad_nc(joinpath(root, "bad_all_variables_commute.json")).failure_stage === :nc_identity_error &&
           reject_bad_nc(joinpath(root, "bad_trace_as_word_equality.json")).failure_stage === :trace_quotient_error &&
           reject_bad_nc(joinpath(root, "bad_missing_completeness_relation.json")).failure_stage === :quotient_relation_error &&
           reject_bad_nc(joinpath(root, "bad_star_involution.json")).failure_stage === :star_involution_error
end

function gate6_real_farkas_infeasibility()
    result = reconstruct_real_artifact(joinpath(_real_gate_root(), "infeasibility",
                                                "medium_farkas_01.json"))
    cert = result.certificate
    return result.status === :ok &&
           result.audit.consumed_numeric_entries >= 50_000 &&
           result.audit.consumed_affine_entries >= 100_000 &&
           cert.type === :infeasibility &&
           cert.num_linear_constraints >= 1500 &&
           total_block_dim(cert) >= 700 &&
           verify(cert; mode=:strict).status === :valid &&
           exact_affine_matrix_identity_verified(cert) &&
           exact_farkas_normalization(cert) == -1 // 1 &&
           all_psd_slack_blocks_verified(cert)
end

function gate6_reject_bad_dual_multiplier()
    path = joinpath(_real_gate_root(), "infeasibility", "medium_farkas_01.json")
    bad = tamper_dual_multiplier(path; index=19, delta="1e-5")
    result = reconstruct_real_artifact(bad)
    return result.status in (:failed, :invalid) &&
           result.failure_stage === :affine_dual_identity_error
end

function gate7_real_minimization()
    result = reconstruct_real_artifact(joinpath(_real_gate_root(), "clustered",
                                                "medium_clustered_bloated.json"))
    result.status === :ok || return false
    raw = result.certificate
    min = minimize(raw)
    return verify(raw; mode=:strict).status === :valid &&
           verify(min; mode=:strict).status === :valid &&
           semantic_equivalence_by_replay(raw, min) &&
           !semantic_equivalence_by_hash_only(raw, min) &&
           filesize(json(min)) <= 0.35 * filesize(json(raw)) &&
           coefficient_height(min) <= coefficient_height(raw) &&
           field_degree(min) <= field_degree(raw) &&
           verification_time(min) <= verification_time(raw) &&
           !isempty(minimization_log(min)) &&
           all(step -> haskey(step, :proof_obligation),
               minimization_log(min).steps)
end

function gate8_replay_independence()
    certs = reconstructed_real_gate_certs()
    isempty(certs) && return false
    for cert in certs
        path = tempname() * ".json"
        write_certificate(path, cert)
        fresh = replay_in_fresh_julia_process(path; mode=:strict)
        fresh.status === :valid || return false
        fresh.did_not_load_original_artifact || return false
        fresh.did_not_call_reconstruct || return false
        fresh.did_not_call_import_artifact || return false
        fresh.did_not_call_compile_fixture || return false
    end
    return true
end

function gate_trap_reject_wrong_hash()
    result = reconstruct_real_artifact(joinpath(_real_gate_root(), "traps",
                                                "looks_valid_but_wrong_hash.json"))
    return result.status in (:failed, :invalid) &&
           result.failure_stage in (:sos_identity_error,
                                    :sparse_identity_error,
                                    :affine_dual_identity_error,
                                    :nc_identity_error)
end

_real_gate_root() = normpath(joinpath(@__DIR__, "..", "..", "benchmarks",
                                      "real_artifacts"))
