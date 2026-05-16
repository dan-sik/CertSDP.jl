@testset "Release audit scripts" begin
    repo_root = normpath(joinpath(@__DIR__, ".."))
    drill_script = joinpath(repo_root, "scripts", "release_audit.jl")
    fresh_script = joinpath(repo_root, "scripts", "fresh_checkout_release_audit.sh")
    checklist = joinpath(repo_root, "RELEASE_CHECKLIST.md")

    @test isfile(drill_script)
    @test isfile(fresh_script)
    @test isfile(checklist)

    drill_text = read(drill_script, String)
    @test occursin("no_msolve_strict_path", drill_text)
    @test occursin("strict_fake_certificate_sample", drill_text)
    @test occursin("package_registration_dry_run", drill_text)
    @test occursin("Apache License", drill_text)
    @test occursin("v1 Release Audit", drill_text)
    @test !occursin("Beta " * "Review" * "er", drill_text)

    fresh_text = read(fresh_script, String)
    @test occursin("git clone", fresh_text)
    @test occursin("--include-worktree", fresh_text)
    @test occursin("--mode sampled-clean", fresh_text)
    @test occursin("references/ is ignored local research context", fresh_text)
    @test occursin("release_audit.jl", fresh_text)

    checklist_text = read(checklist, String)
    @test occursin("Strict verifier adversarial tests", checklist_text)
    @test occursin("Clean clone quickstart", checklist_text)
    @test occursin("Release audit", checklist_text)

    include(drill_script)
    audit_module = Main.ReleaseAuditDrill
    dry_run = audit_module.package_registration_dry_run(repo_root)
    @test dry_run.passed
    @test isempty(dry_run.issues)
    @test length(audit_module.fake_certificate_cases()) >= 3
    @test length(audit_module.failure_report_cases()) >= 2
end
