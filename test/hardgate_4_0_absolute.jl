using CertSDP
using Test

const ABS_ROOT = joinpath(@__DIR__, "..", "benchmarks", "absolute_artifacts")

_abs_path(parts...) = joinpath(ABS_ROOT, parts...)

function gate_abs_0_anti_cheat()
    CertSDP.reset_absolute_gate_call_trace!()
    result = CertSDP.reconstruct_absolute_artifact(_abs_path("sos",
        "algebraic_psd_nonrational_pivot.json"))
    result.status === :ok || return false
    result.audit.used_expected_certificate && return false
    result.audit.used_metadata_truth_claims && return false
    result.audit.called_synthetic_compiler && return false
    for name in (:compile_fixture, :_make_factor_block,
                 :_saved_noisy_artifact, :_external_fixture_instance,
                 :_external_fixture_from_object, :_bind_field_evidence!,
                 :_recover_anchor_low_rank_factor, :_final_anchor_rank)
        get(CertSDP.ABSOLUTE_GATE_CALLS, name, 0) == 0 || return false
    end
    return true
end

function gate_abs_1_algebraic_psd_nonrational_pivot()
    result = CertSDP.reconstruct_absolute_artifact(_abs_path("sos",
        "algebraic_psd_nonrational_pivot.json"))
    result.status === :ok || return false
    cert = result.certificate
    return cert.field == CertSDP.MultiquadraticField([2, 5]) &&
           cert.blocks[1].dimension == 64 &&
           cert.blocks[1].rank == 6 &&
           CertSDP.exact_low_rank_factor_verified(cert) &&
           CertSDP.exact_polynomial_identity_verified(cert) &&
           CertSDP.contains_general_algebraic_entries(cert) &&
           CertSDP.has_nonrational_algebraic_psd_pivots(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid &&
           CertSDP.reconstruction_method(cert) in
               (:algebraic_pivoted_ldlt,
                :algebraic_low_rank_factor_recovery,
                :number_field_psd_factorization)
end

function gate_abs_1_reject_bad_pivot()
    result = CertSDP.reject_algebraic_psd_pivot_tamper(_abs_path("sos",
        "algebraic_psd_nonrational_pivot.json"); pivot=3, delta="1e-25")
    return result.status in (:failed, :invalid) &&
           result.failure_stage in (:psd_error, :field_embedding_error,
                                    :algebraic_factorization_error)
end

function gate_abs_2_high_denominator_multiquadratic()
    result = CertSDP.reconstruct_absolute_artifact(_abs_path("fields",
        "high_denominator_multiquadratic.json"); max_denominator=100_000,
        max_field_degree=4)
    result.status === :ok || return false
    cert = result.certificate
    return cert.field == CertSDP.MultiquadraticField([2, 5]) &&
           CertSDP.field_is_minimal_computed(cert) &&
           CertSDP.max_denominator(cert) >= 50_000 &&
           CertSDP.algebraic_coefficients_are_general_linear_combinations(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

function gate_abs_2_reject_height_budget()
    result = CertSDP.reconstruct_absolute_artifact(_abs_path("fields",
        "high_denominator_multiquadratic.json"); max_denominator=10_000)
    return result.status === :failed &&
           result.failure_stage === :coefficient_height_budget_exceeded
end

function gate_abs_2_reject_insufficient_field()
    result = CertSDP.reconstruct_absolute_artifact(_abs_path("fields",
        "high_denominator_multiquadratic.json");
        allowed_fields=[CertSDP.QQ, CertSDP.QuadraticField(2)])
    return result.status === :failed &&
           result.failure_stage === :field_insufficient_error
end

function gate_abs_3_cubic_embedding_selection()
    result = CertSDP.reconstruct_absolute_artifact(_abs_path("fields",
        "cubic_embedding_selection.json"))
    result.status === :ok || return false
    cert = result.certificate
    return CertSDP.minimal_polynomial(cert.field) ==
           CertSDP.parse_polynomial("t^3 - t - 1") &&
           CertSDP.field_embedding_verified(cert) &&
           CertSDP.has_coefficients_in_power_basis(cert; max_power=2) &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

function gate_abs_3_reject_wrong_embedding()
    result = CertSDP.reject_wrong_cubic_embedding(_abs_path("fields",
        "cubic_embedding_selection.json"))
    return result.status in (:failed, :invalid) &&
           result.failure_stage === :field_embedding_error
end

function gate_abs_4_algebraic_gram_no_rational_skeleton()
    result = CertSDP.reconstruct_absolute_artifact(_abs_path("sos",
        "algebraic_low_rank_no_rational_skeleton.json"))
    result.status === :ok || return false
    cert = result.certificate
    return cert.field == CertSDP.MultiquadraticField([2, 5]) &&
           cert.blocks[1].rank == 5 &&
           CertSDP.full_algebraic_gram_psd_verified(cert) &&
           CertSDP.did_not_use_rational_coordinate_skeleton(cert) &&
           CertSDP.exact_polynomial_identity_verified(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

function gate_abs_5_sparse_semantic_permutation()
    for seed in (1001, 1002, 1003)
        artifact = CertSDP.generate_absolute_sparse_permutation_artifact(seed)
        result = CertSDP.reconstruct_absolute_artifact(artifact.valid_path)
        result.status === :ok || return false
        cert = result.certificate
        CertSDP.full_sparse_polynomial_identity_verified(cert) || return false
        report = CertSDP.stream_sparse_identity_residual(cert)
        report.status === :valid || return false
        report.terms_computed >= 150_000 || return false
        CertSDP.dense_global_gram_used(cert) && return false
        CertSDP.verify(cert; mode=:strict).status === :valid || return false
        bad = CertSDP.reconstruct_absolute_artifact(artifact.invalid_path)
        bad.status in (:failed, :invalid) || return false
        bad.failure_stage in (:sparse_identity_error,
                              :localizing_identity_error,
                              :equality_multiplier_error) || return false
    end
    return true
end

function gate_abs_6_nc_confluence()
    result = CertSDP.reconstruct_absolute_artifact(_abs_path("nctssos",
        "nc_confluence_adversarial.json"))
    result.status === :ok || return false
    cert = result.certificate
    return CertSDP.nc_trace_identity_verified_by_normal_form(cert) &&
           CertSDP.quotient_confluence_checked_on_support(cert) &&
           CertSDP.nc_multiple_rewrite_paths_converge(cert) &&
           CertSDP.trace_cyclic_reduction_computed(cert) &&
           CertSDP.star_involution_verified(cert) &&
           !CertSDP.commutative_shortcut_used(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

function gate_abs_6_reject_nc_adversarial()
    path = _abs_path("nctssos", "nc_confluence_adversarial.json")
    return CertSDP.reject_nc_nonconfluent_rule(path).failure_stage ===
               :quotient_confluence_error &&
           CertSDP.reject_nc_illegal_same_party_commutation(path).failure_stage ===
               :nc_identity_error &&
           CertSDP.reject_nc_trace_rotation_direction_error(path).failure_stage ===
               :trace_quotient_error
end

function gate_abs_7_operator_primal_dual()
    result = CertSDP.reconstruct_absolute_artifact(_abs_path("sdp",
        "operator_primal_dual_gap.json"))
    result.status === :ok || return false
    cert = result.certificate
    return cert.type === :primal_dual_optimality &&
           CertSDP.used_sdp_operator_path(cert) &&
           !CertSDP.used_preexpanded_affine_identities(cert) &&
           CertSDP.exact_primal_feasibility_verified(cert) &&
           CertSDP.exact_dual_feasibility_verified(cert) &&
           CertSDP.exact_objective_gap(cert) == 0 &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

function gate_abs_8_operator_farkas()
    result = CertSDP.reconstruct_absolute_artifact(_abs_path("sdp",
        "operator_farkas_infeasibility.json"))
    result.status === :ok || return false
    cert = result.certificate
    return cert.type === :infeasibility &&
           CertSDP.used_sdp_operator_path(cert) &&
           !CertSDP.used_preexpanded_affine_identities(cert) &&
           CertSDP.exact_sparse_affine_matrix_identity_verified(cert) &&
           CertSDP.exact_farkas_normalization(cert) == -1 // 1 &&
           CertSDP.all_psd_slack_blocks_verified(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

function gate_abs_9_manual_upstream_rebuild(args)
    "--rebuild-from-upstream" in args || return true
    for session in ("sumofsquares_clarabel_general_gram",
                    "tssos_clarabel_sparse_putinar",
                    "nctssos_cosmo_trace",
                    "jump_moi_sdp_farkas")
        result = CertSDP.rebuild_upstream_session(session;
                                                  mode=:rebuild_from_upstream)
        result.did_run_export_script || return false
        result.raw_output_sha256_verified || return false
        result.certsdp_input_sha256_verified || return false
        result.reconstructed_certificate_sha256_verified || return false
        CertSDP.verify(result.certificate; mode=:strict).status === :valid ||
            return false
        CertSDP.replay_in_fresh_julia_process(result.certificate_json).status ===
            :valid || return false
    end
    return true
end

function gate_abs_10_real_benchmark()
    report = CertSDP.run_absolute_gate_benchmark()
    return report.total_runtime_seconds > 0 &&
           report.total_runtime_seconds <= 1800 &&
           report.max_memory_gb > 0 &&
           report.max_memory_gb <= 12 &&
           report.reconstructed_artifact_count >= 6 &&
           report.measured_with_elapsed &&
           report.measured_with_gc_live_bytes &&
           report.sparse_terms_computed >= 150_000 &&
           report.nc_terms_computed >= 80_000 &&
           report.affine_entries_streamed >= 200_000 &&
           !report.used_dense_global_gram &&
           !report.used_dense_original_sdp_matrix
end

function gate_abs_11_hidden_generator()
    for seed in (20260521, 20260522, 20260523)
        artifacts = CertSDP.generate_absolute_hidden_artifacts(seed)
        length(artifacts.valid) >= 5 || return false
        length(artifacts.invalid) >= 5 || return false
        for artifact in artifacts.valid
            CertSDP.artifact_contains_exact_certificate(artifact.path) &&
                return false
            CertSDP.artifact_generated_fresh(artifact.path) || return false
            result = CertSDP.reconstruct_absolute_artifact(artifact.path)
            result.status === :ok || return false
            CertSDP.verify(result.certificate; mode=:strict).status ===
                :valid || return false
        end
        for artifact in artifacts.invalid
            result = CertSDP.reconstruct_absolute_artifact(artifact.path)
            result.status in (:failed, :invalid) || return false
            isnothing(result.failure_stage) && return false
        end
    end
    return true
end

function gate_abs_12_json_independence()
    certs = CertSDP.absolute_gate_certificates()
    if length(certs) < 8
        for path in (_abs_path("sos", "algebraic_psd_nonrational_pivot.json"),
                     _abs_path("fields", "high_denominator_multiquadratic.json"),
                     _abs_path("fields", "cubic_embedding_selection.json"),
                     _abs_path("sos", "algebraic_low_rank_no_rational_skeleton.json"),
                     _abs_path("tssos", "general_sparse_permutation_base.json"),
                     _abs_path("nctssos", "nc_confluence_adversarial.json"),
                     _abs_path("sdp", "operator_primal_dual_gap.json"),
                     _abs_path("sdp", "operator_farkas_infeasibility.json"))
            CertSDP.reconstruct_absolute_artifact(path)
        end
        certs = CertSDP.absolute_gate_certificates()
    end
    length(certs) >= 8 || return false
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

@testset "CertSDP 2.1-ABSOLUTE Universal Reconstruction Gate" begin
    CertSDP.CERTSDP_ABSOLUTE_GATE_MODE[] = true
    try
        @testset "Gate 0 anti-cheat" begin
            @test gate_abs_0_anti_cheat()
        end
        @testset "Gate 1 algebraic PSD non-rational pivot" begin
            @test gate_abs_1_algebraic_psd_nonrational_pivot()
            @test gate_abs_1_reject_bad_pivot()
        end
        @testset "Gate 2 high-denominator algebraic coefficients" begin
            @test gate_abs_2_high_denominator_multiquadratic()
            @test gate_abs_2_reject_height_budget()
            @test gate_abs_2_reject_insufficient_field()
        end
        @testset "Gate 3 cubic embedding selection" begin
            @test gate_abs_3_cubic_embedding_selection()
            @test gate_abs_3_reject_wrong_embedding()
        end
        @testset "Gate 4 algebraic Gram without rational skeleton" begin
            @test gate_abs_4_algebraic_gram_no_rational_skeleton()
        end
        @testset "Gate 5 sparse semantic permutation" begin
            @test gate_abs_5_sparse_semantic_permutation()
        end
        @testset "Gate 6 NC quotient confluence adversarial" begin
            @test gate_abs_6_nc_confluence()
            @test gate_abs_6_reject_nc_adversarial()
        end
        @testset "Gate 7 operator primal-dual" begin
            @test gate_abs_7_operator_primal_dual()
        end
        @testset "Gate 8 operator Farkas" begin
            @test gate_abs_8_operator_farkas()
        end
        @testset "Gate 9 manual upstream rebuild mode" begin
            @test gate_abs_9_manual_upstream_rebuild(ARGS)
        end
        @testset "Gate 10 real benchmark measurement" begin
            @test gate_abs_10_real_benchmark()
        end
        @testset "Gate 11 absolute hidden generator" begin
            @test gate_abs_11_hidden_generator()
        end
        @testset "Gate 12 proof-carrying JSON independence" begin
            @test gate_abs_12_json_independence()
        end
    finally
        CertSDP.CERTSDP_ABSOLUTE_GATE_MODE[] = false
    end
end

println("CertSDP.jl 2.1-ABSOLUTE Hard Gate: PASS")
