@testset "SOS replay derives coefficients from Gram expansion" begin
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "sparse_sos_control_lyapunov", "certificate.json")
    cert = CertSDP.Kernel.parse_sparse_sos_certificate_json(read(path, String))
    derived = CertSDP.SOSGramExpansion.sparse_sos_identity_polynomial(cert)
    target = CertSDP.SOSGramExpansion.polynomial_dict(cert.problem.target_terms)
    @test derived == target
    bad = certsdp3_mutable_json(JSON3.read(read(path, String)))
    bad[:sos_blocks][1][:coefficient_terms][1][:coefficient] = "999"
    bad_path = tempname() * ".json"
    certsdp3_write_json(bad_path, bad)
    @test !CertSDP.Kernel.replay_file(bad_path; strict=true, io=nothing).accepted
end

