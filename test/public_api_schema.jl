@testset "Public API and schema hard freeze" begin
    public_api = Set([:LMIProblem,
                      :BlockLMIProblem,
                      :certify,
                      :verify,
                      :diagnose,
                      :read_problem,
                      :write_problem,
                      :read_certificate,
                      :write_certificate,
                      :certify_sos,
                      :verify_sos,
                      :export_sos_decomposition,
                      :sos_decomposition_text,
                      :sos_decomposition_latex,
                      :sos_decomposition_sage,
                      :sos_decomposition_julia])

    @testset "only hard-frozen API names are exported" begin
        @test Set(names(CertSDP)) == union(public_api, Set([:CertSDP]))

        sandbox = Module(:CertSDPPublicSmoke)
        Core.eval(sandbox, :(using CertSDP))
        for name in public_api
            @test isdefined(sandbox, name)
        end

        for internal in (:RationalCertificate,
                         :AlgebraicCertificate,
                         :CertifiedResult,
                         :FailureResult,
                         :read_sdpa,
                         :write_sdpa,
                         :extract_lmi,
                         :solve_approximately,
                         :validate_problem_schema,
                         :migrate_problem_json)
            @test isdefined(CertSDP, internal)
            @test !isdefined(sandbox, internal)
            @test internal ∉ names(CertSDP)
        end
    end

    @testset "legacy v0.1 problem examples read and migrate through public boundary" begin
        repo_root = normpath(joinpath(@__DIR__, ".."))
        examples = [joinpath(repo_root, "examples", "rational_problem.json"),
                    joinpath(repo_root, "examples", "algebraic_problem.json"),
                    joinpath(repo_root, "examples", "lmi_basic.json"),
                    joinpath(repo_root, "benchmarks", "validation", "rational_pd_2x2",
                             "problem.json"),
                    joinpath(repo_root, "benchmarks", "validation",
                             "rank_deficient_kernel_3x3", "problem.json")]

        for path in examples
            P = read_problem(path)
            @test P isa LMIProblem

            migrated_path = tempname() * ".json"
            @test write_problem(migrated_path, P) == migrated_path
            migrated_json = read(migrated_path, String)
            @test occursin("\"certsdp_problem_version\": \"1.0\"", migrated_json)
            @test validate_problem_schema(migrated_json)
            @test CertSDP.lmi_problem_hash(read_problem(migrated_path)) ==
                  CertSDP.lmi_problem_hash(P)
        end
    end

    @testset "legacy v0.1 LMI certificates read, verify, and migrate" begin
        P = read_problem(joinpath(@__DIR__, "..", "examples", "rational_problem.json"))
        result = certify(P, [1 // 2, 1 // 3])
        @test iscertified(result)
        @test verify(result)

        public_result_path = tempname() * ".json"
        @test write_certificate(public_result_path, result) == public_result_path
        @test verify(read_certificate(public_result_path))
        @test validate_certificate_schema(read(public_result_path, String))

        legacy_cert = RationalCertificate(P, [1 // 2, 1 // 3])
        legacy_path = tempname() * ".json"
        write(legacy_path, rational_certificate_json_string(legacy_cert))

        loaded = read_certificate(legacy_path)
        @test verify(loaded)

        v1_path = tempname() * ".json"
        @test write_certificate(v1_path, loaded) == v1_path
        v1_json = read(v1_path, String)
        @test validate_certificate_schema(v1_json)
        @test verify(read_certificate(v1_path))
        @test occursin("\"certsdp_certificate_version\": \"1.0\"", v1_json)
    end

    @testset "legacy SOS example remains certifiable through public SOS entry" begin
        repo_root = normpath(joinpath(@__DIR__, ".."))
        problem_path = joinpath(repo_root, "examples", "sos", "gram_x2_plus_1.json")
        result = certify_sos(problem_path, [1 0; 0 1])

        @test iscertified(result)
        @test verify_sos(result)

        cert_path = tempname() * ".json"
        @test write_certificate(cert_path, result) == cert_path
        loaded = read_certificate(cert_path)
        @test verify_sos(loaded)
        @test validate_certificate_schema(read(cert_path, String))
    end

    @testset "schema docs are sufficient and API docs exclude internals from contract" begin
        repo_root = normpath(joinpath(@__DIR__, ".."))
        api_text = read(joinpath(repo_root, "docs", "API_STABILITY.md"), String)
        schema_text = read(joinpath(repo_root, "docs", "SCHEMA_V1.md"), String)

        for public_name in public_api
            @test occursin("`$(String(public_name))", api_text)
        end

        @test occursin("Only these names are covered", api_text)
        @test occursin("not part of the compatibility contract", api_text)
        @test !occursin("- `read_sdpa", api_text)
        @test !occursin("- `extract_lmi", api_text)

        for field in ("certsdp_problem_version",
                      "certsdp_certificate_version",
                      "certsdp_failure_report_version",
                      "certificate_type",
                      "problem_hash",
                      "root_interval",
                      "coefficient_matching",
                      "provenance")
            @test occursin(field, schema_text)
        end

        @test occursin("Canonical Hashes", schema_text)
        @test occursin("v0.1 Compatibility", schema_text)
    end
end
