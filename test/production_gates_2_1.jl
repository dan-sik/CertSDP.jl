using CertSDP
using Test

for name in names(CertSDP; all=true)
    text = String(name)
    (occursin("#", text) || startswith(text, "_")) && continue
    name in (:CertSDP, :eval, :include) && continue
    isdefined(@__MODULE__, name) && continue
    @eval const $(name) = getproperty(CertSDP, $(QuoteNode(name)))
end

@testset "CertSDP 2.1 Production Gates" begin
    @test run_production_gates_2_1(io=devnull)
    @test length(CertSDP.PRODUCTION_GATE_CACHE) == PRODUCTION_GATE_COUNT
    @test all(values(CertSDP.PRODUCTION_GATE_CACHE))
end

println("CertSDP.jl 2.1 Production Gates: PASS")
