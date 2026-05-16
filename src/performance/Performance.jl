const _VERIFICATION_CACHE_TLS_KEY = :certsdp_verification_cache

"""
    VerificationCache(; enabled=true)

Scoped cache and timing store for exact verifier work. The cache is data-only:
it reuses exact determinants, algebraic signs, and polynomial remainders, but
it never changes which proof obligations are replayed by the verifier.
"""
mutable struct VerificationCache
    enabled::Bool
    determinant_cache::Dict{Any, Any}
    algebraic_sign_cache::Dict{Any, Any}
    polynomial_remainder_cache::Dict{Any, Any}
    counters::Dict{Symbol, Int}
    timings::Dict{Symbol, Float64}

    function VerificationCache(; enabled::Bool=true)
        return new(enabled,
                   Dict{Any, Any}(),
                   Dict{Any, Any}(),
                   Dict{Any, Any}(),
                   Dict{Symbol, Int}(),
                   Dict{Symbol, Float64}())
    end
end

struct ValidationTimer
    start_ns::UInt64
    timeout_seconds::Union{Nothing, Float64}
end

function ValidationTimer(timeout_seconds=nothing)
    timeout = isnothing(timeout_seconds) ? nothing : Float64(timeout_seconds)
    (isnothing(timeout) || timeout > 0) ||
        throw(ArgumentError("validation timeout must be positive or nothing"))
    return ValidationTimer(time_ns(), timeout)
end

function elapsed_seconds(timer::ValidationTimer)
    return (time_ns() - timer.start_ns) / 1.0e9
end

function remaining_seconds(timer::ValidationTimer)
    isnothing(timer.timeout_seconds) && return nothing
    return max(0.0, timer.timeout_seconds - elapsed_seconds(timer))
end

function timed_out(timer::ValidationTimer)
    remaining = remaining_seconds(timer)
    return !isnothing(remaining) && remaining <= 0
end

function validation_timeout_failure(timer::ValidationTimer, stage::Symbol;
                                    details=Dict{Symbol, Any}())
    diagnostics = Dict{Symbol, Any}(:timeout_seconds => timer.timeout_seconds,
                                    :elapsed_seconds => elapsed_seconds(timer))
    for (key, value) in details
        diagnostics[Symbol(key)] = value
    end
    return CertificationFailure(:validation_timeout,
                                "validation budget timeout reached during $(stage)",
                                stage,
                                diagnostics)
end

function _current_verification_cache()
    try
        cache = task_local_storage(_VERIFICATION_CACHE_TLS_KEY)
        return cache isa VerificationCache ? cache : nothing
    catch err
        err isa KeyError || rethrow()
        return nothing
    end
end

function _with_verification_cache(f::Function; cache::Bool=true, cache_object=nothing)
    current = _current_verification_cache()
    if !isnothing(current) && isnothing(cache_object)
        return f()
    end

    scoped_cache = isnothing(cache_object) ? VerificationCache(; enabled=cache) :
                   cache_object
    return task_local_storage(_VERIFICATION_CACHE_TLS_KEY, scoped_cache) do
        return f()
    end
end

function _verification_cache_bucket(cache::VerificationCache, bucket::Symbol)
    bucket === :determinant && return cache.determinant_cache
    bucket === :algebraic_sign && return cache.algebraic_sign_cache
    bucket === :polynomial_remainder && return cache.polynomial_remainder_cache
    throw(ArgumentError("unknown verification cache bucket `$bucket`"))
end

function _cache_counter!(cache::VerificationCache, name::Symbol)
    cache.counters[name] = get(cache.counters, name, 0) + 1
    return nothing
end

function _record_timing(cache::Union{Nothing, VerificationCache}, name::Symbol,
                        f::Function)
    isnothing(cache) && return f()
    start = time_ns()
    try
        return f()
    finally
        elapsed = (time_ns() - start) / 1.0e9
        cache.timings[name] = get(cache.timings, name, 0.0) + elapsed
    end
end

function _cache_value_copy(value)
    try
        return copy(value)
    catch
        return value
    end
end

function _cache_fetch(bucket::Symbol, key, timing_name::Symbol, f::Function)
    cache = _current_verification_cache()
    if isnothing(cache) || !cache.enabled
        return _record_timing(cache, timing_name, f)
    end

    store = _verification_cache_bucket(cache, bucket)
    if haskey(store, key)
        _cache_counter!(cache, Symbol(bucket, :_hit))
        return _cache_value_copy(store[key])
    end

    _cache_counter!(cache, Symbol(bucket, :_miss))
    value = _record_timing(cache, timing_name, f)
    store[key] = _cache_value_copy(value)
    return value
end

function _cache_fetch(f::Function, bucket::Symbol, key, timing_name::Symbol)
    return _cache_fetch(bucket, key, timing_name, f)
end

