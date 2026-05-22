@testset "Gate J quantum bound certificate" begin
    relations = K3.AbstractQuantumRelation[
        K3.ProjectionRelation(:proj_A, :A),
        K3.ProjectionRelation(:proj_B, :B),
        K3.CommutationRelation(:comm_AB, [:A], [:B]),
        K3.TraceCyclicRelation(:trace_cyclic),
        K3.StarInvolutionRelation(:star_involution),
        K3.NormalizationRelation(:trace_one, 1//1),
    ]
    basis = [Symbol[], [:A], [:B], [:A, :B]]
    problem = K3.NPAProblem([:A, :B], relations, basis; trace_cyclic=true)
    matrix = K3.SparseSymmetricRationalMatrix(4, [(i, i, 1//1) for i in 1:4])
    proof = K3.ExactLowRankPSDProof(matrix,
                                    [[i == j ? 1//1 : 0//1 for j in 1:4]
                                     for i in 1:4],
                                    fill(1//1, 4))
    terms = Tuple{Vector{Symbol}, Rational{BigInt}}[
        ([:A, :A], 1//1),
        ([:A, :B], 1//1),
    ]
    witnesses = K3.NCRewriteWitness[
        K3.NCRewriteWitness([:A, :A],
                             [K3.NCRewriteStep(:proj_A,
                                               :projection_idempotent,
                                               [:A, :A],
                                               [:A])],
                             [:A],
                             [:proj_A],
                             Vector{Symbol}[],
                             Vector{Symbol}[]),
        K3.NCRewriteWitness([:A, :B],
                             [K3.NCRewriteStep(:comm_AB,
                                               :commutation,
                                               [:A, :B],
                                               [:B, :A])],
                             [:B, :A],
                             [:comm_AB],
                             Vector{Symbol}[],
                             Vector{Symbol}[]),
    ]
    moment = K3.NCMomentMatrixCertificate(problem, matrix, proof, terms,
                                          witnesses)
    cert = K3.make_quantum_bound_certificate(problem, moment, terms, 2//1)
    @test K3.verify_quantum_bound_certificate(cert).accepted

    parsed = K3.parse_quantum_bound_certificate_json(JSON3.write(K3.quantum_bound_certificate_json(cert)))
    @test parsed.certificate_hash == cert.certificate_hash
    @test K3.verify_quantum_bound_certificate(parsed).accepted
end
