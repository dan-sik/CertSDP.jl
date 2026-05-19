if !isdefined(@__MODULE__, :certsdp_should_run)
    certsdp_should_run(tags::String...) = true
end

@testset "CLI" begin
    function run_cli(args...)
        out = IOBuffer()
        err = IOBuffer()
        code = CertSDP.main(collect(String.(args)); io=out, err=err)
        return (;
                code,
                out=String(take!(out)),
                err=String(take!(err)),)
    end

    function cli_rational_problem()
        return LMIProblem([1 0; 0 1],
                          [[1 0; 0 0],
                           [0 0; 0 1]];
                          vars=[:x, :y],)
    end

    function cli_rational_solution_file(path::AbstractString)
        write(path, """
        {
            "certsdp_version": "0.1",
            "solution": {
                "type": "rational",
                "x": ["1/2", "1/3"]
            }
        }
        """)
        return path
    end

    @testset "certify, verify, and inspect rational flow" begin
        problem_path = tempname() * ".json"
        solution_path = tempname() * ".json"
        cert_path = tempname() * ".json"

        write_lmi_json(problem_path, cli_rational_problem())
        cli_rational_solution_file(solution_path)

        certify_result = run_cli("certify", problem_path, "--solution", solution_path,
                                 "--out", cert_path)
        @test certify_result.code == 0
        @test occursin("[OK] wrote certificate", certify_result.out)
        @test isempty(certify_result.err)
        @test isfile(cert_path)

        verify_result = run_cli("verify", cert_path)
        @test verify_result.code == 0
        @test occursin("[OK] certificate accepted", verify_result.out)

        inspect_result = run_cli("inspect", cert_path)
        @test inspect_result.code == 0
        @test occursin("Certificate: rational_psd_certificate", inspect_result.out)
        @test occursin("Solution: rational", inspect_result.out)
        @test occursin("Variables: 2 (x, y)", inspect_result.out)

        schema_result = run_cli("schema", "validate", cert_path, "--kind",
                                "certificate")
        @test schema_result.code == 0
        @test occursin("[OK] schema valid: certificate", schema_result.out)

        v1_problem_path = tempname() * ".json"
        migrated_problem_path = tempname() * ".json"
        write_problem(v1_problem_path, cli_rational_problem())
        schema_problem = run_cli("schema", "validate", v1_problem_path, "--kind",
                                 "problem")
        @test schema_problem.code == 0
        @test occursin("[OK] schema valid: problem", schema_problem.out)

        migrate_result = run_cli("migrate", problem_path, "--out",
                                 migrated_problem_path, "--kind", "problem")
        @test migrate_result.code == 0
        @test occursin("[OK] wrote migrated problem schema", migrate_result.out)

        migrated_validate = run_cli("schema", "validate", migrated_problem_path,
                                    "--kind", "problem")
        @test migrated_validate.code == 0
    end

    @testset "certify-sos exported Gram flow" begin
        problem_path = tempname() * ".json"
        solution_path = tempname() * ".json"
        cert_path = tempname() * ".json"

        problem = build_sos_gram_problem([:x],
                                         [[0], [1]],
                                         [PolynomialTerm([2], 1),
                                          PolynomialTerm([0], 1)])
        write(problem_path, sos_gram_problem_json_string(problem))
        write(solution_path, """
        {
            "certsdp_version": "0.1",
            "solution": {
                "type": "rational_gram_matrix",
                "gram_matrix": [["1", "0"], ["0", "1"]]
            }
        }
        """)

        certify_result = run_cli("certify-sos", problem_path, "--solution", solution_path,
                                 "--out", cert_path)
        @test certify_result.code == 0
        @test occursin("[OK] SOS Gram certificate accepted", certify_result.out)
        @test occursin("[OK] wrote SOS Gram certificate", certify_result.out)

        verify_result = run_cli("verify", cert_path)
        @test verify_result.code == 0
        @test occursin("[OK] SOS Gram certificate accepted", verify_result.out)

        inspect_result = run_cli("inspect", cert_path)
        @test inspect_result.code == 0
        @test occursin("Certificate: sos_gram_certificate", inspect_result.out)
        @test occursin("Gram basis size: 2", inspect_result.out)

        export_json_path = tempname() * ".json"
        export_json = run_cli("export-sos", cert_path, "--out", export_json_path)
        @test export_json.code == 0
        @test occursin("[OK] wrote SOS json export", export_json.out)
        @test occursin("\"squares\"", read(export_json_path, String))

        export_text_path = tempname() * ".txt"
        export_text = run_cli("export-sos", cert_path, "--out", export_text_path,
                              "--format", "text")
        @test export_text.code == 0
        @test occursin("[OK] wrote SOS text export", export_text.out)
        @test occursin("x^2 + 1", read(export_text_path, String))

        export_latex_path = tempname() * ".tex"
        export_latex = run_cli("export-sos", cert_path, "--out", export_latex_path,
                               "--format", "latex")
        @test export_latex.code == 0
        @test occursin("[OK] wrote SOS latex export", export_latex.out)
        @test occursin("\\left(x\\right)^2", read(export_latex_path, String))

        export_sage_path = tempname() * ".sage"
        export_sage = run_cli("export-sos", cert_path, "--out", export_sage_path,
                              "--format", "sage")
        @test export_sage.code == 0
        @test occursin("PolynomialRing(QQ", read(export_sage_path, String))

        export_julia_path = tempname() * ".jl"
        export_julia = run_cli("export-sos", cert_path, "--out", export_julia_path,
                               "--format", "julia")
        @test export_julia.code == 0
        @test occursin("@polyvar x", read(export_julia_path, String))
    end

    @testset "certify-auto-sos round-project flow" begin
        problem_path = tempname() * ".json"
        solution_path = tempname() * ".json"
        cert_path = tempname() * ".json"

        problem = build_sos_gram_problem([:x],
                                         [[1], [0]],
                                         [PolynomialTerm([2], 1),
                                          PolynomialTerm([0], 1)])
        write(problem_path, sos_gram_problem_json_string(problem))
        write(solution_path, """
        {
            "certsdp_version": "0.1",
            "solution": {
                "type": "rational_gram_matrix",
                "gram_matrix": [[1.0000001, 0.125], [0.125, 0.9999999]]
            }
        }
        """)

        result = run_cli("certify-auto-sos",
                         problem_path,
                         "--solution",
                         solution_path,
                         "--out",
                         cert_path,
                         "--tolerance",
                         "0.2",
                         "--max-denominator",
                         "64")
        @test result.code == 0
        @test occursin("[OK] exactification strategy: sos_round_project",
                       result.out)
        @test isfile(cert_path)

        verify_result = run_cli("verify", "--strict", cert_path)
        @test verify_result.code == 0
        @test occursin("[OK] SOS Gram certificate accepted", verify_result.out)
    end

    if certsdp_should_run("optional", "msolve", "slow")
        @testset "certify algebraic flow through msolve when available" begin
            if !has_msolve()
                @test_skip "msolve binary is not installed"
            else
                problem_path = tempname() * ".json"
                solution_path = tempname() * ".json"
                cert_path = tempname() * ".json"

                P = LMIProblem([0 1; 1 0],
                               [[1//1 0//1; 0//1 1//2]];
                               vars=[:x],)
                write_lmi_json(problem_path, P)
                write(solution_path, """
                {
                    "certsdp_version": "0.1",
                    "approximate_solution": {
                        "type": "xhat",
                        "precision_bits": 256,
                        "xhat": ["1.4142135623730950488016887242096980785696718753769"]
                    }
                }
                """)

                result = run_cli("certify",
                                 problem_path,
                                 "--solution",
                                 solution_path,
                                 "--out",
                                 cert_path,
                                 "--msolve-precision",
                                 "128")

                @test result.code == 0
                @test occursin("[INFO] running algebraic certifier", result.out)
                @test occursin("[OK] wrote certificate", result.out)

                inspect_result = run_cli("inspect", cert_path)
                @test inspect_result.code == 0
                @test occursin("Certificate: algebraic_psd_certificate", inspect_result.out)
                @test occursin("Minimal polynomial: t^2 - 2", inspect_result.out)
                @test occursin("PSD proof: schur_zero", inspect_result.out)
            end
        end
    end

    @testset "usage and parse errors exit with code 2" begin
        version = run_cli("version")
        @test version.code == 0
        @test occursin("CertSDP.jl 2.1.0", version.out)
        @test !occursin("phase_", version.out)

        missing_args = run_cli("certify")
        @test missing_args.code == 2
        @test occursin("[FAIL]", missing_args.err)
        @test occursin("usage:", missing_args.err)

        bad_cert_path = tempname() * ".json"
        write(bad_cert_path, "{not json")
        bad_verify = run_cli("verify", bad_cert_path)
        @test bad_verify.code == 2
        @test occursin("could not read certificate", bad_verify.err)

        problem_path = tempname() * ".json"
        solution_path = tempname() * ".json"
        write_lmi_json(problem_path, cli_rational_problem())
        write(solution_path, """
        {
            "certsdp_version": "0.1",
            "solution": {
                "type": "rational",
                "x": ["1/2"]
            }
        }
        """)

        bad_certify = run_cli("certify", problem_path, "--solution", solution_path, "--out",
                              tempname() * ".json")
        @test bad_certify.code == 2
        @test occursin("could not read solution", bad_certify.err)
        @test occursin("solution.x has length 1; expected 2", bad_certify.err)
    end

    @testset "diagnose approximate solution reports stable and unstable ranks" begin
        P = LMIProblem([0 0; 0 1],
                       [[1 0; 0 0]];
                       vars=[:x],)
        problem_path = tempname() * ".json"
        stable_path = tempname() * ".json"
        unstable_path = tempname() * ".json"
        write_lmi_json(problem_path, P)

        write(stable_path, """
        {
            "certsdp_version": "0.1",
            "approximate_solution": {
                "type": "xhat",
                "precision_bits": 256,
                "xhat": ["1.0"]
            }
        }
        """)

        stable = run_cli("diagnose",
                         problem_path,
                         "--solution",
                         stable_path,
                         "--rank-relative-tolerance",
                         "1e-12",
                         "--rank-gap-threshold",
                         "1e4")

        @test stable.code == 0
        @test occursin("CertSDP approximate solution diagnosis", stable.out)
        @test occursin("Minimum eigenvalue:", stable.out)
        @test occursin("Rank estimate: 2", stable.out)
        @test occursin("Rank confidence:", stable.out)
        @test occursin("[OK] approximate rank profile is stable", stable.out)

        write(unstable_path, """
        {
            "certsdp_version": "0.1",
            "approximate_solution": {
                "type": "xhat",
                "precision_bits": 256,
                "xhat": ["1e-20"]
            }
        }
        """)

        unstable = run_cli("diagnose",
                           problem_path,
                           "--solution",
                           unstable_path,
                           "--rank-relative-tolerance",
                           "5e-21",
                           "--rank-gap-threshold",
                           "1e6")

        @test unstable.code == 5
        @test occursin("Rank confidence: unstable", unstable.out)
        @test occursin("Rank instability reason:", unstable.out)
        @test occursin("[FAIL] approximate rank profile is unstable", unstable.out)
        @test isempty(unstable.err)
    end

    if certsdp_should_run("cli_validation", "slow")
        @testset "benchmark CLI runs exact compiler validation" begin
            output_dir = mktempdir()
            report_path = joinpath(output_dir, "VALIDATION_REPORT.md")
            result = run_cli("benchmark",
                             joinpath(@__DIR__, "..", "..", "benchmarks"),
                             "--suite",
                             "validation",
                             "--out",
                             report_path)

            @test result.code == 0
            @test occursin("[OK] wrote benchmark report", result.out)
            @test occursin("[OK] benchmark expected statuses matched", result.out)
            @test isfile(report_path)
            report = read(report_path, String)
            @test occursin("CertSDP.jl Validation Report", report)
            @test occursin("CertSDP.jl Validation: PASS", report)
        end
    end

    @testset "CLI solver failures do not crash" begin
        problem_path = tempname() * ".json"
        approx_path = tempname() * ".json"
        write_lmi_json(problem_path, cli_rational_problem())

        result = run_cli("solve",
                         problem_path,
                         "--out",
                         approx_path,
                         "--solver",
                         "not_a_solver")

        @test result.code == 2
        @test occursin("certification failed", result.err)
        @test occursin("numerical_solver_failed", result.err)
        @test !isfile(approx_path)
    end

    @testset "verification rejection exits with code 1" begin
        cert = RationalCertificate(cli_rational_problem(), [1 // 2, 1 // 3])
        json = rational_certificate_json_string(cert)
        tampered_json = replace(json, "\"1/2\"" => "\"-5\""; count=1)
        cert_path = tempname() * ".json"
        write(cert_path, tampered_json)

        result = run_cli("verify", cert_path)

        @test result.code == 1
        @test occursin("[FAIL] certificate hash matches", result.out)
    end

    @testset "certify rejection exits with code 5" begin
        problem_path = tempname() * ".json"
        solution_path = tempname() * ".json"
        write_lmi_json(problem_path, cli_rational_problem())
        write(solution_path, """
        {
            "certsdp_version": "0.1",
            "solution": {
                "type": "rational",
                "x": ["-2", "0"]
            }
        }
        """)

        result = run_cli("certify", problem_path, "--solution", solution_path, "--out",
                         tempname() * ".json")

        @test result.code == 5
        @test occursin("certification failed", result.err)
        @test occursin("PSDVerificationFailure", result.err)
    end

    @testset "certify budget timeout exits with code 4" begin
        problem_path = joinpath(@__DIR__, "..", "..", "examples",
                                "algebraic_problem.json")
        solution_path = joinpath(@__DIR__, "..", "..", "examples",
                                 "algebraic_approx.json")
        result = run_cli("certify",
                         problem_path,
                         "--solution",
                         solution_path,
                         "--out",
                         tempname() * ".json",
                         "--budget",
                         "validation",
                         "--timeout",
                         "0.000000001")

        @test result.code == 4
        @test occursin("BackendTimeoutFailure", result.err)
        @test occursin("validation_timeout", result.err)
        @test occursin("graceful_diagnostic", result.err)
    end

    @testset "certify-sos rejection exits with code 5" begin
        problem_path = tempname() * ".json"
        solution_path = tempname() * ".json"

        problem = build_sos_gram_problem([:x],
                                         [[0], [1]],
                                         [PolynomialTerm([2], 1),
                                          PolynomialTerm([0], 1)])
        write(problem_path, sos_gram_problem_json_string(problem))
        write(solution_path, """
        {
            "certsdp_version": "0.1",
            "solution": {
                "type": "rational_gram_matrix",
                "gram_matrix": [["1", "1"], ["1", "1"]]
            }
        }
        """)

        result = run_cli("certify-sos", problem_path, "--solution", solution_path, "--out",
                         tempname() * ".json")

        @test result.code == 5
        @test occursin("certification failed", result.err)
        @test occursin("SOSMatchingFailure", result.err)
    end
end
