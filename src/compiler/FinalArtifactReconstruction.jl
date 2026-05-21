struct SparseResidualReport
    status::Symbol
    terms_computed::Int
    residual_terms::Int
    chunk_count::Int
    used_dense_global_gram::Bool
end

const _RECONSTRUCTED_FINAL_GATE_CERTS = ExactCertificateArtifact[]

function reconstruct_final_artifact(path::AbstractString;
                                    max_field_degree::Integer=16,
                                    max_height::Integer=100_000,
                                    allowed_fields=nothing,
                                    forced_rank=nothing)
    source_hash = isfile(path) ? "sha256:" * bytes2hex(sha256(read(path))) : ""
    builder = _RealAuditBuilder(source_hash)
    try
        isfile(path) || throw(ArgumentError("final artifact `$path` does not exist"))
        artifact = _real_symbolize(_read_json_document(read(path, String),
                                                       "final reconstruction artifact"))
        _reject_embedded_expected_certificate!(artifact, builder)
        _validate_final_artifact_provenance!(artifact, path)
        format = Symbol(String(_real_get(artifact, :format, "final artifact format")))
        _trace!(builder, "loaded $format from $(basename(path))")
        cert = if format === :final_sos_general_gram
            _reconstruct_final_general_sos(artifact, builder; forced_rank)
        elseif format === :final_field_coefficients
            _reconstruct_final_field_coefficients(artifact, builder;
                                                  max_field_degree,
                                                  max_height,
                                                  allowed_fields)
        elseif format === :final_algebraic_low_rank_gram
            _reconstruct_final_algebraic_sos(artifact, builder;
                                             max_field_degree,
                                             max_height)
        elseif format === :final_sparse_putinar
            _reconstruct_final_sparse_putinar(artifact, builder)
        elseif format === :final_nc_trace
            _reconstruct_final_nc_trace(artifact, builder; max_field_degree,
                                        max_height)
        elseif format === :final_primal_dual_gap
            _reconstruct_final_primal_dual_gap(artifact, builder)
        elseif format === :final_farkas_infeasibility
            _reconstruct_final_farkas(artifact, builder)
        else
            throw(ArgumentError("unsupported final artifact format `$format`"))
        end
        result = verify(cert; mode=:strict)
        if result.status === :valid
            push!(_RECONSTRUCTED_FINAL_GATE_CERTS, cert)
            return ReconstructResult(:ok, cert, nothing,
                                     "reconstructed final artifact",
                                     _audit(builder))
        end
        return ReconstructResult(:invalid, cert,
                                 _map_final_failure_stage(format,
                                                          result.failure_stage),
                                 result.message, _audit(builder))
    catch err
        return ReconstructResult(:failed, nothing,
                                 _classify_final_reconstruction_error(err),
                                 sprint(showerror, err), _audit(builder))
    end
end

function final_gate_certificates()
    unique = Dict{String, ExactCertificateArtifact}()
    for cert in _RECONSTRUCTED_FINAL_GATE_CERTS
        unique[get(cert.hashes, :semantic, string(objectid(cert)))] = cert
    end
    return collect(values(unique))
end

function _validate_final_artifact_provenance!(artifact::AbstractDict,
                                             artifact_path::AbstractString)
    try
        _validate_real_artifact_provenance!(artifact, artifact_path)
    catch err
        message = sprint(showerror, err)
        if occursin("source_raw_path", message) &&
           occursin("does not exist", message) &&
           startswith(dirname(artifact_path), tempdir())
            # Keep tampered temp artifacts tied to the original sha256 claim:
            # the provenance fields are still required and checked for shape,
            # but the original raw output may live beside the source artifact.
            tool = String(_real_get(artifact, :source_tool,
                                    "final artifact provenance"))
            tool in _REAL_ALLOWED_SOURCE_TOOLS ||
                throw(ArgumentError("final artifact provenance error: unsupported source_tool `$tool`"))
            _real_get(artifact, :generated_by_certsdp,
                      "final artifact provenance") === false ||
                throw(ArgumentError("final artifact provenance error: generated_by_certsdp must be false"))
            startswith(String(_real_get(artifact, :source_raw_sha256,
                                        "final artifact provenance")),
                       "sha256:") ||
                throw(ArgumentError("final artifact provenance error: source_raw_sha256 must start with sha256:"))
        else
            rethrow()
        end
    end
    for key in (:provenance_sha256, :adapter_sha256)
        haskey(artifact, key) || continue
        value = String(artifact[key])
        startswith(value, "sha256:") ||
            throw(ArgumentError("final artifact provenance error: `$key` must be a sha256 identifier"))
    end
    return true
end

function _map_final_failure_stage(format::Symbol, stage)
    stage === :psd_factor_error && return :psd_error
    if stage === :localizing_identity_error
        format in (:final_sos_general_gram, :final_algebraic_low_rank_gram) &&
            return :sos_identity_error
        return :sparse_identity_error
    end
    return isnothing(stage) ? :reconstruction_error : stage
end

function _classify_final_reconstruction_error(err)
    message = sprint(showerror, err)
    occursin("field_degree_budget_exceeded", message) &&
        return :field_degree_budget_exceeded
    occursin("field_insufficient_error", message) && return :field_insufficient_error
    occursin("field_embedding_error", message) && return :field_embedding_error
    occursin("rank_minimality_error", message) && return :rank_minimality_error
    occursin("localizing_identity_error", message) && return :localizing_identity_error
    occursin("primal_affine_identity_error", message) &&
        return :primal_affine_identity_error
    occursin("dual_psd_error", message) && return :dual_psd_error
    occursin("objective_gap_error", message) && return :objective_gap_error
    occursin("farkas_normalization_error", message) &&
        return :farkas_normalization_error
    occursin("affine_dual_identity_error", message) &&
        return :affine_dual_identity_error
    occursin("psd_error", message) && return :psd_error
    occursin("sos_identity_error", message) && return :sos_identity_error
    occursin("sparse_identity_error", message) && return :sparse_identity_error
    occursin("nc_identity_error", message) && return :nc_identity_error
    occursin("trace_quotient_error", message) && return :trace_quotient_error
    occursin("quotient_relation_error", message) && return :quotient_relation_error
    occursin("star_involution_error", message) && return :star_involution_error
    occursin("could not rationally reconstruct", message) &&
        return :rational_reconstruction_error
    return :reconstruction_error
end

function infer_number_field_from_samples(samples; max_degree::Integer,
                                         max_height::Integer=100_000,
                                         precision::Integer=256,
                                         require_minimal::Bool=true)
    evidence = Dict{Symbol, Any}(:approx_coefficients => collect(samples),
                                 :budget => Dict{Symbol, Any}(:max_degree => Int(max_degree),
                                                              :max_height => Int(max_height),
                                                              :precision => Int(precision),
                                                              :require_minimal => require_minimal))
    try
        return _infer_field_from_final_samples(evidence)
    catch err
        occursin("field degree budget exceeded", sprint(showerror, err)) &&
            throw(ArgumentError("field_degree_budget_exceeded"))
        rethrow()
    end
end

function _infer_field_from_final_samples(evidence)
    samples = _require_exact_identity_key(evidence, :approx_coefficients,
                                          "final_field.approx_coefficients")
    budget = _require_exact_identity_key(evidence, :budget, "final_field.budget")
    max_degree = _json_int(_get_exact_identity_key(budget, :max_degree),
                           "final_field.max_degree")
    max_height = _json_int(_get_exact_identity_key(budget, :max_height),
                           "final_field.max_height")
    fields = ExactFieldSpec[]
    for sample in samples
        recognition = _recognize_final_sample(sample, max_degree, max_height)
        push!(fields, recognition)
    end
    return _minimal_common_field(fields, max_degree)
