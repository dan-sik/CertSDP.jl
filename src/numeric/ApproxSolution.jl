using Random: MersenneTwister, randn

const DEFAULT_APPROX_PRECISION_BITS = 256
const DEFAULT_RANK_RELATIVE_TOLERANCE = "1e-8"
const DEFAULT_RANK_GAP_THRESHOLD = "1e6"
const DEFAULT_APPROX_SOLVERS = (:clarabel,)
const OPTIONAL_NUMERICAL_SOLVERS = Set([:clarabel])
const CLARABEL_PACKAGE_ID = Base.PkgId(Base.UUID("61c947e1-3e6d-4ee4-985a-eec8c727bd6e"),
                                       "Clarabel")

abstract type NumericalOracleBackend end

struct MissingNumericalOracleBackend <: NumericalOracleBackend
    solver::Symbol
end

"""
    ResidualDiagnostics

Numerical diagnostics for an approximate LMI solution. These values are for
candidate selection and debugging only; exact certificate verification must not
trust them.
"""
struct ResidualDiagnostics
    linear_residual::BigFloat
    symmetry_residual::BigFloat
    min_eigenvalue::BigFloat
    psd_violation::BigFloat
    frobenius_norm::BigFloat
    max_abs_entry::BigFloat
end

"""
    RankProfile

Stable numerical rank profile detected from a BigFloat matrix. The singular
values and pivots are diagnostic data, not proof data.
"""
struct RankProfile
    rank::Int
    pivot_cols::Vector{Int}
    pivot_rows::Vector{Int}
    permutation::Vector{Int}
    tolerance::BigFloat
    singular_values::Vector{BigFloat}
    gap::BigFloat
    method::Symbol
end

"""
    UnstableRankProfile

Returned by `detect_rank_profile` when the numerical singular values do not
show a reliable separation at the requested tolerance.
"""
struct UnstableRankProfile
    reason::String
    tolerance::BigFloat
    singular_values::Vector{BigFloat}
    gap::BigFloat
    candidate_rank::Int
    method::Symbol
end

"""
    ApproxQualityReport

Reusable numerical-oracle diagnostics for an approximate LMI solution. These
fields are human/debugging evidence only; exact verification must still rebuild
the proof over QQ or QQ(alpha).
"""
struct ApproxQualityReport
    problem_hash::String
    residual::BigFloat
    linear_residual::BigFloat
    symmetry_residual::BigFloat
    min_eigenvalue::BigFloat
    psd_violation::BigFloat
    eigenvalue_gap::BigFloat
    rank_estimate::Int
    rank_confidence::Symbol
    rank_gap::BigFloat
    solver_name::Symbol
    solver_status::Symbol
    precision_bits::Int
    primal_residual::Union{Nothing, BigFloat}
    dual_residual::Union{Nothing, BigFloat}
    objective_value::Union{Nothing, BigFloat}
    objective_kind::Symbol
    objective_vector::Vector{BigFloat}
    trace_value::BigFloat
    face_clarity::Symbol
    face_clarity_score::BigFloat
    attempt_index::Int
    retry_index::Int
end

"""
    ApproxSolution

Approximate solution data `xhat` and the evaluated matrix `Xhat = A(xhat)`,
with residual diagnostics and a numerical rank profile.
"""
struct ApproxSolution
    problem_hash::String
    xhat::Vector{BigFloat}
    Xhat::Matrix{BigFloat}
    residuals::ResidualDiagnostics
    eigvals::Vector{BigFloat}
    rank_estimate::Int
    precision_bits::Int
    rank_profile::Union{RankProfile, UnstableRankProfile}
    quality_report::ApproxQualityReport
    slicing_hints::Dict{Symbol, Any}
    oracle_metadata::Dict{Symbol, Any}
end

"""
    ApproxSolution(P, xhat; precision_bits=256, Xhat=nothing, kwargs...)

Build numerical diagnostics for an approximate LMI solution. If `Xhat` is not
provided, it is recomputed as `A(xhat)` using BigFloat arithmetic. If `Xhat` is
provided, `residuals.linear_residual` records the max-entry discrepancy from
the recomputed matrix.
"""
function ApproxSolution(P::LMIProblem,
                        xhat;
                        precision_bits::Integer=DEFAULT_APPROX_PRECISION_BITS,
                        Xhat=nothing,
                        solver_name::Union{Symbol, AbstractString}=:user,
                        solver_status::Union{Symbol, AbstractString}=:user_supplied,
                        objective_value=nothing,
                        objective_kind::Union{Symbol, AbstractString}=:user,
                        objective_vector=nothing,
                        attempt_index::Integer=1,
                        retry_index::Integer=1,
                        solver_primal_residual=nothing,
                        solver_dual_residual=nothing,
                        slicing_hints=nothing,
                        oracle_metadata=nothing,
                        rank_kwargs...,)
    precision_bits > 0 || throw(ArgumentError("precision_bits must be positive"))

    return setprecision(BigFloat, precision_bits) do
        x = _bigfloat_vector(xhat; precision_bits, name=:xhat)
        length(x) == num_variables(P) ||
            throw(DimensionMismatch("xhat has length $(length(x)); expected $(num_variables(P))"))

        evaluated = evaluate_lmi_bigfloat(P, x; precision_bits)
        matrix = isnothing(Xhat) ? evaluated :
                 _bigfloat_matrix(Xhat; precision_bits, name=:Xhat)
        size(matrix) == size(evaluated) ||
            throw(DimensionMismatch("Xhat has size $(size(matrix)); expected $(size(evaluated))"))

        eigenvalues = _symmetric_eigenvalues_bigfloat(_symmetrized_matrix(matrix);
                                                      precision_bits)
        diagnostics = residual_diagnostics(evaluated, matrix, eigenvalues)
        profile = detect_rank_profile(matrix; precision_bits, rank_kwargs...)
        rank = profile isa RankProfile ? profile.rank : profile.candidate_rank
        report = ApproxQualityReport(lmi_problem_hash(P),
                                     diagnostics,
                                     eigenvalues,
                                     profile;
                                     precision_bits=Int(precision_bits),
                                     solver_name=Symbol(solver_name),
                                     solver_status=Symbol(solver_status),
                                     objective_value,
                                     objective_kind=Symbol(objective_kind),
                                     objective_vector=isnothing(objective_vector) ?
                                                      BigFloat[] :
                                                      _bigfloat_vector(objective_vector;
                                                                       precision_bits,
                                                                       name=:objective_vector),
                                     trace_value=_matrix_trace(matrix),
                                     attempt_index=Int(attempt_index),
                                     retry_index=Int(retry_index),
                                     primal_residual=solver_primal_residual,
                                     dual_residual=solver_dual_residual,)

        hints = _approx_slicing_hints(slicing_hints)
        metadata = _approx_oracle_metadata(oracle_metadata)
        _record_rank_settings!(metadata, rank_kwargs)
        return ApproxSolution(lmi_problem_hash(P),
                              x,
                              matrix,
                              diagnostics,
                              eigenvalues,
                              rank,
                              Int(precision_bits),
                              profile,
                              report,
                              hints,
                              metadata)
    end
