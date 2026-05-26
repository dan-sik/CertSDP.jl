@testset "Gate W projector completeness" begin
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "symmetric_sos_cyclic_medium", "certificate.json")
    @test K3.replay_file(path; strict=true, io=nothing).accepted
    bad = certsdp3_mutable_json(JSON3.read(read(path, String)))
    bad[:projector_matrices][1][:entries][1][:value] = "2"
    @test_throws ArgumentError K3.parse_block_diagonalization_certificate_json(JSON3.write(bad))
end
