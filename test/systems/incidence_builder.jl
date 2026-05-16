@testset "Incidence system builder" begin
    @testset "toy rank-deficient LMI produces A(x)Y=0 with gauge fixing" begin
        P = LMIProblem([0 0 0
                        0 0 0
                        0 0 0],
                       [[1 0 0
                         0 0 0
                         0 0 0]];
                       vars=[:x],)
        approx = ApproxSolution(P, [2]; precision_bits=256)
        system = build_incidence_system(P, approx, approx.rank_profile)

        @test approx.rank_profile.rank == 1
        @test variable_symbols(system) == [:x,
                                           :Y_1_1,
                                           :Y_2_1,
                                           :Y_3_1,
                                           :Y_1_2,
                                           :Y_2_2,
                                           :Y_3_2]
        @test length(system.equations) == 10

        @test string(system.equations[1]) == "x*Y_1_1"
        @test string(system.equations[2]) == "0"
        @test string(system.equations[3]) == "0"
        @test string(system.equations[4]) == "x*Y_1_2"
        @test string(system.equations[5]) == "0"
        @test string(system.equations[6]) == "0"

        @test string(system.equations[7]) == "Y_2_1 - 1"
        @test string(system.equations[8]) == "Y_3_1"
        @test string(system.equations[9]) == "Y_2_2"
        @test string(system.equations[10]) == "Y_3_2 - 1"

        @test system.metadata[:kind] === :incidence_system
        @test system.metadata[:builder] === :kernel_incidence
        @test system.metadata[:original_lmi_hash] == lmi_problem_hash(P)
        @test system.metadata[:matrix_size] == 3
        @test system.metadata[:num_lmi_variables] == 1
        @test system.metadata[:rank] == 1
        @test system.metadata[:kernel_dimension] == 2
        @test system.metadata[:pivot_cols] == [1]
        @test system.metadata[:pivot_rows] == [1]
        @test system.metadata[:gauge_rows] == [2, 3]
        @test system.metadata[:gauge_strategy] === :complement_of_pivot_cols
        @test system.metadata[:slicing_strategy] === :none
        @test system.metadata[:slicing_equations] == String[]

        blocks = system.metadata[:equation_blocks]
        @test blocks.incidence == (start=1, stop=6, count=6)
        @test blocks.gauge == (start=7, stop=10, count=4)
        @test blocks.slicing == (start=11, stop=10, count=0)

        gauge = system.metadata[:gauge_equations]
        @test gauge[1] == (equation_index=7, row=2, column=1, value="1")
        @test gauge[2] == (equation_index=8, row=3, column=1, value="0")
        @test gauge[3] == (equation_index=9, row=2, column=2, value="0")
        @test gauge[4] == (equation_index=10, row=3, column=2, value="1")

        text = polynomial_system_text(system)
        @test occursin("ring: QQ[x, Y_1_1, Y_2_1, Y_3_1, Y_1_2, Y_2_2, Y_3_2]", text)
        @test occursin("  f7 = Y_2_1 - 1", text)
        @test occursin("  gauge_rows = [2, 3]", text)
    end

    @testset "invalid incidence inputs are rejected" begin
        P = LMIProblem([0 0; 0 0], [[1 0; 0 0]]; vars=[:x])
        approx = ApproxSolution(P, [1]; precision_bits=256)

        full_rank = RankProfile(2,
                                [1, 2],
                                [1, 2],
                                [1, 2],
                                BigFloat(0),
                                BigFloat[1, 1],
                                BigFloat(Inf),
                                :test)

        bad_length = RankProfile(1,
                                 [1, 2],
                                 [1],
                                 [1, 2],
                                 BigFloat(0),
                                 BigFloat[1, 0],
                                 BigFloat(Inf),
                                 :test)

        @test_throws ArgumentError build_incidence_system(P, approx, full_rank)
        @test_throws ArgumentError build_incidence_system(P, approx, bad_length)
        @test_throws ArgumentError build_incidence_system(P, approx, approx.rank_profile;
                                                          gauge_rows=[1, 2])
        @test_throws ArgumentError build_incidence_system(P, approx, approx.rank_profile;
                                                          gauge_rows=[1, 1])
        P_collision = LMIProblem([0 0; 0 0], [[1 0; 0 0]]; vars=[:Y_1_1])
        approx_collision = ApproxSolution(P_collision, [1]; precision_bits=256)
        @test_throws ArgumentError build_incidence_system(P_collision, approx_collision,
                                                          approx_collision.rank_profile)
    end
end
