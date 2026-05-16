using SHA: sha256

function temp_sdpa(problem::LMIProblem)
    path = tempname() * ".dat-s"
    write_sdpa(problem, path)
    return path
end

@testset "SDPA sparse import/export" begin
    examples_dir = joinpath(@__DIR__, "..", "..", "examples", "sdpa")
    example_files = ["single_block.dat-s",
                     "two_blocks.dat-s",
                     "diagonal_block.dat-s",
                     "mixed_blocks_decimal.dat-s",
                     "empty_variable_matrices.dat-s"]

    @testset "examples roundtrip with stable hashes" begin
        for file in example_files
            path = joinpath(examples_dir, file)
            problem = read_sdpa(path)
            out = tempname() * ".dat-s"

            @test problem isa BlockLMIProblem
            @test write_sdpa(problem, out) == out

            reparsed = read_sdpa(out)
            @test block_lmi_problem_hash(reparsed) == block_lmi_problem_hash(problem)
            @test sdpa_string(reparsed) == read(out, String)
            @test bytes2hex(sha256(sdpa_string(reparsed))) ==
                  bytes2hex(sha256(read(out, String)))
        end
    end

    @testset "single PSD block bridges to existing LMIProblem core" begin
        problem = read_sdpa(joinpath(examples_dir, "single_block.dat-s"))
        block = single_lmi_problem(problem)

        @test num_blocks(problem) == 1
        @test block isa LMIProblem
        @test block.vars == [:x1, :x2]
        @test rational_matrix(block.A0) == Rational{BigInt}[1 0; 0 1]
        @test rational_matrix(block.A[1]) == Rational{BigInt}[1 1//2; 1//2 0]
        @test rational_matrix(block.A[2]) == Rational{BigInt}[0 0; 0 3]
        @test lmi_problem_hash(block) ==
              lmi_problem_hash(single_lmi_problem(read_sdpa(temp_sdpa(block))))
    end

    @testset "multiple PSD and diagonal blocks stay block structured" begin
        problem = read_sdpa(joinpath(examples_dir, "mixed_blocks_decimal.dat-s"))

        @test num_blocks(problem) == 2
        @test block_struct(problem) == [2, -2]
        @test problem.objective == Rational{BigInt}[1 // 2, -5 // 4, 1 // 50]
        @test rational_matrix(problem.blocks[1].A0) ==
              Rational{BigInt}[3//2 0; 0 5//2]
        @test rational_matrix(problem.blocks[1].A[1]) ==
              Rational{BigInt}[1//4 -1//8; -1//8 0]
        @test rational_matrix(problem.blocks[2].A0) ==
              Rational{BigInt}[3 0; 0 4]
        @test rational_matrix(problem.blocks[2].A[2]) ==
              Rational{BigInt}[0 0; 0 -1//5]
        @test_throws ArgumentError single_lmi_problem(problem)
    end

    @testset "decimal spelling and sparse row order are canonicalized" begin
        a = parse_sdpa("""
        2 = mDIM
        1 = nBLOCK
        2 = bLOCKsTRUCT
        0.50, -1.250
        0 1 1 1 -1.0
        0 1 2 2 -2.00
        1 1 1 2 0.1250
        2 1 2 2 1e-1
        """)

        b = parse_sdpa("""
        "same problem with a different order"
        2
        1
        2
        1/2 -5/4
        2 1 2 2 1/10
        0 1 2 2 -2
        1 1 2 1 1/8
        0 1 1 1 -1
        """)

        @test block_lmi_problem_hash(a) == block_lmi_problem_hash(b)
        @test sdpa_string(a) == sdpa_string(b)
    end

    @testset "read_problem and write_problem dispatch on SDPA paths" begin
        source = joinpath(examples_dir, "two_blocks.dat-s")
        problem = read_problem(source)
        path = tempname() * ".dat-s"

        @test problem isa BlockLMIProblem
        @test write_problem(path, problem) == path
        @test block_lmi_problem_hash(read_problem(path)) == block_lmi_problem_hash(problem)

        single = single_lmi_problem(read_sdpa(joinpath(examples_dir, "single_block.dat-s")))
        single_path = tempname() * ".dat-s"
        @test write_problem(single_path, single) == single_path
        @test num_blocks(read_problem(single_path)) == 1
    end

    @testset "malformed SDPA inputs have clear errors" begin
        @test_throws ArgumentError parse_sdpa("""
        1
        1
        1
        0
        0 1 1
        """)

        @test_throws ArgumentError parse_sdpa("""
        1
        1
        1
        0
        2 1 1 1 1
        """)

        @test_throws ArgumentError parse_sdpa("""
        1
        1
        -2
        0
        0 1 1 2 1
        """)

        @test_throws ArgumentError parse_sdpa("""
        1
        1
        1
        0
        0 1 1 1 1/0
        """)

        @test_throws ArgumentError parse_sdpa("""
        1
        1
        1
        0
        0 1 1 1 1.2.3
        """)
    end
end
