@testset "Gate O CLI replay explain" begin
    fixture = certsdp3_low_rank_fixture(n=4)
    dir = mktempdir()
    cert_path = joinpath(dir, "certificate.json")
    certsdp3_write_json(cert_path, K3.certificate_json_v3(fixture.cert))

    out = IOBuffer()
    code = CertSDP.main(["replay", cert_path, "--strict", "--explain"];
                        io=out, err=IOBuffer())
    @test code == CertSDP.CLI_EXIT_OK
    @test occursin("obligation_id", String(take!(out)))

    bad = certsdp3_cert_json(fixture.cert)
    bad[:proof][:low_rank_proof][:diagonal][1] = "-1"
    bad_path = joinpath(dir, "bad.json")
    certsdp3_write_json(bad_path, bad)
    json_out = IOBuffer()
    code = CertSDP.main(["replay", bad_path, "--strict", "--json"];
                        io=json_out, err=IOBuffer())
    @test code != CertSDP.CLI_EXIT_OK
    report = JSON3.read(String(take!(json_out)))
    @test report[:accepted] == false
    @test String(report[:stage]) != "unknown"
end
