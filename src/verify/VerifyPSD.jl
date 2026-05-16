const DEFAULT_MAX_PSD_PRINCIPAL_MINOR_SIZE = 8
const SCHUR_ZERO_PSD_METHOD = "schur_zero"
const LDL_PSD_METHOD = "ldl"
const PIVOTED_LDL_PSD_METHOD = "pivoted_ldl"
const BLOCKWISE_PSD_METHOD = "blockwise"

"""
    PrincipalMinorProof(indices, determinant)

One exact principal-minor determinant used by PSD proof objects. The verifier
always recomputes these determinants before accepting a certificate.
"""
struct PrincipalMinorProof{T}
    indices::Vector{Int}
    determinant::T
end

function PrincipalMinorProof(indices::AbstractVector{<:Integer}, determinant::Rational)
    return PrincipalMinorProof{Rational{BigInt}}(Int.(collect(indices)),
                                                 _to_big_rational(determinant;
                                                                  name=:determinant))
end

function PrincipalMinorProof(indices::Vector{Int}, determinant::T) where {T<:Rational}
    return PrincipalMinorProof{Rational{BigInt}}(indices,
                                                 _to_big_rational(determinant;
                                                                  name=:determinant))
end

function PrincipalMinorProof(indices::AbstractVector{<:Integer}, determinant::Integer)
    return PrincipalMinorProof{Rational{BigInt}}(Int.(collect(indices)),
                                                 _to_big_rational(determinant;
                                                                  name=:determinant))
end

function PrincipalMinorProof(indices::Vector{Int}, determinant::T) where {T<:Integer}
    return PrincipalMinorProof{Rational{BigInt}}(indices,
                                                 _to_big_rational(determinant;
                                                                  name=:determinant))
end

function PrincipalMinorProof(indices::AbstractVector{<:Integer},
                             determinant::AlgebraicElement)
    return PrincipalMinorProof{AlgebraicElement}(Int.(collect(indices)), determinant)
end

function PrincipalMinorProof(indices::Vector{Int}, determinant::AlgebraicElement)
    return PrincipalMinorProof{AlgebraicElement}(indices, determinant)
end

"""
    SchurZeroProof(pivot_block, positive_block_minors, schur_complement)

Facial-block PSD proof data. The pivot block is certified positive definite by
leading principal minors, and the Schur complement is required to be exact zero.
"""
struct SchurZeroProof{T}
    pivot_block::Vector{Int}
    positive_block_minors::Vector{PrincipalMinorProof{T}}
    schur_complement::Matrix{T}
end

"""
    LDLPivotProof(index, value, sign)

One exact pivot from symmetric LDL-style elimination. `sign` is `:positive` or
`:zero`; negative pivots are never stored in accepted proofs.
"""
struct LDLPivotProof{T}
    index::Int
    value::T
    sign::Symbol

    function LDLPivotProof{T}(index::Integer, value::T, sign::Symbol) where {T}
        index >= 1 || throw(ArgumentError("LDL pivot index must be positive"))
        sign in (:positive, :zero) ||
            throw(ArgumentError("LDL pivot sign must be :positive or :zero; got $sign"))
        return new{T}(Int(index), value, sign)
    end
end

function LDLPivotProof(index::Integer, value::T, sign::Symbol) where {T}
    return LDLPivotProof{T}(index, value, sign)
end

"""
    LDLProof(pivots)

Exact LDL-style PSD proof. The verifier recomputes the pivots from the
substituted matrix, and zero pivots must have zero remaining row/column.
"""
struct LDLProof{T}
    pivots::Vector{LDLPivotProof{T}}
end

function LDLProof(pivots::AbstractVector{LDLPivotProof{T}}) where {T}
    return LDLProof{T}(LDLPivotProof{T}[pivots...])
end

"""
    PSDProofFailure

Structured localization for an exact PSD proof failure. `block_index` is
`nothing` for one-block checks. `location` is typically `:minor`, `:pivot`, or
`:schur_complement`.
"""
struct PSDProofFailure
    block_index::Union{Nothing, Int}
    method::Symbol
    location::Symbol
    indices::Vector{Int}
    pivot_index::Union{Nothing, Int}
    message::String
end

"""
    PSDVerificationResult

Boolean result plus localized failure detail for exact PSD proof checks.
"""
struct PSDVerificationResult
    accepted::Bool
    method::Symbol
    failure::Union{Nothing, PSDProofFailure}
end

"""
    PSDProofPlan

Exact proof data selected by `choose_psd_proof`. For `method == :blockwise`,
`block_plans` stores one accepted sub-plan per PSD block. For rejected plans,
`failure` localizes the first exact obstruction.
"""
struct PSDProofPlan
    method::Symbol
    status::Symbol
    field::Symbol
    matrix::Any
    principal_minors::Vector
    schur_zero::Any
    ldl::Any
    block_plans::Vector{PSDProofPlan}
    failure::Union{Nothing, PSDProofFailure}

    function PSDProofPlan(method::Symbol, status::Symbol, field::Symbol, matrix,
                          principal_minors::AbstractVector, schur_zero, ldl,
                          block_plans::AbstractVector{PSDProofPlan},
                          failure::Union{Nothing, PSDProofFailure})
        status in (:accepted, :rejected) ||
            throw(ArgumentError("PSD proof plan status must be :accepted or :rejected"))
        return new(method, status, field, matrix, collect(principal_minors), schur_zero,
                   ldl, PSDProofPlan[block_plans...], failure)
    end
end

"""
    verify_psd_rational(A) -> Bool

Verify that a small exact rational symmetric matrix is positive semidefinite by
checking all principal minors. This rational verifier handles matrices over
`QQ`; algebraic numbers are intentionally handled by the algebraic verifier.
"""
function verify_psd_rational(A; max_size::Integer=DEFAULT_MAX_PSD_PRINCIPAL_MINOR_SIZE)
    matrix = _as_psd_rational_matrix(A)
    n = size(matrix, 1)

    n <= max_size ||
        throw(ArgumentError("verify_psd_rational currently supports matrices of size at most $max_size; got $n"))
    return _verify_principal_minors_rational_result(matrix).accepted
end

