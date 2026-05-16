"""
    SymmetricRationalMatrix(entries; name=:matrix)

Store an exact rational symmetric matrix. Entries may be integers or rationals
and are copied into a dense `Matrix{Rational{BigInt}}`.
"""
struct SymmetricRationalMatrix
    entries::Matrix{Rational{BigInt}}

    function SymmetricRationalMatrix(entries::AbstractMatrix; name::Symbol=:matrix)
        data = _rational_matrix(entries; name)
        _check_square(data; name)
        _check_symmetric(data; name)
        return new(data)
    end
end

"""
    rational_matrix(M) -> Matrix{Rational{BigInt}}

Return a copy of the exact rational entries stored in `M`.
"""
rational_matrix(M::SymmetricRationalMatrix) = copy(M.entries)

Base.size(M::SymmetricRationalMatrix) = size(M.entries)
Base.size(M::SymmetricRationalMatrix, dim::Integer) = size(M.entries, dim)
Base.getindex(M::SymmetricRationalMatrix, i::Integer, j::Integer) = M.entries[i, j]
Base.Matrix(M::SymmetricRationalMatrix) = rational_matrix(M)
Base.:(==)(A::SymmetricRationalMatrix, B::SymmetricRationalMatrix) = A.entries == B.entries

"""
    LMIProblem(A0, A; vars=[:x1, ...])

Represent the linear matrix inequality `A(x) = A0 + sum(x[i] * A[i])`, where all
coefficient matrices are exact rational symmetric matrices of the same size.
"""
struct LMIProblem
    A0::SymmetricRationalMatrix
    A::Vector{SymmetricRationalMatrix}
    vars::Vector{Symbol}

    function LMIProblem(A0, A::AbstractVector;
                        vars::Union{Nothing, AbstractVector{Symbol}}=nothing)
        A0_matrix = _as_symmetric_rational_matrix(A0, :A0)
        coefficient_matrices = SymmetricRationalMatrix[
                                                       _as_symmetric_rational_matrix(matrix,
                                                                                     Symbol("A",
                                                                                            i))
                                                       for (i, matrix) in enumerate(A)
                                                       ]

        expected_size = size(A0_matrix)
        for (i, matrix) in enumerate(coefficient_matrices)
            size(matrix) == expected_size ||
                throw(DimensionMismatch("A$i has size $(size(matrix)); expected $expected_size to match A0"))
        end

        variable_names = isnothing(vars) ?
                         [Symbol("x", i) for i in eachindex(coefficient_matrices)] :
                         collect(vars)
        length(variable_names) == length(coefficient_matrices) ||
            throw(ArgumentError("number of variables ($(length(variable_names))) must match number of coefficient matrices ($(length(coefficient_matrices)))"))
        length(unique(variable_names)) == length(variable_names) ||
            throw(ArgumentError("variable names must be unique"))

        return new(A0_matrix, coefficient_matrices, variable_names)
    end
end

"""
    BlockLMIProblem(blocks; objective=zeros(QQ, n), block_kinds=:psd)

Represent a block-diagonal LMI with shared variables:

`block[j](x) = A0[j] + sum(x[i] * A[i][j]) >= 0`.

This wrapper is used by SDPA sparse import/export because SDPA problems may
contain several PSD blocks while the original `LMIProblem` core stores one
block.
"""
struct BlockLMIProblem
    blocks::Vector{LMIProblem}
    vars::Vector{Symbol}
    objective::Vector{Rational{BigInt}}
    block_kinds::Vector{Symbol}
    metadata::Dict{Symbol, Any}

    function BlockLMIProblem(blocks::AbstractVector{<:LMIProblem};
                             objective::Union{Nothing, AbstractVector}=nothing,
                             block_kinds::Union{Nothing, AbstractVector{Symbol}}=nothing,
                             metadata::AbstractDict=Dict{Symbol, Any}())
        isempty(blocks) &&
            throw(ArgumentError("BlockLMIProblem requires at least one block"))

        block_vector = LMIProblem[blocks...]
        variable_names = copy(block_vector[1].vars)
        for (i, block) in enumerate(block_vector)
            block.vars == variable_names ||
                throw(ArgumentError("block $i variables $(block.vars) do not match first block variables $variable_names"))
        end

        objective_values = if isnothing(objective)
            fill(Rational{BigInt}(0), length(variable_names))
        else
            length(objective) == length(variable_names) ||
                throw(ArgumentError("objective has length $(length(objective)); expected $(length(variable_names))"))
            [_to_big_rational(value; name=Symbol("objective", i))
             for (i, value) in enumerate(objective)]
        end

        kinds = isnothing(block_kinds) ? fill(:psd, length(block_vector)) :
                collect(block_kinds)
        length(kinds) == length(block_vector) ||
            throw(ArgumentError("block_kinds has length $(length(kinds)); expected $(length(block_vector))"))
        for (i, kind) in enumerate(kinds)
            kind in (:psd, :diagonal) ||
                throw(ArgumentError("block_kinds[$i] must be :psd or :diagonal; got $kind"))
            kind === :diagonal && _check_diagonal_block(block_vector[i], i)
        end

        copied_metadata = Dict{Symbol, Any}()
        for (key, value) in metadata
            copied_metadata[Symbol(key)] = value
        end

        return new(block_vector, variable_names, objective_values, kinds,
                   copied_metadata)
    end
