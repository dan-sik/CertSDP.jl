using JuMP
import MathOptInterface as MOI

@testset "JuMP/MOI LMI extraction" begin
    function assert_error_contains(f, needle::AbstractString)
        try
            f()
            error("expected an ArgumentError")
        catch err
            @test err isa ArgumentError
            @test occursin(needle, sprint(showerror, err))
        end
    end

    @testset "JuMP square affine PSD constraint extracts to one LMI" begin
        model = GenericModel{Rational{BigInt}}()
        @variable(model, x)
        @variable(model, y)
        @constraint(model, psd_square, [1+x y; y 2-x] in PSDCone())

        problem = extract_lmi(model)

        @test problem isa LMIProblem
        @test variable_symbols(problem) == [:x1, :x2]
        @test rational_matrix(problem.A0) == Rational{BigInt}[1 0; 0 2]
        @test rational_matrix(problem.A[1]) == Rational{BigInt}[1 0; 0 -1]
        @test rational_matrix(problem.A[2]) == Rational{BigInt}[0 1; 1 0]
        @test verify(RationalCertificate(problem, [0, 0]))
        @test diagnose(RationalCertificate(problem, [0, 0])).status == "verified"
    end

    @testset "JuMP triangle PSD constraint preserves variable mapping metadata" begin
        model = GenericModel{Rational{BigInt}}()
        @variable(model, a)
        @variable(model, b)
        @constraint(model, tri,
                    [1 + a, b, 3 - a] in
                    MOI.PositiveSemidefiniteConeTriangle(2))
        @constraint(model, tri2,
                    [2 - b, 0, 1 + a] in
                    MOI.PositiveSemidefiniteConeTriangle(2))

        problem = extract_lmi(model)

        @test problem isa BlockLMIProblem
        @test num_blocks(problem) == 2
        @test variable_symbols(problem) == [:x1, :x2]
        @test problem.metadata[:source_format] == "jump_moi"
        @test problem.metadata[:source] == "JuMP.Model"
        @test problem.metadata[:bridge_provenance][:frontend] == "JuMP"
        @test problem.metadata[:variables][1][:jump_name] == "a"
        @test problem.metadata[:variables][1][:certsdp_variable] == "x1"
        @test problem.metadata[:variables][2][:jump_name] == "b"
        @test length(problem.metadata[:constraints]) == 2
        @test problem.metadata[:constraints][1][:name] == "tri"

        first_block = problem.blocks[1]
        @test rational_matrix(first_block.A0) == Rational{BigInt}[1 0; 0 3]
        @test rational_matrix(first_block.A[1]) == Rational{BigInt}[1 0; 0 -1]
        @test rational_matrix(first_block.A[2]) == Rational{BigInt}[0 1; 1 0]
        @test all(verify_psd_rational(matrix) for matrix in substitute(problem, [0, 0]))
    end

    @testset "JuMP PSD variable constraint extracts as affine LMI" begin
        model = GenericModel{Rational{BigInt}}()
        @variable(model, X[1:2, 1:2], PSD)

        problem = extract_lmi(model)

        @test problem isa LMIProblem
        @test variable_symbols(problem) == [:x1, :x2, :x3]
        @test rational_matrix(problem.A0) == zeros(Rational{BigInt}, 2, 2)
        @test rational_matrix(problem.A[1]) == Rational{BigInt}[1 0; 0 0]
        @test rational_matrix(problem.A[2]) == Rational{BigInt}[0 1; 1 0]
        @test rational_matrix(problem.A[3]) == Rational{BigInt}[0 0; 0 1]
        @test verify(RationalCertificate(problem, [1, 0, 1]))
    end

    @testset "MOI VectorAffineFunction PSD extraction" begin
        model = MOI.Utilities.Model{Rational{BigInt}}()
        x = MOI.add_variable(model)
        y = MOI.add_variable(model)
        MOI.set(model, MOI.VariableName(), x, "x")
        MOI.set(model, MOI.VariableName(), y, "y")
        terms = MOI.VectorAffineTerm{Rational{BigInt}}[MOI.VectorAffineTerm(1,
                                                                            MOI.ScalarAffineTerm(1 //
                                                                                                 1,
                                                                                                 x)),
                                                       MOI.VectorAffineTerm(2,
                                                                            MOI.ScalarAffineTerm(1 //
                                                                                                 1,
                                                                                                 y)),
                                                       MOI.VectorAffineTerm(3,
                                                                            MOI.ScalarAffineTerm(-1 //
                                                                                                 1,
                                                                                                 x))]
        func = MOI.VectorAffineFunction(terms, Rational{BigInt}[1, 0, 2])
        MOI.add_constraint(model, func, MOI.PositiveSemidefiniteConeTriangle(2))

        problem = extract_moi_lmi(model)

        @test problem isa LMIProblem
        @test variable_symbols(problem) == [:x1, :x2]
        @test rational_matrix(problem.A0) == Rational{BigInt}[1 0; 0 2]
        @test rational_matrix(problem.A[1]) == Rational{BigInt}[1 0; 0 -1]
        @test rational_matrix(problem.A[2]) == Rational{BigInt}[0 1; 1 0]
        @test verify(RationalCertificate(problem, [0, 0]))
    end

    @testset "unsupported models fail loudly" begin
        assert_error_contains("nonlinear/bilinear JuMP PSD constraint") do
            model = GenericModel{Rational{BigInt}}()
            @variable(model, x)
            @variable(model, y)
            @constraint(model, [x * y, 0, 1] in
                               MOI.PositiveSemidefiniteConeTriangle(2))
            return extract_lmi(model)
        end

        assert_error_contains("nonlinear constraints") do
            model = Model()
            @variable(model, x)
            @NLconstraint(model, sin(x) <= 1)
            return extract_lmi(model)
        end

        assert_error_contains("unsupported JuMP constraint type") do
            model = GenericModel{Rational{BigInt}}()
            @variable(model, x)
            @constraint(model, x == 1)
            return extract_lmi(model)
        end

        assert_error_contains("asymmetric square PSD constraint") do
            model = GenericModel{Rational{BigInt}}()
            @variable(model, x)
            @constraint(model, [1 x; 0 1] in PSDCone())
            return extract_lmi(model)
        end

        assert_error_contains("unsupported MOI constraint type") do
            model = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Rational{BigInt}}())
            x = MOI.add_variable(model)
            MOI.add_constraint(model, x, MOI.EqualTo(1 // 1))
            return extract_moi_lmi(model)
        end
    end
end
