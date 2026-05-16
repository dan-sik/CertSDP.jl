@testset "Rational PSD verifier" begin
    @testset "positive definite matrices are accepted" begin
        A = SymmetricRationalMatrix([2//1 1//2 0//1
                                     1//2 3//1 1//3
                                     0//1 1//3 4//1])

        @test verify_psd_rational(A)
        @test verify_psd_rational(rational_matrix(A))
    end

    @testset "rank-deficient PSD matrices are accepted" begin
        A = SymmetricRationalMatrix([1 2 0
                                     2 4 0
                                     0 0 0])

        @test verify_psd_rational(A)
    end

    @testset "indefinite matrices are rejected" begin
        A = SymmetricRationalMatrix([1 2
                                     2 1])

        @test !verify_psd_rational(A)
    end

    @testset "zero matrix is accepted" begin
        A = SymmetricRationalMatrix(zeros(Int, 4, 4))

        @test verify_psd_rational(A)
    end

    @testset "invalid rational PSD inputs are rejected" begin
        @test_throws ArgumentError verify_psd_rational([1 2; 3 4])
        @test_throws ArgumentError verify_psd_rational([1.0 0.0; 0.0 1.0])
        @test_throws DimensionMismatch verify_psd_rational(reshape(1:6, 2, 3))
        @test_throws ArgumentError verify_psd_rational([i == j ? 1 : 0
                                                        for i in 1:9, j in 1:9])
    end

    @testset "principal-minor planner positives" begin
        matrices = [[2//1 1//1; 1//1 2//1],
                    [1//1 2//1 0//1; 2//1 4//1 0//1; 0//1 0//1 0//1],
                    [0//1 0//1; 0//1 0//1]]

        for A in matrices
            plan = choose_psd_proof(A; method=:principal_minors)
            @test plan.status === :accepted
            @test plan.method === :principal_minors
            @test plan.failure === nothing
        end
    end

    @testset "principal-minor planner negatives localize minors" begin
        cases = [([1//1 2//1; 2//1 1//1], [1, 2]),
                 ([-1//1 0//1; 0//1 1//1], [1]),
                 ([1//1 0//1 0//1; 0//1 1//1 2//1; 0//1 2//1 1//1], [2, 3])]

        for (A, expected_indices) in cases
            plan = choose_psd_proof(A; method=:principal_minors)
            @test plan.status === :rejected
            @test plan.failure.location === :minor
            @test plan.failure.indices == expected_indices
        end
    end

    @testset "Schur-zero rational positives" begin
        matrices = [([1//1 0//1; 0//1 0//1], [1]),
                    ([2//1 1//1 2//1; 1//1 2//1 1//1; 2//1 1//1 2//1], [1, 2]),
                    ([3//1 0//1 3//1; 0//1 2//1 0//1; 3//1 0//1 3//1], [1, 2])]

        for (A, pivots) in matrices
            plan = choose_psd_proof(A; method=:schur_zero, pivot_block=pivots)
            @test plan.status === :accepted
            @test plan.schur_zero.pivot_block == pivots
            @test verify_psd_schur_zero(A, pivots)
        end
    end

    @testset "Schur-zero rational negatives localize block proof" begin
        cases = [([0//1 0//1; 0//1 1//1], [1], :positive_block_minor),
                 ([1//1 1//1; 1//1 2//1], [1], :schur_complement),
                 ([1//1 0//1 1//1; 0//1 -1//1 0//1; 1//1 0//1 1//1], [1, 2],
                  :positive_block_minor)]

        for (A, pivots, location) in cases
            plan = choose_psd_proof(A; method=:schur_zero, pivot_block=pivots)
            @test plan.status === :rejected
            @test plan.failure.location === location
        end
    end

    @testset "LDL positives" begin
        matrices = [[2//1 1//1; 1//1 2//1],
                    [1//1 0//1; 0//1 0//1],
                    [4//1 2//1 0//1; 2//1 1//1 0//1; 0//1 0//1 3//1]]

        for A in matrices
            plan = choose_psd_proof(A; method=:ldl)
            @test plan.status === :accepted
            @test plan.method === :ldl
            @test verify_psd_ldl(A)
        end
    end

    @testset "pivoted LDL handles zero leading diagonal order" begin
        A = [0//1 0//1 0//1; 0//1 2//1 1//1; 0//1 1//1 2//1]
        plan = choose_psd_proof(A; method=:pivoted_ldl)

        @test plan.status === :accepted
        @test plan.method === :pivoted_ldl
        @test first(plan.ldl.pivots).index == 2
        @test verify_psd_pivoted_ldl(A)
    end

    @testset "LDL negatives localize pivots" begin
        cases = [([-1//1 0//1; 0//1 1//1], :pivot),
                 ([1//1 2//1; 2//1 1//1], :pivot),
                 ([0//1 1//1; 1//1 0//1], :pivot_row)]

        for (A, location) in cases
            plan = choose_psd_proof(A; method=:ldl)
            @test plan.status === :rejected
            @test plan.failure.location === location
            @test plan.failure.pivot_index !== nothing
        end

        pivoted = choose_psd_proof([0//1 1//1; 1//1 1//1]; method=:pivoted_ldl)
        @test pivoted.status === :rejected
        @test pivoted.failure.location === :pivot
    end

    @testset "blockwise PSD positives and negatives" begin
        positive_blocks = Any[[1//1 0//1; 0//1 0//1],
                              [2//1 1//1; 1//1 2//1],
                              [3//1 0//1; 0//1 4//1]]
        plan = choose_psd_proof(positive_blocks; method=:blockwise,
                                block_method=:principal_minors)
        @test plan.status === :accepted
        @test length(plan.block_plans) == 3
        @test verify_psd_blockwise(positive_blocks; method=:principal_minors)

        negative_sets = [Any[[1//1 0//1; 0//1 1//1], [1//1 2//1; 2//1 1//1]],
                         Any[[1//1 0//1; 0//1 1//1], [-1//1 0//1; 0//1 1//1]],
                         Any[[1//1 0//1; 0//1 1//1], [1//1 0//1; 0//1 1//1],
                             [0//1 1//1; 1//1 0//1]]]
        expected_blocks = [2, 2, 3]

        for (blocks, expected_block) in zip(negative_sets, expected_blocks)
            rejected = choose_psd_proof(blocks; method=:blockwise,
                                        block_method=:principal_minors)
            @test rejected.status === :rejected
            @test rejected.failure.block_index == expected_block
            @test rejected.failure.location === :minor
        end
    end
end
