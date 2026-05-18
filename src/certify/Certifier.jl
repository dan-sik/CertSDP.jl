const DEFAULT_CERTIFICATION_MAX_LINEAR_RESIDUAL = "1e-8"
const DEFAULT_CERTIFICATION_MAX_SYMMETRY_RESIDUAL = "1e-8"
const DEFAULT_CERTIFICATION_MAX_PSD_VIOLATION = "1e-8"

"""
    SelectedAlgebraicSolution

Candidate exact algebraic solution selected from an msolve RUR and its real
solution boxes, before it is turned into a certificate and verified.
"""
struct SelectedAlgebraicSolution
    root::AlgebraicRoot
    coordinates::Vector{AlgebraicElement}
    all_coordinates::Vector{AlgebraicElement}
    variable_order::Vector{Symbol}
    box::Vector{MsolveInterval}
    distance::BigFloat
end

"""
    certify(P, exact_solution_or_approx; kwargs...) -> Union{CertifiedResult,FailureResult}

Run an exact rational certificate build when `exact_solution_or_approx` is a
rational vector. Run the end-to-end algebraic certifier path when it is an
`ApproxSolution`:

rank profile -> incidence system -> msolve backend -> select the real RUR root
closest to `approx.xhat` -> build a Type A/F algebraic certificate -> exact
verify. Any stage failure returns `FailureResult` instead of throwing or
accepting numerical evidence.
"""
function certify(P::LMIProblem,
                 x::AbstractVector{<:Union{Integer, Rational}};
                 psd_method::Union{Symbol, AbstractString}=:auto,
                 pivot_block=nothing,
                 kwargs...)
    outcome = try
        RationalCertificate(P, x; psd_method, pivot_block)
    catch err
        CertificationFailure(:psd_verification_failed,
                             sprint(showerror, err),
                             :psd_verification,
                             Dict{Symbol, Any}(:exception_type => string(typeof(err)),
                                               :num_variables => num_variables(P),
                                               :matrix_size => matrix_size(P)))
    end
    return _certification_result(outcome)
end

function certify(P::LMIProblem,
                 approx::ApproxSolution;
                 algebraic_backend::Union{Symbol, AbstractString, AlgebraicBackend}=:msolve,
                 psd_method::Union{Symbol, AbstractString}=:auto,
                 rank_profile=nothing,
                 pivot_block=nothing,
                 msolve_binary=nothing,
                 msolve_precision::Integer=128,
                 msolve_parametrization::Integer=1,
                 msolve_threads::Integer=1,
                 msolve_timeout_seconds=DEFAULT_ALGEBRAIC_BACKEND_TIMEOUT_SECONDS,
                 msolve_workdir=nothing,
                 sage_binary=nothing,
                 sage_workdir=nothing,
                 backend_artifact_dir=nothing,
                 backend_cache_dir=nothing,
                 backend_cache::Bool=!isnothing(backend_cache_dir),
                 root_selection_precision::Integer=max(approx.precision_bits, 256),
                 max_linear_residual=DEFAULT_CERTIFICATION_MAX_LINEAR_RESIDUAL,
                 max_symmetry_residual=DEFAULT_CERTIFICATION_MAX_SYMMETRY_RESIDUAL,
                 max_psd_violation=DEFAULT_CERTIFICATION_MAX_PSD_VIOLATION,
                 max_candidates::Integer=16,
                 max_system_variables=nothing,
                 max_system_equations=nothing,
                 max_degree_estimate=nothing,
                 memory_hint_mb=nothing,
                 slicing=nothing,
                 slicing_equations=nothing,
                 slicing_tolerance="1e-8",
                 slicing_max_denominator::Integer=1024,
                 slicing_max_equations=nothing,
                 slicing_variables=nothing,
                 rank_retry::Bool=true,
                 max_rank_retries::Integer=3,
                 resource_profile=nothing,
                 budget=nothing,
                 memory_limit_mb=nothing,
                 verify_io::Union{Nothing, IO}=nothing,
                 incidence_kwargs...,)
    outcome = _certify_lmi(P, approx;
                           algebraic_backend,
                           psd_method,
                           rank_profile,
                           pivot_block,
                           msolve_binary,
                           msolve_precision,
                           msolve_parametrization,
                           msolve_threads,
                           msolve_timeout_seconds,
                           msolve_workdir,
                           sage_binary,
                           sage_workdir,
                           backend_artifact_dir,
                           backend_cache_dir,
                           backend_cache,
                           root_selection_precision,
                           max_linear_residual,
                           max_symmetry_residual,
                           max_psd_violation,
                           max_candidates,
                           max_system_variables,
                           max_system_equations,
                           max_degree_estimate,
                           memory_hint_mb,
                           slicing,
                           slicing_equations,
                           slicing_tolerance,
                           slicing_max_denominator,
                           slicing_max_equations,
                           slicing_variables,
                           rank_retry,
                           max_rank_retries,
                           resource_profile,
                           budget,
                           memory_limit_mb,
                           verify_io,
                           incidence_kwargs...)
    return _certification_result(outcome)
end

function certify(P::BlockLMIProblem,
                 x::AbstractVector{<:Union{Integer, Rational}};
                 psd_method::Union{Symbol, AbstractString}=:auto,
                 block_pivot_blocks=nothing,
                 pivot_block=nothing,
                 kwargs...)
    outcome = try
        BlockRationalCertificate(P, x; psd_method,
                                 block_pivot_blocks=isnothing(block_pivot_blocks) ?
                                                    pivot_block :
                                                    block_pivot_blocks)
    catch err
        CertificationFailure(:psd_verification_failed,
                             sprint(showerror, err),
                             :psd_verification,
                             Dict{Symbol, Any}(:exception_type => string(typeof(err)),
                                               :num_blocks => num_blocks(P),
                                               :block_sizes => block_sizes(P)))
    end
    return _certification_result(outcome)
end

function certify(P::BlockLMIProblem,
                 approx::ApproxSolution;
                 psd_method::Union{Symbol, AbstractString}=:auto,
                 block_pivot_blocks=nothing,
                 pivot_block=nothing,
                 kwargs...)
    outcome = _certify_block_lmi(P, approx;
                                 psd_method,
                                 block_pivot_blocks=isnothing(block_pivot_blocks) ?
                                                    pivot_block :
                                                    block_pivot_blocks,
                                 kwargs...)
    return _certification_result(outcome)
end

