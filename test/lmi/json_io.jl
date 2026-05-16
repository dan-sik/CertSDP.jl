@testset "LMI JSON input/output" begin
    A0 = [1 0; 0 2//3]
    A1 = [0 3//5; 3//5 0]
    A2 = [-2 0; 0 1//7]
    P = LMIProblem(A0, [A1, A2]; vars=[:x, :y])

    @testset "JSON roundtrip" begin
        json = lmi_problem_json_string(P)
        parsed = parse_lmi_json(json)

        @test parsed.vars == P.vars
        @test rational_matrix(parsed.A0) == rational_matrix(P.A0)
        @test rational_matrix(parsed.A[1]) == rational_matrix(P.A[1])
        @test rational_matrix(parsed.A[2]) == rational_matrix(P.A[2])
        @test lmi_problem_json(parsed).problem.hash == lmi_problem_hash(P)
        @test occursin("\"3/5\"", json)
        @test occursin("\"-2\"", json)
    end

    @testset "read and write paths" begin
        path = tempname() * ".json"
        write_lmi_json(path, P)
        parsed = read_lmi_json(path)

        @test rational_matrix(parsed.A0) == rational_matrix(P.A0)
        @test parsed.vars == [:x, :y]
    end

    @testset "example file parses" begin
        example = read_lmi_json(joinpath(@__DIR__, "..", "..", "examples",
                                         "lmi_basic.json"))

        @test lmi_problem_hash(example) == lmi_problem_hash(P)
        @test rational_matrix(example.A0) == rational_matrix(P.A0)
        @test example.vars == P.vars
    end

    @testset "invalid JSON formats are rejected" begin
        @test_throws ArgumentError parse_lmi_json("{}")
        @test_throws ArgumentError parse_lmi_json("""
        {
            "certsdp_version": "0.1",
            "problem": {
                "type": "wrong_type",
                "field": "QQ",
                "matrix_size": 1,
                "num_variables": 0,
                "vars": [],
                "A0": [["1"]],
                "A": []
            }
        }
        """)
        @test_throws ArgumentError parse_lmi_json("""
        {
            "certsdp_version": "0.1",
            "problem": {
                "type": "lmi_feasibility",
                "field": "QQ",
                "matrix_size": 1,
                "num_variables": 0,
                "vars": [],
                "A0": [["1/0"]],
                "A": []
            }
        }
        """)
        @test_throws ArgumentError parse_lmi_json("""
        {
            "certsdp_version": "0.1",
            "problem": {
                "type": "lmi_feasibility",
                "field": "QQ",
                "matrix_size": 1,
                "num_variables": 0,
                "vars": [],
                "A0": [[1]],
                "A": []
            }
        }
        """)
        @test_throws ArgumentError parse_lmi_json("""
        {
            "certsdp_version": "0.1",
            "problem": {
                "type": "lmi_feasibility",
                "field": "QQ",
                "matrix_size": 2,
                "num_variables": 0,
                "vars": [],
                "A0": [["1", "2"], ["3", "4"]],
                "A": []
            }
        }
        """)
    end

    @testset "problem hash is stable" begin
        hash = lmi_problem_hash(P)

        reordered_json = """
        {
            "problem": {
                "hash": "$hash",
                "A": [
                    [["0", "3/5"], ["3/5", "0"]],
                    [["-2", "0"], ["0", "1/7"]]
                ],
                "vars": ["x", "y"],
                "num_variables": 2,
                "matrix_size": 2,
                "A0": [["1", "0"], ["0", "2/3"]],
                "field": "QQ",
                "type": "lmi_feasibility"
            },
            "certsdp_version": "0.1"
        }
        """

        parsed = parse_lmi_json(reordered_json)
        @test lmi_problem_hash(parsed) == hash

        tampered_json = replace(reordered_json,
                                "\"hash\": \"$hash\"" => "\"hash\": \"sha256:00\"")
        @test_throws ArgumentError parse_lmi_json(tampered_json)

        same_problem = LMIProblem([1//1 0//1; 0//1 2//3],
                                  [[0//1 3//5; 3//5 0//1], [-2//1 0//1; 0//1 1//7]];
                                  vars=[:x, :y])
        @test lmi_problem_hash(same_problem) == hash
    end
end
