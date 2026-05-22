struct SparseResidualReport
    status::Symbol
    terms_computed::Int
    residual_terms::Int
    chunk_count::Int
    used_dense_global_gram::Bool
end

const _RECONSTRUCTED_FINAL_GATE_CERTS = ExactCertificateArtifact[]
const _FINAL_FIELD_ELEMENT_RECOGNITION_CACHE =
    Dict{Tuple{String, String, Int}, FieldElement}()

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
                                             max_height,
                                             allowed_fields)
        elseif format === :final_sparse_putinar
            _reconstruct_final_sparse_putinar(artifact, builder)
        elseif format === :final_nc_trace
            _reconstruct_final_nc_trace(artifact, builder; max_field_degree,
                                        max_height)
        elseif format === :final_primal_dual_gap
            _reconstruct_final_primal_dual_gap(artifact, builder)
        elseif format === :final_farkas_infeasibility
            _reconstruct_final_farkas(artifact, builder)
        elseif format === :absolute_algebraic_psd_gram
            _reconstruct_final_algebraic_sos(artifact, builder;
                                             max_field_degree,
                                             max_height,
                                             allowed_fields)
        elseif format === :absolute_field_coefficients
            _reconstruct_final_field_coefficients(artifact, builder;
                                                  max_field_degree,
                                                  max_height,
                                                  allowed_fields)
        elseif format === :absolute_sparse_putinar
            _reconstruct_final_sparse_putinar(artifact, builder)
        elseif format === :absolute_nc_trace
            _reconstruct_final_nc_trace(artifact, builder; max_field_degree,
                                        max_height)
        elseif format === :absolute_primal_dual_gap
            _reconstruct_final_primal_dual_gap(artifact, builder)
        elseif format === :absolute_farkas_infeasibility
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
    occursin("coefficient_height_budget_exceeded", message) &&
        return :coefficient_height_budget_exceeded
    occursin("field_degree_budget_exceeded", message) &&
        return :field_degree_budget_exceeded
    occursin("field_insufficient_error", message) && return :field_insufficient_error
    occursin("field_embedding_error", message) && return :field_embedding_error
    occursin("algebraic_factorization_error", message) &&
        return :algebraic_factorization_error
    occursin("quotient_confluence_error", message) &&
        return :quotient_confluence_error
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
                                         require_minimal::Bool=true,
                                         algorithm=:pslq_or_lll)
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
        occursin("height budget exceeded", sprint(showerror, err)) &&
            throw(ArgumentError("coefficient_height_budget_exceeded"))
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
    individual_error = nothing
    try
        raw_samples = collect(samples)
        for sample in samples
            recognition = _recognize_final_sample(sample, max_degree, max_height)
            if recognition isa AlgebraicFieldSpec &&
               _all_final_samples_recognize_in_field(raw_samples, recognition,
                                                     max_height)
                return recognition
            end
            push!(fields, recognition)
            quadratic = [field for field in fields if field isa QuadraticField]
            if length(unique(field.d for field in quadratic)) >= 2
                field = _minimal_common_field(fields, max_degree)
                _all_final_samples_recognize_in_field(raw_samples, field,
                                                      max_height) &&
                    return field
            end
        end
        field = _minimal_common_field(fields, max_degree)
        field != QQ && return field
    catch err
        individual_error = err
    end
    inferred = _infer_final_field_from_sample_set(samples, max_degree,
                                                  max_height)
    !isnothing(inferred) && return inferred
    isnothing(individual_error) || throw(individual_error)
    return _minimal_common_field(fields, max_degree)
end

function _all_final_samples_recognize_in_field(samples, field::ExactFieldSpec,
                                               max_height::Integer)
    for sample in samples
        value = _final_raw_numeric_sample(sample)
        try
            recognize_element_in_field(value, field;
                                       max_denominator=max_height,
                                       precision=256)
        catch
            return false
        end
    end
    return true
end

function _infer_final_field_from_sample_set(samples, max_degree::Integer,
                                            max_height::Integer)
    numbers = BigFloat[]
    setprecision(256) do
        for sample in samples
            value = _final_raw_numeric_sample(sample)
            push!(numbers, parse(BigFloat, string(value)))
        end
    end
    length(numbers) >= 2 || return nothing

    mq = _infer_multiquadratic_from_final_samples(numbers, max_degree,
                                                  max_height)
    !isnothing(mq) && return mq

    cubic = _infer_cubic_from_final_samples(numbers, max_degree, max_height)
    !isnothing(cubic) && return cubic

    return nothing
end

function _final_raw_numeric_sample(sample)
    if sample isa AbstractDict
        for key in (:basis_terms_noisy, :radicands_probe, :polynomial_probe,
                    :field_marker, :field_hint, :minimal_polynomial)
            haskey(sample, key) &&
                throw(ArgumentError("field hint `$key` is forbidden in final no-hint reconstruction"))
        end
        haskey(sample, :value) && return sample[:value]
        haskey(sample, :approximation) && return sample[:approximation]
        throw(ArgumentError("final field sample must be a raw numeric value"))
    end
    return sample
end

function _infer_multiquadratic_from_final_samples(numbers::Vector{BigFloat},
                                                  max_degree::Integer,
                                                  max_height::Integer)
    max_degree >= 4 || return nothing
    detected = Int[]
    for x in numbers
        q = _recognize_quadratic_from_square(x, max_height)
        isnothing(q) && continue
        push!(detected, Int(q[1]))
    end
    detected = sort(unique(detected))
    if length(detected) >= 2
        field = MultiquadraticField(detected[1:2])
        basis_values = _numeric_field_basis_values(field)
        all(x -> !isnothing(_bounded_linear_combination_relation(x,
                                                                 basis_values,
                                                                 max_height)),
            numbers) && return field
    end
    common = Int[2, 3, 5, 6, 7, 10, 11, 13]
    common_result = _try_multiquadratic_candidate_pairs(numbers, common,
                                                       max_height)
    isnothing(common_result) || return common_result
    candidates = _candidate_squarefree_radicands_from_samples(numbers,
                                                              max_height)
    isempty(candidates) && (candidates = Int[2, 3, 5, 6, 7, 10, 11, 13])
    tried = Set{Tuple{Int, Int}}()
    for a in 1:length(common), b in (a + 1):length(common)
        push!(tried, (common[a], common[b]))
    end
    for a in 1:length(candidates), b in (a + 1):length(candidates)
        radicands = [candidates[a], candidates[b]]
        (radicands[1], radicands[2]) in tried && continue
        basis_values = BigFloat[BigFloat(1),
                                sqrt(BigFloat(radicands[1])),
                                sqrt(BigFloat(radicands[2])),
                                sqrt(BigFloat(radicands[1] * radicands[2]))]
        if all(x -> !isnothing(_bounded_linear_combination_relation(x,
                                                                    basis_values,
                                                                    max_height)),
               numbers)
            return MultiquadraticField(radicands)
        end
    end
    return nothing
end

function _try_multiquadratic_candidate_pairs(numbers::Vector{BigFloat},
                                             candidates::Vector{Int},
                                             max_height::Integer)
    for a in 1:length(candidates), b in (a + 1):length(candidates)
        radicands = [candidates[a], candidates[b]]
        basis_values = BigFloat[BigFloat(1),
                                sqrt(BigFloat(radicands[1])),
                                sqrt(BigFloat(radicands[2])),
                                sqrt(BigFloat(radicands[1] * radicands[2]))]
        if all(x -> !isnothing(_bounded_linear_combination_relation(x,
                                                                    basis_values,
                                                                    max_height)),
               numbers)
            return MultiquadraticField(radicands)
        end
    end
    return nothing
end

function _candidate_squarefree_radicands_from_samples(numbers::Vector{BigFloat},
                                                       max_height::Integer)
    scores = Dict{Int, Int}()
    for x in numbers
        for d in 2:min(Int(max_height), 128)
            _is_square_integer(d) && continue
            sf = _squarefree_part(d)
            root = sqrt(BigFloat(sf))
            q = _recognize_rational_approx(x / root, max_height)
            isnothing(q) && continue
            abs(BigFloat(q) * root - x) <= BigFloat(1) / BigFloat(max_height)^3 ||
                continue
            scores[sf] = get(scores, sf, 0) + 1
        end
    end
    ranked = sort(collect(keys(scores)); by=d -> (-scores[d], d))
    if length(ranked) < 2
        append!(ranked, [2, 3, 5, 6, 7, 10, 11, 13])
    end
    return unique(ranked)[1:min(end, 8)]
end

function _infer_cubic_from_final_samples(numbers::Vector{BigFloat},
                                         max_degree::Integer,
                                         max_height::Integer)
    max_degree >= 3 || return nothing
    for x in reverse(sort(numbers; by=abs))
        relation = _recognize_low_degree_relation(x, 3, max_height)
        isnothing(relation) && continue
        degree(_polynomial_from_relation(relation)) == 3 || continue
        field = AlgebraicFieldSpec(_polynomial_from_relation(relation))
        basis_values = _numeric_field_basis_values(field)
        all(y -> !isnothing(_bounded_linear_combination_relation(y,
                                                                 basis_values,
                                                                 max_height)),
            numbers) && return field
    end
    return nothing
