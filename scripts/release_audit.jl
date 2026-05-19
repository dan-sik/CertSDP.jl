#!/usr/bin/env julia

module ReleaseAuditDrill

using CertSDP
using JSON3
using Pkg
using Random
using TOML
using UUIDs

const DEFAULT_SEED = 2912
const DEFAULT_WITH_MSOLVE_SEED = 42

Base.@kwdef mutable struct DrillOptions
    repo::String = abspath(pwd())
    out::String = joinpath(abspath(pwd()), "reports", "certificate_compiler_release_drill")
    mode::Symbol = :full
    seed::Int = DEFAULT_SEED
    with_msolve_seed::Int = DEFAULT_WITH_MSOLVE_SEED
    validation_count::Int = 3
    with_msolve_count::Int = 1
    fake_count::Int = 3
    failure_count::Int = 2
    instantiate::Bool = false
    skip_doctor::Bool = false
    skip_no_msolve::Bool = false
    skip_with_msolve::Bool = false
    skip_validation_sample::Bool = false
    skip_fake_certs::Bool = false
    skip_failure_explain::Bool = false
    skip_package_dry_run::Bool = false
end

function main(args=ARGS)
    options = parse_args(String.(args))
    options.repo = abspath(options.repo)
    options.out = abspath(options.out)
    mkpath(options.out)

    results = NamedTuple[]
    selected_validation = String[]
    selected_msolve = String[]
    selected_fakes = String[]
    selected_failures = String[]

    cd(options.repo) do
        if options.instantiate
            Pkg.activate(options.repo)
            Pkg.instantiate()
        end

        if options.mode === :package_dry_run
            _record_step!(results, "package registration dry-run") do
                package_registration_dry_run(options.repo)
            end
        else
            if !options.skip_doctor
                _record_step!(results, "doctor readiness") do
                    report = CertSDP.doctor_report(; validation_root="benchmarks")
                    (; passed=true,
                       details=string("status=", report.status,
                                      ", checks=", length(report.checks),
                                      ", budget=", report.validation_budget),
                       artifacts=String[])
                end
            end

            if !options.skip_no_msolve
                _record_step!(results, "no-msolve strict verifier path") do
                    no_msolve_strict_path(options)
                end
            end

            if !options.skip_with_msolve
                _record_step!(results, "with-msolve validation path") do
                    result = sampled_validation_run(options;
                                                    label="with_msolve",
                                                    seed=options.with_msolve_seed,
                                                    count=options.with_msolve_count,
                                                    backend_requirement="msolve")
                    append!(selected_msolve, result.selected)
                    result
                end
            end

            if !options.skip_validation_sample
                _record_step!(results, "random validation sample") do
                    result = sampled_validation_run(options;
                                                    label="random_validation",
                                                    seed=options.seed,
                                                    count=options.validation_count)
                    append!(selected_validation, result.selected)
                    result
                end
            end

            if !options.skip_fake_certs
                _record_step!(results, "strict fake-certificate rejection sample") do
                    result = strict_fake_certificate_sample(options)
                    append!(selected_fakes, result.selected)
                    result
                end
            end

            if !options.skip_failure_explain
                _record_step!(results, "failure explain sample") do
                    result = failure_explain_sample(options)
                    append!(selected_failures, result.selected)
                    result
                end
            end

            if !options.skip_package_dry_run
                _record_step!(results, "package registration dry-run") do
                    package_registration_dry_run(options.repo)
                end
            end
        end
    end

    report_path = write_drill_report(options, results;
                                     selected_validation,
                                     selected_msolve,
                                     selected_fakes,
                                     selected_failures)
    passed = all(result -> result.status == "pass", results)
    println("Release audit report: ", report_path)
    for result in results
        println("[", uppercase(result.status), "] ", result.name, ": ", result.details)
    end
    if passed
        println("[PASS] release audit completed with no blockers")
        return 0
    end
    println("[FAIL] release audit found blockers")
    return 1
end

