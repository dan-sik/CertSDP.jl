@testset "Gate H Putinar certificate identity hash" begin
    vars = [:v1, :v2, :v3, :v4, :v5, :v6, :v7, :v8]
    terms = [K3.PolynomialTerm(fill(0, 8), 1//1)]
    problem = K3.SparseSOSProblem(vars, terms,
                                  [[:v1, :v2, :v3], [:v4, :v5, :v6]],
                                  1//1)
    matrix = K3.SparseSymmetricRationalMatrix(1, [(1, 1, 1//1)])
    proof = K3.ExactLowRankPSDProof(matrix, [[1//1]], [1//1])
    block = K3.SparseSOSBlock(:putinar_block, :opf_clique_1,
                              [fill(0, 8)], matrix, proof, terms)
    localizing = K3.LocalizingMatrixProof(:voltage_box, :opf_clique_1,
                                          terms, block)
    bad_putinar = K3.PutinarCertificate([localizing], 1//1,
                                        "sha256:" * repeat("0", 64))
    cert = K3.make_sparse_sos_certificate(problem, K3.SparseSOSBlock[];
                                          putinar=bad_putinar)
    report = K3.verify_sparse_sos_certificate(cert)
    @test !report.accepted
    @test report.stage == :coefficient_matching
    @test report.obligation_id == :putinar_identity_hash
end
