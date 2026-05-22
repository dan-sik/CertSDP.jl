@testset "Gate D low-rank PSD factor replay" begin
    fixture = certsdp3_low_rank_fixture(n=10)
    report = K3.verify_low_rank_psd(fixture.matrix, fixture.proof)
    @test report.accepted

    bad_matrix = K3.SparseSymmetricRationalMatrix(10,
        vcat(fixture.matrix.entries, [(2, 2, 1//1)]))
    bad_report = K3.verify_low_rank_psd(bad_matrix, fixture.proof)
    @test !bad_report.accepted
    @test bad_report.stage != :unknown
    @test bad_report.obligation_id != :unknown

    negative = K3.ExactLowRankPSDProof(fixture.proof.field,
                                       fixture.proof.matrix_hash,
                                       fixture.proof.factor,
                                       [-1//1],
                                       K3.low_rank_identity_hash(
                                           K3.ExactLowRankPSDProof(
                                               fixture.proof.field,
                                               fixture.proof.matrix_hash,
                                               fixture.proof.factor,
                                               [-1//1],
                                               "")))
    negative_report = K3.verify_low_rank_psd(fixture.matrix, negative)
    @test !negative_report.accepted
    @test negative_report.stage == :sign

    mismatch = K3.ExactLowRankPSDProof(fixture.proof.field,
                                       fixture.proof.matrix_hash,
                                       fixture.proof.factor[1:9],
                                       fixture.proof.diagonal,
                                       fixture.proof.identity_proof_hash)
    @test !K3.verify_low_rank_psd(fixture.matrix, mismatch).accepted
end