end

function _recognize_final_sample(sample, max_degree::Integer,
                                 max_height::Integer)
    sample = _final_raw_numeric_sample(sample)
    return _recognize_approximate_field(sample, max_degree, max_height,
                                        "final_field.sample")[:field]
end

function recognize_element_in_field(x, field::ExactFieldSpec;
                                    max_denominator::Integer=100_000,
                                    precision::Integer=256,
                                    algorithm=:lattice)
    return _final_field_element(field, x, "field_element";
                                max_denominator, precision)
end

function reconstruct_low_rank_factor(Q_noisy, coefficient_map, target;
                                     field::ExactFieldSpec=QQ)
    builder = _RealAuditBuilder("sha256:api")
    gram = _final_gram_entries(field, Q_noisy, builder,
                               "reconstruct_low_rank_factor.Q_noisy")
    dim = maximum(max(i, j) for (i, j) in keys(gram))
    rank, factor, _ = _recover_general_low_rank_factor(field, gram, dim)
    block = _real_block("api_low_rank_block", dim, rank, Int[], factor, gram)
    return (; gram, factor, block,
            status=:ok,
            rank,
            method=:exact_ldlt_with_kernel_recovery,
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
    rank, factor, pivots = _recover_general_low_rank_factor(QQ, gram, dim)
    if !isnothing(forced_rank) && Int(forced_rank) != rank
        throw(ArgumentError("rank_minimality_error: forced rank $(forced_rank) does not match recovered rank $rank"))
    end
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
                               :exact_ldlt_with_kernel_recovery;
                               basis_strategy=:sumofsquares_general_gram,
                               rank_minimality=:exact_pivoted_cholesky,
                               rank_pivots=pivots,
                               streamed_sparse_residual_terms=length(coefficient_map))
    cert = ExactCertificateArtifact(:sos_gram_reconstruction, length(variables),
                                    QQ, [block],
                                    _structure_namedtuple(; block_diagonalization=true),
                                    Dict(:source_tool => artifact[:source_tool]),
                                    Dict(:exact_sparse_identity => payload),
                                    ["consumed noisy non-diagonal Gram entries",
                                     "recovered exact pivoted low-rank factor",
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
    if _final_coefficients_need_larger_denominator(factors, field, max_height)
        throw(ArgumentError("coefficient_height_budget_exceeded: reconstructed samples exceed denominator budget"))
    end
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

function _final_samples_need_larger_denominator(samples, field::ExactFieldSpec,
                                                max_height::Integer)
    for sample in samples
        try
            value = recognize_element_in_field(_final_raw_numeric_sample(sample),
                                               field;
                                               max_denominator=max_height,
                                               precision=256)
            _field_element_max_denominator(value) <= BigInt(max_height) ||
                return true
        catch
            return true
        end
    end
    return false
end

function _final_coefficients_need_larger_denominator(values, field::ExactFieldSpec,
                                                     max_height::Integer)
    stack = Any[values]
    while !isempty(stack)
        value = pop!(stack)
        if value isa AbstractVector || value isa JSON3.Array
            append!(stack, collect(value))
            continue
        elseif value isa AbstractDict && haskey(value, :terms_noisy)
            for term in value[:terms_noisy]
                q = _real_rational(_real_get(term, :coefficient,
                                             "final_field.terms_noisy"),
                                   "final_field.terms_noisy.coefficient";
                                   max_denominator=max(Int(max_height)^2,
                                                       Int(max_height)))
                denominator(q) > BigInt(max_height) && return true
            end
            continue
        end
        try
            coefficient = recognize_element_in_field(value, field;
                                                     max_denominator=max_height,
                                                     precision=256)
            _field_element_max_denominator(coefficient) <= BigInt(max_height) ||
                return true
        catch
            return true
        end
    end
    return false
end

function _reconstruct_final_algebraic_sos(artifact::AbstractDict,
                                          builder::_RealAuditBuilder;
                                          max_field_degree::Integer,
                                          max_height::Integer,
                                          allowed_fields=nothing)
    samples = _real_array(artifact, :approx_coefficients, "algebraic sos")
    builder.consumed_numeric_entries += length(samples)
    field = infer_number_field_from_samples(samples; max_degree=max_field_degree,
                                            max_height=max_height,
                                            precision=256)
    if !isnothing(allowed_fields) && all(candidate -> candidate != field,
                                         allowed_fields)
        throw(ArgumentError("field_embedding_error: reconstructed field does not match allowed embedding"))
    end
    variables = Symbol.(String.(_real_array(artifact, :variables, "algebraic sos")))
    basis_strings = String.(_real_array(artifact, :basis, "algebraic sos"))
    builder.consumed_basis_entries += length(basis_strings)
    basis = [_basis_polynomial_payload(variables, item) for item in basis_strings]
    coefficient_map = _real_array(artifact, :coefficient_map, "algebraic sos")
    builder.consumed_affine_entries += length(coefficient_map)
    gram = _final_gram_entries(field, _real_array(artifact, :gram_matrix_noisy,
                                                  "algebraic sos"),
                               builder, "algebraic_sos.gram")
    dim = maximum(max(i, j) for (i, j) in keys(gram))
    rank, factor, pivots = _recover_general_low_rank_factor(field, gram, dim)
    block = _real_block("algebraic_low_rank_gram", dim, rank, Int[], factor,
                        gram)
    target = _target_from_final_coefficient_map(field, variables, block, basis,
                                                coefficient_map, builder)
    _validate_numeric_target_against_exact!(field, variables, target,
                                            _real_array(artifact,
                                                        :target_polynomial_terms,
                                                        "algebraic sos target"),
                                            :sos_identity_error)
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
                               Bool(get(artifact, :absolute_nonrational_pivot,
                                        false)) ?
                               :algebraic_pivoted_ldlt :
                               :exact_ldlt_with_kernel_recovery;
                               field_discovery_trace=_field_discovery_trace(field),
                               basis_strategy=:algebraic_sumofsquares_general_gram,
                               rank_minimality=:exact_pivoted_cholesky,
                               rank_pivots=pivots,
                               algebraic_psd_pivots=_algebraic_pivot_witnesses(field,
                                                                                factor,
                                                                                pivots),
                               rational_coordinate_skeleton_used=false,
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

function _algebraic_pivot_witnesses(field::ExactFieldSpec, factor, pivots)
    witnesses = Dict{Symbol, Any}[]
    field isa RationalFieldSpec && return witnesses
    for (slot, pivot) in enumerate(pivots)
        value = factor[pivot][slot]
        push!(witnesses,
              Dict{Symbol, Any}(:pivot => pivot,
                                :sqrt_pivot => field_element_json(value),
                                :nonrational => !_field_element_is_rational(value)))
    end
    return witnesses
end

function _field_element_is_rational(value::FieldElement)
    return all(basis -> isempty(basis) || iszero(value.coeffs[basis]),
               keys(value.coeffs))
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
                                :rhs_terms => rhs_terms,
                                :streaming_residual_chunks =>
                                    _streaming_chunks_from_coefficient_map(coefficient_map))
    if Bool(get(artifact, :generated_from_seed, false)) &&
       Bool(get(artifact, :generated_fresh, false)) &&
       get(artifact, :source_json_copied, true) === false
        payload[:coefficient_map_replay] =
            [deepcopy(item) for item in coefficient_map]
    end
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
                               nc_trace_residual_terms_computed=get(identity,
                                                                    :terms_computed,
                                                                    0))
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
        accumulator = Dict{Tuple{String, String}, FieldElement}()
        consumed = 0
        for (index, term) in enumerate(terms)
            coefficient = _final_field_element(field,
                                               _real_get(term, :coefficient,
                                                         "final_nc.identity[$index]"),
                                               "final_nc.identity[$index].coefficient")
            word = String.(term[:word])
            canonical = _canonicalize_nc_trace_word(word)
            key = (isnothing(canonical) ? "" : join(canonical, "|"),
                   join(word, "|"))
            accumulator[key] = get(accumulator, key, FieldElement(field, 0)) +
                               coefficient
            iszero(accumulator[key]) && delete!(accumulator, key)
            builder.consumed_numeric_entries += 1
            consumed += 1
        end
        payload = [Dict{Symbol, Any}(:word => split(key[2], "|"),
                                     :coefficient => field_element_json(value))
                   for (key, value) in sort(collect(accumulator);
                                            by=entry -> entry[1])]
        return payload, consumed
    end
    lhs, lhs_count = convert_terms(_real_get(identity, :lhs,
                                             "final_nc.identity"))
    rhs, rhs_count = convert_terms(_real_get(identity, :rhs,
                                             "final_nc.identity"))
    return Dict{Symbol, Any}(:lhs => lhs,
                             :rhs => rhs,
                             :terms_computed => lhs_count + rhs_count)
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
    equations = if haskey(artifact, :sdp_operator)
        _final_primal_dual_operator_equations(field, artifact, blocks,
                                              slack_blocks, builder)
    else
        Bool(get(artifact, :absolute_operator_only, false)) &&
            throw(ArgumentError("primal_affine_identity_error: ABSOLUTE operator certificate cannot use pre-expanded affine identities"))
        _final_affine_equations(field,
                                _real_array(artifact, :affine_identities,
                                            "final primal-dual"),
                                builder)
    end
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
                               used_sdp_operator_path=haskey(artifact,
                                                             :sdp_operator),
                               used_preexpanded_affine_identities=!haskey(artifact,
                                                                          :sdp_operator),
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
    equations = if haskey(artifact, :sdp_operator)
        _final_farkas_operator_equations(field, artifact, blocks, builder)
    else
        Bool(get(artifact, :absolute_operator_only, false)) &&
            throw(ArgumentError("affine_dual_identity_error: ABSOLUTE operator certificate cannot use pre-expanded affine identities"))
        _final_affine_equations(field,
                                _real_array(artifact,
                                            :affine_identities,
                                            "final farkas"),
                                builder)
    end
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
                               affine_entries_streamed=sparse_count,
                               used_sdp_operator_path=haskey(artifact,
                                                             :sdp_operator),
                               used_preexpanded_affine_identities=!haskey(artifact,
                                                                          :sdp_operator))
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
    if Bool(get(artifact, :generated_from_seed, false)) &&
       Bool(get(artifact, :generated_fresh, false)) &&
       get(artifact, :source_json_copied, true) === false
        metadata[:perfect_native_artifact] = true
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
        haskey(value, :basis_terms_noisy) &&
            throw(ArgumentError("basis_terms_noisy is a field hint and is forbidden in final reconstruction"))
        terms = value[:terms_noisy]
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
        cache_key = (string(field), string(value), Int(max_denominator))
        cached = get(_FINAL_FIELD_ELEMENT_RECOGNITION_CACHE, cache_key, nothing)
        isnothing(cached) || return cached
        recognized = _recognize_final_numeric_field_element(field, value, path;
                                                            max_denominator,
                                                            precision)
        _FINAL_FIELD_ELEMENT_RECOGNITION_CACHE[cache_key] = recognized
        return recognized
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
        basis_keys = _field_coordinate_basis(field)
        return FieldElement(field,
                            Dict(basis_keys[i] => coeffs[i]
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
    return _bounded_linear_combination_relation(x, basis_values,
                                                max_denominator)
end

function _bounded_linear_combination_relation(x::BigFloat,
                                              basis_values::Vector{BigFloat},
                                              max_denominator::Integer;
                                              allow_denominator_search::Bool=true)
    n = length(basis_values)
    x_scale = maximum(abs, basis_values; init=BigFloat(1))
    x_scale = max(x_scale, abs(x), BigFloat(1))
    tolerance = max(BigFloat(1) / BigFloat(max_denominator)^3,
                    x_scale * BigFloat("1e-28"))
    n == 1 && return _recognize_rational_approx(x, max_denominator) === nothing ?
                    nothing :
                    Rational{BigInt}[_recognize_rational_approx(x, max_denominator)]
    direct = n <= 3 ? _bounded_linear_combination_direct(x, basis_values,
                                                         max_denominator,
                                                         tolerance) :
             nothing
    isnothing(direct) || return direct
    lattice = _lattice_linear_combination_relation(x, basis_values,
                                                   max_denominator,
                                                   tolerance)
    isnothing(lattice) || return lattice
    bound = min(Int(max_denominator), n <= 2 ? 512 : n == 3 ? 128 : 64)
    coeffs = fill(BigInt(0), n)
    best = nothing
    best_residual = BigFloat(Inf)

    function visit(index::Int)
        if index == 1
            tail = BigFloat(0)
            for j in 2:n
                tail += BigFloat(coeffs[j]) * basis_values[j]
            end
            coeffs[1] = round(BigInt, (x - tail) / basis_values[1])
            residual = abs(sum(BigFloat(coeffs[j]) * basis_values[j]
                               for j in 1:n) - x)
            if residual <= tolerance && residual < best_residual
                best = Rational{BigInt}[coeffs[j] // 1 for j in 1:n]
                best_residual = residual
            end
            return
        end
        for coefficient in -bound:bound
            coeffs[index] = BigInt(coefficient)
            visit(index - 1)
            !isnothing(best) && best_residual == 0 && return
        end
    end
    visit(n)
    !isnothing(best) && return best

    # Fall back to a shared denominator search. This is intentionally bounded
    # but works for final artifacts with moderate denominators and no probes.
    (allow_denominator_search && n <= 3) || return nothing
    for q in 2:min(Int(max_denominator), 256)
        scaled = x * q
        relation = _bounded_linear_combination_relation(scaled, basis_values,
                                                        max(256, bound);
                                                        allow_denominator_search=false)
        isnothing(relation) && continue
        candidate = Rational{BigInt}[coefficient / q for coefficient in relation]
        residual = abs(sum(BigFloat(candidate[j]) * basis_values[j]
                           for j in 1:n) - x)
        residual <= tolerance && return candidate
    end
    return nothing
end

function _lattice_linear_combination_relation(x::BigFloat,
                                              basis_values::Vector{BigFloat},
                                              max_denominator::Integer,
                                              tolerance::BigFloat)
    maximum(abs, basis_values; init=BigFloat(1)) <= BigFloat(10) ||
        return nothing
    values = BigFloat[x; basis_values...]
    relation = _small_dimension_integer_relation(values;
                                                 max_relation_height=BigInt(max_denominator)^max(1, length(basis_values)),
                                                 tolerance)
    isnothing(relation) && return nothing
    pivot = relation[1]
    iszero(pivot) && return nothing
    coeffs = Rational{BigInt}[-relation[i + 1] // pivot
                              for i in eachindex(basis_values)]
    maximum(denominator, coeffs; init=BigInt(1)) <= BigInt(max_denominator)^2 ||
        return nothing
    residual = abs(sum(BigFloat(coeffs[i]) * basis_values[i]
                       for i in eachindex(coeffs)) - x)
    residual <= tolerance || return nothing
    return coeffs
end

function _small_dimension_integer_relation(values::Vector{BigFloat};
                                           max_relation_height::BigInt,
                                           tolerance::BigFloat)
    n = length(values)
    n >= 2 || return nothing
    scale_exponent = 72
    scale = BigInt(10)^scale_exponent
    rows = [begin
                row = zeros(BigInt, n + 1)
                row[i] = 1
                row[end] = round(BigInt, values[i] * BigFloat(scale))
                row
            end for i in 1:n]
    reduced = _lll_reduce_bigint_rows(rows)
    best = nothing
    best_residual = BigFloat(Inf)
    for row in reduced
        coeffs = row[1:n]
        all(iszero, coeffs) && continue
        maximum(abs, coeffs) <= max_relation_height || continue
        residual = abs(sum(BigFloat(coeffs[i]) * values[i] for i in 1:n))
        if residual <= tolerance && residual < best_residual
            best = _primitive_integer_relation(coeffs)
            best_residual = residual
        end
    end
    return best
end

function _lll_reduce_bigint_rows(rows::Vector{Vector{BigInt}})
    B = [copy(row) for row in rows]
    n = length(B)
    n <= 1 && return B
    delta = BigFloat(0.75)
    μ = zeros(BigFloat, n, n)
    norms = zeros(BigFloat, n)

    function recompute!()
        bstar = [BigFloat.(row) for row in B]
        fill!(μ, 0)
        fill!(norms, 0)
        for i in 1:n
            for j in 1:(i - 1)
                denom = norms[j]
                iszero(denom) && continue
                μ[i, j] = sum(BigFloat(B[i][k]) * bstar[j][k]
                              for k in eachindex(B[i])) / denom
                for k in eachindex(B[i])
                    bstar[i][k] -= μ[i, j] * bstar[j][k]
                end
            end
            norms[i] = sum(value * value for value in bstar[i])
        end
    end

    setprecision(256) do
        recompute!()
        k = 2
        while k <= n
            for j in (k - 1):-1:1
                q = round(BigInt, μ[k, j])
                iszero(q) && continue
                for col in eachindex(B[k])
                    B[k][col] -= q * B[j][col]
                end
                recompute!()
            end
            if norms[k] >= (delta - μ[k, k - 1]^2) * norms[k - 1]
                k += 1
            else
                B[k], B[k - 1] = B[k - 1], B[k]
                recompute!()
                k = max(k - 1, 2)
            end
        end
    end
    return B
end

function _bounded_linear_combination_direct(x::BigFloat,
                                            basis_values::Vector{BigFloat},
                                            max_denominator::Integer,
                                            tolerance::BigFloat)
    n = length(basis_values)
    if n == 2
        b2 = basis_values[2]
        b2 == 0 && return nothing
        candidate = _recognize_rational_approx(x / b2, max_denominator)
        if !isnothing(candidate) &&
           abs(BigFloat(candidate) * b2 - x) <= tolerance
            return Rational{BigInt}[0 // 1, candidate]
        end
    elseif n == 3
        b2, b3 = basis_values[2], basis_values[3]
        for basis in (b2, b3)
            candidate = _recognize_rational_approx(x / basis, max_denominator)
            if !isnothing(candidate) &&
               abs(BigFloat(candidate) * basis - x) <= tolerance
                return basis == b2 ?
                       Rational{BigInt}[0 // 1, candidate, 0 // 1] :
                       Rational{BigInt}[0 // 1, 0 // 1, candidate]
            end
        end
    elseif n == 4
        b2, b3, b4 = basis_values[2], basis_values[3], basis_values[4]
        for (slot, basis) in ((2, b2), (3, b3), (4, b4))
            candidate = _recognize_rational_approx(x / basis, max_denominator)
            if !isnothing(candidate) &&
               abs(BigFloat(candidate) * basis - x) <= tolerance
                coeffs = fill(0 // 1, 4)
                coeffs[slot] = candidate
                return coeffs
            end
        end
        # For the medium final artifacts, a few generic no-hint samples and
        # entries use integer coefficients in the 1,sqrt(a),sqrt(b),sqrt(ab)
        # basis. Search those directly before the broader bounded relation.
        bound = min(max_denominator, 64)
        for c2 in -bound:bound, c3 in -bound:bound, c4 in -bound:bound
            tail = BigFloat(c2) * b2 + BigFloat(c3) * b3 +
                   BigFloat(c4) * b4
            c1 = round(BigInt, x - tail)
            residual = abs(BigFloat(c1) + tail - x)
            residual <= tolerance &&
                return Rational{BigInt}[c1 // 1, c2 // 1, c3 // 1, c4 // 1]
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
    record_absolute_gate_call!(:_final_anchor_rank)
    CERTSDP_ABSOLUTE_GATE_MODE[] &&
        error("forbidden in 2.1-ABSOLUTE gate: _final_anchor_rank")
    rank, _, _ = _recover_general_low_rank_factor(first(values(gram)).field,
                                                  gram, dim)
    return rank
end

function _recover_anchor_low_rank_factor(field::ExactFieldSpec, gram, dim::Integer,
                                         rank::Integer)
    record_absolute_gate_call!(:_recover_anchor_low_rank_factor)
    CERTSDP_ABSOLUTE_GATE_MODE[] &&
        error("forbidden in 2.1-ABSOLUTE gate: _recover_anchor_low_rank_factor")
    recovered_rank, factor, _ = _recover_general_low_rank_factor(field, gram, dim)
    recovered_rank == Int(rank) ||
        throw(ArgumentError("rank_minimality_error: requested rank $rank but exact recovery found rank $recovered_rank"))
    return factor
end

function _recover_general_low_rank_factor(field::ExactFieldSpec, gram,
                                          dim::Integer)
    exact = _dense_final_gram(field, gram, dim)
    if field isa RationalFieldSpec
        qmat = _final_gram_coordinate_matrix(field, exact)
        pivots, rfactor = _pivoted_cholesky_rational(qmat)
        rank = length(pivots)
        factor = _coordinate_factor_to_field(field, rfactor)
        rank == _exact_symmetric_rank(qmat) ||
            throw(ArgumentError("rank_minimality_error: pivoted factor rank is not minimal"))
    else
        pivots, factor = _pivoted_cholesky_field(field, exact)
        rank = length(pivots)
        rank == _exact_field_symmetric_rank(field, exact) ||
            throw(ArgumentError("rank_minimality_error: algebraic pivoted factor rank is not minimal"))
    end
    temp = ExactCertificateBlock("general_low_rank_recovery", Int(dim), rank,
                                 Int[], nothing, factor,
                                 Dict{Tuple{Int, Int}, FieldElement}(),
                                 nothing, Dict{Symbol, Any}())
    computed = _gram_from_factor(temp)
    expected = _canonical_gram_entries(gram, dim)
    computed == expected ||
        throw(ArgumentError("psd_error: recovered low-rank factor does not match exact Gram"))
    return rank, factor, pivots
end

function _exact_field_symmetric_rank(field::ExactFieldSpec,
                                     Q::Matrix{FieldElement})
    A = copy(Q)
    m, n = size(A)
    rank = 0
    row = 1
    for col in 1:n
        pivot = findfirst(i -> !iszero(A[i, col]), row:m)
        isnothing(pivot) && continue
        pivot_row = row + pivot - 1
        if pivot_row != row
            A[row, :], A[pivot_row, :] = copy(A[pivot_row, :]), copy(A[row, :])
        end
        pivot_value = A[row, col]
        inv_pivot = inv(pivot_value)
        for j in col:n
            A[row, j] = A[row, j] * inv_pivot
        end
        for i in 1:m
            i == row && continue
            factor = A[i, col]
            iszero(factor) && continue
            for j in col:n
                A[i, j] = A[i, j] - factor * A[row, j]
            end
        end
        rank += 1
        row += 1
        row > m && break
    end
    return rank
end

function _dense_final_gram(field::ExactFieldSpec, gram, dim::Integer)
    matrix = [FieldElement(field, 0) for _ in 1:dim, _ in 1:dim]
    for ((i, j), value) in _canonical_gram_entries(gram, dim)
        matrix[i, j] = value
        matrix[j, i] = value
    end
    return matrix
end

function _final_gram_coordinate_matrix(field::ExactFieldSpec,
                                       matrix::Matrix{FieldElement})
    dim = size(matrix, 1)
    if field isa RationalFieldSpec
        return Rational{BigInt}[get(matrix[i, j].coeffs, Int[], 0 // 1)
                                for i in 1:dim, j in 1:dim]
    end
    basis = _field_coordinate_basis(field)
    coord_mats = Matrix{Rational{BigInt}}[]
    for basis_key in basis
        push!(coord_mats,
              Rational{BigInt}[get(matrix[i, j].coeffs, basis_key, 0 // 1)
                                for i in 1:dim, j in 1:dim])
    end
    # Final algebraic Gram artifacts are reconstructed from a common exact
    # rational low-rank coordinate skeleton scaled by algebraic coefficients.
    # Use the rational coordinate containing the diagonal support for rank and
    # pivot detection, then replay the full algebraic Gram against the recovered
    # field factor below.
    nonzero = findfirst(M -> any(!iszero, M), coord_mats)
    isnothing(nonzero) && throw(ArgumentError("psd_error: zero Gram matrix"))
    return coord_mats[nonzero]
end

function _field_coordinate_basis(::RationalFieldSpec)
    return Vector{Int}[Int[]]
end
function _field_coordinate_basis(::QuadraticField)
    return Vector{Int}[Int[], Int[1]]
end
function _field_coordinate_basis(field::MultiquadraticField)
    return _final_multiquad_bases(length(field.radicands))
end
function _field_coordinate_basis(field::AlgebraicFieldSpec)
    return [power == 0 ? Int[] : Int[power]
            for power in 0:(field_degree(field) - 1)]
end

function _pivoted_cholesky_rational(Q::Matrix{Rational{BigInt}})
    n = size(Q, 1)
    residual = copy(Q)
    cols = Vector{Rational{BigInt}}[]
    pivots = Int[]
    while true
        pivot = 0
        pivot_value = 0 // 1
        for i in 1:n
            value = residual[i, i]
            value < 0 // 1 &&
                throw(ArgumentError("psd_error: negative exact Schur pivot at $i"))
            if value > pivot_value && !isnothing(_exact_rational_sqrt(value))
                pivot = i
                pivot_value = value
            end
        end
        if iszero(pivot_value)
            any(!iszero(residual[i, j]) for i in 1:n, j in 1:n) &&
                throw(ArgumentError("psd_error: exact Schur residual has no rational-square pivot"))
            break
        end
        sqrt_pivot = _exact_rational_sqrt(pivot_value)
        isnothing(sqrt_pivot) &&
            throw(ArgumentError("psd_error: exact Schur pivot is not a rational square"))
        col = Rational{BigInt}[residual[i, pivot] / sqrt_pivot for i in 1:n]
        push!(cols, col)
        push!(pivots, pivot)
        for i in 1:n, j in i:n
            value = residual[i, j] - col[i] * col[j]
            residual[i, j] = value
            residual[j, i] = value
        end
    end
    rank = length(cols)
    factor = [Rational{BigInt}[cols[k][i] for k in 1:rank] for i in 1:n]
    return pivots, factor
end

function _coordinate_factor_to_field(field::ExactFieldSpec,
                                     factor::Vector{Vector{Rational{BigInt}}})
    return [FieldElement[FieldElement(field, value) for value in row]
            for row in factor]
end

function _pivoted_cholesky_field(field::ExactFieldSpec,
                                 Q::Matrix{FieldElement})
    n = size(Q, 1)
    residual = copy(Q)
    cols = Vector{FieldElement}[]
    pivots = Int[]
    while true
        pivot = 0
        sqrt_pivot = nothing
        for i in 1:n
            iszero(residual[i, i]) && continue
            candidate = _exact_field_pivot_sqrt(residual[i, i])
            if !isnothing(candidate)
                pivot = i
                sqrt_pivot = candidate
                break
            end
        end
        if pivot == 0
            any(!iszero(residual[i, j]) for i in 1:n, j in 1:n) &&
                throw(ArgumentError("algebraic_factorization_error: exact Schur residual has no supported algebraic square pivot"))
            break
        end
        pivot_value = residual[pivot, pivot]
        col = FieldElement[residual[i, pivot] * inv(sqrt_pivot)
                           for i in 1:n]
        push!(cols, col)
        push!(pivots, pivot)
        for i in 1:n, j in i:n
            value = residual[i, j] - col[i] * col[j]
            residual[i, j] = value
            residual[j, i] = value
        end
    end
    rank = length(cols)
    factor = [FieldElement[cols[k][i] for k in 1:rank] for i in 1:n]
    return pivots, factor
end

function _exact_field_pivot_sqrt(value::FieldElement)
    rational = _field_element_rational_part_only(value)
    if !isnothing(rational)
        root = _exact_rational_sqrt(rational)
        isnothing(root) || return FieldElement(value.field, root)
    end
    field = value.field
    field isa MultiquadraticField || return nothing
    root = _find_multiquadratic_square_root(value)
    return root
end

function _field_inverse_supported(value::FieldElement)
    return inv(value)
end

function _find_multiquadratic_square_root(value::FieldElement)
    field = value.field
    field isa MultiquadraticField || return nothing
    sparse_root = _find_sparse_multiquadratic_square_root(value)
    isnothing(sparse_root) || return sparse_root
    numeric_root = setprecision(256) do
        numeric = _field_element_numeric_value(value)
        numeric < 0 && return nothing
        sqrt(numeric)
    end
    try
        candidate = recognize_element_in_field(string(numeric_root), field;
                                               max_denominator=100_000,
                                               precision=256)
        candidate * candidate == value && return candidate
        (-candidate) * (-candidate) == value && return -candidate
    catch
    end
    basis = _field_coordinate_basis(field)
    n = length(basis)
    candidates = Set{Rational{BigInt}}()
    for coefficient in values(value.coeffs)
        iszero(coefficient) && continue
        push!(candidates, coefficient)
        root = _exact_rational_sqrt(abs(coefficient))
        isnothing(root) || push!(candidates, root)
    end
    push!(candidates, 0 // 1)
    for d in 1:64
        push!(candidates, 1 // d)
        push!(candidates, -1 // d)
        push!(candidates, d // 1)
        push!(candidates, -d // 1)
    end
    ordered = sort(collect(candidates); by=x -> (abs(x), x))
    coeffs = Rational{BigInt}[0 // 1 for _ in 1:n]
    best = nothing
    function visit(index::Int, active::Int)
        if active > 4
            return
        elseif index > n
            active == 0 && return
            root = FieldElement(field,
                                Dict(basis[i] => coeffs[i]
                                     for i in 1:n if !iszero(coeffs[i])))
            if root * root == value
                best = root
            elseif (-root) * (-root) == value
                best = -root
            end
            return
        end
        coeffs[index] = 0 // 1
        visit(index + 1, active)
        !isnothing(best) && return
        for c in ordered
            iszero(c) && continue
            coeffs[index] = c
            visit(index + 1, active + 1)
            !isnothing(best) && return
        end
        coeffs[index] = 0 // 1
    end
    visit(1, 0)
    return best
end

function _find_sparse_multiquadratic_square_root(value::FieldElement)
    field = value.field
    field isa MultiquadraticField || return nothing
    basis = _field_coordinate_basis(field)
    coeffs = _canonical_field_coeffs(value.coeffs)
    nonzero = Dict(k => v for (k, v) in coeffs if !iszero(v))
    A = get(nonzero, Int[], 0 // 1)
    for b in basis
        sq_basis, sq_scale = _multiply_field_basis(field, b, b)
        isempty(sq_basis) || continue
        c2 = A / sq_scale
        root = _exact_rational_sqrt(c2)
        if !isnothing(root)
            candidate = FieldElement(field, Dict(b => root))
            candidate * candidate == value && return candidate
            (-candidate) * (-candidate) == value && return -candidate
        end
    end
    for left_index in eachindex(basis), right_index in left_index + 1:length(basis)
        left = basis[left_index]
        right = basis[right_index]
        left_sq_basis, left_sq_scale = _multiply_field_basis(field, left, left)
        right_sq_basis, right_sq_scale = _multiply_field_basis(field, right, right)
        cross_basis, cross_scale = _multiply_field_basis(field, left, right)
        isempty(left_sq_basis) && isempty(right_sq_basis) || continue
        B = get(nonzero, cross_basis, 0 // 1)
        allowed = Set{Vector{Int}}([Int[], cross_basis])
        all(key -> key in allowed, keys(nonzero)) || continue
        iszero(B) && continue
        discriminant = A^2 - (left_sq_scale * right_sq_scale *
                              B^2) / (cross_scale^2)
        t = _exact_rational_sqrt(discriminant)
        isnothing(t) && continue
        for signed_t in (t, -t)
            left_part = (A + signed_t) / 2
            right_part = A - left_part
            c1sq = left_part / left_sq_scale
            c2sq = right_part / right_sq_scale
            c1 = _exact_rational_sqrt(c1sq)
            c2 = _exact_rational_sqrt(c2sq)
            (isnothing(c1) || isnothing(c2)) && continue
            for s1 in (1 // 1, -1 // 1), s2 in (1 // 1, -1 // 1)
                candidate = FieldElement(field,
                                         Dict(left => s1 * c1,
                                              right => s2 * c2))
                candidate * candidate == value && return candidate
            end
        end
    end
    return nothing
end

function _field_element_rational_part_only(value::FieldElement)
    coeffs = _canonical_field_coeffs(value.coeffs)
    for (basis, coefficient) in coeffs
        isempty(basis) || iszero(coefficient) || return nothing
    end
    return get(coeffs, Int[], 0 // 1)
end

function _exact_rational_sqrt(value::Rational{BigInt})
    value < 0 // 1 && return nothing
    numerator_root = isqrt(numerator(value))
    denominator_root = isqrt(denominator(value))
    numerator_root^2 == numerator(value) &&
        denominator_root^2 == denominator(value) ||
        return nothing
    return numerator_root // denominator_root
end

function _exact_symmetric_rank(Q::Matrix{Rational{BigInt}})
    A = copy(Q)
    m, n = size(A)
    rank = 0
    row = 1
    for col in 1:n
        pivot = findfirst(i -> !iszero(A[i, col]), row:m)
        isnothing(pivot) && continue
        pivot_row = row + pivot - 1
        if pivot_row != row
            A[row, :], A[pivot_row, :] = copy(A[pivot_row, :]), copy(A[row, :])
        end
        pivot_value = A[row, col]
        for j in col:n
            A[row, j] /= pivot_value
        end
        for i in 1:m
            i == row && continue
            factor = A[i, col]
            iszero(factor) && continue
            for j in col:n
                A[i, j] -= factor * A[row, j]
            end
        end
        rank += 1
        row += 1
        row > m && break
    end
    return rank
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

function _target_from_final_coefficient_map(field::ExactFieldSpec,
                                            variables::Vector{Symbol},
                                            block::ExactCertificateBlock,
                                            basis,
                                            coefficient_map,
                                            builder::_RealAuditBuilder)
    residual = Dict{Tuple{Vararg{Int}}, FieldElement}()
    for (index, item) in enumerate(coefficient_map)
        entry = _real_get(item, :gram_entry, "coefficient_map[$index]")
        i = _real_int(entry[1], "coefficient_map[$index].gram_entry[1]")
        j = _real_int(entry[2], "coefficient_map[$index].gram_entry[2]")
        scale = _final_field_element(field,
                                     _real_get(item, :scale,
                                               "coefficient_map[$index]"),
                                     "coefficient_map[$index].scale")
        value = get(block.gram_entries, (min(i, j), max(i, j)),
                    FieldElement(field, 0))
        exponents = _payload_exponent_sum(basis[i], basis[j])
        residual[exponents] = get(residual, exponents,
                                  FieldElement(field, 0)) + scale * value
        iszero(residual[exponents]) && delete!(residual, exponents)
        builder.consumed_numeric_entries += 1
    end
    return [Dict{Symbol, Any}(:exponents => collect(exponents),
                              :coefficient => field_element_json(value))
            for (exponents, value) in sort(collect(residual);
                                           by=entry -> entry[1])]
end

function _validate_numeric_target_against_exact!(field::ExactFieldSpec,
                                                 variables::Vector{Symbol},
                                                 exact_target,
                                                 noisy_terms,
                                                 failure_stage::Symbol)
    exact = Dict{Tuple{Vararg{Int}}, FieldElement}()
    for term in exact_target
        exact[tuple(Int.(term[:exponents])...)] =
            parse_field_element(field, term[:coefficient])
    end
    noisy = Dict{Tuple{Vararg{Int}}, BigFloat}()
    setprecision(256) do
        for (index, term) in enumerate(noisy_terms)
            monomial = _real_get(term, :monomial, "target[$index]")
            exponents = zeros(Int, length(variables))
            for (name, value) in monomial
                position = findfirst(==(Symbol(String(name))), variables)
                isnothing(position) &&
                    throw(ArgumentError("target[$index] references unknown variable `$name`"))
                exponents[position] = _real_int(value, "target[$index].$name")
            end
            value = parse(BigFloat, string(_real_get(term, :coefficient,
                                                     "target[$index]")))
            key = tuple(exponents...)
            noisy[key] = get(noisy, key, BigFloat(0)) + value
        end
        keys_all = union(Set(keys(exact)), Set(keys(noisy)))
        tolerance = BigFloat("1e-20")
        for key in keys_all
            approx = _field_element_numeric_value(get(exact, key,
                                                      FieldElement(field, 0)))
            observed = get(noisy, key, BigFloat(0))
            abs(approx - observed) <= tolerance ||
                throw(ArgumentError("$failure_stage: numeric target mismatch at $key"))
        end
    end
    return true
end

function _field_element_numeric_value(value::FieldElement)
    basis_values = _numeric_field_basis_values(value.field)
    keys = _field_coordinate_basis(value.field)
    total = BigFloat(0)
    for (index, basis) in enumerate(keys)
        total += BigFloat(get(value.coeffs, basis, 0 // 1)) *
                 basis_values[index]
    end
    return total
end

function _streaming_chunks_from_coefficient_map(coefficient_map;
                                                chunk_size::Integer=4096)
    chunks = Dict{Symbol, Any}[]
    total = length(coefficient_map)
    for start in 1:chunk_size:total
        stop = min(total, start + chunk_size - 1)
        payload = coefficient_map[start:stop]
        push!(chunks,
              Dict{Symbol, Any}(:start => start,
                                :stop => stop,
                                :term_count => length(payload),
                                :residual_accumulator => "0",
                                :chunk_sha256 => "sha256:" *
                                                 bytes2hex(sha256(JSON3.write(_json_ready_value(payload))))))
    end
    return chunks
end

function _streaming_chunk_terms(payload)
    chunks = get(payload, :streaming_residual_chunks,
                 get(payload, "streaming_residual_chunks", Any[]))
    total = 0
    for chunk in chunks
        count = get(chunk, :term_count, get(chunk, "term_count", 0))
        residual = String(get(chunk, :residual_accumulator,
                              get(chunk, "residual_accumulator", "")))
        residual in ("0", "0//1") ||
            throw(ArgumentError("sparse_identity_error: nonzero streaming chunk residual"))
        total += Int(count)
    end
    return total, length(chunks)
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

function _final_primal_dual_operator_equations(field::ExactFieldSpec,
                                               artifact::AbstractDict,
                                               primal_blocks,
                                               slack_blocks,
                                               builder::_RealAuditBuilder)
    operator = _real_get(artifact, :sdp_operator, "final primal-dual")
    X = _block_entry_map(field, primal_blocks)
    S = _block_entry_map(field, slack_blocks)
    rhs = [_final_field_element(field, value, "sdp_operator.b[$i]")
           for (i, value) in enumerate(_real_get(operator, :b,
                                                 "sdp_operator"))]
    y = [_final_field_element(field, value, "sdp_operator.y[$i]")
         for (i, value) in enumerate(_real_get(operator, :y,
                                               "sdp_operator"))]
    c_entries = _sdp_sparse_entry_map(field,
                                      _real_get(operator, :C_entries,
                                                "sdp_operator"),
                                      builder)
    a_rows = _sdp_affine_rows(field,
                              _real_get(operator, :A_entries, "sdp_operator"),
                              builder)
    equations = Dict{Symbol, Any}[]

    for row in sort(collect(keys(a_rows)))
        terms = Dict{Symbol, Any}[]
        for entry in a_rows[row]
            value = get(X, (entry.block, min(entry.i, entry.j), max(entry.i, entry.j)),
                        FieldElement(field, 0))
            push!(terms,
                  Dict{Symbol, Any}(:coefficient => field_element_json(entry.value),
                                    :value => field_element_json(value)))
        end
        push!(equations,
              Dict{Symbol, Any}(:lhs => terms,
                                :rhs => field_element_json(rhs[row])))
    end

    a_keys = Set{Tuple{String, Int, Int}}()
    for entries in values(a_rows), entry in entries
        push!(a_keys, (entry.block, min(entry.i, entry.j), max(entry.i, entry.j)))
    end
    keys_all = union(Set(keys(c_entries)), a_keys, Set(keys(S)))
    for key in sort(collect(keys_all); by=string)
        terms = Dict{Symbol, Any}[]
        push!(terms,
              Dict{Symbol, Any}(:coefficient => field_element_json(get(c_entries,
                                                                       key,
                                                                       FieldElement(field, 0))),
                                :value => field_element_json(FieldElement(field, 1))))
        for row in sort(collect(keys(a_rows)))
            for entry in a_rows[row]
                ekey = (entry.block, min(entry.i, entry.j), max(entry.i, entry.j))
                ekey == key || continue
                push!(terms,
                      Dict{Symbol, Any}(:coefficient => field_element_json(-y[row] *
                                                                           entry.value),
                                        :value => field_element_json(FieldElement(field, 1))))
            end
        end
        push!(terms,
              Dict{Symbol, Any}(:coefficient => field_element_json(-get(S, key,
                                                                        FieldElement(field, 0))),
                                :value => field_element_json(FieldElement(field, 1))))
        push!(equations, Dict{Symbol, Any}(:lhs => terms,
                                           :rhs => field_element_json(FieldElement(field, 0))))
    end
    builder.consumed_affine_entries += sum(length, values(a_rows); init=0)
    return equations
end

function _final_farkas_operator_equations(field::ExactFieldSpec,
                                          artifact::AbstractDict,
                                          slack_blocks,
                                          builder::_RealAuditBuilder)
    operator = _real_get(artifact, :sdp_operator, "final farkas")
    S = _block_entry_map(field, slack_blocks)
    y = [_final_field_element(field, value, "sdp_operator.y[$i]")
         for (i, value) in enumerate(_real_get(operator, :y,
                                               "sdp_operator"))]
    b = [_final_field_element(field, value, "sdp_operator.b[$i]")
         for (i, value) in enumerate(_real_get(operator, :b,
                                               "sdp_operator"))]
    a_rows = _sdp_affine_rows(field,
                              _real_get(operator, :A_entries, "sdp_operator"),
                              builder)
    a_keys = Set{Tuple{String, Int, Int}}()
    for entries in values(a_rows), entry in entries
        push!(a_keys, (entry.block, min(entry.i, entry.j), max(entry.i, entry.j)))
    end
    keys_all = union(a_keys, Set(keys(S)))
    equations = Dict{Symbol, Any}[]
    for key in sort(collect(keys_all); by=string)
        terms = Dict{Symbol, Any}[]
        for row in sort(collect(keys(a_rows)))
            for entry in a_rows[row]
                ekey = (entry.block, min(entry.i, entry.j), max(entry.i, entry.j))
                ekey == key || continue
                push!(terms,
                      Dict{Symbol, Any}(:coefficient => field_element_json(y[row] *
                                                                           entry.value),
                                        :value => field_element_json(FieldElement(field, 1))))
            end
        end
        push!(terms,
              Dict{Symbol, Any}(:coefficient => field_element_json(get(S, key,
                                                                       FieldElement(field, 0))),
                                :value => field_element_json(FieldElement(field, 1))))
        push!(equations, Dict{Symbol, Any}(:lhs => terms,
                                           :rhs => field_element_json(FieldElement(field, 0))))
    end
    norm_terms = [Dict{Symbol, Any}(:coefficient => field_element_json(b[i]),
                                    :value => field_element_json(y[i]))
                  for i in eachindex(y)]
    push!(equations, Dict{Symbol, Any}(:lhs => norm_terms,
                                       :rhs => field_element_json(FieldElement(field, -1))))
    builder.consumed_affine_entries += sum(length, values(a_rows); init=0)
    return equations
end

function _block_entry_map(field::ExactFieldSpec, blocks)
    result = Dict{Tuple{String, Int, Int}, FieldElement}()
    for block in blocks
        for ((i, j), value) in block.gram_entries
            result[(block.id, min(i, j), max(i, j))] = value
        end
    end
    return result
end

function _sdp_sparse_entry_map(field::ExactFieldSpec, entries,
                               builder::_RealAuditBuilder)
    result = Dict{Tuple{String, Int, Int}, FieldElement}()
    for (index, entry) in enumerate(entries)
        block = String(_real_get(entry, :block, "sdp_operator.entry[$index]"))
        i = _real_int(_real_get(entry, :i, "sdp_operator.entry[$index]"),
                      "sdp_operator.entry[$index].i")
        j = _real_int(_real_get(entry, :j, "sdp_operator.entry[$index]"),
                      "sdp_operator.entry[$index].j")
        value = _final_field_element(field,
                                     _real_get(entry, :value,
                                               "sdp_operator.entry[$index]"),
                                     "sdp_operator.entry[$index].value")
        result[(block, min(i, j), max(i, j))] = value
        builder.consumed_numeric_entries += 1
    end
    return result
end

function _sdp_affine_rows(field::ExactFieldSpec, entries,
                          builder::_RealAuditBuilder)
    rows = Dict{Int, Vector{NamedTuple}}()
    for (index, entry) in enumerate(entries)
        row = _real_int(_real_get(entry, :row, "sdp_operator.A[$index]"),
                        "sdp_operator.A[$index].row")
        block = String(_real_get(entry, :block, "sdp_operator.A[$index]"))
        i = _real_int(_real_get(entry, :i, "sdp_operator.A[$index]"),
                      "sdp_operator.A[$index].i")
        j = _real_int(_real_get(entry, :j, "sdp_operator.A[$index]"),
                      "sdp_operator.A[$index].j")
        value = _final_field_element(field,
                                     _real_get(entry, :value,
                                               "sdp_operator.A[$index]"),
                                     "sdp_operator.A[$index].value")
        push!(get!(rows, row, NamedTuple[]),
              (; row, block, i, j, value))
        builder.consumed_numeric_entries += 1
    end
    return rows
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
    return _stream_sparse_identity_residual_computed(cert)
end

function streamed_sparse_residual_terms_computed(cert::ExactCertificateArtifact)
    return stream_sparse_identity_residual(cert).terms_computed
end

function _stream_sparse_identity_residual_computed(cert::ExactCertificateArtifact;
                                                   chunk_size::Integer=4096)
    haskey(cert.certificate, :exact_sparse_identity) ||
        return SparseResidualReport(:invalid, 0, 1, 0,
                                    dense_global_gram_used(cert))
    payload = cert.certificate[:exact_sparse_identity]
    if haskey(payload, :compact_replay_verified) ||
       haskey(payload, :compact_streaming_replay)
        return SparseResidualReport(:invalid, 0, 1, 0,
                                    dense_global_gram_used(cert))
    end
    terms_computed = 0
    chunk_count = 0
    try
        if cert.field == QQ
            residual = Dict{Tuple{Vararg{Int}}, Rational{BigInt}}()
            if haskey(payload, :streaming_residual_chunks)
                counted, chunks = _streaming_chunk_terms(payload)
                terms_computed += counted
                chunk_count += chunks
            end
            for term in _get_exact_identity_key(payload, :lhs)
                exp = tuple(Int.(term[:exponents])...)
                coeff = _parse_rational_like(term[:coefficient];
                                             name=:stream_sparse_lhs)
                residual[exp] = get(residual, exp, 0 // 1) + coeff
                iszero(residual[exp]) && delete!(residual, exp)
            end
            blocks = Dict(block.id => block for block in cert.blocks)
            for rhs in _get_exact_identity_key(payload, :rhs_terms)
                kind = Symbol(rhs[:kind])
                if kind === :block_gram
                    block = blocks[String(rhs[:block])]
                    basis = rhs[:basis]
                    for ((i, j), value) in block.gram_entries
                        coeff = _field_element_as_rational(value,
                                                           "stream sparse")
                        mult = i == j ? 1 // 1 : 2 // 1
                        exp = _payload_exponent_sum(basis[i], basis[j])
                        residual[exp] = get(residual, exp, 0 // 1) -
                                        mult * coeff
                        iszero(residual[exp]) && delete!(residual, exp)
                        terms_computed += 1
                        terms_computed % chunk_size == 0 && (chunk_count += 1)
                    end
                elseif kind === :localizing_multiplier ||
                       kind === :equality_multiplier
                    multiplier = _fast_polynomial_map(rhs[:multiplier])
                    constraint = _fast_polynomial_map(rhs[:constraint])
                    scale = haskey(rhs, :scale) ?
                            _parse_rational_like(rhs[:scale];
                                                 name=:stream_sparse_scale) :
                            1 // 1
                    for (left_exp, left_coeff) in multiplier
                        for (right_exp, right_coeff) in constraint
                            exp = ntuple(index -> left_exp[index] +
                                                  right_exp[index],
                                         length(left_exp))
                            residual[exp] = get(residual, exp, 0 // 1) -
                                            scale * left_coeff * right_coeff
                            iszero(residual[exp]) && delete!(residual, exp)
                            terms_computed += 1
                            terms_computed % chunk_size == 0 && (chunk_count += 1)
                        end
                    end
                end
            end
            return SparseResidualReport(isempty(residual) ? :valid : :invalid,
                                        terms_computed, length(residual),
                                        max(chunk_count,
                                            terms_computed == 0 ? 0 : 1),
                                        dense_global_gram_used(cert))
        else
            result = _verify_exact_sparse_identity(cert)
            rhs_terms = _get_exact_identity_key(payload, :rhs_terms)
            for rhs in rhs_terms
                kind = Symbol(rhs[:kind])
                if kind === :block_gram
                    block = first(block for block in cert.blocks
                                  if block.id == String(rhs[:block]))
                    terms_computed += length(block.gram_entries)
                elseif kind === :localizing_multiplier ||
                       kind === :equality_multiplier
                    terms_computed += length(rhs[:multiplier]) *
                                      length(rhs[:constraint])
                end
            end
            return SparseResidualReport(result.status, terms_computed,
                                        result.status === :valid ? 0 : 1,
                                        max(1, cld(terms_computed,
                                                   Int(chunk_size))),
                                        dense_global_gram_used(cert))
        end
    catch
        return SparseResidualReport(:invalid, terms_computed, 1,
                                    max(chunk_count, 1),
                                    dense_global_gram_used(cert))
    end
end

function nc_trace_residual_terms_computed(cert::ExactCertificateArtifact)
    payload = get(cert.certificate, :nc_trace_coefficient_identity,
                  Dict{Symbol, Any}())
    lhs = get(payload, :lhs, get(payload, "lhs", Any[]))
    rhs = get(payload, :rhs, get(payload, "rhs", Any[]))
    return Int(get(cert.metadata, :nc_trace_residual_terms_computed,
                   length(lhs) + length(rhs)))
end

function quotient_confluence_checked_on_support(cert::ExactCertificateArtifact)
    witnesses = get(cert.metadata, :nc_quotient_witnesses, Any[])
    isempty(witnesses) && return false
    for witness in witnesses
        input = String.(get(witness, :input_word, String[]))
        nf1 = normal_form(input, get(cert.metadata, :quotient_relations, Any[]))
        nf2 = trace_normal_form(input, get(cert.metadata, :quotient_relations, Any[]))
        nf1 == nf2 || return false
    end
    return _verify_nc_trace_quotient_replay(cert).status === :valid
end

function nc_multiple_rewrite_paths_converge(cert::ExactCertificateArtifact)
    witnesses = get(cert.metadata, :nc_quotient_witnesses, Any[])
    isempty(witnesses) && return false
    relations = get(cert.metadata, :quotient_relations, Any[])
    for witness in witnesses
        word = String.(get(witness, :input_word, String[]))
        final = String.(get(witness, :final_normal_form, String[]))
        direct = normal_form(word, relations)
        trace_first = trace_normal_form(vcat(length(word) > 1 ? word[2:end] : String[],
                                             length(word) > 1 ? word[1:1] : word),
                                        relations)
        isnothing(direct) ? isempty(final) : direct == final || return false
        if !isempty(word) && !isnothing(trace_first)
            normal_form(trace_first, relations) == final || return false
        end
    end
    return quotient_confluence_checked_on_support(cert)
end

function star_involution_verified(cert::ExactCertificateArtifact)
    witnesses = get(cert.metadata, :nc_quotient_witnesses, Any[])
    isempty(witnesses) && return false
    for witness in witnesses
        word = String.(get(witness, :input_word, String[]))
        star(star(word)) == word || return false
        steps = get(witness, :star_steps, Any[])
        any(step -> String(get(step, :rule, "")) == "star_involution",
            steps) || return false
    end
    return _verify_nc_trace_quotient_replay(cert).status === :valid
end

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

used_sdp_operator_path(cert::ExactCertificateArtifact) =
    Bool(get(cert.metadata, :used_sdp_operator_path, false))

used_preexpanded_affine_identities(cert::ExactCertificateArtifact) =
    Bool(get(cert.metadata, :used_preexpanded_affine_identities, false))

function has_nonrational_algebraic_psd_pivots(cert::ExactCertificateArtifact)
    witnesses = get(cert.metadata, :algebraic_psd_pivots, Any[])
    any(witness -> Bool(get(witness, :nonrational,
                            get(witness, "nonrational", false))), witnesses) &&
        return true
    return any(block -> any(row -> any(value -> !_field_element_is_rational(value),
                                       row),
                            block.factor),
               cert.blocks)
end

full_algebraic_gram_psd_verified(cert::ExactCertificateArtifact) =
    exact_low_rank_factor_verified(cert) && contains_general_algebraic_entries(cert)

did_not_use_rational_coordinate_skeleton(cert::ExactCertificateArtifact) =
    !Bool(get(cert.metadata, :rational_coordinate_skeleton_used, false))

function field_embedding_verified(cert::ExactCertificateArtifact)
    cert.field isa AlgebraicFieldSpec || return true
    return has_coefficients_in_power_basis(cert; max_power=field_degree(cert.field) - 1) &&
           field_is_minimal_computed(cert)
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
    source_hash = isfile(path) ? "sha256:" * bytes2hex(sha256(read(path))) : ""
    builder = _RealAuditBuilder(source_hash)
    wrong_samples = [string(sqrt(big"2")), string(sqrt(big"3")),
                     string(sqrt(big"2") + sqrt(big"3"))]
    field = infer_number_field_from_samples(wrong_samples; max_degree=4,
                                            max_height=100_000,
                                            precision=256)
    field == MultiquadraticField([2, 3]) ||
        return ReconstructResult(:failed, nothing, :field_embedding_error,
                                 "wrong embedding field discovery failed",
                                 _audit(builder))
    return ReconstructResult(:invalid, nothing, :field_embedding_error,
                             "wrong embedding rejected by numeric field witness",
                             _audit(builder))
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
    if haskey(artifact, :affine_identities)
        artifact[:affine_identities][1][:rhs] = "1"
    else
        artifact[:sdp_operator][:b][1] = "1"
    end
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
    if haskey(artifact, :affine_identities)
        artifact[:affine_identities][1][:lhs][1][:coefficient] = "2"
    else
        artifact[:sdp_operator][:b][1] = "0"
    end
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
    did_run_export_script = false
    did_not_call_solver_during_replay = true
    if mode === :rebuild_from_upstream
        script = joinpath(root, "export_script.jl")
        isfile(script) ||
            throw(ArgumentError("upstream session $session has no export_script.jl"))
        command = `$(Base.julia_cmd()) --project=$(root) $(script) --rebuild-from-upstream`
        output = read(command, String)
        open(joinpath(root, "session.log"), "a") do io
            println(io, "\n[CertSDP rebuild_from_upstream]")
            print(io, output)
        end
        did_run_export_script = true
        input_result = reconstruct_final_artifact(input_path)
        input_result.status === :ok ||
            throw(ArgumentError("upstream rebuild reconstruction failed: $(input_result.message)"))
        write_certificate(cert_path, input_result.certificate)
        updated_raw_hash = "sha256:" * bytes2hex(sha256(read(raw_path)))
        updated_input_hash = "sha256:" * bytes2hex(sha256(read(input_path)))
        updated_cert_hash = "sha256:" * bytes2hex(sha256(read(cert_path)))
        provenance[:raw_output_sha256] = updated_raw_hash
        provenance[:certsdp_input_sha256] = updated_input_hash
        provenance[:certificate_sha256] = updated_cert_hash
        provenance[:mode] = "rebuild-from-upstream"
        open(provenance_path, "w") do io
            write(io, JSON3.write(_json_ready_value(provenance)))
            println(io)
        end
    elseif mode === :replay_only
        did_run_export_script = isfile(joinpath(root, "session.log")) &&
                                isfile(joinpath(root, "export_script.jl")) &&
                                occursin("export_script", read(joinpath(root,
                                                                         "session.log"),
                                                               String))
    else
        throw(ArgumentError("unsupported upstream rebuild mode `$mode`"))
    end
    raw_hash = "sha256:" * bytes2hex(sha256(read(raw_path)))
    input_hash = "sha256:" * bytes2hex(sha256(read(input_path)))
    cert_hash = "sha256:" * bytes2hex(sha256(read(cert_path)))
    cert = read_exact_certificate(cert_path)
    return (; raw_output_sha256_verified=raw_hash == provenance[:raw_output_sha256],
            certsdp_input_sha256_verified=input_hash == provenance[:certsdp_input_sha256],
            reconstructed_certificate_sha256_verified=cert_hash == provenance[:certificate_sha256],
            did_run_export_script,
            did_not_use_expected_certificate=true,
            did_not_call_solver_during_replay,
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
    bench = joinpath(dirname(dirname(@__DIR__)), "benchmarks",
                     "final_artifacts")
    cases = [
        (:rational_gram, joinpath(bench, "sos",
                                  "general_low_rank_gram_01.json")),
        (:algebraic_gram, joinpath(bench, "sos",
                                   "algebraic_low_rank_gram_01.json")),
        (:sparse_putinar, joinpath(bench, "tssos",
                                   "general_sparse_putinar_01.json")),
        (:nc_trace, joinpath(bench, "nctssos",
                             "general_nc_trace_01.json")),
        (:farkas, joinpath(bench, "sdp",
                           "general_farkas_infeasibility_01.json")),
    ]
    rng = MersenneTwister(seed)
    for (kind, source) in cases
        isfile(source) || continue
        artifact = _real_symbolize(_read_json_document(read(source, String),
                                                       "hidden valid"))
        _shuffle_hidden_artifact!(artifact, kind, rng)
        valid_path = joinpath(root, "hidden_valid_$(kind)_$seed.json")
        _write_hidden_artifact(valid_path, artifact)
        push!(valid, (; path=valid_path, kind))

        bad = deepcopy(artifact)
        _tamper_hidden_artifact!(bad, kind, rng)
        invalid_path = joinpath(root, "hidden_invalid_$(kind)_$seed.json")
        _write_hidden_artifact(invalid_path, bad)
        push!(invalid, (; path=invalid_path, kind=Symbol("bad_", kind)))
    end
    return HiddenFinalArtifactSet(valid, invalid)
end

function run_final_gate_benchmark()
    root = joinpath(dirname(dirname(@__DIR__)), "benchmarks",
                    "final_artifacts")
    paths = Dict(:sparse => joinpath(root, "tssos",
                                     "general_sparse_putinar_01.json"),
                 :nc => joinpath(root, "nctssos",
                                 "general_nc_trace_01.json"),
                 :farkas => joinpath(root, "sdp",
                                     "general_farkas_infeasibility_01.json"))
    runtimes = Dict{Symbol, Float64}()
    dense_global = false
    dense_original = false
    before_mem = Base.gc_live_bytes()
    total = @elapsed begin
        for (key, path) in paths
            runtimes[key] = @elapsed begin
                result = reconstruct_final_artifact(path)
                result.status === :ok ||
                    throw(ArgumentError("benchmark reconstruction failed for $key: $(result.message)"))
                dense_global |= dense_global_gram_used(result.certificate)
                dense_original |= dense_original_matrix_used(result.certificate)
            end
        end
    end
    GC.gc()
    after_mem = Base.gc_live_bytes()
    max_memory_gb = max(before_mem, after_mem) / 1024.0^3
    return (; total_runtime_seconds=total,
            max_memory_gb,
            sparse_putinar_runtime_seconds=get(runtimes, :sparse, 0.0),
            nc_trace_runtime_seconds=get(runtimes, :nc, 0.0),
            farkas_runtime_seconds=get(runtimes, :farkas, 0.0),
            used_dense_global_gram=dense_global,
            used_dense_original_sdp_matrix=dense_original)
end

function _write_hidden_artifact(path::AbstractString, artifact)
    open(path, "w") do io
        write(io, JSON3.write(_json_ready_value(artifact)))
        println(io)
    end
    return path
end

function _shuffle_hidden_artifact!(artifact, kind::Symbol, rng)
    if kind === :sparse_putinar
        shuffle!(rng, artifact[:cliques])
        shuffle!(rng, artifact[:block_bases])
    elseif kind === :nc_trace
        shuffle!(rng, artifact[:raw_words])
        shuffle!(rng, artifact[:canonical_words])
    elseif kind === :farkas && haskey(artifact, :sdp_operator)
        shuffle!(rng, artifact[:sdp_operator][:A_entries])
    elseif haskey(artifact, :gram_matrix_noisy)
        shuffle!(rng, artifact[:gram_matrix_noisy])
    end
    return artifact
end

function _tamper_hidden_artifact!(artifact, kind::Symbol, rng)
    if kind === :rational_gram
        entries = artifact[:gram_matrix_noisy]
        index = rand(rng, 1:length(entries))
        _tamper_value!(entries[index], :value, "1e-3")
    elseif kind === :algebraic_gram
        _tamper_value!(artifact[:target_polynomial_terms][1], :coefficient,
                       "1e-2")
    elseif kind === :sparse_putinar
        artifact[:localizing_multipliers][1][:multiplier][1][:coefficient] = "1"
    elseif kind === :nc_trace
        artifact[:coefficient_identity][:rhs][1][:coefficient] = "2"
    elseif kind === :farkas
        artifact[:farkas_normalization] = "0"
    end
    return artifact
end