function _certify_block_lmi(P::BlockLMIProblem,
                            approx::ApproxSolution;
                            psd_method::Union{Symbol, AbstractString}=:auto,
                            block_pivot_blocks=nothing,
                            verify_io::Union{Nothing, IO}=nothing,
                            kwargs...)
    aggregate = block_diagonal_lmi_problem(P)
    block_hash = block_lmi_problem_hash(P)
    aggregate_hash = lmi_problem_hash(aggregate)
    if approx.problem_hash == block_hash
        approx_for_aggregate = _retag_approx_solution(approx, aggregate_hash)
    elseif approx.problem_hash == aggregate_hash
        approx_for_aggregate = approx
    else
        return CertificationFailure(:approximation_problem_mismatch,
                                    "approximation problem hash $(approx.problem_hash) matches neither block LMI hash $block_hash nor aggregate LMI hash $aggregate_hash",
                                    :input,
                                    Dict{Symbol, Any}(:approx_problem_hash => approx.problem_hash,
                                                      :block_problem_hash => block_hash,
                                                      :aggregate_problem_hash => aggregate_hash,
                                                      :num_blocks => num_blocks(P),
                                                      :block_sizes => block_sizes(P)))
    end

    aggregate_outcome = _certify_lmi(aggregate, approx_for_aggregate;
                                     psd_method,
                                     verify_io,
                                     kwargs...)
    aggregate_outcome isa CertificationFailure &&
        return _with_block_certification_diagnostics(aggregate_outcome, P)

    aggregate_outcome isa AlgebraicCertificate ||
        return CertificationFailure(:certificate_build_failed,
                                    "aggregate multi-block algebraic certifier returned $(typeof(aggregate_outcome)); expected AlgebraicCertificate",
                                    :certificate_build,
                                    Dict{Symbol, Any}(:num_blocks => num_blocks(P),
                                                      :block_sizes => block_sizes(P)))

    block_psd_method = Symbol(psd_method) === Symbol(SCHUR_ZERO_PSD_METHOD) &&
                       isnothing(block_pivot_blocks) ? :blockwise : psd_method
    cert = try
        BlockAlgebraicCertificate(P,
                                  aggregate_outcome.root,
                                  aggregate_outcome.solution;
                                  psd_method=block_psd_method,
                                  block_pivot_blocks,
                                  provenance=aggregate_outcome.provenance)
    catch err
        return _certification_exception(:certificate_build_failed,
                                        :certificate_build,
                                        err)
    end

    accepted = try
        verify(cert; io=verify_io)
    catch err
        return _certification_exception(:verify_exception, :verify, err)
    end
    accepted && return cert

    return CertificationFailure(:psd_verification_failed,
                                "exact verifier rejected the blockwise algebraic certificate",
                                :verify,
                                Dict{Symbol, Any}(:num_blocks => num_blocks(P),
                                                  :block_sizes => block_sizes(P)))
end

function _with_block_certification_diagnostics(failure::CertificationFailure,
                                               P::BlockLMIProblem)
    diagnostics = copy(failure.diagnostics)
    diagnostics[:num_blocks] = num_blocks(P)
    diagnostics[:block_sizes] = block_sizes(P)
    diagnostics[:aggregate_strategy] = :block_diagonal_incidence
    return CertificationFailure(failure.reason, failure.message, failure.stage,
                                diagnostics)
end

