const EXACTIFY_DIRECT_STRATEGY = :direct
const EXACTIFY_SOS_ROUND_PROJECT_STRATEGY = :sos_round_project

const EXACTIFY_EXPERIMENTAL_STRATEGIES = Set([:perturb_compensate,
                                              :clustered_low_rank_field,
                                              :degenerate_incidence,
                                              :nc_round_project_lift,
                                              :quantum_bounds_bridge])

"""
    ExactificationAttempt

One strategy attempt in an exactification run. A strategy may produce an
accepted certificate, a normal certification failure, or a deliberately
unsupported result when the corresponding research algorithm is not yet a
trusted implementation.
"""
struct ExactificationAttempt
    strategy::Symbol
    status::Symbol
    stage::Symbol
    message::String
    diagnostics::Dict{Symbol, Any}
end

"""
    ExactificationReport

Auditable trace for `certify_auto_sos` and future exactification pipelines.
The report is diagnostic metadata only; strict replay still accepts only the
resulting exact certificate.
"""
struct ExactificationReport
    family::Symbol
    attempts::Vector{ExactificationAttempt}
    selected_strategy::Union{Nothing, Symbol}
end

function exactification_report_json(report::ExactificationReport)
    return (;
            family=String(report.family),
            selected_strategy=isnothing(report.selected_strategy) ? nothing :
                              String(report.selected_strategy),
            attempts=[exactification_attempt_json(attempt)
                      for attempt in report.attempts],)
end

function exactification_attempt_json(attempt::ExactificationAttempt)
    return (;
            strategy=String(attempt.strategy),
            status=String(attempt.status),
            stage=String(attempt.stage),
            message=attempt.message,
            diagnostics=_certification_diagnostics_json(attempt.diagnostics),)
end

function exactification_hard_gates()
    return [(;
             id=:strategy_boundary,
             title="Strategy boundary",
             gate="Every exactification algorithm must be a named strategy with deterministic inputs, diagnostics, and a handoff into strict replay."),
            (;
             id=:strict_replay_boundary,
             title="Verifier boundary",
             gate="No strategy output is accepted unless an existing exact certificate verifier accepts it without solver logs or numerical tolerances."),
            (;
             id=:round_project_sos,
             title="Parrilo-Peyrl SOS path",
             gate="Floating Gram candidates must be reconstructed, projected onto exact coefficient equations, and then PSD-verified over QQ."),
            (;
             id=:perturb_compensate,
             title="Perturbation/compensation",
             gate="Perturbed SOS claims must include an exact compensation identity; unsupported cases must fail loudly."),
            (;
             id=:number_field,
             title="Number fields",
             gate="Algebraic certificates must expose the field, embeddings, root isolation, and exact sign obligations."),
            (;
             id=:nc_quantum,
             title="Noncommutative/quantum",
             gate="Word, involution, trace-cyclic, and projection identities must be replayed symbolically before any PSD block is trusted."),
            (;
             id=:external_adapters,
             title="External adapters",
             gate="Adapters may translate RealCertify/NCTSSOS/ClusteredLowRank/quantum artifacts, but never extend the trusted verifier by importing their logs."),
            (;
             id=:paper_artifacts,
             title="Reviewer artifact",
             gate="A paper artifact must contain data-only certificates, strict replay output, hashes, and a replay command that works from a fresh checkout.")]
end

