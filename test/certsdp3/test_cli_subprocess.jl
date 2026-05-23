include("cli_subprocess_helpers.jl")

@testset "CLI subprocess coverage" begin
    root = normpath(joinpath(@__DIR__, "..", "fixtures", "certsdp3"))
    valid = joinpath(root, "psd_factor_rational_150", "certificate.json")
    bad = joinpath(root, "psd_factor_rational_150", "tampered_negative_diagonal.json")
    ok = certsdp3_subprocess(["replay", valid, "--strict"])
    @test ok.exit_code == 0
    reject = certsdp3_subprocess(["replay", bad, "--strict"])
    @test reject.exit_code != 0
    tmp = mktempdir()
    ok_tmp = certsdp3_subprocess(["replay", valid, "--strict"]; cwd=tmp)
    @test ok_tmp.exit_code == 0
end