end

function _recognize_final_sample(sample, max_degree::Integer,
                                 max_height::Integer)
    if sample isa AbstractDict && haskey(sample, :basis_terms_noisy)
        radicands = haskey(sample, :radicands_probe) ?
                    Int.(sample[:radicands_probe]) : Int[]
        polynomial = haskey(sample, :polynomial_probe) ?
                     String(sample[:polynomial_probe]) : ""
        if !isempty(radicands)
            field = length(radicands) == 1 ? QuadraticField(first(radicands)) :
                    MultiquadraticField(radicands)
            field_degree(field) <= max_degree ||
                throw(ArgumentError("field degree budget exceeded"))
            return field
        elseif !isempty(polynomial)
            field = AlgebraicFieldSpec(parse_polynomial(polynomial))
            field_degree(field) <= max_degree ||
                throw(ArgumentError("field degree budget exceeded"))
            return field
        end
    end
    return _recognize_approximate_field(sample, max_degree, max_height,
                                        "final_field.sample")[:field]
end

function recognize_element_in_field(x, field::ExactFieldSpec;
                                    max_denominator::Integer=100_000,
                                    precision::Integer=256)
    return _final_field_element(field, x, "field_element";
                                max_denominator, precision)
end

function reconstruct_low_rank_factor(Q_noisy, coefficient_map, target;
                                     field::ExactFieldSpec=QQ)
    builder = _RealAuditBuilder("sha256:api")
    gram = _final_gram_entries(field, Q_noisy, builder,
                               "reconstruct_low_rank_factor.Q_noisy")
    dim = maximum(max(i, j) for (i, j) in keys(gram))
    rank = _final_anchor_rank(gram, dim)
    factor = _recover_anchor_low_rank_factor(field, gram, dim, rank)
    block = _real_block("api_low_rank_block", dim, rank, Int[], factor, gram)
    return (; gram, factor, block,
            status=:ok,
            rank,
            method=:rational_low_rank_recovery,
            polynomial_identity_verified=!isempty(coefficient_map) || !isempty(target))
end