"""
    certify_auto_sos(problem, gram_matrix; kwargs...)

Try exact SOS certification strategies in order. The first production strategy
is `:sos_round_project`, which reconstructs a rational Gram candidate, projects
it onto the exact coefficient-matching affine space, and then calls the strict
SOS Gram certifier.
"""
function certify_auto_sos(problem::SOSGramProblem,
                          gram_matrix;
                          strategies=(:direct, :sos_round_project),
                          tolerance=nothing,
                          max_denominator::Integer=DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR)
    attempts = ExactificationAttempt[]

    for raw_strategy in strategies
        strategy = Symbol(raw_strategy)
        if strategy === EXACTIFY_DIRECT_STRATEGY
            result, attempt = _exactify_direct_sos_attempt(problem, gram_matrix)
        elseif strategy === EXACTIFY_SOS_ROUND_PROJECT_STRATEGY
            result, attempt = _exactify_sos_round_project_attempt(problem,
                                                                  gram_matrix;
                                                                  tolerance,
                                                                  max_denominator)
        elseif strategy in EXACTIFY_EXPERIMENTAL_STRATEGIES
            result = nothing
            attempt = _exactify_unsupported_attempt(strategy)
        else
            result = nothing
            attempt = ExactificationAttempt(strategy,
                                            :failed,
                                            :options,
                                            "unknown exactification strategy `$strategy`",
                                            Dict{Symbol, Any}())
        end
        push!(attempts, attempt)
        if result isa CertifiedResult
            report = ExactificationReport(:sos, attempts, strategy)
            artifacts = Dict{Symbol, Any}(:exactification_report => report)
            return CertifiedResult(certificate(result);
                                   status=result.status,
                                   artifacts)
        end
    end

    report = ExactificationReport(:sos, attempts, nothing)
    failure = GenericCertificationFailure(:no_exactification_strategy_verified,
                                          "no SOS exactification strategy produced an accepted certificate",
                                          :exactify,
                                          Dict{Symbol, Any}(:exactification_report => exactification_report_json(report)))
    return FailureResult(failure;
                         artifacts=Dict{Symbol, Any}(:exactification_report => report))
end

function _exactify_direct_sos_attempt(problem::SOSGramProblem, gram_matrix)
    result = try
        Q = _exactify_exact_sos_candidate_matrix(problem, gram_matrix)
        certify_sos(problem, Q)
    catch err
        FailureResult(GenericCertificationFailure(:direct_exactification_failed,
                                                  sprint(showerror, err),
                                                  :exactify,
                                                  Dict{Symbol, Any}(:exception_type => string(typeof(err)))))
    end

    if result isa CertifiedResult
        return result,
               ExactificationAttempt(:direct,
                                     :certified,
                                     :verify,
                                     "direct exact SOS Gram certificate accepted",
                                     Dict{Symbol, Any}())
    end

    return result,
           ExactificationAttempt(:direct,
                                 :failed,
                                 result.failure.stage,
                                 result.failure.message,
                                 _with_failure_reason(result.failure))
end

function _exactify_sos_round_project_attempt(problem::SOSGramProblem,
                                             gram_matrix;
                                             tolerance,
                                             max_denominator::Integer)
    projected = try
        round_project_sos_gram(problem, gram_matrix; tolerance, max_denominator)
    catch err
        result = FailureResult(GenericCertificationFailure(:sos_round_project_failed,
                                                           sprint(showerror, err),
                                                           :exactify,
                                                           Dict{Symbol, Any}(:exception_type => string(typeof(err)))))
        return result,
               ExactificationAttempt(:sos_round_project,
                                     :failed,
                                     :exactify,
                                     result.failure.message,
                                     _with_failure_reason(result.failure))
    end

    result = certify_sos(problem, projected.gram_matrix)
    if result isa CertifiedResult
        result = CertifiedResult(certificate(result);
                                 artifacts=Dict{Symbol, Any}(:projection => projected,
                                                             :source => "sos_round_project_exactification"))
        return result,
               ExactificationAttempt(:sos_round_project,
                                     :certified,
                                     :verify,
                                     "round-project SOS Gram certificate accepted",
                                     Dict{Symbol, Any}(:coefficient_equations => projected.coefficient_equations,
                                                       :pivot_variables => projected.pivot_variables,
                                                       :free_variables => projected.free_variables,
                                                       :adjusted_entries => projected.adjusted_entries))
    end

    return result,
           ExactificationAttempt(:sos_round_project,
                                 :failed,
                                 result.failure.stage,
                                 result.failure.message,
                                 merge(_with_failure_reason(result.failure),
                                       Dict{Symbol, Any}(:coefficient_equations => projected.coefficient_equations,
                                                         :pivot_variables => projected.pivot_variables,
                                                         :free_variables => projected.free_variables,
                                                         :adjusted_entries => projected.adjusted_entries)))
