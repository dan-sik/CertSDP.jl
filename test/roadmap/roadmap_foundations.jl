@testset "Roadmap foundation models" begin
    @testset "proof obligation graph for SOS certificates" begin
        problem = SOSGramProblem([:x], [[1], [0]],
                                 [PolynomialTerm([2], 1), PolynomialTerm([0], 1)])
        result = certify_sos(problem, [1 0; 0 1])
        @test result isa CertifiedResult
        graph = CertSDP.proof_obligation_graph(certificate(result))
        @test graph.family === :sos_gram
        @test any(obligation -> obligation.id === :coefficient_matching,
                  graph.obligations)
        json = CertSDP.proof_obligation_graph_json(graph)
        @test json.family == "sos_gram"
    end

    @testset "external adapter registry names trusted boundaries" begin
        specs = CertSDP.external_adapter_specs()
        @test length(specs) >= 4
        @test CertSDP.external_adapter_spec(:NCTSSOS).production_gate === :nc_quantum
        @test occursin("do not trust",
                       lowercase(CertSDP.external_adapter_spec(:RealCertify).trusted_boundary))
    end

    @testset "noncommutative word identities" begin
        x = nc_word(:x)
        y = nc_word(:y)
        @test nc_involution(nc_multiply(x, y)) == nc_multiply(nc_involution(y),
                                                              nc_involution(x))
        lhs = [NCPolynomialTerm(nc_multiply(x, y), 1)]
        rhs = [NCPolynomialTerm(nc_multiply(y, x), 1)]
        @test !nc_identity_holds(lhs, rhs)
        @test nc_identity_holds(lhs, rhs; trace_cyclic=true)
    end

    @testset "paper artifact manifest is data-only" begin
        problem = SOSGramProblem([:x], [[1], [0]],
                                 [PolynomialTerm([2], 1), PolynomialTerm([0], 1)])
        cert = certificate(certify_sos(problem, [1 0; 0 1]))
        manifest = CertSDP.paper_artifact_manifest(cert; title="SOS smoke")
        @test manifest.certificate_type == SOS_GRAM_CERTIFICATE_TYPE
        @test occursin("verify --strict", manifest.replay_command)
        @test manifest.proof_obligations.family == "sos_gram"
        latex = CertSDP.paper_artifact_latex_snippet(cert)
        @test occursin("CertSDP certificate", latex)
    end

    @testset "paper artifact directory writes strict replay evidence" begin
        problem = SOSGramProblem([:x], [[1], [0]],
                                 [PolynomialTerm([2], 1), PolynomialTerm([0], 1)])
        cert = certificate(certify_sos(problem, [1 0; 0 1]))
        dir = mktempdir()
        artifact = CertSDP.write_paper_artifact(dir, cert; title="SOS reviewer smoke")
        @test artifact.accepted
        @test isfile(artifact.certificate_path)
        @test isfile(artifact.manifest_path)
        @test isfile(artifact.replay_path)
        @test isfile(artifact.snippet_path)
        @test isfile(artifact.provenance_path)
        @test verify_strict(artifact.certificate_path)
        replay = read(artifact.replay_path, String)
        @test occursin("[OK]", replay)
        manifest = JSON3.read(read(artifact.manifest_path, String))
        @test manifest.replay_accepted
        @test manifest.files.certificate == "certificate.json"
        @test occursin("data-only", read(joinpath(dir, "README.md"), String))
    end

    @testset "NC SOS Gram core replays word matching and PSD" begin
        x = nc_word(:x)
        y = nc_word(:y)
        problem = CertSDP.NCSOSGramProblem([:x, :y],
                                           [x, y],
                                           [NCPolynomialTerm(nc_multiply(nc_involution(x),
                                                                         x),
                                                             1),
                                            NCPolynomialTerm(nc_multiply(nc_involution(y),
                                                                         y),
                                                             1)])
        result = CertSDP.certify_nc_sos(problem, [1 0; 0 1])
        @test result isa CertifiedResult
        @test verify(result)
        graph = CertSDP.proof_obligation_graph(certificate(result))
        @test graph.family === :nc_sos_gram
        @test any(obligation -> obligation.id === :word_coefficient_matching,
                  graph.obligations)

        bad = CertSDP.certify_nc_sos(problem, [1 1//2; 1//2 1])
        @test bad isa FailureResult
    end

    @testset "trace-cyclic NC SOS matching accepts cyclic rotations" begin
        x = nc_word(:x)
        y = nc_word(:y)
        problem = CertSDP.NCSOSGramProblem([:x, :y],
                                           [x],
                                           [NCPolynomialTerm(nc_multiply(x,
                                                                         nc_involution(x)),
                                                             1)];
                                           trace_cyclic=true)
        result = CertSDP.certify_nc_sos(problem, reshape([1], 1, 1))
        @test result isa CertifiedResult
        @test verify(result)
    end

    @testset "NC relation reductions are replayed and fingerprinted" begin
        u = nc_word(:u)
        id = nc_identity_word()
        unit_relation = nc_multiply(nc_involution(u), u)
        reduction = CertSDP.NCRelationReduction([CertSDP.NCRewriteRule(unit_relation,
                                                                       id)])
        @test CertSDP.nc_reduce_word(unit_relation, reduction) == id
        @test CertSDP.nc_relation_reduction_matches(reduction,
                                                    reduction.fingerprint)
        @test !CertSDP.nc_relation_reduction_matches(reduction,
                                                     "sha256:0000000000000000000000000000000000000000000000000000000000000000")

        problem = CertSDP.NCSOSGramProblem([:u],
                                           [u],
                                           [NCPolynomialTerm(id, 1)];
                                           reduction)
        result = CertSDP.certify_nc_sos(problem, reshape([1], 1, 1))
        @test result isa CertifiedResult
        cert = certificate(result)
        @test verify(cert)
        graph = CertSDP.proof_obligation_graph(cert)
        @test any(obligation -> obligation.id === :word_relations,
                  graph.obligations)

        stale = CertSDP.NCRelationReduction([CertSDP.NCRewriteRule(u, id)])
        stale_problem = CertSDP.NCSOSGramProblem([:u],
                                                 [u],
                                                 [NCPolynomialTerm(id, 1)];
                                                 reduction=stale)
        @test CertSDP.certify_nc_sos(stale_problem,
                                     reshape([1], 1, 1)) isa FailureResult
    end
end
