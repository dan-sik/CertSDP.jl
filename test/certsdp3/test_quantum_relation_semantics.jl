@testset "Gate J quantum relation semantics" begin
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "quantum_i3322_medium", "certificate.json")
    @test K3.replay_file(path; strict=true, io=nothing).accepted
    tamper = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                      "quantum_i3322_medium",
                      "tampered_commutation_relation.json")
    report = K3.replay_file(tamper; strict=true, io=nothing)
    @test !report.accepted
end