function _certify_lmi(P::LMIProblem,
                      approx::ApproxSolution;
                      algebraic_backend::Union{Symbol, AbstractString, AlgebraicBackend}=:msolve,
                      psd_method::Union{Symbol, AbstractString}=:auto,
                      rank_profile=nothing,
                      pivot_block=nothing,
                      msolve_binary=nothing,
                      msolve_precision::Integer=128,
                      msolve_parametrization::Integer=1,
                      msolve_threads::Integer=1,
                      msolve_timeout_seconds=DEFAULT_ALGEBRAIC_BACKEND_TIMEOUT_SECONDS,
                      msolve_workdir=nothing,
                      sage_binary=nothing,
                      sage_workdir=nothing,
                      backend_artifact_dir=nothing,
                      backend_cache_dir=nothing,
                      backend_cache::Bool=!isnothing(backend_cache_dir),
                      root_selection_precision::Integer=max(approx.precision_bits, 256),
                      max_linear_residual=DEFAULT_CERTIFICATION_MAX_LINEAR_RESIDUAL,
                      max_symmetry_residual=DEFAULT_CERTIFICATION_MAX_SYMMETRY_RESIDUAL,
                      max_psd_violation=DEFAULT_CERTIFICATION_MAX_PSD_VIOLATION,
                      max_candidates::Integer=16,
                      max_system_variables=nothing,
                      max_system_equations=nothing,
                      max_degree_estimate=nothing,
                      memory_hint_mb=nothing,
                      slicing=nothing,
                      slicing_equations=nothing,
                      slicing_tolerance="1e-8",
                      slicing_max_denominator::Integer=1024,
                      slicing_max_equations=nothing,
                      slicing_variables=nothing,
                      rank_retry::Bool=true,
                      max_rank_retries::Integer=3,
                      resource_profile=nothing,
                      budget=nothing,
                      memory_limit_mb=nothing,
                      verify_io::Union{Nothing, IO}=nothing,
                      incidence_kwargs...,)
    max_candidates > 0 || return CertificationFailure(:invalid_options,
                                                      "max_candidates must be positive",
                                                      :options,
                                                      Dict{Symbol, Any}(:max_candidates => max_candidates))

    has_resource_budget = !isnothing(resource_profile) || !isnothing(budget)
    uses_default_timeout = msolve_timeout_seconds ==
                           DEFAULT_ALGEBRAIC_BACKEND_TIMEOUT_SECONDS
    budget_timeout_seconds = has_resource_budget && uses_default_timeout ? nothing :
                             msolve_timeout_seconds
    resource_budget = try
        resolve_resource_budget(; profile=resource_profile,
                                budget,
                                max_system_variables,
                                max_system_equations,
                                max_degree_estimate,
                                timeout_seconds=budget_timeout_seconds,
                                memory_limit_mb,
                                memory_hint_mb)
    catch err
        return CertificationFailure(:invalid_options,
                                    "invalid resource budget: $(sprint(showerror, err))",
                                    :options,
                                    Dict{Symbol, Any}(:exception_type => string(typeof(err))))
    end
    validation_timer = ValidationTimer(resource_budget.timeout_seconds)

    sanity_failure = _certification_input_sanity_failure(P, approx;
                                                         max_linear_residual,
                                                         max_symmetry_residual,
                                                         max_psd_violation,)
    isnothing(sanity_failure) || return sanity_failure

    backend_adapter = try
        _certification_backend_adapter(algebraic_backend;
                                       msolve_binary,
                                       msolve_precision,
                                       msolve_parametrization,
                                       msolve_threads,
                                       timeout_seconds=resource_budget.timeout_seconds,
                                       msolve_workdir,
                                       sage_binary,
                                       sage_workdir,
                                       backend_artifact_dir,
                                       backend_cache_dir,
                                       backend_cache)
    catch err
        return _certification_exception(:unsupported_backend, :backend, err)
    end

    profiles = try
        _certification_rank_attempts(P, approx, rank_profile;
                                     rank_retry,
                                     max_rank_retries)
    catch err
        return _certification_exception(:rank_profile_failed, :rank_profile, err)
    end
    isempty(profiles) && return _rank_profile_failure(isnothing(rank_profile) ?
                                                      approx.rank_profile :
                                                      rank_profile)

    slicing_specs = _certification_slicing_attempts(approx;
                                                    slicing,
                                                    slicing_equations,
                                                    slicing_tolerance,
                                                    slicing_max_denominator,
                                                    slicing_max_equations,
                                                    slicing_variables)
    attempts = Any[]
    preferred_failure = nothing

    for (profile_index, profile) in enumerate(profiles)
        profile isa RankProfile || begin
                                   failure = _rank_profile_failure(profile)
                                   push!(attempts,
                                         _attempt_failure_summary(profile_index,
                                                                  0,
                                                                  profile,
                                                                  nothing,
                                                                  nothing,
                                                                  failure))
                                   isnothing(preferred_failure) && (preferred_failure = failure)
                                   continue
                                   end

        for (slice_index, slice_spec) in enumerate(slicing_specs)
            system = try
                build_incidence_system(P,
                                       approx,
                                       profile;
                                       slicing=slice_spec.strategy,
                                       slicing_equations=slice_spec.equations,
                                       slicing_tolerance=slice_spec.tolerance,
                                       slicing_max_denominator=slice_spec.max_denominator,
                                       slicing_max_equations=slice_spec.max_equations,
                                       slicing_variables=slice_spec.variables,
                                       slicing_seed=slice_spec.seed,
                                       incidence_kwargs...)
            catch err
                failure = _certification_exception(:incidence_system_failed,
                                                   :incidence,
                                                   err)
                push!(attempts,
                      _attempt_failure_summary(profile_index,
                                               slice_index,
                                               profile,
                                               slice_spec,
                                               nothing,
                                               failure))
                isnothing(preferred_failure) && (preferred_failure = failure)
                continue
            end

            system_failure = _system_size_failure(system;
                                                  max_system_variables=resource_budget.max_system_variables,
                                                  max_system_equations=resource_budget.max_system_equations,
                                                  max_degree_estimate=resource_budget.max_degree_estimate,
                                                  memory_hint_mb=resource_budget.memory_hint_mb)
            if !isnothing(system_failure)
                push!(attempts,
                      _attempt_failure_summary(profile_index,
                                               slice_index,
                                               profile,
                                               slice_spec,
                                               system,
                                               system_failure))
                return _with_attempt_diagnostics(system_failure, attempts)
            end

            if timed_out(validation_timer)
                timeout_failure = validation_timeout_failure(validation_timer,
                                                             :incidence;
                                                             details=Dict{Symbol, Any}(:variables => length(variable_symbols(system)),
                                                                                       :equations => length(system.equations),
                                                                                       :degree_estimate => _polynomial_system_degree_estimate(system),
                                                                                       :validation_budget => validation_budget_label(resource_budget)))
                push!(attempts,
                      _attempt_failure_summary(profile_index,
                                               slice_index,
                                               profile,
                                               slice_spec,
                                               system,
                                               timeout_failure))
                return _with_attempt_diagnostics(timeout_failure, attempts)
            end

            attempt_timeout = remaining_seconds(validation_timer)
            if !isnothing(attempt_timeout) && attempt_timeout <= 0
                timeout_failure = validation_timeout_failure(validation_timer,
                                                             :msolve;
                                                             details=Dict{Symbol, Any}(:validation_budget => validation_budget_label(resource_budget)))
                push!(attempts,
                      _attempt_failure_summary(profile_index,
                                               slice_index,
                                               profile,
                                               slice_spec,
                                               system,
                                               timeout_failure))
                return _with_attempt_diagnostics(timeout_failure, attempts)
            end

            attempt_backend = isnothing(attempt_timeout) ? backend_adapter :
                              _backend_with_timeout(backend_adapter, attempt_timeout)

            backend_result = solve_system(system, attempt_backend)
            if !isnothing(backend_result.failure)
                failure = _certification_backend_failure(backend_result.failure)
                push!(attempts,
                      _attempt_failure_summary(profile_index,
                                               slice_index,
                                               profile,
                                               slice_spec,
                                               system,
                                               failure))
                isnothing(preferred_failure) && (preferred_failure = failure)
                backend_result.failure.reason in (:timeout, :unavailable) &&
                    return _with_attempt_diagnostics(failure, attempts)
                continue
            end

            outcome = _certify_from_msolve_output(P,
                                                  approx,
                                                  profile,
                                                  system,
                                                  backend_result.output;
                                                  psd_method,
                                                  pivot_block,
                                                  root_selection_precision,
                                                  max_candidates,
                                                  verify_io,
                                                  backend_provenance=backend_result.provenance,
                                                  attempt=(profile_index=profile_index,
                                                           slice_index=slice_index,
                                                           slicing_strategy=system.metadata[:slicing_strategy]))
            if !(outcome isa CertificationFailure)
                return outcome
            end
            push!(attempts,
                  _attempt_failure_summary(profile_index,
                                           slice_index,
                                           profile,
                                           slice_spec,
                                           system,
                                           outcome))
            if outcome.reason === :msolve_positive_dimensional &&
               slice_spec.strategy === :none &&
               any(spec -> spec.strategy !== :none, slicing_specs)
                preferred_failure = outcome
                continue
            end
            preferred_failure = _prefer_certification_failure(preferred_failure, outcome)
        end
    end

    if isnothing(preferred_failure)
        preferred_failure = CertificationFailure(:no_candidate_verified,
                                                 "no algebraic certification attempt produced an accepted certificate",
                                                 :certify,
                                                 Dict{Symbol, Any}())
    end
    return _with_attempt_diagnostics(preferred_failure, attempts)
end