"""
    verify_psd_algebraic(A) -> Bool

Verify that a small symmetric matrix over one algebraic field `QQ(alpha)` is
positive semidefinite by checking all principal minors with certified algebraic
sign tests. A failed sign certification throws; callers must not treat it as an
accepted proof.
"""
function verify_psd_algebraic(A; max_size::Integer=DEFAULT_MAX_PSD_PRINCIPAL_MINOR_SIZE,
                              max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS)
    matrix = _as_psd_algebraic_matrix(A)
    n = size(matrix, 1)

    n <= max_size ||
        throw(ArgumentError("verify_psd_algebraic currently supports matrices of size at most $max_size; got $n"))
    return _verify_principal_minors_algebraic_result(matrix; max_refinements).accepted
end

"""
    verify_psd_schur_zero(A, pivot_block) -> Bool

Verify a symmetric algebraic matrix by a facial Schur-zero proof. The principal
block `A[pivot_block, pivot_block]` is certified positive definite by
Sylvester's criterion, and the exact Schur complement is required to be the zero
matrix. Failed algebraic sign certification throws instead of accepting.
"""
function verify_psd_schur_zero(A, pivot_block;
                               max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS)
    if _contains_algebraic_entry(A)
        matrix = _as_psd_algebraic_matrix(A)
        return _verify_schur_zero_algebraic_result(matrix, pivot_block;
                                                   max_refinements).accepted
    end

    matrix = _as_psd_rational_matrix(A)
    return _verify_schur_zero_rational_result(matrix, pivot_block).accepted
end

"""
    verify_psd_ldl(A) -> Bool

Verify PSD by exact LDL-style elimination. This is a fallback proof method and
does not use numerical eigenvalues.
"""
function verify_psd_ldl(A;
                        max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS)
    if _contains_algebraic_entry(A)
        matrix = _as_psd_algebraic_matrix(A)
        return _verify_ldl_algebraic_result(matrix; max_refinements).accepted
    end

    matrix = _as_psd_rational_matrix(A)
    return _verify_ldl_rational_result(matrix).accepted
end

"""
    verify_psd_pivoted_ldl(A) -> Bool

Verify PSD by exact symmetric pivoted LDL elimination. Positive pivots are
chosen from the remaining diagonal entries; when no positive pivot remains,
the verifier requires the whole remaining Schur complement to be exactly zero.
"""
function verify_psd_pivoted_ldl(A;
                                max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS)
    if _contains_algebraic_entry(A)
        matrix = _as_psd_algebraic_matrix(A)
        return _verify_pivoted_ldl_algebraic_result(matrix; max_refinements).accepted
    end

    matrix = _as_psd_rational_matrix(A)
    return _verify_pivoted_ldl_rational_result(matrix).accepted
end

"""
    verify_psd_blockwise(blocks) -> Bool

Verify every PSD block independently with exact arithmetic. This helper accepts
the same block collection as `choose_psd_proof`.
"""
function verify_psd_blockwise(blocks;
                              method::Union{Symbol, AbstractString}=:auto,
                              kwargs...)
    plan = choose_psd_proof(blocks, nothing; method=:blockwise,
                            block_method=Symbol(method), kwargs...)
    return plan.status === :accepted
end

"""
    choose_psd_proof(A, rank_profile=nothing; options...) -> PSDProofPlan

Choose and build an exact PSD proof plan for one matrix. The planner may use a
numerical `rank_profile` only to choose a candidate method/pivot block; the
returned proof data is computed exactly from `A`.
"""
function choose_psd_proof(A, rank_profile=nothing;
                          method::Union{Symbol, AbstractString}=:auto,
                          pivot_block=nothing,
                          max_size::Integer=DEFAULT_MAX_PSD_PRINCIPAL_MINOR_SIZE,
                          max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS,
                          block_index::Union{Nothing, Integer}=nothing,
                          block_method::Union{Symbol, AbstractString}=:auto,
                          block_pivot_blocks=nothing)
    method_symbol = Symbol(method)
    if method_symbol === Symbol(BLOCKWISE_PSD_METHOD)
        return _choose_blockwise_psd_proof(A, rank_profile;
                                           block_method=Symbol(block_method),
                                           block_pivot_blocks,
                                           max_size,
                                           max_refinements)
    elseif A isa AbstractVector && !(A isa AbstractMatrix)
        return _choose_blockwise_psd_proof(A, rank_profile;
                                           block_method=method_symbol,
                                           block_pivot_blocks,
                                           max_size,
                                           max_refinements)
    end

    return _choose_single_psd_proof(A, rank_profile;
                                    method=method_symbol,
                                    pivot_block,
                                    max_size,
                                    max_refinements,
                                    block_index=isnothing(block_index) ? nothing :
                                                Int(block_index))
end

function _as_psd_rational_matrix(A::SymmetricRationalMatrix)
    return rational_matrix(A)
end

function _as_psd_rational_matrix(A::AbstractMatrix)
    matrix = _rational_matrix(A; name=:A)
    _check_square(matrix; name=:A)
    _check_symmetric(matrix; name=:A)
    return matrix
end

function _principal_minor_indices(mask::UInt, n::Integer)
    indices = Int[]
    for i in 1:n
        if !iszero(mask & (UInt(1) << (i - 1)))
            push!(indices, i)
        end
    end
    return indices
end

function _validate_pivot_block(pivot_block, matrix_size_value::Integer)
    pivot_block isa AbstractVector ||
        throw(ArgumentError("pivot_block must be a vector of indices"))
    isempty(pivot_block) && throw(ArgumentError("pivot_block must not be empty"))

    pivots = Int[]
    for (i, value) in enumerate(pivot_block)
        value isa Integer || throw(ArgumentError("pivot_block[$i] must be an integer"))
        index = Int(value)
        1 <= index <= matrix_size_value ||
            throw(ArgumentError("pivot_block[$i] is out of range for matrix size $matrix_size_value"))
        push!(pivots, index)
    end

    issorted(pivots) || throw(ArgumentError("pivot_block must be sorted"))
    length(unique(pivots)) == length(pivots) ||
        throw(ArgumentError("pivot_block must be unique"))
    return pivots
end

function _complement_indices(matrix_size_value::Integer, pivots::Vector{Int})
    pivot_set = Set(pivots)
    return [i for i in 1:matrix_size_value if !(i in pivot_set)]
end

function _contains_algebraic_entry(A)
    A isa AbstractMatrix || return false
    for entry in A
        entry isa AlgebraicElement && return true
    end
    return false
end

