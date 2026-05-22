@testset "Gate M fixture backend" begin
    fixture = certsdp3_low_rank_fixture(n=3)
    dir = mktempdir()
    cert_path = joinpath(dir, "cert.json")
    certsdp3_write_json(cert_path, K3.certificate_json_v3(fixture.cert))
    system = CertSDP.Exactify3.build_candidate_system(:problem)
    set = CertSDP.Exactify3.solve_candidates(system,
                                             CertSDP.Exactify3.FixtureCandidateBackend(cert_path))
    @test set.status === :finite
    @test length(set.candidates) == 1
    @test CertSDP.Exactify3.replay_candidate(first(set.candidates)).accepted
end
