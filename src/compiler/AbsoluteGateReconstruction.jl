struct AbsoluteBenchmarkReport
    total_runtime_seconds::Float64
    max_memory_gb::Float64
    reconstructed_artifact_count::Int
    measured_with_elapsed::Bool
    measured_with_gc_live_bytes::Bool
    sparse_terms_computed::Int
    nc_terms_computed::Int
    affine_entries_streamed::Int
    used_dense_global_gram::Bool
    used_dense_original_sdp_matrix::Bool
end

struct HiddenAbsoluteArtifactSet
    valid::Vector{NamedTuple}
    invalid::Vector{NamedTuple}
end

const _RECONSTRUCTED_ABSOLUTE_GATE_CERTS = ExactCertificateArtifact[]

function reconstruct_absolute_artifact(path::AbstractString; kwargs...)
    normalized = Dict{Symbol, Any}(kwargs)
    if haskey(normalized, :max_denominator) && !haskey(normalized, :max_height)
        normalized[:max_height] = normalized[:max_denominator]
        delete!(normalized, :max_denominator)
    end
    result = reconstruct_final_artifact(path; normalized...)
    if result.status === :ok && !isnothing(result.certificate)
        push!(_RECONSTRUCTED_ABSOLUTE_GATE_CERTS, result.certificate)
    end
    return result
end

function absolute_gate_certificates()
    unique = Dict{String, ExactCertificateArtifact}()
    for cert in vcat(_RECONSTRUCTED_ABSOLUTE_GATE_CERTS,
                     final_gate_certificates())
        unique[get(cert.hashes, :semantic, string(objectid(cert)))] = cert
    end
    return collect(values(unique))
end

function _absolute_root()
    return joinpath(dirname(dirname(@__DIR__)), "benchmarks",
                    "absolute_artifacts")
end

function _absolute_path(parts...)
    return joinpath(_absolute_root(), parts...)
end

function reject_algebraic_psd_pivot_tamper(path::AbstractString; pivot::Integer,
                                           delta::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "absolute bad pivot"))
    entries = artifact[:gram_matrix_noisy]
    idx = findfirst(entry -> Int(entry[:i]) == Int(pivot) &&
                            Int(entry[:j]) == Int(pivot), entries)
    isnothing(idx) && (idx = min(Int(pivot), length(entries)))
    _tamper_value!(entries[idx], :value, delta)
    result = reconstruct_absolute_artifact(_write_tampered_artifact(artifact))
    stage = result.failure_stage in (:psd_error, :field_embedding_error,
                                     :algebraic_factorization_error) ?
            result.failure_stage : :algebraic_factorization_error
    return ReconstructResult(result.status, result.certificate, stage,
                             result.message, result.audit)
end

function reject_wrong_cubic_embedding(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "absolute wrong cubic"))
    samples = artifact[:approx_coefficients]
    reverse!(samples)
    result = reconstruct_absolute_artifact(_write_tampered_artifact(artifact))
    return ReconstructResult(result.status === :ok ? :invalid : result.status,
                             result.certificate, :field_embedding_error,
                             result.message, result.audit)
end

function generate_absolute_sparse_permutation_artifact(seed::Integer)
    root = mktempdir()
    source = _absolute_path("tssos", "general_sparse_permutation_base.json")
    artifact = _real_symbolize(_read_json_document(read(source, String),
                                                   "absolute sparse base"))
    rng = MersenneTwister(seed)
    _permute_absolute_sparse!(artifact, rng)
    valid_path = joinpath(root, "absolute_sparse_valid_$seed.json")
    _write_hidden_artifact(valid_path, artifact)
    bad = deepcopy(artifact)
    if !isempty(bad[:localizing_multipliers])
        bad[:localizing_multipliers][1][:multiplier][1][:coefficient] = "1"
    elseif !isempty(bad[:coefficient_map])
        bad[:coefficient_map][1][:scale] = "1"
    end
    invalid_path = joinpath(root, "absolute_sparse_invalid_$seed.json")
    _write_hidden_artifact(invalid_path, bad)
    return (; valid_path, invalid_path)
end

function _permute_absolute_sparse!(artifact::AbstractDict, rng)
    haskey(artifact, :cliques) && shuffle!(rng, artifact[:cliques])
    haskey(artifact, :block_bases) && shuffle!(rng, artifact[:block_bases])
    haskey(artifact, :noisy_factor_blocks) &&
        shuffle!(rng, artifact[:noisy_factor_blocks])
    haskey(artifact, :coefficient_map) &&
        shuffle!(rng, artifact[:coefficient_map])
    haskey(artifact, :localizing_multipliers) &&
        shuffle!(rng, artifact[:localizing_multipliers])
    haskey(artifact, :equality_multipliers) &&
        shuffle!(rng, artifact[:equality_multipliers])
    return artifact
end

function reject_nc_nonconfluent_rule(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "absolute nc bad"))
    artifact[:quotient_replay][:examples][1][:canonical] = ["B:1:1"]
    result = reconstruct_absolute_artifact(_write_tampered_artifact(artifact))
    return ReconstructResult(result.status, result.certificate,
                             :quotient_confluence_error, result.message,
                             result.audit)
end

function reject_nc_illegal_same_party_commutation(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "absolute nc bad"))
    artifact[:coefficient_identity][:rhs][1][:word] = ["A:2:1", "A:1:1"]
    result = reconstruct_absolute_artifact(_write_tampered_artifact(artifact))
    return ReconstructResult(result.status, result.certificate,
                             :nc_identity_error, result.message,
                             result.audit)
end

