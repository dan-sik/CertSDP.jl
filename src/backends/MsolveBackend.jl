"""
    MsolveInterval(lower, upper)

Closed rational interval returned by msolve for one coordinate of an isolated
real solution box. Unlike `RationalInterval`, this allows point intervals such
as `[1, 1]`, which msolve uses for rational coordinates.
"""
struct MsolveInterval
    lower::Rational{BigInt}
    upper::Rational{BigInt}

    function MsolveInterval(lower, upper)
        lo = _to_big_rational(lower; name=:msolve_interval_lower)
        hi = _to_big_rational(upper; name=:msolve_interval_upper)
        lo <= hi || throw(ArgumentError("msolve interval must satisfy lower <= upper"))
        return new(lo, hi)
    end
end

"""
    RURSolution

Basic rational univariate representation parsed from `msolve -P 1` or
`msolve -P 2` output. For msolve's characteristic-zero parametrization, the
last variable in `variable_order` is the parameter `t`; earlier coordinates
are represented by the raw numerator polynomials and integer divisors returned
by msolve.
"""
struct RURSolution
    variable_order::Vector{Symbol}
    linear_form::Vector{Rational{BigInt}}
    minimal_polynomial::UnivariatePolynomial
    denominator::UnivariatePolynomial
    numerators::Vector{UnivariatePolynomial}
    numerator_denominators::Vector{BigInt}
end

"""
    MsolveOutput

Parsed msolve output. `status` is one of `:finite`, `:empty`, or
`:positive_dimensional`. `rur` is present when msolve was called with `-P 1`
or `-P 2`; `real_solution_boxes` is present when msolve emitted real isolated
solutions.
"""
struct MsolveOutput
    status::Symbol
    characteristic::Union{Nothing, Int}
    degree::Union{Nothing, Int}
    variable_order::Vector{Symbol}
    rur::Union{Nothing, RURSolution}
    real_solution_boxes::Vector{Vector{MsolveInterval}}
    raw_output::String
end

struct MsolveNotFoundError <: Exception
    message::String
end

Base.showerror(io::IO, err::MsolveNotFoundError) = print(io, err.message)

"""
    MsolveBackend(; kwargs...)

Optional external-process adapter for msolve. It never participates in the
trusted verifier path; it only produces algebraic candidates plus provenance.
Use `workdir` or `artifact_dir` to persist input/output/stdout/stderr logs.
"""
struct MsolveBackend <: AlgebraicBackend
    binary::Union{Nothing, String}
    characteristic::Int
    precision::Int
    parametrization::Int
    threads::Int
    timeout_seconds::Union{Nothing, Float64}
    workdir::Union{Nothing, String}
    artifact_dir::Union{Nothing, String}
    result_cache::Union{Nothing, BackendResultCache}

    function MsolveBackend(; binary=nothing,
                           characteristic::Integer=0,
                           precision::Integer=128,
                           parametrization::Integer=1,
                           threads::Integer=1,
                           timeout_seconds=DEFAULT_ALGEBRAIC_BACKEND_TIMEOUT_SECONDS,
                           workdir=nothing,
                           artifact_dir=nothing,
                           cache_dir=nothing,
                           cache::Bool=!isnothing(cache_dir),
                           result_cache=nothing,)
        characteristic >= 0 ||
            throw(ArgumentError("msolve characteristic must be nonnegative"))
        precision > 0 || throw(ArgumentError("msolve precision must be positive"))
        parametrization in (0, 1, 2) ||
            throw(ArgumentError("msolve parametrization must be 0, 1, or 2"))
        threads > 0 || throw(ArgumentError("msolve threads must be positive"))
        timeout = isnothing(timeout_seconds) ? nothing : Float64(timeout_seconds)
        (isnothing(timeout) || timeout > 0) ||
            throw(ArgumentError("msolve timeout_seconds must be positive or nothing"))
        backend_cache = if result_cache isa BackendResultCache
            result_cache
        elseif !isnothing(cache_dir)
            BackendResultCache(String(cache_dir); enabled=cache)
        else
            nothing
        end
        return new(isnothing(binary) ? nothing : String(binary),
                   Int(characteristic),
                   Int(precision),
                   Int(parametrization),
                   Int(threads),
                   timeout,
                   isnothing(workdir) ? nothing : String(workdir),
                   isnothing(artifact_dir) ? nothing : String(artifact_dir),
                   backend_cache)
    end
end

"""
    SageMsolveBackend

Optional Sage/msolve adapter. It writes the same exact polynomial-system input
as `MsolveBackend`, runs a Sage adapter script, parses msolve-compatible
candidate output, and records provenance/artifacts. When Sage is unavailable or
the optional path is not configured, it returns an `AlgebraicBackendFailure`
instead of touching the core verifier.
"""
struct SageMsolveBackend <: AlgebraicBackend
    binary::Union{Nothing, String}
    msolve_binary::Union{Nothing, String}
    precision::Int
    parametrization::Int
    threads::Int
    timeout_seconds::Union{Nothing, Float64}
    workdir::Union{Nothing, String}
    artifact_dir::Union{Nothing, String}

    function SageMsolveBackend(; binary=nothing,
                               msolve_binary=nothing,
                               precision::Integer=128,
                               parametrization::Integer=1,
                               threads::Integer=1,
                               timeout_seconds=DEFAULT_ALGEBRAIC_BACKEND_TIMEOUT_SECONDS,
                               workdir=nothing,
                               artifact_dir=nothing,)
        precision > 0 || throw(ArgumentError("sage/msolve precision must be positive"))
        parametrization >= 0 ||
            throw(ArgumentError("sage/msolve parametrization must be nonnegative"))
        threads > 0 || throw(ArgumentError("sage/msolve threads must be positive"))
        timeout = isnothing(timeout_seconds) ? nothing : Float64(timeout_seconds)
        (isnothing(timeout) || timeout > 0) ||
            throw(ArgumentError("sage timeout_seconds must be positive or nothing"))
        return new(isnothing(binary) ? nothing : String(binary),
                   isnothing(msolve_binary) ? nothing : String(msolve_binary),
                   Int(precision),
                   Int(parametrization),
                   Int(threads),
                   timeout,
                   isnothing(workdir) ? nothing : String(workdir),
                   isnothing(artifact_dir) ? nothing : String(artifact_dir))
    end
end

Base.:(==)(a::MsolveInterval, b::MsolveInterval) = a.lower == b.lower && a.upper == b.upper

