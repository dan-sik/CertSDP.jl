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
                     "validation.md",
                     "benchmarks.md",
                     "performance.md",
                     "certificate_format.md",
                     "api_reference.md",
                     "citation.md"]

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
        @test occursin("Quickstart", readme)
        @test occursin("bin/certsdp verify --strict /tmp/certsdp-rational-cert.json",
                       readme)
        @test occursin("Ecosystem Fit", readme)
        @test occursin("candidate evidence in, exact replayable certificate out",
                       readme)
        @test occursin("Platform Support", readme)
        @test occursin("Validation", readme)
        @test occursin("Citation", readme)
        @test occursin("Kolmogorov", readme)
        @test occursin("Why It Exists", readme)
        @test occursin("What CertSDP Produces", readme)
        @test occursin("Capabilities", readme)
        @test occursin("Citation", readme)
        @test occursin("scripts/run_validation.jl", readme)
        @test !occursin("stress", lowercase(readme))
        @test !occursin("production gate", lowercase(readme))
        @test !occursin("hard gate", lowercase(readme))
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
        @test occursin("Paper-Artifact Coverage", validation)
        @test occursin("Exact replay", validation)
        @test occursin("Algebraic reconstruction", validation)
        @test occursin("Mutation Matrix", validation)
        @test occursin("Raw Artifacts And DOI", validation)

        index = read(joinpath(repo_root, "docs", "index.md"), String)
        @test occursin("At A Glance", index)
        @test occursin("Core Claim", index)
        @test occursin("Release Boundaries", index)
        @test occursin("Not claimed", index)
        @test occursin("Platform Scope", index)
        @test occursin("Compiler artifacts", index)
        @test occursin("Infeasibility", index)

        platform = read(joinpath(repo_root, "docs", "platform_support.md"), String)
        @test occursin("Support Matrix", platform)
        @test occursin("Windows", platform)
        @test occursin("verifier-only", platform)
        @test occursin("Claims To Avoid", platform)

        benchmarks = read(joinpath(repo_root, "docs", "benchmarks.md"), String)
        @test occursin("bin/certsdp benchmark", benchmarks)
        @test occursin("Reading The Report", benchmarks)

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
