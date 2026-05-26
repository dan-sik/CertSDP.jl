@testset "Gate W block transform reconstruction" begin
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "symmetric_sos_cyclic_medium", "certificate.json")
    cert = JSON3.read(read(path, String))
    checkers = Set(String(node[:checker]) for node in cert[:proof_dag][:nodes])
    @test "verify_block_diagonalization_certificate" in checkers
    bad = certsdp3_mutable_json(cert)
    bad[:reconstructed_matrix][:entries][1][:value] = "2"
    @test_throws ArgumentError K3.parse_block_diagonalization_certificate_json(JSON3.write(bad))
end