function _algebraic_element_rational_value(element::AlgebraicElement)
    degree(element.numerator) <= 0 || return nothing
    degree(element.denominator) == 0 || return nothing
    return element.numerator.coeffs[1] / element.denominator.coeffs[1]
end

function _algebraic_matrix_rational_entries(matrix::AbstractMatrix{AlgebraicElement})
    values = Matrix{Rational{BigInt}}(undef, size(matrix)...)
    for index in eachindex(matrix)
        value = _algebraic_element_rational_value(matrix[index])
        isnothing(value) && return nothing
        values[index] = value
    end
    return values
end

_psd_success(method::Symbol) = PSDVerificationResult(true, method, nothing)

function _psd_failure(method::Symbol, location::Symbol, message::AbstractString;
                      block_index::Union{Nothing, Int}=nothing,
                      indices::AbstractVector{<:Integer}=Int[],
                      pivot_index::Union{Nothing, Int}=nothing)
    failure = PSDProofFailure(block_index, method, location, Int.(collect(indices)),
                              pivot_index, String(message))
    return PSDVerificationResult(false, method, failure)
end

function _with_failure_block(result::PSDVerificationResult, block_index::Int)
    result.accepted && return result
    failure = result.failure
    isnothing(failure) && return result
    localized = PSDProofFailure(block_index, failure.method, failure.location,
                                failure.indices, failure.pivot_index, failure.message)
    return PSDVerificationResult(false, result.method, localized)
end

function _failure_message(result::PSDVerificationResult)
    failure = result.failure
    isnothing(failure) && return ""
    block = isnothing(failure.block_index) ? "" : "block $(failure.block_index): "
    index = !isempty(failure.indices) ? " at indices $(failure.indices)" :
            isnothing(failure.pivot_index) ? "" : " at pivot $(failure.pivot_index)"
    return string(block, failure.method, " ", failure.location, index, ": ",
                  failure.message)
end

function _verify_principal_minors_rational_result(matrix::AbstractMatrix{<:Rational};
                                                  block_index::Union{Nothing, Int}=nothing)
    n = size(matrix, 1)
    for mask in 1:((UInt(1) << n) - UInt(1))
        indices = _principal_minor_indices(mask, n)
        minor = _determinant_rational_minor(matrix, indices)
        minor >= 0 ||
            return _psd_failure(Symbol(RATIONAL_PSD_METHOD), :minor,
                                "principal minor determinant is negative: $minor";
                                block_index, indices)
    end
    return _psd_success(Symbol(RATIONAL_PSD_METHOD))
end

function _verify_principal_minors_algebraic_result(matrix::AbstractMatrix{AlgebraicElement};
                                                   max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS,
                                                   block_index::Union{Nothing, Int}=nothing)
    n = size(matrix, 1)
    for mask in 1:((UInt(1) << n) - UInt(1))
        indices = _principal_minor_indices(mask, n)
        minor = _determinant_algebraic_minor(matrix, indices)
        sign = certified_sign(minor; max_refinements)
        sign === :negative &&
            return _psd_failure(Symbol(RATIONAL_PSD_METHOD), :minor,
                                "principal minor determinant is negative: $(algebraic_element_string(minor))";
                                block_index, indices)
    end
    return _psd_success(Symbol(RATIONAL_PSD_METHOD))
end

function _principal_minor_proofs_rational(matrix::SymmetricRationalMatrix)
    entries = rational_matrix(matrix)
    n = size(entries, 1)
    minors = PrincipalMinorProof{Rational{BigInt}}[]
    for mask in 1:((UInt(1) << n) - UInt(1))
        indices = _principal_minor_indices(mask, n)
        push!(minors,
              PrincipalMinorProof(indices,
                                  _determinant_rational_minor(entries,
                                                              indices)))
    end
    return minors
end

function _principal_minor_proofs_algebraic(matrix::AbstractMatrix{AlgebraicElement})
    entries = _as_psd_algebraic_matrix(matrix)
    n = size(entries, 1)
    minors = PrincipalMinorProof{AlgebraicElement}[]
    for mask in 1:((UInt(1) << n) - UInt(1))
        indices = _principal_minor_indices(mask, n)
        determinant = _determinant_algebraic_minor(entries, indices)
        push!(minors, PrincipalMinorProof(indices, determinant))
    end
    return minors
end

function _verify_positive_definite_rational_result(B::AbstractMatrix{<:Rational};
                                                   pivot_indices::Vector{Int},
                                                   block_index::Union{Nothing, Int}=nothing)
    _check_square(B; name=:positive_block)
    for k in 1:size(B, 1)
        minor = _determinant_rational_minor(B, collect(1:k))
        minor > 0 ||
            return _psd_failure(Symbol(SCHUR_ZERO_PSD_METHOD), :positive_block_minor,
                                "leading pivot-block minor is not positive: $minor";
                                block_index, indices=pivot_indices[1:k])
    end
    return _psd_success(Symbol(SCHUR_ZERO_PSD_METHOD))
end

function _verify_positive_definite_algebraic_result(B::AbstractMatrix{AlgebraicElement};
                                                    pivot_indices::Vector{Int},
                                                    max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS,
                                                    block_index::Union{Nothing, Int}=nothing)
    matrix = _as_psd_algebraic_matrix(B)
    rational_entries = _algebraic_matrix_rational_entries(matrix)
    if !isnothing(rational_entries)
        return _verify_positive_definite_rational_result(rational_entries;
                                                         pivot_indices,
                                                         block_index)
    end
    root = _common_algebraic_root(vec(matrix))
    for k in 1:size(matrix, 1)
        minor = _determinant_algebraic_minor(matrix, collect(1:k))
        sign = certified_sign(minor; max_refinements)
        sign === :positive ||
            return _psd_failure(Symbol(SCHUR_ZERO_PSD_METHOD), :positive_block_minor,
                                "leading pivot-block minor is not positive: $(algebraic_element_string(minor))";
                                block_index, indices=pivot_indices[1:k])
    end
    return _psd_success(Symbol(SCHUR_ZERO_PSD_METHOD))
end

