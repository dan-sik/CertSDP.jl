include("cli_subprocess_helpers.jl")

@testset "Gate X full offline bundle verify" begin
    root = joinpath(@__DIR__, "..", "fixtures", "certsdp3", "bundles")
    ok = certsdp3_subprocess(["bundle", "verify", joinpath(root, "paper_bundle_demo")])
    @test ok.exit_code == 0
end
