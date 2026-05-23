@testset "Gate Z release audit is executable evidence" begin
    root = normpath(joinpath(@__DIR__, "..", ".."))
    report_path = joinpath(root, "build", "certsdp3_audit_report.json")
    score_path = joinpath(root, "build", "certsdp3_gate_scores.json")

    proc = run(pipeline(`$(Base.julia_cmd()) --project=$(root) --startup-file=no $(joinpath(root, "scripts", "release_audit_certsdp3.jl")) --gate A`;
                        stdout=devnull, stderr=devnull);
               wait=false)
    wait(proc)
    @test success(proc)
    @test isfile(report_path)
    @test isfile(score_path)

    report = JSON3.read(read(report_path, String))
    @test report[:gates][:A][:status] == "PASS"
    @test report[:gates][:A][:score] >= 9
    @test !isempty(report[:gates][:A][:valid_fixtures_run])
    @test !isempty(report[:gates][:A][:tamper_fixtures_run])
end