function parse_args(args::Vector{String})
    options = DrillOptions()
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--repo"
            i += 1
            i <= length(args) || error("--repo requires a path")
            options.repo = args[i]
        elseif arg == "--out"
            i += 1
            i <= length(args) || error("--out requires a directory")
            options.out = args[i]
        elseif arg == "--mode"
            i += 1
            i <= length(args) || error("--mode requires full, sampled-clean, or package-dry-run")
            mode = Symbol(replace(lowercase(args[i]), '-' => '_'))
            mode in (:full, :sampled_clean, :package_dry_run) ||
                error("--mode must be full, sampled-clean, or package-dry-run")
            options.mode = mode
            if mode === :sampled_clean
                options.skip_with_msolve = true
                options.skip_no_msolve = true
            end
        elseif arg == "--seed"
            i += 1
            i <= length(args) || error("--seed requires an integer")
            options.seed = parse(Int, args[i])
        elseif arg == "--with-msolve-seed"
            i += 1
            i <= length(args) || error("--with-msolve-seed requires an integer")
            options.with_msolve_seed = parse(Int, args[i])
        elseif arg == "--validation-count"
            i += 1
            i <= length(args) || error("--validation-count requires an integer")
            options.validation_count = _positive_int(args[i], "--validation-count")
        elseif arg == "--with-msolve-count"
            i += 1
            i <= length(args) || error("--with-msolve-count requires an integer")
            options.with_msolve_count = _positive_int(args[i], "--with-msolve-count")
        elseif arg == "--fake-count"
            i += 1
            i <= length(args) || error("--fake-count requires an integer")
            options.fake_count = _positive_int(args[i], "--fake-count")
        elseif arg == "--failure-count"
            i += 1
            i <= length(args) || error("--failure-count requires an integer")
            options.failure_count = _positive_int(args[i], "--failure-count")
        elseif arg == "--instantiate"
            options.instantiate = true
        elseif arg == "--skip-doctor"
            options.skip_doctor = true
        elseif arg == "--skip-no-msolve"
            options.skip_no_msolve = true
        elseif arg == "--skip-with-msolve"
            options.skip_with_msolve = true
        elseif arg == "--skip-validation-sample"
            options.skip_validation_sample = true
        elseif arg == "--skip-fake-certs"
            options.skip_fake_certs = true
        elseif arg == "--skip-failure-explain"
            options.skip_failure_explain = true
        elseif arg == "--skip-package-dry-run"
            options.skip_package_dry_run = true
        elseif arg in ("-h", "--help")
            print_usage()
            exit(0)
        else
            error("unknown option `$arg`")
        end
        i += 1
    end
    return options
end

function print_usage(; io::IO=stdout)
    println(io, "usage: julia --project=. scripts/release_audit.jl [options]")
    println(io, "  --repo DIR                 repository root (default: pwd)")
    println(io, "  --out DIR                  output directory")
    println(io, "  --mode full|sampled-clean|package-dry-run")
    println(io, "  --seed N                   random seed for validation/fake/failure samples")
    println(io, "  --validation-count N       number of validation cases to sample")
    println(io, "  --fake-count N             number of fake certificates to mutate and reject")
    println(io, "  --failure-count N          number of failure reports to explain")
    println(io, "  --instantiate              run Pkg.instantiate() first")
end

function _positive_int(value::AbstractString, option::AbstractString)
    parsed = parse(Int, value)
    parsed > 0 || error("$option must be positive")
    return parsed
end

function _record_step!(results::Vector{NamedTuple}, name::AbstractString, f::Function)
    try
        result = f()
        status = get(result, :passed, false) ? "pass" : "fail"
        push!(results, (;
                        name=String(name),
                        status,
                        details=String(get(result, :details, "")),
                        artifacts=Vector{String}(get(result, :artifacts, String[]))))
    catch err
        push!(results, (;
                        name=String(name),
                        status="fail",
                        details=sprint(showerror, err),
                        artifacts=String[]))
    end
    return results
end

_record_step!(f::Function, results::Vector{NamedTuple}, name::AbstractString) =
    _record_step!(results, name, f)

