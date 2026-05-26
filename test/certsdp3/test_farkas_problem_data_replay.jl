@testset "Gate G Farkas problem data replay" begin
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "farkas_infeasible_lmi_medium", "certificate.json")
    @test K3.replay_file(path; strict=true, io=nothing).accepted

    tampered = certsdp3_mutable_json(JSON3.read(read(path, String)))
    tampered[:contradiction_rhs] = "-1"
    @test_throws ArgumentError K3.parse_farkas_infeasibility_certificate_json(JSON3.write(tampered))
end