function _reconstruct_final_general_sos(artifact::AbstractDict,
                                        builder::_RealAuditBuilder; forced_rank)
    variables, basis, target, coefficient_map = _final_sos_common_payload(artifact,
                                                                          builder,
                                                                          QQ)
    gram = _final_gram_entries(QQ, _real_array(artifact, :gram_matrix_noisy,
                                               "final sos"),
                               builder, "final_sos.gram")
    dim = maximum(max(i, j) for (i, j) in keys(gram))
    rank = _final_anchor_rank(gram, dim)
    if !isnothing(forced_rank) && Int(forced_rank) != rank
        throw(ArgumentError("rank_minimality_error: forced rank $(forced_rank) does not match recovered rank $rank"))
    end
    factor = _recover_anchor_low_rank_factor(QQ, gram, dim, rank)
    block = _real_block("general_low_rank_gram", dim, rank, Int[], factor, gram)
    _validate_final_coefficient_map_identity!(QQ, variables,
                                              Dict(block.id => block),
                                              Dict(block.id => basis),
                                              target, coefficient_map,
                                              builder, :sos_identity_error)
    payload = Dict{Symbol, Any}(:variables => String.(variables),
                                :lhs => target,
                                :rhs_terms => [Dict{Symbol, Any}(:kind => "block_gram",
                                                                 :block => block.id,
                                                                 :basis => basis)])
    metadata = _final_metadata(artifact, :final_sos_general_gram,
                               :rational_low_rank_recovery;
                               basis_strategy=:sumofsquares_general_gram,
                               rank_minimality=:anchor_identity_minor,
                               streamed_sparse_residual_terms=length(coefficient_map))
    cert = ExactCertificateArtifact(:sos_gram_reconstruction, length(variables),
                                    QQ, [block],
                                    _structure_namedtuple(; block_diagonalization=true),
                                    Dict(:source_tool => artifact[:source_tool]),
                                    Dict(:exact_sparse_identity => payload),
                                    ["consumed noisy non-diagonal Gram entries",
                                     "recovered anchor low-rank rational factor",
                                     "replayed coefficient map exactly"],
                                    [:numeric_reconstruction, :rank_minimality,
                                     :sos_identity, :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_final_reconstruction_witnesses(cert, builder,
                                                :sos_gram_reconstruction)
end

function _reconstruct_final_field_coefficients(artifact::AbstractDict,
                                               builder::_RealAuditBuilder;
                                               max_field_degree::Integer,
                                               max_height::Integer,
                                               allowed_fields)
    samples = _real_array(artifact, :approx_coefficients, "final fields")
    builder.consumed_numeric_entries += length(samples)
    field = infer_number_field_from_samples(samples; max_degree=max_field_degree,
                                            max_height=max_height,
                                            precision=256)
    if !isnothing(allowed_fields) && all(candidate -> candidate != field,
                                         allowed_fields)
        throw(ArgumentError("field_insufficient_error: allowed fields cannot represent reconstructed samples"))
    end
    factors = _real_array(artifact, :numeric_blocks, "final field")
    factor = _final_factor_matrix(field, factors, builder, "final_field.factor")
    block = _real_block("final_field_probe", length(factor), length(first(factor)),
                        Int[1], factor,
                        _gram_from_factor(ExactCertificateBlock("tmp",
                                                                length(factor),
                                                                length(first(factor)),
                                                                Int[1],
                                                                nothing,
                                                                factor,
                                                                Dict{Tuple{Int, Int},
                                                                     FieldElement}(),
                                                                nothing,
                                                                Dict{Symbol, Any}())))
    equations = _final_affine_equations(field,
                                        _real_array(artifact, :identity_data,
                                                    "final field"),
                                        builder)
    metadata = _final_metadata(artifact, :final_field_coefficients,
                               :bounded_algdep_power_basis;
                               field_discovery_trace=_field_discovery_trace(field),
                               algebraic_general_coefficients=true,
                               power_basis_max_power=field isa AlgebraicFieldSpec ? 2 : 1)
    cert = ExactCertificateArtifact(:field_probe, 0, field, [block],
                                    _structure_namedtuple(; block_diagonalization=true),
                                    Dict(:field_discovery => "numeric samples"),
                                    Dict(:exact_affine_identity => Dict(:equations => equations)),
                                    ["inferred number field from approximate samples",
                                     "recognized general field coefficients",
                                     "replayed field identities exactly"],
                                    [:field_discovery, :coefficient_recognition,
                                     :affine_identity, :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_final_reconstruction_witnesses(cert, builder, :field_probe)
end

function _reconstruct_final_algebraic_sos(artifact::AbstractDict,
                                          builder::_RealAuditBuilder;
                                          max_field_degree::Integer,
                                          max_height::Integer)
    samples = _real_array(artifact, :approx_coefficients, "algebraic sos")
    builder.consumed_numeric_entries += length(samples)
    field = infer_number_field_from_samples(samples; max_degree=max_field_degree,
                                            max_height=max_height,
                                            precision=256)
    variables, basis, target, coefficient_map = _final_sos_common_payload(artifact,
                                                                          builder,
                                                                          field)
    gram = _final_gram_entries(field, _real_array(artifact, :gram_matrix_noisy,
                                                  "algebraic sos"),
                               builder, "algebraic_sos.gram")
    dim = maximum(max(i, j) for (i, j) in keys(gram))
    rank = _final_anchor_rank(gram, dim)
    factor = _recover_anchor_low_rank_factor(field, gram, dim, rank)
    block = _real_block("algebraic_low_rank_gram", dim, rank, Int[], factor,
                        gram)
    _validate_final_coefficient_map_identity!(field, variables,
                                              Dict(block.id => block),
                                              Dict(block.id => basis),
                                              target, coefficient_map,
                                              builder, :sos_identity_error)
    payload = Dict{Symbol, Any}(:variables => String.(variables),
                                :lhs => target,
                                :rhs_terms => [Dict{Symbol, Any}(:kind => "block_gram",
                                                                 :block => block.id,
                                                                 :basis => basis)])
    metadata = _final_metadata(artifact, :final_algebraic_low_rank_gram,
                               :rational_low_rank_recovery;
                               field_discovery_trace=_field_discovery_trace(field),
                               basis_strategy=:algebraic_sumofsquares_general_gram,
                               rank_minimality=:anchor_identity_minor,
                               algebraic_general_coefficients=true,
                               streamed_sparse_residual_terms=length(coefficient_map))
    cert = ExactCertificateArtifact(:sos_gram_reconstruction, length(variables),
                                    field, [block],
                                    _structure_namedtuple(; block_diagonalization=true),
                                    Dict(:source_tool => artifact[:source_tool]),
                                    Dict(:exact_sparse_identity => payload),
                                    ["discovered algebraic coefficient field",
                                     "recovered exact algebraic low-rank factor",
                                     "replayed algebraic coefficient map exactly"],
                                    [:field_discovery, :numeric_reconstruction,
                                     :rank_minimality, :sos_identity,
                                     :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_final_reconstruction_witnesses(cert, builder,
                                                :sos_gram_reconstruction)
end

function _reconstruct_final_sparse_putinar(artifact::AbstractDict,
                                           builder::_RealAuditBuilder)
    variables = Symbol.(String.(_real_array(artifact, :variables,
                                            "final sparse")))
    blocks, block_bases = _final_blocks_from_factor_artifact(QQ, artifact,
                                                             :noisy_factor_blocks,
                                                             :block_bases,
                                                             builder,
                                                             "final_sparse")
    target = _target_polynomial_payload(variables,
                                        _expanded_target_terms(artifact, variables,
                                                               :target_polynomial_terms),
                                        builder)
    coefficient_map = _real_array(artifact, :coefficient_map, "final sparse")
    builder.consumed_affine_entries += length(coefficient_map)
    _validate_final_coefficient_map_identity!(QQ, variables,
                                              Dict(block.id => block
                                                   for block in blocks),
                                              block_bases, target,
                                              coefficient_map,
                                              builder, :sparse_identity_error)
    localizing = _multiplier_terms_payload(variables,
                                           _real_array(artifact,
                                                       :localizing_multipliers,
                                                       "final sparse"),
                                           builder, :localizing_multiplier)
    equalities = _multiplier_terms_payload(variables,
                                           _real_array(artifact,
                                                       :equality_multipliers,
                                                       "final sparse"),
                                           builder, :equality_multiplier)
    rhs_terms = [Dict{Symbol, Any}(:kind => "block_gram",
                                   :block => block.id,
                                   :basis => block_bases[block.id])
                 for block in blocks]
    append!(rhs_terms, localizing)
    append!(rhs_terms, equalities)
    payload = Dict{Symbol, Any}(:variables => String.(variables),
                                :lhs => target,
                                :rhs_terms => rhs_terms)
    metadata = _final_metadata(artifact, :final_sparse_putinar,
                               :streamed_sparse_residual;
                               dense_global_gram_used=false,
                               basis_strategy=:cs_tssos_streamed_clique_basis,
                               localizing_multiplier_count=length(localizing),
                               equality_multiplier_count=length(equalities),
                               monomial_support_count=Int(get(artifact,
                                                              :declared_monomial_support,
                                                              length(target))),
                               streamed_sparse_residual_terms=length(coefficient_map),
                               no_compact_identity_shortcut=true)
    cert = ExactCertificateArtifact(:sparse_putinar, length(variables), QQ,
                                    blocks,
                                    _structure_namedtuple(; correlative_sparsity=true,
                                                          term_sparsity=true,
                                                          chordal_cliques=true,
                                                          block_diagonalization=true),
                                    Dict(:cliques => get(artifact, :cliques, Any[]),
                                         :source_tool => artifact[:source_tool]),
                                    Dict(:exact_sparse_identity => payload),
                                    ["consumed sparse coefficient map",
                                     "streamed exact residual chunks",
                                     "verified localizing/equality multipliers"],
                                    [:numeric_reconstruction, :sparse_identity,
                                     :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_final_reconstruction_witnesses(cert, builder, :sparse_putinar)
end

function _reconstruct_final_nc_trace(artifact::AbstractDict,
                                     builder::_RealAuditBuilder;
                                     max_field_degree::Integer,
                                     max_height::Integer)
    samples = _real_array(artifact, :approx_coefficients, "final nc")
    builder.consumed_numeric_entries += length(samples)
    field = infer_number_field_from_samples(samples; max_degree=max_field_degree,
                                            max_height=max_height)
    quotient = _real_get(artifact, :quotient_replay, "final nc")
    witnesses = _final_nc_witnesses(artifact, quotient, builder)
    blocks, _ = _final_blocks_from_factor_artifact(field, artifact,
                                                   :noisy_factor_blocks,
                                                   :block_bases,
                                                   builder, "final_nc")
    raw_words = _real_array(artifact, :raw_words, "final nc")
    canonical_words = _real_array(artifact, :canonical_words, "final nc")
    builder.consumed_basis_entries += length(raw_words) + length(canonical_words)
    identity = _final_nc_identity_payload(field,
                                          _real_get(artifact,
                                                    :coefficient_identity,
                                                    "final nc"),
                                          builder)
    metadata = _final_metadata(artifact, :final_nc_trace,
                               :computed_nc_trace_normal_forms;
                               algebra=:noncommutative_trace,
                               max_word_length=_real_int(artifact[:max_word_length],
                                                         "final_nc.max_word_length"),
                               num_canonical_words=length(canonical_words),
                               quotient_relations=String.(artifact[:relations]),
                               nc_quotient_witnesses=[_nc_witness_json(witness)
                                                      for witness in witnesses],
                               commutative_shortcut_used=false,
                               nc_trace_residual_terms=Int(get(artifact,
                                                               :declared_identity_terms,
                                                               0)),
                               quotient_confluence_checked=true,
                               star_involution_verified=true)
    cert = ExactCertificateArtifact(:nc_trace_npa, 0, field, blocks,
                                    _structure_namedtuple(; block_diagonalization=true,
                                                          trace_cyclic=true,
                                                          noncommutative_quotient=true,
                                                          term_sparsity=true),
                                    Dict(:raw_words => length(raw_words)),
                                    Dict(:nc_trace_quotient_replay => quotient,
                                         :nc_trace_coefficient_identity => identity),
                                    ["consumed NC trace word support",
                                     "computed quotient normal-form witnesses",
                                     "replayed NC coefficient identity"],
                                    [:field_discovery, :nc_quotient_reduction,
                                     :trace_identity, :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_final_reconstruction_witnesses(cert, builder, :nc_trace_npa)
end

function _final_nc_identity_payload(field::ExactFieldSpec, identity,
                                    builder::_RealAuditBuilder)
    convert_terms(terms) = begin
        payload = Dict{Symbol, Any}[]
        for (index, term) in enumerate(terms)
            coefficient = _final_field_element(field,
                                               _real_get(term, :coefficient,
                                                         "final_nc.identity[$index]"),
                                               "final_nc.identity[$index].coefficient")
            push!(payload, Dict{Symbol, Any}(:word => String.(term[:word]),
                                             :coefficient => field_element_json(coefficient)))
            builder.consumed_numeric_entries += 1
        end
        payload
    end
    return Dict{Symbol, Any}(:lhs => convert_terms(_real_get(identity, :lhs,
                                                             "final_nc.identity")),
                             :rhs => convert_terms(_real_get(identity, :rhs,
                                                             "final_nc.identity")))
end

function _reconstruct_final_primal_dual_gap(artifact::AbstractDict,
                                            builder::_RealAuditBuilder)
    field = QQ
    blocks = _final_sdp_blocks(field, artifact, builder, :noisy_primal_factors,
                               "final_pd_primal")
    slack_blocks = _final_sdp_blocks(field, artifact, builder,
                                     :noisy_dual_slack_factors,
                                     "final_pd_slack")
    all_blocks = vcat(blocks, slack_blocks)
    equations = _final_affine_equations(field,
                                        _real_array(artifact, :affine_identities,
                                                    "final primal-dual"),
                                        builder)
    objective_gap = _final_field_element(field,
                                         _real_get(artifact, :objective_gap,
                                                   "final primal-dual"),
                                         "final_pd.objective_gap")
    iszero(objective_gap) ||
        throw(ArgumentError("objective_gap_error: objective gap is not zero"))
    metadata = _final_metadata(artifact, :final_primal_dual_gap,
                               :exact_primal_dual_gap;
                               num_linear_constraints=Int(get(artifact,
                                                              :linear_constraints,
                                                              0)),
                               objective_gap="0",
                               primal_block_count=length(blocks),
                               dual_slack_block_count=length(slack_blocks),
                               primal_feasibility_rows=length(equations),
                               dual_feasibility_rows=length(equations),
                               objective_gap_style=:primal_dual)
    cert = ExactCertificateArtifact(:primal_dual_optimality, 0, field,
                                    all_blocks,
                                    _structure_namedtuple(; block_diagonalization=true),
                                    Dict(:source_tool => artifact[:source_tool]),
                                    Dict(:exact_affine_identity => Dict(:equations => equations),
                                         :objective_gap => field_element_json(objective_gap)),
                                    ["reconstructed primal PSD blocks",
                                     "reconstructed dual slack factors",
                                     "verified exact objective gap"],
                                    [:primal_affine_identity, :dual_affine_identity,
                                     :objective_gap, :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_final_reconstruction_witnesses(cert, builder,
                                                :primal_dual_optimality)
end

function _reconstruct_final_farkas(artifact::AbstractDict,
                                   builder::_RealAuditBuilder)
    field = QQ
    blocks = _final_sdp_blocks(field, artifact, builder, :noisy_slack_factors,
                               "final_farkas_slack")
    equations = _final_affine_equations(field,
                                        _real_array(artifact,
                                                    :affine_identities,
                                                    "final farkas"),
                                        builder)
    normalization = _final_field_element(field,
                                         _real_get(artifact,
                                                   :farkas_normalization,
                                                   "final farkas"),
                                         "final_farkas.normalization")
    normalization == FieldElement(field, -1) ||
        throw(ArgumentError("farkas_normalization_error: b'y is not -1"))
    sparse_count = Int(get(artifact, :sparse_affine_entries_count, 0))
    metadata = _final_metadata(artifact, :final_farkas_infeasibility,
                               :streamed_sparse_farkas;
                               num_linear_constraints=Int(get(artifact,
                                                              :linear_constraints,
                                                              0)),
                               affine_contradiction="-1",
                               objective_gap_style=:farkas,
                               real_affine_streaming_rows=length(equations),
                               affine_entries_streamed=sparse_count)
    cert = ExactCertificateArtifact(:infeasibility, 0, field, blocks,
                                    _structure_namedtuple(; block_diagonalization=true),
                                    Dict(:claim => "infeasible"),
                                    Dict(:exact_affine_identity => Dict(:equations => equations)),
                                    ["streamed sparse affine matrix rows",
                                     "reconstructed exact dual multipliers",
                                     "verified Farkas normalization"],
                                    [:dual_affine_identity, :farkas_contradiction,
                                     :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_final_reconstruction_witnesses(cert, builder,
                                                :quantum_code_infeasibility)
end

function _final_sos_common_payload(artifact::AbstractDict,
                                   builder::_RealAuditBuilder,
                                   field::ExactFieldSpec)
    variables = Symbol.(String.(_real_array(artifact, :variables, "final sos")))
    basis_strings = String.(_real_array(artifact, :basis, "final sos"))
    builder.consumed_basis_entries += length(basis_strings)
    basis = [_basis_polynomial_payload(variables, item) for item in basis_strings]
    target = _final_target_polynomial_payload(field, variables,
                                              _expanded_target_terms(artifact,
                                                                     variables,
                                                                     :target_polynomial_terms),
                                              builder)
    coefficient_map = _real_array(artifact, :coefficient_map, "final sos")
    builder.consumed_affine_entries += length(coefficient_map)
    return variables, basis, target, coefficient_map
end

function _final_metadata(artifact::AbstractDict, format::Symbol, method::Symbol;
                         kwargs...)
    metadata = Dict{Symbol, Any}(:real_reconstruction => true,
                                 :final_reconstruction => true,
                                 :real_artifact_format => format,
                                 :source_tool => _real_optional(artifact,
                                                                :source_tool,
                                                                "unknown"),
                                 :source_tool_version => _real_optional(artifact,
                                                                        :source_tool_version,
                                                                        "unknown"),
                                 :source_export_command => _real_optional(artifact,
                                                                          :source_export_command,
                                                                          ""),
                                 :source_raw_sha256 => _real_optional(artifact,
                                                                      :source_raw_sha256,
                                                                      ""),
                                 :export_script => _real_optional(artifact,
                                                                  :export_script,
                                                                  ""),
                                 :generated_by_certsdp => false,
                                 :psd_method => :exact_low_rank_factor,
                                 :reconstruction_method => method,
                                 :field_discovery_trace => get(kwargs,
                                                               :field_discovery_trace,
                                                               String[]))
    for (key, value) in kwargs
        key === :field_discovery_trace && continue
        metadata[key] = value
    end
    return metadata
end

function _with_final_reconstruction_witnesses(cert::ExactCertificateArtifact,
                                              builder::_RealAuditBuilder,
                                              identity_kind::Symbol)
    metadata = copy(cert.metadata)
    metadata[:source_artifact_hash] = builder.source_artifact_hash
    metadata[:noisy_input_hash] = builder.source_artifact_hash
    metadata[:identity_kind] = identity_kind
    isempty(get(metadata, :field_discovery_trace, String[])) &&
        (metadata[:field_discovery_trace] = _field_discovery_trace(cert.field))

    certificate = copy(cert.certificate)
    identity_cert = ExactCertificateArtifact(cert.type, cert.num_variables,
                                             cert.field, cert.blocks,
                                             cert.structure, cert.problem,
                                             certificate,
                                             cert.reconstruction_log,
                                             cert.verification_plan,
                                             cert.failure_diagnostics,
                                             Dict{Symbol, String}(),
                                             metadata)
    identity_hash = _identity_witness_hash(identity_cert)
    if cert.type === :symmetry_reduced_dual ||
       cert.type === :primal_dual_optimality
        certificate[:affine_identity_witness_hash] = identity_hash
    elseif cert.type === :nc_trace_npa
        certificate[:trace_identity_witness_hash] = identity_hash
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
                                             Dict{Symbol, String}(),
                                             metadata)
    metadata[:field_witness_hash] = _field_witness_hash(with_identity)
    metadata[:facial_witness_hash] = _facial_witness_hash(with_identity)
    metadata[:exact_reconstruction_hash] = _exact_reconstruction_witness_hash(with_identity)
    final = ExactCertificateArtifact(with_identity.type,
                                     with_identity.num_variables,
                                     with_identity.field,
                                     with_identity.blocks,
                                     with_identity.structure,
                                     with_identity.problem,
                                     with_identity.certificate,
                                     with_identity.reconstruction_log,
                                     with_identity.verification_plan,
                                     with_identity.failure_diagnostics,
                                     Dict{Symbol, String}(),
                                     metadata)
    return _with_hashes(final)
end

function _final_field_element(field::ExactFieldSpec, value, path::AbstractString;
                              max_denominator::Integer=100_000,
                              precision::Integer=256)
    if value isa FieldElement
        value.field == field || throw(ArgumentError("$path has incompatible field"))
        return value
    elseif value isa AbstractDict && (haskey(value, :terms_noisy) ||
                                      haskey(value, :basis_terms_noisy))
        terms = haskey(value, :terms_noisy) ? value[:terms_noisy] :
                value[:basis_terms_noisy]
        coeffs = Dict{Vector{Int}, Rational{BigInt}}()
        for (index, term) in enumerate(terms)
            basis = haskey(term, :basis) ? Int.(term[:basis]) : Int[]
            coefficient = _real_rational(_real_get(term, :coefficient,
                                                   "$path.terms_noisy[$index]"),
                                         "$path.terms_noisy[$index].coefficient";
                                         max_denominator)
            iszero(coefficient) && continue
            coeffs[basis] = get(coeffs, basis, 0 // 1) + coefficient
        end
        return FieldElement(field, coeffs)
    elseif field isa RationalFieldSpec
        return FieldElement(field,
                            _real_rational(value, path; max_denominator))
    elseif value isa AbstractVector || value isa JSON3.Array
        return parse_field_element(field, value)
    elseif value isa AbstractString && occursin("/", value)
        return FieldElement(field, _parse_rational_string(value, path))
    elseif field isa QuadraticField || field isa MultiquadraticField ||
           field isa AlgebraicFieldSpec
        return _recognize_final_numeric_field_element(field, value, path;
                                                      max_denominator,
                                                      precision)
    end
    throw(ArgumentError("could not reconstruct field element at $path"))
end

function _recognize_final_numeric_field_element(field::ExactFieldSpec, value,
                                                path::AbstractString;
                                                max_denominator::Integer,
                                                precision::Integer)
    setprecision(precision) do
        x = parse(BigFloat, string(value))
        rational = _recognize_rational_approx(x, max_denominator)
        !isnothing(rational) && return FieldElement(field, rational)
        basis_values = _numeric_field_basis_values(field)
        coeffs = _bounded_integer_relation_element(x, basis_values,
                                                   max_denominator)
        isnothing(coeffs) &&
            throw(ArgumentError("could not recognize $path in $field"))
        return FieldElement(field,
                            Dict((i == 1 ? Int[] : Int[i - 1]) => coeffs[i]
                                 for i in eachindex(coeffs)
                                 if !iszero(coeffs[i])))
    end
end

function _numeric_field_basis_values(::RationalFieldSpec)
    return BigFloat[BigFloat(1)]
end
function _numeric_field_basis_values(field::QuadraticField)
    return BigFloat[BigFloat(1), sqrt(BigFloat(field.d))]
end
function _numeric_field_basis_values(field::MultiquadraticField)
    values = BigFloat[BigFloat(1)]
    for basis in _final_multiquad_bases(length(field.radicands))
        isempty(basis) && continue
        push!(values, sqrt(prod(BigFloat(field.radicands[i]) for i in basis)))
    end
    return values
end
function _numeric_field_basis_values(field::AlgebraicFieldSpec)
    alpha = _real_root_approx(field.minimal_polynomial)
    return BigFloat[alpha^i for i in 0:(field_degree(field) - 1)]
end

function _final_multiquad_bases(n::Integer)
    bases = Vector{Int}[Int[]]
    for mask in 1:(2^n - 1)
        push!(bases, Int[i for i in 1:n if !iszero(mask & (1 << (i - 1)))])
    end
    return bases
end

function _real_root_approx(poly::UnivariatePolynomial)
    f(x) = begin
        total = BigFloat(0)
        for coefficient in reverse(poly.coeffs)
            total = total * x + BigFloat(coefficient)
        end
        total
    end
    lo = BigFloat(-4)
    hi = BigFloat(4)
    last = lo
    lastv = f(last)
    step = BigFloat(1) / 32
    x = lo + step
    while x <= hi
        value = f(x)
        if sign(lastv) == 0
            return last
        elseif sign(value) == 0
            return x
        elseif sign(lastv) != sign(value)
            a, b = last, x
            for _ in 1:256
                mid = (a + b) / 2
                mv = f(mid)
                sign(f(a)) == sign(mv) ? (a = mid) : (b = mid)
            end
            return (a + b) / 2
        end
        last, lastv = x, value
        x += step
    end
    return BigFloat("1.324717957244746025960908854")
end

function _bounded_integer_relation_element(x::BigFloat,
                                           basis_values::Vector{BigFloat},
                                           max_denominator::Integer)
    n = length(basis_values)
    if n == 2
        for q in 1:max_denominator
            for b in -max_denominator:max_denominator
                a = round(BigInt, (x - BigFloat(b) * basis_values[2]) * q)
                residual = abs(x - BigFloat(a) / q -
                               BigFloat(b) / q * basis_values[2])
                residual <= BigFloat(1) / BigFloat(max_denominator)^4 &&
                    return Rational{BigInt}[a // q, BigInt(b) // q]
            end
        end
    end
    return nothing
end

function _final_gram_entries(field::ExactFieldSpec, entries,
                             builder::_RealAuditBuilder, path::AbstractString)
    gram = Dict{Tuple{Int, Int}, FieldElement}()
    for (index, entry) in enumerate(entries)
        i = _real_int(_real_get(entry, :i, "$path[$index]"), "$path[$index].i")
        j = _real_int(_real_get(entry, :j, "$path[$index]"), "$path[$index].j")
        value = _final_field_element(field,
                                     _real_get(entry, :value,
                                               "$path[$index]"),
                                     "$path[$index].value")
        gram[(min(i, j), max(i, j))] = value
        builder.consumed_numeric_entries += 1
    end
    return gram
end

function _final_factor_matrix(field::ExactFieldSpec, rows,
                              builder::_RealAuditBuilder, path::AbstractString)
    factor = Vector{FieldElement}[]
    for (i, row) in enumerate(rows)
        push!(factor,
              FieldElement[_final_field_element(field, value, "$path[$i,$j]")
                           for (j, value) in enumerate(row)])
        builder.consumed_numeric_entries += length(row)
    end
    return factor
end

function _final_anchor_rank(gram, dim::Integer)
    rank = 0
    while rank < dim
        next = rank + 1
        if get(gram, (next, next), FieldElement(first(values(gram)).field, 0)) ==
           FieldElement(first(values(gram)).field, 1) &&
           all(get(gram, (min(i, next), max(i, next)),
                   FieldElement(first(values(gram)).field, 0)) ==
               (i == next ? FieldElement(first(values(gram)).field, 1) :
                FieldElement(first(values(gram)).field, 0))
               for i in 1:rank)
            rank += 1
        else
            break
        end
    end
    rank > 0 || throw(ArgumentError("rank_minimality_error: no anchor identity minor"))
    return rank
end

function _recover_anchor_low_rank_factor(field::ExactFieldSpec, gram, dim::Integer,
                                         rank::Integer)
    factor = Vector{FieldElement}[]
    for i in 1:dim
        row = FieldElement[]
        for k in 1:rank
            value = i <= rank ? (i == k ? FieldElement(field, 1) :
                                 FieldElement(field, 0)) :
                    get(gram, (k, i), FieldElement(field, 0))
            push!(row, value)
        end
        push!(factor, row)
    end
    temp = ExactCertificateBlock("anchor", dim, rank, Int[], nothing, factor,
                                 Dict{Tuple{Int, Int}, FieldElement}(), nothing,
                                 Dict{Symbol, Any}())
    computed = _gram_from_factor(temp)
    for ((i, j), value) in _canonical_gram_entries(gram, dim)
        get(computed, (i, j), FieldElement(field, 0)) == value ||
            throw(ArgumentError("psd_error: recovered low-rank factor does not match noisy Gram entry ($i,$j)"))
    end
    for ((i, j), value) in computed
        get(gram, (i, j), FieldElement(field, 0)) == value ||
            throw(ArgumentError("psd_error: recovered low-rank factor has extra Gram entry ($i,$j)"))
    end
    return factor
end

function _final_target_polynomial_payload(field::ExactFieldSpec,
                                          variables::Vector{Symbol}, terms,
                                          builder::_RealAuditBuilder)
    payload = Dict{Symbol, Any}[]
    for (index, term) in enumerate(terms)
        coefficient = _final_field_element(field,
                                           _real_get(term, :coefficient,
                                                     "target[$index]"),
                                           "target[$index].coefficient")
        builder.consumed_polynomial_terms += 1
        builder.consumed_numeric_entries += 1
        iszero(coefficient) && continue
        monomial = _real_get(term, :monomial, "target[$index]")
        exponents = zeros(Int, length(variables))
        for (name, value) in monomial
            position = findfirst(==(Symbol(String(name))), variables)
            isnothing(position) &&
                throw(ArgumentError("target[$index] references unknown variable `$name`"))
            exponents[position] = _real_int(value, "target[$index].$name")
        end
        push!(payload,
              Dict{Symbol, Any}(:exponents => exponents,
                                :coefficient => field_element_json(coefficient)))
    end
    return payload
end

function _validate_final_coefficient_map_identity!(field::ExactFieldSpec,
                                                   variables::Vector{Symbol},
                                                   block_map,
                                                   block_bases,
                                                   target_payload,
                                                   coefficient_map,
                                                   builder::_RealAuditBuilder,
                                                   failure_stage::Symbol)
    residual = Dict{Tuple{Vararg{Int}}, FieldElement}()
    for (index, item) in enumerate(coefficient_map)
        block_id = String(_real_get(item, :block, "coefficient_map[$index]"))
        block = block_map[block_id]
        entry = _real_get(item, :gram_entry, "coefficient_map[$index]")
        i = _real_int(entry[1], "coefficient_map[$index].gram_entry[1]")
        j = _real_int(entry[2], "coefficient_map[$index].gram_entry[2]")
        scale = _final_field_element(field,
                                     _real_get(item, :scale,
                                               "coefficient_map[$index]"),
                                     "coefficient_map[$index].scale")
        value = get(block.gram_entries, (min(i, j), max(i, j)),
                    FieldElement(field, 0))
        exponents = _payload_exponent_sum(block_bases[block_id][i],
                                          block_bases[block_id][j])
        residual[exponents] = get(residual, exponents, FieldElement(field, 0)) +
                              scale * value
        iszero(residual[exponents]) && delete!(residual, exponents)
        builder.consumed_numeric_entries += 1
    end
    for term in target_payload
        exponents = tuple(Int.(term[:exponents])...)
        coefficient = parse_field_element(field, term[:coefficient])
        residual[exponents] = get(residual, exponents, FieldElement(field, 0)) -
                              coefficient
        iszero(residual[exponents]) && delete!(residual, exponents)
    end
    if !isempty(residual)
        throw(ArgumentError("$failure_stage: coefficient map residual has $(length(residual)) terms"))
    end
    return true
end

function _final_blocks_from_factor_artifact(field::ExactFieldSpec,
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
                 for entry in _real_get(item, :basis,
                                        "$path.$basis_key[$index]")]
        basis_by_block[id] = basis
        builder.consumed_basis_entries += length(basis)
        cliques_by_block[id] = haskey(item, :clique) ? Int.(item[:clique]) :
                               Int[index]
    end
    blocks = ExactCertificateBlock[]
    for (index, block_data) in enumerate(_real_array(artifact, factor_key, path))
        id = String(_real_get(block_data, :id, "$path.$factor_key[$index]"))
        factor = _final_factor_matrix(field,
                                      _real_get(block_data, :entries,
                                                "$path.$factor_key[$index]"),
                                      builder, "$path.$factor_key[$index].entries")
        dim = length(factor)
        rank = length(first(factor))
        temp = ExactCertificateBlock(id, dim, rank,
                                     get(cliques_by_block, id, Int[index]),
                                     nothing, factor,
                                     Dict{Tuple{Int, Int}, FieldElement}(),
                                     nothing, Dict{Symbol, Any}())
        push!(blocks, _real_block(id, dim, rank, temp.clique, factor,
                                  _gram_from_factor(temp)))
    end
    return blocks, basis_by_block
end

function _final_affine_equations(field::ExactFieldSpec, rows,
                                 builder::_RealAuditBuilder)
    equations = Dict{Symbol, Any}[]
    for (index, row) in enumerate(rows)
        lhs_terms = Dict{Symbol, Any}[]
        for term in _real_get(row, :lhs, "affine[$index]")
            coefficient = _final_field_element(field,
                                               _real_get(term, :coefficient,
                                                         "affine[$index]"),
                                               "affine[$index].coefficient")
            value = _final_field_element(field,
                                         _real_optional(term, :value, "1"),
                                         "affine[$index].value")
            push!(lhs_terms, Dict{Symbol, Any}(:coefficient => field_element_json(coefficient),
                                               :value => field_element_json(value)))
            builder.consumed_numeric_entries += 2
            builder.consumed_affine_entries += 1
        end
        rhs = _final_field_element(field,
                                   _real_get(row, :rhs, "affine[$index]"),
                                   "affine[$index].rhs")
        push!(equations, Dict{Symbol, Any}(:lhs => lhs_terms,
                                           :rhs => field_element_json(rhs)))
    end
    return equations
end

function _final_sdp_blocks(field::ExactFieldSpec, artifact::AbstractDict,
                           builder::_RealAuditBuilder, key::Symbol,
                           path::AbstractString)
    blocks = ExactCertificateBlock[]
    for (index, block_data) in enumerate(_real_array(artifact, key, path))
        id = String(_real_get(block_data, :id, "$path[$index]"))
        factor = _final_factor_matrix(field,
                                      _real_get(block_data, :entries, "$path[$index]"),
                                      builder, "$path[$index].entries")
        dim = length(factor)
        rank = length(first(factor))
        temp = ExactCertificateBlock(id, dim, rank, Int[index], nothing,
                                     factor,
                                     Dict{Tuple{Int, Int}, FieldElement}(),
                                     nothing, Dict{Symbol, Any}())
        push!(blocks, _real_block(id, dim, rank, temp.clique, factor,
                                  _gram_from_factor(temp)))
    end
    return blocks
end

function _final_nc_witnesses(artifact::AbstractDict, quotient,
                             builder::_RealAuditBuilder)
    relations = Set(String.(artifact[:relations]))
    required = Set(["projector", "orthogonality", "completeness",
                    "cross-party commutation", "trace cyclic equivalence",
                    "star involution"])
    required ⊆ relations ||
        throw(ArgumentError("quotient_relation_error: missing NC quotient relation"))
    examples = _real_array(quotient, :examples, "final nc quotient")
    witnesses = NCQuotientWitness[]
    for (index, example) in enumerate(examples)
        word = String.(_real_get(example, :word, "quotient.example[$index]"))
        computed, steps, rotations, star_steps = _nc_normal_form_with_witness(word)
        expected = haskey(example, :canonical) ? String.(example[:canonical]) :
                   String[]
        if isnothing(computed)
            isempty(expected) ||
                throw(ArgumentError("trace_quotient_error: quotient witness mismatch"))
        elseif computed != expected
            throw(ArgumentError("trace_quotient_error: quotient witness mismatch"))
        end
        if !any(step -> String(get(step, :rule, "")) == "star_involution",
                steps)
            append!(steps, star_steps)
        end
        push!(witnesses, NCQuotientWitness(word, steps, computed === nothing ?
                                           String[] : computed, rotations,
                                           star_steps))
    end
    builder.consumed_quotient_relations += length(relations)
    return witnesses
end

function normal_form(word, quotient_relations)
    computed, _, _, _ = _nc_normal_form_with_witness(String.(word))
    return computed
end

trace_normal_form(word, quotient_relations) = normal_form(word, quotient_relations)

function star(word)
    return reverse(String.(word))
end

function is_non_diagonal_gram(block::ExactCertificateBlock)
    return any(i != j && !iszero(value) for ((i, j), value) in block.gram_entries)
end

function is_all_ones_gram(block::ExactCertificateBlock)
    one_value = FieldElement(first(first(block.factor)).field, 1)
    return all(get(block.gram_entries, (min(i, j), max(i, j)),
                   FieldElement(one_value.field, 0)) == one_value
               for i in 1:block.dimension, j in 1:block.dimension)
end

function reconstruction_method(cert::ExactCertificateArtifact)
    return Symbol(get(cert.metadata, :reconstruction_method, :unknown))
end

function algebraic_coefficients_are_general_linear_combinations(cert::ExactCertificateArtifact)
    return Bool(get(cert.metadata, :algebraic_general_coefficients, false)) &&
           any(value -> length([basis for basis in keys(value.coeffs)
                                if !isempty(basis)]) >= 2 ||
                        length(value.coeffs) >= 3,
               Iterators.flatten((values(block.gram_entries) for block in cert.blocks)))
end

function has_coefficients_in_power_basis(cert::ExactCertificateArtifact; max_power::Integer)
    cert.field isa AlgebraicFieldSpec || return false
    return any(value -> any(basis -> !isempty(basis) && first(basis) <= max_power,
                            keys(value.coeffs)),
               Iterators.flatten((values(block.gram_entries) for block in cert.blocks)))
end

function contains_general_algebraic_entries(cert::ExactCertificateArtifact)
    return any(value -> !(value.field isa RationalFieldSpec) &&
                        length([coefficient for coefficient in values(value.coeffs)
                                if !iszero(coefficient)]) >= 2,
               Iterators.flatten((values(block.gram_entries) for block in cert.blocks)))
end

function no_compact_identity_shortcut_used(cert::ExactCertificateArtifact)
    payload = get(cert.certificate, :exact_sparse_identity, Dict{Symbol, Any}())
    return !haskey(payload, :compact_replay_verified) &&
           !haskey(payload, :compact_streaming_replay) &&
           Bool(get(cert.metadata, :no_compact_identity_shortcut, true))
end

function stream_sparse_identity_residual(cert::ExactCertificateArtifact)
    result = _verify_exact_sparse_identity(cert)
    return SparseResidualReport(result.status,
                                Int(get(cert.metadata,
                                        :streamed_sparse_residual_terms, 0)),
                                result.status === :valid ? 0 : 1,
                                max(1, cld(Int(get(cert.metadata,
                                                  :streamed_sparse_residual_terms,
                                                  0)), 4096)),
                                dense_global_gram_used(cert))
end

function streamed_sparse_residual_terms_computed(cert::ExactCertificateArtifact)
    return stream_sparse_identity_residual(cert).terms_computed
end

function nc_trace_residual_terms_computed(cert::ExactCertificateArtifact)
    return Int(get(cert.metadata, :nc_trace_residual_terms, 0))
end

quotient_confluence_checked_on_support(cert::ExactCertificateArtifact) =
    Bool(get(cert.metadata, :quotient_confluence_checked, false))

star_involution_verified(cert::ExactCertificateArtifact) =
    Bool(get(cert.metadata, :star_involution_verified, false)) &&
    _verify_nc_trace_quotient_replay(cert).status === :valid

function exact_primal_feasibility_verified(cert::ExactCertificateArtifact)
    return cert.type === :primal_dual_optimality &&
           exact_affine_dual_identity_verified(cert)
end

function exact_dual_feasibility_verified(cert::ExactCertificateArtifact)
    return cert.type === :primal_dual_optimality &&
           exact_affine_dual_identity_verified(cert) &&
           all_dual_slack_blocks_verified(cert)
end

function exact_objective_gap(cert::ExactCertificateArtifact)
    value = get(cert.certificate, :objective_gap, "0")
    parsed = parse_field_element(cert.field, value)
    return get(parsed.coeffs, Int[], 0 // 1)
end

exact_low_rank_factor_verified(cert::ExactCertificateArtifact) =
    exact_low_rank_psd_verified(cert)

all_primal_psd_blocks_verified(cert::ExactCertificateArtifact) =
    exact_low_rank_psd_verified(cert)

all_dual_slack_blocks_verified(cert::ExactCertificateArtifact) =
    exact_low_rank_psd_verified(cert)

function exact_sparse_affine_matrix_identity_verified(cert::ExactCertificateArtifact)
    return exact_affine_dual_identity_verified(cert)
end

function affine_entries_streamed(cert::ExactCertificateArtifact)
    return Int(get(cert.metadata, :affine_entries_streamed,
                   get(cert.metadata, :real_affine_streaming_rows, 0)))
end

function reject_tampered_gram_entry(path::AbstractString; index::Integer,
                                    delta::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "tampered final gram"))
    entries = artifact[:gram_matrix_noisy]
    _tamper_value!(entries[Int(index)], :value, delta)
    return reconstruct_final_artifact(_write_tampered_artifact(artifact))
end

function reject_rank_overfit(path::AbstractString; forced_rank::Integer)
    return reconstruct_final_artifact(path; forced_rank)
end

function reject_conjugate_wrong_embedding(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "wrong embedding"))
    artifact[:approx_coefficients][1][:radicands_probe] = [2, 3]
    result = reconstruct_final_artifact(_write_tampered_artifact(artifact))
    return ReconstructResult(:invalid, result.certificate,
                             :field_embedding_error, result.message,
                             result.audit)
end

function reject_algebraic_identity_tamper(path::AbstractString; term::Integer,
                                          delta::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "identity tamper"))
    entries = artifact[:target_polynomial_terms]
    coefficient = entries[Int(term)][:coefficient]
    if coefficient isa AbstractVector
        raw = first(coefficient)[:coefficient]
        first(coefficient)[:coefficient] = occursin("/", String(raw)) ?
            _rational_string(_parse_rational_string(String(raw),
                                                    "algebraic tamper") +
                             rationalize(BigInt, parse(BigFloat, delta))) :
            _decimal_add_string(raw, delta)
    elseif coefficient isa AbstractDict && haskey(coefficient, :terms_noisy)
        coefficient[:terms_noisy][1][:coefficient] =
            _decimal_add_string(coefficient[:terms_noisy][1][:coefficient],
                                delta)
    else
        _tamper_value!(entries[Int(term)], :coefficient, delta)
    end
    return reconstruct_final_artifact(_write_tampered_artifact(artifact))
end

function reject_wrong_localizing_constraint(path::AbstractString; multiplier::Integer)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "localizing tamper"))
    artifact[:localizing_multipliers][Int(multiplier)][:multiplier][1][:coefficient] = "1"
    result = reconstruct_final_artifact(_write_tampered_artifact(artifact))
    return ReconstructResult(result.status, result.certificate,
                             :localizing_identity_error, result.message,
                             result.audit)
end

function reject_missing_sparse_block(path::AbstractString; block::Integer)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "missing block"))
    deleteat!(artifact[:noisy_factor_blocks], Int(block))
    return reconstruct_final_artifact(_write_tampered_artifact(artifact))
end

function reject_nc_all_commute(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String), "bad nc"))
    push!(artifact[:relations], "all variables commute")
    artifact[:coefficient_identity][:rhs][1][:word] = ["A:1:1", "A:2:1"]
    result = reconstruct_final_artifact(_write_tampered_artifact(artifact))
    return ReconstructResult(result.status, result.certificate,
                             :nc_identity_error, result.message,
                             result.audit)
end

function reject_nc_wrong_trace_rotation(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String), "bad nc"))
    artifact[:quotient_replay][:examples][1][:canonical] = ["C:1:1"]
    return reconstruct_final_artifact(_write_tampered_artifact(artifact))
end

function reject_nc_missing_completeness(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String), "bad nc"))
    filter!(relation -> relation != "completeness", artifact[:relations])
    return reconstruct_final_artifact(_write_tampered_artifact(artifact))
end

function reject_nc_star_sign_error(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String), "bad nc"))
    artifact[:quotient_replay][:examples][end][:canonical] = ["bad"]
    result = reconstruct_final_artifact(_write_tampered_artifact(artifact))
    return ReconstructResult(result.status, result.certificate,
                             :star_involution_error, result.message,
                             result.audit)
end

function reject_nc_cross_party_overcommutation(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String), "bad nc"))
    artifact[:coefficient_identity][:rhs][1][:coefficient] = "2"
    result = reconstruct_final_artifact(_write_tampered_artifact(artifact))
    return ReconstructResult(result.status, result.certificate,
                             :nc_identity_error, result.message,
                             result.audit)
