@testset "Type R rational certificates" begin
    function sample_rational_certificate()
        P = LMIProblem([1 0; 0 1],
                       [[1 0; 0 0],
                        [0 0; 0 1]];
                       vars=[:x, :y],)
        return RationalCertificate(P, [1 // 2, 1 // 3])
    end

    @testset "true certificates are accepted" begin
        cert = sample_rational_certificate()

        @test cert.solution == Rational{BigInt}[1 // 2, 1 // 3]
        @test cert.hash == rational_certificate_hash(cert)
        @test verify(cert)

        output = IOBuffer()
        @test verify(cert; io=output)
        text = String(take!(output))
        @test occursin("[OK] certificate hash matches", text)
        @test occursin("[OK] certificate accepted", text)
    end

    @testset "save/load JSON roundtrip" begin
        cert = sample_rational_certificate()
        path = tempname() * ".json"

        save_certificate(path, cert)
        loaded = load_certificate(path)

        @test loaded.hash == cert.hash
        @test loaded.solution == cert.solution
        @test lmi_problem_hash(loaded.problem) == lmi_problem_hash(cert.problem)
        @test rational_matrix(loaded.psd_proof.matrix) ==
              rational_matrix(cert.psd_proof.matrix)
        @test verify(loaded)
        @test verify(path)
    end

    @testset "tampered JSON entry is rejected" begin
        cert = sample_rational_certificate()
        json = rational_certificate_json_string(cert)
        tampered_json = replace(json, "\"1/2\"" => "\"-5\""; count=1)
        tampered = parse_certificate_json(tampered_json)

        output = IOBuffer()
        @test !verify(tampered; io=output)
        @test occursin("[FAIL] certificate hash matches", String(take!(output)))
    end

    @testset "fake proof with matching hash is rejected" begin
        cert = sample_rational_certificate()
        fake_matrix = SymmetricRationalMatrix([2 0; 0 2])
        fake_proof = RationalPSDProof(:principal_minors, fake_matrix,
                                      rational_psd_proof(fake_matrix).principal_minors)
        fake_without_hash = RationalCertificate(cert.problem, cert.solution, fake_proof, "")
        fake = RationalCertificate(cert.problem, cert.solution, fake_proof,
                                   rational_certificate_hash(fake_without_hash))

        output = IOBuffer()
        @test !verify(fake; io=output)
        text = String(take!(output))
        @test occursin("[OK] certificate hash matches", text)
        @test occursin("[FAIL] substituted matrix matches rational solution", text)
    end

    @testset "rational LDL certificates reject fake pivots" begin
        P = LMIProblem([0 0; 0 0],
                       [[1 0; 0 0],
                        [0 0; 0 1]])
        cert = RationalCertificate(P, [1, 1]; psd_method=:ldl)
        @test cert.psd_proof.method === :ldl
        @test verify(cert)

        fake_pivots = copy(cert.psd_proof.ldl.pivots)
        fake_pivots[2] = LDLPivotProof(2, Rational{BigInt}(2), :positive)
        fake_proof = RationalPSDProof(:ldl,
                                      cert.psd_proof.matrix,
                                      PrincipalMinorProof{Rational{BigInt}}[],
                                      nothing,
                                      LDLProof(fake_pivots))
        fake_without_hash = RationalCertificate(P, cert.solution, fake_proof, "")
        fake = RationalCertificate(P, cert.solution, fake_proof,
                                   rational_certificate_hash(fake_without_hash))

        output = IOBuffer()
        @test !verify(fake; io=output)
        text = String(take!(output))
        @test occursin("[OK] certificate hash matches", text)
        @test occursin("[FAIL] LDL proof matches recomputation", text)
    end

    @testset "non-PSD fake certificate is rejected even with matching hash" begin
        P = LMIProblem([1 0; 0 1], [[0 2; 2 0]])
        bad_matrix = substitute(P, [1])
        bad_proof = RationalPSDProof(:principal_minors,
                                     bad_matrix,
                                     PrincipalMinorProof[PrincipalMinorProof([1], 1 // 1),
                                                         PrincipalMinorProof([2], 1 // 1),
                                                         PrincipalMinorProof([1, 2],
                                                                             -3 // 1)])
        bad_without_hash = RationalCertificate(P, Rational{BigInt}[1 // 1], bad_proof, "")
        bad = RationalCertificate(P, Rational{BigInt}[1 // 1], bad_proof,
                                  rational_certificate_hash(bad_without_hash))

        output = IOBuffer()
        @test !verify(bad; io=output)
        text = String(take!(output))
        @test occursin("[OK] principal-minor proof matches recomputation", text)
        @test occursin("[FAIL] all principal minors are nonnegative", text)
    end

    @testset "CLI verify command" begin
        cert = sample_rational_certificate()
        path = tempname() * ".json"
        save_certificate(path, cert)

        root = normpath(joinpath(@__DIR__, "..", ".."))
        cli = joinpath(root, "bin", "certsdp")
        output = read(`$cli verify $path`, String)

        @test occursin("[OK] certificate accepted", output)
    end
end
