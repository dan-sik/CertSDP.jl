@testset "Gate D chordal PSD certificate" begin
    CertSDP.Debug.reset_densification_counter!()
    fixture = certsdp3_chordal_fixture(n=30, clique_size=7, overlap=3)
    report = K3.verify_chordal_psd(fixture.matrix, fixture.proof)
    @test report.accepted
    @test CertSDP.Debug.densification_counter() == 0

    bad_separator = copy(fixture.proof.separator_proofs)
    first_separator = bad_separator[1]
    bad_separator[1] = K3.SeparatorConsistencyProof(first_separator.id,
                                                    first_separator.left_clique,
                                                    first_separator.right_clique,
                                                    first_separator.vertices,
                                                    "sha256:" * repeat("0", 64))
    bad_proof = K3.ChordalPSDProof(fixture.proof.theorem_tag,
                                   fixture.proof.matrix_hash,
                                   fixture.proof.structure,
                                   fixture.proof.clique_proofs,
                                   bad_separator,
                                   K3.chordal_proof_hash(
                                       K3.ChordalPSDProof(
                                           fixture.proof.theorem_tag,
                                           fixture.proof.matrix_hash,
                                           fixture.proof.structure,
                                           fixture.proof.clique_proofs,
                                           bad_separator,
                                           "")))
    bad_report = K3.verify_chordal_psd(fixture.matrix, bad_proof)
    @test !bad_report.accepted
    @test bad_report.stage == :separator_replay
    @test bad_report.separator_id == first_separator.id

    clique_proofs = copy(fixture.proof.clique_proofs)
    clique = clique_proofs[1]
    bad_entries = copy(clique.matrix.entries)
    bad_entries[1] = (bad_entries[1][1], bad_entries[1][2], 2//1)
    bad_local = K3.SparseSymmetricRationalMatrix(clique.matrix.n,
                                                bad_entries)
    bad_low_rank = K3.ExactLowRankPSDProof(bad_local,
                                           clique.psd_proof.factor,
                                           clique.psd_proof.diagonal)
    clique_proofs[1] = K3.CliquePSDProof(clique.id,
                                         clique.clique_index,
                                         clique.vertices,
                                         bad_local,
                                         bad_low_rank)
    bad_clique_proof = K3.ChordalPSDProof(fixture.matrix,
                                          fixture.structure,
                                          clique_proofs,
                                          fixture.proof.separator_proofs)
    clique_report = K3.verify_chordal_psd(fixture.matrix, bad_clique_proof)
    @test !clique_report.accepted
    @test clique_report.clique_id == clique.id
end
