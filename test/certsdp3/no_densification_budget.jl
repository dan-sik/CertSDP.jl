@testset "Gate T no silent densification budget" begin
    CertSDP.Debug.reset_densification_counter!()
    fixture = certsdp3_chordal_fixture(n=3000, clique_size=10, overlap=8,
                                       complete_cliques=false)
    measurement_start = time()
    report = K3.verify_chordal_psd(fixture.matrix, fixture.proof)
    elapsed = time() - measurement_start
    @test report.accepted
    @test elapsed < 60
    @test CertSDP.Debug.densification_counter() == 0
    @test length(fixture.structure.cliques) >= 250
    @test maximum(length.(fixture.structure.cliques)) <= 10
end