function Base.show(io::IO, interval::MsolveInterval)
    return print(io, "[", _rational_string(interval.lower), ", ",
                 _rational_string(interval.upper), "]")
end

"""
    msolve_input(system; characteristic=0) -> String

Serialize a `PolynomialSystem` to msolve's `.ms` input format.
Zero equations are omitted because they do not change the solution set and can
confuse external polynomial parsers.
"""
function msolve_input(system::PolynomialSystem; characteristic::Integer=0)
    characteristic >= 0 || throw(ArgumentError("msolve characteristic must be nonnegative"))
    variable_names = _msolve_variable_names(system)
    equations = [equation for equation in system.equations if !iszero(equation)]
    isempty(equations) &&
        throw(ArgumentError("msolve input requires at least one nonzero equation"))

    io = IOBuffer()
    println(io, join(variable_names, ","))
    println(io, characteristic)
    for (i, equation) in enumerate(equations)
        text = _msolve_polynomial_string(equation)
        print(io, text)
        i < length(equations) && print(io, ",")
        println(io)
    end
    return String(take!(io))
end

"""
    write_msolve_input(path, system; characteristic=0)

Write `system` in msolve `.ms` format and return `path`.
"""
function write_msolve_input(path::AbstractString, system::PolynomialSystem; kwargs...)
    open(path, "w") do io
        return write(io, msolve_input(system; kwargs...))
    end
    return path
end

"""
    find_msolve(; binary=nothing) -> Union{String,Nothing}

Find an executable msolve binary. The explicit `binary` argument wins, followed
by `ENV["CERTSDP_MSOLVE"]`, then `PATH`.
"""
function find_msolve(; binary=nothing)
    if !isnothing(binary)
        return _msolve_executable_path(String(binary))
    end

    env_path = get(ENV, "CERTSDP_MSOLVE", "")
    if !isempty(strip(env_path))
        found = _msolve_executable_path(strip(env_path))
        !isnothing(found) && return found
    end

    return Sys.which("msolve")
end

"""
    has_msolve(; binary=nothing) -> Bool

Return whether an msolve executable is available.
"""
has_msolve(; binary=nothing) = !isnothing(find_msolve(; binary))

"""
    msolve_version(; binary=nothing, timeout_seconds=10) -> Union{String,Nothing}

Capture the msolve version string without making msolve a hard dependency.
"""
function msolve_version(; binary=nothing, timeout_seconds=10)
    executable = find_msolve(; binary)
    isnothing(executable) && return nothing
    return _external_tool_version([executable, "--version"]; timeout_seconds)
end

"""
    solve_with_msolve(system; kwargs...) -> MsolveOutput

Run an external msolve process on `system` and parse its output. This is an
optional backend adapter: if msolve is unavailable, it throws
`MsolveNotFoundError` instead of affecting the core verifier.
"""
function solve_with_msolve(system::PolynomialSystem;
                           binary=nothing,
                           characteristic::Integer=0,
                           precision::Integer=128,
                           parametrization::Integer=1,
                           threads::Integer=1,
                           timeout_seconds=DEFAULT_ALGEBRAIC_BACKEND_TIMEOUT_SECONDS,
                           workdir=nothing,
                           artifact_dir=nothing,
                           cache_dir=nothing,
                           cache::Bool=!isnothing(cache_dir),)
    backend = MsolveBackend(; binary,
                            characteristic,
                            precision,
                            parametrization,
                            threads,
                            timeout_seconds,
                            workdir,
                            artifact_dir,
                            cache_dir,
                            cache)
    result = solve_system(system, backend)
    if !isnothing(result.failure)
        if result.failure.reason === :unavailable
            throw(MsolveNotFoundError(result.failure.message))
        end
        throw(result.failure)
    end
    return result.output
end

"""
    parse_msolve_output(text; variables=Symbol[]) -> MsolveOutput

Parse the bracketed textual output emitted by msolve for finite real solutions
and the basic characteristic-zero rational parametrization.
"""
function parse_msolve_output(text::AbstractString;
                             variables::AbstractVector{Symbol}=Symbol[])
    source = replace(String(text), ":" => "")
    parsed, parser = _msolve_parse_value(source, 1)
    _msolve_skip_ws(source, parser.index) <= lastindex(source) &&
        throw(ArgumentError("unexpected trailing data in msolve output"))

    raw = String(text)
    parsed isa Vector || throw(ArgumentError("msolve output must be a list"))
    isempty(parsed) && throw(ArgumentError("msolve output list must not be empty"))

    first_value = _msolve_int(parsed[1], "output[1]")
    if first_value == -1
        return MsolveOutput(:empty, nothing, nothing, Symbol[], nothing,
                            Vector{Vector{MsolveInterval}}(), raw)
    elseif first_value > 0
        return MsolveOutput(:positive_dimensional, nothing, nothing, Symbol[], nothing,
                            Vector{Vector{MsolveInterval}}(), raw)
    elseif first_value != 0
        throw(ArgumentError("unsupported msolve dimension marker `$first_value`"))
    end

    length(parsed) >= 2 || throw(ArgumentError("finite msolve output is missing payload"))
    payload = parsed[2]
    payload isa Vector || throw(ArgumentError("finite msolve payload must be a list"))

    characteristic = nothing
    degree_value = nothing
    variable_order = Symbol.(variables)
    rur = nothing
    boxes = Vector{Vector{MsolveInterval}}()

    if _msolve_looks_like_parametrization(payload)
        characteristic, degree_value, variable_order, rur = _msolve_parse_parametrization(payload)
        if length(parsed) >= 3
            boxes = _msolve_parse_real_block(parsed[3], "output[3]")
        end
    else
        boxes = _msolve_parse_real_block(payload, "output[2]")
    end

    return MsolveOutput(:finite, characteristic, degree_value, variable_order, rur, boxes,
                        raw)
end