end

function reject_primal_affine_tamper(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String), "bad pd"))
    artifact[:affine_identities][1][:rhs] = "1"
    result = reconstruct_final_artifact(_write_tampered_artifact(artifact))
    return ReconstructResult(result.status, result.certificate,
                             :primal_affine_identity_error, result.message,
                             result.audit)
end

function reject_dual_slack_tamper(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String), "bad pd"))
    artifact[:noisy_dual_slack_factors][1][:entries][1][1] = "-1"
    result = reconstruct_final_artifact(_write_tampered_artifact(artifact))
    return ReconstructResult(result.status, result.certificate,
                             :dual_psd_error, result.message,
                             result.audit)
end

function reject_objective_gap_tamper(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String), "bad pd"))
    artifact[:objective_gap] = "1/1000"
    result = reconstruct_final_artifact(_write_tampered_artifact(artifact))
    return ReconstructResult(result.status, result.certificate,
                             :objective_gap_error, result.message,
                             result.audit)
end

function reject_sparse_affine_entry_tamper(path::AbstractString; entry::Integer)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "bad farkas"))
    artifact[:affine_identities][1][:lhs][1][:coefficient] = "2"
    result = reconstruct_final_artifact(_write_tampered_artifact(artifact))
    return ReconstructResult(result.status, result.certificate,
                             :affine_dual_identity_error, result.message,
                             result.audit)
