@testset "Certifier pipeline" begin
    function certifier_toy_problem()
        return LMIProblem([0 1; 1 0],
                          [[1//1 0//1; 0//1 1//2]];
                          vars=[:x],)
    end

    @testset "toy degenerate LMI certifies end-to-end through msolve" begin
        if !has_msolve()
            @test_skip "msolve binary is not installed"
        else
            P = certifier_toy_problem()
            approx = ApproxSolution(P, [sqrt(big(2))];
                                    precision_bits=256,
                                    relative_tolerance="1e-12",
                                    gap_threshold="1e4",)

            result = certify(P, approx; msolve_precision=128, msolve_threads=1)

            @test result isa CertifiedResult
            @test iscertified(result)
            cert = certificate(result)
            @test cert isa AlgebraicCertificate
            @test result.psd_proof.method === :schur_zero
            @test result.psd_proof.schur_zero.pivot_block == [1]
            @test result.solution[1] == AlgebraicElement(result.root, "t")
            @test result.root.f == parse_polynomial("t^2 - 2")
            @test haskey(result.provenance, :algebraic_backend)
            @test result.provenance[:algebraic_backend] isa AlgebraicBackendProvenance
            cert_json = CertSDP.certificate_json_v1(cert)
            @test cert_json.provenance.algebraic_backend.backend == "msolve"
            @test verify(result)
        end
    end

    @testset "root selection chooses the real solution closest to xhat" begin
        P = certifier_toy_problem()
        approx = ApproxSolution(P, [sqrt(big(2))];
                                precision_bits=256,
                                relative_tolerance="1e-12",
                                gap_threshold="1e4",)
        rur = RURSolution([:Y_2_1, :Y_1_1, :x],
                          Rational{BigInt}[0, 0, 1],
                          parse_polynomial("t^2 - 2"),
                          parse_polynomial("2*t"),
                          [parse_polynomial("-2*t"), parse_polynomial("2")],
                          BigInt[1, 1])
        output = MsolveOutput(:finite,
                              0,
                              2,
                              [:Y_2_1, :Y_1_1, :x],
                              rur,
                              [[MsolveInterval(1, 1), MsolveInterval(7 // 10, 8 // 10),
                                MsolveInterval(-3 // 2, -7 // 5)],
                               [MsolveInterval(1, 1), MsolveInterval(-8 // 10, -7 // 10),
                                MsolveInterval(7 // 5, 3 // 2)]],
                              "")

        candidates = select_nearby_real_solutions(output, P, approx)

        @test length(candidates) == 2
        @test candidates[1].root.interval.lower == 7 // 5
        @test candidates[1].root.interval.upper == 3 // 2
        @test candidates[1].coordinates[1] == AlgebraicElement(candidates[1].root, "t")
        @test candidates[2].root.interval.lower == -3 // 2
        @test candidates[1].distance < candidates[2].distance

        system = build_incidence_system(P, approx)
        @test verify_polynomial_system_solution(system, candidates[1])

        tampered = SelectedAlgebraicSolution(candidates[1].root,
                                             candidates[1].coordinates,
                                             [candidates[1].all_coordinates[1],
                                              AlgebraicElement(candidates[1].root, "0"),
                                              candidates[1].all_coordinates[3]],
                                             candidates[1].variable_order,
                                             candidates[1].box,
                                             candidates[1].distance)
        @test !verify_polynomial_system_solution(system, tampered)
    end

    @testset "candidate failing incidence equations is rejected before certificate build" begin
        P = certifier_toy_problem()
        approx = ApproxSolution(P, [sqrt(big(2))];
                                precision_bits=256,
                                relative_tolerance="1e-12",
                                gap_threshold="1e4",)
        bad_rur = RURSolution([:Y_2_1, :Y_1_1, :x],
                              Rational{BigInt}[0, 0, 1],
                              parse_polynomial("t^2 - 2"),
                              parse_polynomial("2*t"),
                              [parse_polynomial("-2*t"), parse_polynomial("0")],
                              BigInt[1, 1])
        bad_output = MsolveOutput(:finite,
                                  0,
                                  2,
                                  [:Y_2_1, :Y_1_1, :x],
                                  bad_rur,
                                  [[MsolveInterval(1, 1), MsolveInterval(0, 0),
                                    MsolveInterval(7 // 5, 3 // 2)]],
                                  "")
        candidates = select_nearby_real_solutions(bad_output, P, approx)
        system = build_incidence_system(P, approx)

        @test !verify_polynomial_system_solution(system, candidates[1])

        result = CertSDP._certify_from_msolve_output(P,
                                                     approx,
                                                     approx.rank_profile,
                                                     system,
                                                     bad_output)

        @test result isa NoNearbyRealSolutionFailure
        @test result.reason === :no_candidate_verified
        @test result.stage === :verify
        @test result.diagnostics[:candidate_failures][1][:stage] === :incidence_solution
        @test occursin("incidence system",
                       result.diagnostics[:candidate_failures][1][:message])
    end

    @testset "missing msolve is returned as structured failure" begin
        P = certifier_toy_problem()
        approx = ApproxSolution(P, [sqrt(big(2))];
                                precision_bits=256,
                                relative_tolerance="1e-12",
                                gap_threshold="1e4",)

        result = certify(P, approx; msolve_binary="/definitely/not/msolve")

        @test result isa FailureResult
        @test result.failure isa BackendFailure
        @test result.reason === :msolve_failed
        @test result.stage === :msolve
        @test result.diagnostics[:backend_failure] isa AlgebraicBackendFailure
        @test result.diagnostics[:backend_failure].reason === :unavailable

        as_json = certification_failure_json(result)
        @test as_json.status == "not_certified"
        @test as_json.reason == "msolve_failed"
        @test haskey(as_json.diagnostics, "exception_type")
        @test as_json.diagnostics["backend_failure"].failure_type ==
              "AlgebraicBackendFailure"

        report = failure_report_json(result)
        @test report.provenance.algebraic_backend.backend == "msolve"
        @test report.details["backend_failure"].failure_type == "AlgebraicBackendFailure"
    end

    @testset "input sanity failures are structured" begin
        P = certifier_toy_problem()
        approx = ApproxSolution(P, [sqrt(big(2))];
                                precision_bits=256,
                                relative_tolerance="1e-12",
                                gap_threshold="1e4",)

        noisy = ApproxSolution(P, [sqrt(big(2))];
                               precision_bits=256,
                               Xhat=approx.Xhat .+ BigFloat("1e-4"),
                               relative_tolerance="1e-12",
                               gap_threshold="1e4",)
        noisy_result = certify(P, noisy; max_linear_residual="1e-8")

        @test noisy_result isa FailureResult
        @test noisy_result.failure isa NumericalFailure
        @test noisy_result.reason === :approximation_residual_too_large
        @test noisy_result.stage === :input

        other = LMIProblem([0 1; 1 0],
                           [[1//1 0//1; 0//1 1//3]];
                           vars=[:x],)
        mismatch_result = certify(other, approx)

        @test mismatch_result isa FailureResult
        @test mismatch_result.failure isa NumericalFailure
        @test mismatch_result.reason === :approximation_problem_mismatch
        @test mismatch_result.stage === :input
    end

    @testset "invalid PSD proof method is structured failure" begin
        if !has_msolve()
            @test_skip "msolve binary is not installed"
        else
            P = certifier_toy_problem()
            approx = ApproxSolution(P, [sqrt(big(2))];
                                    precision_bits=256,
                                    relative_tolerance="1e-12",
                                    gap_threshold="1e4",)

            result = certify(P, approx; psd_method=:definitely_not_a_method)

            @test result isa FailureResult
            @test result.failure isa PSDVerificationFailure
            @test result.reason === :invalid_psd_proof_method
            @test result.stage === :certificate_build
        end
    end

    @testset "unstable rank profile stops before incidence construction" begin
        P = certifier_toy_problem()
        approx = ApproxSolution(P, [sqrt(big(2))];
                                precision_bits=256,
                                relative_tolerance="1e6",
                                gap_threshold="1e4",)

        unstable = UnstableRankProfile("test unstable profile",
                                       BigFloat(1),
                                       BigFloat[2, 1],
                                       BigFloat(2),
                                       1,
                                       :test)
        result = certify(P, approx; rank_profile=unstable)

        @test result isa FailureResult
        @test result.failure isa RankUnstableFailure
        @test result.reason === :rank_profile_unstable
        @test result.stage === :rank_profile
        @test result.diagnostics[:candidate_rank] == 1
    end
end
