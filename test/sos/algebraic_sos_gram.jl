@testset "Algebraic SOS Gram certificates" begin
    root = parse_algebraic_root("t^2 - 2", ("1", "2"))
    alpha = AlgebraicElement(root, "t")
    problem = CertSDP.AlgebraicSOSGramProblem([:x],
                                              [[1], [0]],
                                              [CertSDP.AlgebraicPolynomialTerm([2],
                                                                               alpha),
                                               CertSDP.AlgebraicPolynomialTerm([0],
                                                                               alpha)])
    gram = [alpha AlgebraicElement(root, 0);
            AlgebraicElement(root, 0) alpha]

    result = CertSDP.certify_algebraic_sos(problem, gram)
    @test result isa CertifiedResult
    cert = certificate(result)
    @test cert isa CertSDP.AlgebraicSOSGramCertificate
    @test verify(cert)
    @test verify_strict_json(certificate_json_v1_string(cert))

    loaded = parse_certificate_json(certificate_json_v1_string(cert))
    @test loaded isa CertSDP.AlgebraicSOSGramCertificate
    @test verify(loaded)

    graph = CertSDP.proof_obligation_graph(cert)
    @test graph.family === :algebraic_sos_gram
    @test any(obligation -> obligation.id === :gram_psd, graph.obligations)

    bad_problem = CertSDP.AlgebraicSOSGramProblem([:x],
                                                  [[1], [0]],
                                                  [CertSDP.AlgebraicPolynomialTerm([2],
                                                                                   alpha)])
    @test CertSDP.certify_algebraic_sos(bad_problem, gram) isa FailureResult

    negative_gram = [AlgebraicElement(root, "-t") AlgebraicElement(root, 0);
                     AlgebraicElement(root, 0) AlgebraicElement(root, "-t")]
    negative_problem = CertSDP.AlgebraicSOSGramProblem([:x],
                                                       [[1], [0]],
                                                       [CertSDP.AlgebraicPolynomialTerm([2],
                                                                                        -alpha),
                                                        CertSDP.AlgebraicPolynomialTerm([0],
                                                                                        -alpha)])
    @test CertSDP.certify_algebraic_sos(negative_problem,
                                        negative_gram) isa FailureResult
end