function solve_system(system::PolynomialSystem, backend::MsolveBackend)
    cached = _msolve_cached_result(system, backend)
    !isnothing(cached) && return cached

    executable = find_msolve(; binary=backend.binary)
    options = _msolve_backend_options(backend)
    if isnothing(executable)
        provenance = _empty_backend_provenance(:msolve;
                                               executable=backend.binary,
                                               timeout_seconds=backend.timeout_seconds,
                                               options)
        failure = AlgebraicBackendFailure(:msolve,
                                          :unavailable,
                                          "msolve executable not found; install msolve or set CERTSDP_MSOLVE",
                                          provenance,
                                          "",
                                          "",
                                          "",
                                          Dict{Symbol, String}(),
                                          Dict{Symbol, Any}(:binary => backend.binary))
        return _algebraic_failure_result(failure)
    end

    version = msolve_version(; binary=executable,
                             timeout_seconds=_version_timeout(backend.timeout_seconds))
    run_dir = _msolve_persistent_dir(backend)
    if isnothing(run_dir)
        return mktempdir() do dir
            return _solve_system_msolve_in_dir(system,
                                               backend,
                                               executable,
                                               version,
                                               dir;
                                               persist_artifacts=false)
        end
    end

    mkpath(run_dir)
    return _solve_system_msolve_in_dir(system,
                                       backend,
                                       executable,
                                       version,
                                       run_dir;
                                       persist_artifacts=true)
end

function solve_system(system::PolynomialSystem, backend::SageMsolveBackend)
    executable = _find_sage(; binary=backend.binary)
    options = Dict{Symbol, Any}(:timeout_seconds => backend.timeout_seconds,
                                :workdir => backend.workdir,
                                :artifact_dir => backend.artifact_dir,
                                :msolve_binary => backend.msolve_binary,
                                :precision => backend.precision,
                                :parametrization => backend.parametrization,
                                :threads => backend.threads)
    if isnothing(executable)
        provenance = _empty_backend_provenance(:sage_msolve;
                                               executable=backend.binary,
                                               timeout_seconds=backend.timeout_seconds,
                                               workdir=backend.workdir,
                                               options)
        failure = AlgebraicBackendFailure(:sage_msolve,
                                          :unavailable,
                                          "SageMath executable not found; install Sage or pass SageMsolveBackend(binary=...)",
                                          provenance,
                                          "",
                                          "",
                                          "",
                                          Dict{Symbol, String}(),
                                          Dict{Symbol, Any}())
        return _algebraic_failure_result(failure)
    end

    version = _external_tool_version([executable, "--version"];
                                     timeout_seconds=_version_timeout(backend.timeout_seconds))
    run_dir = _sage_msolve_persistent_dir(backend)
    if isnothing(run_dir)
        return mktempdir() do dir
            return _solve_system_sage_msolve_in_dir(system,
                                                    backend,
                                                    executable,
                                                    version,
                                                    dir;
                                                    persist_artifacts=false)
        end
    end

    mkpath(run_dir)
    return _solve_system_sage_msolve_in_dir(system,
                                            backend,
                                            executable,
                                            version,
                                            run_dir;
                                            persist_artifacts=true)
end

function _solve_system_sage_msolve_in_dir(system::PolynomialSystem,
                                          backend::SageMsolveBackend,
                                          executable::AbstractString,
                                          version::Union{Nothing, String},
                                          dir::AbstractString;
                                          persist_artifacts::Bool)
    input_path = joinpath(dir, "certsdp-sage-msolve-input.ms")
    output_path = joinpath(dir, "certsdp-sage-msolve-output.res")
    stdout_path = joinpath(dir, "certsdp-sage-msolve-stdout.log")
    stderr_path = joinpath(dir, "certsdp-sage-msolve-stderr.log")
    script_path = joinpath(dir, "certsdp-sage-msolve-adapter.py")
    command_path = joinpath(dir, "certsdp-sage-msolve-command.txt")
    provenance_path = joinpath(dir, "certsdp-sage-msolve-provenance.json")
    backend_log_path = joinpath(dir, "certsdp-sage-msolve-backend.log")
    failure_path = joinpath(dir, "certsdp-sage-msolve-failure.json")

    artifacts = persist_artifacts ?
                Dict{Symbol, String}(:input => input_path,
                                     :output => output_path,
                                     :stdout => stdout_path,
                                     :stderr => stderr_path,
                                     :script => script_path,
                                     :command => command_path,
                                     :provenance => provenance_path,
                                     :backend_log => backend_log_path) :
                Dict{Symbol, String}()

    msolve_executable = isnothing(backend.msolve_binary) ? "msolve" :
                        backend.msolve_binary
    command = String[executable,
                     script_path,
                     input_path,
                     output_path,
                     msolve_executable,
                     string(backend.parametrization),
                     string(backend.precision),
                     string(backend.threads)]
    persist_artifacts && write(command_path, join(command, " ") * "\n")

    try
        write_msolve_input(input_path, system; characteristic=0)
        write(script_path, _sage_msolve_adapter_script())
    catch err
        provenance = _sage_msolve_provenance(backend,
                                             executable,
                                             version,
                                             command,
                                             artifacts;
                                             workdir=dir,
                                             input_path,
                                             output_path,
                                             stdout_path,
                                             stderr_path)
        failure = AlgebraicBackendFailure(:sage_msolve,
                                          :invalid_input,
                                          sprint(showerror, err),
                                          provenance,
                                          "",
                                          "",
                                          "",
                                          artifacts,
                                          Dict{Symbol, Any}(:exception_type => string(typeof(err))))
        return _algebraic_failure_result(failure; persist_artifacts,
                                         failure_path,
                                         backend_log_path,
                                         provenance_path)
    end

    process_result = try
        _run_backend_process(command;
                             stdout_path,
                             stderr_path,
                             timeout_seconds=backend.timeout_seconds)
    catch err
        provenance = _sage_msolve_provenance(backend,
                                             executable,
                                             version,
                                             command,
                                             artifacts;
                                             workdir=dir,
                                             input_path,
                                             output_path,
                                             stdout_path,
                                             stderr_path)
        failure = AlgebraicBackendFailure(:sage_msolve,
                                          :process_error,
                                          sprint(showerror, err),
                                          provenance,
                                          "",
                                          "",
                                          "",
                                          artifacts,
                                          Dict{Symbol, Any}(:exception_type => string(typeof(err))))
        return _algebraic_failure_result(failure; persist_artifacts,
                                         failure_path,
                                         backend_log_path,
                                         provenance_path)
    end

    stdout = isfile(stdout_path) ? read(stdout_path, String) : ""
    stderr = isfile(stderr_path) ? read(stderr_path, String) : ""
    backend_output = isfile(output_path) ? read(output_path, String) : ""
    provenance = _sage_msolve_provenance(backend,
                                         executable,
                                         version,
                                         command,
                                         artifacts;
                                         workdir=dir,
                                         input_path,
                                         output_path,
                                         stdout_path,
                                         stderr_path,
                                         exit_code=process_result.exit_code,
                                         timed_out=process_result.timed_out,
                                         elapsed_seconds=process_result.elapsed_seconds)

    if process_result.timed_out
        failure = AlgebraicBackendFailure(:sage_msolve,
                                          :timeout,
                                          "Sage/msolve adapter exceeded timeout of $(backend.timeout_seconds) seconds",
                                          provenance,
                                          stdout,
                                          stderr,
                                          backend_output,
                                          artifacts,
                                          Dict{Symbol, Any}(:timeout_seconds => string(backend.timeout_seconds)))
        return _algebraic_failure_result(failure; persist_artifacts,
                                         failure_path,
                                         backend_log_path,
                                         provenance_path)
    elseif process_result.exit_code != 0
        failure = AlgebraicBackendFailure(:sage_msolve,
                                          :process_failed,
                                          _msolve_failure_message(stdout, stderr,
                                                                  process_result.exit_code),
                                          provenance,
                                          stdout,
                                          stderr,
                                          backend_output,
                                          artifacts,
                                          Dict{Symbol, Any}(:exit_code => process_result.exit_code))
        return _algebraic_failure_result(failure; persist_artifacts,
                                         failure_path,
                                         backend_log_path,
                                         provenance_path)
    end

    parsed_output = try
        parse_msolve_output(backend_output; variables=variable_symbols(system))
    catch err
        failure = AlgebraicBackendFailure(:sage_msolve,
                                          :parse_failed,
                                          sprint(showerror, err),
                                          provenance,
                                          stdout,
                                          stderr,
                                          backend_output,
                                          artifacts,
                                          Dict{Symbol, Any}(:exception_type => string(typeof(err))))
        return _algebraic_failure_result(failure; persist_artifacts,
                                         failure_path,
                                         backend_log_path,
                                         provenance_path)
    end

    backend_log = _backend_log(; command, version, stdout, stderr, backend_output)
    if persist_artifacts
        write(backend_log_path, backend_log)
        _write_json_artifact(provenance_path,
                             algebraic_backend_provenance_json(provenance))
    end

    return AlgebraicSolveResult(:success,
                                parsed_output,
                                backend_log,
                                stdout,
                                stderr,
                                backend_output,
                                Dict{Symbol, Any}(:elapsed_seconds => process_result.elapsed_seconds),
                                String[],
                                provenance,
                                nothing,
                                artifacts)