end

function ApproxSolution(P::BlockLMIProblem,
                        xhat;
                        Xhat=nothing,
                        block_Xhat=nothing,
                        kwargs...)
    isnothing(Xhat) || isnothing(block_Xhat) ||
        throw(ArgumentError("pass either Xhat or block_Xhat for a block LMI approximation, not both"))
    aggregate = block_diagonal_lmi_problem(P)
    aggregate_Xhat = isnothing(block_Xhat) ? Xhat :
                     _block_diagonal_matrix(block_Xhat; name=:block_Xhat)
    approx = ApproxSolution(aggregate, xhat; Xhat=aggregate_Xhat, kwargs...)
    return _retag_approx_solution(approx, block_lmi_problem_hash(P))
end

function _block_diagonal_matrix(blocks; name::Symbol)
    blocks isa AbstractVector || throw(ArgumentError("$name must be a vector of matrices"))
    isempty(blocks) && throw(ArgumentError("$name must not be empty"))
    sizes = Int[]
    for (i, block) in enumerate(blocks)
        block isa AbstractMatrix ||
            throw(ArgumentError("$name[$i] must be a matrix"))
        size(block, 1) == size(block, 2) ||
            throw(DimensionMismatch("$name[$i] must be square; got $(size(block))"))
        push!(sizes, size(block, 1))
    end
    total = sum(sizes)
    result = Matrix{Any}(fill(0, total, total))
    offset = 0
    for (block, size_value) in zip(blocks, sizes)
        rows = (offset + 1):(offset + size_value)
        result[rows, rows] .= block
        offset += size_value
    end
    return result
end

function _retag_approx_solution(approx::ApproxSolution, problem_hash::AbstractString)
    return ApproxSolution(String(problem_hash),
                          copy(approx.xhat),
                          copy(approx.Xhat),
                          approx.residuals,
                          copy(approx.eigvals),
                          approx.rank_estimate,
                          approx.precision_bits,
                          approx.rank_profile,
                          _retag_quality_report(approx.quality_report, problem_hash),
                          copy(approx.slicing_hints),
                          copy(approx.oracle_metadata))
end

function _retag_quality_report(report::ApproxQualityReport,
                               problem_hash::AbstractString)
    return ApproxQualityReport(String(problem_hash),
                               report.residual,
                               report.linear_residual,
                               report.symmetry_residual,
                               report.min_eigenvalue,
                               report.psd_violation,
                               report.eigenvalue_gap,
                               report.rank_estimate,
                               report.rank_confidence,
                               report.rank_gap,
                               report.solver_name,
                               report.solver_status,
                               report.precision_bits,
                               report.primal_residual,
                               report.dual_residual,
                               report.objective_value,
                               report.objective_kind,
                               copy(report.objective_vector),
                               report.trace_value,
                               report.face_clarity,
                               report.face_clarity_score,
                               report.attempt_index,
                               report.retry_index)
end

function _approx_slicing_hints(value)
    isnothing(value) && return Dict{Symbol, Any}()
    if value isa AbstractDict
        return Dict{Symbol, Any}(Symbol(key) => val for (key, val) in value)
    elseif value isa NamedTuple
        return Dict{Symbol, Any}(Symbol(key) => val for (key, val) in pairs(value))
    end
    throw(ArgumentError("slicing_hints must be a dictionary, named tuple, or nothing"))
end

function _approx_oracle_metadata(value)
    if isnothing(value)
        return Dict{Symbol, Any}()
    elseif value isa AbstractDict
        return Dict{Symbol, Any}(Symbol(key) => val for (key, val) in value)
    elseif value isa NamedTuple
        return Dict{Symbol, Any}(Symbol(key) => val for (key, val) in pairs(value))
    end
    throw(ArgumentError("oracle_metadata must be a dictionary, named tuple, or nothing"))
end

function _record_rank_settings!(metadata::Dict{Symbol, Any}, rank_kwargs)
    rank_options = Dict{Symbol, Any}(Symbol(key) => value
                                     for (key, value) in pairs(rank_kwargs))
    metadata[:rank_relative_tolerance] = string(get(rank_options,
                                                    :relative_tolerance,
                                                    DEFAULT_RANK_RELATIVE_TOLERANCE))
    metadata[:rank_gap_threshold] = string(get(rank_options,
                                               :gap_threshold,
                                               DEFAULT_RANK_GAP_THRESHOLD))
    if haskey(rank_options, :absolute_tolerance)
        metadata[:rank_absolute_tolerance] = string(rank_options[:absolute_tolerance])
    end
    return metadata
end

function ApproxQualityReport(problem_hash::AbstractString,
                             residuals::ResidualDiagnostics,
                             eigvals::AbstractVector{BigFloat},
                             profile::Union{RankProfile, UnstableRankProfile};
                             precision_bits::Integer,
                             solver_name::Symbol,
                             solver_status::Symbol,
                             objective_value=nothing,
                             objective_kind::Symbol=:unknown,
                             objective_vector=BigFloat[],
                             trace_value=BigFloat(0),
                             attempt_index::Integer=1,
                             retry_index::Integer=1,
                             primal_residual=nothing,
                             dual_residual=nothing,)
    rank = profile isa RankProfile ? profile.rank : profile.candidate_rank
    rank_gap = profile.gap
    confidence = _rank_confidence(profile)
    residual = maximum((residuals.linear_residual,
                        residuals.symmetry_residual,
                        residuals.psd_violation))
    objective = isnothing(objective_value) ? nothing :
                _bigfloat_scalar(objective_value; name=:objective_value)
    primal = isnothing(primal_residual) ? nothing :
             _bigfloat_scalar(primal_residual; name=:primal_residual)
    dual = isnothing(dual_residual) ? nothing :
           _bigfloat_scalar(dual_residual; name=:dual_residual)
    clarity, clarity_score = _face_clarity(profile, eigvals, residuals)

    return ApproxQualityReport(String(problem_hash),
                               residual,
                               residuals.linear_residual,
                               residuals.symmetry_residual,
                               residuals.min_eigenvalue,
                               residuals.psd_violation,
                               _eigenvalue_rank_gap(eigvals, rank),
                               rank,
                               confidence,
                               rank_gap,
                               solver_name,
                               solver_status,
                               Int(precision_bits),
                               primal,
                               dual,
                               objective,
                               objective_kind,
                               BigFloat[objective_vector...],
                               _bigfloat_scalar(trace_value; name=:trace_value),
                               clarity,
                               clarity_score,
                               Int(attempt_index),
                               Int(retry_index))
