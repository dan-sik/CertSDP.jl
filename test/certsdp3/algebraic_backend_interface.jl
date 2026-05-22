@testset "Gate M algebraic backend interface" begin
    system = CertSDP.Exactify3.build_candidate_system(:problem,
                                                       [:obligation];
                                                       metadata=Dict(:gate => :M))
    @test haskey(system, :problem)
    null_set = CertSDP.Exactify3.solve_candidates(system,
                                                  CertSDP.Exactify3.NullCandidateBackend())
    @test null_set.status === :unavailable
    @test CertSDP.Exactify3.candidate_provenance(null_set)[:backend] === :null
end
