using JSON3: JSON3

@testset "Structured failure reports" begin
    function failure_report_problem()
        return LMIProblem([0 1; 1 0],
                          [[1//1 0//1; 0//1 1//2]];
                          vars=[:x],)
    end

    function failure_report_approx(P=failure_report_problem())
        return ApproxSolution(P,
                              [sqrt(big(2))];
                              precision_bits=256,
                              relative_tolerance="1e-12",
                              gap_threshold="1e4")
    end

    function report_roundtrip_ok(failure::CertificationFailure)
        report = failure_report_json(failure)
        json = JSON3.write(report)
        @test report.status == "not_certified"
        @test !isempty(report.summary)
        @test !isempty(report.suggestions)
        @test validate_failure_report_schema(json)
        parsed = parse_failure_report_json(json)
        @test parsed.reason === failure.reason
        @test parsed.stage === failure.stage
        return report
    end

    function run_cli(args...)
        out = IOBuffer()
        err = IOBuffer()
        code = CertSDP.main(collect(String.(args)); io=out, err=err)
        return (;
                code,
                out=String(take!(out)),
                err=String(take!(err)))
    end

    @testset "failure hierarchy exports public JSON" begin
        failures = CertificationFailure[CertificationFailure(:numerical_solver_failed,
                                                             "solver did not converge",
                                                             :numerical_oracle,
                                                             Dict{Symbol, Any}(:solver => "clarabel")),
                                        CertificationFailure(:rank_profile_unstable,
                                                             "rank gap too small",
                                                             :rank_profile,
                                                             Dict{Symbol, Any}(:gap => "1e-3")),
                                        CertificationFailure(:system_too_large,
                                                             "incidence system is too large",
                                                             :incidence,
                                                             Dict{Symbol, Any}(:variables => 51,
                                                                               :equations => 80)),
                                        CertificationFailure(:msolve_failed,
                                                             "backend missing",
                                                             :msolve,
                                                             Dict{Symbol, Any}(:backend_reason => :unavailable)),
                                        CertificationFailure(:no_real_algebraic_solution,
                                                             "no real root boxes",
                                                             :root_selection,
                                                             Dict{Symbol, Any}(:box_count => 0)),
                                        CertificationFailure(:psd_verification_failed,
                                                             "minor is negative",
                                                             :verify,
                                                             Dict{Symbol, Any}(:minor => [1,
                                                                                          2])),
                                        CertificationFailure(:sos_matching_failed,
                                                             "coefficient mismatch",
                                                             :sos_matching,
                                                             Dict{Symbol, Any}(:basis_size => 2))]

        expected_types = [NumericalFailure,
                          RankUnstableFailure,
                          SystemTooLargeFailure,
                          BackendFailure,
                          NoNearbyRealSolutionFailure,
                          PSDVerificationFailure,
                          SOSMatchingFailure]

        for (failure, expected) in zip(failures, expected_types)
            @test failure isa expected
            report = report_roundtrip_ok(failure)
            @test report.failure_type == String(nameof(expected))
            @test !isempty(report.details)
        end
    end

    @testset "certify returns result wrappers" begin
        P = failure_report_problem()
        approx = failure_report_approx(P)
        if !has_msolve()
            @test_skip "msolve binary is not installed"
        else
            result = certify(P, approx; msolve_precision=128)
            @test result isa CertifiedResult
            @test iscertified(result)
            @test certificate(result) isa AlgebraicCertificate
            @test verify(result)
        end

        failure_result = certify(P, approx; msolve_binary="/definitely/not/msolve")
        @test failure_result isa FailureResult
        @test !iscertified(failure_result)
        @test failure(failure_result) isa BackendFailure
        @test !verify(failure_result)
    end

    @testset "10 failure mode regression reports" begin
        P = failure_report_problem()
        approx = failure_report_approx(P)

        unstable = UnstableRankProfile("ambiguous tiny eigenvalue",
                                       BigFloat(1),
                                       BigFloat[2, 1],
                                       BigFloat(2),
                                       1,
                                       :test)
        noisy = ApproxSolution(P,
                               [sqrt(big(2))];
                               precision_bits=256,
                               Xhat=approx.Xhat .+ BigFloat("1e-4"),
                               relative_tolerance="1e-12",
                               gap_threshold="1e4")
        other = LMIProblem([0 1; 1 0],
                           [[1//1 0//1; 0//1 1//3]];
                           vars=[:x])

        actual_failures = [certify(P, approx; msolve_binary="/definitely/not/msolve"),
                           certify(P, approx; rank_profile=unstable),
                           certify(P, noisy; max_linear_residual="1e-8"),
                           certify(other, approx),
                           certify(P, approx; max_system_variables=1)]

        for result in actual_failures
            @test result isa FailureResult
            report_roundtrip_ok(result.failure)
        end
        @test failure(actual_failures[1]) isa BackendFailure
        @test failure(actual_failures[2]) isa RankUnstableFailure
        @test failure(actual_failures[3]) isa NumericalFailure
        @test failure(actual_failures[4]) isa NumericalFailure
        @test failure(actual_failures[5]) isa SystemTooLargeFailure

        manual_failures = CertificationFailure[CertificationFailure(:unsupported_numerical_solver,
                                                                    "solver is not supported",
                                                                    :numerical_oracle,
                                                                    Dict{Symbol, Any}(:solver => "imaginary")),
                                               CertificationFailure(:no_nearby_real_solution,
                                                                    "all real roots are far from xhat",
                                                                    :root_selection,
                                                                    Dict{Symbol, Any}(:nearest_distance => "10")),
                                               CertificationFailure(:psd_verification_failed,
                                                                    "exact verifier found a negative minor",
                                                                    :verify,
                                                                    Dict{Symbol, Any}(:minor_indices => [1])),
                                               CertificationFailure(:sos_matching_failed,
                                                                    "Gram matrix coefficient mismatch",
                                                                    :sos_matching,
                                                                    Dict{Symbol, Any}(:monomial => [2])),
                                               CertificationFailure(:sos_psd_failed,
                                                                    "Gram matrix is not PSD",
                                                                    :sos_psd,
                                                                    Dict{Symbol, Any}(:pivot => 2))]

        @test length(actual_failures) + length(manual_failures) == 10
        for failure in manual_failures
            report = report_roundtrip_ok(failure)
            @test occursin(" ", report.suggestions[1])
        end
    end

    @testset "SOS failures return FailureResult" begin
        problem = build_sos_gram_problem([:x],
                                         [[0], [1]],
                                         [PolynomialTerm([2], 1),
                                          PolynomialTerm([0], 1)])
        mismatch = certify_sos(problem, [1 1; 1 1])
        @test mismatch isa FailureResult
        @test mismatch.failure isa SOSMatchingFailure
        @test failure_report_json(mismatch).failure_type == "SOSMatchingFailure"

        nonpsd_problem = build_sos_gram_problem([:x],
                                                [[0], [1]],
                                                [PolynomialTerm([2], -1),
                                                 PolynomialTerm([0], 1)])
        nonpsd = certify_sos(nonpsd_problem, [1 0; 0 -1])
        @test nonpsd isa FailureResult
        @test nonpsd.failure isa SOSMatchingFailure
        @test nonpsd.reason === :sos_matching_failed
        @test nonpsd.stage === :sos_psd
    end

    @testset "diagnose failure.json is human-readable and exit codes are specific" begin
        failure = CertificationFailure(:rank_profile_unstable,
                                       "rank gap too small",
                                       :rank_profile,
                                       Dict{Symbol, Any}(:candidate_ranks => [2, 3],
                                                         :gap => "1e-3"))
        path = tempname() * ".json"
        write_failure_report(path, failure)

        result = run_cli("diagnose", path)
        @test result.code == 5
        @test occursin("CertSDP failure diagnosis", result.out)
        @test occursin("Failure type: RankUnstableFailure", result.out)
        @test occursin("Suggested next steps:", result.out)
        @test isempty(result.err)

        backend = CertificationFailure(:msolve_failed,
                                       "msolve missing",
                                       :msolve,
                                       Dict{Symbol, Any}(:backend_reason => :unavailable))
        backend_path = tempname() * ".json"
        write_failure_report(backend_path, backend)
        backend_cli = run_cli("diagnose", backend_path)
        @test backend_cli.code == 3
        @test occursin("Failure type: BackendFailure", backend_cli.out)
    end
end
