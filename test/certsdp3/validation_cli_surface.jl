@testset "Gate P/Q validation corpus CLI replay surface" begin
    root = normpath(joinpath(@__DIR__, "..", "fixtures", "certsdp3"))
    index = JSON3.read(read(joinpath(root, "index.json"), String))
    bundle_checked = false
    for fixture in index[:fixtures]
        fixture_id = String(fixture[:fixture_id])
        dir = joinpath(root, fixture_id)
        cert_path = joinpath(dir, "certificate.json")

        replay_json = IOBuffer()
        @test CertSDP.main(["replay", cert_path, "--strict", "--json"];
                           io=replay_json, err=IOBuffer()) == CertSDP.CLI_EXIT_OK
        report = JSON3.read(String(take!(replay_json)))
        @test report[:accepted] == true
        @test String(report[:stage]) != "unknown"
        @test String(report[:obligation_id]) != "unknown"

        @test CertSDP.main(["verify", cert_path, "--strict"];
                           io=IOBuffer(), err=IOBuffer()) == CertSDP.CLI_EXIT_OK
        @test CertSDP.main(["schema", "validate", cert_path, "--kind",
                            "certificate"]; io=IOBuffer(),
                           err=IOBuffer()) == CertSDP.CLI_EXIT_OK

        diagnose_json = IOBuffer()
        @test CertSDP.main(["diagnose", cert_path, "--format", "json"];
                           io=diagnose_json,
                           err=IOBuffer()) == CertSDP.CLI_EXIT_OK
        diagnosed = JSON3.read(String(take!(diagnose_json)))
        @test diagnosed[:accepted] == true

        if !bundle_checked && fixture_id == "sparse_sos_control_lyapunov"
            bundle_dir = joinpath(mktempdir(), "bundle")
            @test CertSDP.main(["bundle", cert_path, "--out", bundle_dir];
                               io=IOBuffer(),
                               err=IOBuffer()) == CertSDP.CLI_EXIT_OK
            @test isfile(joinpath(bundle_dir, "VERIFY.sh"))
            @test success(`bash $(joinpath(bundle_dir, "VERIFY.sh"))`)
            bundle_checked = true
        end

        if fixture_id == "block_native_algebraic_medium"
            certified = joinpath(mktempdir(), "certified.json")
            @test CertSDP.main(["certify", joinpath(dir, "problem.json"),
                                "--candidate", cert_path, "--out", certified];
                               io=IOBuffer(),
                               err=IOBuffer()) == CertSDP.CLI_EXIT_OK
            @test isfile(certified)
            wrong_problem = certsdp3_mutable_json(JSON3.read(read(joinpath(dir, "problem.json"),
                                                                  String)))
            wrong_problem[:hash] = "sha256:" * repeat("1", 64)
            wrong_path = joinpath(mktempdir(), "wrong_problem.json")
            certsdp3_write_json(wrong_path, wrong_problem)
            @test CertSDP.main(["certify", wrong_path, "--candidate", cert_path,
                                "--out", joinpath(mktempdir(), "bad.json")];
                               io=IOBuffer(),
                               err=IOBuffer()) != CertSDP.CLI_EXIT_OK
        end

        for tamper in fixture[:tamper_files]
            tamper_path = joinpath(dir, String(tamper))
            tamper_json = IOBuffer()
            code = CertSDP.main(["replay", tamper_path, "--strict", "--json"];
                                io=tamper_json,
                                err=IOBuffer())
            @test code != CertSDP.CLI_EXIT_OK
            if position(tamper_json) > 0
                tamper_report = JSON3.read(String(take!(tamper_json)))
                @test tamper_report[:accepted] == false
                @test String(tamper_report[:stage]) != "unknown"
            end
        end
    end
    @test bundle_checked
end
