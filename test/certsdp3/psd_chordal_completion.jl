@testset "Gate D chordal completion proof language" begin
    fixture = certsdp3_chordal_fixture(n=120, clique_size=10, overlap=4,
                                       complete_cliques=false)
    @test fixture.proof.theorem_tag ===
          :positive_semidefinite_completion_for_chordal_graph
    @test fixture.proof.matrix_hash == fixture.matrix.hash
    @test fixture.proof.structure.graph_hash ==
          K3.chordal_structure_hash(fixture.structure)
    @test K3.verify_chordal_psd(fixture.matrix, fixture.proof).accepted

    bad_cliques = copy(fixture.proof.clique_proofs)
    bad = bad_cliques[1]
    bad_cliques[1] = K3.CliquePSDProof(bad.id,
                                       length(fixture.structure.cliques) + 1,
                                       bad.vertices,
                                       bad.matrix,
                                       bad.psd_proof)
    bad_proof = K3.ChordalPSDProof(fixture.matrix, fixture.structure,
                                   bad_cliques,
                                   fixture.proof.separator_proofs)
    report = K3.verify_chordal_psd(fixture.matrix, bad_proof)
    @test !report.accepted
    @test report.stage == :clique_replay
    @test report.clique_id == bad.id
end