end

function _rank_confidence(profile::RankProfile)
    isinf(profile.gap) && return :high
    profile.gap >= parse(BigFloat, "1e12") && return :high
    return :medium
end

_rank_confidence(::UnstableRankProfile) = :unstable

function _eigenvalue_rank_gap(eigvals::AbstractVector{BigFloat}, rank::Integer)
    n = length(eigvals)
    n == 0 && return BigFloat(Inf)
    rank <= 0 && return eigvals[end] == 0 ? BigFloat(Inf) :
                        abs(eigvals[end]) == 0 ? BigFloat(Inf) :
                        inv(abs(eigvals[end]))
    rank >= n && return eigvals[1] == 0 ? BigFloat(Inf) :
                        abs(eigvals[1]) == 0 ? BigFloat(Inf) :
                        abs(eigvals[1])

    lower = abs(eigvals[n - rank])
    upper = abs(eigvals[n - rank + 1])
    lower == 0 && return BigFloat(Inf)
    return upper / lower
end

"""
    approx_quality_report_json(report) -> NamedTuple

Return a JSON-ready v1.0 numerical diagnostic report.
"""
function approx_quality_report_json(report::ApproxQualityReport)
    return (;
            certsdp_approx_report_version="1.0",
            status=report.rank_confidence === :unstable ? "rank_unstable" : "ok",
            problem_hash=report.problem_hash,
            residual=string(report.residual),
            linear_residual=string(report.linear_residual),
            symmetry_residual=string(report.symmetry_residual),
            min_eigenvalue=string(report.min_eigenvalue),
            psd_violation=string(report.psd_violation),
            eigenvalue_gap=string(report.eigenvalue_gap),
            rank_estimate=report.rank_estimate,
            rank_confidence=String(report.rank_confidence),
            rank_gap=string(report.rank_gap),
            solver_name=String(report.solver_name),
            solver_status=String(report.solver_status),
            precision_bits=report.precision_bits,
            primal_residual=isnothing(report.primal_residual) ? nothing :
                            string(report.primal_residual),
            dual_residual=isnothing(report.dual_residual) ? nothing :
                          string(report.dual_residual),
            objective_value=isnothing(report.objective_value) ? nothing :
                            string(report.objective_value),
            objective_kind=String(report.objective_kind),
            objective_vector=string.(report.objective_vector),
            trace=string(report.trace_value),
            face_clarity=String(report.face_clarity),
            face_clarity_score=string(report.face_clarity_score),
            attempt_index=report.attempt_index,
            retry_index=report.retry_index,
            recommendation=_approx_report_recommendation(report),)
end

function approx_quality_report_json(approx::ApproxSolution)
    return approx_quality_report_json(approx.quality_report)
end

function _approx_report_recommendation(report::ApproxQualityReport)
    report.rank_confidence === :unstable &&
        return "rank profile is unstable; rerun the numerical solver with higher precision or random objective restarts"
    report.psd_violation > max(parse(BigFloat, "1e-8"), report.residual) &&
        return "candidate is numerically outside the PSD cone; recompute the approximate solution"
    report.face_clarity in (:ambiguous, :unstable) &&
        return "face clarity is weak; try random linear objectives, trace objective, or a different rank tolerance before certification"
    report.rank_estimate < 0 &&
        return "rank could not be estimated reliably"
    return "rank profile is usable for certification heuristics; exact verification is still required"
end

