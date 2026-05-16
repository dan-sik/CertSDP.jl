using JSON3: JSON3

@testset "Replay reproducibility tooling" begin
    function run_tooling_cli(args...)
        out = IOBuffer()
        err = IOBuffer()
        code = CertSDP.main(collect(String.(args)); io=out, err=err)
        return (;
                code,
                out=String(take!(out)),
                err=String(take!(err)),)
    end

    @testset "doctor reports validation readiness components" begin
        report = doctor_report()
        names = [check.name for check in report.checks]
        for expected in ("Julia", "CertSDP", "RAM/CPU threads", "Clarabel",
                         "msolve", "SumOfSquares", "JuMP", "cache status",
                         "validation suite")
            @test expected in names
        end
        @test report.status in ("ready", "not_ready")
        @test report.ready == all(check -> check.ok ||
                                               !(check.name in ("Julia", "CertSDP",
                                                                "RAM/CPU threads",
                                                                "Clarabel", "msolve",
                                                                "SumOfSquares", "JuMP",
                                                                "validation suite")),
                                  report.checks)

        cli = run_tooling_cli("doctor")
        @test cli.code in (0, 5)
        @test occursin("CertSDP doctor", cli.out)
        @test occursin("ready to run", cli.out)
        @test isempty(cli.err)
    end

    @testset "explain failure is useful and capped at 30 lines" begin
        failure = CertificationFailure(:rank_profile_unstable,
                                       "rank gap too small",
                                       :rank_profile,
                                       Dict{Symbol, Any}(:candidate_ranks => [2, 3],
                                                         :gap => "1e-3",
                                                         :singular_values => ["1", "1e-9"]))
        path = tempname() * ".json"
        write_failure_report(path, failure)

        lines = explain_failure_report(path)
        @test length(lines) <= 30
        @test occursin("RankUnstableFailure", join(lines, "\n"))
        @test occursin("candidate_ranks", join(lines, "\n"))
        @test any(startswith(line, "- ") for line in lines)

        cli = run_tooling_cli("explain", path)
        @test cli.code == 5
        @test count(==('\n'), cli.out) <= 30
        @test occursin("Likely next steps:", cli.out)
        @test isempty(cli.err)
    end

    @testset "bundle and replay strict verification artifact" begin
        P = LMIProblem([1 0; 0 1],
                       [[1 0; 0 0],
                        [0 0; 0 1]];
                       vars=[:x, :y],)
        temp = mktempdir()
        problem_path = joinpath(temp, "problem.json")
        approx_path = joinpath(temp, "approx.json")
        cert_path = joinpath(temp, "cert.json")
        bundle_path = joinpath(temp, "artifact.zip")
        logs_dir = joinpath(temp, "logs")
        mkpath(logs_dir)
        write_problem(problem_path, P)
        write(approx_path, """
        {
            "certsdp_version": "0.1",
            "solution": {
                "type": "rational",
                "x": ["1/2", "1/3"]
            }
        }
        """)
        write(joinpath(logs_dir, "backend.log"),
              "no backend used for rational fixture at $logs_dir\n")

        certify = run_tooling_cli("certify", problem_path, "--solution", approx_path,
                                  "--out", cert_path)
        @test certify.code == 0

        bundled = run_tooling_cli("bundle", cert_path, "--out", bundle_path,
                                  "--problem", problem_path,
                                  "--approx", approx_path,
                                  "--logs", logs_dir)
        @test bundled.code == 0
        @test isfile(bundle_path)

        entries = CertSDP._zip_read(bundle_path)
        for entry in ("manifest.json", "README.md", "certificate/cert.json",
                      "problem/problem.json", "approx/approx.json",
                      "reports/verification_report.txt",
                      "versions/versions.json", "backend_logs/backend.log")
            @test haskey(entries, entry)
        end
        manifest = JSON3.read(String(entries["manifest.json"]))
        @test manifest.certsdp_artifact_bundle_version == "1.0"
        @test manifest.strict_verify_at_bundle_time == true
        @test manifest.redacted == true
        @test manifest.certificate_source == "<redacted>"
        @test !occursin(temp, String(entries["manifest.json"]))
        backend_log = String(entries["backend_logs/backend.log"])
        @test !occursin(logs_dir, backend_log)
        @test occursin("<redacted-path>", backend_log)
        @test !occursin(temp, String(entries["versions/versions.json"]))

        replay = run_tooling_cli("replay", bundle_path)
        @test replay.code == 0
        @test occursin("[OK] replay strict verification accepted", replay.out)
        @test isempty(replay.err)

        extract_dir = joinpath(temp, "extract")
        replay_extract = run_tooling_cli("replay", bundle_path, "--extract-dir",
                                         extract_dir)
        @test replay_extract.code == 0
        @test isfile(joinpath(extract_dir, "certificate", "cert.json"))
        @test isfile(joinpath(extract_dir, "versions", "versions.json"))
    end
end
