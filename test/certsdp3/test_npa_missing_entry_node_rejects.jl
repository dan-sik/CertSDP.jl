@testset "Gate J missing NPA entry node rejects" begin
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "quantum_i3322_medium", "certificate.json")
    cert = JSON3.read(read(path, String))
    nodes = certsdp3_mutable_json(cert[:proof_dag][:nodes])
    idx = findfirst(node -> node[:kind] == "npa_moment_entry", nodes)
    @test !isnothing(idx)
    deleteat!(nodes, idx)
    bad = certsdp3_mutable_json(cert)
    bad[:proof_dag][:nodes] = nodes
    @test_throws ArgumentError K3.parse_quantum_bound_certificate_json(JSON3.write(bad))
end
