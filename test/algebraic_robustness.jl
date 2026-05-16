@testset "Algebraic robustness" begin
    function algebraic_robustness_problem()
        return LMIProblem([0 1; 1 0],
                          [[1//1 0//1; 0//1 1//2]];
                          vars=[:x],)
    end

    function algebraic_robustness_approx(P=algebraic_robustness_problem())
        return ApproxSolution(P, [sqrt(big(2))];
                              precision_bits=256,
                              relative_tolerance="1e-12",
                              gap_threshold="1e4")
    end

    function free_slice_problem()
        return LMIProblem([1//1 0//1; 0//1 0//1],
                          [[0//1 0//1; 0//1 0//1]];
                          vars=[:x],)
    end

    cubic_cases = [(name=:cubic_minus2_22,
                    approx=big"2.5122989997865677",
                    minimal="3*t^3 - 3*t^2 - 11*t - 1",
                    A0=[-2//1 -2//1 1//1; -2//1 2//1 2//1; 1//1 2//1 0//1],
                    A1=[2//1 0//1 0//1; 0//1 2//1 1//1; 0//1 1//1 2//1]),
                   (name=:cubic_minus1_0_13,
                    approx=big"0.36427998711956977",
                    minimal="3*t^3 + 5*t^2 - 16*t - 3",
                    A0=[1//1 -2//1 1//1; -2//1 2//1 -1//1; 1//1 -1//1 1//1],
                    A1=[0//1 1//1 -2//1; 1//1 2//1 2//1; -2//1 2//1 -1//1]),
                   (name=:cubic_4_11_0,
                    approx=big"1.81671263224485",
                    minimal="11*t^3 + 32*t^2 + 19*t - 6",
                    A0=[2//1 0//1 1//1; 0//1 2//1 1//1; 1//1 1//1 2//1],
                    A1=[-1//1 0//1 -1//1; 0//1 2//1 0//1; -1//1 0//1 1//1])]

    @testset "system carries slicing metadata and exact slice equations" begin
        P = algebraic_robustness_problem()
        approx = algebraic_robustness_approx(P)
        system = build_incidence_system(P, approx, approx.rank_profile;
                                        slicing=:none)
        @test system.metadata[:certifier_context] === :validation_algebraic_robustness
        @test system.metadata[:slicing_strategy] === :none
        @test system.metadata[:slicing_equations] == String[]
        @test haskey(system.metadata, :slicing_equation_specs)
    end

    @testset "user-provided slicing is accepted" begin
        P = algebraic_robustness_problem()
        approx = algebraic_robustness_approx(P)
        slice = [(coefficients=Dict(:x => 1), rhs=1, label="x=1")]
        system = build_incidence_system(P, approx, approx.rank_profile;
                                        slicing=:user,
                                        slicing_equations=slice)
        @test system.metadata[:slicing_strategy] === :user
        @test any(contains.(system.metadata[:slicing_equations], "x - 1"))

        hinted = ApproxSolution(P, [sqrt(big(2))];
                                precision_bits=256,
                                relative_tolerance="1e-12",
                                gap_threshold="1e4",
                                slicing_hints=(equations=slice,))
        hinted_system = build_incidence_system(P, hinted, hinted.rank_profile)
        @test hinted_system.metadata[:slicing_strategy] === :user
        @test any(contains.(hinted_system.metadata[:slicing_equations], "x - 1"))
    end

    @testset "rational slicing respects denominator cap" begin
        P = algebraic_robustness_problem()
        approx = algebraic_robustness_approx(P)
        system = build_incidence_system(P, approx, approx.rank_profile;
                                        slicing=:rational_rounding,
                                        slicing_max_denominator=10)
        @test system.metadata[:slicing_strategy] === :rational_rounding
        @test isempty(system.metadata[:slicing_equations])
    end

    @testset "rational slicing removes a positive-dimensional free coordinate" begin
        if !has_msolve()
            @test_skip "msolve binary is not installed"
        else
            P = free_slice_problem()
            approx = ApproxSolution(P, [0];
                                    precision_bits=256,
                                    relative_tolerance="1e-12",
                                    gap_threshold="1e4")

            unsliced = certify(P, approx;
                               slicing=:none,
                               msolve_timeout_seconds=10,
                               verify_io=nothing)
            @test unsliced isa FailureResult
            @test unsliced.failure isa PositiveDimensionalFailure
            @test unsliced.failure.reason === :msolve_positive_dimensional
            @test haskey(unsliced.failure.diagnostics, :attempt_summary)

            sliced = certify(P, approx;
                             slicing=:rational_rounding,
                             slicing_max_denominator=1,
                             msolve_timeout_seconds=10,
                             verify_io=nothing)
            @test sliced isa CertifiedResult
            @test iscertified(sliced)
            @test verify(sliced; io=nothing)
            @test sliced.root.f == parse_polynomial("t - 1")
            @test sliced.solution[1] == AlgebraicElement(sliced.root, 0)
        end
    end

    @testset "three non-sqrt algebraic cubic examples certify" begin
        if !has_msolve()
            @test_skip "msolve binary is not installed"
        else
            for case in cubic_cases
                P = LMIProblem(case.A0, [case.A1]; vars=[:x])
                approx = ApproxSolution(P, [case.approx];
                                        precision_bits=256,
                                        relative_tolerance="1e-12",
                                        gap_threshold="1e4")
                result = certify(P, approx;
                                 slicing=:none,
                                 msolve_precision=128,
                                 msolve_threads=1,
                                 msolve_timeout_seconds=30,
                                 verify_io=nothing)
                @test result isa CertifiedResult
                @test iscertified(result)
                @test verify(result; io=nothing)
                @test result.root.f ==
                      AlgebraicRoot(parse_polynomial(case.minimal),
                                    result.root.interval).f
                @test result.psd_proof.method === :schur_zero
            end
        end
    end

    @testset "paper-inspired incidence systems succeed or fail usefully" begin
        if !has_msolve()
            @test_skip "msolve binary is not installed"
        else
            isolated = cubic_cases[1]
            P = LMIProblem(isolated.A0, [isolated.A1]; vars=[:x])
            approx = ApproxSolution(P, [isolated.approx];
                                    precision_bits=256,
                                    relative_tolerance="1e-12",
                                    gap_threshold="1e4")
            system = build_incidence_system(P, approx, approx.rank_profile;
                                            slicing=:none)
            @test system.metadata[:kind] === :incidence_system
            @test system.metadata[:rank] == 2
            @test system.metadata[:kernel_dimension] == 1
            result = certify(P, approx;
                             slicing=:none,
                             msolve_timeout_seconds=30,
                             verify_io=nothing)
            @test result isa CertifiedResult

            positive_dimensional = free_slice_problem()
            free_approx = ApproxSolution(positive_dimensional, [0];
                                         precision_bits=256,
                                         relative_tolerance="1e-12",
                                         gap_threshold="1e4")
            useful = certify(positive_dimensional, free_approx;
                             slicing=:none,
                             msolve_timeout_seconds=10,
                             verify_io=nothing)
            @test useful isa FailureResult
            @test useful.failure.reason === :msolve_positive_dimensional
            @test useful.failure.stage === :msolve
            @test useful.failure.diagnostics[:status] === :positive_dimensional
            @test haskey(useful.failure.diagnostics, :attempts)
        end
    end

    @testset "positive-dimensional parser and oversize cases fail structurally" begin
        parsed = parse_msolve_output("[1, 1, -1, []]:")
        @test parsed.status === :positive_dimensional

        P = free_slice_problem()
        approx = ApproxSolution(P, [0];
                                precision_bits=256,
                                relative_tolerance="1e-12",
                                gap_threshold="1e4")
        too_large = certify(P, approx;
                            msolve_binary="/definitely/not/msolve",
                            max_system_variables=1,
                            max_system_equations=1,
                            max_degree_estimate=1,
                            memory_hint_mb=1,
                            verify_io=nothing)
        @test too_large isa FailureResult
        @test too_large.failure isa SystemTooLargeFailure
        @test too_large.failure.reason === :system_too_large
        @test too_large.failure.stage === :incidence
        @test haskey(too_large.failure.diagnostics, :memory_estimate_mb)
        @test haskey(too_large.failure.diagnostics, :degree_estimate)
        @test haskey(too_large.failure.diagnostics, :attempt_summary)
    end

    @testset "rank/profile retry and diagnostics are exposed" begin
        if !has_msolve()
            @test_skip "msolve binary is not installed"
            return
        end

        P = free_slice_problem()
        approx = ApproxSolution(P, [0];
                                precision_bits=256,
                                relative_tolerance="1e-12",
                                gap_threshold="1e4")
        failure = certify(P, approx;
                          rank_retry=true,
                          max_rank_retries=1,
                          slicing=:none,
                          msolve_timeout_seconds=10,
                          verify_io=nothing)
        @test failure isa FailureResult
        @test haskey(failure.diagnostics, :attempts)
        @test haskey(failure.diagnostics, :attempt_summary)
        @test any(entry[:profile_index] > 1
                  for entry in failure.diagnostics[:attempt_summary])
    end
end
