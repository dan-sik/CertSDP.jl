using JSON3

@testset "Multi-block certification" begin
    function multiblock_cli(args...)
        out = IOBuffer()
        err = IOBuffer()
        code = CertSDP.main(collect(String.(args)); io=out, err=err)
        return (; code, out=String(take!(out)), err=String(take!(err)))
    end

    function multiblock_solution_file(x)
        path = tempname() * ".json"
        rational_text = [denominator(value) == 1 ? string(numerator(value)) :
                         string(numerator(value), "/", denominator(value))
                         for value in Rational{BigInt}.(x)]
        write(path,
              JSON3.write((;
                           certsdp_version="0.1",
                           solution=(;
                                     type=RATIONAL_SOLUTION_TYPE,
                                     x=rational_text,),)))
        return path
    end

    function multiblock_certify_from_problem(P, x; method=:auto)
        result = certify(P, Rational{BigInt}.(x); psd_method=method)
        @test iscertified(result)
        cert = certificate(result)
        @test cert isa BlockRationalCertificate
        @test verify(cert)
        @test verify(cert; strict=true)
        return cert
    end

    function multiblock_algebraic_problem()
        return BlockLMIProblem([LMIProblem([0 1; 1 0],
                                           [[1//1 0//1; 0//1 1//2]];
                                           vars=[:x]),
                                LMIProblem([1;;], [[0;;]]; vars=[:x])])
    end

    @testset "BlockLMIProblem v1 JSON schema roundtrip" begin
        P = read_problem(joinpath(@__DIR__, "..", "..", "examples", "sdpa",
                                  "two_blocks.dat-s"))
        path = tempname() * ".json"

        @test write_problem(path, P) == path
        json = read(path, String)
        @test occursin("\"type\": \"block_lmi_feasibility\"", json)
        @test validate_problem_schema(json)
        @test validate_block_problem_schema(json)
        loaded = read_problem(path)
        @test loaded isa BlockLMIProblem
        @test block_lmi_problem_hash(loaded) == block_lmi_problem_hash(P)
    end

    @testset "foundational SDPA/JuMP-style multi-block examples certify" begin
        examples_dir = joinpath(@__DIR__, "..", "..", "examples", "sdpa")
        fixtures = [("sdpa_two_blocks",
                     read_problem(joinpath(examples_dir,
                                           "two_blocks.dat-s")),
                     [0, 0]),
                    ("sdpa_mixed_blocks_decimal",
                     read_problem(joinpath(examples_dir,
                                           "mixed_blocks_decimal.dat-s")),
                     [0, 0, 0]),
                    ("manual_three_blocks",
                     BlockLMIProblem([LMIProblem([1 0; 0 1], [[1 0; 0 0], [0 0; 0 1]];
                                                 vars=[:x, :y]),
                                      LMIProblem([2 1; 1 2], [[0 0; 0 0], [1 0; 0 0]];
                                                 vars=[:x, :y]),
                                      LMIProblem([3;;], [[1;;], [-1;;]]; vars=[:x, :y])]),
                     [0, 0]),
                    ("jump_like_two_blocks",
                     BlockLMIProblem([LMIProblem([1 0; 0 3], [[1 0; 0 -1], [0 1; 1 0]];
                                                 vars=[:x1, :x2]),
                                      LMIProblem([2 0; 0 1], [[0 0; 0 1], [-1 0; 0 0]];
                                                 vars=[:x1, :x2])];
                                     metadata=Dict(:source_format => "jump_moi",
                                                   :source => "multiblock_test")),
                     [0, 0]),
                    ("schur_zero_blocks",
                     BlockLMIProblem([LMIProblem([1 0; 0 0], [[0 0; 0 0]]; vars=[:x]),
                                      LMIProblem([2 1 2; 1 2 1; 2 1 2],
                                                 [[0 0 0; 0 0 0; 0 0 0]];
                                                 vars=[:x])]),
                     [0])]

        certified = 0
        for (name, P, x) in fixtures
            cert = multiblock_certify_from_problem(P, x;
                                                   method=name == "schur_zero_blocks" ?
                                                          :auto : :principal_minors)
            @test num_blocks(cert.problem) >= 2
            @test cert.psd_proof.method === :blockwise
            @test all(proof.method in (:principal_minors, :schur_zero, :ldl)
                      for proof in cert.psd_proof.block_proofs)
            certified += 1
        end
        @test certified >= 5
    end

    @testset "blockwise certificate JSON, strict verify, and inspect" begin
        P = read_problem(joinpath(@__DIR__, "..", "..", "examples", "sdpa",
                                  "two_blocks.dat-s"))
        cert = multiblock_certify_from_problem(P, [0, 0]; method=:principal_minors)
        cert_path = tempname() * ".json"
        @test write_certificate(cert_path, cert) == cert_path

        json = read(cert_path, String)
        @test validate_certificate_schema(json)
        loaded = read_certificate(cert_path)
        @test loaded isa BlockRationalCertificate
        @test verify(loaded; strict=true)

        inspect = multiblock_cli("inspect", cert_path)
        @test inspect.code == 0
        @test occursin("block_rational_psd_certificate", inspect.out)
        @test occursin("Blocks: 2", inspect.out)
        @test occursin("Block 1 PSD proof", inspect.out)

        strict = multiblock_cli("verify", "--strict", cert_path)
        @test strict.code == 0
        @test occursin("blockwise certificate accepted", strict.out)
    end

    @testset "CLI multi-block certify supports SDPA input" begin
        problem_path = joinpath(@__DIR__, "..", "..", "examples", "sdpa",
                                "two_blocks.dat-s")
        solution_path = multiblock_solution_file([0 // 1, 0 // 1])
        cert_path = tempname() * ".json"

        certify_result = multiblock_cli("certify", problem_path,
                                        "--solution", solution_path,
                                        "--out", cert_path,
                                        "--psd-method", "principal_minors")
        @test certify_result.code == 0
        @test occursin("blockwise certificate accepted", certify_result.out)

        verify_result = multiblock_cli("verify", "--strict", cert_path)
        @test verify_result.code == 0
        @test occursin("block 2 PSD verified", verify_result.out)
    end

    @testset "multi-block algebraic incidence certifies through aggregate and replays blockwise" begin
        if !has_msolve()
            @test_skip "msolve binary is not installed"
        else
            P = multiblock_algebraic_problem()
            approx = ApproxSolution(P, [sqrt(big(2))];
                                    precision_bits=256,
                                    relative_tolerance="1e-12",
                                    gap_threshold="1e4")

            result = certify(P, approx; msolve_precision=128, msolve_threads=1)

            @test result isa CertifiedResult
            cert = certificate(result)
            @test cert isa BlockAlgebraicCertificate
            @test cert.root.f == parse_polynomial("t^2 - 2")
            @test cert.solution[1] == AlgebraicElement(cert.root, "t")
            @test verify(cert)
            @test verify(cert; strict=true)
            @test validate_certificate_schema(certificate_json_v1_string(cert))
        end
    end

    @testset "CLI multi-block algebraic certify accepts approximate solution" begin
        if !has_msolve()
            @test_skip "msolve binary is not installed"
        else
            P = multiblock_algebraic_problem()
            problem_path = tempname() * ".json"
            write_problem(problem_path, P)
            approx = ApproxSolution(P, [sqrt(big(2))];
                                    precision_bits=256,
                                    relative_tolerance="1e-12",
                                    gap_threshold="1e4")
            approx_path = tempname() * ".json"
            CertSDP.write_approx_solution_json(approx_path, approx)
            cert_path = tempname() * ".json"

            certify_result = multiblock_cli("certify", problem_path,
                                            "--solution", approx_path,
                                            "--out", cert_path)

            @test certify_result.code == 0
            loaded = read_certificate(cert_path)
            @test loaded isa BlockAlgebraicCertificate
            @test verify(loaded; strict=true)
        end
    end

    @testset "fake block certificate rejection localizes block and minor" begin
        P = BlockLMIProblem([LMIProblem([1 0; 0 1], [[0 0; 0 0]]; vars=[:x]),
                             LMIProblem([1 2; 2 1], [[0 0; 0 0]]; vars=[:x])])
        good_first_block = rational_psd_proof(substitute(P.blocks[1], [0]);
                                              method=:principal_minors)
        bad_matrix = substitute(P.blocks[2], [0])
        bad_second_block = RationalPSDProof(:principal_minors,
                                            bad_matrix,
                                            CertSDP._principal_minor_proofs_rational(bad_matrix))
        bad_block_proofs = [good_first_block, bad_second_block]
        fake_proof = BlockRationalPSDProof(bad_block_proofs)
        fake_without_hash = BlockRationalCertificate(P, Rational{BigInt}[0], fake_proof, "")
        fake = BlockRationalCertificate(P, Rational{BigInt}[0], fake_proof,
                                        block_rational_certificate_hash(fake_without_hash))

        out = IOBuffer()
        @test !verify(fake; io=out)
        text = String(take!(out))
        @test occursin("block 2: principal_minors minor at indices [1, 2]", text)
    end

    @testset "negative PSD block reports block, method, and failed minor" begin
        blocks = Any[[1//1 0//1; 0//1 1//1],
                     [1//1 2//1; 2//1 1//1]]
        plan = choose_psd_proof(blocks; method=:blockwise,
                                block_method=:principal_minors)
        @test plan.status === :rejected
        @test plan.failure.block_index == 2
        @test plan.failure.method === :principal_minors
        @test plan.failure.location === :minor
        @test plan.failure.indices == [1, 2]
        @test occursin("block 2",
                       CertSDP._failure_message(PSDVerificationResult(false,
                                                                      plan.method,
                                                                      plan.failure)))
    end

    @testset "larger total block dimension 15-30 verifies and fails clearly" begin
        good_blocks = [LMIProblem([i == j ? 1 : 0 for i in 1:dim, j in 1:dim],
                                  [zeros(Int, dim, dim)];
                                  vars=[:x])
                       for dim in (5, 7, 6)]
        good = BlockLMIProblem(good_blocks)
        good_cert = multiblock_certify_from_problem(good, [0]; method=:ldl)
        @test matrix_size(good) == 18
        @test verify(good_cert; strict=true)

        bad_blocks = Any[Rational{BigInt}[i == j ? 1 : 0 for i in 1:8, j in 1:8],
                         Rational{BigInt}[i == j ? 1 : 0 for i in 1:7, j in 1:7]]
        bad_blocks[2][3, 3] = -1
        plan = choose_psd_proof(bad_blocks; method=:blockwise,
                                block_method=:principal_minors,
                                max_size=10)
        @test plan.status === :rejected
        @test plan.failure.block_index == 2
        @test plan.failure.location === :minor
        @test plan.failure.indices == [3]
    end

    @testset "validation metadata includes multi-block examples" begin
        suite_root = normpath(joinpath(@__DIR__, "..", "..", "benchmarks"))
        cases = benchmark_cases(suite_root; subset=:validation)
        names = Set(case.name for case in cases)
        @test "validation__multiblock_dense_dim60_n20" in names
        @test "validation__multiblock_sdpa_two_blocks" in names
        @test count(case -> occursin("multi_block", case.expected.category), cases) >= 2
    end
end
