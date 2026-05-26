@testset "Gate L cubic field sign tamper rejection" begin
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "psd_factor_algebraic_40",
                    "tampered_algebraic_sign.json")
    report = K3.replay_file(path; strict=true, io=nothing)
    @test !report.accepted
end
