@testset "SOS exactification strategy layer" begin
    problem = SOSGramProblem([:x], [[1], [0]],
                             [PolynomialTerm([2], 1), PolynomialTerm([0], 1)])

    @testset "round-project repairs coefficient mismatch before strict replay" begin
        near = [1.0000001 0.125;
                0.125 0.9999999]
        direct = CertSDP.certify_auto_sos(problem,
                                          near;
                                          strategies=[:direct],
                                          tolerance=0.2,
                                          max_denominator=64)
        @test direct isa FailureResult

        result = CertSDP.certify_auto_sos(problem,
                                          near;
                                          strategies=[:direct, :sos_round_project],
                                          tolerance=0.2,
                                          max_denominator=64)
        @test result isa CertifiedResult
        @test verify_sos(result)
        report = result.artifacts[:exactification_report]
        @test report.selected_strategy === :sos_round_project
        @test length(report.attempts) == 2
        cert = certificate(result)
        @test rational_matrix(cert.gram_matrix) ==
              Rational{BigInt}[1 0; 0 1]
    end

    @testset "experimental strategies fail loudly before promotion" begin
        result = CertSDP.certify_auto_sos(problem,
                                          [1 0; 0 1];
                                          strategies=[:perturb_compensate])
        @test result isa FailureResult
        report = result.artifacts[:exactification_report]
        @test report.attempts[1].status === :unsupported
        @test report.attempts[1].stage === :hard_gate
    end

    @testset "assurance checks are introspectable" begin
        gates = CertSDP.exactification_hard_gates()
        @test length(gates) == 8
        @test any(gate -> gate.id === :round_project_sos, gates)
        @test any(gate -> gate.id === :nc_quantum, gates)
    end
end