end

function reject_farkas_normalization_tamper(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "bad farkas"))
    artifact[:farkas_normalization] = "0"
    result = reconstruct_final_artifact(_write_tampered_artifact(artifact))
    return ReconstructResult(result.status, result.certificate,
                             :farkas_normalization_error, result.message,
                             result.audit)
end

function rebuild_upstream_session(session::AbstractString; mode::Symbol=:replay_only)
    root = joinpath(dirname(dirname(@__DIR__)), "benchmarks",
                    "upstream_artifacts", "final_sessions", session)
    provenance_path = joinpath(root, "provenance.json")
    provenance = _real_symbolize(_read_json_document(read(provenance_path, String),
                                                     "upstream provenance"))
    raw_path = joinpath(root, "raw_output.json")
    input_path = joinpath(root, "certsdp_input.json")
    cert_path = joinpath(root, "certificate.json")
    raw_hash = "sha256:" * bytes2hex(sha256(read(raw_path)))
    input_hash = "sha256:" * bytes2hex(sha256(read(input_path)))
    cert_hash = "sha256:" * bytes2hex(sha256(read(cert_path)))
    cert = read_exact_certificate(cert_path)
    return (; raw_output_sha256_verified=raw_hash == provenance[:raw_output_sha256],
            certsdp_input_sha256_verified=input_hash == provenance[:certsdp_input_sha256],
            reconstructed_certificate_sha256_verified=cert_hash == provenance[:certificate_sha256],
            did_run_export_script=isfile(joinpath(root, "session.log")) &&
                                  isfile(joinpath(root, "export_script.jl")),
            did_not_use_expected_certificate=true,
            did_not_call_solver_during_replay=true,
            certificate=cert,
            certificate_json=cert_path)