"""
    solve_approximately(problem; solvers=[:clarabel], random_objective_trials=0,
                        precision=256, solution=nothing, xhat=nothing)

Obtain a reusable approximate LMI solution with numerical diagnostics. A
user-supplied `solution`/`xhat` is wrapped without calling a solver; otherwise
the requested numerical solvers are tried and the best diagnostic candidate is
returned. Numerical output is never verifier evidence.
"""
function solve_approximately(P::LMIProblem;
                             solvers=DEFAULT_APPROX_SOLVERS,
                             random_objective_trials::Integer=0,
                             trace_objective=true,
                             solver_attempts::Integer=1,
                             solver_retry_policy::Union{Symbol, AbstractString}=:default,
                             precision=DEFAULT_APPROX_PRECISION_BITS,
                             solution=nothing,
                             xhat=nothing,
                             Xhat=nothing,
                             random_seed::Integer=0,
                             require_stable_rank::Bool=false,
                             clarabel_max_iter::Integer=200,
                             clarabel_time_limit=nothing,
                             rank_kwargs...)
    precision_bits = _precision_bits(precision)
    random_objective_trials >= 0 ||
        return CertificationFailure(:invalid_options,
                                    "random_objective_trials must be nonnegative",
                                    :numerical_oracle,
                                    Dict{Symbol, Any}(:random_objective_trials => random_objective_trials))
    solver_attempts > 0 ||
        return CertificationFailure(:invalid_options,
                                    "solver_attempts must be positive",
                                    :numerical_oracle,
                                    Dict{Symbol, Any}(:solver_attempts => solver_attempts))

    user_solution = isnothing(solution) ? xhat : solution
    if user_solution isa ApproxSolution
        problem_hash = lmi_problem_hash(P)
        user_solution.problem_hash == problem_hash ||
            return CertificationFailure(:approximation_problem_mismatch,
                                        "user-supplied approximation hash $(user_solution.problem_hash) does not match problem hash $problem_hash",
                                        :numerical_oracle,
                                        Dict{Symbol, Any}(:approx_problem_hash => user_solution.problem_hash,
                                                          :problem_hash => problem_hash))
        return _maybe_require_stable_rank(user_solution; require_stable_rank)
    elseif !isnothing(user_solution)
        approx = try
            ApproxSolution(P,
                           user_solution;
                           precision_bits,
                           Xhat,
                           solver_name=:user,
                           solver_status=:user_supplied,
                           rank_kwargs...)
        catch err
            return _numerical_oracle_exception(:user_solution_invalid, err)
        end
        return _maybe_require_stable_rank(approx; require_stable_rank)
    end

    num_variables(P) == 0 && begin
                             approx = ApproxSolution(P,
                                                     BigFloat[];
                                                     precision_bits,
                                                     solver_name=:constant,
                                                     solver_status=:not_run,
                                                     rank_kwargs...)
                             return _maybe_require_stable_rank(approx; require_stable_rank)
                             end

    candidates = ApproxSolution[]
    failures = Any[]
    attempts = Any[]
    objectives = _oracle_objectives(P, random_objective_trials;
                                    random_seed,
                                    trace_objective)
    retry_specs = _solver_retry_specs(solver_attempts;
                                      policy=solver_retry_policy,
                                      clarabel_max_iter,
                                      clarabel_time_limit)

    for solver in _solver_vector(solvers)
        solver_symbol = Symbol(solver)
        for objective in objectives, retry_spec in retry_specs
            attempt_index = length(attempts) + 1
            result = if solver_symbol in OPTIONAL_NUMERICAL_SOLVERS
                _solve_approximately_with_solver(P,
                                                 Val(solver_symbol),
                                                 objective;
                                                 precision_bits,
                                                 retry_spec,
                                                 attempt_index,
                                                 rank_kwargs...)
            else
                CertificationFailure(:unsupported_numerical_solver,
                                     "unsupported numerical solver `$solver_symbol`; this release supports `:clarabel` and user-supplied solutions",
                                     :numerical_oracle,
                                     Dict{Symbol, Any}(:solver => String(solver_symbol),
                                                       :objective_kind => String(objective.kind),
                                                       :retry_index => retry_spec.retry_index))
            end

            if result isa ApproxSolution
                score = face_search_candidate_score(result)
                result.oracle_metadata[:attempt] = _oracle_attempt_metadata(solver_symbol,
                                                                            objective,
                                                                            retry_spec,
                                                                            :accepted,
                                                                            score)
                push!(candidates, result)
                push!(attempts, result.oracle_metadata[:attempt])
            elseif result isa FailureResult
                failure_json = certification_failure_json(result)
                push!(failures, failure_json)
                push!(attempts,
                      _oracle_attempt_metadata(solver_symbol, objective, retry_spec,
                                               :failed, failure_json))
            elseif result isa CertificationFailure
                failure_json = certification_failure_json(result)
                push!(failures, failure_json)
                push!(attempts,
                      _oracle_attempt_metadata(solver_symbol, objective, retry_spec,
                                               :failed, failure_json))
            else
                push!(failures, string(result))
                push!(attempts,
                      _oracle_attempt_metadata(solver_symbol, objective, retry_spec,
                                               :failed, string(result)))
            end
        end
    end

    if isempty(candidates)
        return CertificationFailure(:numerical_solver_failed,
                                    "no numerical solver produced an accepted approximate solution",
                                    :numerical_oracle,
                                    Dict{Symbol, Any}(:solvers => String.(Symbol.(_solver_vector(solvers))),
                                                      :attempts => length(attempts),
                                                      :attempt_log => attempts,
                                                      :failures => failures))
    end

    best = _select_best_approx_candidate(candidates)
    best.oracle_metadata[:candidate_count] = length(candidates)
    best.oracle_metadata[:failure_count] = length(failures)
    best.oracle_metadata[:attempts] = attempts
    best.oracle_metadata[:selected_score] = face_search_candidate_score(best)
    best.oracle_metadata[:selection_policy] = :max_rank_face_search
    final = _maybe_require_stable_rank(best; require_stable_rank)
    if final isa CertificationFailure
        diagnostics = copy(final.diagnostics)
        diagnostics[:attempts] = attempts
        diagnostics[:selected_score] = best.oracle_metadata[:selected_score]
        return CertificationFailure(final.reason, final.message, final.stage,
                                    diagnostics)
    end
    return final
end

function solve_approximately(P::BlockLMIProblem; kwargs...)
    return solve_approximately(single_lmi_problem(P); kwargs...)
end

function _maybe_require_stable_rank(approx::ApproxSolution; require_stable_rank::Bool)
    (!require_stable_rank || approx.rank_profile isa RankProfile) && return approx
    return _rank_unstable_failure(approx)
end

function _rank_unstable_failure(approx::ApproxSolution)
    profile = approx.rank_profile
    if profile isa UnstableRankProfile
        return CertificationFailure(:rank_profile_unstable,
                                    "rank profile is unstable: $(profile.reason)",
                                    :rank_profile,
                                    Dict{Symbol, Any}(:reason => profile.reason,
                                                      :candidate_rank => profile.candidate_rank,
                                                      :tolerance => string(profile.tolerance),
                                                      :singular_values => string.(profile.singular_values),
                                                      :gap => string(profile.gap),
                                                      :method => profile.method,
                                                      :approx_quality_report => approx_quality_report_json(approx)))
    end
    return CertificationFailure(:rank_profile_missing,
                                "approximation does not contain a stable rank profile",
                                :rank_profile,
                                Dict{Symbol, Any}(:rank_profile_type => string(typeof(profile)),
                                                  :approx_quality_report => approx_quality_report_json(approx)))
end

function _precision_bits(precision)
    precision isa Integer && precision > 0 && return Int(precision)
    precision isa Integer &&
        throw(ArgumentError("precision must be positive; got $precision"))
    symbol = Symbol(precision)
    symbol in (:default, :high) && return DEFAULT_APPROX_PRECISION_BITS
    symbol in (:double, :float64) && return 128
    symbol === :very_high && return 512
    throw(ArgumentError("unsupported precision `$precision`; use an integer bit count, :default, :high, :double, or :very_high"))
end

function _solver_vector(solvers)
    if solvers isa Symbol || solvers isa AbstractString
        return [Symbol(solvers)]
    elseif solvers isa AbstractVector || solvers isa Tuple
        return [Symbol(solver) for solver in solvers]
    end
    throw(ArgumentError("solvers must be a symbol, string, tuple, or vector"))
end

