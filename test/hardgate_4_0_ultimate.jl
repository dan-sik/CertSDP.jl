using CertSDP
using Test

function gate_ultimate_1a_sparse_density()
    artifacts = CertSDP.generate_native_hidden_artifacts(1_000_001)
    sparse = only(filter(a -> a.kind == :native_sparse_putinar,
                         artifacts.valid))

    @test !CertSDP.artifact_derived_from_existing_json(sparse.path)
    @test !CertSDP.artifact_contains_exact_certificate(sparse.path)

    result = CertSDP.reconstruct_perfect_artifact(sparse.path)
    @test result.status == :ok
    cert = result.certificate

    @test cert.type == :sparse_putinar
    @test CertSDP.verify(cert; mode=:strict).status == :valid

    report = CertSDP.sparse_semantic_density_report(cert)
    @test report.status == :valid
    @test report.total_entries >= 20_000
    @test report.semantic_density >= 0.90
    @test report.duplicate_zero_entries <= floor(Int, 0.02 * report.total_entries)
    @test report.exact_residual_status == :valid

    stream = CertSDP.stream_sparse_identity_residual(cert)
    @test stream.status == :valid
    @test stream.terms_computed >= 20_000
    return true
end

function gate_ultimate_1b_zero_filler_trap()
    trap = CertSDP.generate_sparse_zero_filler_trap(seed=1_000_002)
    result = CertSDP.reconstruct_perfect_artifact(trap.path)
    @test result.status in (:failed, :invalid)
    @test result.failure_stage in
          [:sparse_semantic_density_error, :sparse_identity_error]
    return true
end

function gate_ultimate_2a_nonzero_multipliers()
    artifacts = CertSDP.generate_native_hidden_artifacts(1_000_003)
    sparse = only(filter(a -> a.kind == :native_sparse_putinar,
                         artifacts.valid))
    result = CertSDP.reconstruct_perfect_artifact(sparse.path)
    @test result.status == :ok
    cert = result.certificate

    report = CertSDP.multiplier_semantic_report(cert)
    @test report.status == :valid
    @test report.localizing_count >= 20
    @test report.equality_count >= 5
    @test report.nonzero_localizing_count >= 5
    @test report.nonzero_equality_count >= 2
    @test report.nonzero_localizing_terms >= 50
    @test report.nonzero_equality_terms >= 10

    @test CertSDP.full_sparse_polynomial_identity_verified(cert)
    @test CertSDP.verify(cert; mode=:strict).status == :valid
    return true
end

function gate_ultimate_2b_all_zero_multiplier_trap()
    trap = CertSDP.generate_all_zero_multiplier_trap(seed=1_000_004)
    result = CertSDP.reconstruct_perfect_artifact(trap.path)
    @test result.status in (:failed, :invalid)
    @test result.failure_stage in
          [:multiplier_semantic_error, :sparse_identity_error,
           :localizing_identity_error,
           :equality_multiplier_error]
    return true
end

function gate_ultimate_3a_critical_pair_valid()
    result = CertSDP.reconstruct_absolute_artifact(
        joinpath(@__DIR__, "..", "benchmarks", "absolute_artifacts",
                 "nctssos", "nc_confluence_adversarial.json"))
    @test result.status == :ok
    report = CertSDP.critical_pair_report(result.certificate)

    @test report.status == :valid
    @test report.num_rules >= 6
    @test report.num_pairs_generated >= 20
    @test report.num_pairs_checked >= 20
    @test report.num_joinable == report.num_pairs_checked
    @test report.num_nonjoinable == 0

    for pair in report.pairs
        @test pair.joinable
        @test pair.normal_form_a == pair.normal_form_b
        @test !isempty(pair.path_a_steps)
        @test !isempty(pair.path_b_steps)
    end
    return true
end

function gate_ultimate_3b_nonjoinable_pair_reject()
    bad = CertSDP.make_nonjoinable_critical_pair_certificate(seed=1_000_005)
    report = CertSDP.critical_pair_report(bad)
    @test report.status == :invalid
    @test report.num_nonjoinable >= 1
    @test any(pair -> !pair.joinable, report.pairs)
    return true
end

function gate_ultimate_4_critical_pair_not_metadata()
    result = CertSDP.reconstruct_absolute_artifact(
        joinpath(@__DIR__, "..", "benchmarks", "absolute_artifacts",
                 "nctssos", "nc_confluence_adversarial.json"))
    @test result.status == :ok
    report1 = CertSDP.critical_pair_report(result.certificate)
    tampered = CertSDP.tamper_nc_critical_pair_metadata(result.certificate;
                                                        num_pairs_checked=999,
                                                        status=:valid)
    report2 = CertSDP.critical_pair_report(tampered)

    @test report1.num_pairs_checked == report2.num_pairs_checked
    @test report2.num_pairs_checked != 999
    @test report2.status == report1.status
    return true
end

function gate_ultimate_5_benchmark()
    report = CertSDP.run_ultimate_gate_benchmark()

    @test report.measured_with_elapsed
    @test report.measured_with_gc_live_bytes
    @test report.native_generated_artifact_count >= 5
    @test report.sparse_semantic_density_checked >= 1
    @test report.multiplier_semantics_checked >= 1
    @test report.nc_critical_pair_reports_checked >= 1
    @test report.zero_filler_traps_rejected >= 1
    @test report.nonjoinable_nc_traps_rejected >= 1

    @test report.total_runtime_seconds > 0
    @test report.total_runtime_seconds <= 2400
    @test report.max_memory_gb > 0
    @test report.max_memory_gb <= 12
    return true
end

@testset "CertSDP 2.1-ULTIMATE Gate" begin
    CertSDP.CERTSDP_ABSOLUTE_GATE_MODE[] = true

    try
        @testset "Gate 1 native sparse no-filler density" begin
            @test gate_ultimate_1a_sparse_density()
            @test gate_ultimate_1b_zero_filler_trap()
        end

        @testset "Gate 2 nonzero multiplier semantics" begin
            @test gate_ultimate_2a_nonzero_multipliers()
            @test gate_ultimate_2b_all_zero_multiplier_trap()
        end

        @testset "Gate 3 NC critical-pair confluence" begin
            @test gate_ultimate_3a_critical_pair_valid()
            @test gate_ultimate_3b_nonjoinable_pair_reject()
        end

        @testset "Gate 4 NC report computed, not metadata" begin
            @test gate_ultimate_4_critical_pair_not_metadata()
        end

        @testset "Gate 5 ultimate benchmark" begin
            @test gate_ultimate_5_benchmark()
        end
    finally
        CertSDP.CERTSDP_ABSOLUTE_GATE_MODE[] = false
    end
end

println("CertSDP.jl 2.1-ULTIMATE Hard Gate: PASS")