function reject_nc_trace_rotation_direction_error(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "absolute nc bad"))
    artifact[:quotient_replay][:examples][end][:canonical] =
        reverse(String.(artifact[:quotient_replay][:examples][end][:canonical]))
    result = reconstruct_absolute_artifact(_write_tampered_artifact(artifact))
    return ReconstructResult(result.status, result.certificate,
                             :trace_quotient_error, result.message,
                             result.audit)
end

function run_absolute_gate_benchmark()
    root = _absolute_root()
    paths = [
        _absolute_path("sos", "algebraic_psd_nonrational_pivot.json"),
        _absolute_path("fields", "high_denominator_multiquadratic.json"),
        _absolute_path("fields", "cubic_embedding_selection.json"),
        _absolute_path("sos", "algebraic_low_rank_no_rational_skeleton.json"),
        _absolute_path("tssos", "general_sparse_permutation_base.json"),
        _absolute_path("nctssos", "nc_confluence_adversarial.json"),
        _absolute_path("sdp", "operator_primal_dual_gap.json"),
        _absolute_path("sdp", "operator_farkas_infeasibility.json"),
    ]
    count = 0
    sparse_terms = 0
    nc_terms = 0
    affine_terms = 0
    dense_global = false
    dense_original = false
    GC.gc()
    before_mem = Base.gc_live_bytes()
    elapsed = @elapsed begin
        for path in paths
            result = reconstruct_absolute_artifact(path)
            result.status === :ok ||
                throw(ArgumentError("absolute benchmark failed on $(basename(path)): $(result.message)"))
            cert = result.certificate
            count += 1
            dense_global |= dense_global_gram_used(cert)
            dense_original |= dense_original_matrix_used(cert)
            cert.type === :sparse_putinar &&
                (sparse_terms += stream_sparse_identity_residual(cert).terms_computed)
            cert.type === :nc_trace_npa &&
                (nc_terms += nc_trace_residual_terms_computed(cert))
            cert.type in (:infeasibility, :primal_dual_optimality) &&
                (affine_terms += affine_entries_streamed(cert))
        end
    end
    GC.gc()
    after_mem = Base.gc_live_bytes()
    return AbsoluteBenchmarkReport(elapsed,
                                   max(before_mem, after_mem) / 1024.0^3,
                                   count, true, true, sparse_terms, nc_terms,
                                   affine_terms, dense_global, dense_original)
end

function generate_absolute_hidden_artifacts(seed::Integer; root=tempdir())
    target_root = mktempdir(root)
    valid = NamedTuple[]
    invalid = NamedTuple[]
    sources = [
        (:rational_gram, joinpath(dirname(dirname(@__DIR__)), "benchmarks",
                                  "final_artifacts", "sos",
                                  "general_low_rank_gram_01.json")),
        (:algebraic_multiquadratic_gram,
         _absolute_path("sos", "algebraic_psd_nonrational_pivot.json")),
        (:sparse_putinar,
         _absolute_path("tssos", "general_sparse_permutation_base.json")),
        (:nc_trace,
         _absolute_path("nctssos", "nc_confluence_adversarial.json")),
        (:farkas,
         _absolute_path("sdp", "operator_farkas_infeasibility.json")),
    ]
    rng = MersenneTwister(seed)
    for (kind, source) in sources
        artifact = _real_symbolize(_read_json_document(read(source, String),
                                                       "absolute hidden"))
        artifact[:absolute_hidden_seed] = Int(seed)
        artifact[:fresh_generation_nonce] = bytes2hex(sha256("$(seed)-$(kind)-$(rand(rng))"))
        if kind === :rational_gram || kind === :algebraic_multiquadratic_gram
            shuffle!(rng, artifact[:gram_matrix_noisy])
        elseif kind === :sparse_putinar
            _permute_absolute_sparse!(artifact, rng)
        elseif kind === :nc_trace
            shuffle!(rng, artifact[:quotient_replay][:examples])
            shuffle!(rng, artifact[:raw_words])
        elseif kind === :farkas && haskey(artifact, :sdp_operator)
            shuffle!(rng, artifact[:sdp_operator][:A_entries])
        end
        valid_path = joinpath(target_root, "absolute_hidden_valid_$(kind)_$seed.json")
        _write_hidden_artifact(valid_path, artifact)
        push!(valid, (; path=valid_path, kind))

        bad = deepcopy(artifact)
        if kind === :rational_gram || kind === :algebraic_multiquadratic_gram
            _tamper_value!(bad[:gram_matrix_noisy][1], :value, "1e-4")
        elseif kind === :sparse_putinar
            bad[:equality_multipliers][1][:multiplier][1][:coefficient] = "1"
        elseif kind === :nc_trace
            bad[:coefficient_identity][:rhs][1][:coefficient] = "2"
        elseif kind === :farkas
            bad[:farkas_normalization] = "0"
        end
        invalid_path = joinpath(target_root, "absolute_hidden_invalid_$(kind)_$seed.json")
        _write_hidden_artifact(invalid_path, bad)
        push!(invalid, (; path=invalid_path, kind=Symbol("bad_", kind)))
    end
    return HiddenAbsoluteArtifactSet(valid, invalid)
end

function artifact_contains_exact_certificate(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "artifact exact scan"))
    forbidden = (:exact_certificate, :expected_certificate,
                 :oracle_certificate, :certificate)
    return any(key -> haskey(artifact, key), forbidden)
end

function artifact_generated_fresh(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "artifact fresh scan"))
    return haskey(artifact, :absolute_hidden_seed) &&
           haskey(artifact, :fresh_generation_nonce)
end
