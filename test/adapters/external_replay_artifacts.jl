using JSON3

@testset "External replay adapter artifacts" begin
    problem = SOSGramProblem([:x], [[1], [0]],
                             [PolynomialTerm([2], 1), PolynomialTerm([0], 1)])
    cert = certificate(certify_sos(problem, [1 0; 0 1]))

    for adapter in (:RealCertify, :NCTSSOS, :ClusteredLowRankSolver,
                    :CertifiedQuantumBounds)
        artifact_json = CertSDP.external_replay_artifact_json(adapter, cert;
                                                              source_format="$(adapter)-fixture")
        artifact = CertSDP.parse_external_replay_artifact(JSON3.read(JSON3.write(artifact_json)))
        @test artifact.adapter.name === adapter
        @test verify(artifact)
        @test artifact.certificate isa SOSGramCertificate
    end

    accepted = CertSDP.external_replay_artifact_json(:RealCertify, cert;
                                                     source_format="realcertify-maple-export")
    tampered = Dict{String, Any}(String(key) => value for (key, value) in pairs(accepted))
    tampered["raw_solver_output"] = "Maple said true"
    @test_throws ArgumentError CertSDP.parse_external_replay_artifact(JSON3.read(JSON3.write(tampered)))

    mutated = JSON3.read(JSON3.write(accepted))
    as_dict = Dict{String, Any}(String(key) => value for (key, value) in pairs(mutated))
    replay = Dict{String, Any}(String(key) => value
                               for (key, value) in pairs(mutated.replay))
    replay["accepted"] = false
    as_dict["replay"] = replay
    @test_throws ArgumentError CertSDP.parse_external_replay_artifact(JSON3.read(JSON3.write(as_dict)))
end
