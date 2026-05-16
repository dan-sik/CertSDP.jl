@testset "Documentation hardening" begin
    repo_root = normpath(joinpath(@__DIR__, "..", ".."))

    required_docs = ["installation.md",
                     "platform_support.md",
                     "quickstart.md",
                     "lmi_tutorial.md",
                     "sos_tutorial.md",
                     "sdpa_import.md",
                     "jump_moi_integration.md",
                     "backends.md",
                     "diagnostics.md",
                     "workflows.md",
                     "trust_model.md",
                     "public_narrative.md",
                     "validation.md",
                     "benchmarks.md",
                     "performance.md",
                     "certificate_format.md",
                     "api_reference.md",
                     "citation.md",
                     "RELEASE_CHECKLIST.md",
                     "release_path.md",
                     "V1_RELEASE_READINESS.md"]

    @testset "expert docs exist" begin
        for doc in required_docs
            path = joinpath(repo_root, "docs", doc)
            @test isfile(path)
            text = read(path, String)
            @test occursin("#", text)
            @test length(strip(text)) > 400
        end
    end

    @testset "README is release oriented" begin
        readme = read(joinpath(repo_root, "README.md"), String)
        @test occursin("Five-Minute Quickstart", readme)
        @test occursin("bin/certsdp verify --strict /tmp/certsdp-rational-cert.json",
                       readme)
        @test occursin("Where CertSDP Fits", readme)
        @test occursin("not another large-scale SDP solver", readme)
        @test occursin("Platform Support", readme)
        @test occursin("Validation", readme)
        @test occursin("Citation", readme)
        @test occursin("Kolmogorov", readme)
        @test occursin("Why CertSDP Exists", readme)
        @test occursin("A solver residual is not a proof", readme)
        @test occursin("A solver finds a candidate. CertSDP makes it replayable", readme)
        @test occursin("Signature Demo", readme)
        @test occursin("Public narrative", readme)
        @test occursin("Release And Citation", readme)
        @test occursin("TagBot", readme)
        @test occursin("Zenodo", readme)
        @test occursin("scripts/run_validation.jl", readme)
        @test occursin("Optional numerical oracle", readme)
        @test !occursin("stress", lowercase(readme))
        @test !occursin("frontier", lowercase(readme))
    end

    @testset "P2 narrative docs cover workflows and limitations honestly" begin
        workflows = read(joinpath(repo_root, "docs", "workflows.md"), String)
        @test occursin("Trust Boundary Diagram", workflows)
        @test occursin("Certificate Anatomy", workflows)
        @test occursin("Result Wrappers", workflows)
        @test occursin("API, CLI, And Frontend Map", workflows)
        @test occursin("certsdp replay", workflows)

        api = read(joinpath(repo_root, "docs", "api_reference.md"), String)
        @test occursin("Result Contract", api)
        @test occursin("CertifiedResult", api)
        @test occursin("FailureResult", api)
        @test occursin("Workflow Map", api)

        validation = read(joinpath(repo_root, "docs", "validation.md"), String)
        @test occursin("scripts/run_validation.jl", validation)
        @test occursin("temporary Julia", validation)
        @test occursin("environment and installs the optional Clarabel",
                       validation)
        @test occursin("Paper-Artifact Coverage", validation)
        @test occursin("SDPA/SDPLIB-style", validation)
        @test occursin("SumOfSquares-style", validation)
        @test occursin("Mutation Matrix", validation)
        @test occursin("Raw Artifacts And DOI", validation)

        index = read(joinpath(repo_root, "docs", "index.md"), String)
        @test occursin("At A Glance", index)
        @test occursin("Core Claim", index)
        @test occursin("Public narrative", index)
        @test occursin("Release Boundaries", index)
        @test occursin("Not claimed", index)
        @test occursin("Platform Scope", index)
        @test occursin("Algebraic multi-block workflows", index)
        @test occursin("Infeasibility", index)

        platform = read(joinpath(repo_root, "docs", "platform_support.md"), String)
        @test occursin("Support Matrix", platform)
        @test occursin("Windows", platform)
        @test occursin("verifier-only", platform)
        @test occursin("Claims To Avoid", platform)

        release_path = read(joinpath(repo_root, "docs", "release_path.md"), String)
        @test occursin("Julia Registry", release_path)
        @test occursin("TagBot", release_path)
        @test occursin("CompatHelper", release_path)
        @test occursin("DOI", release_path)

        benchmarks = read(joinpath(repo_root, "docs", "benchmarks.md"), String)
        @test occursin("public release artifact path", benchmarks)
        @test occursin("bin/certsdp benchmark", benchmarks)
        @test occursin("How To Read One Row", benchmarks)

        public_narrative = read(joinpath(repo_root, "docs", "public_narrative.md"),
                                String)
        @test occursin("Claims That Are Safe", public_narrative)
        @test occursin("Claims To Avoid", public_narrative)
        @test occursin("Copy-Ready Snippets", public_narrative)
        @test occursin("registry and doi", lowercase(public_narrative))

        trust_model = read(joinpath(repo_root, "docs", "trust_model.md"), String)
        @test occursin("Threat Model / Assumptions", trust_model)
        @test occursin("not execute benchmark source files", trust_model)

        quickstart = read(joinpath(repo_root, "docs", "quickstart.md"), String)
        @test occursin("If Something Fails", quickstart)

        installation = read(joinpath(repo_root, "docs", "installation.md"), String)
        @test occursin("Choose A Path", installation)
        @test occursin("Repository CLI Path", installation)
        @test occursin("Julia Dependency Path", installation)

        api = read(joinpath(repo_root, "docs", "api_reference.md"), String)
        @test occursin("Failure diagnostics", api)

        stability = read(joinpath(repo_root, "docs", "API_STABILITY.md"), String)
        @test occursin("Surface Map", stability)

        certificate = read(joinpath(repo_root, "docs", "certificate_format.md"),
                           String)
        @test occursin("abridged example", lowercase(certificate))

        citation = read(joinpath(repo_root, "docs", "citation.md"), String)
        @test occursin("After a DOI is minted", citation)
    end

    @testset "docs examples are language-tagged" begin
        for path in filter(p -> endswith(p, ".md"),
                           readdir(joinpath(repo_root, "docs"); join=true))
            text = read(path, String)
            in_fence = false
            for (line_number, line) in enumerate(eachsplit(text, '\n'))
                startswith(line, "```") || continue
                if in_fence
                    in_fence = false
                    continue
                end
                info = strip(chop(line; head=3, tail=0))
                @test !isempty(info)
                @test first(split(info)) in ["@autodocs",
                                             "@docs",
                                             "@index",
                                             "@meta",
                                             "bash",
                                             "bibtex",
                                             "jldoctest",
                                             "json",
                                             "julia",
                                             "mermaid",
                                             "text"]
                if occursin("Pseudo-code", text[max(1, firstindex(text)):lastindex(text)])
                    @test true
                end
                in_fence = true
            end
            @test !in_fence
        end
    end

    @testset "docs build" begin
        include(joinpath(repo_root, "docs", "make.jl"))
        index = CertSDPDocs.build()
        @test isfile(index)
        @test isfile(joinpath(repo_root, "docs", "build", "quickstart.html"))
        @test isfile(joinpath(repo_root, "docs", "build", "api_reference.html"))
        @test isfile(joinpath(repo_root, "docs", "build", "workflows.html"))
        @test isfile(joinpath(repo_root, "docs", "build", "release_path.html"))
        @test occursin("Quickstart",
                       read(joinpath(repo_root, "docs", "build", "quickstart.html"),
                            String))
        @test occursin("API Reference",
                       read(joinpath(repo_root, "docs", "build", "api_reference.html"),
                            String))
        @test occursin("Trust Boundary Diagram",
                       read(joinpath(repo_root, "docs", "build", "workflows.html"),
                            String))
    end
end
