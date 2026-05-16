const CERTIFICATION_FAILURE_STATUS = "not_certified"

abstract type CertificationResult end
abstract type CertificationFailure end

struct CertifiedResult{C} <: CertificationResult
    certificate::C
    status::Symbol
    artifacts::Dict{Symbol, Any}
end

struct FailureResult{F <: CertificationFailure} <: CertificationResult
    failure::F
    status::Symbol
    artifacts::Dict{Symbol, Any}
end

struct GenericCertificationFailure <: CertificationFailure
    reason::Symbol
    message::String
    stage::Symbol
    diagnostics::Dict{Symbol, Any}
end

struct NumericalFailure <: CertificationFailure
    reason::Symbol
    message::String
    stage::Symbol
    diagnostics::Dict{Symbol, Any}
end

struct RankUnstableFailure <: CertificationFailure
    reason::Symbol
    message::String
    stage::Symbol
    diagnostics::Dict{Symbol, Any}
end

struct SystemTooLargeFailure <: CertificationFailure
    reason::Symbol
    message::String
    stage::Symbol
    diagnostics::Dict{Symbol, Any}
end

struct BackendFailure <: CertificationFailure
    reason::Symbol
    message::String
    stage::Symbol
    diagnostics::Dict{Symbol, Any}
end

struct PositiveDimensionalFailure <: CertificationFailure
    reason::Symbol
    message::String
    stage::Symbol
    diagnostics::Dict{Symbol, Any}
end

struct BackendTimeoutFailure <: CertificationFailure
    reason::Symbol
    message::String
    stage::Symbol
    diagnostics::Dict{Symbol, Any}
end

struct BadCandidateRejected <: CertificationFailure
    reason::Symbol
    message::String
    stage::Symbol
    diagnostics::Dict{Symbol, Any}
end

struct NoNearbyRealSolutionFailure <: CertificationFailure
    reason::Symbol
    message::String
    stage::Symbol
    diagnostics::Dict{Symbol, Any}
end

struct PSDVerificationFailure <: CertificationFailure
    reason::Symbol
    message::String
    stage::Symbol
    diagnostics::Dict{Symbol, Any}
end

struct SOSMatchingFailure <: CertificationFailure
    reason::Symbol
    message::String
    stage::Symbol
    diagnostics::Dict{Symbol, Any}
end

const _NUMERICAL_FAILURE_REASONS = Set([:invalid_options,
                                        :approximation_problem_mismatch,
                                        :approximation_dimension_mismatch,
                                        :approximation_matrix_size_mismatch,
                                        :approximation_residual_too_large,
                                        :approximation_symmetry_residual_too_large,
                                        :approximation_psd_violation_too_large,
                                        :unsupported_numerical_solver,
                                        :numerical_solver_failed,
                                        :numerical_solver_status,
                                        :user_solution_invalid,
                                        :clarabel_setup_failed,
                                        :clarabel_solve_failed,
                                        :clarabel_solution_invalid])

const _RANK_FAILURE_REASONS = Set([:rank_profile_unstable,
                                   :rank_profile_missing])

const _SYSTEM_TOO_LARGE_REASONS = Set([:system_too_large,
                                       :incidence_system_too_large])

const _BACKEND_FAILURE_REASONS = Set([:unsupported_backend,
                                      :numerical_solver_unavailable,
                                      :msolve_failed,
                                      :backend_failed])

const _POSITIVE_DIMENSIONAL_FAILURE_REASONS = Set([:msolve_positive_dimensional,
                                                   :positive_dimensional])

const _BACKEND_TIMEOUT_FAILURE_REASONS = Set([:backend_timeout,
                                              :msolve_timeout,
                                              :validation_timeout])

const _NO_NEARBY_FAILURE_REASONS = Set([:msolve_empty_solution_set,
                                        :no_real_algebraic_solution,
                                        :no_nearby_real_solution,
                                        :no_candidate_verified,
                                        :root_selection_failed])

const _BAD_CANDIDATE_FAILURE_REASONS = Set([:bad_candidate_rejected,
                                            :candidate_rejected])

const _PSD_FAILURE_REASONS = Set([:invalid_psd_proof_method,
                                  :psd_verification_failed,
                                  :certificate_build_failed,
                                  :verify_exception,
                                  :incidence_system_failed])

const _SOS_FAILURE_REASONS = Set([:sos_matching_failed,
                                  :sos_psd_failed,
                                  :sos_certificate_failed])

function CertifiedResult(certificate; status::Symbol=:certified,
                         artifacts=Dict{Symbol, Any}())
    return CertifiedResult(certificate, status, _symbol_any_dict(artifacts))
end

function FailureResult(failure::CertificationFailure; status::Symbol=:not_certified,
                       artifacts=Dict{Symbol, Any}())
    return FailureResult(failure, status, _symbol_any_dict(artifacts))
end

function Base.getproperty(result::CertifiedResult, name::Symbol)
    return name in (:certificate, :status, :artifacts) ? getfield(result, name) :
           getproperty(getfield(result, :certificate), name)
end

function Base.getproperty(result::FailureResult, name::Symbol)
    return name in (:failure, :status, :artifacts) ? getfield(result, name) :
           getproperty(getfield(result, :failure), name)
end

iscertified(::CertifiedResult) = true
iscertified(::FailureResult) = false
iscertified(::Any) = false

Base.convert(::Type{Bool}, result::CertifiedResult) = iscertified(result)
Base.convert(::Type{Bool}, result::FailureResult) = iscertified(result)

certificate(result::CertifiedResult) = result.certificate
failure(result::FailureResult) = result.failure

