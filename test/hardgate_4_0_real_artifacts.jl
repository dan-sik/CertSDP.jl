using CertSDP
using Test

for name in names(CertSDP; all=true)
    text = String(name)
    (occursin("#", text) || startswith(text, "_")) && continue
    name in (:CertSDP, :eval, :include) && continue
    isdefined(@__MODULE__, name) && continue
    @eval const $(name) = getproperty(CertSDP, $(QuoteNode(name)))
end

const REAL_GATE_ROOT = joinpath(@__DIR__, "..", "benchmarks", "real_artifacts")

@testset "CertSDP 2.1R Real Artifact Reconstruction Gate" begin
    CertSDP.CERTSDP_REAL_GATE_MODE[] = true
    try
        @testset "Gate 0 anti-cheat instrumentation" begin
            @test gate0_anti_cheat_instrumentation()
        end

        @testset "Gate 1 real SumOfSquares reconstruction" begin
            @test gate1_real_sumofsquares_gram()
            @test gate1_reject_tampered_sumofsquares()
        end

        @testset "Gate 2 real sparse TSSOS reconstruction" begin
            @test gate2_real_sparse_tssos()
            @test gate2_reject_wrong_sparse_multiplier()
        end

        @testset "Gate 3 automatic field discovery" begin
            @test gate3_field_discovery_without_hints()
            @test gate3_reject_field_budget_exceeded()
        end

        @testset "Gate 4 real clustered low-rank reconstruction" begin
            @test gate4_real_clustered_low_rank()
            @test gate4_reject_bad_symmetry_transform()
        end

        @testset "Gate 5 real NC trace reconstruction" begin
            @test gate5_real_nc_trace()
            @test gate5_reject_bad_nc_variants()
        end

        @testset "Gate 6 real infeasibility reconstruction" begin
            @test gate6_real_farkas_infeasibility()
            @test gate6_reject_bad_dual_multiplier()
        end

        @testset "Gate 7 minimization semantic preservation" begin
            @test gate7_real_minimization()
        end

        @testset "Gate 8 replay independence" begin
            @test gate8_replay_independence()
        end

        @testset "Trap artifact must be rejected" begin
            @test gate_trap_reject_wrong_hash()
        end
    finally
        CertSDP.CERTSDP_REAL_GATE_MODE[] = false
    end
end

println("CertSDP.jl 2.1R Real Artifact Hard Gate: PASS")