function _oracle_objectives(P::LMIProblem, random_objective_trials::Integer;
                            random_seed::Integer,
                            trace_objective=true)
    n = num_variables(P)
    objectives = NamedTuple[(;
                             kind=:feasibility,
                             vector=zeros(Float64, n),
                             trial=0,
                             direction=:none,
                             seed=random_seed,)]
    trace_modes = _trace_objective_modes(trace_objective)
    trace_vector = _trace_objective_vector(P)
    for mode in trace_modes
        objective = mode === :maximize ? -trace_vector : trace_vector
        normalized = _normalized_objective(objective)
        isnothing(normalized) && continue
        push!(objectives,
              (;
               kind=mode === :maximize ? :trace_max : :trace_min,
               vector=normalized,
               trial=0,
               direction=mode,
               seed=random_seed,))
    end

    rng = MersenneTwister(random_seed)
    for trial in 1:random_objective_trials
        objective = randn(rng, n)
        normalized = _normalized_objective(objective)
        isnothing(normalized) && continue
        push!(objectives,
              (;
               kind=:random_linear,
               vector=normalized,
               trial,
               direction=:forward,
               seed=random_seed,))
        push!(objectives,
              (;
               kind=:random_linear,
               vector=-normalized,
               trial,
               direction=:reverse,
               seed=random_seed,))
    end
    return objectives
end

function _trace_objective_modes(trace_objective)
    trace_objective === false && return Symbol[]
    trace_objective === true && return [:maximize]
    mode = Symbol(trace_objective)
    mode in (:none, :false, :off, :no) && return Symbol[]
    mode in (:maximize, :max, :trace_max) && return [:maximize]
    mode in (:minimize, :min, :trace_min) && return [:minimize]
    mode === :both && return [:maximize, :minimize]
    throw(ArgumentError("trace_objective must be true, false, :maximize, :minimize, or :both"))
end

function _trace_objective_vector(P::LMIProblem)
    return Float64[_matrix_trace(rational_matrix(matrix)) for matrix in P.A]
end

function _normalized_objective(objective::AbstractVector{<:Real})
    vector = collect(Float64, objective)
    norm_value = sqrt(sum(value -> value * value, vector))
    norm_value == 0 && return nothing
    vector ./= norm_value
    return vector
end

function _solver_retry_specs(solver_attempts::Integer;
                             policy::Union{Symbol, AbstractString}=:default,
                             clarabel_max_iter::Integer=200,
                             clarabel_time_limit=nothing)
    retry_policy = Symbol(policy)
    retry_policy in (:default, :none, :conservative) ||
        throw(ArgumentError("unsupported solver_retry_policy `$policy`"))
    specs = NamedTuple[]
    for retry_index in 1:solver_attempts
        max_iter = retry_policy === :none ? clarabel_max_iter :
                   clarabel_max_iter * retry_index
        tol_scale = retry_policy === :conservative ? retry_index : 1
        push!(specs,
              (;
               retry_index,
               max_iter,
               time_limit=isnothing(clarabel_time_limit) ? Inf :
                          Float64(clarabel_time_limit),
               tol_feas=1.0e-8 / tol_scale,
               tol_gap_abs=1.0e-8 / tol_scale,
               tol_gap_rel=1.0e-8 / tol_scale,))
    end
    return specs
end

function _solve_approximately_with_solver(P::LMIProblem,
                                          solver::Val{solver_symbol},
                                          objective;
                                          precision_bits::Integer,
                                          retry_spec,
                                          attempt_index::Integer,
                                          rank_kwargs...) where {solver_symbol}
    _maybe_load_optional_numerical_backend(solver)
    backend = Base.invokelatest(_optional_numerical_backend, solver)
    backend isa MissingNumericalOracleBackend &&
        return _missing_numerical_backend_failure(backend.solver, objective,
                                                  retry_spec)
    return Base.invokelatest(_solve_approximately_with_backend,
                             P,
                             backend,
                             objective;
                             precision_bits,
                             retry_spec,
                             attempt_index,
                             rank_kwargs...)
end

function _optional_numerical_backend(::Val{solver}) where {solver}
    return MissingNumericalOracleBackend(Symbol(solver))
end

function _maybe_load_optional_numerical_backend(::Val{solver}) where {solver}
    solver === :clarabel || return false
    return try
        Base.require(CLARABEL_PACKAGE_ID)
        true
    catch
        false
    end
end

function _solve_approximately_with_backend(P::LMIProblem,
                                           backend::NumericalOracleBackend,
                                           objective;
                                           precision_bits::Integer,
                                           retry_spec,
                                           attempt_index::Integer,
                                           rank_kwargs...)
    return _missing_numerical_backend_failure(_backend_solver_symbol(backend),
                                              objective,
                                              retry_spec)
end

_backend_solver_symbol(backend::MissingNumericalOracleBackend) = backend.solver
_backend_solver_symbol(::NumericalOracleBackend) = :unknown

function _missing_numerical_backend_failure(solver::Symbol, objective, retry_spec)
    return CertificationFailure(:numerical_solver_unavailable,
                                "numerical solver `$solver` is optional and is not available in the active Julia environment; load or install the solver package, or pass a user-supplied approximate solution",
                                :numerical_oracle,
                                Dict{Symbol, Any}(:solver => String(solver),
                                                  :objective_kind => String(objective.kind),
                                                  :retry_index => retry_spec.retry_index,
                                                  :trust_boundary => "the exact verifier does not depend on numerical solver packages"))
end

function _select_best_approx_candidate(candidates::Vector{ApproxSolution})
    isempty(candidates) && throw(ArgumentError("no approximate candidates"))
    return first(sort(candidates; by=_approx_candidate_score, rev=true))
end

function _matrix_trace(matrix::AbstractMatrix)
    _check_square(matrix; name=:matrix)
    total = zero(eltype(matrix))
    for i in axes(matrix, 1)
        total += matrix[i, i]
    end
    return total
end

function _face_clarity(profile::RankProfile,
                       eigvals::AbstractVector{BigFloat},
                       residuals::ResidualDiagnostics)
    m = length(eigvals)
    m == 0 && return :full_rank, BigFloat(Inf)
    profile.rank >= m && return :full_rank, BigFloat(Inf)
    profile.rank <= 0 && return :ambiguous, profile.gap
    score = min(profile.gap, _eigenvalue_rank_gap(eigvals, profile.rank))
    residuals.psd_violation > parse(BigFloat, "1e-7") && return :unstable, score
    score >= parse(BigFloat, "1e12") && return :clear, score
    score >= parse(BigFloat, "1e6") && return :usable, score
    return :ambiguous, score
end

