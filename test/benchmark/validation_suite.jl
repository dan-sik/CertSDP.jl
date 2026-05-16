@testset "Validation benchmark suite" begin
    repo_root = normpath(joinpath(@__DIR__, "..", ".."))
    suite_root = joinpath(repo_root, "benchmarks")

    @testset "validation fixtures cover public workflows" begin
        @test isdir(suite_root)
        cases = benchmark_cases(suite_root; subset=:validation)
        @test length(cases) >= 15

        categories = Set(case.expected.category for case in cases)
        for category in ["multi_block_sdp_validation",
                         "algebraic_incidence_validation",
                         "SOS",
                         "imported_workflow_validation",
                         "solve_diagnose_certify_validation"]
            @test category in categories
        end

        @test any(case -> case.expected.certificate_origin ==
                          "certifier_generated" &&
                              case.expected.pipeline == "certify_from_approx" &&
                              case.expected.algebraic_degree >= 4 &&
                              case.expected.variable_count >= 2,
                  cases)
        @test any(case -> case.expected.source_kind == "jump_moi_extract" &&
                      case.expected.workflow ===
                      CertSDP.JUMP_MOI_EXTRACT_WORKFLOW,
                  cases)

        for case in cases
            @test isfile(case.problem_path)
            if case.expected.workflow === CertSDP.JUMP_MOI_EXTRACT_WORKFLOW
                @test basename(case.problem_path) == "source.jl"
            else
                @test isfile(case.approx_path)
            end
            @test isfile(case.expected_path)
            @test isfile(case.readme_path)
            @test case.expected.expected_runtime_seconds > 0
            @test case.expected.memory_expectation_mb >= 0
            @test case.expected.backend_requirement in ("none", "msolve",
                                                        "clarabel",
                                                        "external_optional")
            @test length(strip(read(case.readme_path, String))) > 80
        end
    end

    @testset "runner writes validation report and enforces expected status" begin
        output_dir = mktempdir()
        report_path = joinpath(output_dir, "VALIDATION_REPORT.md")
        generated_dir = joinpath(output_dir, "generated")

        result = run_benchmarks(suite_root;
                                out=report_path,
                                subset=:validation,
                                generated_dir)

        @test result.passed
        @test isempty(result.mismatches)
        @test length(result.rows) >= 15
        @test isfile(report_path)

        report = read(report_path, String)
        @test occursin("# CertSDP v1.0 Validation Report", report)
        @test occursin("Executive Summary", report)
        @test occursin("Replay Evidence At A Glance", report)
        @test occursin("Evidence By Workflow Family", report)
        @test occursin("Paper Artifact Coverage", report)
        @test occursin("Paper-derived degenerate SDP mechanism", report)
        @test occursin("SDPA/SDPLIB-style imported SDP", report)
        @test occursin("SumOfSquares-style SOS workflow", report)
        @test occursin("Adversarial Mutation Matrix", report)
        @test occursin("Raw Artifacts And Archival Status", report)
        @test occursin("Archival DOI", report)
        @test occursin("Verification Footprint", report)
        @test occursin("Does the algebraic path cover rational-rounding failure?",
                       report)
        @test !occursin("Number Of Actual Rational Rounding Failures Certified",
                        report)
        @test !occursin("Number Of Solve -> Diagnose -> Certify Workflows Passed",
                        report)
        @test !occursin("Strict Verifier Timing Summary", report)
        @test occursin("Slowest Validation Cases", report)
        @test occursin("Cache consistency", report)
        @test occursin("algebraic_certifier_quartic_dim10_n2", report)
        @test occursin("workflow_jump_moi_extract_multiblock_dim48", report)
        @test all(row.verify_consistent for row in result.rows)
        @test all(row.verify_cache_hits >= 0 for row in result.rows)
        @test all(row.verify_cache_misses >= 0 for row in result.rows)
        @test any(row -> row.cert_size > 0, result.rows)

        cert_files = filter(name -> endswith(name, "_cert.json"), readdir(generated_dir))
        @test !isempty(cert_files)
    end

    @testset "expected status mismatch fails clearly" begin
        source_case = joinpath(suite_root, "validation",
                               "fake_rational_solution_rejected")
        temp_root = mktempdir()
        bad_case = joinpath(temp_root, "negative_fake_cert_rational_solution")
        cp(source_case, bad_case)

        expected_path = joinpath(bad_case, "expected.json")
        text = read(expected_path, String)
        write(expected_path,
              replace(text,
                      "\"expected_status\": \"rejected\"" => "\"expected_status\": \"certified\""))

        result = run_benchmarks(temp_root;
                                out=joinpath(temp_root, "report.md"),
                                subset=:all)

        @test !result.passed
        @test length(result.mismatches) == 1
        @test occursin("expected status certified, got rejected", result.mismatches[1])
        @test occursin("expected `certified` but observed `rejected`",
                       read(joinpath(temp_root, "report.md"), String))
    end

    @testset "benchmark source execution is repo-local and documented" begin
        docs = read(joinpath(repo_root, "docs", "benchmarks.md"), String)
        @test occursin("Source Execution Trust Model", docs)
        @test occursin("not a sandbox", docs)
        source_path = joinpath(mktempdir(), "source.jl")
        write(source_path, "error(\"should not execute\")\n")
        result = CertSDP._run_jump_moi_extraction_script(source_path, mktempdir())
        @test result.status == CertSDP.BENCHMARK_STATUS_BACKEND_UNAVAILABLE
        @test occursin("refusing to execute benchmark source outside this repository",
                       result.message)
    end

    @testset "CLI benchmark command" begin
        function run_cli(args...)
            out = IOBuffer()
            err = IOBuffer()
            code = CertSDP.main(collect(String.(args)); io=out, err=err)
            return (;
                    code,
                    out=String(take!(out)),
                    err=String(take!(err)),)
        end

        output_dir = mktempdir()
        report_path = joinpath(output_dir, "VALIDATION_REPORT.md")
        result = run_cli("benchmark",
                         suite_root,
                         "--suite",
                         "validation",
                         "--budget",
                         "validation",
                         "--timeout",
                         "300",
                         "--out",
                         report_path,
                         "--generated-dir",
                         joinpath(output_dir, "generated"))

        @test result.code == 0
        @test occursin("[OK] wrote benchmark report", result.out)
        @test occursin("[INFO] validation budget: validation", result.out)
        @test occursin("[OK] benchmark expected statuses matched", result.out)
        @test isempty(result.err)
        @test isfile(report_path)

        default_out = joinpath(mktempdir(), "benchmarks")
        cp(suite_root, default_out)
        default_result = run_cli("benchmark", default_out, "--suite", "validation")
        @test default_result.code == 0
        @test isfile(joinpath(default_out, "VALIDATION_REPORT.md"))
    end
end