function verification_cache_stats(cache::VerificationCache)
    hits = sum(value for (key, value) in cache.counters
               if endswith(String(key), "_hit"); init=0)
    misses = sum(value for (key, value) in cache.counters
                 if endswith(String(key), "_miss"); init=0)
    return (;
            enabled=cache.enabled,
            determinant_entries=length(cache.determinant_cache),
            algebraic_sign_entries=length(cache.algebraic_sign_cache),
            polynomial_remainder_entries=length(cache.polynomial_remainder_cache),
            hits,
            misses,
            counters=copy(cache.counters),
            timings=copy(cache.timings),)
end

function cache_stress_report(work::Function; iterations::Integer=8)
    iterations > 0 || throw(ArgumentError("iterations must be positive"))
    cached_stats = VerificationCache(; enabled=true)
    uncached_stats = VerificationCache(; enabled=false)
    cached_results = Any[]
    uncached_results = Any[]
    cached_seconds = 0.0
    uncached_seconds = 0.0

    _with_verification_cache(; cache_object=uncached_stats) do
        for _ in 1:iterations
            start = time_ns()
            push!(uncached_results, work())
            uncached_seconds += (time_ns() - start) / 1.0e9
        end
    end

    _with_verification_cache(; cache_object=cached_stats) do
        for _ in 1:iterations
            start = time_ns()
            push!(cached_results, work())
            cached_seconds += (time_ns() - start) / 1.0e9
        end
    end

    return (;
            iterations=Int(iterations),
            consistent=cached_results == uncached_results,
            cached_seconds,
            uncached_seconds,
            cached=verification_cache_stats(cached_stats),
            uncached=verification_cache_stats(uncached_stats),)
end

function certificate_size_report(path::AbstractString)
    cert = read_certificate(path)
    return certificate_size_report(cert; bytes=filesize(path))
end

function certificate_size_report(cert; bytes=nothing)
    return (;
            certificate_type=_certificate_size_type(cert),
            bytes=isnothing(bytes) ? _certificate_json_size(cert) : Int(bytes),
            problem_dimension=_certificate_problem_dimension(cert),
            variable_count=_certificate_variable_count(cert),
            proof_obligations=_certificate_proof_obligations(cert),
            algebraic_degree=_certificate_algebraic_degree(cert),)
end

function _certificate_json_size(cert)
    type_name = nameof(typeof(cert))
    if type_name in (:RationalCertificate, :BlockRationalCertificate,
                     :AlgebraicCertificate)
        return sizeof(certificate_json_v1_string(cert))
    elseif type_name === :SOSGramCertificate
        return sizeof(sos_gram_certificate_json_string(cert))
    end
    return 0
end

function _certificate_size_type(cert)
    type_name = nameof(typeof(cert))
    type_name === :RationalCertificate && return "rational_psd_certificate"
    type_name === :BlockRationalCertificate && return "block_rational_psd_certificate"
    type_name === :AlgebraicCertificate && return "algebraic_psd_certificate"
    type_name === :SOSGramCertificate && return "sos_gram_certificate"
    return String(type_name)
end

function _certificate_problem_dimension(cert)
    type_name = nameof(typeof(cert))
    type_name === :SOSGramCertificate && return length(cert.problem.basis)
    hasproperty(cert, :problem) && return matrix_size(cert.problem)
    return nothing
end

function _certificate_variable_count(cert)
    type_name = nameof(typeof(cert))
    type_name === :SOSGramCertificate && return num_variables(cert.problem.lmi)
    hasproperty(cert, :problem) && return num_variables(cert.problem)
    return nothing
end

function _certificate_proof_obligations(cert)
    type_name = nameof(typeof(cert))
    if type_name === :BlockRationalCertificate
        return sum(length(proof.principal_minors) for proof in cert.psd_proof.block_proofs)
    elseif type_name in (:RationalCertificate, :AlgebraicCertificate)
        return length(cert.psd_proof.principal_minors)
    elseif type_name === :SOSGramCertificate
        return length(cert.coefficient_proof) +
               _certificate_proof_obligations(cert.lmi_certificate)
    end
    return nothing
end

function _certificate_algebraic_degree(cert)
    type_name = nameof(typeof(cert))
    type_name === :AlgebraicCertificate && return degree(cert.root.f)
    type_name === :SOSGramCertificate &&
        return _certificate_algebraic_degree(cert.lmi_certificate)
    return 1
end

"""
    verify_timed(cert; cache=true, io=nothing)

Run `verify` and return acceptance, wall time, and exact-operation timing/cache
statistics. This is intended for benchmarks and profiling; it does not weaken
verification.
"""
function verify_timed(cert; io::Union{Nothing, IO}=nothing, cache::Bool=true,
                      strict::Bool=false)
    cache_object = VerificationCache(; enabled=cache)
    start = time_ns()
    accepted = verify(cert; io, cache, cache_object, strict)
    elapsed = (time_ns() - start) / 1.0e9
    return (;
            accepted,
            seconds=elapsed,
            stats=verification_cache_stats(cache_object),)
end

function verify_timed(path::AbstractString; kwargs...)
    return verify_timed(read_certificate(path); kwargs...)
end
