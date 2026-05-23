module DensificationPolicy

using ..Debug

export DenseConversionToken,
       allow_dense_conversion,
       forbid_dense_conversion,
       no_densify_enabled,
       record_dense_conversion!,
       @no_densify

struct DenseConversionToken
    reason::Symbol
    max_dimension::Int
end

const NO_DENSIFY_DEPTH = Ref(0)

allow_dense_conversion(reason::Symbol, max_dimension::Integer) =
    DenseConversionToken(reason, Int(max_dimension))

function forbid_dense_conversion()
    NO_DENSIFY_DEPTH[] += 1
    return nothing
end

no_densify_enabled() = NO_DENSIFY_DEPTH[] > 0

function record_dense_conversion!(reason::Symbol, size::Integer;
                                  token::Union{Nothing, DenseConversionToken}=nothing,
                                  gate_id::Symbol=:T)
    if no_densify_enabled()
        throw(ArgumentError("dense conversion `$reason` is forbidden in trusted no-densify replay"))
    end
    isnothing(token) &&
        throw(ArgumentError("dense conversion `$reason` requires a DenseConversionToken"))
    Int(size) <= token.max_dimension ||
        throw(ArgumentError("dense conversion `$reason` size $size exceeds token limit $(token.max_dimension)"))
    Debug.record_densification!(reason, Int(size), gate_id)
    return true
end

macro no_densify(ex)
    return quote
        $(NO_DENSIFY_DEPTH)[] += 1
        try
            $(esc(ex))
        finally
            $(NO_DENSIFY_DEPTH)[] -= 1
        end
    end
end

end