end

function _sage_msolve_adapter_script()
    return """
import subprocess
import sys

input_path, output_path, msolve, parametrization, precision, threads = sys.argv[1:7]
cmd = [msolve, "-P", parametrization, "-p", precision, "-t", threads,
       "-f", input_path, "-o", output_path]
proc = subprocess.run(cmd, capture_output=True, text=True)
sys.stdout.write(proc.stdout)
sys.stderr.write(proc.stderr)
sys.exit(proc.returncode)
"""
end

function _sage_msolve_persistent_dir(backend::SageMsolveBackend)
    !isnothing(backend.artifact_dir) && return backend.artifact_dir
    !isnothing(backend.workdir) && return backend.workdir
    return nothing
end

function _sage_msolve_provenance(backend::SageMsolveBackend,
                                 executable::AbstractString,
                                 version::Union{Nothing, String},
                                 command::Vector{String},
                                 artifacts::Dict{Symbol, String};
                                 workdir,
                                 input_path,
                                 output_path,
                                 stdout_path,
                                 stderr_path,
                                 exit_code=nothing,
                                 timed_out=false,
                                 elapsed_seconds=nothing)
    return _empty_backend_provenance(:sage_msolve;
                                     executable,
                                     version,
                                     command,
                                     timeout_seconds=backend.timeout_seconds,
                                     exit_code,
                                     timed_out,
                                     elapsed_seconds,
                                     workdir,
                                     input_path,
                                     output_path,
                                     stdout_path,
                                     stderr_path,
                                     artifacts,
                                     options=Dict{Symbol, Any}(:timeout_seconds => backend.timeout_seconds,
                                                               :workdir => backend.workdir,
                                                               :artifact_dir => backend.artifact_dir,
                                                               :msolve_binary => backend.msolve_binary,
                                                               :precision => backend.precision,
                                                               :parametrization => backend.parametrization,
                                                               :threads => backend.threads))
end

