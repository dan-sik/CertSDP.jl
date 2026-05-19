using CertSDP
using Test

for name in names(CertSDP; all=true)
    text = String(name)
    (occursin("#", text) || startswith(text, "_")) && continue
    name in (:CertSDP, :eval, :include) && continue
    isdefined(@__MODULE__, name) && continue
    @eval const $(name) = getproperty(CertSDP, $(QuoteNode(name)))
end

@testset "CertSDP 2.0 Exact Certificate Compiler Hard Gate" begin
    @test gate1_sparse_opf_like_sos()
    @test gate2_algebraic_symmetry_clustered_low_rank()
    @test gate3_nc_trace_npa_certificate()
    @test gate4_quantum_code_like_infeasibility()
    @test gate5_automatic_field_escalation_minimality()
    @test gate6_certificate_minimization()
    @test gate7_external_artifact_import()

    @test hidden_gate_sparse_opf_like()
    @test hidden_gate_symmetry_clustered_low_rank()
    @test hidden_gate_nc_trace_npa()
    @test hidden_gate_infeasibility()

    @test pass_hidden_variant(:sparse_opf_like)
    @test pass_hidden_variant(:symmetry_clustered_low_rank)
    @test pass_hidden_variant(:nc_trace_npa)
    @test pass_hidden_variant(:quantum_code_infeasibility)

    @test compiler_validation_runtime() <= 900
end

println("CertSDP.jl 2.0 Hard Gate: PASS")
