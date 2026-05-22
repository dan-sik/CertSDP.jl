using CertSDP
using Test

function gate_perfect_1a_native_rational_gram()
    artifacts = CertSDP.generate_native_hidden_artifacts(991001)
    gram = only(filter(a -> a.kind == :native_rational_gram,
                       artifacts.valid))
    CertSDP.artifact_generated_fresh(gram.path) || return false
    CertSDP.artifact_derived_from_existing_json(gram.path) && return false
    CertSDP.artifact_contains_exact_certificate(gram.path) && return false
    result = CertSDP.reconstruct_perfect_artifact(gram.path)
    result.status === :ok || return false
    cert = result.certificate
    return cert.field == CertSDP.QQ &&
           CertSDP.is_non_diagonal_gram(cert.blocks[1]) &&
           !CertSDP.is_all_ones_gram(cert.blocks[1]) &&
           CertSDP.no_identity_anchor_minor(cert.blocks[1]) &&
           CertSDP.exact_low_rank_factor_verified(cert) &&
           CertSDP.exact_polynomial_identity_verified(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

function gate_perfect_1b_native_algebraic_gram()
    artifacts = CertSDP.generate_native_hidden_artifacts(991002)
    alg = only(filter(a -> a.kind == :native_algebraic_gram,
                      artifacts.valid))
    CertSDP.artifact_derived_from_existing_json(alg.path) && return false
    CertSDP.artifact_contains_field_hints(alg.path) && return false
    result = CertSDP.reconstruct_perfect_artifact(alg.path)
    result.status === :ok || return false
    cert = result.certificate
    return cert.field isa CertSDP.MultiquadraticField &&
           CertSDP.field_is_minimal_computed(cert) &&
           CertSDP.contains_general_algebraic_entries(cert) &&
           CertSDP.full_algebraic_gram_psd_verified(cert) &&
           CertSDP.exact_polynomial_identity_verified(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

function gate_perfect_1c_native_sparse_putinar()
    artifacts = CertSDP.generate_native_hidden_artifacts(991003)
    sparse = only(filter(a -> a.kind == :native_sparse_putinar,
                         artifacts.valid))
    CertSDP.artifact_derived_from_existing_json(sparse.path) && return false
    result = CertSDP.reconstruct_perfect_artifact(sparse.path)
    result.status === :ok || return false
    cert = result.certificate
    report = CertSDP.stream_sparse_identity_residual(cert)
    return cert.type === :sparse_putinar &&
           CertSDP.full_sparse_polynomial_identity_verified(cert) &&
           CertSDP.all_localizing_multipliers_verified(cert) &&
           CertSDP.all_equality_multipliers_verified(cert) &&
           report.status === :valid &&
           report.terms_computed >= 20_000 &&
           !CertSDP.dense_global_gram_used(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

function gate_perfect_1d_native_nc_trace()
    artifacts = CertSDP.generate_native_hidden_artifacts(991004)
    nc = only(filter(a -> a.kind == :native_nc_trace, artifacts.valid))
    CertSDP.artifact_derived_from_existing_json(nc.path) && return false
    result = CertSDP.reconstruct_perfect_artifact(nc.path)
    result.status === :ok || return false
    cert = result.certificate
    report = CertSDP.confluence_report(cert)
    return cert.algebra === :noncommutative_trace &&
           CertSDP.nc_trace_identity_verified_by_normal_form(cert) &&
           CertSDP.nc_multiple_rewrite_paths_converge(cert) &&
           report.status === :valid &&
           report.num_critical_pairs_checked >= 10 &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

function gate_perfect_1e_native_farkas()
    artifacts = CertSDP.generate_native_hidden_artifacts(991005)
    farkas = only(filter(a -> a.kind == :native_farkas, artifacts.valid))
    CertSDP.artifact_derived_from_existing_json(farkas.path) && return false
    result = CertSDP.reconstruct_perfect_artifact(farkas.path)
    result.status === :ok || return false
    cert = result.certificate
    return cert.type === :infeasibility &&
           CertSDP.used_sdp_operator_path(cert) &&
           !CertSDP.used_preexpanded_affine_identities(cert) &&
           CertSDP.exact_sparse_affine_matrix_identity_verified(cert) &&
           CertSDP.exact_farkas_normalization(cert) == -1 // 1 &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

function gate_perfect_1f_native_invalid_reject()
    artifacts = CertSDP.generate_native_hidden_artifacts(991006)
    length(artifacts.invalid) >= 5 || return false
    for artifact in artifacts.invalid
        CertSDP.artifact_derived_from_existing_json(artifact.path) &&
            return false
        result = CertSDP.reconstruct_absolute_artifact(artifact.path)
        result.status in (:failed, :invalid) || return false
        isnothing(result.failure_stage) && return false
    end
    return true
end

function gate_perfect_2a_nonrational_psd_pivot()
    K = CertSDP.MultiquadraticField([2, 5])
    Q = CertSDP.make_test_psd_matrix_over_field(K; dim=24, rank=5,
        nonrational_pivots=true, no_rational_coordinate_skeleton=true,
        seed=7771)
    result = CertSDP.factor_psd_over_number_field(Q, K)
    return result.status === :ok &&
           result.field == K &&
           result.rank == 5 &&
           result.used_nonrational_pivots &&
           !result.used_rational_coordinate_skeleton &&
           result.residual_zero &&
           CertSDP.verify_field_factorization(Q, result.factor, K)
end

function gate_perfect_2b_psd_tamper_reject()
    K = CertSDP.MultiquadraticField([2, 5])
    Q = CertSDP.make_test_psd_matrix_over_field(K; dim=20, rank=4,
        nonrational_pivots=true, seed=7772)
    Q_bad = CertSDP.tamper_field_matrix_entry(Q, 7, 11, "1/1000000000")
    result = CertSDP.factor_psd_over_number_field(Q_bad, K)
    return result.status in (:failed, :invalid) &&
           result.failure_stage in (:psd_error, :algebraic_factorization_error)
end

function gate_perfect_2c_standalone_no_reconstructor()
    CertSDP.reset_absolute_gate_call_trace!()
    K = CertSDP.MultiquadraticField([2, 5])
    Q = CertSDP.make_test_psd_matrix_over_field(K; dim=18, rank=3, seed=7773)
    result = CertSDP.factor_psd_over_number_field(Q, K)
    return result.status === :ok &&
           get(CertSDP.ABSOLUTE_GATE_CALLS, :reconstruct_final_artifact, 0) == 0 &&
           get(CertSDP.ABSOLUTE_GATE_CALLS, :reconstruct_absolute_artifact, 0) == 0
end

function gate_perfect_3a_nc_confluence_report()
    result = CertSDP.reconstruct_absolute_artifact(joinpath(@__DIR__, "..",
        "benchmarks", "absolute_artifacts", "nctssos",
        "nc_confluence_adversarial.json"))
    result.status === :ok || return false
    report = CertSDP.confluence_report(result.certificate)
    report.status === :valid || return false
    report.num_words_checked >= 10 || return false
    report.num_critical_pairs_checked >= 10 || return false
    isempty(report.failures) || return false
    for path in report.paths
        haskey(path, :input_word) || return false
        haskey(path, :path_a_steps) || return false
        haskey(path, :path_b_steps) || return false
        haskey(path, :normal_form_a) || return false
        haskey(path, :normal_form_b) || return false
        path[:same_normal_form] == true || return false
        path[:normal_form_a] == path[:normal_form_b] || return false
    end
    return true
end

function gate_perfect_3b_nc_nonconfluence_reject()
    bad = CertSDP.make_nonconfluent_nc_certificate(seed=8801)
    report = CertSDP.confluence_report(bad)
    return report.status === :invalid &&
           report.num_critical_pairs_checked >= 1 &&
           !isempty(report.failures)
end

function gate_perfect_4_benchmark_integrity()
    report = CertSDP.run_perfect_gate_benchmark()
    return report.measured_with_elapsed &&
           report.measured_with_gc_live_bytes &&
           report.reconstructed_artifact_count >= 10 &&
           report.native_generated_artifact_count >= 5 &&
           report.standalone_psd_factorization_count >= 3 &&
           report.nc_confluence_reports_checked >= 2 &&
           report.total_runtime_seconds > 0 &&
           report.total_runtime_seconds <= 2400 &&
           report.max_memory_gb > 0 &&
           report.max_memory_gb <= 12 &&
           !report.used_dense_global_gram &&
           !report.used_dense_original_sdp_matrix
end

function gate_perfect_5_json_independence()
    artifacts = CertSDP.generate_native_hidden_artifacts(991007)
    certs = CertSDP.ExactCertificateArtifact[]
    for artifact in artifacts.valid
        result = CertSDP.reconstruct_perfect_artifact(artifact.path)
        result.status === :ok || return false
        push!(certs, result.certificate)
    end
    length(certs) >= 5 || return false
    for cert in certs
        path = tempname() * ".json"
        CertSDP.write_certificate(path, cert)
        fresh = CertSDP.replay_in_fresh_julia_process(path; mode=:strict)
        fresh.status === :valid || return false
        fresh.did_not_call_reconstruct || return false
        fresh.did_not_call_import_artifact || return false
        fresh.did_not_load_original_artifact || return false
        fresh.did_not_call_solver || return false
        fresh.did_not_use_network || return false
    end
    return true
end

@testset "CertSDP 2.1-PERFECT Gate" begin
    CertSDP.CERTSDP_ABSOLUTE_GATE_MODE[] = true
    try
        @testset "Gate 1 native hidden artifacts" begin
            @test gate_perfect_1a_native_rational_gram()
            @test gate_perfect_1b_native_algebraic_gram()
            @test gate_perfect_1c_native_sparse_putinar()
            @test gate_perfect_1d_native_nc_trace()
            @test gate_perfect_1e_native_farkas()
            @test gate_perfect_1f_native_invalid_reject()
        end
        @testset "Gate 2 standalone number-field PSD factorization" begin
            @test gate_perfect_2a_nonrational_psd_pivot()
            @test gate_perfect_2b_psd_tamper_reject()
            @test gate_perfect_2c_standalone_no_reconstructor()
        end
        @testset "Gate 3 NC confluence report" begin
            @test gate_perfect_3a_nc_confluence_report()
            @test gate_perfect_3b_nc_nonconfluence_reject()
        end
        @testset "Gate 4 benchmark integrity" begin
            @test gate_perfect_4_benchmark_integrity()
        end
        @testset "Gate 5 JSON independence" begin
            @test gate_perfect_5_json_independence()
        end
    finally
        CertSDP.CERTSDP_ABSOLUTE_GATE_MODE[] = false
    end
end

println("CertSDP.jl 2.1-PERFECT Hard Gate: PASS")
