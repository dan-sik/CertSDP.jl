@testset "Gate H localizing matrix replay" begin
    using SHA: sha256

    vars = [:x1, :x2, :x3, :x4]
    terms = [K3.PolynomialTerm([0, 0, 0, 0], 1//1)]
    problem = K3.SparseSOSProblem(vars, terms, [[:x1, :x2]], 0//1)
    matrix = K3.SparseSymmetricRationalMatrix(1, [(1, 1, 1//1)])
    proof = K3.ExactLowRankPSDProof(matrix, [[1//1]], [1//1])
    block = K3.SparseSOSBlock(:loc_gram, :clique_1,
                              [[0, 0, 0, 0]],
                              matrix,
                              proof,
                              terms)
    localizing = K3.LocalizingMatrixProof(:loc_1, :clique_1,
                                          [K3.PolynomialTerm([0, 0, 0, 0], 1//1)],
                                          block)
    identity_hash = "sha256:" * bytes2hex(sha256(JSON3.write((;
        bound="0",
        localizing=[K3.localizing_matrix_proof_json(localizing)],
    ))))
    putinar = K3.PutinarCertificate([localizing], 0//1, identity_hash)
    cert = K3.make_sparse_sos_certificate(problem, K3.SparseSOSBlock[];
                                          putinar)
    @test K3.verify_sparse_sos_certificate(cert).accepted

    bad_putinar = K3.PutinarCertificate([localizing], 1//1, identity_hash)
    bad_cert = K3.make_sparse_sos_certificate(problem, K3.SparseSOSBlock[];
                                              putinar=bad_putinar)
    bad = K3.verify_sparse_sos_certificate(bad_cert)
    @test !bad.accepted
    @test bad.stage == :objective_bound
end