function _solve_system_msolve_in_dir(system::PolynomialSystem,
                                     backend::MsolveBackend,
                                     executable::AbstractString,
                                     version::Union{Nothing, String},
                                     dir::AbstractString;
                                     persist_artifacts::Bool)
    input_path = joinpath(dir, "certsdp-msolve-input.ms")
    output_path = joinpath(dir, "certsdp-msolve-output.res")
    stdout_path = joinpath(dir, "certsdp-msolve-stdout.log")
    stderr_path = joinpath(dir, "certsdp-msolve-stderr.log")
    command_path = joinpath(dir, "certsdp-msolve-command.txt")
    provenance_path = joinpath(dir, "certsdp-msolve-provenance.json")
    backend_log_path = joinpath(dir, "certsdp-msolve-backend.log")
    failure_path = joinpath(dir, "certsdp-msolve-failure.json")

    artifacts = persist_artifacts ?
                Dict{Symbol, String}(:input => input_path,
                                     :output => output_path,
                                     :stdout => stdout_path,
                                     :stderr => stderr_path,
                                     :command => command_path,
                                     :provenance => provenance_path,
                                     :backend_log => backend_log_path) :
                Dict{Symbol, String}()

    command = String[executable,
                     "-P", string(backend.parametrization),
                     "-p", string(backend.precision),
                     "-t", string(backend.threads),
                     "-f", input_path,
                     "-o", output_path]
    persist_artifacts && write(command_path, join(command, " ") * "\n")

    try
        write_msolve_input(input_path, system; characteristic=backend.characteristic)
    catch err
        provenance = _msolve_provenance(backend,
                                        executable,
                                        version,
                                        command,
                                        artifacts;
                                        workdir=dir,
                                        input_path,
                                        output_path,
                                        stdout_path,
                                        stderr_path)
        failure = AlgebraicBackendFailure(:msolve,
                                          :invalid_input,
                                          sprint(showerror, err),
                                          provenance,
                                          "",
                                          "",
                                          "",
                                          artifacts,
                                          Dict{Symbol, Any}(:exception_type => string(typeof(err))))
        return _algebraic_failure_result(failure; persist_artifacts,
                                         failure_path,
                                         backend_log_path,
                                         provenance_path)
    end

    process_result = try
        _run_backend_process(command;
                             stdout_path,
                             stderr_path,
                             timeout_seconds=backend.timeout_seconds)
    catch err
        stdout = isfile(stdout_path) ? read(stdout_path, String) : ""
        stderr = isfile(stderr_path) ? read(stderr_path, String) : ""
        provenance = _msolve_provenance(backend,
                                        executable,
                                        version,
                                        command,
                                        artifacts;
                                        workdir=dir,
                                        input_path,
                                        output_path,
                                        stdout_path,
                                        stderr_path)
        failure = AlgebraicBackendFailure(:msolve,
                                          :process_start_failed,
                                          sprint(showerror, err),
                                          provenance,
                                          stdout,
                                          stderr,
                                          "",
                                          artifacts,
                                          Dict{Symbol, Any}(:exception_type => string(typeof(err))))
        return _algebraic_failure_result(failure; persist_artifacts,
                                         failure_path,
                                         backend_log_path,
                                         provenance_path)
    end

    stdout = isfile(stdout_path) ? read(stdout_path, String) : ""
    stderr = isfile(stderr_path) ? read(stderr_path, String) : ""
    backend_output = isfile(output_path) ? read(output_path, String) : ""
    artifacts_with_failure = persist_artifacts ?
                             merge(artifacts,
                                   Dict(:failure => failure_path)) :
                             artifacts
    provenance = _msolve_provenance(backend,
                                    executable,
                                    version,
                                    command,
                                    artifacts;
                                    workdir=dir,
                                    input_path,
                                    output_path,
                                    stdout_path,
                                    stderr_path,
                                    exit_code=process_result.exit_code,
                                    timed_out=process_result.timed_out,
                                    elapsed_seconds=process_result.elapsed_seconds)

    if process_result.timed_out
        failure = AlgebraicBackendFailure(:msolve,
                                          :timeout,
                                          "msolve exceeded timeout of $(backend.timeout_seconds) seconds",
                                          provenance,
                                          stdout,
                                          stderr,
                                          backend_output,
                                          artifacts_with_failure,
                                          Dict{Symbol, Any}(:timeout_seconds => string(backend.timeout_seconds)))
        return _algebraic_failure_result(failure; persist_artifacts,
                                         failure_path,
                                         backend_log_path,
                                         provenance_path)
    elseif process_result.exit_code != 0
        failure = AlgebraicBackendFailure(:msolve,
                                          :process_failed,
                                          _msolve_failure_message(stdout, stderr,
                                                                  process_result.exit_code),
                                          provenance,
                                          stdout,
                                          stderr,
                                          backend_output,
                                          artifacts_with_failure,
                                          Dict{Symbol, Any}(:exit_code => process_result.exit_code))
        return _algebraic_failure_result(failure; persist_artifacts,
                                         failure_path,
                                         backend_log_path,
                                         provenance_path)
    elseif !isfile(output_path)
        failure = AlgebraicBackendFailure(:msolve,
                                          :missing_output,
                                          "msolve exited successfully but did not produce output file `$output_path`",
                                          provenance,
                                          stdout,
                                          stderr,
                                          backend_output,
                                          artifacts_with_failure,
                                          Dict{Symbol, Any}())
        return _algebraic_failure_result(failure; persist_artifacts,
                                         failure_path,
                                         backend_log_path,
                                         provenance_path)
    end

    parsed = try
        parse_msolve_output(backend_output; variables=variable_symbols(system))
    catch err
        failure = AlgebraicBackendFailure(:msolve,
                                          :parse_failed,
                                          "could not parse msolve output: $(sprint(showerror, err))",
                                          provenance,
                                          stdout,
                                          stderr,
                                          backend_output,
                                          artifacts_with_failure,
                                          Dict{Symbol, Any}(:exception_type => string(typeof(err))))
        return _algebraic_failure_result(failure; persist_artifacts,
                                         failure_path,
                                         backend_log_path,
                                         provenance_path)
    end

    backend_log = _backend_log(; command, version, stdout, stderr, backend_output)
    persist_artifacts && begin
                         write(backend_log_path, backend_log)
                         _write_json_artifact(provenance_path,
                                              algebraic_backend_provenance_json(provenance))
                         end
    timings = Dict{Symbol, Any}(:elapsed_seconds => process_result.elapsed_seconds)
    result = AlgebraicSolveResult(:success,
                                  parsed,
                                  backend_log,
                                  stdout,
                                  stderr,
                                  backend_output,
                                  timings,
                                  String[],
                                  provenance,
                                  nothing,
                                  artifacts)
    _msolve_store_cached_result(system, backend, result)
    return result
end

function _msolve_cached_result(system::PolynomialSystem, backend::MsolveBackend)
    cache = backend.result_cache
    (isnothing(cache) || !cache.enabled) && return nothing
    key = _msolve_cache_key(system, backend)
    entry_dir = _backend_cache_entry_dir(cache, key)
    metadata_path = joinpath(entry_dir, "metadata.json")
    output_path = joinpath(entry_dir, "output.res")
    isfile(metadata_path) && isfile(output_path) || return nothing

    metadata = try
        JSON3.read(read(metadata_path, String))
    catch
        return nothing
    end
    _cached_string(metadata, :system_hash) == polynomial_system_hash(system) ||
        return nothing
    _cached_string(metadata, :backend) == "msolve" || return nothing

    backend_output = read(output_path, String)
    parsed = try
        parse_msolve_output(backend_output; variables=variable_symbols(system))
    catch
        return nothing
    end

    options = _msolve_backend_options(backend)
    provenance = _empty_backend_provenance(:msolve;
                                           executable=_cached_string(metadata,
                                                                     :executable),
                                           version=_cached_string(metadata, :version),
                                           command=String[],
                                           timeout_seconds=backend.timeout_seconds,
                                           exit_code=0,
                                           timed_out=false,
                                           elapsed_seconds=0.0,
                                           workdir=entry_dir,
                                           input_path=nothing,
                                           output_path,
                                           stdout_path=nothing,
                                           stderr_path=nothing,
                                           artifacts=Dict{Symbol, String}(:cache_entry => entry_dir,
                                                                          :output => output_path,
                                                                          :metadata => metadata_path),
                                           options=merge(options,
                                                         Dict{Symbol, Any}(:cache_hit => true,
                                                                           :system_hash => polynomial_system_hash(system))))
    backend_log = "cache hit: $(_cached_string(metadata, :cache_key))\n"
    timings = Dict{Symbol, Any}(:elapsed_seconds => 0.0, :cache_hit => true)
    return AlgebraicSolveResult(:success,
                                parsed,
                                backend_log,
                                "",
                                "",
                                backend_output,
                                timings,
                                String["msolve result cache hit"],
                                provenance,
                                nothing,
                                provenance.artifacts)