function _face_clarity(profile::UnstableRankProfile,
                       eigvals::AbstractVector{BigFloat},
                       residuals::ResidualDiagnostics)
    return :unstable, profile.gap
end

function _approx_candidate_score(approx::ApproxSolution)
    score = face_search_candidate_score(approx)
    gap = isinf(approx.quality_report.rank_gap) ? 1.0e300 :
          Float64(approx.quality_report.rank_gap)
    return (score.feasible_for_certification ? 1 : 0,
            score.stable_rank ? 1 : 0,
            score.rank_estimate,
            score.rank_confidence_score,
            Float64(score.face_clarity_score),
            -Float64(score.psd_violation),
            -Float64(score.residual),
            gap)
end

"""
    face_search_candidate_score(approx)

Return the numerical max-rank / face-search score used to select among solver
attempts. The score is only a heuristic for choosing candidates; exact
certification still happens later.
"""
function face_search_candidate_score(approx::ApproxSolution)
    report = approx.quality_report
    feasible_limit = max(parse(BigFloat, "1e-7"),
                         parse(BigFloat, "1e3") * max(report.residual,
                                                      eps(BigFloat)))
    confidence_score = report.rank_confidence === :high ? 3 :
                       report.rank_confidence === :medium ? 2 : 0
    clarity_score = report.face_clarity === :full_rank ? 4 :
                    report.face_clarity === :clear ? 3 :
                    report.face_clarity === :usable ? 2 :
                    report.face_clarity === :ambiguous ? 1 : 0
    return (;
            selection_policy="max_rank_face_search",
            stable_rank=approx.rank_profile isa RankProfile,
            feasible_for_certification=report.psd_violation <= feasible_limit,
            rank_estimate=report.rank_estimate,
            rank_confidence=String(report.rank_confidence),
            rank_confidence_score=confidence_score,
            face_clarity=String(report.face_clarity),
            face_clarity_class_score=clarity_score,
            face_clarity_score=report.face_clarity_score,
            eigengap=report.eigenvalue_gap,
            rank_gap=report.rank_gap,
            residual=report.residual,
            psd_violation=report.psd_violation,
            objective_kind=String(report.objective_kind),
            objective_value=isnothing(report.objective_value) ? nothing :
                            report.objective_value,
            attempt_index=report.attempt_index,
            retry_index=report.retry_index,)
end

function _oracle_attempt_metadata(solver::Symbol, objective, retry_spec, status::Symbol,
                                  payload)
    return Dict{Symbol, Any}(:solver => solver,
                             :objective_kind => objective.kind,
                             :objective_vector => string.(objective.vector),
                             :objective_trial => objective.trial,
                             :objective_direction => objective.direction,
                             :random_seed => objective.seed,
                             :retry_index => retry_spec.retry_index,
                             :max_iter => retry_spec.max_iter,
                             :status => status,
                             :payload => payload)
end

function max_rank_workflow_summary(approx::ApproxSolution)
    attempts = get(approx.oracle_metadata, :attempts, Any[])
    score = face_search_candidate_score(approx)
    return (;
            selection_policy="max_rank_face_search",
            selected_attempt=approx.quality_report.attempt_index,
            selected_objective_kind=String(approx.quality_report.objective_kind),
            selected_rank=approx.rank_estimate,
            selected_rank_confidence=String(approx.quality_report.rank_confidence),
            selected_face_clarity=String(approx.quality_report.face_clarity),
            selected_score=_certification_diagnostics_json(score),
            candidate_count=get(approx.oracle_metadata, :candidate_count, length(attempts)),
            failure_count=get(approx.oracle_metadata, :failure_count, 0),
            attempt_count=length(attempts),
            attempts=_certification_diagnostics_json(attempts),)
end

function _numerical_oracle_exception(reason::Symbol, err)
    return CertificationFailure(reason,
                                sprint(showerror, err),
                                :numerical_oracle,
                                Dict{Symbol, Any}(:exception_type => string(typeof(err))))
end

"""
    evaluate_lmi_bigfloat(P, xhat; precision_bits=256) -> Matrix{BigFloat}

Evaluate `A0 + sum(xhat[i] * A[i])` using BigFloat arithmetic.
"""
function evaluate_lmi_bigfloat(P::LMIProblem, xhat;
                               precision_bits::Integer=DEFAULT_APPROX_PRECISION_BITS)
    precision_bits > 0 || throw(ArgumentError("precision_bits must be positive"))

    return setprecision(BigFloat, precision_bits) do
        x = _bigfloat_vector(xhat; precision_bits, name=:xhat)
        length(x) == num_variables(P) ||
            throw(DimensionMismatch("xhat has length $(length(x)); expected $(num_variables(P))"))

        m = matrix_size(P)
        result = Matrix{BigFloat}(undef, m, m)
        A0 = rational_matrix(P.A0)
        for i in 1:m, j in 1:m
            result[i, j] = _bigfloat_rational(A0[i, j])
        end

        for (value, coefficient) in zip(x, P.A)
            entries = rational_matrix(coefficient)
            for i in 1:m, j in 1:m
                result[i, j] += value * _bigfloat_rational(entries[i, j])
            end
        end

        return result
    end
end

"""
    residual_diagnostics(P, xhat; precision_bits=256, Xhat=nothing)

Compute numerical residual diagnostics for an LMI approximate solution.
"""
function residual_diagnostics(P::LMIProblem,
                              xhat;
                              precision_bits::Integer=DEFAULT_APPROX_PRECISION_BITS,
                              Xhat=nothing,)
    return setprecision(BigFloat, precision_bits) do
        evaluated = evaluate_lmi_bigfloat(P, xhat; precision_bits)
        matrix = isnothing(Xhat) ? evaluated :
                 _bigfloat_matrix(Xhat; precision_bits, name=:Xhat)
        eigenvalues = _symmetric_eigenvalues_bigfloat(_symmetrized_matrix(matrix);
                                                      precision_bits)
        return residual_diagnostics(evaluated, matrix, eigenvalues)
    end
end

function residual_diagnostics(evaluated::AbstractMatrix{BigFloat},
                              matrix::AbstractMatrix{BigFloat},
                              eigenvalues::AbstractVector{BigFloat})
    size(evaluated) == size(matrix) ||
        throw(DimensionMismatch("evaluated matrix has size $(size(evaluated)); got matrix size $(size(matrix))"))

    linear_residual = _max_abs_difference(matrix, evaluated)
    symmetry_residual = _symmetry_residual(matrix)
    min_eigenvalue = isempty(eigenvalues) ? BigFloat(0) : minimum(eigenvalues)
    psd_violation = min_eigenvalue < 0 ? -min_eigenvalue : BigFloat(0)
    frobenius_norm = _frobenius_norm(matrix)
    max_abs_entry = _max_abs_entry(matrix)

    return ResidualDiagnostics(linear_residual,
                               symmetry_residual,
                               min_eigenvalue,
                               psd_violation,
                               frobenius_norm,
                               max_abs_entry)
