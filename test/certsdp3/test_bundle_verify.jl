include("cli_subprocess_helpers.jl")

@testset "bundle verify subprocess rejects tamper" begin
    root = normpath(joinpath(@__DIR__, "..", "fixtures", "certsdp3", "bundles"))
    ok = certsdp3_subprocess(["bundle", "verify", joinpath(root, "paper_bundle_demo")])
    @test ok.exit_code == 0
    bad = certsdp3_subprocess(["bundle", "verify", joinpath(root, "paper_bundle_demo_tampered")])
    @test bad.exit_code != 0
end

