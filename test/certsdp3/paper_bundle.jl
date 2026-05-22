@testset "Gate X paper bundle" begin
    fixture = certsdp3_low_rank_fixture(n=5)
    dir = mktempdir()
    cert_path = joinpath(dir, "certificate.json")
    bundle_dir = joinpath(dir, "paper-bundle/")
    certsdp3_write_json(cert_path, K3.certificate_json_v3(fixture.cert))

    @test CertSDP.main(["bundle", cert_path, "--out", bundle_dir];
                       io=IOBuffer(), err=IOBuffer()) == CertSDP.CLI_EXIT_OK
    for file in ["certificate.json", "problem.json", "proof_dag.json",
                 "replay_report.json", "replay_report.html", "VERIFY.sh",
                 "CITATION.cff", "theorem_statement.txt", "hashes.txt"]
        @test isfile(joinpath(bundle_dir, file))
        @test filesize(joinpath(bundle_dir, file)) > 0
    end
    @test success(`bash $(joinpath(bundle_dir, "VERIFY.sh"))`)
    @test occursin(fixture.cert.certificate_id,
                   read(joinpath(bundle_dir, "theorem_statement.txt"), String))

    tampered = certsdp3_cert_json(fixture.cert)
    tampered[:proof][:low_rank_proof][:diagonal][1] = "-1"
    certsdp3_write_json(joinpath(bundle_dir, "certificate.json"), tampered)
    @test !success(`bash $(joinpath(bundle_dir, "VERIFY.sh"))`)
end
