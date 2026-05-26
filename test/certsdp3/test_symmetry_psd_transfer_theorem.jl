@testset "Gate W PSD transfer theorem" begin
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "symmetric_sos_cyclic_medium", "certificate.json")
    cert = JSON3.read(read(path, String))
    transfer = filter(node -> String(node[:checker]) == "check_symmetry_psd_transfer",
                      cert[:proof_dag][:nodes])
    @test length(transfer) == 1
    bad = certsdp3_mutable_json(cert)
    idx = findfirst(node -> String(node[:checker]) == "check_symmetry_psd_transfer",
                    bad[:proof_dag][:nodes])
    deleteat!(bad[:proof_dag][:nodes], idx)
    @test_throws ArgumentError K3.parse_block_diagonalization_certificate_json(JSON3.write(bad))
end
