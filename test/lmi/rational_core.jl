@testset "Exact rational LMI core" begin
    @testset "legal LMI" begin
        A0 = SymmetricRationalMatrix([1//2 0; 0 2])
        A1 = SymmetricRationalMatrix([0 1//3; 1//3 0])
        A2 = SymmetricRationalMatrix([1 0; 0 -1//4])

        P = LMIProblem(A0, [A1, A2]; vars=[:u, :v])

        @test matrix_size(P) == 2
        @test num_variables(P) == 2
        @test P.vars == [:u, :v]
        @test rational_matrix(P.A0) == Rational{BigInt}[1//2 0//1; 0//1 2//1]
    end

    @testset "non-symmetric matrices are rejected" begin
        @test_throws ArgumentError SymmetricRationalMatrix([1 2; 3 4])
        @test_throws ArgumentError LMIProblem([1 0; 0 1], [[0 1; 2 0]])
    end

    @testset "dimension mismatches are rejected" begin
        @test_throws DimensionMismatch LMIProblem([1 0; 0 1], [[1 0 0; 0 1 0; 0 0 1]])
        @test_throws ArgumentError LMIProblem([1 0; 0 1], [[1 0; 0 1]]; vars=[:x, :y])
    end

    @testset "exact rational substitution" begin
        A0 = [1//2 0; 0 1//3]
        A1 = [2 1//5; 1//5 0]
        A2 = [0 -3//7; -3//7 4]
        P = LMIProblem(A0, [A1, A2])

        evaluated = substitute(P, [3 // 2, -2 // 3])

        expected = Rational{BigInt}[7//2 41//70
                                    41//70 -7//3]
        @test evaluated isa SymmetricRationalMatrix
        @test rational_matrix(evaluated) == expected

        @test_throws DimensionMismatch substitute(P, [1 // 1])
    end
end