end

function _exactify_unsupported_attempt(strategy::Symbol)
    return ExactificationAttempt(strategy,
                                 :unsupported,
                                 :hard_gate,
                                 "strategy `$strategy` is registered behind a hard gate but is not yet a trusted implementation",
                                 Dict{Symbol, Any}(:hard_gate => true))
end

function _with_failure_reason(failure::CertificationFailure)
    diagnostics = copy(failure.diagnostics)
    diagnostics[:reason] = String(failure.reason)
    diagnostics[:failure_type] = String(failure_type(failure))
    return diagnostics
end

"""
    round_project_sos_gram(problem, gram_matrix; tolerance, max_denominator)

Reconstruct a rational Gram candidate and project it onto the exact affine
coefficient-matching equations for `p == v'Qv`. The projection preserves free
variables from the reconstructed candidate and solves pivot entries exactly.
PSD is intentionally not claimed here; callers must pass the result through
`certify_sos` or `verify_sos`.
"""
function round_project_sos_gram(problem::SOSGramProblem,
                                gram_matrix;
                                tolerance=nothing,
                                max_denominator::Integer=DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR)
    max_denominator > 0 ||
        throw(ArgumentError("max_denominator must be positive"))
    candidate = _exactify_candidate_sos_matrix(problem, gram_matrix;
                                               tolerance,
                                               max_denominator)
    A, b, pairs, row_exponents = _sos_coefficient_linear_system(problem)
    seed = Rational{BigInt}[candidate[i, j] for (i, j) in pairs]
    solution, pivot_columns, free_columns = _solve_affine_system_with_seed(A, b,
                                                                           seed)
    projected_entries = copy(candidate)
    adjusted_entries = 0
    for (column, (i, j)) in enumerate(pairs)
        old = projected_entries[i, j]
        new = solution[column]
        old == new || (adjusted_entries += (i == j ? 1 : 2))
        projected_entries[i, j] = new
        projected_entries[j, i] = new
    end
    Q = SymmetricRationalMatrix(projected_entries; name=:projected_sos_gram)
    matches = coefficient_matching_metadata(problem, Q)
    _sos_coefficient_matches_all_exact(matches) ||
        throw(ArgumentError("round-project result does not satisfy exact SOS coefficient equations"))

    return (;
            gram_matrix=Q,
            coefficient_equations=size(A, 1),
            gram_variables=length(pairs),
            pivot_variables=length(pivot_columns),
            free_variables=length(free_columns),
            adjusted_entries,
            row_exponents=[collect(exponent) for exponent in row_exponents],)
end

function _exactify_exact_sos_candidate_matrix(problem::SOSGramProblem, gram_matrix)
    if gram_matrix isa SymmetricRationalMatrix
        return gram_matrix
    elseif gram_matrix isa AbstractMatrix
        return SymmetricRationalMatrix(gram_matrix; name=:gram_matrix)
    end

    n = length(problem.basis)
    return SymmetricRationalMatrix(_exactify_parse_exact_matrix(gram_matrix, n);
                                   name=:gram_matrix)
end

function _exactify_candidate_sos_matrix(problem::SOSGramProblem,
                                        gram_matrix;
                                        tolerance,
                                        max_denominator::Integer)
    if gram_matrix isa SymmetricRationalMatrix
        return rational_matrix(gram_matrix)
    elseif gram_matrix isa AbstractMatrix
        return _exactify_reconstruct_matrix(gram_matrix,
                                            length(problem.basis);
                                            tolerance,
                                            max_denominator)
    end
    return _exactify_reconstruct_matrix(gram_matrix,
                                        length(problem.basis);
                                        tolerance,
                                        max_denominator)
end

