@testset "Gate A kernel trust boundary" begin
    fixture = certsdp3_low_rank_fixture(n=5)
    cert_json = certsdp3_cert_json(fixture.cert)

    claimed = copy(cert_json)
    claimed[:metadata] = Dict("solver_status" => "optimal",
                              "residual" => "0.0")
    @test K3.parse_certificate_json_v3(JSON3.write(claimed)) isa K3.V3Certificate

    truth_claim = copy(cert_json)
    truth_claim[:accepted] = true
    @test_throws ArgumentError K3.parse_certificate_json_v3(JSON3.write(truth_claim))

    raw_log = copy(cert_json)
    raw_log[:proof][:raw_solver_stdout] = "optimal"
    @test_throws ArgumentError K3.parse_certificate_json_v3(JSON3.write(raw_log))

    tampered = copy(cert_json)
    tampered[:proof][:low_rank_proof][:diagonal] = ["-1"]
    @test_throws ArgumentError K3.parse_certificate_json_v3(JSON3.write(tampered))

    @test K3.verify_certificate(fixture.cert).accepted
end
