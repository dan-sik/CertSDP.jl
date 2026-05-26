@testset "Gate W projector orthogonality" begin
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "symmetric_sos_cyclic_medium", "certificate.json")
    cert = JSON3.read(read(path, String))
    @test any(node -> String(node[:checker]) == "check_symmetry_projector_orthogonality",
              cert[:proof_dag][:nodes])
    @test K3.replay_file(path; strict=true, io=nothing).accepted
end
