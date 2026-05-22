@testset "Gate A adapter metadata is untrusted" begin
    fixture = certsdp3_low_rank_fixture(n=5)
    candidate = CertSDP.Adapters.adapter_candidate(:mock_solver,
                                                   fixture.cert;
                                                   metadata=Dict(:verified => true,
                                                                 :solver_status => "optimal"))
    report = CertSDP.Adapters.certify_adapter_candidate(candidate)
    @test report.accepted

    bad_matrix = K3.SparseSymmetricRationalMatrix(5, [(1, 1, 2//1)])
    bad_proof = K3.ExactLowRankPSDProof(fixture.proof.field,
                                        bad_matrix.hash,
                                        fixture.proof.factor,
                                        fixture.proof.diagonal,
                                        K3.low_rank_identity_hash(
                                            K3.ExactLowRankPSDProof(
                                                fixture.proof.field,
                                                bad_matrix.hash,
                                                fixture.proof.factor,
                                                fixture.proof.diagonal,
                                                "")))
    bad_cert = K3.make_low_rank_psd_certificate(bad_matrix, bad_proof)
    bad_candidate = CertSDP.Adapters.adapter_candidate(:mock_solver,
                                                       bad_cert;
                                                       metadata=Dict(:verified => true))
    bad_report = CertSDP.Adapters.certify_adapter_candidate(bad_candidate)
    @test !bad_report.accepted
    @test bad_report.stage == :identity_replay
end
