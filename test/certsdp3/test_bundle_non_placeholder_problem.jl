include("cli_subprocess_helpers.jl")

@testset "Gate X bundle non-placeholder problem" begin
    root = joinpath(@__DIR__, "..", "fixtures", "certsdp3", "bundles")
    problem = read(joinpath(root, "paper_bundle_demo", "problem.json"), String)
    @test !occursin("certificate_exact_problem_reference", problem)
    @test certsdp3_subprocess(["bundle", "verify", joinpath(root, "paper_bundle_demo")]).exit_code == 0
end