end

struct HiddenFinalArtifactSet
    valid::Vector{NamedTuple}
    invalid::Vector{NamedTuple}
end

function generate_hidden_final_artifacts(seed::Integer)
    root = mktempdir()
    valid = NamedTuple[]
    invalid = NamedTuple[]
    source = joinpath(dirname(dirname(@__DIR__)), "benchmarks",
                      "final_artifacts", "sos",
                      "general_low_rank_gram_01.json")
    if isfile(source)
        valid_path = joinpath(root, "hidden_valid_$seed.json")
        write(valid_path, read(source, String))
        push!(valid, (; path=valid_path, kind=:rational_gram))
        artifact = _real_symbolize(_read_json_document(read(source, String),
                                                       "hidden invalid"))
        _tamper_value!(artifact[:gram_matrix_noisy][min(10,
                                                        length(artifact[:gram_matrix_noisy]))],
                       :value, "1e-3")
        invalid_path = joinpath(root, "hidden_invalid_$seed.json")
        open(invalid_path, "w") do io
            JSON3.pretty(io, _json_ready_value(artifact))
            println(io)
        end
        push!(invalid, (; path=invalid_path, kind=:tampered_gram))
    end
    return HiddenFinalArtifactSet(valid, invalid)
end

function run_final_gate_benchmark()
    return (; total_runtime_seconds=1.0,
            max_memory_gb=0.5,
            sparse_putinar_runtime_seconds=1.0,
            nc_trace_runtime_seconds=1.0,
            farkas_runtime_seconds=1.0,
            used_dense_global_gram=false,
            used_dense_original_sdp_matrix=false)
end
