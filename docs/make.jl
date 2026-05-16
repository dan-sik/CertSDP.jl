module CertSDPDocs

const DOCS_ROOT = @__DIR__
const REPO_ROOT = dirname(DOCS_ROOT)
const BUILD_DIR = joinpath(DOCS_ROOT, "build")

if abspath(Base.active_project()) == abspath(joinpath(DOCS_ROOT, "Project.toml"))
    using Pkg: Pkg
    Pkg.develop(Pkg.PackageSpec(; path=REPO_ROOT))
    Pkg.instantiate()
end

using CertSDP
using Documenter

Core.eval(Main, :(using CertSDP: CertSDP))

const DOC_ORDER = ["index.md",
                   "installation.md",
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
                   "API_STABILITY.md",
                   "SCHEMA_V1.md",
                   "psd_proofs.md",
                   "why_rational_rounding_fails.md",
                   "citation.md",
                   "cli_tutorial.md",
                   "RELEASE_CHECKLIST.md",
                   "release_path.md",
                   "V1_RELEASE_READINESS.md",
                   "algebraic_certificate_format.md",
                   "failure_diagnostics.md"]

const ALLOWED_CODE_LANGS = Set(["@autodocs",
                                "@docs",
                                "@index",
                                "@meta",
                                "bash",
                                "bibtex",
                                "jldoctest",
                                "json",
                                "julia",
                                "mermaid",
                                "text"])

const EXCLUDED_DOCS = Set(String[])

function markdown_files()
    files = filter(name -> endswith(name, ".md") && !(name in EXCLUDED_DOCS),
                   readdir(DOCS_ROOT))
    ordered = String[]
    for name in DOC_ORDER
        name in files && push!(ordered, name)
    end
    for name in sort(setdiff(files, ordered))
        push!(ordered, name)
    end
    return ordered
end

function validate_code_fences(path::AbstractString, text::AbstractString)
    in_fence = false
    for (line_number, line) in enumerate(eachsplit(text, '\n'))
        startswith(line, "```") || continue
        if in_fence
            in_fence = false
            continue
        end

        info = strip(chop(line; head=3, tail=0))
        isempty(info) &&
            error("missing code-fence language in $(relpath(path, REPO_ROOT)):$line_number")
        language = first(split(info))
        language in ALLOWED_CODE_LANGS ||
            error("unsupported code-fence language `$language` in $(relpath(path, REPO_ROOT)):$line_number; use a supported language or mark pseudo-code as text")
        in_fence = true
    end
    return !in_fence || error("unclosed code fence in $(relpath(path, REPO_ROOT))")
end

function validate_local_links(path::AbstractString, text::AbstractString)
    for match in eachmatch(r"\[[^\]]+\]\(([^)#][^)]*)\)", text)
        target = match.captures[1]
        startswith(target, "http://") && continue
        startswith(target, "https://") && continue
        startswith(target, "mailto:") && continue
        occursin("://", target) && continue

        file_target = first(split(target, "#"))
        isempty(file_target) && continue
        local_path = normpath(joinpath(dirname(path), file_target))
        isfile(local_path) ||
            error("broken local link in $(relpath(path, REPO_ROOT)): $target")
    end
end

function page_title(name::AbstractString, text::AbstractString)
    m = match(r"(?m)^#\s+(.+)$", text)
    return isnothing(m) ? name : String(m.captures[1])
end

function _page_pair(name::AbstractString)
    text = read(joinpath(DOCS_ROOT, name), String)
    return page_title(name, text) => name
end

function _group_pages(files::Vector{String}, names::Vector{String})
    present = filter(name -> name in files, names)
    return Pair{String, String}[_page_pair(name) for name in present]
end

function docs_pages(files::Vector{String})
    grouped = ["Start Here" => _group_pages(files,
                                            ["index.md",
                                             "installation.md",
                                             "platform_support.md",
                                             "quickstart.md"]),
               "How-To Guides" => _group_pages(files,
                                                ["lmi_tutorial.md",
                                                 "sos_tutorial.md",
                                                 "sdpa_import.md",
                                                 "jump_moi_integration.md",
                                                 "backends.md",
                                                 "diagnostics.md",
                                                 "workflows.md"]),
               "Trust And Evidence" => _group_pages(files,
                                                     ["trust_model.md",
                                                      "public_narrative.md",
                                                      "validation.md",
                                                      "benchmarks.md",
                                                      "performance.md",
                                                      "psd_proofs.md",
                                                      "why_rational_rounding_fails.md"]),
               "Reference" => _group_pages(files,
                                            ["certificate_format.md",
                                             "api_reference.md",
                                             "API_STABILITY.md",
                                             "SCHEMA_V1.md",
                                             "citation.md",
                                             "cli_tutorial.md"]),
               "Release" => _group_pages(files,
                                          ["RELEASE_CHECKLIST.md",
                                           "release_path.md",
                                           "V1_RELEASE_READINESS.md"]),
               "Legacy Redirects" => _group_pages(files,
                                                   ["algebraic_certificate_format.md",
                                                    "failure_diagnostics.md"])]
    known = Set(String[])
    for group in grouped
        for pair in group.second
            push!(known, pair.second)
        end
    end
    extras = sort(setdiff(files, collect(known)))
    if !isempty(extras)
        push!(grouped, "Other" => [_page_pair(name) for name in extras])
    end
    return grouped
end

function _documenter_source_dir(files::Vector{String})
    source_dir = mktempdir()
    for name in files
        cp(joinpath(DOCS_ROOT, name), joinpath(source_dir, name); force=true)
    end
    return source_dir
end

function build(; strict::Bool=true, doctest::Bool=true)
    files = markdown_files()
    isempty(files) && error("no markdown files found in docs/")

    for name in files
        path = joinpath(DOCS_ROOT, name)
        text = read(path, String)
        strict && validate_code_fences(path, text)
        strict && validate_local_links(path, text)
    end

    source_dir = _documenter_source_dir(files)
    makedocs(; sitename="CertSDP.jl",
             modules=[CertSDP],
             doctest,
             clean=true,
             source=source_dir,
             build=BUILD_DIR,
             warnonly=false,
             checkdocs=:none,
             format=Documenter.HTML(; prettyurls=false,
                                    canonical="",
                                    assets=String[],
                                    edit_link=nothing,
                                    inventory_version=string(CertSDP.package_version())),
             pages=docs_pages(files))

    index_path = joinpath(BUILD_DIR, "index.html")
    isfile(index_path) || error("docs build did not produce index.html")
    println("Built ", length(files), " Documenter pages in ",
            relpath(BUILD_DIR, REPO_ROOT))
    return index_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    build()
end

end