function _choose_single_psd_proof(A, rank_profile;
                                  method::Symbol,
                                  pivot_block,
                                  max_size::Integer,
                                  max_refinements::Integer,
                                  block_index::Union{Nothing, Int}=nothing)
    is_algebraic = _contains_algebraic_entry(A)
    matrix = is_algebraic ? _as_psd_algebraic_matrix(A) :
             SymmetricRationalMatrix(_as_psd_rational_matrix(A); name=:psd_proof_matrix)
    n = size(matrix, 1)
    field = is_algebraic ? :QQbar : :QQ

    if method === :auto
        pivots = _planner_pivot_block(rank_profile, pivot_block, n)
        if !isnothing(pivots) && length(pivots) < n
            plan = _try_single_psd_method(matrix, Symbol(SCHUR_ZERO_PSD_METHOD);
                                          pivot_block=pivots,
                                          max_size,
                                          max_refinements,
                                          block_index,
                                          field)
            plan.status === :accepted && return plan
        end

        if n <= max_size
            plan = _try_single_psd_method(matrix, Symbol(RATIONAL_PSD_METHOD);
                                          pivot_block=nothing,
                                          max_size,
                                          max_refinements,
                                          block_index,
                                          field)
            plan.status === :accepted && return plan
        end

        return _try_single_psd_method(matrix, Symbol(PIVOTED_LDL_PSD_METHOD);
                                      pivot_block=nothing,
                                      max_size,
                                      max_refinements,
                                      block_index,
                                      field)
    end

    return _try_single_psd_method(matrix, method;
                                  pivot_block,
                                  max_size,
                                  max_refinements,
                                  block_index,
                                  field)
end

function _try_single_psd_method(matrix, method::Symbol;
                                pivot_block,
                                max_size::Integer,
                                max_refinements::Integer,
                                block_index::Union{Nothing, Int},
                                field::Symbol)
    if method === Symbol(RATIONAL_PSD_METHOD)
        n = size(matrix, 1)
        n <= max_size ||
            throw(ArgumentError("principal-minor PSD proof supports matrices of size at most $max_size; got $n"))
        if field === :QQ
            entries = rational_matrix(matrix)
            result = _verify_principal_minors_rational_result(entries; block_index)
            minors = result.accepted ? _principal_minor_proofs_rational(matrix) : []
        else
            entries = _as_psd_algebraic_matrix(matrix)
            result = _verify_principal_minors_algebraic_result(entries;
                                                               max_refinements,
                                                               block_index)
            minors = result.accepted ? _principal_minor_proofs_algebraic(entries) : []
        end
        return PSDProofPlan(Symbol(RATIONAL_PSD_METHOD),
                            result.accepted ? :accepted : :rejected,
                            field, matrix, minors, nothing, nothing,
                            PSDProofPlan[], result.failure)
    elseif method === Symbol(SCHUR_ZERO_PSD_METHOD)
        isnothing(pivot_block) &&
            throw(ArgumentError("pivot_block is required for a Schur-zero PSD proof"))
        if field === :QQ
            entries = rational_matrix(matrix)
            result = _verify_schur_zero_rational_result(entries, pivot_block;
                                                        block_index)
            schur = result.accepted ?
                    _schur_zero_proof_rational_unchecked(matrix, pivot_block) :
                    nothing
        else
            entries = _as_psd_algebraic_matrix(matrix)
            result = _verify_schur_zero_algebraic_result(entries, pivot_block;
                                                         max_refinements,
                                                         block_index)
            schur = result.accepted ?
                    _schur_zero_proof_algebraic_unchecked(entries, pivot_block) :
                    nothing
        end
        return PSDProofPlan(Symbol(SCHUR_ZERO_PSD_METHOD),
                            result.accepted ? :accepted : :rejected,
                            field, matrix, [], schur, nothing, PSDProofPlan[],
                            result.failure)
    elseif method === Symbol(LDL_PSD_METHOD)
        if field === :QQ
            ldl, result = _ldl_rational_proof(rational_matrix(matrix))
        else
            ldl, result = _ldl_algebraic_proof(_as_psd_algebraic_matrix(matrix);
                                               max_refinements)
        end
        if !result.accepted && !isnothing(block_index)
            result = _with_failure_block(result, block_index)
        end
        return PSDProofPlan(Symbol(LDL_PSD_METHOD),
                            result.accepted ? :accepted : :rejected,
                            field, matrix, [], nothing, ldl, PSDProofPlan[],
                            result.failure)
    elseif method === Symbol(PIVOTED_LDL_PSD_METHOD)
        if field === :QQ
            ldl, result = _pivoted_ldl_rational_proof(rational_matrix(matrix))
        else
            ldl, result = _pivoted_ldl_algebraic_proof(_as_psd_algebraic_matrix(matrix);
                                                       max_refinements)
        end
        if !result.accepted && !isnothing(block_index)
            result = _with_failure_block(result, block_index)
        end
        return PSDProofPlan(Symbol(PIVOTED_LDL_PSD_METHOD),
                            result.accepted ? :accepted : :rejected,
                            field, matrix, [], nothing, ldl, PSDProofPlan[],
                            result.failure)
    end

    throw(ArgumentError("unsupported PSD proof method `$method`"))
end

function _planner_pivot_block(profile, pivot_block, matrix_size_value::Integer)
    pivots = if !isnothing(pivot_block)
        Int[value for value in pivot_block]
    elseif profile isa RankProfile
        Int[value for value in profile.pivot_cols]
    elseif profile isa AbstractDict && haskey(profile, :pivot_block)
        Int[value for value in profile[:pivot_block]]
    elseif profile isa AbstractDict && haskey(profile, "pivot_block")
        Int[value for value in profile["pivot_block"]]
    elseif profile isa NamedTuple && haskey(profile, :pivot_block)
        Int[value for value in profile.pivot_block]
    else
        return nothing
    end
    return _validate_pivot_block(pivots, matrix_size_value)
end

function _choose_blockwise_psd_proof(blocks, rank_profiles;
                                     block_method::Symbol,
                                     block_pivot_blocks,
                                     max_size::Integer,
                                     max_refinements::Integer)
    block_vector = _psd_block_vector(blocks)
    isempty(block_vector) &&
        throw(ArgumentError("blockwise PSD proof needs at least one block"))

    profiles = _block_option_vector(rank_profiles, length(block_vector); default=nothing)
    pivot_blocks = _block_option_vector(block_pivot_blocks, length(block_vector);
                                        default=nothing)
    plans = PSDProofPlan[]
    for (i, block) in enumerate(block_vector)
        plan = _choose_single_psd_proof(block,
                                        profiles[i];
                                        method=block_method,
                                        pivot_block=pivot_blocks[i],
                                        max_size,
                                        max_refinements,
                                        block_index=i)
        if plan.status !== :accepted
            return PSDProofPlan(Symbol(BLOCKWISE_PSD_METHOD), :rejected,
                                :mixed, nothing, [], nothing, nothing, plans,
                                plan.failure)
        end
        push!(plans, plan)
    end
    return PSDProofPlan(Symbol(BLOCKWISE_PSD_METHOD), :accepted, :mixed, nothing, [],
                        nothing, nothing, plans, nothing)
