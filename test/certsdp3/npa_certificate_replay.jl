@testset "Gate J NPA fixture replay" begin
    chsh = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "quantum_chsh_level2", "certificate.json")
    cert = K3.parse_quantum_bound_certificate_json(read(chsh, String))
    @test K3.verify_quantum_bound_certificate(cert).accepted

    bad = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                   "quantum_chsh_level2", "tampered_objective.json")
    @test_throws ArgumentError K3.parse_quantum_bound_certificate_json(read(bad, String))
end