end

BlockLMIProblem(block::LMIProblem; kwargs...) = BlockLMIProblem([block]; kwargs...)

"""
    extract_lmi(args...; kwargs...)

Placeholder for optional JuMP/MOI frontend extensions. Load JuMP to enable
`extract_lmi(model::JuMP.Model)`.
"""
function extract_lmi(args...; kwargs...)
    throw(ArgumentError("no JuMP/MOI LMI extractor is available for these arguments; load JuMP or pass an LMIProblem/BlockLMIProblem directly"))
end

"""
    extract_moi_lmi(args...; kwargs...)

Placeholder for optional MOI frontend extensions. Load MathOptInterface to
enable extraction from MOI model-like objects.
"""
function extract_moi_lmi(args...; kwargs...)
    throw(ArgumentError("no MOI LMI extractor is available for these arguments; load MathOptInterface or pass an LMIProblem/BlockLMIProblem directly"))
end

"""
    matrix_size(P::LMIProblem) -> Int

Return the dimension `m` of the square matrices in `P`.
"""
matrix_size(P::LMIProblem) = size(P.A0, 1)

"""
    matrix_size(P::BlockLMIProblem) -> Int

Return the total dimension of the block-diagonal matrix represented by `P`.
"""
matrix_size(P::BlockLMIProblem) = sum(block_sizes(P))

"""
    num_variables(P::LMIProblem) -> Int

Return the number of variables in `P`.
"""
num_variables(P::LMIProblem) = length(P.A)
num_variables(P::BlockLMIProblem) = length(P.vars)

"""
    num_blocks(P::BlockLMIProblem) -> Int

Return the number of PSD blocks in a block LMI problem.
"""
num_blocks(P::BlockLMIProblem) = length(P.blocks)

"""
    block_sizes(P::BlockLMIProblem) -> Vector{Int}

Return the dimensions of the block matrices in `P`.
"""
block_sizes(P::BlockLMIProblem) = [matrix_size(block) for block in P.blocks]

"""
    variable_symbols(P) -> Vector{Symbol}

Return the shared variable order for LMI problem objects.
"""
variable_symbols(P::LMIProblem) = copy(P.vars)
variable_symbols(P::BlockLMIProblem) = copy(P.vars)

"""
    block_struct(P::BlockLMIProblem) -> Vector{Int}

Return SDPA-style block sizes. Diagonal blocks are represented by negative
sizes, matching SDPA's convention.
"""
function block_struct(P::BlockLMIProblem)
    return [kind === :diagonal ? -matrix_size(block) : matrix_size(block)
            for (kind, block) in zip(P.block_kinds, P.blocks)]
end

"""
    single_lmi_problem(P::BlockLMIProblem) -> LMIProblem

Return the only block of `P`, or throw a clear error if `P` has multiple
blocks. This is the bridge back to the original one-block verifier/certifier.
"""
function single_lmi_problem(P::BlockLMIProblem)
    num_blocks(P) == 1 ||
        throw(ArgumentError("BlockLMIProblem has $(num_blocks(P)) blocks; expected exactly one"))
    return P.blocks[1]
end

