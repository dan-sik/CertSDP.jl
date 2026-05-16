@testset "Algebraic root and element core" begin
    @testset "polynomial parsing and remainders" begin
        f = parse_polynomial("t^2 - 2")
        multiple = parse_polynomial("t^3 - 2*t")

        @test f == UnivariatePolynomial([-2, 0, 1])
        @test string(f) == "t^2 - 2"
        @test parse_polynomial(string(f)) == f
        @test iszero(polynomial_remainder(multiple, f))
        @test polynomial_remainder(parse_polynomial("t^3 + t + 1"), f) ==
              parse_polynomial("3*t + 1")
        @test parse_rational_function("(t^2 + 1)/(t - 1)") ==
              (parse_polynomial("t^2 + 1"), parse_polynomial("t - 1"))
        @test parse_rational_function("1/2*t + 3") ==
              (parse_polynomial("1/2*t + 3"), UnivariatePolynomial(1))
    end

    @testset "sqrt(2) toy root" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")

        @test root.f == parse_polynomial("t^2 - 2")
        @test root.interval == RationalInterval(1, 3 // 2)
        @test string(root) == "AlgebraicRoot(t^2 - 2, [1, 3/2])"
        @test occursin("AlgebraicElement(t; root=AlgebraicRoot(t^2 - 2", string(alpha))

        @test alpha * alpha == AlgebraicElement(root, "2")
        @test alpha == AlgebraicElement(root, "2/t")
        @test AlgebraicElement(root, "(t^2 + t)/(t)") == alpha + 1
        @test alpha != -alpha
        @test iszero(alpha^2 - 2)

        zero = AlgebraicElement(root, "0", "t + 1")
        @test iszero(zero)
        @test zero.denominator == UnivariatePolynomial(1)
        @test alpha + zero == alpha
    end

    @testset "cubic toy root" begin
        root = parse_algebraic_root("t^3 - t - 1", ("1", "3/2"))
        beta = parse_algebraic_element(root, "t")

        @test beta^3 == beta + 1
        @test AlgebraicElement(root, "t^4") == AlgebraicElement(root, "t^2 + t")
        @test AlgebraicElement(root, "(t^3 + t)/(t + 1)") ==
              AlgebraicElement(root, "(2*t + 1)/(t + 1)")
        @test beta != AlgebraicElement(root, "t + 1")
    end

    @testset "root polynomial normalization removes repeated factors" begin
        root = AlgebraicRoot("t^4 - 4*t^2 + 4", "1", "3/2")
        alpha = AlgebraicElement(root, "t")

        @test root.f == parse_polynomial("t^2 - 2")
        @test alpha^2 == AlgebraicElement(root, "2")
    end

    @testset "invalid algebraic data is rejected" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")

        @test_throws ArgumentError AlgebraicRoot("2", "0", "1")
        @test_throws ArgumentError AlgebraicRoot("t^2 - 2", "2", "1")
        @test_throws ArgumentError AlgebraicElement(root, "1/(t^2 - 2)")
        @test_throws ArgumentError parse_polynomial("t^-1")
        @test_throws ArgumentError parse_polynomial("(t + 1)*(t + 1)")
    end
end
