using JSON3

@testset "Strict verifier trust boundary" begin
    ZERO_SHA = "sha256:" * repeat("0", 64)

    function _strict_problem()
        return LMIProblem([1 0; 0 1],
                          [[1 0; 0 0],
                           [0 0; 0 1]];
                          vars=[:x, :y],)
    end

    function _strict_cert()
        return RationalCertificate(_strict_problem(), [1 // 2, 1 // 3])
    end

    function _strict_sos_cert()
        problem = build_sos_gram_problem([:x],
                                         [[0], [1]],
                                         [PolynomialTerm([0], 1),
                                          PolynomialTerm([2], 1)])
        return SOSGramCertificate(problem, [1 0; 0 1])
    end

    function _strict_json_dict(cert)
        return JSON3.read(certificate_json_v1_string(cert), Dict{String, Any})
    end

    function _strict_json_text(data)
        io = IOBuffer()
        JSON3.pretty(io, data)
        println(io)
        return String(take!(io))
    end

    function _strict_cli(json_text::AbstractString)
        path = tempname() * ".json"
        write(path, json_text)
        out = IOBuffer()
        err = IOBuffer()
        code = CertSDP.main(["verify", "--strict", path]; io=out, err=err)
        return (; code, out=String(take!(out)), err=String(take!(err)))
    end

    function _strict_rejects(json_text::AbstractString, needles)
        result = _strict_cli(json_text)
        text = result.out * result.err
        @test result.code == 1
        @test occursin("[FAIL]", text)
        @test any(needle -> occursin(needle, text), needles)
        @test !occursin("[OK] certificate accepted", text)
        @test !occursin("[OK] SOS Gram certificate accepted", text)
        return result
    end

    @testset "strict accepts exact v1 certificates without backend availability" begin
        cert = _strict_cert()
        result = _strict_cli(certificate_json_v1_string(cert))

        @test result.code == 0
        @test occursin("[OK] certificate accepted", result.out)
        @test isempty(result.err)

        old_env = get(ENV, "CERTSDP_MSOLVE", nothing)
        ENV["CERTSDP_MSOLVE"] = "/definitely/not/a/backend"
        try
            @test verify(cert; strict=true)
            no_backend_result = _strict_cli(certificate_json_v1_string(cert))
            @test no_backend_result.code == 0
        finally
            if isnothing(old_env)
                delete!(ENV, "CERTSDP_MSOLVE")
            else
                ENV["CERTSDP_MSOLVE"] = old_env
            end
        end
    end

    @testset "strict requires schema version, problem hash, and exact proof data" begin
        cert = _strict_cert()

        missing_version = _strict_json_dict(cert)
        delete!(missing_version, "certsdp_certificate_version")
        _strict_rejects(_strict_json_text(missing_version),
                        ["certsdp_certificate_version"])

        missing_hash = _strict_json_dict(cert)
        delete!(missing_hash, "problem_hash")
        _strict_rejects(_strict_json_text(missing_hash), ["problem_hash"])

        bad_hash = _strict_json_dict(cert)
        bad_hash["problem_hash"] = ZERO_SHA
        _strict_rejects(_strict_json_text(bad_hash), ["problem_hash"])

        missing_data = _strict_json_dict(cert)
        delete!(missing_data["proof"]["psd"], "data")
        _strict_rejects(_strict_json_text(missing_data),
                        ["root.proof.psd is missing required key `data`"])

        missing_linear_status = _strict_json_dict(cert)
        delete!(missing_linear_status["proof"]["linear_constraints"], "status")
        _strict_rejects(_strict_json_text(missing_linear_status),
                        ["linear_constraints.status"])
    end

    @testset "strict rejects numerical or backend-dependent proof claims" begin
        cert = _strict_cert()

        with_approx = _strict_json_dict(cert)
        with_approx["approximate_solution"] = Dict("xhat" => ["0.5", "0.333"])
        _strict_rejects(_strict_json_text(with_approx),
                        ["approximate_solution is forbidden"])

        approx_method = _strict_json_dict(cert)
        approx_method["proof"]["linear_constraints"]["method"] = "approx_equality"
        _strict_rejects(_strict_json_text(approx_method),
                        ["approx_equality", "exact_substitution"])

        backend_psd = _strict_json_dict(cert)
        backend_psd["proof"]["psd"]["method"] = "msolve_backend_artifact"
        _strict_rejects(_strict_json_text(backend_psd),
                        ["backend-dependent method", "msolve_backend_artifact"])

        tolerance_claim = _strict_json_dict(cert)
        tolerance_claim["proof"]["psd"]["data"]["tolerance"] = "1e-8"
        _strict_rejects(_strict_json_text(tolerance_claim),
                        ["tolerance is forbidden"])
    end

    @testset "fake backend logs do not affect strict verify result" begin
        accepted = _strict_json_dict(_strict_cert())
        accepted["provenance"]["algebraic_backend"] = Dict("backend" => "msolve",
                                                           "status" => "claimed_success",
                                                           "backend_log" => "[FAKE] accepted by backend")
        accepted_result = _strict_cli(_strict_json_text(accepted))
        @test accepted_result.code == 0
        @test occursin("[OK] certificate accepted", accepted_result.out)

        rejected = _strict_json_dict(_strict_cert())
        rejected["solution"]["coordinates"]["x"] = "-5"
        rejected["provenance"]["algebraic_backend"] = Dict("backend" => "msolve",
                                                           "backend_log" => "[FAKE] verifier should accept this")
        _strict_rejects(_strict_json_text(rejected),
                        ["certificate hash matches",
                         "substituted matrix matches rational solution"])
    end

    @testset "strict rejects legacy certificate input but non-strict migration remains" begin
        legacy = rational_certificate_json_string(_strict_cert())
        legacy_path = tempname() * ".json"
        write(legacy_path, legacy)

        out = IOBuffer()
        @test verify(read_certificate(legacy_path); io=out)
        @test occursin("[OK] certificate accepted", String(take!(out)))

        strict_result = _strict_cli(legacy)
        @test strict_result.code == 1
        @test occursin("certsdp_certificate_version", strict_result.out)
    end

    @testset "strict handles SOS embedded proof as v1 data only" begin
        cert = _strict_sos_cert()
        result = _strict_cli(certificate_json_v1_string(cert))
        @test result.code == 0
        @test occursin("[OK] SOS Gram certificate accepted", result.out)

        legacy_embedded = _strict_json_dict(cert)
        legacy_embedded["lmi_certificate"] = JSON3.read(rational_certificate_json_string(cert.lmi_certificate),
                                                        Dict{String, Any})
        _strict_rejects(_strict_json_text(legacy_embedded),
                        ["root.lmi_certificate.certsdp_certificate_version"])
    end

    @testset "trust model doc states independent replay boundary" begin
        repo_root = normpath(joinpath(@__DIR__, "..", ".."))
        path = joinpath(repo_root, "docs", "trust_model.md")
        @test isfile(path)
        text = read(path, String)
        for phrase in ("certsdp verify --strict",
                       "does not execute code",
                       "does not run an external solver",
                       "msolve",
                       "approximate equality",
                       "Backend logs in provenance are ignored")
            @test occursin(phrase, text)
        end
    end
end
