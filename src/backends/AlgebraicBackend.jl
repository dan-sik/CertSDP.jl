const DEFAULT_ALGEBRAIC_BACKEND_TIMEOUT_SECONDS = 300.0

"""
    AlgebraicBackend

Abstract interface for optional exact algebraic system backends. Backends may
use external processes, but their output is only candidate data for the exact
CertSDP verifier.
"""
abstract type AlgebraicBackend end

"""
    AlgebraicBackendProvenance

Machine-readable provenance for one backend invocation. Paths are artifact
paths when the caller requested a persistent artifact directory; otherwise
they may be `nothing` even though stdout/stderr were captured in memory.
"""
struct AlgebraicBackendProvenance
    backend::Symbol
    executable::Union{Nothing, String}
    version::Union{Nothing, String}
    command::Vector{String}
    timeout_seconds::Union{Nothing, Float64}
    exit_code::Union{Nothing, Int}
    timed_out::Bool
    elapsed_seconds::Union{Nothing, Float64}
    workdir::Union{Nothing, String}
    input_path::Union{Nothing, String}
    output_path::Union{Nothing, String}
    stdout_path::Union{Nothing, String}
    stderr_path::Union{Nothing, String}
    artifacts::Dict{Symbol, String}
    options::Dict{Symbol, Any}
end

"""
    BackendResultCache(cache_dir; enabled=true)

Optional file-backed cache for algebraic backend results. Entries are keyed by
the exact polynomial system hash plus backend options, never by approximate
solver data. Cached outputs are still only candidate data and must pass the
exact CertSDP verifier.
"""
struct BackendResultCache
    cache_dir::String
    enabled::Bool

    function BackendResultCache(cache_dir::AbstractString; enabled::Bool=true)
        path = normpath(String(cache_dir))
        return new(path, Bool(enabled))
    end
end

"""
    AlgebraicBackendFailure

Structured failure from an optional algebraic backend. This is separate from
`CertificationFailure`: it records what happened inside the backend adapter,
while certifier-level failures decide how to continue or report to users.
"""
struct AlgebraicBackendFailure <: Exception
    backend::Symbol
    reason::Symbol
    message::String
    provenance::AlgebraicBackendProvenance
    stdout::String
    stderr::String
    backend_output::String
    artifacts::Dict{Symbol, String}
    diagnostics::Dict{Symbol, Any}
end

"""
    AlgebraicSolveResult

Result returned by `solve_system(system, backend)`. Successful calls have
`failure === nothing`; unavailable, timed-out, process, and parse failures are
returned as `AlgebraicBackendFailure` so optional backends never crash core
test suites.
"""
struct AlgebraicSolveResult
    status::Symbol
    output::Any
    backend_log::String
    stdout::String
    stderr::String
    backend_output::String
    timings::Dict{Symbol, Any}
    warnings::Vector{String}
    provenance::AlgebraicBackendProvenance
    failure::Union{Nothing, AlgebraicBackendFailure}
    artifacts::Dict{Symbol, String}
end

function Base.showerror(io::IO, failure::AlgebraicBackendFailure)
    return print(io, failure.backend, " backend ", failure.reason, ": ", failure.message)
end

backend_name(backend::AlgebraicBackend) = Symbol(nameof(typeof(backend)))

function solve_system(system::PolynomialSystem, backend::AlgebraicBackend)
    throw(MethodError(solve_system, (system, backend)))
end

function algebraic_backend_provenance_json(provenance::AlgebraicBackendProvenance)
    return (;
            backend=String(provenance.backend),
            executable=provenance.executable,
            version=provenance.version,
            command=provenance.command,
            timeout_seconds=isnothing(provenance.timeout_seconds) ? nothing :
                            string(provenance.timeout_seconds),
            exit_code=provenance.exit_code,
            timed_out=provenance.timed_out,
            elapsed_seconds=isnothing(provenance.elapsed_seconds) ? nothing :
                            string(provenance.elapsed_seconds),
            workdir=provenance.workdir,
            input_path=provenance.input_path,
            output_path=provenance.output_path,
            stdout_path=provenance.stdout_path,
            stderr_path=provenance.stderr_path,
            artifacts=Dict(String(key) => value for (key, value) in provenance.artifacts),
            options=_certification_diagnostics_json(provenance.options),)
end

function algebraic_backend_failure_json(failure::AlgebraicBackendFailure)
    return (;
            failure_type="AlgebraicBackendFailure",
            backend=String(failure.backend),
            reason=String(failure.reason),
            message=failure.message,
            provenance=algebraic_backend_provenance_json(failure.provenance),
            stdout=failure.stdout,
            stderr=failure.stderr,
            backend_output=failure.backend_output,
            artifacts=Dict(String(key) => value for (key, value) in failure.artifacts),
            diagnostics=_certification_diagnostics_json(failure.diagnostics),)
end

function _empty_backend_provenance(backend::Symbol;
                                   executable=nothing,
                                   version=nothing,
                                   command=String[],
                                   timeout_seconds=nothing,
                                   exit_code=nothing,
                                   timed_out=false,
                                   elapsed_seconds=nothing,
                                   workdir=nothing,
                                   input_path=nothing,
                                   output_path=nothing,
                                   stdout_path=nothing,
                                   stderr_path=nothing,
                                   artifacts=Dict{Symbol, String}(),
                                   options=Dict{Symbol, Any}(),)
    return AlgebraicBackendProvenance(backend,
                                      isnothing(executable) ? nothing : String(executable),
                                      isnothing(version) ? nothing : String(version),
                                      String.(command),
                                      isnothing(timeout_seconds) ? nothing :
                                      Float64(timeout_seconds),
                                      isnothing(exit_code) ? nothing : Int(exit_code),
                                      Bool(timed_out),
                                      isnothing(elapsed_seconds) ? nothing :
                                      Float64(elapsed_seconds),
                                      isnothing(workdir) ? nothing : String(workdir),
                                      isnothing(input_path) ? nothing : String(input_path),
                                      isnothing(output_path) ? nothing :
                                      String(output_path),
                                      isnothing(stdout_path) ? nothing :
                                      String(stdout_path),
                                      isnothing(stderr_path) ? nothing :
                                      String(stderr_path),
                                      Dict{Symbol, String}(artifacts),
                                      Dict{Symbol, Any}(options))
end

function _backend_log(; command=String[],
                      version=nothing,
                      stdout="",
                      stderr="",
                      backend_output="",
                      failure_message=nothing)
    io = IOBuffer()
    !isempty(command) && println(io, "command: ", join(command, " "))
    !isnothing(version) && println(io, "version: ", version)
    if !isempty(stdout)
        println(io, "\n[stdout]")
        print(io, stdout)
        endswith(stdout, "\n") || println(io)
    end
    if !isempty(stderr)
        println(io, "\n[stderr]")
        print(io, stderr)
        endswith(stderr, "\n") || println(io)
    end
    if !isempty(backend_output)
        println(io, "\n[backend_output]")
        print(io, backend_output)
        endswith(backend_output, "\n") || println(io)
    end
    if !isnothing(failure_message)
        println(io, "\n[failure]")
        println(io, failure_message)
    end
    return String(take!(io))
end

function _write_json_artifact(path::AbstractString, object)
    open(path, "w") do io
        JSON3.pretty(io, object)
        return println(io)
    end
    return path
end
