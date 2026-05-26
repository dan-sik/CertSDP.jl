@testset "Gate G no primal-dual lhs/rhs fallback" begin
    valid = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                     "primal_dual_portfolio_50", "certificate.json")
    cert = K3.parse_primal_dual_optimality_certificate_json(read(valid, String))
    @test K3.verify_primal_dual_optimality(cert).accepted

    bad = certsdp3_mutable_json(JSON3.read(read(valid, String)))
    delete!(bad, :problem)
    delete!(bad[:primal], :primal_vector)
    delete!(bad[:dual], :dual_variables)
    @test_throws ArgumentError K3.parse_primal_dual_optimality_certificate_json(JSON3.write(bad))
end
