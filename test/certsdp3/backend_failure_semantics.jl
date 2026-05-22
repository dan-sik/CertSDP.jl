@testset "Gate M backend failure semantics" begin
    missing = CertSDP.Exactify3.solve_candidates(:system,
                                                 CertSDP.Exactify3.FixtureCandidateBackend("missing.json"))
    @test missing.status === :unavailable
    @test isempty(missing.candidates)

    external = CertSDP.Exactify3.solve_candidates(:system,
                                                  CertSDP.Exactify3.MsolveCandidateBackend(nothing))
    @test external.status === :unavailable
    @test external.provenance[:backend] === :msolve
end