end

function _msolve_store_cached_result(system::PolynomialSystem,
                                     backend::MsolveBackend,
                                     result::AlgebraicSolveResult)
    cache = backend.result_cache
    (isnothing(cache) || !cache.enabled || !isnothing(result.failure)) && return nothing
    result.status === :success || return nothing

    key = _msolve_cache_key(system, backend)
    entry_dir = _backend_cache_entry_dir(cache, key)
    mkpath(entry_dir)
    output_path = joinpath(entry_dir, "output.res")
    metadata_path = joinpath(entry_dir, "metadata.json")
    write(output_path, result.backend_output)
    metadata = (;
                cache_key=key,
                backend="msolve",
                system_hash=polynomial_system_hash(system),
                options=_msolve_cache_options(backend),
                executable=result.provenance.executable,
                version=result.provenance.version,
                stored_at_unix=time(),)
    _write_json_artifact(metadata_path, metadata)
    return nothing
end

function _msolve_cache_key(system::PolynomialSystem, backend::MsolveBackend)
    payload = (;
               system_hash=polynomial_system_hash(system),
               backend="msolve",
               options=_msolve_cache_options(backend),)
    return bytes2hex(sha256(JSON3.write(payload)))
end

function _msolve_cache_options(backend::MsolveBackend)
    executable = find_msolve(; binary=backend.binary)
    return (;
            characteristic=backend.characteristic,
            precision=backend.precision,
            parametrization=backend.parametrization,
            threads=backend.threads,
            binary=isnothing(executable) ? backend.binary : executable,
            version=isnothing(executable) ? nothing :
                    msolve_version(; binary=executable,
                                   timeout_seconds=_version_timeout(backend.timeout_seconds)),)
end

function _backend_cache_entry_dir(cache::BackendResultCache, key::AbstractString)
    return joinpath(cache.cache_dir, "msolve", String(key))
end

function _cached_string(metadata, key::Symbol)
    haskey(metadata, key) || return nothing
    value = metadata[key]
    isnothing(value) && return nothing
    return String(value)
end

function _msolve_backend_options(backend::MsolveBackend)
    return Dict{Symbol, Any}(:characteristic => backend.characteristic,
                             :precision => backend.precision,
                             :parametrization => backend.parametrization,
                             :threads => backend.threads,
                             :timeout_seconds => backend.timeout_seconds,
                             :binary => backend.binary,
                             :workdir => backend.workdir,
                             :artifact_dir => backend.artifact_dir,
                             :cache_enabled => !isnothing(backend.result_cache) &&
                                               backend.result_cache.enabled,
                             :cache_dir => isnothing(backend.result_cache) ? nothing :
                                           backend.result_cache.cache_dir)
end

function _msolve_persistent_dir(backend::MsolveBackend)
    !isnothing(backend.artifact_dir) && return backend.artifact_dir
    !isnothing(backend.workdir) && return backend.workdir
    return nothing
end

function _msolve_provenance(backend::MsolveBackend,
                            executable::AbstractString,
                            version::Union{Nothing, String},
                            command::Vector{String},
                            artifacts::Dict{Symbol, String};
                            workdir::AbstractString,
                            input_path::AbstractString,
                            output_path::AbstractString,
                            stdout_path::AbstractString,
                            stderr_path::AbstractString,
                            exit_code=nothing,
                            timed_out=false,
                            elapsed_seconds=nothing)
    return _empty_backend_provenance(:msolve;
                                     executable,
                                     version,
                                     command,
                                     timeout_seconds=backend.timeout_seconds,
                                     exit_code,
                                     timed_out,
                                     elapsed_seconds,
                                     workdir,
                                     input_path,
                                     output_path,
                                     stdout_path,
                                     stderr_path,
                                     artifacts,
                                     options=_msolve_backend_options(backend))
end

function _algebraic_failure_result(failure::AlgebraicBackendFailure;
                                   persist_artifacts::Bool=false,
                                   failure_path=nothing,
                                   backend_log_path=nothing,
                                   provenance_path=nothing)
    backend_log = _backend_log(; command=failure.provenance.command,
                               version=failure.provenance.version,
                               stdout=failure.stdout,
                               stderr=failure.stderr,
                               backend_output=failure.backend_output,
                               failure_message=failure.message)
    if persist_artifacts
        if !isnothing(backend_log_path)
            write(backend_log_path, backend_log)
        end
        if !isnothing(provenance_path)
            _write_json_artifact(provenance_path,
                                 algebraic_backend_provenance_json(failure.provenance))
        end
        if !isnothing(failure_path)
            _write_json_artifact(failure_path, algebraic_backend_failure_json(failure))
        end
    end
    timings = Dict{Symbol, Any}()
    !isnothing(failure.provenance.elapsed_seconds) &&
        (timings[:elapsed_seconds] = failure.provenance.elapsed_seconds)
    return AlgebraicSolveResult(failure.reason,
                                nothing,
                                backend_log,
                                failure.stdout,
                                failure.stderr,
                                failure.backend_output,
                                timings,
                                String[],
                                failure.provenance,
                                failure,
                                failure.artifacts)
end

function _run_backend_process(command::Vector{String};
                              stdout_path::AbstractString,
                              stderr_path::AbstractString,
                              timeout_seconds)
    start_time = time()
    process = nothing
    open(stdout_path, "w") do stdout_io
        open(stderr_path, "w") do stderr_io
            process = run(pipeline(Cmd(command); stdout=stdout_io, stderr=stderr_io);
                          wait=false)
            timed_out = false
            while !Base.process_exited(process)
                if !isnothing(timeout_seconds) && (time() - start_time) >= timeout_seconds
                    timed_out = true
                    kill(process)
                    try
                        wait(process)
                    catch
                    end
                    break
                end
                sleep(0.05)
            end
            if !timed_out
                wait(process)
            end
            elapsed = time() - start_time
            return (exit_code=process.exitcode,
                    timed_out=timed_out,
                    elapsed_seconds=elapsed)
        end
    end
