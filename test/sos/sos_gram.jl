@testset "SOS Gram workflow" begin
    function sample_sos_problem()
        return build_sos_gram_problem([:x],
                                      [[0], [1]],
                                      [PolynomialTerm([2], 1),
                                       PolynomialTerm([0], 1)])
    end

    @testset "exported Gram SDP verifies exact coefficient matching" begin
        problem = sample_sos_problem()
        Q = [1 0; 0 1]

        @test problem.variables == [:x]
        @test problem.basis == [[0], [1]]
        @test verify_sos_gram_matrix(problem, Q)

        result = certify_sos(problem, Q)
        @test result isa CertifiedResult
        cert = certificate(result)
        @test cert.hash == sos_gram_certificate_hash(cert)
        @test verify(cert)
        @test verify_sos(cert)
        @test verify(cert.lmi_certificate)
        @test rational_matrix(cert.gram_matrix) == Rational{BigInt}[1 0; 0 1]
        @test length(cert.coefficient_proof) == 2
        @test cert.decomposition.status === :squares
        @test length(export_sos_decomposition(cert).squares) == 2
        @test occursin("x^2 + 1", sos_decomposition_text(cert))
        @test occursin("\\left(x\\right)^2", sos_decomposition_latex(cert))
        @test occursin("PolynomialRing(QQ", sos_decomposition_sage(cert))
        @test occursin("@polyvar x", sos_decomposition_julia(cert))

        output = IOBuffer()
        @test verify(cert; io=output)
        text = String(take!(output))
        @test occursin("[OK] SOS coefficient matching is exact", text)
        @test occursin("[OK] Gram polynomial matches target polynomial", text)
        @test occursin("[OK] SOS Gram certificate accepted", text)
    end

    @testset "JSON problem and certificate roundtrip" begin
        problem = sample_sos_problem()
        parsed_problem = parse_sos_gram_json(sos_gram_problem_json_string(problem))

        @test parsed_problem.variables == problem.variables
        @test parsed_problem.basis == problem.basis
        @test sos_gram_problem_hash(parsed_problem) == sos_gram_problem_hash(problem)

        cert = certificate(certify_sos(parsed_problem, [1//1 0//1; 0//1 1//1]))
        loaded = parse_certificate_json(sos_gram_certificate_json_string(cert))

        @test loaded isa SOSGramCertificate
        @test loaded.hash == cert.hash
        @test verify(loaded)
    end

    @testset "certificate hashes preserve stored provenance" begin
        problem = sample_sos_problem()
        cert = certificate(certify_sos(problem, [1//1 0//1; 0//1 1//1]))
        lmi_json = certificate_json_v1(cert.lmi_certificate)
        stored_lmi_json = merge(lmi_json,
                                (;
                                 provenance=merge(lmi_json.provenance,
                                                  (; julia_version="1.10.11"))))
        metadata = Dict{Symbol, Any}(:certsdp_version => "1.0.0",
                                     :julia_version => "1.10.11",
                                     :schema_version => "1.0",
                                     :source => "sos_gram_workflow",
                                     :verifier_version => "1.0.0",
                                     :lmi_certificate_json => stored_lmi_json)
        without_hash = SOSGramCertificate(cert.problem, cert.gram_matrix,
                                          cert.lmi_certificate,
                                          cert.coefficient_proof,
                                          cert.decomposition, "", metadata)
        stored = SOSGramCertificate(cert.problem, cert.gram_matrix,
                                    cert.lmi_certificate, cert.coefficient_proof,
                                    cert.decomposition,
                                    sos_gram_certificate_hash(without_hash),
                                    metadata)

        json = sos_gram_certificate_json(stored)
        @test json.provenance.julia_version == "1.10.11"
        @test json.lmi_certificate.provenance.julia_version == "1.10.11"

        loaded = parse_certificate_json(sos_gram_certificate_json_string(stored))
        @test loaded isa SOSGramCertificate
        @test loaded.hash == stored.hash
        @test loaded.metadata[:julia_version] == "1.10.11"
        @test verify(loaded)
    end

    @testset "fake coefficient matches are rejected" begin
        problem = sample_sos_problem()
        bad_Q = [1 1; 1 1]

        @test !verify_sos_gram_matrix(problem, bad_Q)
        result = certify_sos(problem, bad_Q)
        @test result isa FailureResult
        @test result.failure isa SOSMatchingFailure
    end

    @testset "non-PSD Gram matrices are rejected" begin
        problem = build_sos_gram_problem([:x],
                                         [[0], [1]],
                                         [PolynomialTerm([2], -1),
                                          PolynomialTerm([0], 1)])
        bad_Q = [1 0; 0 -1]

        @test !verify_sos_gram_matrix(problem, bad_Q)
        result = certify_sos(problem, bad_Q)
        @test result isa FailureResult
        @test result.failure isa SOSMatchingFailure
    end

    @testset "fake certificate with matching hash is rejected" begin
        problem = sample_sos_problem()
        cert = certificate(certify_sos(problem, [1 0; 0 1]))
        fake_matches = copy(cert.coefficient_proof)
        fake_matches[1] = SOSCoefficientMatch(fake_matches[1].exponents,
                                              fake_matches[1].target_coefficient + 1,
                                              fake_matches[1].gram_coefficient,
                                              fake_matches[1].contributions)
        fake_without_hash = SOSGramCertificate(cert.problem,
                                               cert.gram_matrix,
                                               cert.lmi_certificate,
                                               fake_matches,
                                               cert.decomposition,
                                               "")
        fake = SOSGramCertificate(cert.problem,
                                  cert.gram_matrix,
                                  cert.lmi_certificate,
                                  fake_matches,
                                  cert.decomposition,
                                  sos_gram_certificate_hash(fake_without_hash))

        output = IOBuffer()
        @test !verify(fake; io=output)
        text = String(take!(output))
        @test occursin("[OK] SOS certificate hash matches", text)
        @test occursin("[FAIL] SOS coefficient metadata matches recomputation", text)
    end

    @testset "optional SumOfSquares GramMatrix extraction" begin
        @eval using DynamicPolynomials
        @eval using SumOfSquares

        @eval @polyvar x
        gram = @eval GramMatrix([1//1 0//1; 0//1 1//1], [1, x])
        extracted = extract_sos_gram_sdp(gram)

        problem = extracted.problem
        @test problem isa SOSGramProblem
        @test problem.variables == [:x]
        @test problem.basis == [[0], [1]]
        @test extracted.gram_matrix == Rational{BigInt}[1 0; 0 1]
        @test verify_sos_gram_matrix(problem, extracted.gram_matrix)
    end

    @testset "five SOS examples verify exactly" begin
        examples = Pair{SOSGramProblem, Matrix{Int}}[build_sos_gram_problem([:x],
                                                     [[0], [1]],
                                                     [PolynomialTerm([0], 1),
                                                     PolynomialTerm([2], 1)]) => [1 0; 0 1],
                                                     build_sos_gram_problem([:x, :y],
                                                     [[1, 0], [0, 1]],
                                                     [PolynomialTerm([2, 0], 1),
                                                     PolynomialTerm([1, 1], 2),
                                                     PolynomialTerm([0, 2], 1)]) => [1 1;
                                                                                     1 1],
                                                     build_sos_gram_problem([:x],
                                                     [[0], [1], [2]],
                                                     [PolynomialTerm([0], 1),
                                                     PolynomialTerm([4], 1)]) => [1 0 0;
                                                                                  0 0 0;
                                                                                  0 0 1],
                                                     build_sos_gram_problem([:x, :y],
                                                     [[2, 0], [1, 1], [0, 2]],
                                                     [PolynomialTerm([4, 0], 1),
                                                     PolynomialTerm([3, 1], 2),
                                                     PolynomialTerm([2, 2], 2),
                                                     PolynomialTerm([1, 3], 2),
                                                     PolynomialTerm([0, 4], 1)]) => [1 1 0;
                                                                                     1 2 1;
                                                                                     0 1 1],
                                                     build_sos_gram_problem([:x],
                                                     [[0], [1], [2]],
                                                     [PolynomialTerm([0], 1),
                                                     PolynomialTerm([1], 2),
                                                     PolynomialTerm([2], 2),
                                                     PolynomialTerm([3], 2),
                                                     PolynomialTerm([4], 1)]) => [1 1 0;
                                                                                  1 2 1;
                                                                                  0 1 1]]

        for (problem, Q) in examples
            cert = certificate(certify_sos(problem, Q))
            @test verify_sos(cert)
            @test all(match.target_coefficient == match.gram_coefficient
                      for match in cert.coefficient_proof)
        end
    end

    @testset "Gram-only certificate falls back when square export is unsafe" begin
        problem = build_sos_gram_problem([:x, :y],
                                         [[1, 0], [0, 1]],
                                         [PolynomialTerm([2, 0], 1002002),
                                          PolynomialTerm([1, 1], 2),
                                          PolynomialTerm([0, 2], 1)])
        cert = certificate(certify_sos(problem, [1002002 1; 1 1]))

        @test verify_sos(cert)
        @test cert.decomposition.status === :gram_only
        exported = export_sos_decomposition(cert)
        @test exported.type == "gram_only"
        @test occursin("safety budget", exported.reason)
        @test occursin("v'Qv", sos_decomposition_text(cert))
    end

    @testset "off-diagonal rational Gram factorization when safe" begin
        problem = build_sos_gram_problem([:x, :y],
                                         [[1, 0], [0, 1]],
                                         [PolynomialTerm([2, 0], 1),
                                          PolynomialTerm([1, 1], 2),
                                          PolynomialTerm([0, 2], 1)])
        cert = certificate(certify_sos(problem, [1 1; 1 1]))

        @test verify_sos(cert)
        @test cert.decomposition.status === :squares
        @test cert.decomposition.method == "exact_rational_ldl_square_pivots"
        @test length(cert.decomposition.squares) == 1
        @test occursin("(x + y)^2", sos_decomposition_text(cert))
    end

    @testset "non-square rational pivots can decompose safely" begin
        problem = build_sos_gram_problem([:x],
                                         [[1]],
                                         [PolynomialTerm([2], 2)])
        cert = certificate(certify_sos(problem, [2;;]))

        @test verify_sos(cert)
        @test cert.decomposition.status === :squares
        @test cert.decomposition.method == "exact_rational_ldl_four_squares"
        @test length(cert.decomposition.squares) == 2
    end

    @testset "float-to-rational reconstruction is explicit only" begin
        problem = sample_sos_problem()

        float_result = certify_sos(problem, [1.0 0.0; 0.0 1.0])
        @test float_result isa FailureResult
        @test float_result.failure isa SOSMatchingFailure
        reconstructed = reconstruct_rational_gram_matrix([1.0 0.0; 0.0 1.0];
                                                         tolerance=1e-12)
        cert = certificate(certify_sos(problem, reconstructed))
        @test verify_sos(cert)
        @test rational_matrix(cert.gram_matrix) == Rational{BigInt}[1 0; 0 1]

        @test_throws ArgumentError reconstruct_rational_gram_matrix([1.0 0.0; 0.0 1.0])
        @test_throws ArgumentError reconstruct_rational_gram_matrix([0.3333;;];
                                                                    tolerance=1e-12,
                                                                    max_denominator=100)
    end

    @testset "CLI float reconstruction is explicit and verified" begin
        problem = sample_sos_problem()
        problem_path = tempname() * ".json"
        write_sos_gram_json(problem_path, problem)

        solution_path = tempname() * ".json"
        write(solution_path,
              """
              {
                "solution": {
                  "type": "rational_gram_matrix",
                  "gram_matrix": [[1.0, 0.0], [0.0, 1.0]]
                }
              }
              """)
        cert_path = tempname() * ".json"

        without_reconstruction = CertSDP.main(["certify-sos",
                                               problem_path,
                                               "--solution",
                                               solution_path,
                                               "--out",
                                               cert_path];
                                              io=IOBuffer(),
                                              err=IOBuffer())
        @test without_reconstruction == CertSDP.CLI_EXIT_USAGE

        accepted = CertSDP.main(["certify-sos",
                                 problem_path,
                                 "--solution",
                                 solution_path,
                                 "--out",
                                 cert_path,
                                 "--reconstruct-floats",
                                 "--reconstruction-tolerance",
                                 "1e-12"];
                                io=IOBuffer(),
                                err=IOBuffer())
        @test accepted == CertSDP.CLI_EXIT_OK
        @test verify_sos(read_certificate(cert_path))
    end

    @testset "SumOfSquares constraint and model extraction with supplied Gram matrices" begin
        @eval using DynamicPolynomials
        @eval using SumOfSquares

        @eval @polyvar x
        @eval const CERTSDP_SOS_TEST_MODEL = SOSModel()
        cref = @eval @constraint(CERTSDP_SOS_TEST_MODEL, x^2 + 1 in SOSCone())

        @test_throws ArgumentError extract_sos_gram_sdp(cref;
                                                        gram_matrix=[1//1 0//1; 0//1 1//1])
        extracted = extract_sos_gram_sdp(cref;
                                         gram_matrix=[1//1 0//1; 0//1 1//1],
                                         reconstruct_floats=true,
                                         tolerance=1e-12)
        @test extracted.problem isa SOSGramProblem
        @test extracted.problem.basis == [[0], [1]]
        @test extracted.gram_matrix == Rational{BigInt}[1 0; 0 1]

        result = certify_sos(@eval(CERTSDP_SOS_TEST_MODEL);
                             gram_matrices=[[1//1 0//1; 0//1 1//1]],
                             reconstruct_floats=true,
                             tolerance=1e-12)
        @test result isa CertifiedResult
        cert = certificate(result)
        @test cert isa SOSGramCertificate
        @test verify_sos(cert)

        unsolved = @eval SOSModel()
        @eval @constraint($unsolved, x^2 + 1 in SOSCone())
        @test_throws ArgumentError extract_sos_gram_sdp(unsolved)
        @test_throws ArgumentError certify_sos(unsolved)
    end

    @testset "SumOfSquares extraction rejects floats unless reconstruction is explicit" begin
        @eval using DynamicPolynomials
        @eval using SumOfSquares

        @eval @polyvar z
        gram = @eval GramMatrix([1.0 0.0; 0.0 1.0], [1, z])
        @test_throws ArgumentError extract_sos_gram_sdp(gram)

        extracted = extract_sos_gram_sdp(gram;
                                         reconstruct_floats=true,
                                         tolerance=1e-12)
        @test verify_sos_gram_matrix(extracted.problem, extracted.gram_matrix)
        @test extracted.gram_matrix == Rational{BigInt}[1 0; 0 1]
    end

    @testset "v1 schema validates SOS and rejects fake certificate data" begin
        cert = certificate(certify_sos(sample_sos_problem(), [1 0; 0 1]))
        json = sos_gram_certificate_json_string(cert)

        @test validate_certificate_schema(json)
        @test parse_certificate_json(json) isa SOSGramCertificate
        @test verify_sos(parse_certificate_json(json))

        fake_json = replace(json,
                            "\"gram_coefficient\": \"1\"" => "\"gram_coefficient\": \"2\"";
                            count=1)
        fake = parse_certificate_json(fake_json)
        @test fake isa SOSGramCertificate
        @test !verify_sos(fake)
    end
end
