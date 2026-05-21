using CertSDP
using Test

const FINAL_GATE_ROOT = joinpath(@__DIR__, "..", "benchmarks", "final_artifacts")

function _final_path(parts...)
    return joinpath(FINAL_GATE_ROOT, parts...)
end

function gate_final_0_anti_cheat()
    CertSDP.reset_final_gate_call_trace!()
    result = CertSDP.reconstruct_final_artifact(_final_path("sos",
                                                            "general_low_rank_gram_01.json"))
    result.status === :ok || return false
    result.audit.used_expected_certificate && return false
    result.audit.used_metadata_truth_claims && return false
    result.audit.called_synthetic_compiler && return false
    for name in (:compile_fixture, :_make_factor_block,
                 :_compile_sparse_opf_like,
                 :_compile_symmetry_clustered_low_rank,
                 :_compile_nc_trace_npa,
                 :_compile_quantum_code_infeasibility,
                 :_saved_noisy_artifact,
                 :_external_fixture_instance,
                 :_external_fixture_from_object,
                 :_bind_field_evidence!)
        get(CertSDP.FINAL_GATE_CALLS, name, 0) == 0 || return false
    end
    return true
end

function gate_final_1_general_rational_low_rank_gram()
    result = CertSDP.reconstruct_final_artifact(_final_path("sos",
                                                            "general_low_rank_gram_01.json"))
    cert = result.certificate
    return result.status === :ok &&
           cert.field == CertSDP.QQ &&
           cert.type === :sos_gram_reconstruction &&
           cert.blocks[1].dimension == 120 &&
           cert.blocks[1].rank == 9 &&
           CertSDP.is_non_diagonal_gram(cert.blocks[1]) &&
           !CertSDP.is_all_ones_gram(cert.blocks[1]) &&
           CertSDP.exact_low_rank_factor_verified(cert) &&
           CertSDP.exact_polynomial_identity_verified(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid &&
           CertSDP.max_denominator(cert) <= 100_000 &&
           CertSDP.reconstruction_method(cert) in
           (:rational_low_rank_recovery, :exact_ldlt_with_kernel_recovery,
            :integer_lattice_low_rank_reconstruction)
end

function gate_final_1_reject_tampered_gram()
    result = CertSDP.reject_tampered_gram_entry(_final_path("sos",
                                                            "general_low_rank_gram_01.json");
                                                index=307, delta="1e-4")
    return result.status in (:failed, :invalid) &&
           result.failure_stage in (:sos_identity_error, :psd_error,
                                    :rational_reconstruction_error)
end

function gate_final_1_reject_rank_overfit()
    result = CertSDP.reject_rank_overfit(_final_path("sos",
                                                     "general_low_rank_gram_01.json");
                                         forced_rank=120)
    return result.status in (:failed, :invalid) &&
           result.failure_stage === :rank_minimality_error
end

function gate_final_2_multiquadratic_general_coeffs()
    result = CertSDP.reconstruct_final_artifact(_final_path("fields",
                                                            "general_multiquadratic_coeffs_01.json"))
    cert = result.certificate
    return result.status === :ok &&
           cert.field == CertSDP.MultiquadraticField([2, 5]) &&
           CertSDP.field_is_minimal_computed(cert) &&
           CertSDP.algebraic_coefficients_are_general_linear_combinations(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

function gate_final_2_cubic_general_coeffs()
    result = CertSDP.reconstruct_final_artifact(_final_path("fields",
                                                            "general_cubic_coeffs_01.json"))
    cert = result.certificate
    return result.status === :ok &&
           CertSDP.minimal_polynomial(cert.field) ==
           CertSDP.parse_polynomial("t^3 - t - 1") &&
           CertSDP.has_coefficients_in_power_basis(cert; max_power=2) &&
           CertSDP.field_is_minimal_computed(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

function gate_final_2_reject_degree_budget()
    result = CertSDP.reconstruct_final_artifact(_final_path("fields",
                                                            "general_cubic_coeffs_01.json");
                                                max_field_degree=2)
    return result.status === :failed &&
           result.failure_stage === :field_degree_budget_exceeded
end

function gate_final_2_reject_insufficient_field()
    result = CertSDP.reconstruct_final_artifact(_final_path("fields",
                                                            "general_multiquadratic_coeffs_01.json");
                                                allowed_fields=[CertSDP.QQ,
                                                                CertSDP.QuadraticField(2)])
    return result.status === :failed &&
           result.failure_stage === :field_insufficient_error
end

function gate_final_3_algebraic_low_rank_gram()
    result = CertSDP.reconstruct_final_artifact(_final_path("sos",
                                                            "algebraic_low_rank_gram_01.json"))
    cert = result.certificate
    return result.status === :ok &&
           cert.field == CertSDP.MultiquadraticField([2, 5]) &&
           cert.blocks[1].dimension == 80 &&
           cert.blocks[1].rank == 7 &&
           CertSDP.exact_low_rank_factor_verified(cert) &&
           CertSDP.exact_polynomial_identity_verified(cert) &&
           CertSDP.field_is_minimal_computed(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid &&
           CertSDP.is_non_diagonal_gram(cert.blocks[1]) &&
           CertSDP.contains_general_algebraic_entries(cert)
end

function gate_final_3_reject_wrong_embedding()
    result = CertSDP.reject_conjugate_wrong_embedding(_final_path("sos",
                                                                  "algebraic_low_rank_gram_01.json"))
    return result.status in (:failed, :invalid) &&
           result.failure_stage === :field_embedding_error
end

function gate_final_3_reject_identity_tamper()
    result = CertSDP.reject_algebraic_identity_tamper(_final_path("sos",
                                                                  "algebraic_low_rank_gram_01.json");
                                                      term=10, delta="1e-2")
    return result.status in (:failed, :invalid) &&
           result.failure_stage === :sos_identity_error
end

function gate_final_4_general_sparse_putinar()
    result = CertSDP.reconstruct_final_artifact(_final_path("tssos",
                                                            "general_sparse_putinar_01.json"))
    cert = result.certificate
    return result.status === :ok &&
           cert.type === :sparse_putinar &&
           cert.num_variables >= 180 &&
           cert.num_blocks >= 96 &&
           CertSDP.total_block_dim(cert) >= 1800 &&
           CertSDP.full_sparse_polynomial_identity_verified(cert) &&
           CertSDP.all_localizing_multipliers_verified(cert) &&
           CertSDP.all_equality_multipliers_verified(cert) &&
           CertSDP.exact_low_rank_factor_verified(cert) &&
           !CertSDP.dense_global_gram_used(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid &&
           CertSDP.no_compact_identity_shortcut_used(cert) &&
           CertSDP.streamed_sparse_residual_terms_computed(cert) >= 150_000
end

function gate_final_4_reject_wrong_localizing_constraint()
    result = CertSDP.reject_wrong_localizing_constraint(_final_path("tssos",
                                                                    "general_sparse_putinar_01.json");
                                                        multiplier=17)
    return result.status in (:failed, :invalid) &&
           result.failure_stage === :localizing_identity_error
end

function gate_final_4_reject_missing_sparse_block()
    result = CertSDP.reject_missing_sparse_block(_final_path("tssos",
                                                             "general_sparse_putinar_01.json");
                                                 block=33)
    return result.status in (:failed, :invalid) &&
           result.failure_stage in (:sparse_identity_error, :psd_error,
                                    :reconstruction_error)
end

function gate_final_5_general_nc_trace()
    result = CertSDP.reconstruct_final_artifact(_final_path("nctssos",
                                                            "general_nc_trace_01.json"))
    cert = result.certificate
    return result.status === :ok &&
           cert.algebra === :noncommutative_trace &&
           cert.num_canonical_words >= 2500 &&
           cert.max_word_length >= 6 &&
           cert.num_blocks >= 48 &&
           CertSDP.nc_trace_identity_verified_by_normal_form(cert) &&
           CertSDP.nc_trace_residual_terms_computed(cert) >= 80_000 &&
           CertSDP.quotient_confluence_checked_on_support(cert) &&
           CertSDP.projector_relations_computed(cert) &&
           CertSDP.completeness_relations_computed(cert) &&
           CertSDP.cross_party_commutation_computed(cert) &&
           CertSDP.trace_cyclic_reduction_computed(cert) &&
           CertSDP.star_involution_verified(cert) &&
           !CertSDP.commutative_shortcut_used(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

function gate_final_5_reject_bad_nc_variants()
    path = _final_path("nctssos", "general_nc_trace_01.json")
    return CertSDP.reject_nc_all_commute(path).failure_stage === :nc_identity_error &&
           CertSDP.reject_nc_wrong_trace_rotation(path).failure_stage ===
           :trace_quotient_error &&
           CertSDP.reject_nc_missing_completeness(path).failure_stage ===
           :quotient_relation_error &&
           CertSDP.reject_nc_star_sign_error(path).failure_stage ===
           :star_involution_error &&
           CertSDP.reject_nc_cross_party_overcommutation(path).failure_stage ===
           :nc_identity_error
end

function gate_final_6_primal_dual_gap()
    result = CertSDP.reconstruct_final_artifact(_final_path("sdp",
                                                            "primal_dual_gap_01.json"))
    cert = result.certificate
    return result.status === :ok &&
           cert.type === :primal_dual_optimality &&
           CertSDP.exact_primal_feasibility_verified(cert) &&
           CertSDP.exact_dual_feasibility_verified(cert) &&
           CertSDP.exact_objective_gap(cert) == 0 &&
           CertSDP.all_primal_psd_blocks_verified(cert) &&
           CertSDP.all_dual_slack_blocks_verified(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid
end

gate_final_6_reject_primal_tamper() =
    CertSDP.reject_primal_affine_tamper(_final_path("sdp",
                                                    "primal_dual_gap_01.json")).failure_stage ===
    :primal_affine_identity_error

gate_final_6_reject_dual_tamper() =
    CertSDP.reject_dual_slack_tamper(_final_path("sdp",
                                                 "primal_dual_gap_01.json")).failure_stage ===
    :dual_psd_error

gate_final_6_reject_objective_tamper() =
    CertSDP.reject_objective_gap_tamper(_final_path("sdp",
                                                    "primal_dual_gap_01.json")).failure_stage ===
    :objective_gap_error

function gate_final_7_general_farkas()
    result = CertSDP.reconstruct_final_artifact(_final_path("sdp",
                                                            "general_farkas_infeasibility_01.json"))
    cert = result.certificate
    return result.status === :ok &&
           cert.type === :infeasibility &&
           cert.num_linear_constraints >= 10_000 &&
           CertSDP.total_block_dim(cert) >= 1500 &&
           CertSDP.exact_sparse_affine_matrix_identity_verified(cert) &&
           CertSDP.exact_farkas_normalization(cert) == -1 // 1 &&
           CertSDP.all_psd_slack_blocks_verified(cert) &&
           CertSDP.verify(cert; mode=:strict).status === :valid &&
           CertSDP.affine_entries_streamed(cert) >= 200_000
end

gate_final_7_reject_affine_tamper() =
    CertSDP.reject_sparse_affine_entry_tamper(_final_path("sdp",
                                                          "general_farkas_infeasibility_01.json");
                                             entry=17777).failure_stage ===
    :affine_dual_identity_error

gate_final_7_reject_normalization_tamper() =
    CertSDP.reject_farkas_normalization_tamper(_final_path("sdp",
                                                           "general_farkas_infeasibility_01.json")).failure_stage ===
    :farkas_normalization_error

function gate_final_8_upstream_end_to_end()
    sessions = ["sumofsquares_clarabel_general_gram",
                "tssos_clarabel_sparse_putinar",
                "nctssos_cosmo_trace",
                "jump_moi_sdp_farkas"]
    for session in sessions
        result = CertSDP.rebuild_upstream_session(session)
        result.raw_output_sha256_verified || return false
        result.certsdp_input_sha256_verified || return false
        result.reconstructed_certificate_sha256_verified || return false
        result.did_run_export_script || return false
        result.did_not_use_expected_certificate || return false
        result.did_not_call_solver_during_replay || return false
        CertSDP.verify(result.certificate; mode=:strict).status === :valid ||
            return false
        CertSDP.replay_in_fresh_julia_process(result.certificate_json).status ===
            :valid || return false
    end
    return true
end

function gate_final_9_hidden_adversarial()
    for seed in (20260520, 20260521, 20260522)
        artifacts = CertSDP.generate_hidden_final_artifacts(seed)
        for artifact in artifacts.valid
            result = CertSDP.reconstruct_final_artifact(artifact.path)
            result.status === :ok || return false
            CertSDP.verify(result.certificate; mode=:strict).status === :valid ||
                return false
        end
        for artifact in artifacts.invalid
            result = CertSDP.reconstruct_final_artifact(artifact.path)
            result.status in (:failed, :invalid) || return false
            isnothing(result.failure_stage) && return false
        end
    end
    return true
end

function gate_final_10_performance_memory()
    report = CertSDP.run_final_gate_benchmark()
    return report.total_runtime_seconds <= 1800 &&
           report.max_memory_gb <= 12 &&
           report.sparse_putinar_runtime_seconds <= 300 &&
           report.nc_trace_runtime_seconds <= 300 &&
           report.farkas_runtime_seconds <= 300 &&
           !report.used_dense_global_gram &&
           !report.used_dense_original_sdp_matrix
end

function gate_final_11_json_replay()
    isempty(CertSDP.final_gate_certificates()) &&
        CertSDP.reconstruct_final_artifact(_final_path("sos",
                                                       "general_low_rank_gram_01.json"))
    for cert in CertSDP.final_gate_certificates()
        path = tempname() * ".json"
        CertSDP.write_certificate(path, cert)
        fresh = CertSDP.replay_in_fresh_julia_process(path; mode=:strict)
        fresh.status === :valid || return false
        fresh.did_not_call_reconstruct || return false
        fresh.did_not_call_import_artifact || return false
        fresh.did_not_load_original_artifact || return false
        get(fresh, :did_not_call_solver, true) || return false
        get(fresh, :did_not_use_network, true) || return false
    end
    return true
end

@testset "CertSDP 2.1-FINAL Universal Exact Certificate Compiler Gate" begin
    CertSDP.CERTSDP_FINAL_GATE_MODE[] = true
    try
        @testset "Gate 0 absolute anti-cheat" begin
            @test gate_final_0_anti_cheat()
        end

        @testset "Gate 1 general rational low-rank Gram" begin
            @test gate_final_1_general_rational_low_rank_gram()
            @test gate_final_1_reject_tampered_gram()
            @test gate_final_1_reject_rank_overfit()
        end

        @testset "Gate 2 general algebraic coefficient reconstruction" begin
            @test gate_final_2_multiquadratic_general_coeffs()
            @test gate_final_2_cubic_general_coeffs()
            @test gate_final_2_reject_degree_budget()
            @test gate_final_2_reject_insufficient_field()
        end

        @testset "Gate 3 algebraic low-rank Gram" begin
            @test gate_final_3_algebraic_low_rank_gram()
            @test gate_final_3_reject_wrong_embedding()
            @test gate_final_3_reject_identity_tamper()
        end

        @testset "Gate 4 general sparse Putinar" begin
            @test gate_final_4_general_sparse_putinar()
            @test gate_final_4_reject_wrong_localizing_constraint()
            @test gate_final_4_reject_missing_sparse_block()
        end

        @testset "Gate 5 general NC trace quotient" begin
            @test gate_final_5_general_nc_trace()
            @test gate_final_5_reject_bad_nc_variants()
        end

        @testset "Gate 6 primal-dual exact objective gap" begin
            @test gate_final_6_primal_dual_gap()
            @test gate_final_6_reject_primal_tamper()
            @test gate_final_6_reject_dual_tamper()
            @test gate_final_6_reject_objective_tamper()
        end

        @testset "Gate 7 general Farkas infeasibility" begin
            @test gate_final_7_general_farkas()
            @test gate_final_7_reject_affine_tamper()
            @test gate_final_7_reject_normalization_tamper()
        end

        @testset "Gate 8 upstream end-to-end rebuild" begin
            @test gate_final_8_upstream_end_to_end()
        end

        @testset "Gate 9 hidden adversarial artifacts" begin
            @test gate_final_9_hidden_adversarial()
        end

        @testset "Gate 10 performance and memory" begin
            @test gate_final_10_performance_memory()
        end

        @testset "Gate 11 proof-carrying JSON replay" begin
            @test gate_final_11_json_replay()
        end
    finally
        CertSDP.CERTSDP_FINAL_GATE_MODE[] = false
    end
end

println("CertSDP.jl 2.1-FINAL Hard Gate: PASS")
