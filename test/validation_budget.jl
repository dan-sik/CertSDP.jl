@testset "Validation budget" begin
    repo_root = normpath(joinpath(@__DIR__, ".."))
    suite_root = joinpath(repo_root, "benchmarks")

    @testset "single validation budget gates internal levels and memory expectations" begin
        @test normalize_capability_tier("tier0") === :tier0
        @test normalize_capability_tier("tier1.5") === :tier1_5
        @test capability_tier_index(:tier3) == 4
        @test resource_profile(:validation).max_tier === :tier2
        @test resource_profile_allows(:validation, :tier1; memory_expectation_mb=512)
        @test resource_profile_allows(:validation, :tier2; memory_expectation_mb=512)
        @test !resource_profile_allows(:validation, :tier3; memory_expectation_mb=512)
        @test resource_profile_allows(:validation, :tier1; memory_expectation_mb=64_000)
        @test !resource_profile_allows(:validation, :tier1; memory_expectation_mb=64_001)
        budget = validation_budget(:validation; timeout_seconds=30)
        @test validation_budget_label(budget) == "validation"
        @test validation_timeout_policy(budget).timeout_seconds == 30
    end

    @testset "all benchmark metadata fits validation budget" begin
        cases = benchmark_cases(suite_root; subset=:all, profile=:validation)
        @test length(cases) >= 18
        for case in cases
            @test case.expected.tier in (:tier0, :tier1, :tier1_5, :tier2, :tier3)
            @test case.expected.expected_runtime_seconds > 0
            @test case.expected.memory_expectation_mb >= 0
            @test !isempty(case.expected.backend_requirement)
        end
        @test all(capability_tier_index(case.expected.tier) <=
                  capability_tier_index(resource_profile(:validation).max_tier)
                  for case in cases)
        @test all(case.expected.memory_expectation_mb <=
                  resource_profile(:validation).memory_limit_mb for case in cases)
    end

    @testset "validation guard does not select oversized fixtures" begin
        temp_root = mktempdir()
        source_case = joinpath(suite_root, "validation", "rational_pd_2x2")
        oversized_case = joinpath(temp_root, "oversized_fixture")
        cp(source_case, oversized_case)
        expected_path = joinpath(oversized_case, "expected.json")
        text = read(expected_path, String)
        text = replace(text,
                       "\"memory_expectation_mb\": 256" => "\"memory_expectation_mb\": 64001")
        write(expected_path, text)

        @test isempty(benchmark_cases(temp_root; subset=:all, profile=:validation))
    end

    @testset "certify accepts validation budget scaffold" begin
        P = read_problem(joinpath(repo_root, "examples", "algebraic_problem.json"))
        approx = CertSDP._read_cli_solution_file(P,
                                                 joinpath(repo_root,
                                                          "examples",
                                                          "algebraic_approx.json"))
        result = certify(P, approx;
                         resource_profile=:validation,
                         max_system_variables=1,
                         verify_io=nothing)
        @test result isa FailureResult
        @test result.failure.reason === :system_too_large
        @test result.failure.stage === :incidence
    end

    @testset "validation timeout returns structured diagnostics" begin
        P = read_problem(joinpath(repo_root, "examples", "algebraic_problem.json"))
        approx = CertSDP._read_cli_solution_file(P,
                                                 joinpath(repo_root,
                                                          "examples",
                                                          "algebraic_approx.json"))
        result = certify(P, approx;
                         resource_profile=:validation,
                         budget=(timeout_seconds=1.0e-9,),
                         verify_io=nothing)
        @test result isa FailureResult
        @test result.failure isa BackendTimeoutFailure
        @test result.failure.reason === :validation_timeout
        @test haskey(result.failure.diagnostics, :timeout_seconds)
        @test get(result.failure.diagnostics, :graceful_diagnostic, false) === true
    end
end