"""
    block_diagonal_lmi_problem(P::BlockLMIProblem) -> LMIProblem

Return the single dense block-diagonal LMI represented by `P`. This is used by
algebraic incidence certification: the backend sees one exact incidence system,
while the resulting certificate is replayed block-by-block.
"""
function block_diagonal_lmi_problem(P::BlockLMIProblem)
    offsets = cumsum(vcat(0, block_sizes(P)[1:(end - 1)]))
    total_size = matrix_size(P)
    A0 = fill(Rational{BigInt}(0), total_size, total_size)
    A = [fill(Rational{BigInt}(0), total_size, total_size) for _ in P.vars]

    for (block, offset) in zip(P.blocks, offsets)
        rows = (offset + 1):(offset + matrix_size(block))
        A0[rows, rows] .= rational_matrix(block.A0)
        for (j, matrix) in enumerate(block.A)
            A[j][rows, rows] .= rational_matrix(matrix)
        end
    end

    return LMIProblem(A0, A; vars=P.vars)
end

"""
    substitute(P::LMIProblem, x) -> SymmetricRationalMatrix

Evaluate `A0 + sum(x[i] * A[i])` using exact rational arithmetic.
"""
function substitute(P::LMIProblem, x::AbstractVector{<:Union{Integer, Rational}})
    length(x) == num_variables(P) ||
        throw(DimensionMismatch("substitution has length $(length(x)); expected $(num_variables(P))"))

    values = [_to_big_rational(value; name=Symbol("x", i)) for (i, value) in enumerate(x)]
    result = rational_matrix(P.A0)

    for (value, coefficient) in zip(values, P.A)
        result .+= value .* coefficient.entries
    end

    return SymmetricRationalMatrix(result; name=:substitution)
end

"""
    substitute(P::BlockLMIProblem, x) -> Vector{SymmetricRationalMatrix}

Evaluate every PSD block of a block LMI problem using exact rational
arithmetic.
"""
substitute(P::BlockLMIProblem, x::AbstractVector{<:Union{Integer, Rational}}) = [substitute(block,
                                                                                            x)
                                                                                 for block in
                                                                                     P.blocks]

function _as_symmetric_rational_matrix(matrix, name::Symbol)
    matrix isa SymmetricRationalMatrix && return matrix
    matrix isa AbstractMatrix || throw(ArgumentError("$name must be a matrix"))
    return SymmetricRationalMatrix(matrix; name)
end

function _rational_matrix(entries::AbstractMatrix; name::Symbol)
    return [_to_big_rational(entry; name) for entry in entries]
end

function _to_big_rational(value::Integer; name::Symbol)
    return Rational{BigInt}(BigInt(value), BigInt(1))
end

function _to_big_rational(value::Rational; name::Symbol)
    return Rational{BigInt}(BigInt(numerator(value)), BigInt(denominator(value)))
end

function _to_big_rational(value; name::Symbol)
    throw(ArgumentError("$name contains non-exact entry $value; expected an integer or rational"))
end

function _check_square(entries::AbstractMatrix; name::Symbol)
    return size(entries, 1) == size(entries, 2) ||
           throw(DimensionMismatch("$name must be square; got size $(size(entries))"))
end

function _check_symmetric(entries::AbstractMatrix; name::Symbol)
    for j in axes(entries, 2), i in (j + 1):size(entries, 1)
        entries[i, j] == entries[j, i] ||
            throw(ArgumentError("$name must be symmetric; entry ($i, $j)=$(entries[i, j]) differs from ($j, $i)=$(entries[j, i])"))
    end
end

function _check_diagonal_block(block::LMIProblem, block_index::Integer)
    _check_diagonal_matrix(rational_matrix(block.A0), "block $block_index A0")
    for (i, matrix) in enumerate(block.A)
        _check_diagonal_matrix(rational_matrix(matrix), "block $block_index A$i")
    end
    return true
end

function _check_diagonal_matrix(entries::AbstractMatrix, name::AbstractString)
    for j in axes(entries, 2), i in axes(entries, 1)
        i == j && continue
        entries[i, j] == 0 ||
            throw(ArgumentError("$name must be diagonal for an SDPA diagonal block; entry ($i, $j)=$(entries[i, j])"))
    end
    return true
end
