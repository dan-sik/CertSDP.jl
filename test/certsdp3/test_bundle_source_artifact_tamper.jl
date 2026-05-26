include("cli_subprocess_helpers.jl")

@testset "Gate X source artifact tamper" begin
    root = joinpath(@__DIR__, "..", "fixtures", "certsdp3", "bundles")
    bad = certsdp3_subprocess(["bundle", "verify", joinpath(root, "tampered_imported_tssos_bundle")])
    @test bad.exit_code != 0
end
