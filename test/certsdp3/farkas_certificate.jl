@testset "Gate G Farkas infeasibility" begin
    matrix = K3.SparseSymmetricRationalMatrix(20,
        [(i, i, 1//1) for i in 1:20])
    factor = [[i == j ? 1//1 : 0//1 for j in 1:20] for i in 1:20]
    proof = K3.ExactLowRankPSDProof(matrix, factor, fill(1//1, 20))
    cert = K3.make_farkas_infeasibility_certificate(matrix.hash,
                                                    fill(0//1, 10),
                                                    fill(0//1, 10),
                                                    [proof],
                                                    0//1,
                                                    -1//1)
    report = K3.verify_farkas_infeasibility(cert)
    @test !report.accepted
    @test report.stage == :farkas_problem_data

    bad_identity = K3.make_farkas_infeasibility_certificate(matrix.hash,
                                                           [1//1; fill(0//1, 9)],
                                                           fill(0//1, 10),
                                                           [proof],
                                                           0//1,
                                                           -1//1)
    identity_report = K3.verify_farkas_infeasibility(bad_identity)
    @test !identity_report.accepted
    @test identity_report.stage == :farkas_problem_data

    bad_norm = K3.make_farkas_infeasibility_certificate(matrix.hash,
                                                       fill(0//1, 10),
                                                       fill(0//1, 10),
                                                       [proof],
                                                       0//1,
                                                       1//1)
    norm_report = K3.verify_farkas_infeasibility(bad_norm)
    @test !norm_report.accepted
    @test norm_report.stage == :farkas_problem_data
end
