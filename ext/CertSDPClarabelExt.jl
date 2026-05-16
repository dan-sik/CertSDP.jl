module CertSDPClarabelExt

using CertSDP
using Clarabel: Clarabel
using SparseArrays: sparse, spzeros

const CLARABEL_ACCEPTED_STATUSES = Set(["SOLVED", "ALMOST_SOLVED"])

struct ClarabelNumericalBackend <: CertSDP.NumericalOracleBackend end

CertSDP._optional_numerical_backend(::Val{:clarabel}) = ClarabelNumericalBackend()

CertSDP._backend_solver_symbol(::ClarabelNumericalBackend) = :clarabel

function CertSDP._solve_approximately_with_backend(P::CertSDP.LMIProblem,
                                                   ::ClarabelNumericalBackend,
                                                   objective;
                                                   precision_bits::Integer,
                                                   retry_spec,
                                                   attempt_index::Integer,
                                                   rank_kwargs...)
    n = CertSDP.num_variables(P)
    m = CertSDP.matrix_size(P)
    length(objective.vector) == n ||
        return CertSDP.CertificationFailure(:numerical_solver_failed,
                                            "Clarabel objective has length $(length(objective.vector)); expected $n",
                                            :numerical_oracle,
                                            Dict{Symbol, Any}(:solver => "clarabel"))

    Pq = spzeros(Float64, n, n)
    q = collect(Float64, objective.vector)
    A, b = _clarabel_lmi_conic_data(P)
    cones = Clarabel.SupportedCone[Clarabel.PSDTriangleConeT(m)]
    settings = Clarabel.Settings(; verbose=false,
                                 max_iter=retry_spec.max_iter,
                                 time_limit=retry_spec.time_limit,
                                 tol_feas=retry_spec.tol_feas,
                                 tol_gap_abs=retry_spec.tol_gap_abs,
                                 tol_gap_rel=retry_spec.tol_gap_rel,
                                 chordal_decomposition_enable=false)

    solver = try
        Clarabel.Solver(Pq, q, A, b, cones, settings)
    catch err
        return CertSDP._numerical_oracle_exception(:clarabel_setup_failed, err)
    end

    try
        Clarabel.solve!(solver)
    catch err
        return CertSDP._numerical_oracle_exception(:clarabel_solve_failed, err)
    end

    status_text = string(solver.solution.status)
    status_symbol = Symbol(lowercase(status_text))
    status_text in CLARABEL_ACCEPTED_STATUSES ||
        return CertSDP.CertificationFailure(:numerical_solver_status,
                                            "Clarabel returned status `$status_text`",
                                            :numerical_oracle,
                                            Dict{Symbol, Any}(:solver => "clarabel",
                                                              :solver_status => status_text,
                                                              :objective_kind => String(objective.kind),
                                                              :objective => string.(objective.vector),
                                                              :retry_index => retry_spec.retry_index))

    return try
        CertSDP.ApproxSolution(P,
                               string.(solver.solution.x);
                               precision_bits,
                               solver_name=:clarabel,
                               solver_status=status_symbol,
                               objective_value=solver.solution.obj_val,
                               objective_kind=objective.kind,
                               objective_vector=string.(objective.vector),
                               attempt_index,
                               retry_index=retry_spec.retry_index,
                               solver_primal_residual=solver.solution.r_prim,
                               solver_dual_residual=solver.solution.r_dual,
                               oracle_metadata=(objective=(kind=objective.kind,
                                                           vector=string.(objective.vector),
                                                           trial=objective.trial,
                                                           direction=objective.direction,
                                                           seed=objective.seed),
                                                retry=retry_spec),
                               rank_kwargs...)
    catch err
        CertSDP._numerical_oracle_exception(:clarabel_solution_invalid, err)
    end
end

function _clarabel_lmi_conic_data(P::CertSDP.LMIProblem)
    m = CertSDP.matrix_size(P)
    n = CertSDP.num_variables(P)
    cone_dim = div(m * (m + 1), 2)
    row_indices = Int[]
    col_indices = Int[]
    values = Float64[]

    for (j, matrix) in enumerate(P.A)
        packed = _clarabel_svec(matrix)
        for i in 1:cone_dim
            iszero(packed[i]) && continue
            push!(row_indices, i)
            push!(col_indices, j)
            push!(values, -packed[i])
        end
    end

    return sparse(row_indices, col_indices, values, cone_dim, n),
           _clarabel_svec(P.A0)
end

function _clarabel_svec(M::CertSDP.SymmetricRationalMatrix)
    entries = CertSDP.rational_matrix(M)
    m = size(entries, 1)
    packed = Vector{Float64}(undef, div(m * (m + 1), 2))
    scale = sqrt(2.0)
    index = 1
    for col in 1:m, row in 1:col
        value = Float64(entries[row, col])
        packed[index] = row == col ? value : scale * value
        index += 1
    end
    return packed
end

end
