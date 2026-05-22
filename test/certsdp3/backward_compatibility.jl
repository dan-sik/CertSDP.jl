@testset "Gate Y backward compatibility" begin
    for name in (:LMIProblem, :BlockLMIProblem, :certify, :verify, :diagnose,
                 :read_problem, :write_problem, :read_certificate,
                 :write_certificate, :certify_sos, :verify_sos)
        @test isdefined(CertSDP, name)
    end

    P = CertSDP.LMIProblem([1//1 0//1; 0//1 1//1],
                           [[0//1 0//1; 0//1 0//1]];
                           vars=[:x])
    result = CertSDP.certify(P, [0//1])
    @test result isa CertSDP.CertifiedResult
    @test CertSDP.verify(result)

    dir = mktempdir()
    path = joinpath(dir, "legacy_cert.json")
    CertSDP.write_certificate(path, result)
    parsed = CertSDP.read_certificate(path)
    @test parsed isa CertSDP.RationalCertificate
    @test CertSDP.verify(parsed)
end