end

function _external_tool_version(command::Vector{String}; timeout_seconds=10)
    mktempdir() do dir
        stdout_path = joinpath(dir, "version-stdout.log")
        stderr_path = joinpath(dir, "version-stderr.log")
        result = try
            _run_backend_process(command;
                                 stdout_path,
                                 stderr_path,
                                 timeout_seconds)
        catch
            return nothing
        end
        stdout = isfile(stdout_path) ? strip(read(stdout_path, String)) : ""
        stderr = isfile(stderr_path) ? strip(read(stderr_path, String)) : ""
        result.timed_out && return nothing
        result.exit_code == 0 || return nothing
        text = !isempty(stdout) ? stdout : stderr
        isempty(text) && return nothing
        return String(first(split(text, '\n')))
    end
end

function _version_timeout(timeout_seconds)
    isnothing(timeout_seconds) && return 10.0
    return min(Float64(timeout_seconds), 10.0)
end

function _msolve_failure_message(stdout::AbstractString, stderr::AbstractString,
                                 exit_code::Integer)
    detail = strip(!isempty(stderr) ? stderr : stdout)
    isempty(detail) && return "msolve exited with code $exit_code"
    first_line = first(split(detail, '\n'))
    return "msolve exited with code $exit_code: $first_line"
end

function _find_sage(; binary=nothing)
    if !isnothing(binary)
        return _msolve_executable_path(String(binary))
    end

    env_path = get(ENV, "CERTSDP_SAGE", "")
    if !isempty(strip(env_path))
        found = _msolve_executable_path(strip(env_path))
        !isnothing(found) && return found
    end

    return Sys.which("sage")
end

function _msolve_executable_path(path::AbstractString)
    isempty(path) && return nothing
    if isfile(path) && Sys.isexecutable(path)
        return path
    end
    return Sys.which(path)
end

function _msolve_variable_names(system::PolynomialSystem)
    names = String.(variable_symbols(system))
    for name in names
        _msolve_validate_variable_name(name)
    end
    return names
end

function _msolve_validate_variable_name(name::AbstractString)
    occursin(r"^[A-Za-z_][A-Za-z0-9_]*$", name) ||
        throw(ArgumentError("variable name `$name` is not supported by the msolve writer; use ASCII identifiers"))
    return nothing
end

function _msolve_polynomial_string(polynomial::MultivariatePolynomial)
    return replace(string(polynomial), " " => "")
end

function _msolve_looks_like_parametrization(payload::Vector)
    length(payload) >= 6 || return false
    payload[4] isa Vector || return false
    payload[5] isa Vector || return false
    payload[6] isa Vector || return false
    return true
end

function _msolve_parse_parametrization(payload::Vector)
    characteristic = _msolve_int(payload[1], "parametrization.characteristic")
    nvars = _msolve_int(payload[2], "parametrization.nvars")
    degree_value = _msolve_int(payload[3], "parametrization.degree")
    nvars >= 1 ||
        throw(ArgumentError("msolve parametrization must contain at least one variable"))
    variable_order = _msolve_symbol_list(payload[4], "parametrization.variables")
    length(variable_order) == nvars ||
        throw(ArgumentError("msolve parametrization variable count $(length(variable_order)) does not match nvars $nvars"))
    linear_form = _msolve_rational_list(payload[5], "parametrization.linear_form")

    container = payload[6]
    container isa Vector ||
        throw(ArgumentError("msolve parametrization data must be a list"))
    length(container) >= 2 ||
        throw(ArgumentError("msolve parametrization data is incomplete"))
    _msolve_int(container[1], "parametrization.count") == 1 ||
        throw(ArgumentError("CertSDP currently supports exactly one msolve parametrization"))

    data = container[2]
    data isa Vector || throw(ArgumentError("msolve parametrization payload must be a list"))
    length(data) >= 3 ||
        throw(ArgumentError("msolve parametrization payload is incomplete"))

    minimal_polynomial = _msolve_univariate_polynomial(data[1], "parametrization.w")
    denominator = _msolve_univariate_polynomial(data[2], "parametrization.wprime")
    numerators, numerator_denominators = _msolve_param_numerators(data[3],
                                                                  "parametrization.numerators")
    length(numerators) == nvars - 1 ||
        throw(ArgumentError("msolve returned $(length(numerators)) coordinate numerators; expected $(nvars - 1)"))

    rur = RURSolution(variable_order,
                      linear_form,
                      minimal_polynomial,
                      denominator,
                      numerators,
                      numerator_denominators)
    return characteristic, degree_value, variable_order, rur
end

function _msolve_param_numerators(value, path::AbstractString)
    value isa Vector || throw(ArgumentError("$path must be a list"))
    numerators = UnivariatePolynomial[]
    denominators = BigInt[]
    for (i, entry) in enumerate(value)
        entry_path = "$path[$i]"
        entry isa Vector || throw(ArgumentError("$entry_path must be a list"))
        length(entry) == 2 ||
            throw(ArgumentError("$entry_path must contain polynomial and divisor"))
        push!(numerators, _msolve_univariate_polynomial(entry[1], "$entry_path.polynomial"))
        push!(denominators, BigInt(_msolve_int(entry[2], "$entry_path.divisor")))
    end
    return numerators, denominators
end

function _msolve_univariate_polynomial(value, path::AbstractString)
    value isa Vector || throw(ArgumentError("$path must be a polynomial encoding"))
    length(value) == 2 ||
        throw(ArgumentError("$path must have [degree, coefficients] form"))
    degree_value = _msolve_int(value[1], "$path.degree")
    degree_value >= 0 || throw(ArgumentError("$path.degree must be nonnegative"))
    coeffs_raw = value[2]
    coeffs_raw isa Vector || throw(ArgumentError("$path.coefficients must be a list"))
    length(coeffs_raw) == degree_value + 1 ||
        throw(ArgumentError("$path has $(length(coeffs_raw)) coefficients; expected $(degree_value + 1)"))
    return UnivariatePolynomial([_msolve_rational(coeff, "$path.coefficients")
                                 for coeff in coeffs_raw])
end