function no_msolve_strict_path(options::DrillOptions)
    outdir = joinpath(options.out, "no_msolve")
    mkpath(outdir)
    cert_path = joinpath(outdir, "rational_strict_cert.json")

    P = CertSDP.LMIProblem(Rational{BigInt}[1 0; 0 1],
                           [Rational{BigInt}[1 0; 0 0],
                            Rational{BigInt}[0 0; 0 1]];
                           vars=[:x, :y])
    cert = CertSDP.RationalCertificate(P, Rational{BigInt}[1 // 2, 1 // 3])
    CertSDP.write_certificate(cert_path, cert)

    temp_path = mktempdir()
    output = IOBuffer()
    doctor_status = nothing
    accepted = with_env(["CERTSDP_MSOLVE" => "/definitely/not/msolve",
                         "PATH" => temp_path]) do
        doctor_status = CertSDP.doctor_report(; validation_root="benchmarks").status
        CertSDP.verify_strict(cert_path; io=output)
    end
    report_path = joinpath(outdir, "strict_verify_no_msolve.txt")
    write(report_path, String(take!(output)))
    accepted || error("strict verifier rejected a rational certificate without msolve")
    doctor_status == "not_ready" ||
        error("doctor did not report missing msolve under isolated PATH")
    return (;
            passed=true,
            details=string("strict verify accepted while doctor status was ",
                           doctor_status),
            artifacts=[cert_path, report_path])
end

function with_env(pairs::Vector{Pair{String, String}}, f::Function)
    old = Dict{String, Union{Nothing, String}}()
    for (key, value) in pairs
        old[key] = haskey(ENV, key) ? ENV[key] : nothing
        ENV[key] = value
    end
    try
        return f()
    finally
        for (key, value) in old
            if isnothing(value)
                delete!(ENV, key)
            else
                ENV[key] = value
            end
        end
    end
end

with_env(f::Function, pairs::Vector{Pair{String, String}}) = with_env(pairs, f)

function sampled_validation_run(options::DrillOptions;
                                label::AbstractString,
                                seed::Integer,
                                count::Integer,
                                backend_requirement=nothing)
    root = joinpath(options.repo, "benchmarks")
    cases = CertSDP.benchmark_cases(root; subset=:validation)
    if !isnothing(backend_requirement)
        requirement = String(backend_requirement)
        cases = filter(case -> case.expected.backend_requirement == requirement, cases)
    end
    length(cases) >= count ||
        error("only $(length(cases)) validation cases available for sample `$label`")

    Random.seed!(seed)
    selected = sort(Random.shuffle(cases)[1:count]; by=case -> case.name)
    sample_root = joinpath(options.out, label, "benchmarks")
    sample_validation_root = joinpath(sample_root, "validation")
    rm(sample_root; recursive=true, force=true)
    mkpath(sample_validation_root)
    for case in selected
        target = joinpath(sample_validation_root, basename(case.dir))
        cp(case.dir, target; force=true)
    end

    report_path = joinpath(options.out, label, "report.md")
    generated_dir = joinpath(options.out, label, "generated")
    result = CertSDP.run_benchmarks(sample_root;
                                    out=report_path,
                                    generated_dir=generated_dir,
                                    subset=:validation,
                                    budget=:validation)
    result.passed ||
        error("sample `$label` mismatches: " * join(result.mismatches, "; "))
    selected_names = [case.name for case in selected]
    return (;
            passed=true,
            details=string("selected ", length(selected_names), " cases: ",
                           join(selected_names, ", ")),
            artifacts=[report_path, generated_dir],
            selected=selected_names)
end

function strict_fake_certificate_sample(options::DrillOptions)
    cases = fake_certificate_cases()
    length(cases) >= options.fake_count ||
        error("fake certificate pool has only $(length(cases)) cases")
    Random.seed!(options.seed + 1000)
    selected = sort(Random.shuffle(cases)[1:options.fake_count]; by=case -> case.name)
    outdir = joinpath(options.out, "fake_certs")
    rm(outdir; recursive=true, force=true)
    mkpath(outdir)
    rejected = String[]
    artifacts = String[]
    for case in selected
        path = joinpath(outdir, _slug(case.name) * ".json")
        write(path, case.json)
        result = run_cli("verify", "--strict", path)
        text_path = joinpath(outdir, _slug(case.name) * ".txt")
        write(text_path, result.out * result.err)
        result.code == 0 && error("strict verifier accepted fake certificate `$(case.name)`")
        occursin("[FAIL]", result.out * result.err) ||
            error("strict verifier rejection for `$(case.name)` did not include [FAIL]")
        push!(rejected, case.name)
        push!(artifacts, path)
        push!(artifacts, text_path)
    end
    return (;
            passed=true,
            details=string("rejected ", length(rejected), " fakes: ",
                           join(rejected, ", ")),
            artifacts,
            selected=rejected)
end

function failure_explain_sample(options::DrillOptions)
    cases = failure_report_cases()
    length(cases) >= options.failure_count ||
        error("failure pool has only $(length(cases)) cases")
    Random.seed!(options.seed + 2000)
    selected = sort(Random.shuffle(cases)[1:options.failure_count]; by=case -> case.name)
    outdir = joinpath(options.out, "failures")
    rm(outdir; recursive=true, force=true)
    mkpath(outdir)
    explained = String[]
    artifacts = String[]
    for case in selected
        failure_path = joinpath(outdir, _slug(case.name) * ".json")
        CertSDP.write_failure_report(failure_path, case.failure)
        result = run_cli("explain", failure_path, "--max-lines", "30")
        text_path = joinpath(outdir, _slug(case.name) * ".txt")
        write(text_path, result.out * result.err)
        lines = split(chomp(result.out), '\n')
        length(lines) <= 30 ||
            error("explain output for `$(case.name)` exceeded 30 lines")
        occursin("Likely next steps:", result.out) ||
            error("explain output for `$(case.name)` lacks next steps")
        occursin("Type:", result.out) ||
            error("explain output for `$(case.name)` lacks failure type")
        push!(explained, case.name)
        push!(artifacts, failure_path)
        push!(artifacts, text_path)
    end
    return (;
            passed=true,
            details=string("explained ", length(explained), " failures: ",
                           join(explained, ", ")),
            artifacts,
            selected=explained)
end

function package_registration_dry_run(repo::AbstractString)
    project_path = joinpath(repo, "Project.toml")
    isfile(project_path) || error("Project.toml not found")
    project = TOML.parsefile(project_path)
    issues = String[]
    checks = String[]

    _check_project_identity!(checks, issues, project)
    _check_compat_bounds!(checks, issues, project)
    _check_extensions!(checks, issues, project)
    _check_release_files!(checks, issues, repo)
    _check_load_and_precompile!(checks, issues, repo)

    report_path = joinpath(repo, "reports", "package_registration_dry_run.txt")
    mkpath(dirname(report_path))
    open(report_path, "w") do io
        println(io, "CertSDP package registration dry-run")
        println(io, "This is a local metadata and loadability check; it does not open a registry PR.")
        println(io)
        println(io, "Checks:")
        for check in checks
            println(io, "- ", check)
        end
        if isempty(issues)
            println(io)
            println(io, "Blockers: none")
        else
            println(io)
            println(io, "Blockers:")
            for issue in issues
                println(io, "- ", issue)
            end
        end
    end

    return (;
            passed=isempty(issues),
            details=isempty(issues) ?
                    string("local metadata dry-run passed; ",
                           project["name"], " ", project["version"]) :
                    join(issues, "; "),
            artifacts=[report_path],
            checks,
            issues)
end

function _check_project_identity!(checks, issues, project)
    for key in ("name", "uuid", "version")
        haskey(project, key) || push!(issues, "Project.toml missing `$key`")
    end
    if haskey(project, "name")
        project["name"] == "CertSDP" || push!(issues, "package name is not CertSDP")
        push!(checks, "Project.toml has package name $(project["name"])")
    end
    if haskey(project, "uuid")
        try
            UUIDs.UUID(project["uuid"])
            push!(checks, "Project.toml uuid parses")
        catch
            push!(issues, "Project.toml uuid is invalid")
        end
    end
    if haskey(project, "version")
        try
            VersionNumber(project["version"])
            push!(checks, "Project.toml version parses as $(project["version"])")
        catch
            push!(issues, "Project.toml version is not a valid VersionNumber")
        end
    end
    return nothing
end

function _check_compat_bounds!(checks, issues, project)
    compat = get(project, "compat", Dict{String, Any}())
    haskey(compat, "julia") || push!(issues, "[compat] missing julia")
    deps = Set{String}()
    for table in ("deps", "weakdeps")
        for name in keys(get(project, table, Dict{String, Any}()))
            push!(deps, String(name))
        end
    end
    for dep in sort(collect(deps))
        haskey(compat, dep) || push!(issues, "[compat] missing $dep")
    end
    isempty(deps) || push!(checks, "compat entries cover deps and weakdeps")
    return nothing
end

function _check_extensions!(checks, issues, project)
    weakdeps = Set(String.(keys(get(project, "weakdeps", Dict{String, Any}()))))
    extensions = get(project, "extensions", Dict{String, Any}())
    for (extension, deps) in extensions
        deps isa AbstractString && (deps = [deps])
        deps isa AbstractVector ||
            (push!(issues, "extension $extension must list dependency names"); continue)
        for dep in deps
            String(dep) in weakdeps ||
                push!(issues, "extension $extension references non-weakdep $dep")
        end
    end
    push!(checks, "Julia extension dependency lists are consistent")
    return nothing
end

function _check_release_files!(checks, issues, repo)
    required = ["README.md", "LICENSE", "CHANGELOG.md", "CITATION.cff",
                "codemeta.json", "NOTICE.md", "docs/validation.md",
                "docs/trust_model.md", "docs/citation.md"]
    for path in required
        full = joinpath(repo, path)
        if isfile(full) && !isempty(strip(read(full, String)))
            push!(checks, "$path exists")
        else
            push!(issues, "$path missing or empty")
        end
    end
    license = joinpath(repo, "LICENSE")
    if isfile(license)
        license_text = read(license, String)
        (occursin("Apache License", license_text) &&
         occursin("Grant of Patent License", license_text)) ||
            push!(issues, "LICENSE does not identify Apache License 2.0")
    end
    return nothing
end

function _check_load_and_precompile!(checks, issues, repo)
    try
        Pkg.activate(repo)
        Pkg.precompile()
        push!(checks, "Pkg.precompile completed")
    catch err
        push!(issues, "Pkg.precompile failed: $(sprint(showerror, err))")
    end
    try
        CertSDP.package_marker() === :exact_certificate_compiler ||
            push!(issues, "CertSDP package marker mismatch")
        push!(checks, "CertSDP loads from active project")
    catch err
        push!(issues, "CertSDP load check failed: $(sprint(showerror, err))")
    end
    return nothing
end

function run_cli(args::AbstractString...)
    out = IOBuffer()
    err = IOBuffer()
    code = CertSDP.main(collect(args); io=out, err=err)
    return (;
            code,
            out=String(take!(out)),
            err=String(take!(err)))
end

function fake_certificate_cases()
    rational = _valid_rational_cert()
    algebraic = _valid_algebraic_cert()
    sos = _valid_sos_cert()
    zero_sha = "sha256:" * repeat("0", 64)

    cases = NamedTuple[]
    push!(cases,
          (name="rational coordinate mutation",
           json=_mutated_json(rational) do data
               data["solution"]["coordinates"]["x"] = "-5"
           end))
    push!(cases,
          (name="rational principal-minor mutation",
           json=_mutated_json(rational) do data
               data["proof"]["psd"]["data"]["principal_minors"][3]["determinant"] = "19"
           end))
    push!(cases,
          (name="rational non-PSD fake matrix",
           json=CertSDP.certificate_json_v1_string(_bad_rational_nonpsd_cert())))
    push!(cases,
          (name="algebraic coordinate mutation",
           json=_mutated_json(algebraic) do data
               data["solution"]["coordinates"]["x"] = "-t"
           end))
    push!(cases,
          (name="algebraic non-PSD fake matrix",
           json=CertSDP.certificate_json_v1_string(_bad_algebraic_nonpsd_cert())))
    push!(cases,
          (name="SOS coefficient metadata mutation",
           json=_sos_coefficient_mutation(sos)))
    push!(cases,
          (name="SOS problem hash mutation",
           json=begin
               data = _json_dict(sos)
               data["problem_hash"] = zero_sha
               _json_text(data)
           end))
    return cases
end

function failure_report_cases()
    P = CertSDP.LMIProblem(Rational{BigInt}[0 1; 1 0],
                           [Rational{BigInt}[1 0; 0 1 // 2]];
                           vars=[:x])
    approx = CertSDP.ApproxSolution(P, [sqrt(big(2))];
                                    precision_bits=256,
                                    relative_tolerance="1e-12",
                                    gap_threshold="1e4")
    noisy = CertSDP.ApproxSolution(P, [sqrt(big(2))];
                                   precision_bits=256,
                                   Xhat=approx.Xhat .+ BigFloat("1e-4"),
                                   relative_tolerance="1e-12",
                                   gap_threshold="1e4")
    missing_backend = CertSDP.certify(P, approx; msolve_binary="/definitely/not/msolve")
    too_large = CertSDP.certify(P, approx; max_system_variables=1)
    noisy_failure = CertSDP.certify(P, noisy; max_linear_residual="1e-8")
    failures = [
        ("missing msolve backend", missing_backend),
        ("incidence system too large", too_large),
        ("noisy approximate solution", noisy_failure),
    ]
    cases = NamedTuple[]
    for (name, result) in failures
        result isa CertSDP.FailureResult ||
            error("expected `$name` to produce FailureResult")
        push!(cases, (name=name, failure=CertSDP.failure(result)))
    end
    return cases
end

function _valid_rational_cert()
    P = CertSDP.LMIProblem(Rational{BigInt}[1 0; 0 1],
                           [Rational{BigInt}[1 0; 0 0],
                            Rational{BigInt}[0 0; 0 1]];
                           vars=[:x, :y])
    return CertSDP.RationalCertificate(P, Rational{BigInt}[1 // 2, 1 // 3])
end

function _valid_algebraic_cert()
    root = CertSDP.AlgebraicRoot("t^2 - 2", "1", "3/2")
    alpha = CertSDP.AlgebraicElement(root, "t")
    P = CertSDP.LMIProblem(Rational{BigInt}[0 1; 1 0],
                           [Rational{BigInt}[1 0; 0 1]];
                           vars=[:x])
    return CertSDP.AlgebraicCertificate(P, root, [alpha])
end

function _valid_sos_cert()
    problem = CertSDP.build_sos_gram_problem([:x],
                                             [[0], [1]],
                                             [CertSDP.PolynomialTerm([0], 1),
                                              CertSDP.PolynomialTerm([2], 1)])
    return CertSDP.SOSGramCertificate(problem, Rational{BigInt}[1 0; 0 1])
end

function _bad_rational_nonpsd_cert()
    P = CertSDP.LMIProblem(Rational{BigInt}[1 2; 2 1],
                           [zeros(Rational{BigInt}, 2, 2)];
                           vars=[:z])
    matrix = CertSDP.substitute(P, Rational{BigInt}[0])
    proof = CertSDP._rational_psd_proof_unchecked(matrix)
    without_hash = CertSDP.RationalCertificate(P, Rational{BigInt}[0], proof, "")
    return CertSDP.RationalCertificate(P, Rational{BigInt}[0], proof,
                                       CertSDP.rational_certificate_hash(without_hash))
end

function _bad_algebraic_nonpsd_cert()
    root = CertSDP.AlgebraicRoot("t^2 - 2", "1", "3/2")
    alpha = CertSDP.AlgebraicElement(root, "t")
    P = CertSDP.LMIProblem(Rational{BigInt}[0 2; 2 0],
                           [Rational{BigInt}[1 0; 0 1]];
                           vars=[:x])
    matrix = CertSDP.substitute(P, [alpha])
    proof = CertSDP.AlgebraicPSDProof(:principal_minors,
                                      matrix,
                                      [CertSDP.PrincipalMinorProof([1], alpha),
                                       CertSDP.PrincipalMinorProof([2], alpha),
                                       CertSDP.PrincipalMinorProof([1, 2],
                                                                   alpha^2 - 4)])
    without_hash = CertSDP.AlgebraicCertificate(P, root, [alpha], proof, "")
    return CertSDP.AlgebraicCertificate(P, root, [alpha], proof,
                                        CertSDP.algebraic_certificate_hash(without_hash))
end

function _sos_coefficient_mutation(cert)
    matches = copy(cert.coefficient_proof)
    first_match = matches[1]
    matches[1] = CertSDP.SOSCoefficientMatch(first_match.exponents,
                                             first_match.target_coefficient + 1,
                                             first_match.gram_coefficient,
                                             first_match.contributions)
    fake = CertSDP.SOSGramCertificate(cert.problem,
                                      cert.gram_matrix,
                                      cert.lmi_certificate,
                                      matches,
                                      cert.decomposition,
                                      "")
    return CertSDP.certificate_json_v1_string(_rehash_certificate(fake))
end

function _mutated_json(cert, mutator::Function)
    data = _json_dict(cert)
    mutator(data)
    return _rehash_json(_json_text(data))
end

_mutated_json(mutator::Function, cert) = _mutated_json(cert, mutator)

function _json_dict(cert)
    return JSON3.read(CertSDP.certificate_json_v1_string(cert), Dict{String, Any})
end

function _json_text(data)
    io = IOBuffer()
    JSON3.pretty(io, data)
    println(io)
    return String(take!(io))
end

function _rehash_json(json_text::AbstractString)
    parsed = CertSDP.parse_certificate_json(json_text)
    return CertSDP.certificate_json_v1_string(_rehash_certificate(parsed))
end

function _rehash_certificate(cert)
    if cert isa CertSDP.RationalCertificate
        return CertSDP.RationalCertificate(cert.problem,
                                           cert.solution,
                                           cert.psd_proof,
                                           CertSDP.rational_certificate_hash(cert))
    elseif cert isa CertSDP.AlgebraicCertificate
        return CertSDP.AlgebraicCertificate(cert.problem,
                                            cert.root,
                                            cert.solution,
                                            cert.psd_proof,
                                            CertSDP.algebraic_certificate_hash(cert),
                                            cert.provenance)
    elseif cert isa CertSDP.SOSGramCertificate
        return CertSDP.SOSGramCertificate(cert.problem,
                                          cert.gram_matrix,
                                          cert.lmi_certificate,
                                          cert.coefficient_proof,
                                          cert.decomposition,
                                          CertSDP.sos_gram_certificate_hash(cert))
    end
    error("unsupported certificate type $(typeof(cert))")
end

function _slug(text::AbstractString)
    slug = replace(lowercase(String(text)), r"[^a-z0-9]+" => "_")
    slug = strip(slug, '_')
    return isempty(slug) ? "case" : slug
end

function write_drill_report(options::DrillOptions, results;
                            selected_validation=String[],
                            selected_msolve=String[],
                            selected_fakes=String[],
                            selected_failures=String[])
    path = joinpath(options.out, "release_audit_report.md")
    open(path, "w") do io
        println(io, "# CertSDP Release Audit Drill Report")
        println(io)
        println(io, "- Repository: `", options.repo, "`")
        println(io, "- Seed: `", options.seed, "`")
        println(io, "- Mode: `", options.mode, "`")
        println(io, "- Overall: `",
                all(result -> result.status == "pass", results) ? "pass" : "blocker",
                "`")
        println(io)
        println(io, "## Checks")
        println(io)
        println(io, "| Check | Status | Details |")
        println(io, "| --- | --- | --- |")
        for result in results
            println(io, "| ", _md(result.name), " | `", result.status, "` | ",
                    _md(result.details), " |")
        end
        _write_selection(io, "Random validation sample", selected_validation)
        _write_selection(io, "With-msolve sample", selected_msolve)
        _write_selection(io, "Fake certificates rejected", selected_fakes)
        _write_selection(io, "Failure explanations", selected_failures)
        artifacts = unique(vcat([result.artifacts for result in results]...))
        if !isempty(artifacts)
            println(io)
            println(io, "## Artifacts")
            for artifact in artifacts
                println(io, "- `", artifact, "`")
            end
        end
    end
    return path
end

function _write_selection(io::IO, title::AbstractString, items)
    isempty(items) && return nothing
    println(io)
    println(io, "## ", title)
    for item in items
        println(io, "- `", item, "`")
    end
    return nothing
end

function _md(text::AbstractString)
    return replace(String(text), "|" => "\\|", "\n" => "<br>")
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    exit(ReleaseAuditDrill.main(ARGS))
end