end

function _psd_block_vector(blocks)
    if blocks isa BlockLMIProblem
        throw(ArgumentError("choose_psd_proof expects substituted PSD block matrices, not an unsubstituted BlockLMIProblem"))
    elseif blocks isa Tuple
        return Any[blocks...]
    elseif blocks isa AbstractVector && !(blocks isa AbstractMatrix)
        return Any[blocks...]
    end
    throw(ArgumentError("blockwise PSD proof expects a vector or tuple of block matrices"))
end

function _block_option_vector(value, count::Integer; default=nothing)
    if isnothing(value)
        return Any[default for _ in 1:count]
    elseif value isa Tuple
        length(value) == count ||
            throw(ArgumentError("block option has length $(length(value)); expected $count"))
        return Any[value...]
    elseif value isa AbstractVector && !(value isa AbstractMatrix)
        length(value) == count ||
            throw(ArgumentError("block option has length $(length(value)); expected $count"))
        return Any[value...]
    end
    return Any[value for _ in 1:count]
end

function _as_psd_algebraic_matrix(A::AbstractMatrix)
    matrix = _algebraic_matrix(A; name=:A)
    _check_square(matrix; name=:A)
    _check_algebraic_symmetric(matrix; name=:A)
    _common_algebraic_root(vec(matrix))
    return matrix
end

function _algebraic_matrix(entries::AbstractMatrix; name::Symbol)
    root = _infer_common_algebraic_root(entries; name)
    data = Matrix{AlgebraicElement}(undef, size(entries))
    for index in eachindex(entries)
        entry = entries[index]
        if entry isa AlgebraicElement
            data[index] = entry
        else
            data[index] = AlgebraicElement(root, _to_big_rational(entry; name))
        end
    end
    return data
end

function _infer_common_algebraic_root(entries::AbstractMatrix; name::Symbol)
    root = nothing
    for entry in entries
        entry isa AlgebraicElement || continue
        if isnothing(root)
            root = entry.root
        elseif entry.root != root
            throw(ArgumentError("$name entries must share the same root representation"))
        end
    end
    isnothing(root) &&
        throw(ArgumentError("$name must contain at least one AlgebraicElement"))
    return root
end

function _check_algebraic_symmetric(entries::AbstractMatrix{AlgebraicElement}; name::Symbol)
    for j in axes(entries, 2), i in (j + 1):size(entries, 1)
        entries[i, j] == entries[j, i] ||
            throw(ArgumentError("$name must be symmetric; entry ($i, $j)=$(entries[i, j]) differs from ($j, $i)=$(entries[j, i])"))
    end
end

function _determinant_algebraic(A::AbstractMatrix)
    matrix = _as_psd_algebraic_matrix(A)
    root = _common_algebraic_root(vec(matrix))
    return _determinant_algebraic_expansion_cached(matrix, root)
end

function _determinant_rational_minor(matrix::AbstractMatrix{<:Rational},
                                     indices::Vector{Int})
    return _cache_fetch(:determinant,
                        (:QQ, _rational_matrix_cache_key(matrix, indices)),
                        :determinant_seconds) do
        return _determinant_bareiss(matrix[indices, indices])
    end
end

function _determinant_algebraic_minor(matrix::AbstractMatrix{AlgebraicElement},
                                      indices::Vector{Int})
    root = _common_algebraic_root(vec(matrix))
    return _cache_fetch(:determinant,
                        (:QQbar, _algebraic_matrix_cache_key(matrix, indices)),
                        :determinant_seconds) do
        return _determinant_algebraic_bareiss(matrix[indices, indices], root)
    end
end

function _determinant_algebraic_expansion_cached(matrix::AbstractMatrix{AlgebraicElement},
                                                 root::AlgebraicRoot)
    n = size(matrix, 1)
    indices = collect(1:n)
    return _cache_fetch(:determinant,
                        (:QQbar, _algebraic_matrix_cache_key(matrix, indices)),
                        :determinant_seconds) do
        return _determinant_algebraic_bareiss(matrix, root)
    end
end

function _rational_matrix_cache_key(matrix::AbstractMatrix{<:Rational},
                                    indices::Vector{Int})
    return (size(matrix), Tuple(indices),
            Tuple(matrix[i, j] for i in axes(matrix, 1), j in axes(matrix, 2)))
end

function _algebraic_matrix_cache_key(matrix::AbstractMatrix{AlgebraicElement},
                                     indices::Vector{Int})
    root = _common_algebraic_root(vec(matrix))
    return (_polynomial_coeff_cache_key(root.f),
            root.interval.lower,
            root.interval.upper,
            size(matrix),
            Tuple(indices),
            Tuple((_polynomial_coeff_cache_key(matrix[i, j].numerator),
                   _polynomial_coeff_cache_key(matrix[i, j].denominator))
                  for i in axes(matrix, 1), j in axes(matrix, 2)))
end

function _determinant_bareiss(matrix::AbstractMatrix)
    n = size(matrix, 1)
    size(matrix, 2) == n || throw(DimensionMismatch("determinant requires a square matrix"))
    n == 0 && return Rational{BigInt}(1)
    n == 1 && return matrix[1, 1]

    work = copy(matrix)
    previous_pivot = _one_like_psd_entry(work[1, 1])
    sign = 1
    for k in 1:(n - 1)
        pivot_row = findfirst(row -> !iszero(work[row, k]), k:n)
        if isnothing(pivot_row)
            return zero(work[1, 1])
        end
        pivot_row = pivot_row + k - 1
        if pivot_row != k
            for col in 1:n
                work[k, col], work[pivot_row, col] = work[pivot_row, col], work[k, col]
            end
            sign = -sign
        end

        pivot = work[k, k]
        for i in (k + 1):n, j in (k + 1):n
            work[i, j] = (work[i, j] * pivot - work[i, k] * work[k, j]) /
                         previous_pivot
        end
        previous_pivot = pivot
    end
    return sign == 1 ? work[n, n] : -work[n, n]
