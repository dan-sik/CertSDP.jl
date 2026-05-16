#!/usr/bin/env julia

using Pkg

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))

function _usage()
    return """
    Usage:
      julia scripts/run_validation.jl [--out PATH] [--generated-dir PATH] [--budget validation] [--timeout SECONDS]

    Runs the public validation artifact in a temporary Julia environment. The
    environment develops this checkout and installs the optional Clarabel
    numerical oracle used by the solve -> diagnose -> certify validation row.
    Strict certificate replay remains independent of Clarabel, msolve, and
    backend logs.
    """
end

function _parse_args(args)
    options = Dict{String, String}("out" => joinpath(REPO_ROOT, "benchmarks",
                                                     "VALIDATION_REPORT.md"),
                                   "generated-dir" => joinpath(REPO_ROOT,
                                                               "benchmarks",
                                                               "generated"),
                                   "budget" => "validation",
                                   "timeout" => "")
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg in ("-h", "--help")
            println(strip(_usage()))
            exit(0)
        elseif arg in ("--out", "--generated-dir", "--budget", "--timeout")
            i == length(args) && error("missing value for $arg")
            options[arg[3:end]] = args[i + 1]
            i += 2
        else
            error("unknown argument: $arg\n\n$(_usage())")
        end
    end
    return options
end

function main(args=ARGS)
    options = _parse_args(args)
    out = abspath(options["out"])
    generated_dir = abspath(options["generated-dir"])
    budget = Symbol(options["budget"])
    timeout = isempty(options["timeout"]) ? nothing : parse(Float64, options["timeout"])

    println("[INFO] preparing temporary validation environment")
    Pkg.activate(; temp=true)
    Pkg.develop(Pkg.PackageSpec(; path=REPO_ROOT))
    Pkg.add(; name="Clarabel", version="0.11.1")

    certsdp = Base.require(Base.PkgId(Base.UUID("ed312aa7-6e2f-4f9d-9b07-28f4d6d8238e"),
                                      "CertSDP"))

    kwargs = (; out, generated_dir, subset=:validation, budget)
    result = cd(REPO_ROOT) do
        if isnothing(timeout)
            return Base.invokelatest(certsdp.run_benchmarks,
                                     "benchmarks"; kwargs...)
        end
        return Base.invokelatest(certsdp.run_benchmarks,
                                 "benchmarks"; kwargs..., timeout_seconds=timeout)
    end

    if result.passed
        println("[OK] validation expected statuses matched")
        println("[OK] report: ", out)
        println("[OK] generated artifacts: ", generated_dir)
        return 0
    end

    println(stderr, "[FAIL] validation expected status mismatch")
    for mismatch in result.mismatches
        println(stderr, "[FAIL] ", mismatch)
    end
    return 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
