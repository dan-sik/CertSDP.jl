@testset "Gate G primal-dual affine operator replay" begin
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "primal_dual_portfolio_50", "certificate.json")
    @test K3.replay_file(path; strict=true, io=nothing).accepted

    tampered = certsdp3_mutable_json(JSON3.read(read(path, String)))
    tampered[:problem][:blocks][1][:A][1][:entries][1][:value] = "7"
    @test_throws ArgumentError K3.parse_primal_dual_optimality_certificate_json(JSON3.write(tampered))
end