end

_one_like_psd_entry(value::Rational) = one(value)
_one_like_psd_entry(value::AlgebraicElement) = AlgebraicElement(value.root, 1)

function _determinant_algebraic_expansion(matrix::AbstractMatrix{AlgebraicElement},
                                          root::AlgebraicRoot)
    return _determinant_algebraic_bareiss(matrix, root)
end

function _determinant_algebraic_bareiss(matrix::AbstractMatrix{AlgebraicElement},
                                        root::AlgebraicRoot)
    n = size(matrix, 1)
    size(matrix, 2) == n || throw(DimensionMismatch("determinant requires a square matrix"))
    n == 0 && return AlgebraicElement(root, 1)
    n == 1 && return matrix[1, 1]
    n == 2 && return matrix[1, 1] * matrix[2, 2] - matrix[1, 2] * matrix[2, 1]

    return _determinant_bareiss(matrix)
end

function _verify_positive_definite_algebraic(B::AbstractMatrix{AlgebraicElement};
                                             max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS)
    matrix = _as_psd_algebraic_matrix(B)
    result = _verify_positive_definite_algebraic_result(matrix;
                                                        pivot_indices=collect(1:size(matrix,
                                                                                     1)),
                                                        max_refinements)
    return result.accepted
end

function _schur_complement_rational(matrix::AbstractMatrix{<:Rational},
                                    pivots::Vector{Int})
    entries = _as_psd_rational_matrix(matrix)
    n = size(entries, 1)
    rest = _complement_indices(n, pivots)
    isempty(rest) && return Matrix{Rational{BigInt}}(undef, 0, 0)

    B = entries[pivots, pivots]
    C = entries[pivots, rest]
    D = entries[rest, rest]
    B_inv = inv(B)
    return D - transpose(C) * B_inv * C
end

function _verify_schur_zero_rational_result(matrix::AbstractMatrix{<:Rational},
                                            pivot_block;
                                            block_index::Union{Nothing, Int}=nothing)
    entries = _as_psd_rational_matrix(matrix)
    pivots = _validate_pivot_block(pivot_block, size(entries, 1))
    B = entries[pivots, pivots]

    positive = _verify_positive_definite_rational_result(B;
                                                         pivot_indices=pivots,
                                                         block_index)
    positive.accepted || return positive

    schur = _schur_complement_rational(entries, pivots)
    for index in eachindex(schur)
        iszero(schur[index]) || return _psd_failure(Symbol(SCHUR_ZERO_PSD_METHOD),
                                                    :schur_complement,
                                                    "Schur complement entry $(Tuple(index)) is nonzero: $(schur[index])";
                                                    block_index)
    end
    return _psd_success(Symbol(SCHUR_ZERO_PSD_METHOD))
end

function _verify_schur_zero_algebraic_result(matrix::AbstractMatrix{AlgebraicElement},
                                             pivot_block;
                                             max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS,
                                             block_index::Union{Nothing, Int}=nothing)
    entries = _as_psd_algebraic_matrix(matrix)
    pivots = _validate_pivot_block(pivot_block, size(entries, 1))
    B = entries[pivots, pivots]

    positive = _verify_positive_definite_algebraic_result(B;
                                                          pivot_indices=pivots,
                                                          max_refinements,
                                                          block_index)
    positive.accepted || return positive

    schur = _schur_complement_algebraic(entries, pivots)
    for index in eachindex(schur)
        iszero(schur[index]) || return _psd_failure(Symbol(SCHUR_ZERO_PSD_METHOD),
                                                    :schur_complement,
                                                    "Schur complement entry $(Tuple(index)) is nonzero: $(algebraic_element_string(schur[index]))";
                                                    block_index)
    end
    return _psd_success(Symbol(SCHUR_ZERO_PSD_METHOD))
end

function _schur_zero_proof_rational_unchecked(matrix::SymmetricRationalMatrix,
                                              pivot_block)
    entries = rational_matrix(matrix)
    pivots = _validate_pivot_block(pivot_block, size(entries, 1))
    B = entries[pivots, pivots]
    positive_block_minors = PrincipalMinorProof{Rational{BigInt}}[]
    for k in 1:length(pivots)
        push!(positive_block_minors,
              PrincipalMinorProof(pivots[1:k],
                                  _determinant_rational_minor(B,
                                                              collect(1:k))))
    end
    schur = _schur_complement_rational(entries, pivots)
    return SchurZeroProof{Rational{BigInt}}(pivots, positive_block_minors, schur)
end

function _schur_zero_proof_algebraic_unchecked(matrix::AbstractMatrix, pivot_block)
    entries = _as_psd_algebraic_matrix(matrix)
    pivots = _validate_pivot_block(pivot_block, size(entries, 1))
    B = entries[pivots, pivots]
    root = _common_algebraic_root(vec(entries))
    positive_block_minors = PrincipalMinorProof{AlgebraicElement}[]
    rational_B = _algebraic_matrix_rational_entries(B)

    for k in 1:length(pivots)
        determinant = if isnothing(rational_B)
            _determinant_algebraic_minor(B, collect(1:k))
        else
            AlgebraicElement(root,
                             _determinant_rational_minor(rational_B,
                                                         collect(1:k)))
        end
        push!(positive_block_minors, PrincipalMinorProof(pivots[1:k], determinant))
    end

    schur = _schur_complement_algebraic(entries, pivots)
    return SchurZeroProof{AlgebraicElement}(pivots, positive_block_minors, schur)
end

function _schur_complement_algebraic(matrix::AbstractMatrix{AlgebraicElement},
                                     pivots::Vector{Int})
    entries = _as_psd_algebraic_matrix(matrix)
    n = size(entries, 1)
    rest = _complement_indices(n, pivots)
    root = _common_algebraic_root(vec(entries))

    isempty(rest) && return Matrix{AlgebraicElement}(undef, 0, 0)

    B = entries[pivots, pivots]
    C = entries[pivots, rest]
    D = entries[rest, rest]
    B_inv = _inverse_algebraic_matrix(B)
    correction = _algebraic_matmul(_transpose_algebraic_matrix(C),
                                   _algebraic_matmul(B_inv, C))

    schur = _zero_algebraic_matrix(root, length(rest), length(rest))
    for i in axes(D, 1), j in axes(D, 2)
        schur[i, j] = D[i, j] - correction[i, j]
    end
    return schur
