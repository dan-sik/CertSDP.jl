@testset "Gate G objective bound certificate type" begin
    matrix = K3.SparseSymmetricRationalMatrix(50, [(1, 1, 1//1)])
    proof = K3.ExactLowRankPSDProof(matrix, [[i == 1 ? 1//1 : 0//1]
                                             for i in 1:50],
                                    [1//1])
    primal = K3.PrimalFeasibilityCertificate(matrix.hash, [0//1], [0//1],
                                             [matrix], [proof], 3//1)
    dual = K3.DualFeasibilityCertificate(matrix.hash, [0//1], [0//1],
                                         [matrix], [proof], 3//1)
    opt = K3.make_primal_dual_optimality_certificate(matrix.hash, primal, dual)
    bound = K3.ObjectiveBoundCertificate(matrix.hash, 3//1, :lower,
                                         opt.certificate_hash)
    @test bound.problem_hash == matrix.hash
    @test bound.bound == 3//1
    @test K3.verify_primal_dual_optimality(opt).accepted
end
