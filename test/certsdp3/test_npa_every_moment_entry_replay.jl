@testset "Gate J every NPA moment entry replay" begin
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "quantum_i3322_medium", "certificate.json")
    cert = JSON3.read(read(path, String))
    declared = length(cert[:moment_certificate][:moment_matrix][:entries])
    nodes = count(node -> node[:kind] == "npa_moment_entry",
                  cert[:proof_dag][:nodes])
    @test K3.replay_file(path; strict=true, io=nothing).accepted
    @test nodes == declared
end
