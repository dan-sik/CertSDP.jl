@testset "Gate H sparse SOS certificate" begin
    vars = [:x1, :x2, :x3, :x4]
    terms = [K3.PolynomialTerm([2, 0, 0, 0], 1//1),
             K3.PolynomialTerm([0, 2, 0, 0], 1//1)]
    problem = K3.SparseSOSProblem(vars, terms, [[:x1, :x2], [:x3, :x4]], 0//1)

    matrix = K3.SparseSymmetricRationalMatrix(2, [(1, 1, 1//1), (2, 2, 1//1)])
    proof = K3.ExactLowRankPSDProof(matrix, [[1//1, 0//1], [0//1, 1//1]],
                                    [1//1, 1//1])
    block = K3.SparseSOSBlock(:gram_1, :clique_1,
                              [[1, 0, 0, 0], [0, 1, 0, 0]],
                              matrix,
                              proof,
                              terms)
    cert = K3.make_sparse_sos_certificate(problem, [block])
    report = K3.verify_sparse_sos_certificate(cert)
    @test report.accepted

    tampered_block = K3.SparseSOSBlock(:gram_1, :clique_1,
                                       block.basis_exponents,
                                       matrix,
                                       proof,
                                       [K3.PolynomialTerm([2, 0, 0, 0], 2//1)])
    bad = K3.make_sparse_sos_certificate(problem, [tampered_block])
    bad_report = K3.verify_sparse_sos_certificate(bad)
    @test !bad_report.accepted
    @test bad_report.stage == :coefficient_matching
end