function _system_size_failure(system::PolynomialSystem;
                              max_system_variables=nothing,
                              max_system_equations=nothing,
                              max_degree_estimate=nothing,
                              memory_hint_mb=nothing)
    variable_count = length(variable_symbols(system))
    equation_count = length(system.equations)
    degree_estimate = _polynomial_system_degree_estimate(system)
    memory_estimate_mb = _polynomial_system_memory_hint_mb(system, degree_estimate)
    variable_limit = isnothing(max_system_variables) ? nothing :
                     _positive_limit(max_system_variables, :max_system_variables)
    equation_limit = isnothing(max_system_equations) ? nothing :
                     _positive_limit(max_system_equations, :max_system_equations)
    degree_limit = isnothing(max_degree_estimate) ? nothing :
                   _positive_limit(max_degree_estimate, :max_degree_estimate)
    memory_hint = isnothing(memory_hint_mb) ? nothing :
                  _positive_limit(memory_hint_mb, :memory_hint_mb)
    if !isnothing(variable_limit) && variable_count > variable_limit
        return CertificationFailure(:system_too_large,
                                    "incidence system has $variable_count variables, exceeding limit $variable_limit",
                                    :incidence,
                                    Dict{Symbol, Any}(:variables => variable_count,
                                                      :equations => equation_count,
                                                      :degree_estimate => degree_estimate,
                                                      :memory_estimate_mb => memory_estimate_mb,
                                                      :max_system_variables => variable_limit))
    end
    if !isnothing(equation_limit) && equation_count > equation_limit
        return CertificationFailure(:system_too_large,
                                    "incidence system has $equation_count equations, exceeding limit $equation_limit",
                                    :incidence,
                                    Dict{Symbol, Any}(:variables => variable_count,
                                                      :equations => equation_count,
                                                      :degree_estimate => degree_estimate,
                                                      :memory_estimate_mb => memory_estimate_mb,
                                                      :max_system_equations => equation_limit))
    end
    if !isnothing(degree_limit) && degree_estimate > degree_limit
        return CertificationFailure(:system_too_large,
                                    "incidence system degree estimate $degree_estimate exceeds limit $degree_limit",
                                    :incidence,
                                    Dict{Symbol, Any}(:variables => variable_count,
                                                      :equations => equation_count,
                                                      :degree_estimate => degree_estimate,
                                                      :memory_estimate_mb => memory_estimate_mb,
                                                      :max_degree_estimate => degree_limit))
    end
    if !isnothing(memory_hint) && memory_estimate_mb > memory_hint
        return CertificationFailure(:system_too_large,
                                    "incidence system memory estimate $(memory_estimate_mb) MB exceeds hint $(memory_hint) MB",
                                    :incidence,
                                    Dict{Symbol, Any}(:variables => variable_count,
                                                      :equations => equation_count,
                                                      :degree_estimate => degree_estimate,
                                                      :memory_estimate_mb => memory_estimate_mb,
                                                      :memory_hint_mb => memory_hint))
    end
    return nothing
end

function _certification_backend_adapter(algebraic_backend;
                                        msolve_binary=nothing,
                                        msolve_precision::Integer=128,
                                        msolve_parametrization::Integer=1,
                                        msolve_threads::Integer=1,
                                        timeout_seconds=DEFAULT_ALGEBRAIC_BACKEND_TIMEOUT_SECONDS,
                                        msolve_workdir=nothing,
                                        sage_binary=nothing,
                                        sage_workdir=nothing,
                                        backend_artifact_dir=nothing,
                                        backend_cache_dir=nothing,
                                        backend_cache::Bool=false)
    algebraic_backend isa AlgebraicBackend && return algebraic_backend
    backend = Symbol(algebraic_backend)
    if backend === :msolve
        return MsolveBackend(; binary=msolve_binary,
                             precision=msolve_precision,
                             parametrization=msolve_parametrization,
                             threads=msolve_threads,
                             timeout_seconds,
                             workdir=msolve_workdir,
                             artifact_dir=backend_artifact_dir,
                             cache_dir=backend_cache_dir,
                             cache=backend_cache)
    elseif backend === :sage_msolve || backend === :sage
        return SageMsolveBackend(; binary=sage_binary,
                                 msolve_binary,
                                 precision=msolve_precision,
                                 parametrization=msolve_parametrization,
                                 threads=msolve_threads,
                                 timeout_seconds,
                                 workdir=sage_workdir,
                                 artifact_dir=backend_artifact_dir)
    end
    throw(ArgumentError("unsupported algebraic backend `$backend`; supported backends are `:msolve` and `:sage_msolve`"))
end

function _backend_with_timeout(backend::MsolveBackend, timeout_seconds)
    return MsolveBackend(; binary=backend.binary,
                         characteristic=backend.characteristic,
                         precision=backend.precision,
                         parametrization=backend.parametrization,
                         threads=backend.threads,
                         timeout_seconds,
                         workdir=backend.workdir,
                         artifact_dir=backend.artifact_dir,
                         result_cache=backend.result_cache)
end

function _backend_with_timeout(backend::SageMsolveBackend, timeout_seconds)
    return SageMsolveBackend(; binary=backend.binary,
                             msolve_binary=backend.msolve_binary,
                             precision=backend.precision,
                             parametrization=backend.parametrization,
                             threads=backend.threads,
                             timeout_seconds,
                             workdir=backend.workdir,
                             artifact_dir=backend.artifact_dir)
end

_backend_with_timeout(backend::AlgebraicBackend, timeout_seconds) = backend

function _polynomial_system_degree_estimate(system::PolynomialSystem)
    isempty(system.equations) && return 0
    return maximum(_multivariate_polynomial_degree, system.equations)
end

function _multivariate_polynomial_degree(polynomial::MultivariatePolynomial)
    isempty(polynomial.terms) && return 0
    return maximum(sum(exponents) for exponents in keys(polynomial.terms))
end

function _polynomial_system_memory_hint_mb(system::PolynomialSystem,
                                           degree_estimate::Integer)
    variables = length(variable_symbols(system))
    equations = length(system.equations)
    term_count = sum(length(equation.terms) for equation in system.equations)
    estimate = variables * equations + term_count + degree_estimate * max(1, variables)
    return max(1, ceil(Int, estimate / 8))
end

function _certification_rank_attempts(P::LMIProblem,
                                      approx::ApproxSolution,
                                      requested_rank_profile;
                                      rank_retry::Bool=true,
                                      max_rank_retries::Integer=3)
    max_rank_retries >= 0 ||
        throw(ArgumentError("max_rank_retries must be nonnegative"))
    profiles = RankProfile[]
    if requested_rank_profile isa RankProfile
        push!(profiles, requested_rank_profile)
        rank_retry || return profiles
        for profile in _rank_retry_profiles(approx,
                                            requested_rank_profile,
                                            matrix_size(P),
                                            max_rank_retries)
            push!(profiles, profile)
        end
        return profiles
    elseif requested_rank_profile isa UnstableRankProfile
        return [requested_rank_profile]
    elseif isnothing(requested_rank_profile)
        current = approx.rank_profile
        if current isa RankProfile
            push!(profiles, current)
            rank_retry && append!(profiles,
                                  _rank_retry_profiles(approx,
                                                       current,
                                                       matrix_size(P),
                                                       max_rank_retries))
            return profiles
        elseif current isa UnstableRankProfile
            return [current]
        end
    end
    return [approx.rank_profile]
