include("cli_subprocess_helpers.jl")

@testset "Gate X extra proof file rejects" begin
    src = joinpath(@__DIR__, "..", "fixtures", "certsdp3", "bundles",
                   "paper_bundle_demo")
    tmp = mktempdir()
    cp(src, tmp; force=true)
    bundle = joinpath(tmp, basename(src))
    write(joinpath(bundle, "extra_proof.json"), "{}\n")
    bad = certsdp3_subprocess(["bundle", "verify", bundle])
    @test bad.exit_code != 0
end
