"""
    substitute(P::LMIProblem, x::Vector{AlgebraicElement}) -> Matrix{AlgebraicElement}

Evaluate `A0 + sum(x[i] * A[i])` exactly in one algebraic field `QQ(alpha)`.
All coordinates must share the same `AlgebraicRoot`.
"""
function substitute(P::LMIProblem, x::AbstractVector{<:AlgebraicElement})
    length(x) == num_variables(P) ||
        throw(DimensionMismatch("substitution has length $(length(x)); expected $(num_variables(P))"))

    root = _common_algebraic_root(collect(x))
    result = [AlgebraicElement(root, P.A0.entries[i, j])
              for i in axes(P.A0.entries, 1), j in axes(P.A0.entries, 2)]

    for (value, coefficient) in zip(x, P.A)
        for index in eachindex(result)
            result[index] = result[index] + value * coefficient.entries[index]
        end
    end

    _check_algebraic_symmetric(result; name=:substitution)
    return result
end

"""
    substitute(P::BlockLMIProblem, x::Vector{AlgebraicElement})

Evaluate every PSD block of a block LMI problem exactly in one algebraic field.
"""
substitute(P::BlockLMIProblem, x::AbstractVector{<:AlgebraicElement}) = [substitute(block,
                                                                                    x)
                                                                         for block in
                                                                             P.blocks]