end

function _rank_retry_profiles(approx::ApproxSolution,
                              profile::RankProfile,
                              matrix_size_value::Integer,
                              max_rank_retries::Integer)
    retries = Any[]
    max_rank = matrix_size_value
    base_rank = profile.rank
    seen = Set{Int}([base_rank])
    for delta in 1:max_rank_retries
        for candidate_rank in (base_rank - delta, base_rank + delta)
            0 <= candidate_rank <= max_rank || continue
            candidate_rank in seen && continue
            push!(seen, candidate_rank)
            push!(retries,
                  _rank_profile_variant(approx, profile, candidate_rank,
                                        matrix_size_value))
        end
    end
    return retries
end

function _rank_profile_variant(approx::ApproxSolution,
                               profile::RankProfile,
                               candidate_rank::Integer,
                               matrix_size_value::Integer)
    tolerance = profile.tolerance
    singular_values = profile.singular_values
    method = profile.method
    if candidate_rank == profile.rank
        return profile
    elseif candidate_rank < 0
        return UnstableRankProfile("requested retry rank below zero",
                                   tolerance,
                                   singular_values,
                                   profile.gap,
                                   candidate_rank,
                                   method)
    end
    limit = min(candidate_rank, length(profile.permutation))
    pivots = _extend_index_set(profile.permutation, candidate_rank, matrix_size_value)
    rows = _extend_index_set(profile.pivot_rows, candidate_rank, matrix_size_value)
    return RankProfile(candidate_rank,
                       pivots,
                       rows,
                       copy(profile.permutation),
                       tolerance,
                       singular_values,
                       profile.gap,
                       method)
end

function _extend_index_set(indices::AbstractVector{Int},
                           target_count::Integer,
                           upper::Integer)
    target_count <= 0 && return Int[]
    selected = Int[]
    seen = Set{Int}()
    for index in indices
        if !(index in seen)
            push!(selected, index)
            push!(seen, index)
        end
        length(selected) >= target_count && break
    end
    if length(selected) < target_count
        for index in 1:upper
            index in seen && continue
            push!(selected, index)
            push!(seen, index)
            length(selected) >= target_count && break
        end
    end
    sort!(selected)
    return selected
end

function _certification_slicing_attempts(approx::ApproxSolution;
                                         slicing=nothing,
                                         slicing_equations=nothing,
                                         slicing_tolerance="1e-8",
                                         slicing_max_denominator::Integer=1024,
                                         slicing_max_equations=nothing,
                                         slicing_variables=nothing)
    hint = _approx_slicing_hint(approx)
    strategies = Any[]
    if !isnothing(slicing_equations)
        push!(strategies,
              (;
               strategy=:user,
               equations=slicing_equations,
               tolerance=slicing_tolerance,
               max_denominator=slicing_max_denominator,
               max_equations=slicing_max_equations,
               variables=slicing_variables,
               seed=0,))
    elseif haskey(hint, :equations)
        push!(strategies,
              (;
               strategy=:user,
               equations=hint[:equations],
               tolerance=slicing_tolerance,
               max_denominator=slicing_max_denominator,
               max_equations=slicing_max_equations,
               variables=get(hint, :variables, slicing_variables),
               seed=0,))
    end

    auto_strategy = isnothing(slicing) ? get(hint, :strategy, :rational_rounding) :
                    Symbol(slicing)
    push!(strategies,
          (;
           strategy=auto_strategy,
           equations=nothing,
           tolerance=slicing_tolerance,
           max_denominator=slicing_max_denominator,
           max_equations=slicing_max_equations,
           variables=get(hint, :variables, slicing_variables),
           seed=get(hint, :seed, 0),))

    if auto_strategy !== :none && auto_strategy !== :user
        push!(strategies,
              (;
               strategy=:none,
               equations=nothing,
               tolerance=slicing_tolerance,
               max_denominator=slicing_max_denominator,
               max_equations=0,
               variables=nothing,
               seed=0,))
    end
    return strategies
end

function _approx_slicing_hint(approx::ApproxSolution)
    hints = approx.slicing_hints
    haskey(hints, :slicing) && return hints[:slicing]
    return hints
end

function _attempt_failure_summary(profile_index::Integer,
                                  slice_index::Integer,
                                  profile,
                                  slice_spec,
                                  system,
                                  failure::CertificationFailure)
    diagnostics = Dict{Symbol, Any}(:profile_index => profile_index,
                                    :slice_index => slice_index,
                                    :failure => certification_failure_json(failure))
    if profile isa RankProfile
        diagnostics[:rank] = profile.rank
        diagnostics[:pivot_cols] = copy(profile.pivot_cols)
        diagnostics[:pivot_rows] = copy(profile.pivot_rows)
    elseif profile isa UnstableRankProfile
        diagnostics[:rank_profile] = Dict{Symbol, Any}(:reason => profile.reason,
                                                       :candidate_rank => profile.candidate_rank,
                                                       :gap => string(profile.gap))
    end
    if !isnothing(slice_spec)
        diagnostics[:slice_strategy] = slice_spec.strategy
        diagnostics[:slice_seed] = slice_spec.seed
    end
    if !isnothing(system)
        diagnostics[:system_variables] = length(variable_symbols(system))
        diagnostics[:system_equations] = length(system.equations)
        diagnostics[:system_degree_estimate] = _polynomial_system_degree_estimate(system)
    end
    return diagnostics
end

function _with_attempt_diagnostics(failure::CertificationFailure, attempts)
    diagnostics = copy(failure.diagnostics)
    diagnostics[:attempts] = attempts
    diagnostics[:attempt_count] = length(attempts)
    diagnostics[:attempt_summary] = _attempt_summary(attempts)
    if haskey(failure.diagnostics, :timeout_seconds)
        diagnostics[:graceful_diagnostic] = true
    end
    return CertificationFailure(failure.reason, failure.message, failure.stage,
                                diagnostics)
end

function _attempt_summary(attempts)
    summaries = Any[]
    for attempt in attempts
        push!(summaries,
              Dict{Symbol, Any}(:profile_index => attempt[:profile_index],
                                :slice_index => attempt[:slice_index],
                                :reason => attempt[:failure].reason,
                                :stage => attempt[:failure].stage))
    end
    return summaries
end

