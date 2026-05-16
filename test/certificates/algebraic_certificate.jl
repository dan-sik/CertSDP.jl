@testset "Type A algebraic certificates" begin
    function sqrt2_toy_certificate()
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        P = LMIProblem([0 1; 1 0],
                       [[1 0; 0 1]];
                       vars=[:x],)
        return AlgebraicCertificate(P, root, [alpha])
    end

    function schur_zero_toy_certificate()
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        P = LMIProblem([0 0 1
                        0 1 -1
                        1 -1 3],
                       [[1 0 0
                         0 0 1
                         0 1 -3//2]];
                       vars=[:x],)
        return AlgebraicCertificate(P, root, [alpha]; psd_method=:schur_zero,
                                    pivot_block=[1, 2])
    end

    @testset "sqrt(2) toy LMI verifies without floating point" begin
        cert = sqrt2_toy_certificate()

        @test cert.solution[1] == AlgebraicElement(cert.root, "t")
        @test verify_psd_algebraic(substitute(cert.problem, cert.solution))
        @test cert.hash == algebraic_certificate_hash(cert)
        @test verify(cert)

        output = IOBuffer()
        @test verify(cert; io=output)
        text = String(take!(output))
        @test occursin("[OK] substituted matrix matches algebraic solution", text)
        @test occursin("[OK] algebraic root interval isolates one real root", text)
        @test occursin("[OK] PSD verified over QQ(alpha)", text)
        @test occursin("[OK] certificate accepted", text)
    end

    @testset "save/load JSON roundtrip" begin
        cert = sqrt2_toy_certificate()
        path = tempname() * ".json"

        save_certificate(path, cert)
        loaded = load_certificate(path)

        @test loaded isa AlgebraicCertificate
        @test loaded.hash == cert.hash
        @test loaded.root == cert.root
        @test loaded.solution == cert.solution
        @test lmi_problem_hash(loaded.problem) == lmi_problem_hash(cert.problem)
        @test CertSDP._algebraic_matrices_equal(loaded.psd_proof.matrix,
                                                cert.psd_proof.matrix)
        @test verify(loaded)
        @test verify(path)
    end

    @testset "Schur-zero certificate JSON verifies and roundtrips" begin
        cert = schur_zero_toy_certificate()
        path = tempname() * ".json"

        @test cert.psd_proof.method === :schur_zero
        @test cert.psd_proof.schur_zero.pivot_block == [1, 2]
        @test length(cert.psd_proof.schur_zero.positive_block_minors) == 2
        @test isempty(cert.psd_proof.principal_minors)
        @test verify(cert)

        json_object = algebraic_certificate_json(cert)
        @test json_object.psd_proof.method == "schur_zero"
        @test json_object.psd_proof.pivot_block == [1, 2]
        @test json_object.psd_proof.positive_block.proof ==
              "sylvester_principal_minors_positive"
        @test json_object.psd_proof.schur_complement.status == "zero"

        output = IOBuffer()
        @test verify(cert; io=output)
        text = String(take!(output))
        @test occursin("[OK] Schur-zero proof matches recomputation", text)
        @test occursin("[OK] pivot block is certified positive definite", text)
        @test occursin("[OK] Schur complement is exact zero", text)
        @test occursin("[OK] Schur-zero PSD verified over QQ(alpha)", text)

        save_certificate(path, cert)
        loaded = load_certificate(path)
        @test loaded.psd_proof.method === :schur_zero
        @test loaded.psd_proof.schur_zero.pivot_block == [1, 2]
        @test CertSDP._schur_zero_proofs_equal(loaded.psd_proof.schur_zero,
                                               cert.psd_proof.schur_zero)
        @test verify(loaded)
    end

    @testset "tampered algebraic coordinate is rejected by hash" begin
        cert = sqrt2_toy_certificate()
        json = algebraic_certificate_json_string(cert)
        tampered_json = replace(json, "\"x\": \"t\"" => "\"x\": \"1\""; count=1)
        tampered = parse_certificate_json(tampered_json)

        output = IOBuffer()
        @test !verify(tampered; io=output)
        @test occursin("[FAIL] certificate hash matches", String(take!(output)))
    end

    @testset "fake proof with matching hash is rejected" begin
        cert = sqrt2_toy_certificate()
        root = cert.root
        fake_matrix = [AlgebraicElement(root, "2") AlgebraicElement(root, "0")
                       AlgebraicElement(root, "0") AlgebraicElement(root, "2")]
        fake_proof = AlgebraicPSDProof(:principal_minors, fake_matrix,
                                       algebraic_psd_proof(fake_matrix).principal_minors)
        fake_without_hash = AlgebraicCertificate(cert.problem, cert.root, cert.solution,
                                                 fake_proof, "")
        fake = AlgebraicCertificate(cert.problem, cert.root, cert.solution, fake_proof,
                                    algebraic_certificate_hash(fake_without_hash))

        output = IOBuffer()
        @test !verify(fake; io=output)
        text = String(take!(output))
        @test occursin("[OK] certificate hash matches", text)
        @test occursin("[FAIL] substituted matrix matches algebraic solution", text)
    end

    @testset "fake Schur-zero proof with matching hash is rejected" begin
        cert = schur_zero_toy_certificate()
        root = cert.root
        good_schur = cert.psd_proof.schur_zero
        fake_minors = copy(good_schur.positive_block_minors)
        fake_minors[1] = PrincipalMinorProof([1], AlgebraicElement(root, "1"))
        fake_schur = SchurZeroProof{AlgebraicElement}(good_schur.pivot_block,
                                                      fake_minors,
                                                      good_schur.schur_complement)
        fake_proof = AlgebraicPSDProof(:schur_zero,
                                       cert.psd_proof.matrix,
                                       PrincipalMinorProof{AlgebraicElement}[],
                                       fake_schur)
        fake_without_hash = AlgebraicCertificate(cert.problem, cert.root, cert.solution,
                                                 fake_proof, "")
        fake = AlgebraicCertificate(cert.problem, cert.root, cert.solution, fake_proof,
                                    algebraic_certificate_hash(fake_without_hash))

        output = IOBuffer()
        @test !verify(fake; io=output)
        text = String(take!(output))
        @test occursin("[OK] certificate hash matches", text)
        @test occursin("[FAIL] Schur-zero positive-block minors match recomputation",
                       text)
    end

    @testset "algebraic LDL certificates reject fake pivots" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        P = LMIProblem([0 0; 0 1],
                       [[1 0; 0 0]];
                       vars=[:x],)
        cert = AlgebraicCertificate(P, root, [alpha]; psd_method=:ldl)
        @test cert.psd_proof.method === :ldl
        @test verify(cert)

        fake_pivots = copy(cert.psd_proof.ldl.pivots)
        fake_pivots[1] = LDLPivotProof(1, AlgebraicElement(root, "1"), :positive)
        fake_proof = AlgebraicPSDProof(:ldl,
                                       cert.psd_proof.matrix,
                                       PrincipalMinorProof{AlgebraicElement}[],
                                       nothing,
                                       LDLProof(fake_pivots))
        fake_without_hash = AlgebraicCertificate(P, root, [alpha], fake_proof, "")
        fake = AlgebraicCertificate(P, root, [alpha], fake_proof,
                                    algebraic_certificate_hash(fake_without_hash))

        output = IOBuffer()
        @test !verify(fake; io=output)
        text = String(take!(output))
        @test occursin("[OK] certificate hash matches", text)
        @test occursin("[FAIL] LDL proof matches recomputation", text)
    end

    @testset "nonzero Schur complement is rejected even with matching hash" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        P = LMIProblem([0 0 1
                        0 1 -1
                        1 -1 4],
                       [[1 0 0
                         0 0 1
                         0 1 -3//2]];
                       vars=[:x],)
        bad_matrix = substitute(P, [alpha])
        bad_proof = CertSDP._schur_zero_psd_proof_unchecked(bad_matrix, [1, 2])
        bad_without_hash = AlgebraicCertificate(P, root, [alpha], bad_proof, "")
        bad = AlgebraicCertificate(P, root, [alpha], bad_proof,
                                   algebraic_certificate_hash(bad_without_hash))

        output = IOBuffer()
        @test !verify(bad; io=output)
        text = String(take!(output))
        @test occursin("[OK] Schur-zero proof matches recomputation", text)
        @test occursin("[FAIL] Schur complement is exact zero", text)
    end

    @testset "non-PSD algebraic fake certificate is rejected even with matching hash" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        P = LMIProblem([0 2; 2 0],
                       [[1 0; 0 1]];
                       vars=[:x],)
        bad_matrix = substitute(P, [alpha])
        bad_proof = AlgebraicPSDProof(:principal_minors,
                                      bad_matrix,
                                      [PrincipalMinorProof([1], alpha),
                                       PrincipalMinorProof([2], alpha),
                                       PrincipalMinorProof([1, 2], alpha^2 - 4)])
        bad_without_hash = AlgebraicCertificate(P, root, [alpha], bad_proof, "")
        bad = AlgebraicCertificate(P, root, [alpha], bad_proof,
                                   algebraic_certificate_hash(bad_without_hash))

        output = IOBuffer()
        @test !verify(bad; io=output)
        text = String(take!(output))
        @test occursin("[OK] principal-minor proof matches recomputation", text)
        @test occursin("[FAIL] all principal minors are certified nonnegative", text)
    end

    @testset "fake root interval is rejected even when hash matches" begin
        cert = sqrt2_toy_certificate()
        bad_root = AlgebraicRoot("t^2 - 2", "-2", "2")
        bad_solution = [AlgebraicElement(bad_root, "t")]
        bad_matrix = [AlgebraicElement(bad_root, "t") AlgebraicElement(bad_root, "1")
                      AlgebraicElement(bad_root, "1") AlgebraicElement(bad_root, "t")]
        bad_proof = AlgebraicPSDProof(:principal_minors,
                                      bad_matrix,
                                      [PrincipalMinorProof([1],
                                                           AlgebraicElement(bad_root, "t")),
                                       PrincipalMinorProof([2],
                                                           AlgebraicElement(bad_root, "t")),
                                       PrincipalMinorProof([1, 2],
                                                           AlgebraicElement(bad_root, "1"))])
        bad_without_hash = AlgebraicCertificate(cert.problem, bad_root, bad_solution,
                                                bad_proof, "")
        bad = AlgebraicCertificate(cert.problem, bad_root, bad_solution, bad_proof,
                                   algebraic_certificate_hash(bad_without_hash))

        output = IOBuffer()
        @test !verify(bad; io=output)
        text = String(take!(output))
        @test occursin("[OK] certificate hash matches", text)
        @test occursin("[FAIL] algebraic root interval isolates one real root", text)
    end

    @testset "CLI verify command accepts Type A certificates" begin
        cert = sqrt2_toy_certificate()
        path = tempname() * ".json"
        save_certificate(path, cert)

        root = normpath(joinpath(@__DIR__, "..", ".."))
        cli = joinpath(root, "bin", "certsdp")
        output = read(`$cli verify $path`, String)

        @test occursin("[OK] PSD verified over QQ(alpha)", output)
        @test occursin("[OK] certificate accepted", output)
    end
end
