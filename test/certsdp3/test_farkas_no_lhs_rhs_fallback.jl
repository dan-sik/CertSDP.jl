@testset "Gate G no Farkas lhs/rhs fallback" begin
    valid = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                     "farkas_infeasible_lmi_medium", "certificate.json")
    cert = K3.parse_farkas_infeasibility_certificate_json(read(valid, String))
    @test K3.verify_farkas_infeasibility(cert).accepted

    bad = certsdp3_mutable_json(JSON3.read(read(valid, String)))
    delete!(bad, :problem)
    delete!(bad, :dual_variables)
    @test_throws ArgumentError K3.parse_farkas_infeasibility_certificate_json(JSON3.write(bad))
end
