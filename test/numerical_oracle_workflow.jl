@testset "Numerical oracle / max-rank workflow" begin
    function rank_gap_problem(epsilon)
        return LMIProblem([0 0 0
                           0 epsilon 0
                           0 0 1],
                          [[1 0 0
                            0 -1 0
                            0 0 0]];
                          vars=[:x])
    end

    @testset "two fixtures need random objective for the better rank profile" begin
        fixtures = [(epsilon=1 // 1_000_000, tolerance="6e-7"),
                    (epsilon=1 // 1_000, tolerance="6e-4")]

        for fixture in fixtures
            P = rank_gap_problem(fixture.epsilon)
            feasibility = solve_approximately(P;
                                              trace_objective=false,
                                              random_objective_trials=0,
                                              precision=256,
                                              relative_tolerance=fixture.tolerance,
                                              gap_threshold="1e4")
            randomized = solve_approximately(P;
                                             trace_objective=false,
                                             random_objective_trials=1,
                                             random_seed=1,
                                             precision=256,
                                             relative_tolerance=fixture.tolerance,
                                             gap_threshold="1e4")

            @test feasibility isa ApproxSolution
            @test randomized isa ApproxSolution
            @test feasibility.rank_estimate == 1
            @test randomized.rank_estimate == 2
            @test randomized.quality_report.objective_kind === :random_linear
            @test randomized.residuals.psd_violation <= parse(BigFloat, "1e-7")
            @test CertSDP.max_rank_workflow_summary(randomized).selected_rank == 2
        end
    end

    @testset "three solve -> diagnose -> certify examples pass" begin
        if !has_msolve()
            @test_skip "msolve binary is not installed"
        else
            examples = [read_problem(joinpath(@__DIR__, "..", "examples",
                                              "algebraic_problem.json")),
                        read_problem(joinpath(@__DIR__, "..", "examples",
                                              "numerical_oracle",
                                              "sqrt2_problem.json")),
                        read_problem(joinpath(@__DIR__, "..", "benchmarks", "validation",
                                              "workflow_solve_certify_sqrt2_random_objective",
                                              "problem.json"))]

            for P in examples
                approx = solve_approximately(P;
                                             random_objective_trials=2,
                                             trace_objective=:maximize,
                                             solver_attempts=1,
                                             random_seed=3,
                                             precision=256,
                                             relative_tolerance="1e-8",
                                             gap_threshold="1e4")
                @test approx isa ApproxSolution
                @test diagnose(approx).status == "ok"
                @test diagnose(approx).face_clarity in ("full_rank", "clear", "usable",
                                                        "ambiguous")

                result = certify(P, approx;
                                 msolve_precision=128,
                                 msolve_timeout_seconds=30,
                                 verify_io=nothing)
                @test result isa CertifiedResult
                @test verify(result; io=nothing)
            end
        end
    end

    @testset "uncertifiable solver output explains why" begin
        P = LMIProblem([-1 0; 0 1],
                       [[0 0; 0 0]];
                       vars=[:x])
        bad = ApproxSolution(P, [0];
                             precision_bits=256,
                             solver_name=:clarabel,
                             solver_status=:solved)

        result = certify(P, bad; max_psd_violation="1e-8")

        @test result isa FailureResult
        @test result.failure isa NumericalFailure
        @test result.reason === :approximation_psd_violation_too_large
        @test occursin("not numerically PSD", result.message)
        @test diagnose(result).suggestions[1] ==
              "provide a higher precision approximate solution"
    end
end
