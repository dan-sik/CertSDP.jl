@testset "Validation benchmark suite" begin
    for name in (:gate1_sparse_opf_like_sos,
                 :gate2_algebraic_symmetry_clustered_low_rank,
                 :gate3_nc_trace_npa_certificate,
                 :gate4_quantum_code_like_infeasibility,
                 :gate5_automatic_field_escalation_minimality,
                 :gate6_certificate_minimization,
                 :gate7_external_artifact_import,
                 :pass_hidden_variant,
                 :compiler_validation_runtime)
        isdefined(@__MODULE__, name) ||
            @eval const $(name) = getproperty(CertSDP, $(QuoteNode(name)))
    end

    @testset "exact compiler validation is the public validation suite" begin
        @test gate1_sparse_opf_like_sos()
        @test gate2_algebraic_symmetry_clustered_low_rank()
        @test gate3_nc_trace_npa_certificate()
        @test gate4_quantum_code_like_infeasibility()
        @test gate5_automatic_field_escalation_minimality()
        @test gate6_certificate_minimization()
        @test gate7_external_artifact_import()
    end

    @testset "seeded hidden variants reject hardcoding" begin
        @test pass_hidden_variant(:sparse_opf_like)
        @test pass_hidden_variant(:symmetry_clustered_low_rank)
        @test pass_hidden_variant(:nc_trace_npa)
        @test pass_hidden_variant(:quantum_code_infeasibility)
    end

    @testset "compiler validation runtime budget" begin
        @test compiler_validation_runtime() <= 900
    end
end