function _exactify_parse_exact_matrix(value, expected_size::Integer)
    matrix = Matrix{Rational{BigInt}}(undef, expected_size, expected_size)
    _exactify_matrix_shape(value, expected_size)
    for i in 1:expected_size, j in 1:expected_size
        matrix[i, j] = _exactify_exact_scalar(_exactify_matrix_entry(value, i, j),
                                              "gram_matrix[$i,$j]")
    end
    return matrix
end

function _exactify_reconstruct_matrix(value,
                                      expected_size::Integer;
                                      tolerance,
                                      max_denominator::Integer)
    matrix = Matrix{Rational{BigInt}}(undef, expected_size, expected_size)
    _exactify_matrix_shape(value, expected_size)
    for i in 1:expected_size
        raw_diagonal = _exactify_matrix_entry(value, i, i)
        matrix[i, i] = _exactify_reconstruct_scalar(raw_diagonal;
                                                    tolerance,
                                                    max_denominator,
                                                    path="gram_matrix[$i,$i]")
        for j in (i + 1):expected_size
            left = _exactify_matrix_entry(value, i, j)
            right = _exactify_matrix_entry(value, j, i)
            entry = _exactify_reconstruct_symmetric_pair(left, right;
                                                         tolerance,
                                                         max_denominator,
                                                         path="gram_matrix[$i,$j]")
            matrix[i, j] = entry
            matrix[j, i] = entry
        end
    end
    return matrix
end

function _exactify_matrix_shape(value, expected_size::Integer)
    if value isa AbstractMatrix
        size(value) == (expected_size, expected_size) ||
            throw(DimensionMismatch("Gram matrix has size $(size(value)); expected $((expected_size, expected_size))"))
        return true
    elseif value isa AbstractVector
        length(value) == expected_size ||
            throw(ArgumentError("Gram matrix has $(length(value)) rows; expected $expected_size"))
        for (i, row) in enumerate(value)
            row isa AbstractVector ||
                throw(ArgumentError("Gram matrix row $i must be a vector"))
            length(row) == expected_size ||
                throw(ArgumentError("Gram matrix row $i has $(length(row)) entries; expected $expected_size"))
        end
        return true
    end
    throw(ArgumentError("Gram matrix candidate must be a matrix or nested vector"))
end

function _exactify_matrix_entry(value::AbstractMatrix, i::Integer, j::Integer)
    return value[i, j]
end

function _exactify_matrix_entry(value::AbstractVector, i::Integer, j::Integer)
    return value[i][j]
end

function _exactify_exact_scalar(value, path::AbstractString)
    value isa AbstractString && return _parse_rational_string(value, path)
    value isa Integer && return Rational{BigInt}(BigInt(value), BigInt(1))
    value isa Rational && return Rational{BigInt}(BigInt(numerator(value)),
                                                  BigInt(denominator(value)))
    if value isa Real && value == trunc(value)
        return Rational{BigInt}(BigInt(value), BigInt(1))
    end
    throw(ArgumentError("$path is not exact rational data; use :sos_round_project with an explicit tolerance for floating candidates"))
end

function _exactify_reconstruct_scalar(value;
                                      tolerance,
                                      max_denominator::Integer,
                                      path::AbstractString)
    if value isa AbstractString || value isa Integer || value isa Rational ||
       (value isa Real && !(value isa AbstractFloat))
        return _exactify_exact_scalar(value, path)
    end
    isnothing(tolerance) &&
        throw(ArgumentError("$path is floating-point data; pass an explicit tolerance"))
    return reconstruct_rational_value(value;
                                      tolerance,
                                      max_denominator,
                                      path)
end