function _prefer_certification_failure(current, candidate::CertificationFailure)
    isnothing(current) && return candidate
    current.reason === :msolve_positive_dimensional && return current
    candidate.reason === :msolve_positive_dimensional && return candidate
    current.reason === :no_candidate_verified && return candidate
    candidate.reason === :no_candidate_verified && return current
    return current
end

function _positive_limit(value, name::Symbol)
    parsed = try
        Int(value)
    catch err
        throw(ArgumentError("$name must be an integer: $(sprint(showerror, err))"))
    end
    parsed >= 0 || throw(ArgumentError("$name must be nonnegative"))
    return parsed
end

function _certification_input_sanity_failure(P::LMIProblem,
                                             approx::ApproxSolution;
                                             max_linear_residual=DEFAULT_CERTIFICATION_MAX_LINEAR_RESIDUAL,
                                             max_symmetry_residual=DEFAULT_CERTIFICATION_MAX_SYMMETRY_RESIDUAL,
                                             max_psd_violation=DEFAULT_CERTIFICATION_MAX_PSD_VIOLATION,)
    problem_hash = lmi_problem_hash(P)
    approx.problem_hash == problem_hash ||
        return CertificationFailure(:approximation_problem_mismatch,
                                    "approximation problem hash $(approx.problem_hash) does not match LMI hash $problem_hash",
                                    :input,
                                    Dict{Symbol, Any}(:approx_problem_hash => approx.problem_hash,
                                                      :problem_hash => problem_hash))

    length(approx.xhat) == num_variables(P) ||
        return CertificationFailure(:approximation_dimension_mismatch,
                                    "approximation xhat has length $(length(approx.xhat)); expected $(num_variables(P))",
                                    :input,
                                    Dict{Symbol, Any}(:xhat_length => length(approx.xhat),
                                                      :num_variables => num_variables(P)))

    size(approx.Xhat) == (matrix_size(P), matrix_size(P)) ||
        return CertificationFailure(:approximation_matrix_size_mismatch,
                                    "approximation Xhat has size $(size(approx.Xhat)); expected $((matrix_size(P), matrix_size(P)))",
                                    :input,
                                    Dict{Symbol, Any}(:xhat_matrix_size => string(size(approx.Xhat)),
                                                      :matrix_size => matrix_size(P)))

    _diagnostic_exceeds_limit(approx.residuals.linear_residual, max_linear_residual;
                              name=:max_linear_residual) &&
        return CertificationFailure(:approximation_residual_too_large,
                                    "approximation Xhat does not match exact LMI evaluation at xhat within tolerance",
                                    :input,
                                    Dict{Symbol, Any}(:linear_residual => string(approx.residuals.linear_residual),
                                                      :max_linear_residual => string(max_linear_residual),
                                                      :symmetry_residual => string(approx.residuals.symmetry_residual),
                                                      :psd_violation => string(approx.residuals.psd_violation)))

    _diagnostic_exceeds_limit(approx.residuals.symmetry_residual, max_symmetry_residual;
                              name=:max_symmetry_residual) &&
        return CertificationFailure(:approximation_symmetry_residual_too_large,
                                    "approximation Xhat is not symmetric within tolerance",
                                    :input,
                                    Dict{Symbol, Any}(:symmetry_residual => string(approx.residuals.symmetry_residual),
                                                      :max_symmetry_residual => string(max_symmetry_residual)))

    _diagnostic_exceeds_limit(approx.residuals.psd_violation, max_psd_violation;
                              name=:max_psd_violation) &&
        return CertificationFailure(:approximation_psd_violation_too_large,
                                    "approximation Xhat is not numerically PSD within tolerance",
                                    :input,
                                    Dict{Symbol, Any}(:psd_violation => string(approx.residuals.psd_violation),
                                                      :max_psd_violation => string(max_psd_violation)))

    return nothing
end

function _diagnostic_exceeds_limit(value::BigFloat, limit; name::Symbol)
    isnothing(limit) && return false
    threshold = _bigfloat_scalar(limit; name)
    threshold >= 0 || throw(ArgumentError("$name must be nonnegative"))
    return value > threshold
end

function _certify_from_msolve_output(P::LMIProblem,
                                     approx::ApproxSolution,
                                     profile::RankProfile,
                                     system::PolynomialSystem,
                                     output::MsolveOutput;
                                     psd_method::Union{Symbol, AbstractString}=:auto,
                                     pivot_block=nothing,
                                     root_selection_precision::Integer=max(approx.precision_bits,
                                                                           256),
                                     max_candidates::Integer=16,
                                     verify_io::Union{Nothing, IO}=nothing,
                                     backend_provenance=nothing,
                                     attempt=nothing,)
    output.status === :finite ||
        return CertificationFailure(output.status === :empty ? :msolve_empty_solution_set :
                                    :msolve_positive_dimensional,
                                    "msolve returned status `$(output.status)`",
                                    :msolve,
                                    Dict{Symbol, Any}(:status => output.status,
                                                      :equation_count => length(system.equations),
                                                      :variable_order => String.(variable_symbols(system))))

    candidates = try
        select_nearby_real_solutions(output, P, approx;
                                     precision_bits=root_selection_precision)
    catch err
        return _certification_exception(:root_selection_failed, :root_selection, err)
    end

    isempty(candidates) && return CertificationFailure(:no_real_algebraic_solution,
                                                       "msolve did not return a real RUR solution with all LMI coordinates",
                                                       :root_selection,
                                                       Dict{Symbol, Any}(:msolve_variable_order => String.(output.variable_order),
                                                                         :box_count => length(output.real_solution_boxes),
                                                                         :has_rur => !isnothing(output.rur),
                                                                         :attempt => attempt))

    method_plan = try
        _certification_psd_choices(psd_method, profile, pivot_block, matrix_size(P))
    catch err
        return _certification_exception(:invalid_psd_proof_method, :certificate_build, err)
    end

    selected_failures = Any[]
    for candidate in Iterators.take(candidates, max_candidates)
        solves_incidence = try
            verify_polynomial_system_solution(system, candidate)
        catch err
            push!(selected_failures,
                  _candidate_failure(candidate, :incidence_solution, err))
            continue
        end
        if !solves_incidence
            push!(selected_failures,
                  Dict{Symbol, Any}(:stage => :incidence_solution,
                                    :message => "selected RUR candidate does not exactly satisfy the incidence system",
                                    :distance => string(candidate.distance),
                                    :root_interval => _rational_interval_strings(candidate.root.interval)))
            continue
        end

        for plan in method_plan
            cert = try
                AlgebraicCertificate(P, candidate.root, candidate.coordinates;
                                     psd_method=plan.method,
                                     pivot_block=plan.pivot_block,
                                     provenance=_algebraic_certificate_backend_provenance(backend_provenance))
            catch err
                push!(selected_failures,
                      _candidate_failure(candidate,
                                         :certificate_build,
                                         err;
                                         psd_method=plan.method,
                                         pivot_block=plan.pivot_block))
                continue
            end

            accepted = try
                verify(cert; io=verify_io)
            catch err
                push!(selected_failures,
                      _candidate_failure(candidate,
                                         :verify_exception,
                                         err;
                                         psd_method=plan.method,
                                         pivot_block=plan.pivot_block))
                continue
            end

            accepted && return cert
            push!(selected_failures,
                  Dict{Symbol, Any}(:stage => :verify,
                                    :message => "exact verifier rejected candidate certificate",
                                    :distance => string(candidate.distance),
                                    :root_interval => _rational_interval_strings(candidate.root.interval),
                                    :psd_method => plan.method,
                                    :pivot_block => isnothing(plan.pivot_block) ?
                                                    nothing : copy(plan.pivot_block)))
        end
    end

    reason = _candidate_failures_are_psd(selected_failures) ? :psd_verification_failed :
             :no_candidate_verified
    return CertificationFailure(reason,
                                "no selected algebraic solution produced a certificate accepted by the exact verifier",
                                :verify,
                                Dict{Symbol, Any}(:candidate_count => length(candidates),
                                                  :attempted_candidates => min(length(candidates),
                                                                               max_candidates),
                                                  :attempt => attempt,
                                                  :candidate_failures => selected_failures))
