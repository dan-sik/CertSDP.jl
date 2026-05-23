@testset "Gate QA deterministic replay evidence" begin
    root = normpath(joinpath(@__DIR__, "..", "fixtures", "certsdp3"))
    cert_path = joinpath(root, "psd_factor_rational_150", "certificate.json")
    reports = [K3.replay_file(cert_path; strict=true, io=nothing) for _ in 1:3]

    @test all(report -> report.accepted, reports)
    @test length(unique(report.certificate_hash for report in reports)) == 1
    @test length(unique(report.problem_hash for report in reports)) == 1

    tamper = joinpath(root, "quantum_i3322_medium", "tampered_psd_proof.json")
    bad = K3.replay_file(tamper; strict=true, io=nothing)
    @test !bad.accepted
    @test bad.stage !== :unknown
    @test bad.obligation_id !== :unknown
end