function _exactify_reconstruct_symmetric_pair(left,
                                              right;
                                              tolerance,
                                              max_denominator::Integer,
                                              path::AbstractString)
    if left isa AbstractFloat || right isa AbstractFloat
        isnothing(tolerance) &&
            throw(ArgumentError("$path is floating-point data; pass an explicit tolerance"))
        # CERTSDP_NUMERIC_DIAGNOSTIC_ONLY: tolerance checks are candidate filtering, never verifier acceptance
        l = BigFloat(left)
        r = BigFloat(right)
        abs(l - r) <= BigFloat(tolerance) ||
            throw(ArgumentError("$path is not symmetric within tolerance $tolerance"))
        return reconstruct_rational_value((l + r) / 2;
                                          tolerance,
                                          max_denominator,
                                          path)
    end
    q_left = _exactify_reconstruct_scalar(left; tolerance, max_denominator, path)
    q_right = _exactify_reconstruct_scalar(right; tolerance, max_denominator, path)
    q_left == q_right ||
        throw(ArgumentError("$path is not exactly symmetric after reconstruction"))
    return q_left
end

function _sos_coefficient_linear_system(problem::SOSGramProblem)
    n = length(problem.basis)
    pairs = Tuple{Int, Int}[(i, j) for j in 1:n for i in 1:j]
    target_terms = _sos_terms_dict(problem.polynomial)
    exponents = Set{Tuple{Vararg{Int}}}(keys(target_terms))
    pair_exponents = Tuple{Vararg{Int}}[]
    for (i, j) in pairs
        exponent = tuple((problem.basis[i][k] + problem.basis[j][k]
                          for k in eachindex(problem.variables))...)
        push!(pair_exponents, exponent)
        push!(exponents, exponent)
    end
    rows = sort(collect(exponents); lt=_sos_exponent_order_lt)
    row_index = Dict(exponent => i for (i, exponent) in enumerate(rows))
    A = zeros(Rational{BigInt}, length(rows), length(pairs))
    b = Rational{BigInt}[get(target_terms, exponent, 0 // 1) for exponent in rows]
    for (column, (i, j)) in enumerate(pairs)
        row = row_index[pair_exponents[column]]
        A[row, column] += (i == j ? 1 // 1 : 2 // 1)
    end
    return A, b, pairs, rows
end

function _solve_affine_system_with_seed(A::Matrix{Rational{BigInt}},
                                        b::Vector{Rational{BigInt}},
                                        seed::Vector{Rational{BigInt}})
    rows, cols = size(A)
    length(b) == rows ||
        throw(DimensionMismatch("right-hand side length $(length(b)) does not match row count $rows"))
    length(seed) == cols ||
        throw(DimensionMismatch("seed length $(length(seed)) does not match column count $cols"))

    augmented = Matrix{Rational{BigInt}}(undef, rows, cols + 1)
    augmented[:, 1:cols] .= A
    augmented[:, cols + 1] .= b

    pivot_columns = Int[]
    pivot_row = 1
    for column in 1:cols
        found = 0
        for row in pivot_row:rows
            if !iszero(augmented[row, column])
                found = row
                break
            end
        end
        found == 0 && continue
        if found != pivot_row
            augmented[pivot_row, :], augmented[found, :] = copy(augmented[found, :]),
                                                           copy(augmented[pivot_row, :])
        end
        pivot = augmented[pivot_row, column]
        augmented[pivot_row, :] ./= pivot
        for row in 1:rows
            row == pivot_row && continue
            factor = augmented[row, column]
            iszero(factor) && continue
            augmented[row, :] .-= factor .* augmented[pivot_row, :]
        end
        push!(pivot_columns, column)
        pivot_row += 1
        pivot_row > rows && break
    end

    for row in 1:rows
        all(iszero(augmented[row, column]) for column in 1:cols) &&
            !iszero(augmented[row, cols + 1]) &&
            throw(ArgumentError("coefficient-matching system is inconsistent"))
    end

    pivot_set = Set(pivot_columns)
    free_columns = [column for column in 1:cols if !(column in pivot_set)]
    solution = copy(seed)
    for (row, column) in enumerate(pivot_columns)
        value = augmented[row, cols + 1]
        for free in free_columns
            value -= augmented[row, free] * solution[free]
        end
        solution[column] = value
    end

    A * solution == b ||
        throw(ArgumentError("affine projection failed exact residual check"))
    return solution, pivot_columns, free_columns
end
