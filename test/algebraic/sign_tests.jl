@testset "Algebraic sign tests" begin
    @testset "sqrt(2) signs" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")

        positive = algebraic_sign(alpha - 1)
        @test positive.status === :positive
        @test certified_sign(alpha - 1) === :positive
        @test positive.interval !== nothing

        zero = algebraic_sign(alpha^2 - 2)
        @test zero.status === :zero
        @test occursin("numerator is zero", zero.reason)
        @test certified_sign(alpha^2 - 2) === :zero

        negative = algebraic_sign(1 - alpha)
        @test negative.status === :negative
        @test certified_sign(1 - alpha) === :negative
    end

    @testset "rational functions and denominator zero" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")

        @test certified_sign(AlgebraicElement(root, "t - 1", "t + 1")) === :positive
        @test certified_sign(AlgebraicElement(root, "1 - t", "t + 1")) === :negative
        @test certified_sign(AlgebraicElement(root, "0", "t^2 - 3*t + 2");
                             max_refinements=0) === :zero

        reducible_root = AlgebraicRoot("t^4 - 5*t^2 + 6", "1", "3/2")
        @test_throws ArgumentError algebraic_sign(AlgebraicElement(reducible_root, "1",
                                                                   "t^2 - 2"))
        @test_throws ArgumentError algebraic_sign(AlgebraicElement(reducible_root, "0",
                                                                   "t^2 - 2"))
    end

    @testset "Sturm root-count shortcut avoids interval dependency blow-up" begin
        root = AlgebraicRoot("t^3 - 2", "1", "2")
        element = AlgebraicElement(root, "1", "t^2 - 3*t + 91/40")

        sign = algebraic_sign(element; max_refinements=0)
        @test sign.status === :positive
        @test certified_sign(element; max_refinements=0) === :positive
    end

    @testset "explicit failure is not accepted silently" begin
        bad_root = AlgebraicRoot("t^2 - 2", "-2", "2")
        result = algebraic_sign(AlgebraicElement(bad_root, "t + 3"))

        @test result.status === :failed
        @test occursin("isolate exactly one real root", result.reason)
        @test_throws ArgumentError certified_sign(AlgebraicElement(bad_root, "t + 3"))

        boundary_root = AlgebraicRoot("t^2 - 2", "1", "2")
        boundary_failure = algebraic_sign(AlgebraicElement(boundary_root, "t - 3/2");
                                          max_refinements=0)
        @test boundary_failure.status === :failed
        @test_throws ArgumentError certified_sign(AlgebraicElement(boundary_root,
                                                                   "t - 3/2");
                                                  max_refinements=0)
    end
end
