@testset "Gate L cubic field sign replay" begin
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "psd_factor_algebraic_40", "certificate.json")
    cert = JSON3.read(read(path, String))
    @test length(cert[:field][:minimal_polynomial]) - 1 >= 3
    @test K3.replay_file(path; strict=true, io=nothing).accepted
end
