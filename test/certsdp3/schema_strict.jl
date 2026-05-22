@testset "Gate F strict v3 schema" begin
    fixture = certsdp3_low_rank_fixture(n=4)
    cert_json = certsdp3_cert_json(fixture.cert)
    text = JSON3.write(cert_json)

    @test K3.validate_certificate_schema_v3(text)

    unknown = copy(cert_json)
    unknown[:surprise] = "field"
    @test_throws ArgumentError K3.parse_certificate_json_v3(JSON3.write(unknown))

    missing = copy(cert_json)
    delete!(missing, :proof)
    @test_throws ArgumentError K3.parse_certificate_json_v3(JSON3.write(missing))

    wrong_version = copy(cert_json)
    wrong_version[:certsdp_certificate_version] = "2.0"
    @test_throws ArgumentError K3.parse_certificate_json_v3(JSON3.write(wrong_version))

    float_exact = copy(cert_json)
    float_exact[:proof][:matrix][:entries][1][:value] = 1.0
    @test_throws ArgumentError K3.parse_certificate_json_v3(JSON3.write(float_exact))

    bad_hash = copy(cert_json)
    bad_hash[:problem_hash] = "sha256:" * repeat("0", 64)
    @test_throws ArgumentError K3.parse_certificate_json_v3(JSON3.write(bad_hash))

    malicious = copy(cert_json)
    malicious[:proof][:matrix][:entries][1][:accepted] = true
    @test_throws ArgumentError K3.parse_certificate_json_v3(JSON3.write(malicious))
end
