@testset "Gate A exactify candidates must replay" begin
    fixture = certsdp3_low_rank_fixture(n=4)
    report = CertSDP.Exactify3.replay_candidate(fixture.cert)
    @test report.accepted

    non_certificate = CertSDP.Exactify3.CandidateSet(:finite, Any[Dict(:x => 1)],
                                                     Dict(:solver_status => "optimal"))
    rejected = CertSDP.Exactify3.replay_candidate(non_certificate)
    @test !rejected.accepted
    @test rejected.stage == :candidate_replay

    bad_matrix = K3.SparseSymmetricRationalMatrix(4, [(1, 1, 2//1)])
    bad_proof = K3.ExactLowRankPSDProof(bad_matrix,
                                        fixture.proof.factor,
                                        fixture.proof.diagonal)
    bad_cert = K3.make_low_rank_psd_certificate(bad_matrix, bad_proof)
    bad = CertSDP.Exactify3.replay_candidate(bad_cert)
    @test !bad.accepted
    @test bad.obligation_id == :matrix_identity
end
