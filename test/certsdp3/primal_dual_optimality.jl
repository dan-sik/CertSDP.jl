@testset "Gate G primal-dual optimality" begin
    matrix = K3.SparseSymmetricRationalMatrix(50,
        [(i, i, 1//1) for i in 1:50])
    factor = [[i == j ? 1//1 : 0//1 for j in 1:50] for i in 1:50]
    proof = K3.ExactLowRankPSDProof(matrix, factor, fill(1//1, 50))
    primal = K3.PrimalFeasibilityCertificate(matrix.hash,
                                             fill(1//1, 50),
                                             fill(1//1, 50),
                                             [matrix],
                                             [proof],
                                             7//1)
    dual = K3.DualFeasibilityCertificate(matrix.hash,
                                         fill(2//1, 50),
                                         fill(2//1, 50),
                                         [matrix],
                                         [proof],
                                         7//1)
    cert = K3.make_primal_dual_optimality_certificate(matrix.hash, primal, dual)
    report = K3.verify_primal_dual_optimality(cert)
    @test !report.accepted
    @test report.stage == :primal_dual_affine_map

    bad_gap = K3.PrimalDualOptimalityCertificate(cert.problem_hash,
                                                 cert.primal,
                                                 cert.dual,
                                                 1//1,
                                                 cert.certificate_hash,
                                                 cert.dag)
    gap_report = K3.verify_primal_dual_optimality(bad_gap)
    @test !gap_report.accepted
    @test gap_report.stage == :hash

    bad_dual = K3.DualFeasibilityCertificate(matrix.hash,
                                             fill(2//1, 50),
                                             fill(3//1, 50),
                                             [matrix],
                                             [proof],
                                             7//1)
    bad_cert = K3.make_primal_dual_optimality_certificate(matrix.hash,
                                                         primal,
                                                         bad_dual)
    bad_report = K3.verify_primal_dual_optimality(bad_cert)
    @test !bad_report.accepted
    @test bad_report.stage == :primal_dual_affine_map
end
