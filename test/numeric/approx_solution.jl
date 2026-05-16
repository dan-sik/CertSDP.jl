@testset "Approximate solution diagnostics" begin
    @testset "BigFloat LMI evaluation and residuals" begin
        P = LMIProblem([0 0; 0 0],
                       [[1 0; 0 0],
                        [0 0; 0 1]];
                       vars=[:x, :y],)

        approx = ApproxSolution(P, ["1.0", "1e-30"]; precision_bits=256)

        @test approx.problem_hash == lmi_problem_hash(P)
        @test approx.precision_bits == 256
        @test length(approx.xhat) == 2
        @test approx.Xhat[1, 1] == BigFloat(1)
        @test approx.Xhat[2, 2] == parse(BigFloat, "1e-30")
        @test approx.residuals.linear_residual == 0
        @test approx.residuals.symmetry_residual == 0
        @test approx.residuals.psd_violation == 0
        @test approx.rank_profile isa RankProfile
        @test approx.rank_estimate == 1
        @test approx.rank_profile.rank == 1
        @test approx.rank_profile.pivot_cols == [1]
        @test approx.rank_profile.pivot_rows == [1]
        @test approx.quality_report isa ApproxQualityReport
        @test approx.quality_report.solver_name === :user
        @test approx.quality_report.solver_status === :user_supplied
        @test approx.quality_report.rank_confidence === :high
    end

    @testset "provided Xhat residuals are reported" begin
        P = LMIProblem([1 0; 0 1], []; vars=Symbol[])
        tiny = parse(BigFloat, "1e-40")
        Xhat = BigFloat[1 tiny; 0 1]
        approx = ApproxSolution(P, []; precision_bits=256, Xhat=Xhat)

        @test approx.residuals.linear_residual == tiny
        @test approx.residuals.symmetry_residual == tiny
        @test approx.rank_profile isa RankProfile
        @test approx.rank_profile.rank == 2
    end

    @testset "detect_rank_profile accepts clear gaps" begin
        small = parse(BigFloat, "1e-20")
        tiny = parse(BigFloat, "1e-40")
        A = BigFloat[1 0 0
                     0 small 0
                     0 0 tiny]

        profile = detect_rank_profile(A; precision_bits=256, relative_tolerance="1e-30",
                                      gap_threshold="1e6")

        @test profile isa RankProfile
        @test profile.rank == 2
        @test profile.pivot_cols == [1, 2]
        @test profile.pivot_rows == [1, 2]
        @test profile.gap > parse(BigFloat, "1e6")
        @test length(profile.singular_values) == 3
    end

    @testset "detect_rank_profile reports unstable gaps" begin
        small = parse(BigFloat, "1e-20")
        nearby = parse(BigFloat, "1e-21")
        A = BigFloat[1 0 0
                     0 small 0
                     0 0 nearby]

        profile = detect_rank_profile(A; precision_bits=256, relative_tolerance="5e-21",
                                      gap_threshold="1e6")

        @test profile isa UnstableRankProfile
        @test profile.candidate_rank == 2
        @test profile.gap < parse(BigFloat, "1e6")
        @test occursin("gap", profile.reason)
    end

    @testset "solve_approximately wraps user solutions and reports rank stability" begin
        P = LMIProblem([0 0; 0 1],
                       [[1 0; 0 0]];
                       vars=[:x],)

        approx = solve_approximately(P;
                                     solution=["1.0"],
                                     precision=256,
                                     relative_tolerance="1e-12",
                                     gap_threshold="1e4",)

        @test approx isa ApproxSolution
        @test approx.rank_profile isa RankProfile
        @test approx.rank_estimate == 2
        @test approx.quality_report.min_eigenvalue == 1
        @test approx_quality_report_json(approx).status == "ok"
        @test diagnose(approx).rank_confidence in ("high", "medium")

        unstable = solve_approximately(P;
                                       solution=["1e-20"],
                                       precision=256,
                                       relative_tolerance="5e-21",
                                       gap_threshold="1e6",)

        @test unstable isa ApproxSolution
        @test unstable.rank_profile isa UnstableRankProfile
        @test unstable.quality_report.rank_confidence === :unstable
        @test approx_quality_report_json(unstable).status == "rank_unstable"

        failure = solve_approximately(P;
                                      solution=["1e-20"],
                                      precision=256,
                                      relative_tolerance="5e-21",
                                      gap_threshold="1e6",
                                      require_stable_rank=true,)

        @test failure isa CertificationFailure
        @test failure.reason === :rank_profile_unstable
        @test failure.stage === :rank_profile
    end

    @testset "solve_approximately uses Clarabel backend" begin
        P = LMIProblem([0 0; 0 1],
                       [[1 0; 0 0]];
                       vars=[:x],)

        approx = solve_approximately(P;
                                     solvers=[:clarabel],
                                     random_objective_trials=1,
                                     precision=256,
                                     relative_tolerance="1e-10",
                                     gap_threshold="1e4",)

        @test approx isa ApproxSolution
        @test approx.quality_report.solver_name === :clarabel
        @test approx.quality_report.solver_status in (:solved, :almost_solved)
        @test approx.residuals.psd_violation <= parse(BigFloat, "1e-6")
        @test length(approx.xhat) == 1
        @test approx.quality_report.face_clarity in (:full_rank, :clear, :usable,
                                                     :ambiguous, :unstable)
        @test haskey(approx.oracle_metadata, :attempts)
        @test CertSDP.face_search_candidate_score(approx).selection_policy ==
              "max_rank_face_search"
    end

    @testset "Random objectives improve max-rank face search" begin
        for epsilon in (1 // 1_000_000, 1 // 1_000)
            P = LMIProblem([0 0 0
                            0 epsilon 0
                            0 0 1],
                           [[1 0 0
                             0 -1 0
                             0 0 0]];
                           vars=[:x])
            tolerance = epsilon == 1 // 1_000_000 ? "6e-7" : "6e-4"

            feasibility = solve_approximately(P;
                                              random_objective_trials=0,
                                              trace_objective=false,
                                              precision=256,
                                              relative_tolerance=tolerance,
                                              gap_threshold="1e4")
            randomized = solve_approximately(P;
                                             random_objective_trials=1,
                                             trace_objective=false,
                                             random_seed=1,
                                             precision=256,
                                             relative_tolerance=tolerance,
                                             gap_threshold="1e4")

            @test feasibility isa ApproxSolution
            @test randomized isa ApproxSolution
            @test feasibility.rank_estimate == 1
            @test randomized.rank_estimate == 2
            @test randomized.quality_report.objective_kind === :random_linear
            @test CertSDP.face_search_candidate_score(randomized).rank_estimate == 2
            summary = CertSDP.max_rank_workflow_summary(randomized)
            @test summary.selected_objective_kind == "random_linear"
            @test summary.selected_rank == 2
            @test summary.attempt_count >= 3
        end
    end

    @testset "Solver retry failures are structured" begin
        P = LMIProblem([0 0; 0 1],
                       [[1 0; 0 0]];
                       vars=[:x])
        failure = solve_approximately(P; solvers=[:definitely_not_a_solver])

        @test failure isa CertificationFailure
        @test failure isa NumericalFailure
        @test failure.reason === :numerical_solver_failed
        @test haskey(failure.diagnostics, :attempt_log)
        @test !isempty(failure.diagnostics[:attempt_log])
    end

    @testset "JSON xhat input" begin
        P = LMIProblem([0 0; 0 0],
                       [[1 0; 0 0],
                        [0 0; 0 1]];
                       vars=[:x, :y],)
        problem_json = CertSDP._canonical_lmi_problem_json(P)
        hash = lmi_problem_hash(P)
        json = """
        {
            "certsdp_version": "0.1",
            "problem": {
                "type": "$(problem_json.type)",
                "field": "$(problem_json.field)",
                "matrix_size": $(problem_json.matrix_size),
                "num_variables": $(problem_json.num_variables),
                "vars": ["x", "y"],
                "A0": [["0", "0"], ["0", "0"]],
                "A": [
                    [["1", "0"], ["0", "0"]],
                    [["0", "0"], ["0", "1"]]
                ],
                "hash": "$hash"
            },
            "approximate_solution": {
                "type": "xhat",
                "precision_bits": 256,
                "xhat": ["1.0", "1e-30"]
            }
        }
        """

        approx = parse_approx_solution_json(json)

        @test approx isa ApproxSolution
        @test approx.problem_hash == hash
        @test approx.xhat[1] == BigFloat(1)
        @test approx.rank_profile isa RankProfile
        @test approx.rank_profile.rank == 1

        path = tempname() * ".json"
        write(path, json)
        @test read_approx_solution_json(path).rank_estimate == 1

        solve_path = tempname() * ".json"
        solved = solve_approximately(P;
                                     random_objective_trials=1,
                                     trace_objective=false,
                                     random_seed=1,
                                     precision=256,
                                     relative_tolerance="1e-12",
                                     gap_threshold="1e4")
        @test solved isa ApproxSolution
        CertSDP.write_approx_solution_json(solve_path, solved)
        reparsed = CertSDP._read_cli_solution_file(P, solve_path)
        @test reparsed isa ApproxSolution
        @test reparsed.quality_report.objective_kind == solved.quality_report.objective_kind
        @test reparsed.oracle_metadata[:rank_relative_tolerance] == "1e-12"
    end

    @testset "invalid approximate data is rejected" begin
        P = LMIProblem([1 0; 0 1], []; vars=Symbol[])

        @test_throws DimensionMismatch ApproxSolution(P, [1])
        @test_throws ArgumentError detect_rank_profile([1.0 0.0; 0.0 1.0];
                                                       relative_tolerance="0")
        @test_throws ArgumentError parse_approx_solution_json("""
        {
            "certsdp_version": "0.1",
            "problem": {
                "type": "lmi_feasibility",
                "field": "QQ",
                "matrix_size": 1,
                "num_variables": 0,
                "vars": [],
                "A0": [["1"]],
                "A": []
            },
            "approximate_solution": {
                "type": "xhat",
                "precision_bits": 256,
                "xhat": ["not-a-number"]
            }
        }
        """)
    end
end
