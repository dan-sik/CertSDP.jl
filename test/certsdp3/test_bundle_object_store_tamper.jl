include("cli_subprocess_helpers.jl")

@testset "Gate X object store tamper" begin
    root = joinpath(@__DIR__, "..", "fixtures", "certsdp3", "bundles")
    bad = certsdp3_subprocess(["bundle", "verify", joinpath(root, "paper_bundle_demo_tampered")])
    @test bad.exit_code != 0
end
