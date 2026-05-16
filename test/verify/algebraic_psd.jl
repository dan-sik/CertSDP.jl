@testset "Algebraic PSD verifier" begin
    @testset "sqrt(2) principal-minor PSD check" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        A = [alpha 1
             1 alpha]

        @test verify_psd_algebraic(A)
        @test CertSDP._determinant_algebraic(A) == AlgebraicElement(root, "1")
    end

    @testset "rank-deficient algebraic PSD matrices are accepted" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        A = [alpha 0 0
             0 0 0
             0 0 alpha-1]

        @test verify_psd_algebraic(A)
    end

    @testset "Schur-zero verifies rank-deficient algebraic PSD faster than all minors" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        A = [alpha 0 1
             0 1 alpha-1
             1 alpha-1 3-(3 // 2) * alpha]

        @test verify_psd_schur_zero(A, [1, 2])
        @test !verify_psd_schur_zero(A, [1])

        schur_proof = schur_zero_psd_proof(A, [1, 2])
        fallback_proof = algebraic_psd_proof(A)

        @test schur_proof.method === :schur_zero
        @test schur_proof.schur_zero.pivot_block == [1, 2]
        @test length(schur_proof.schur_zero.positive_block_minors) == 2
        @test length(fallback_proof.principal_minors) == 7
        @test length(schur_proof.schur_zero.positive_block_minors) <
              length(fallback_proof.principal_minors)
        @test CertSDP._iszero_algebraic_matrix(schur_proof.schur_zero.schur_complement)
    end

    @testset "indefinite algebraic matrices are rejected" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        A = [alpha 2
             2 alpha]

        @test !verify_psd_algebraic(A)
        @test !verify_psd_schur_zero([alpha 2; 2 alpha], [1])
    end

    @testset "sign failures and invalid inputs are not silently accepted" begin
        bad_root = AlgebraicRoot("t^2 - 2", "-2", "2")
        alpha = AlgebraicElement(bad_root, "t")

        @test_throws ArgumentError verify_psd_algebraic([alpha 0; 0 1])
        @test_throws ArgumentError verify_psd_schur_zero([alpha 0; 0 1], [1])
        @test_throws ArgumentError verify_psd_algebraic([1 0; 0 1])
        @test_throws ArgumentError verify_psd_algebraic([alpha 1; 0 alpha])
        @test_throws ArgumentError verify_psd_schur_zero([alpha 0; 0 1], [2, 1])
    end

    @testset "algebraic planner supports all exact methods" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")

        principal_positive = [[alpha 0; 0 1],
                              [alpha 1; 1 alpha],
                              [alpha 0 0; 0 0 0; 0 0 alpha-1]]
        for A in principal_positive
            plan = choose_psd_proof(A; method=:principal_minors)
            @test plan.status === :accepted
            @test plan.method === :principal_minors
        end

        schur_positive = [([alpha 0; 0 0], [1]),
                          ([alpha 0 1; 0 1 alpha-1; 1 alpha-1 3-(3 // 2) * alpha],
                           [1, 2]),
                          ([alpha 0 alpha; 0 1 0; alpha 0 alpha], [1, 2])]
        for (A, pivots) in schur_positive
            plan = choose_psd_proof(A; method=:schur_zero, pivot_block=pivots)
            @test plan.status === :accepted
            @test plan.schur_zero.pivot_block == pivots
        end

        ldl_positive = [[alpha 0; 0 1],
                        [alpha 1; 1 alpha],
                        [1 0 0; 0 alpha 0; 0 0 0]]
        for A in ldl_positive
            plan = choose_psd_proof(A; method=:ldl)
            @test plan.status === :accepted
            @test plan.ldl !== nothing
        end

        pivoted = [0 0 0; 0 alpha 1; 0 1 alpha]
        pivoted_plan = choose_psd_proof(pivoted; method=:pivoted_ldl)
        @test pivoted_plan.status === :accepted
        @test pivoted_plan.method === :pivoted_ldl
        @test first(pivoted_plan.ldl.pivots).index == 2
        @test verify_psd_pivoted_ldl(pivoted)
    end

    @testset "Bareiss algebraic determinant handles larger minors" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        A = [alpha 1 0 0
             1 alpha 0 0
             0 0 alpha 0
             0 0 0 alpha+1]

        @test CertSDP._determinant_algebraic(A) ==
              (alpha^2 - 1) * alpha * (alpha + 1)
        @test verify_psd_pivoted_ldl(A)
    end

    @testset "algebraic planner localizes failures" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")

        principal_negative = [([alpha 2; 2 alpha], :minor),
                              ([alpha-2 0; 0 1], :minor),
                              ([1 0 0; 0 alpha 2; 0 2 alpha], :minor)]
        for (A, location) in principal_negative
            plan = choose_psd_proof(A; method=:principal_minors)
            @test plan.status === :rejected
            @test plan.failure.location === location
        end

        schur_negative = [([0 0; 0 alpha], [1], :positive_block_minor),
                          ([1 1; 1 alpha], [1], :schur_complement),
                          ([alpha 0 2; 0 1 0; 2 0 alpha], [1, 2], :schur_complement)]
        for (A, pivots, location) in schur_negative
            plan = choose_psd_proof(A; method=:schur_zero, pivot_block=pivots)
            @test plan.status === :rejected
            @test plan.failure.location === location
        end

        ldl_negative = [([alpha-2 0; 0 1], :pivot),
                        ([alpha 2; 2 alpha], :pivot),
                        ([0 1; 1 alpha], :pivot_row)]
        for (A, location) in ldl_negative
            plan = choose_psd_proof(A; method=:ldl)
            @test plan.status === :rejected
            @test plan.failure.location === location
        end

        pivoted_negative = choose_psd_proof([0 1; 1 alpha]; method=:pivoted_ldl)
        @test pivoted_negative.status === :rejected
        @test pivoted_negative.failure.location === :pivot
    end
end