end

function _candidate_failures_are_psd(failures)
    isempty(failures) && return false
    for failure in failures
        stage = get(failure, :stage, nothing)
        stage in (:certificate_build, :verify, :verify_exception) || return false
    end
    return true
end

function _rank_profile_failure(profile)
    if profile isa UnstableRankProfile
        return CertificationFailure(:rank_profile_unstable,
                                    "rank profile is unstable: $(profile.reason)",
                                    :rank_profile,
                                    Dict{Symbol, Any}(:reason => profile.reason,
                                                      :candidate_rank => profile.candidate_rank,
                                                      :tolerance => string(profile.tolerance),
                                                      :singular_values => string.(profile.singular_values),
                                                      :gap => string(profile.gap),
                                                      :method => profile.method))
    end

    return CertificationFailure(:rank_profile_missing,
                                "approximation does not contain a stable rank profile",
                                :rank_profile,
                                Dict{Symbol, Any}(:rank_profile_type => string(typeof(profile))))
end

function _certification_exception(reason::Symbol, stage::Symbol, err)
    return CertificationFailure(reason,
                                sprint(showerror, err),
                                stage,
                                Dict{Symbol, Any}(:exception_type => string(typeof(err))))
end

function _certification_backend_failure(failure::AlgebraicBackendFailure)
    reason = failure.reason === :timeout ? :backend_timeout :
             failure.backend === :msolve ? :msolve_failed : :backend_failed
    return CertificationFailure(reason,
                                failure.message,
                                failure.backend,
                                Dict{Symbol, Any}(:failure_type => "AlgebraicBackendFailure",
                                                  :exception_type => "AlgebraicBackendFailure",
                                                  :backend => failure.backend,
                                                  :backend_reason => failure.reason,
                                                  :backend_failure => failure,
                                                  :backend_provenance => failure.provenance,
                                                  :artifacts => failure.artifacts,
                                                  :stdout => failure.stdout,
                                                  :stderr => failure.stderr))
end

function _algebraic_certificate_backend_provenance(provenance)
    isnothing(provenance) && return Dict{Symbol, Any}()
    return Dict{Symbol, Any}(:algebraic_backend => provenance)
end

function _certification_psd_choice(psd_method, profile::RankProfile, pivot_block,
                                   matrix_size_value::Integer)
    plan = first(_certification_psd_choices(psd_method, profile, pivot_block,
                                            matrix_size_value))
    return plan.method, plan.pivot_block
end

function _certification_psd_choices(psd_method,
                                    profile::RankProfile,
                                    pivot_block,
                                    matrix_size_value::Integer)
    method = Symbol(psd_method)
    if method === :auto
        method = profile.rank < matrix_size_value ? Symbol(SCHUR_ZERO_PSD_METHOD) :
                 :auto
    end

    if method === Symbol(SCHUR_ZERO_PSD_METHOD)
        pivots = isnothing(pivot_block) ? copy(profile.pivot_cols) :
                 Int[value for value in pivot_block]
        plans = Any[(; method, pivot_block=pivots)]
        isnothing(pivot_block) &&
            append!(plans,
                    [(; method=Symbol(RATIONAL_PSD_METHOD), pivot_block=nothing),
                     (; method=Symbol(LDL_PSD_METHOD), pivot_block=nothing),
                     (; method=Symbol(PIVOTED_LDL_PSD_METHOD), pivot_block=nothing)])
        return plans
    elseif method in (Symbol(RATIONAL_PSD_METHOD), Symbol(LDL_PSD_METHOD),
                      Symbol(PIVOTED_LDL_PSD_METHOD), :auto)
        return [(; method, pivot_block=nothing)]
    end

    throw(ArgumentError("unsupported PSD proof method `$psd_method`"))
end

function _candidate_failure(candidate::SelectedAlgebraicSolution,
                            stage::Symbol,
                            err;
                            psd_method=nothing,
                            pivot_block=nothing)
    return Dict{Symbol, Any}(:stage => stage,
                             :message => sprint(showerror, err),
                             :exception_type => string(typeof(err)),
                             :distance => string(candidate.distance),
                             :root_interval => _rational_interval_strings(candidate.root.interval),
                             :psd_method => psd_method,
                             :pivot_block => isnothing(pivot_block) ? nothing :
                                             copy(pivot_block))
end

