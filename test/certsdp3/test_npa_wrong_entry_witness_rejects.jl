@testset "Gate J wrong NPA entry witness rejects" begin
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "quantum_i3322_medium", "certificate.json")
    bad = certsdp3_mutable_json(JSON3.read(read(path, String)))
    idx = findfirst(node -> node[:kind] == "npa_moment_entry", bad[:proof_dag][:nodes])
    bad[:proof_dag][:nodes][idx][:typed_payload][:rewrite_witness][:final_word] = Any["BAD"]
    @test_throws ArgumentError K3.parse_quantum_bound_certificate_json(JSON3.write(bad))
end
