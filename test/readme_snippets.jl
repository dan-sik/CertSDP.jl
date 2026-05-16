@testset "README and CI public snippets" begin
    repo_root = normpath(joinpath(@__DIR__, ".."))

    @testset "Julia API rational certificate snippet" begin
        problem_path = joinpath(repo_root, "examples", "rational_problem.json")
        sandbox = Module(:CertSDPReadmeRationalSnippet)
        Core.eval(sandbox, :(using CertSDP))
        accepted, written, loaded = Core.eval(sandbox,
                                              quote
                                                  P = read_problem($problem_path)
                                                  result = certify(P, [1 // 2, 1 // 3])
                                                  cert_path = tempname() * ".json"
                                                  ok = verify(result)
                                                  wrote = write_certificate(cert_path,
                                                                            result) ==
                                                          cert_path
                                                  replay = verify(read_certificate(cert_path))
                                                  (ok, wrote, replay)
                                              end)

        @test accepted
        @test written
        @test loaded
    end

    @testset "README CLI quickstart files" begin
        cert_path = tempname() * ".json"
        certify_code = CertSDP.main(["certify",
                                     joinpath(repo_root, "examples",
                                              "rational_problem.json"),
                                     "--solution",
                                     joinpath(repo_root, "examples",
                                              "rational_solution.json"),
                                     "--out",
                                     cert_path];
                                    io=IOBuffer(),
                                    err=IOBuffer())
        @test certify_code == 0
        @test isfile(cert_path)

        verify_code = CertSDP.main(["verify", "--strict", cert_path];
                                   io=IOBuffer(),
                                   err=IOBuffer())
        @test verify_code == 0
    end

    @testset "Windows verifier smoke public path" begin
        sandbox = Module(:CertSDPWindowsSmokeSnippet)
        Core.eval(sandbox, :(using CertSDP))
        cert_path = tempname() * ".json"
        Core.eval(sandbox,
                  quote
                      result = certify(read_problem($(joinpath(repo_root, "examples",
                                                               "rational_problem.json"))),
                                       [1 // 2, 1 // 3])
                      verify(result) || error("public exact rational certify failed")
                      write_certificate($cert_path, result)
                  end)

        code = CertSDP.main(["verify", "--strict", cert_path];
                            io=IOBuffer(),
                            err=IOBuffer())
        @test code == 0
    end
end