end

"""
    detect_rank_profile(A; precision_bits=256, relative_tolerance=1e-8, gap_threshold=1e6)

Estimate a numerical rank profile from BigFloat singular values. A stable
profile is returned only when the singular values are clearly separated around
the tolerance boundary; otherwise an `UnstableRankProfile` is returned.
"""
function detect_rank_profile(A;
                             precision_bits::Integer=DEFAULT_APPROX_PRECISION_BITS,
                             absolute_tolerance=nothing,
                             relative_tolerance=DEFAULT_RANK_RELATIVE_TOLERANCE,
                             gap_threshold=DEFAULT_RANK_GAP_THRESHOLD,)
    precision_bits > 0 || throw(ArgumentError("precision_bits must be positive"))

    return setprecision(BigFloat, precision_bits) do
        matrix = _bigfloat_matrix(A; precision_bits, name=:A)
        singular_values = _singular_values_bigfloat(matrix; precision_bits)
        scale = isempty(singular_values) ? BigFloat(1) :
                max(BigFloat(1), singular_values[1])
        relative_tol = _bigfloat_scalar(relative_tolerance; name=:relative_tolerance)
        relative_tol > 0 || throw(ArgumentError("relative_tolerance must be positive"))
        abs_tol = isnothing(absolute_tolerance) ? BigFloat(0) :
                  _bigfloat_scalar(absolute_tolerance; name=:absolute_tolerance)
        abs_tol >= 0 || throw(ArgumentError("absolute_tolerance must be nonnegative"))
        tolerance = max(abs_tol, relative_tol * scale)
        gap_limit = _bigfloat_scalar(gap_threshold; name=:gap_threshold)
        gap_limit > 1 || throw(ArgumentError("gap_threshold must be greater than 1"))

        candidate_rank = count(value -> value > tolerance, singular_values)
        gap = _rank_boundary_gap(singular_values, candidate_rank, tolerance)

        if isempty(singular_values)
            return RankProfile(0, Int[], Int[], Int[], tolerance, singular_values,
                               BigFloat(Inf), :svd_rrqr)
        elseif candidate_rank == 0
            if singular_values[1] <= tolerance / gap_limit
                return RankProfile(0, Int[], Int[], collect(1:size(matrix, 2)), tolerance,
                                   singular_values, gap, :svd_rrqr)
            end
            return UnstableRankProfile("all singular values are near the tolerance boundary",
                                       tolerance, singular_values, gap, candidate_rank,
                                       :svd_rrqr)
        elseif candidate_rank == length(singular_values)
            margin = singular_values[end] / tolerance
            if margin >= gap_limit
                pivots = _rrqr_profile(matrix, candidate_rank; tolerance)
                return RankProfile(candidate_rank, pivots.cols, pivots.rows,
                                   pivots.permutation, tolerance, singular_values,
                                   BigFloat(Inf), :svd_rrqr)
            end
            return UnstableRankProfile("smallest singular value is too close to the tolerance boundary",
                                       tolerance, singular_values, margin, candidate_rank,
                                       :svd_rrqr)
        elseif gap >= gap_limit
            pivots = _rrqr_profile(matrix, candidate_rank; tolerance)
            return RankProfile(candidate_rank, pivots.cols, pivots.rows, pivots.permutation,
                               tolerance, singular_values, gap, :svd_rrqr)
        end

        return UnstableRankProfile("singular-value gap is not large enough", tolerance,
                                   singular_values, gap, candidate_rank, :svd_rrqr)
    end
end

function _rank_boundary_gap(singular_values::Vector{BigFloat}, rank::Integer,
                            tolerance::BigFloat)
    isempty(singular_values) && return BigFloat(Inf)
    rank <= 0 &&
        return singular_values[1] == 0 ? BigFloat(Inf) : tolerance / singular_values[1]
    rank >= length(singular_values) &&
        return singular_values[end] == 0 ? BigFloat(Inf) : singular_values[end] / tolerance
    denominator = max(singular_values[rank + 1], BigFloat(0))
    denominator == 0 && return BigFloat(Inf)
    return singular_values[rank] / denominator
end

function _rrqr_profile(matrix::Matrix{BigFloat}, rank::Integer; tolerance::BigFloat)
    col_permutation = _pivoted_gram_schmidt_permutation(matrix; tolerance)
    row_permutation = _pivoted_gram_schmidt_permutation(transpose(matrix); tolerance)
    r = min(Int(rank), length(col_permutation), length(row_permutation))

    return (;
            cols=sort(col_permutation[1:r]),
            rows=sort(row_permutation[1:r]),
            permutation=col_permutation,)
end

function _pivoted_gram_schmidt_permutation(A; tolerance::BigFloat)
    matrix = Matrix{BigFloat}(A)
    rows, cols = size(matrix)
    permutation = collect(1:cols)
    remaining_norms = [_column_norm_squared(matrix, j) for j in 1:cols]
    selected = Vector{BigFloat}[]

    limit = min(rows, cols)
    for k in 1:limit
        pivot_offset = argmax(remaining_norms[k:end])
        pivot = k + pivot_offset - 1
        if pivot != k
            matrix[:, [k, pivot]] = matrix[:, [pivot, k]]
            permutation[[k, pivot]] = permutation[[pivot, k]]
            remaining_norms[[k, pivot]] = remaining_norms[[pivot, k]]
        end

        vector = copy(matrix[:, k])
        for q in selected
            projection = dot(q, vector)
            vector .-= projection .* q
        end

        norm_value = sqrt(max(dot(vector, vector), BigFloat(0)))
        norm_value <= tolerance && continue

        vector ./= norm_value
        push!(selected, vector)

        for j in (k + 1):cols
            projection = dot(vector, matrix[:, j])
            matrix[:, j] .-= projection .* vector
            remaining_norms[j] = _column_norm_squared(matrix, j)
        end
    end

    return permutation
end