end

function _ldl_rational_proof(A::AbstractMatrix{<:Rational})
    entries = _as_psd_rational_matrix(A)
    n = size(entries, 1)
    work = Matrix{Rational{BigInt}}(entries)
    pivots = LDLPivotProof{Rational{BigInt}}[]

    for k in 1:n
        pivot = work[k, k]
        if pivot < 0
            return nothing,
                   _psd_failure(Symbol(LDL_PSD_METHOD), :pivot,
                                "LDL pivot is negative: $pivot";
                                pivot_index=k)
        elseif iszero(pivot)
            for j in (k + 1):n
                iszero(work[k, j]) ||
                    return nothing,
                           _psd_failure(Symbol(LDL_PSD_METHOD), :pivot_row,
                                        "zero LDL pivot has nonzero coupling at ($k, $j): $(work[k, j])";
                                        pivot_index=k,
                                        indices=[k, j])
            end
            push!(pivots, LDLPivotProof(k, pivot, :zero))
            continue
        end

        push!(pivots, LDLPivotProof(k, pivot, :positive))
        for i in (k + 1):n, j in i:n
            work[i, j] -= work[i, k] * work[k, j] / pivot
            work[j, i] = work[i, j]
        end
    end

    return LDLProof(pivots), _psd_success(Symbol(LDL_PSD_METHOD))
end

function _ldl_algebraic_proof(A::AbstractMatrix{AlgebraicElement};
                              max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS)
    entries = _as_psd_algebraic_matrix(A)
    n = size(entries, 1)
    root = _common_algebraic_root(vec(entries))
    work = copy(entries)
    pivots = LDLPivotProof{AlgebraicElement}[]

    for k in 1:n
        pivot = work[k, k]
        sign = certified_sign(pivot; max_refinements)
        if sign === :negative
            return nothing,
                   _psd_failure(Symbol(LDL_PSD_METHOD), :pivot,
                                "LDL pivot is negative: $(algebraic_element_string(pivot))";
                                pivot_index=k)
        elseif sign === :zero
            for j in (k + 1):n
                iszero(work[k, j]) ||
                    return nothing,
                           _psd_failure(Symbol(LDL_PSD_METHOD), :pivot_row,
                                        "zero LDL pivot has nonzero coupling at ($k, $j): $(algebraic_element_string(work[k, j]))";
                                        pivot_index=k,
                                        indices=[k, j])
            end
            push!(pivots, LDLPivotProof(k, AlgebraicElement(root, 0), :zero))
            continue
        end

        push!(pivots, LDLPivotProof(k, pivot, :positive))
        for i in (k + 1):n, j in i:n
            work[i, j] = work[i, j] - work[i, k] * work[k, j] / pivot
            work[j, i] = work[i, j]
        end
    end

    return LDLProof(pivots), _psd_success(Symbol(LDL_PSD_METHOD))
end

function _pivoted_ldl_rational_proof(A::AbstractMatrix{<:Rational})
    entries = _as_psd_rational_matrix(A)
    n = size(entries, 1)
    work = Matrix{Rational{BigInt}}(entries)
    original_indices = collect(1:n)
    pivots = LDLPivotProof{Rational{BigInt}}[]

    k = 1
    while k <= n
        pivot_position = nothing
        for i in k:n
            diagonal = work[i, i]
            diagonal < 0 &&
                return nothing,
                       _psd_failure(Symbol(PIVOTED_LDL_PSD_METHOD), :pivot,
                                    "pivoted LDL diagonal is negative: $diagonal";
                                    pivot_index=original_indices[i])
            if diagonal > 0
                pivot_position = i
                break
            end
        end

        if isnothing(pivot_position)
            for i in k:n, j in i:n
                iszero(work[i, j]) ||
                    return nothing,
                           _psd_failure(Symbol(PIVOTED_LDL_PSD_METHOD), :pivot_row,
                                        "remaining zero-diagonal Schur complement has nonzero coupling at original indices ($(original_indices[i]), $(original_indices[j])): $(work[i, j])";
                                        pivot_index=original_indices[i],
                                        indices=[original_indices[i], original_indices[j]])
            end
            for i in k:n
                push!(pivots, LDLPivotProof(original_indices[i], zero(work[i, i]), :zero))
            end
            break
        end

        _swap_symmetric_positions!(work, original_indices, k, pivot_position)
        pivot = work[k, k]
        push!(pivots, LDLPivotProof(original_indices[k], pivot, :positive))
        for i in (k + 1):n, j in i:n
            work[i, j] -= work[i, k] * work[k, j] / pivot
            work[j, i] = work[i, j]
        end
        k += 1
    end

    return LDLProof(pivots), _psd_success(Symbol(PIVOTED_LDL_PSD_METHOD))
end

function _pivoted_ldl_algebraic_proof(A::AbstractMatrix{AlgebraicElement};
                                      max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS)
    entries = _as_psd_algebraic_matrix(A)
    n = size(entries, 1)
    root = _common_algebraic_root(vec(entries))
    work = copy(entries)
    original_indices = collect(1:n)
    pivots = LDLPivotProof{AlgebraicElement}[]

    k = 1
    while k <= n
        pivot_position = nothing
        for i in k:n
            diagonal = work[i, i]
            sign = certified_sign(diagonal; max_refinements)
            sign === :negative &&
                return nothing,
                       _psd_failure(Symbol(PIVOTED_LDL_PSD_METHOD), :pivot,
                                    "pivoted LDL diagonal is negative: $(algebraic_element_string(diagonal))";
                                    pivot_index=original_indices[i])
            if sign === :positive
                pivot_position = i
                break
            end
        end

        if isnothing(pivot_position)
            for i in k:n, j in i:n
                iszero(work[i, j]) ||
                    return nothing,
                           _psd_failure(Symbol(PIVOTED_LDL_PSD_METHOD), :pivot_row,
                                        "remaining zero-diagonal Schur complement has nonzero coupling at original indices ($(original_indices[i]), $(original_indices[j])): $(algebraic_element_string(work[i, j]))";
                                        pivot_index=original_indices[i],
                                        indices=[original_indices[i], original_indices[j]])
            end
            for i in k:n
                push!(pivots,
                      LDLPivotProof(original_indices[i], AlgebraicElement(root, 0),
                                    :zero))
            end
            break
        end

        _swap_symmetric_positions!(work, original_indices, k, pivot_position)
        pivot = work[k, k]
        push!(pivots, LDLPivotProof(original_indices[k], pivot, :positive))
        for i in (k + 1):n, j in i:n
            work[i, j] = work[i, j] - work[i, k] * work[k, j] / pivot
            work[j, i] = work[i, j]
        end
        k += 1
    end

    return LDLProof(pivots), _psd_success(Symbol(PIVOTED_LDL_PSD_METHOD))