verify(result::CertifiedResult; kwargs...) = verify(result.certificate; kwargs...)
verify(::FailureResult; kwargs...) = false

verify_sos(result::CertifiedResult; kwargs...) = verify_sos(result.certificate; kwargs...)
verify_sos(::FailureResult; kwargs...) = false

function write_certificate(path::AbstractString, result::CertifiedResult)
    return write_certificate(path, result.certificate)
end

function save_certificate(path::AbstractString, result::CertifiedResult)
    return save_certificate(path, result.certificate)
end

function export_sos_decomposition(result::CertifiedResult)
    return export_sos_decomposition(result.certificate)
end
sos_decomposition_text(result::CertifiedResult) = sos_decomposition_text(result.certificate)
function sos_decomposition_latex(result::CertifiedResult)
    return sos_decomposition_latex(result.certificate)
end
sos_decomposition_sage(result::CertifiedResult) = sos_decomposition_sage(result.certificate)
function sos_decomposition_julia(result::CertifiedResult)
    return sos_decomposition_julia(result.certificate)
end

function Base.show(io::IO, result::CertifiedResult)
    return print(io, "CertifiedResult(", typeof(result.certificate), ")")
end

function Base.show(io::IO, result::FailureResult)
    return print(io, "FailureResult(", failure_type(result.failure), ": ",
                 result.failure.reason, ")")
end

function Base.show(io::IO, failure::CertificationFailure)
    return print(io, failure_type(failure), "(", failure.reason, " at ",
                 failure.stage, ": ", failure.message, ")")
end

function _symbol_any_dict(value)
    if value isa Dict{Symbol, Any}
        return copy(value)
    elseif value isa AbstractDict
        return Dict{Symbol, Any}(Symbol(key) => val for (key, val) in value)
    elseif value isa NamedTuple
        return Dict{Symbol, Any}(Symbol(key) => val for (key, val) in pairs(value))
    end
    throw(ArgumentError("diagnostics/artifacts must be a dictionary or NamedTuple"))
end

function _failure_type_for_reason(reason::Symbol, stage::Symbol,
                                  diagnostics::Dict{Symbol, Any})
    reason in _RANK_FAILURE_REASONS && return RankUnstableFailure
    reason in _SYSTEM_TOO_LARGE_REASONS && return SystemTooLargeFailure
    reason in _POSITIVE_DIMENSIONAL_FAILURE_REASONS &&
        return PositiveDimensionalFailure
    reason in _BACKEND_TIMEOUT_FAILURE_REASONS && return BackendTimeoutFailure
    reason in _BAD_CANDIDATE_FAILURE_REASONS && return BadCandidateRejected
    reason in _BACKEND_FAILURE_REASONS && return BackendFailure
    reason in _NO_NEARBY_FAILURE_REASONS && return NoNearbyRealSolutionFailure
    reason in _SOS_FAILURE_REASONS && return SOSMatchingFailure
    reason in _NUMERICAL_FAILURE_REASONS && return NumericalFailure
    reason in _PSD_FAILURE_REASONS && return PSDVerificationFailure
    stage in (:input, :numerical_oracle) && return NumericalFailure
    haskey(diagnostics, :backend_failure) && return BackendFailure
    return GenericCertificationFailure
end

function CertificationFailure(reason::Symbol, message::AbstractString, stage::Symbol,
                              diagnostics=Dict{Symbol, Any}())
    data = _symbol_any_dict(diagnostics)
    failure_type = _failure_type_for_reason(reason, stage, data)
    return failure_type(reason, String(message), stage, data)
end

failure_type(failure::CertificationFailure) = String(nameof(typeof(failure)))

"""
    certification_failure_json(failure) -> NamedTuple

Return a JSON-ready structured representation of a certification failure.
This compact form is useful for nested diagnostics. Use `failure_report_json`
for the public, user-facing v1.0 failure report.
"""
function certification_failure_json(failure::CertificationFailure)
    return (;
            status=CERTIFICATION_FAILURE_STATUS,
            failure_type=failure_type(failure),
            reason=String(failure.reason),
            message=failure.message,
            stage=String(failure.stage),
            diagnostics=_certification_diagnostics_json(failure.diagnostics),)
end

function certification_failure_json(result::FailureResult)
    return certification_failure_json(result.failure)
end

function _certification_result(outcome; artifacts=Dict{Symbol, Any}())
    if outcome isa CertificationFailure
        return FailureResult(outcome; artifacts)
    end
    return CertifiedResult(outcome; artifacts)
end

function _certification_diagnostics_json(value)
    if isdefined(@__MODULE__, :AlgebraicBackendFailure) &&
       value isa AlgebraicBackendFailure
        return algebraic_backend_failure_json(value)
    elseif isdefined(@__MODULE__, :AlgebraicBackendProvenance) &&
           value isa AlgebraicBackendProvenance
        return algebraic_backend_provenance_json(value)
    end

    if value isa AbstractDict
        return Dict(String(key) => _certification_diagnostics_json(val)
                    for (key, val) in value)
    elseif value isa AbstractVector
        return [_certification_diagnostics_json(item) for item in value]
    elseif value isa Tuple
        return [_certification_diagnostics_json(item) for item in value]
    elseif value isa NamedTuple
        return Dict(String(key) => _certification_diagnostics_json(val)
                    for (key, val) in pairs(value))
    elseif value isa Symbol
        return String(value)
    elseif value isa BigFloat || value isa Rational
        return string(value)
    elseif value isa Integer || value isa AbstractString || value isa Bool ||
           isnothing(value)
        return value
    end
    return string(value)
end