"""
    select_nearby_real_solutions(output, P, approx; precision_bits=...)

Convert msolve RUR real boxes into exact algebraic LMI-coordinate candidates and
sort them by the coordinate midpoint distance to `approx.xhat`.
"""
function select_nearby_real_solutions(output::MsolveOutput,
                                      P::LMIProblem,
                                      approx::ApproxSolution;
                                      precision_bits::Integer=max(approx.precision_bits,
                                                                  256),)
    output.status === :finite ||
        throw(ArgumentError("cannot select roots from non-finite msolve output status $(output.status)"))
    rur = output.rur
    isnothing(rur) &&
        throw(ArgumentError("msolve output does not contain a RUR parametrization"))
    isempty(output.real_solution_boxes) &&
        throw(ArgumentError("msolve output does not contain real solution boxes"))

    variable_order = !isempty(output.variable_order) ? output.variable_order :
                     rur.variable_order
    variable_order == rur.variable_order ||
        throw(ArgumentError("msolve variable order does not match RUR variable order"))

    coordinate_indices = _lmi_coordinate_indices(variable_order, P.vars)
    candidates = SelectedAlgebraicSolution[]

    for box in output.real_solution_boxes
        length(box) == length(variable_order) ||
            throw(ArgumentError("msolve real solution box has $(length(box)) intervals; expected $(length(variable_order))"))

        root_interval = _selected_parameter_interval(rur, variable_order, box)
        root = AlgebraicRoot(rur.minimal_polynomial, root_interval)
        all_coordinates = _rur_coordinate_elements(rur, root)
        coordinates = AlgebraicElement[all_coordinates[index]
                                       for index in coordinate_indices]
        distance = _coordinate_box_distance(box, coordinate_indices, approx.xhat;
                                            precision_bits)
        push!(candidates,
              SelectedAlgebraicSolution(root, coordinates, all_coordinates, variable_order,
                                        box, distance))
    end

    sort!(candidates; by=candidate -> candidate.distance)
    return candidates
end

"""
    verify_polynomial_system_solution(system, candidate) -> Bool

Exactly evaluate every equation of `system` at a selected RUR candidate. The
candidate variable order may differ from the system's ring order; variables are
matched by name before evaluation. This check verifies the algebraic backend
candidate, not feasibility of the original LMI.
"""
function verify_polynomial_system_solution(system::PolynomialSystem,
                                           candidate::SelectedAlgebraicSolution)
    values = _candidate_values_for_system(system, candidate)
    for equation in system.equations
        iszero(_evaluate_multivariate_polynomial(equation, values)) || return false
    end
    return true
end

function _lmi_coordinate_indices(variable_order::Vector{Symbol}, vars::Vector{Symbol})
    indices = Int[]
    for var in vars
        index = findfirst(==(var), variable_order)
        isnothing(index) &&
            throw(ArgumentError("msolve variable order is missing LMI coordinate `$var`"))
        push!(indices, index)
    end
    return indices
end

function _selected_parameter_interval(rur::RURSolution, variable_order::Vector{Symbol},
                                      box::Vector{MsolveInterval})
    parameter_index = length(variable_order)
    parameter_index >= 1 || throw(ArgumentError("RUR variable order must not be empty"))
    interval = box[parameter_index]
    if interval.lower == interval.upper
        return _point_parameter_interval(rur, interval.lower)
    end
    return RationalInterval(interval.lower, interval.upper)
end

function _point_parameter_interval(rur::RURSolution, point::Rational{BigInt})
    degree(rur.minimal_polynomial) == 1 ||
        throw(ArgumentError("selected RUR parameter interval is a point for a non-linear parameter polynomial"))
    iszero(_evaluate_polynomial(rur.minimal_polynomial, point)) ||
        throw(ArgumentError("selected RUR point interval does not satisfy the parameter polynomial"))
    radius = Rational{BigInt}(1, 1)
    return RationalInterval(point - radius, point + radius)
end

function _rur_coordinate_elements(rur::RURSolution, root::AlgebraicRoot)
    nvars = length(rur.variable_order)
    length(rur.numerators) == nvars - 1 ||
        throw(ArgumentError("RUR has $(length(rur.numerators)) numerators; expected $(nvars - 1)"))
    length(rur.numerator_denominators) == nvars - 1 ||
        throw(ArgumentError("RUR has $(length(rur.numerator_denominators)) numerator divisors; expected $(nvars - 1)"))

    coordinates = AlgebraicElement[]
    sizehint!(coordinates, nvars)
    for i in 1:(nvars - 1)
        divisor = rur.numerator_denominators[i]
        divisor != 0 || throw(ArgumentError("RUR coordinate divisor $i is zero"))
        numerator = -rur.numerators[i]
        denominator = rur.denominator * Rational{BigInt}(divisor, 1)
        push!(coordinates, AlgebraicElement(root, numerator, denominator))
    end

    push!(coordinates, AlgebraicElement(root, "t"))
    return coordinates
end

function _candidate_values_for_system(system::PolynomialSystem,
                                      candidate::SelectedAlgebraicSolution)
    length(candidate.variable_order) == length(candidate.all_coordinates) ||
        throw(ArgumentError("candidate has $(length(candidate.all_coordinates)) coordinates for $(length(candidate.variable_order)) variables"))
    length(unique(candidate.variable_order)) == length(candidate.variable_order) ||
        throw(ArgumentError("candidate variable order contains duplicate names"))

    index_by_variable = Dict{Symbol, Int}(variable => i
                                          for (i, variable) in
                                              enumerate(candidate.variable_order))

    values = AlgebraicElement[]
    for variable in variable_symbols(system)
        index = get(index_by_variable, variable, nothing)
        isnothing(index) &&
            throw(ArgumentError("candidate is missing a value for system variable `$variable`"))
        push!(values, candidate.all_coordinates[index])
    end

    _common_algebraic_root(values)
    return values
end

function _evaluate_multivariate_polynomial(polynomial::MultivariatePolynomial,
                                           values::Vector{AlgebraicElement})
    length(values) == length(polynomial.ring.variables) ||
        throw(DimensionMismatch("got $(length(values)) values for polynomial over $(length(polynomial.ring.variables)) variables"))

    root = _common_algebraic_root(values)
    total = AlgebraicElement(root, 0)

    for (exponents, coefficient) in polynomial.terms
        term = AlgebraicElement(root, coefficient)
        for (value, exponent) in zip(values, exponents)
            exponent == 0 && continue
            term *= value^exponent
        end
        total += term
    end

    return total
end

function _coordinate_box_distance(box::Vector{MsolveInterval},
                                  coordinate_indices::Vector{Int},
                                  xhat::Vector{BigFloat};
                                  precision_bits::Integer,)
    length(coordinate_indices) == length(xhat) ||
        throw(DimensionMismatch("coordinate index count $(length(coordinate_indices)) does not match xhat length $(length(xhat))"))

    return setprecision(BigFloat, precision_bits) do
        total = BigFloat(0)
        for (box_index, target) in zip(coordinate_indices, xhat)
            midpoint = _bigfloat_interval_midpoint(box[box_index])
            delta = midpoint - BigFloat(target)
            total += delta * delta
        end
        return sqrt(total)
    end
end

function _bigfloat_interval_midpoint(interval::MsolveInterval)
    return (_bigfloat_rational(interval.lower) + _bigfloat_rational(interval.upper)) / 2
end

function _rational_interval_strings(interval::RationalInterval)
    return [_rational_string(interval.lower), _rational_string(interval.upper)]
end
