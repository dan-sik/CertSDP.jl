using JSON3: JSON3

@testset "API freeze and schema v1.0" begin
    function schema_v1_problem()
        return LMIProblem([1 0; 0 1],
                          [[1 0; 0 0],
                           [0 0; 0 1]];
                          vars=[:x, :y],)
    end

    function schema_v1_algebraic_certificate()
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        P = LMIProblem([0 1; 1 0],
                       [[1 0; 0 1]];
                       vars=[:x],)
        return AlgebraicCertificate(P, root, [alpha])
    end

    @testset "Public API names remain defined" begin
        public_names = [:LMIProblem,
                        :BlockLMIProblem,
                        :certify,
                        :verify,
                        :diagnose,
                        :read_problem,
                        :write_problem,
                        :read_certificate,
                        :write_certificate,
                        :certify_sos,
                        :verify_sos]

        for name in public_names
            @test isdefined(CertSDP, name)
        end

        internal_names = [:read_sdpa,
                          :write_sdpa,
                          :extract_lmi,
                          :AlgebraicBackend,
                          :MsolveBackend,
                          :solve_system]
        exported_names = Set(names(CertSDP))
        for name in internal_names
            @test isdefined(CertSDP, name)
            @test name ∉ exported_names
        end
    end

    @testset "problem schema v1.0 writes, validates, reads, and migrates" begin
        P = schema_v1_problem()
        path = tempname() * ".json"

        @test write_problem(path, P) == path
        json = read(path, String)
        @test occursin("\"certsdp_problem_version\": \"1.0\"", json)
        @test occursin("\"variables\"", json)
        @test occursin("\"var\": \"x\"", json)
        @test validate_problem_schema(json)

        parsed = read_problem(path)
        @test lmi_problem_hash(parsed) == lmi_problem_hash(P)
        @test parsed.vars == P.vars

        old_json = lmi_problem_json_string(P)
        migrated = migrate_problem_json(old_json)
        @test validate_problem_schema(migrated)
        @test lmi_problem_hash(parse_problem_json(migrated)) == lmi_problem_hash(P)
        @test lmi_problem_hash(read_problem(joinpath(@__DIR__, "..", "examples",
                                                     "rational_problem.json"))) ==
              lmi_problem_hash(P)
    end

    @testset "problem schema rejects malformed v1.0 JSON" begin
        P = schema_v1_problem()
        valid = CertSDP.problem_json_v1_string(P)

        missing_version = replace(valid,
                                  "\"certsdp_problem_version\": \"1.0\",\n" => "";
                                  count=1)
        @test_throws ArgumentError validate_problem_schema(missing_version)

        wrong_var = replace(valid, "\"var\": \"x\"" => "\"var\": \"z\""; count=1)
        @test_throws ArgumentError validate_problem_schema(wrong_var)

        tampered_hash = replace(valid,
                                lmi_problem_hash(P) => "sha256:" * repeat("0", 64);
                                count=1)
        @test_throws ArgumentError validate_problem_schema(tampered_hash)
    end

    @testset "certificate schema v1.0 writes, validates, reads, and verifies" begin
        P = schema_v1_problem()
        cert = RationalCertificate(P, [1 // 2, 1 // 3])
        path = tempname() * ".json"

        @test write_certificate(path, cert) == path
        json = read(path, String)
        @test occursin("\"certsdp_certificate_version\": \"1.0\"", json)
        @test occursin("\"problem_hash\"", json)
        @test occursin("\"linear_constraints\"", json)
        @test validate_certificate_schema(json)

        loaded = read_certificate(path)
        @test loaded isa RationalCertificate
        @test verify(loaded)
        @test loaded.hash == cert.hash

        old_json = rational_certificate_json_string(cert)
        migrated = migrate_certificate_json(old_json)
        @test validate_certificate_schema(migrated)
        @test verify(parse_certificate_json(migrated))
    end

    @testset "algebraic certificate schema v1.0 remains exact-verifiable" begin
        cert = schema_v1_algebraic_certificate()
        json = CertSDP.certificate_json_v1_string(cert)

        @test validate_certificate_schema(json)
        parsed = parse_certificate_json(json)
        @test parsed isa AlgebraicCertificate
        @test verify(parsed)

        backend_provenance = CertSDP._empty_backend_provenance(:msolve;
                                                               executable="/tmp/msolve",
                                                               version="0.test",
                                                               command=["msolve",
                                                                        "--version"])
        with_provenance = AlgebraicCertificate(cert.problem,
                                               cert.root,
                                               cert.solution,
                                               cert.psd_proof,
                                               cert.hash,
                                               Dict{Symbol, Any}(:algebraic_backend => backend_provenance))
        provenance_json = CertSDP.certificate_json_v1_string(with_provenance)
        @test occursin("\"algebraic_backend\"", provenance_json)
        parsed_with_provenance = parse_certificate_json(provenance_json)
        @test haskey(parsed_with_provenance.provenance, :algebraic_backend)

        migrated = migrate_certificate_json(algebraic_certificate_json_string(cert))
        @test validate_certificate_schema(migrated)
        @test verify(parse_certificate_json(migrated))
    end

    @testset "certificate schema rejects malformed v1.0 JSON" begin
        cert = RationalCertificate(schema_v1_problem(), [1 // 2, 1 // 3])
        valid = CertSDP.certificate_json_v1_string(cert)

        missing_problem_hash = replace(valid,
                                       "    \"problem_hash\": \"$(lmi_problem_hash(cert.problem))\",\n" => "";
                                       count=1)
        @test_throws ArgumentError validate_certificate_schema(missing_problem_hash)

        bad_id = replace(valid, cert.hash => "sha256:not-a-valid-digest"; count=1)
        @test_throws ArgumentError validate_certificate_schema(bad_id)

        wrong_linear_method = replace(valid,
                                      "\"method\": \"exact_substitution\"" => "\"method\": \"floating_point\"";
                                      count=1)
        @test_throws ArgumentError validate_certificate_schema(wrong_linear_method)
    end

    @testset "failure report schema v1.0 and diagnose" begin
        failure = CertificationFailure(:rank_profile_unstable,
                                       "rank gap too small",
                                       :rank_profile,
                                       Dict{Symbol, Any}(:candidate_ranks => [2, 3],
                                                         :gap => "1e-3"))
        report = diagnose(failure)
        json = JSON3.write(report)

        @test report.certsdp_failure_report_version == "1.0"
        @test report.status == "not_certified"
        @test report.failure_type == "RankUnstableFailure"
        @test report.reason == "rank_profile_unstable"
        @test !isempty(report.suggestions)
        @test validate_failure_report_schema(json)

        missing_summary = replace(json, "\"summary\":\"rank gap too small\"," => "";
                                  count=1)
        @test_throws ArgumentError validate_failure_report_schema(missing_summary)
    end

    @testset "Docs define public/internal boundary" begin
        repo_root = normpath(joinpath(@__DIR__, ".."))
        api_doc = joinpath(repo_root, "docs", "API_STABILITY.md")
        schema_doc = joinpath(repo_root, "docs", "SCHEMA_V1.md")

        @test isfile(api_doc)
        @test isfile(schema_doc)

        api_text = read(api_doc, String)
        schema_text = read(schema_doc, String)
        @test occursin("Stable Public API", api_text)
        @test occursin("Internal API", api_text)
        @test occursin("read_problem", api_text)
        @test occursin("BlockLMIProblem", api_text)
        @test !occursin("- `read_sdpa", api_text)
        @test occursin("not part of the compatibility contract", api_text)
        @test occursin("Problem Schema v1.0", schema_text)
        @test occursin("SDPA Sparse Frontend", schema_text)
        @test occursin("Certificate Schema v1.0", schema_text)
        @test occursin("Failure Report Schema v1.0", schema_text)
        @test occursin("rational strings", schema_text)
    end
end