function _msolve_parse_real_block(value, path::AbstractString)
    value isa Vector || throw(ArgumentError("$path must be a real-solution block"))
    isempty(value) && return Vector{Vector{MsolveInterval}}()
    group_count = _msolve_int(value[1], "$path.count")
    group_count == 0 && return Vector{Vector{MsolveInterval}}()
    length(value) >= 2 || throw(ArgumentError("$path is missing solution boxes"))

    boxes = Vector{Vector{MsolveInterval}}()
    for group in value[2:end]
        group isa Vector || throw(ArgumentError("$path group must be a list"))
        for box in group
            push!(boxes, _msolve_parse_solution_box(box, "$path.box"))
        end
    end
    return boxes
end

function _msolve_parse_solution_box(value, path::AbstractString)
    value isa Vector || throw(ArgumentError("$path must be a list of coordinate intervals"))
    return [_msolve_parse_interval(interval, "$path[$i]")
            for (i, interval) in enumerate(value)]
end

function _msolve_parse_interval(value, path::AbstractString)
    value isa Vector || throw(ArgumentError("$path must be an interval list"))
    length(value) == 2 || throw(ArgumentError("$path must have [lower, upper] form"))
    return MsolveInterval(_msolve_rational(value[1], "$path.lower"),
                          _msolve_rational(value[2], "$path.upper"))
end

function _msolve_symbol_list(value, path::AbstractString)
    value isa Vector || throw(ArgumentError("$path must be a string list"))
    return Symbol[
                  item isa AbstractString ? Symbol(String(item)) :
                  throw(ArgumentError("$path[$i] must be a string"))
                  for (i, item) in enumerate(value)
                  ]
end

function _msolve_rational_list(value, path::AbstractString)
    value isa Vector || throw(ArgumentError("$path must be a rational list"))
    return Rational{BigInt}[_msolve_rational(item, "$path[$i]")
                            for (i, item) in enumerate(value)]
end

function _msolve_int(value, path::AbstractString)
    rational = _msolve_rational(value, path)
    denominator(rational) == 1 || throw(ArgumentError("$path must be an integer"))
    int_value = numerator(rational)
    typemin(Int) <= int_value <= typemax(Int) ||
        throw(ArgumentError("$path is outside Int range"))
    return Int(int_value)
end

function _msolve_rational(value, path::AbstractString)
    value isa Rational{BigInt} && return value
    value isa Integer && return Rational{BigInt}(value)
    throw(ArgumentError("$path must be rational"))
end

mutable struct _MsolveParser
    index::Int
end

function _msolve_parse_value(source::String, index::Int)
    parser = _MsolveParser(_msolve_skip_ws(source, index))
    value = _msolve_parse_value!(source, parser)
    return value, parser
end

function _msolve_parse_value!(source::String, parser::_MsolveParser)
    parser.index = _msolve_skip_ws(source, parser.index)
    parser.index <= lastindex(source) ||
        throw(ArgumentError("unexpected end of msolve output"))
    char = source[parser.index]
    if char == '['
        return _msolve_parse_list!(source, parser)
    elseif char == '\''
        return _msolve_parse_string!(source, parser)
    end
    return _msolve_parse_number!(source, parser)
end

function _msolve_parse_list!(source::String, parser::_MsolveParser)
    _msolve_take!(source, parser, '[')
    values = Any[]
    parser.index = _msolve_skip_ws(source, parser.index)
    if parser.index <= lastindex(source) && source[parser.index] == ']'
        parser.index = nextind(source, parser.index)
        return values
    end

    while true
        push!(values, _msolve_parse_value!(source, parser))
        parser.index = _msolve_skip_ws(source, parser.index)
        parser.index <= lastindex(source) ||
            throw(ArgumentError("unterminated msolve list"))
        char = source[parser.index]
        if char == ','
            parser.index = nextind(source, parser.index)
            continue
        elseif char == ']'
            parser.index = nextind(source, parser.index)
            return values
        end
        throw(ArgumentError("expected comma or closing bracket in msolve list"))
    end
end

function _msolve_parse_string!(source::String, parser::_MsolveParser)
    _msolve_take!(source, parser, '\'')
    start = parser.index
    while parser.index <= lastindex(source) && source[parser.index] != '\''
        parser.index = nextind(source, parser.index)
    end
    parser.index <= lastindex(source) ||
        throw(ArgumentError("unterminated string in msolve output"))
    value = source[start:prevind(source, parser.index)]
    parser.index = nextind(source, parser.index)
    return value
end

function _msolve_parse_number!(source::String, parser::_MsolveParser)
    start = parser.index
    if parser.index <= lastindex(source) && source[parser.index] in ('+', '-')
        parser.index = nextind(source, parser.index)
    end
    digit_start = parser.index
    while parser.index <= lastindex(source) && isdigit(source[parser.index])
        parser.index = nextind(source, parser.index)
    end
    digit_start < parser.index || throw(ArgumentError("expected number in msolve output"))
    numerator_value = parse(BigInt, source[start:prevind(source, parser.index)])

    parser.index = _msolve_skip_ws(source, parser.index)
    if parser.index > lastindex(source) || source[parser.index] != '/'
        return Rational{BigInt}(numerator_value)
    end

    parser.index = nextind(source, parser.index)
    parser.index = _msolve_skip_ws(source, parser.index)
    denominator_value = _msolve_parse_positive_integer!(source, parser)
    if parser.index <= lastindex(source) && source[parser.index] == '^'
        parser.index = nextind(source, parser.index)
        exponent = _msolve_parse_positive_integer!(source, parser)
        denominator_value = denominator_value^Int(exponent)
    end
    denominator_value != 0 || throw(ArgumentError("zero denominator in msolve output"))
    return Rational{BigInt}(numerator_value, denominator_value)
end

function _msolve_parse_positive_integer!(source::String, parser::_MsolveParser)
    start = parser.index
    while parser.index <= lastindex(source) && isdigit(source[parser.index])
        parser.index = nextind(source, parser.index)
    end
    start < parser.index || throw(ArgumentError("expected integer in msolve output"))
    return parse(BigInt, source[start:prevind(source, parser.index)])
end

function _msolve_take!(source::String, parser::_MsolveParser, expected::Char)
    parser.index <= lastindex(source) && source[parser.index] == expected ||
        throw(ArgumentError("expected `$expected` in msolve output"))
    parser.index = nextind(source, parser.index)
    return nothing
end

function _msolve_skip_ws(source::String, index::Int)
    i = index
    while i <= lastindex(source) && isspace(source[i])
        i = nextind(source, i)
    end
    return i
end
