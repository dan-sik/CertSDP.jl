@testset "Gate J objective from verified moments" begin
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "quantum_i3322_medium", "certificate.json")
    @test K3.replay_file(path; strict=true, io=nothing).accepted
    bad = certsdp3_mutable_json(JSON3.read(read(path, String)))
    obj = only(filter(node -> node[:id] == "objective_bound", bad[:proof_dag][:nodes]))
    pop!(obj[:typed_payload][:moment_entry_hashes])
    @test_throws ArgumentError K3.parse_quantum_bound_certificate_json(JSON3.write(bad))
end