end

function _swap_symmetric_positions!(work::AbstractMatrix, original_indices::Vector{Int},
                                    a::Integer, b::Integer)
    a == b && return nothing
    for col in axes(work, 2)
        work[a, col], work[b, col] = work[b, col], work[a, col]
    end
    for row in axes(work, 1)
        work[row, a], work[row, b] = work[row, b], work[row, a]
    end
    original_indices[a], original_indices[b] = original_indices[b], original_indices[a]
    return nothing
end

function _verify_ldl_rational_result(A::AbstractMatrix{<:Rational};
                                     block_index::Union{Nothing, Int}=nothing)
    proof, result = _ldl_rational_proof(A)
    if result.accepted
        return result
    elseif isnothing(block_index)
        return result
    end
    return _with_failure_block(result, block_index)
end

function _verify_ldl_algebraic_result(A::AbstractMatrix{AlgebraicElement};
                                      max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS,
                                      block_index::Union{Nothing, Int}=nothing)
    proof, result = _ldl_algebraic_proof(A; max_refinements)
    if result.accepted
        return result
    elseif isnothing(block_index)
        return result
    end
    return _with_failure_block(result, block_index)
end

function _verify_pivoted_ldl_rational_result(A::AbstractMatrix{<:Rational};
                                             block_index::Union{Nothing, Int}=nothing)
    proof, result = _pivoted_ldl_rational_proof(A)
    if result.accepted
        return result
    elseif isnothing(block_index)
        return result
    end
    return _with_failure_block(result, block_index)
end

function _verify_pivoted_ldl_algebraic_result(A::AbstractMatrix{AlgebraicElement};
                                              max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS,
                                              block_index::Union{Nothing, Int}=nothing)
    proof, result = _pivoted_ldl_algebraic_proof(A; max_refinements)
    if result.accepted
        return result
    elseif isnothing(block_index)
        return result
    end
    return _with_failure_block(result, block_index)
end

function _ldl_proofs_equal(a::LDLProof, b::LDLProof)
    length(a.pivots) == length(b.pivots) || return false
    for (left, right) in zip(a.pivots, b.pivots)
        left.index == right.index || return false
        left.sign == right.sign || return false
        left.value == right.value || return false
    end
    return true
end

function _inverse_algebraic_matrix(B::AbstractMatrix{AlgebraicElement})
    matrix = _as_psd_algebraic_matrix(B)
    n = size(matrix, 1)
    root = _common_algebraic_root(vec(matrix))
    augmented = _zero_algebraic_matrix(root, n, 2n)

    for i in 1:n
        for j in 1:n
            augmented[i, j] = matrix[i, j]
        end
        augmented[i, n + i] = AlgebraicElement(root, 1)
    end

    for pivot_index in 1:n
        pivot = augmented[pivot_index, pivot_index]
        iszero(pivot) &&
            throw(ArgumentError("positive definite pivot block produced a zero elimination pivot"))
        inverse_pivot = inv(pivot)

        for j in 1:(2n)
            augmented[pivot_index, j] = augmented[pivot_index, j] * inverse_pivot
        end

        for row in 1:n
            row == pivot_index && continue
            factor = augmented[row, pivot_index]
            iszero(factor) && continue
            for j in 1:(2n)
                augmented[row, j] = augmented[row, j] - factor * augmented[pivot_index, j]
            end
        end
    end

    inverse = Matrix{AlgebraicElement}(undef, n, n)
    for i in 1:n, j in 1:n
        inverse[i, j] = augmented[i, n + j]
    end
    return inverse
end

function _algebraic_matmul(A::AbstractMatrix{AlgebraicElement},
                           B::AbstractMatrix{AlgebraicElement})
    size(A, 2) == size(B, 1) ||
        throw(DimensionMismatch("matrix multiplication dimensions do not match: $(size(A)) and $(size(B))"))

    root = _common_algebraic_root(vec(A))
    isempty(B) || (root == _common_algebraic_root(vec(B)) ||
                   throw(ArgumentError("algebraic matrix multiplication requires a common root")))

    result = _zero_algebraic_matrix(root, size(A, 1), size(B, 2))
    for i in 1:size(A, 1), j in 1:size(B, 2)
        total = AlgebraicElement(root, 0)
        for k in 1:size(A, 2)
            total = total + A[i, k] * B[k, j]
        end
        result[i, j] = total
    end
    return result
end

function _transpose_algebraic_matrix(A::AbstractMatrix{AlgebraicElement})
    result = Matrix{AlgebraicElement}(undef, size(A, 2), size(A, 1))
    for i in axes(A, 1), j in axes(A, 2)
        result[j, i] = A[i, j]
    end
    return result
end

function _zero_algebraic_matrix(root::AlgebraicRoot, rows::Integer, cols::Integer)
    matrix = Matrix{AlgebraicElement}(undef, rows, cols)
    for i in 1:rows, j in 1:cols
        matrix[i, j] = AlgebraicElement(root, 0)
    end
    return matrix
end

function _iszero_algebraic_matrix(matrix::AbstractMatrix{AlgebraicElement})
    for entry in matrix
        iszero(entry) || return false
    end
    return true
end

function _algebraic_cofactor(matrix::AbstractMatrix{AlgebraicElement}, row_to_drop::Integer,
                             column_to_drop::Integer)
    n = size(matrix, 1)
    cofactor = Matrix{AlgebraicElement}(undef, n - 1, n - 1)
    target_i = 1
    for i in 1:n
        i == row_to_drop && continue
        target_j = 1
        for j in 1:n
            j == column_to_drop && continue
            cofactor[target_i, target_j] = matrix[i, j]
            target_j += 1
        end
        target_i += 1
    end
    return cofactor
end