function _singular_values_bigfloat(A::Matrix{BigFloat}; precision_bits::Integer)
    rows, cols = size(A)
    isempty(A) && return BigFloat[]

    values = if rows == cols && _is_nearly_symmetric(A)
        abs.(_symmetric_eigenvalues_bigfloat(_symmetrized_matrix(A); precision_bits))
    else
        gram = transpose(A) * A
        eigenvalues = _symmetric_eigenvalues_bigfloat(_symmetrized_matrix(Matrix{BigFloat}(gram));
                                                      precision_bits)
        [sqrt(max(value, BigFloat(0))) for value in eigenvalues]
    end

    sort!(values; rev=true)
    return values
end

function _symmetric_eigenvalues_bigfloat(A::Matrix{BigFloat}; precision_bits::Integer)
    _check_square(A; name=:A)
    n = size(A, 1)
    n == 0 && return BigFloat[]
    n == 1 && return [A[1, 1]]

    matrix = copy(A)
    scale = max(BigFloat(1), _max_abs_entry(matrix))
    tolerance = sqrt(eps(BigFloat)) * scale * BigFloat(max(1, n))
    max_sweeps = 64 * n * n

    for _ in 1:max_sweeps
        p, q, offdiag = _largest_offdiag_entry(matrix)
        offdiag <= tolerance && break

        app = matrix[p, p]
        aqq = matrix[q, q]
        apq = matrix[p, q]
        apq == 0 && continue

        tau = (aqq - app) / (2 * apq)
        tau_sign = tau >= 0 ? BigFloat(1) : BigFloat(-1)
        t = tau_sign / (abs(tau) + sqrt(BigFloat(1) + tau * tau))
        c = inv(sqrt(BigFloat(1) + t * t))
        s = t * c

        for k in 1:n
            k == p || k == q || begin
                    akp = matrix[k, p]
                    akq = matrix[k, q]
                    matrix[k, p] = c * akp - s * akq
                    matrix[p, k] = matrix[k, p]
                    matrix[k, q] = s * akp + c * akq
                    matrix[q, k] = matrix[k, q]
                end
        end

        matrix[p, p] = c * c * app - 2 * s * c * apq + s * s * aqq
        matrix[q, q] = s * s * app + 2 * s * c * apq + c * c * aqq
        matrix[p, q] = BigFloat(0)
        matrix[q, p] = BigFloat(0)
    end

    values = [matrix[i, i] for i in 1:n]
    sort!(values)
    return values
end

function _largest_offdiag_entry(matrix::Matrix{BigFloat})
    n = size(matrix, 1)
    best_i = 1
    best_j = 2
    best_value = abs(matrix[1, 2])

    for j in 2:n, i in 1:(j - 1)
        value = abs(matrix[i, j])
        if value > best_value
            best_i = i
            best_j = j
            best_value = value
        end
    end

    return best_i, best_j, best_value
end

function _symmetrized_matrix(A::Matrix{BigFloat})
    _check_square(A; name=:A)
    matrix = similar(A)
    for i in axes(A, 1), j in axes(A, 2)
        matrix[i, j] = (A[i, j] + A[j, i]) / 2
    end
    return matrix
end

function _is_nearly_symmetric(A::Matrix{BigFloat})
    size(A, 1) == size(A, 2) || return false
    return _symmetry_residual(A) <=
           sqrt(eps(BigFloat)) * max(BigFloat(1), _max_abs_entry(A))
end

function _symmetry_residual(A::AbstractMatrix{BigFloat})
    _check_square(A; name=:A)
    residual = BigFloat(0)
    for j in axes(A, 2), i in (j + 1):size(A, 1)
        residual = max(residual, abs(A[i, j] - A[j, i]))
    end
    return residual
end

function _max_abs_difference(A::AbstractMatrix{BigFloat}, B::AbstractMatrix{BigFloat})
    size(A) == size(B) || throw(DimensionMismatch("matrix sizes do not match"))
    residual = BigFloat(0)
    for index in eachindex(A, B)
        residual = max(residual, abs(A[index] - B[index]))
    end
    return residual
end

function _frobenius_norm(A::AbstractMatrix{BigFloat})
    total = BigFloat(0)
    for value in A
        total += value * value
    end
    return sqrt(total)
end

function _max_abs_entry(A::AbstractMatrix{BigFloat})
    value = BigFloat(0)
    for entry in A
        value = max(value, abs(entry))
    end
    return value
end

function _column_norm_squared(A::Matrix{BigFloat}, column::Integer)
    total = BigFloat(0)
    for i in axes(A, 1)
        total += A[i, column] * A[i, column]
    end
    return total
end

function _bigfloat_matrix(entries; precision_bits::Integer, name::Symbol)
    entries isa AbstractMatrix || throw(ArgumentError("$name must be a matrix"))
    return [_bigfloat_scalar(entry; name) for entry in entries]
end

function _bigfloat_vector(entries; precision_bits::Integer, name::Symbol)
    entries isa AbstractVector || throw(ArgumentError("$name must be a vector"))
    return [_bigfloat_scalar(entry; name) for entry in entries]
end

function _bigfloat_scalar(value::BigFloat; name::Symbol)
    return BigFloat(value)
end

function _bigfloat_scalar(value::Integer; name::Symbol)
    return BigFloat(value)
end

function _bigfloat_scalar(value::Rational; name::Symbol)
    return _bigfloat_rational(value)
end

function _bigfloat_scalar(value::AbstractFloat; name::Symbol)
    return BigFloat(value)
end

function _bigfloat_scalar(value::AbstractString; name::Symbol)
    text = strip(String(value))
    isempty(text) && throw(ArgumentError("$name must not be an empty numeric string"))

    rational_match = match(r"^([+-]?\d+)(?:/(\d+))?$", text)
    if !isnothing(rational_match)
        numerator_value = parse(BigInt, rational_match.captures[1])
        denominator_value = isnothing(rational_match.captures[2]) ? BigInt(1) :
                            parse(BigInt, rational_match.captures[2])
        denominator_value != 0 || throw(ArgumentError("$name has zero denominator"))
        return BigFloat(numerator_value) / BigFloat(denominator_value)
    end

    return try
        parse(BigFloat, text)
    catch err
        throw(ArgumentError("$name is not a valid BigFloat string `$value`: $(sprint(showerror, err))"))
    end
end

function _bigfloat_scalar(value; name::Symbol)
    throw(ArgumentError("$name contains nonnumeric entry $value"))
end

function _bigfloat_rational(value::Rational)
    return BigFloat(numerator(value)) / BigFloat(denominator(value))
end
