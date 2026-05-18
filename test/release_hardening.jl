using TOML

@testset "Release hardening" begin
    repo_root = normpath(joinpath(@__DIR__, ".."))

    @testset "release files exist" begin
        required_files = ["LICENSE",
                          "VERSION",
                          "NOTICE.md",
                          "CHANGELOG.md",
                          "CITATION.cff",
                          "codemeta.json",
                          "CONTRIBUTING.md",
                          "CODE_OF_CONDUCT.md",
                          joinpath("scripts", "run_validation.jl"),
                          joinpath("scripts", "release_audit.jl"),
                          joinpath("scripts", "fresh_checkout_release_audit.sh"),
                          ".gitignore",
                          ".JuliaFormatter.toml",
                          joinpath(".github", "workflows", "ci.yml"),
                          joinpath(".github", "workflows", "docs.yml"),
                          joinpath(".github", "workflows", "validation.yml"),
                          joinpath(".github", "workflows", "tagbot.yml"),
                          joinpath(".github", "workflows", "compathelper.yml")]

        for file in required_files
            path = joinpath(repo_root, file)
            @test isfile(path)
            @test !isempty(strip(read(path, String)))
        end

        @test occursin("Apache License", read(joinpath(repo_root, "LICENSE"), String))
        @test occursin("Grant of Patent License",
                       read(joinpath(repo_root, "LICENSE"), String))
        @test occursin("Third-Party", read(joinpath(repo_root, "NOTICE.md"), String))
        @test occursin("Apache-2.0 core package",
                       read(joinpath(repo_root, "NOTICE.md"), String))
        @test occursin("optional external executable",
                       read(joinpath(repo_root, "NOTICE.md"), String))
        @test occursin("cff-version: 1.2.0",
                       read(joinpath(repo_root, "CITATION.cff"), String))
        @test occursin("license: \"Apache-2.0\"",
                       read(joinpath(repo_root, "CITATION.cff"), String))
        @test occursin("\"@type\": \"SoftwareSourceCode\"",
                       read(joinpath(repo_root, "codemeta.json"), String))
        @test occursin("\"license\": \"https://spdx.org/licenses/Apache-2.0.html\"",
                       read(joinpath(repo_root, "codemeta.json"), String))
        @test occursin("trust boundary",
                       lowercase(read(joinpath(repo_root, "CONTRIBUTING.md"), String)))
        @test occursin("exact replay layer",
                       lowercase(read(joinpath(repo_root, "CONTRIBUTING.md"), String)))
        old_angle = "review" * "er-grade"
        @test !occursin(old_angle,
                        lowercase(read(joinpath(repo_root, "CONTRIBUTING.md"), String)))
        internal_notes_dir = "design" * "doc"
        @test !occursin(internal_notes_dir,
                        lowercase(read(joinpath(repo_root, "CONTRIBUTING.md"), String)))
        @test occursin("verify --strict",
                       read(joinpath(repo_root, "CONTRIBUTING.md"), String))
        @test occursin("Contributor Covenant",
                       read(joinpath(repo_root, "CODE_OF_CONDUCT.md"), String))
        @test strip(read(joinpath(repo_root, "VERSION"), String)) == "1.0.0"
        @test occursin("## v1.0.0", read(joinpath(repo_root, "CHANGELOG.md"), String))
        @test occursin("Pkg.test",
                       read(joinpath(repo_root, ".github", "workflows", "ci.yml"), String))
        @test occursin("Windows verifier-only smoke",
                       read(joinpath(repo_root, ".github", "workflows", "ci.yml"), String))
        @test occursin("scripts/run_validation.jl",
                       read(joinpath(repo_root, ".github", "workflows", "ci.yml"),
                            String))
        @test occursin("Documenter build",
                       read(joinpath(repo_root, ".github", "workflows", "docs.yml"),
                            String))
        @test occursin("Public validation suite",
                       read(joinpath(repo_root, ".github", "workflows", "validation.yml"),
                            String))
        @test occursin("JuliaRegistries/TagBot",
                       read(joinpath(repo_root, ".github", "workflows", "tagbot.yml"),
                            String))
        @test occursin("CompatHelper.main",
                       read(joinpath(repo_root, ".github", "workflows", "compathelper.yml"),
                            String))
    end

    @testset "public source tree has no local residue" begin
        ignore_text = read(joinpath(repo_root, ".gitignore"), String)
        @test occursin(".DS_Store", ignore_text)
        @test occursin("docs/Manifest*.toml", ignore_text)
        @test occursin("docs/build/", ignore_text)
        @test occursin("benchmarks/generated/", ignore_text)
        @test occursin("reports/", ignore_text)
        @test occursin("designdoc/", ignore_text)
        @test occursin("references/", ignore_text)
        @test !isfile(joinpath(repo_root, ".gitmodules"))

        tracked = String[]
        if isdir(joinpath(repo_root, ".git"))
            try
                tracked = split(chomp(read(`git -C $repo_root ls-files`, String)), '\n')
            catch
                tracked = String[]
            end
        end

        if !isempty(tracked)
            forbidden_paths = Set([".DS_Store",
                                   ".gitmodules",
                                   "docs/Manifest-v1.10.toml",
                                   "docs/Manifest.toml",
                                   "docs/build"])
            @test all(path -> !(path in forbidden_paths &&
                                (isfile(joinpath(repo_root, path)) ||
                                 isdir(joinpath(repo_root, path)))),
                      tracked)
            @test all(path -> !(startswith(path, "designdoc/") &&
                                isfile(joinpath(repo_root, path))), tracked)
            @test all(path -> !(startswith(path, "reports/") &&
                                isfile(joinpath(repo_root, path))), tracked)
            @test all(path -> !(startswith(path, "benchmarks/generated/") &&
                                isfile(joinpath(repo_root, path))), tracked)
            @test all(path -> !(startswith(path, "references/") &&
                                isfile(joinpath(repo_root, path))), tracked)

            text_suffixes = [".md", ".jl", ".toml", ".json", ".yml", ".yaml",
                             ".cff", ".sh", ".txt"]
            local_markers = [repo_root, "/Users/" * "shani_mac"]
            for rel in tracked
                any(suffix -> endswith(rel, suffix), text_suffixes) || continue
                path = joinpath(repo_root, rel)
                isfile(path) || continue
                text = read(path, String)
                for marker in local_markers
                    @test !occursin(marker, text)
                end
            end
        end
    end

    @testset "exact verifier dependency boundary" begin
        project = TOML.parsefile(joinpath(repo_root, "Project.toml"))
        @test !haskey(project["deps"], "Clarabel")
        @test project["weakdeps"]["Clarabel"] ==
              "61c947e1-3e6d-4ee4-985a-eec8c727bd6e"
        @test project["extensions"]["CertSDPClarabelExt"] == "Clarabel"
        @test isfile(joinpath(repo_root, "ext", "CertSDPClarabelExt.jl"))
        approx_source = read(joinpath(repo_root, "src", "numeric",
                                      "ApproxSolution.jl"), String)
        @test !occursin("using Clarabel", approx_source)
        @test occursin("MissingNumericalOracleBackend", approx_source)
    end

    @testset "README quickstart and release wording" begin
        readme = read(joinpath(repo_root, "README.md"), String)
        @test occursin("Quickstart", readme)
        @test occursin("bin/certsdp certify", readme)
        @test occursin("certify-sos", readme)
        @test occursin("rational rounding", lowercase(readme))
        @test occursin("Exact replay for numerical SDP/SOS certificates",
                       readme)
        @test occursin("A solver finds a candidate. CertSDP makes it replayable",
                       readme)
        @test occursin("Where CertSDP Fits", readme)
        @test occursin("Current Validation Snapshot", readme)
        @test occursin("Signature Demo", readme)
        @test occursin("Showcases", readme)
        @test occursin("Platform Support", readme)
        @test occursin("generic large-scale SDP solver", readme)
        @test occursin("Limitations", readme)
        @test occursin("Why CertSDP Exists", readme)
        @test occursin("Citation", readme)
        @test occursin("infeasibility", lowercase(readme))
        @test occursin("scripts/run_validation.jl", readme)
        @test occursin("API_STABILITY", readme)
        @test occursin("License", readme)
        @test occursin("Apache License 2.0", readme)
        @test occursin("v1.0", readme)
        @test occursin("Validation", readme)
        @test !occursin("stress", lowercase(readme))
        @test !occursin("frontier", lowercase(readme))
    end

    @testset "public API exports are hard-frozen" begin
        exported_names = Set(names(CertSDP))
        @test exported_names == Set([:CertSDP,
                                     :LMIProblem,
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

        @test isdefined(CertSDP, :RationalCertificate)
        @test :RationalCertificate ∉ exported_names
        @test :read_lmi_json ∉ exported_names
        @test :write_sos_gram_json ∉ exported_names
    end

    @testset "SOS problem read/write roundtrip" begin
        problem = build_sos_gram_problem([:x],
                                         [[0], [1]],
                                         [PolynomialTerm([0], 1),
                                          PolynomialTerm([2], 1)])

        path = tempname() * ".json"
        @test write_sos_gram_json(path, problem) == path
        parsed = read_sos_gram_json(path)
        @test sos_gram_problem_hash(parsed) == sos_gram_problem_hash(problem)
    end
end
