const DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS = 128

"""
    AlgebraicSignResult(status; reason="", interval=nothing, refinements=0)

Certified sign-test result for an algebraic element. `status` is one of
`:zero`, `:positive`, `:negative`, or `:failed`; callers must treat `:failed`
as non-acceptance.
"""
struct AlgebraicSignResult
    status::Symbol
    reason::String
    interval::Union{Nothing, RationalInterval}
    refinements::Int

    function AlgebraicSignResult(status::Symbol; reason::AbstractString="",
                                 interval::Union{Nothing, RationalInterval}=nothing,
                                 refinements::Integer=0)
        status in (:zero, :positive, :negative, :failed) ||
            throw(ArgumentError("algebraic sign status must be :zero, :positive, :negative, or :failed; got $status"))
        refinements >= 0 || throw(ArgumentError("refinements must be nonnegative"))
        return new(status, String(reason), interval, Int(refinements))
    end
end

"""
    algebraic_sign(x; max_refinements=128) -> AlgebraicSignResult

Certify the sign of `g(alpha)/h(alpha)`. The test first uses exact polynomial
remainders for zero detection, then refines the rational isolating interval for
`alpha` until interval arithmetic separates the sign. Failure is explicit via
`:failed`; a denominator that evaluates to zero at the selected root throws an
`ArgumentError`.
"""
function algebraic_sign(x::AlgebraicElement;
                        max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS)
    max_refinements >= 0 || throw(ArgumentError("max_refinements must be nonnegative"))
    return _cache_fetch(:algebraic_sign,
                        _algebraic_sign_cache_key(x, max_refinements),
                        :algebraic_sign_seconds) do
        return _algebraic_sign_uncached(x; max_refinements)
    end
end

function _algebraic_sign_uncached(x::AlgebraicElement;
                                  max_refinements::Integer=DEFAULT_MAX_ALGEBRAIC_SIGN_REFINEMENTS)
    if iszero(polynomial_remainder(x.numerator, x.root.f))
        if _shares_selected_root(x.denominator, x.root)
            throw(ArgumentError("algebraic element denominator evaluates to zero at the selected root"))
        end
        return AlgebraicSignResult(:zero;
                                   reason="numerator is zero modulo the root polynomial",
                                   interval=x.root.interval,
                                   refinements=0,)
    end

    denominator_sign = _polynomial_sign_at_root(x.denominator, x.root; max_refinements)
    if denominator_sign.status === :zero
        throw(ArgumentError("algebraic element denominator evaluates to zero at the selected root"))
    elseif denominator_sign.status === :failed
        return AlgebraicSignResult(:failed;
                                   reason="could not certify denominator sign: $(denominator_sign.reason)",
                                   interval=denominator_sign.interval,
                                   refinements=denominator_sign.refinements,)
    end

    numerator_sign = _polynomial_sign_at_root(x.numerator, x.root; max_refinements)
    if numerator_sign.status === :zero
        return AlgebraicSignResult(:zero;
                                   reason=numerator_sign.reason,
                                   interval=numerator_sign.interval,
                                   refinements=numerator_sign.refinements,)
    elseif numerator_sign.status === :failed
        return numerator_sign
    end

    status = numerator_sign.status === denominator_sign.status ? :positive : :negative
    return AlgebraicSignResult(status;
                               reason="numerator and denominator signs certified by interval refinement",
                               interval=numerator_sign.interval,
                               refinements=max(numerator_sign.refinements,
                                               denominator_sign.refinements),)
end

function _algebraic_sign_cache_key(x::AlgebraicElement, max_refinements::Integer)
    return (_polynomial_coeff_cache_key(x.root.f),
            x.root.interval.lower,
            x.root.interval.upper,
            _polynomial_coeff_cache_key(x.numerator),
            _polynomial_coeff_cache_key(x.denominator),
            Int(max_refinements))
end

"""
    certified_sign(x; kwargs...) -> Symbol

Return `:zero`, `:positive`, or `:negative`, throwing if the sign cannot be
certified. This is the strict helper to use inside verifiers.
"""
function certified_sign(x::AlgebraicElement; kwargs...)
    result = algebraic_sign(x; kwargs...)
    result.status === :failed &&
        throw(ArgumentError("could not certify algebraic sign: $(result.reason)"))
    return result.status
end

function Base.show(io::IO, result::AlgebraicSignResult)
    print(io, "AlgebraicSignResult(", result.status)
    isempty(result.reason) || print(io, ", reason=", repr(result.reason))
    isnothing(result.interval) || print(io, ", interval=", result.interval)
    return print(io, ", refinements=", result.refinements, ")")
end

struct _RationalRange
    lower::Rational{BigInt}
    upper::Rational{BigInt}

    function _RationalRange(lower::Rational{BigInt}, upper::Rational{BigInt})
        lower <= upper || throw(ArgumentError("invalid rational range: lower > upper"))
        return new(lower, upper)
    end
end

_RationalRange(value::Rational{BigInt}) = _RationalRange(value, value)

function _polynomial_sign_at_root(p::UnivariatePolynomial, root::AlgebraicRoot;
                                  max_refinements::Integer)
    reduced = polynomial_remainder(p, root.f)
    if iszero(reduced)
        return AlgebraicSignResult(:zero;
                                   reason="polynomial is zero modulo the root polynomial",
                                   interval=root.interval,
                                   refinements=0,)
    end

    constant_sign = _constant_polynomial_sign(reduced)
    if !isnothing(constant_sign)
        return AlgebraicSignResult(constant_sign;
                                   reason="constant polynomial sign",
                                   interval=root.interval,
                                   refinements=0,)
    end

    validation_error = _refinable_root_interval_error(root)
    if !isnothing(validation_error)
        return AlgebraicSignResult(:failed;
                                   reason=validation_error,
                                   interval=root.interval,
                                   refinements=0,)
    end

    selected_zero = _shares_selected_root(reduced, root)
    if selected_zero
        return AlgebraicSignResult(:zero;
                                   reason="polynomial shares the selected algebraic root",
                                   interval=root.interval,
                                   refinements=0,)
    end

    lower = root.interval.lower
    upper = root.interval.upper

    for refinements in 0:max_refinements
        current_interval = RationalInterval(lower, upper)
        if _count_real_roots_in_interval(reduced, current_interval) == 0
            probe = (lower + upper) // 2
            probe_value = _evaluate_polynomial(reduced, probe)
            if !iszero(probe_value)
                return AlgebraicSignResult(_rational_sign(probe_value);
                                           reason="Sturm count excluded roots on the isolating interval",
                                           interval=current_interval,
                                           refinements,)
            end
        end

        range = _evaluate_polynomial_interval(reduced, lower, upper)
        range_sign = _range_sign(range)
        if !isnothing(range_sign)
            return AlgebraicSignResult(range_sign;
                                       reason="interval arithmetic separated zero",
                                       interval=current_interval,
                                       refinements,)
        end

        refinements == max_refinements && break

        refinement = _bisect_root_bracket(root.f, lower, upper)
        if refinement isa Rational{BigInt}
            point_sign = _rational_sign(_evaluate_polynomial(reduced, refinement))
            return AlgebraicSignResult(point_sign;
                                       reason="root isolated as an exact rational point",
                                       interval=RationalInterval(root.interval.lower,
                                                                 root.interval.upper),
                                       refinements=refinements + 1,)
        elseif refinement === nothing
            return AlgebraicSignResult(:failed;
                                       reason="root interval could not be refined by sign-changing bisection",
                                       interval=current_interval,
                                       refinements,)
        else
            lower, upper = refinement
        end
    end

    return AlgebraicSignResult(:failed;
                               reason="could not determine sign after $max_refinements interval refinements",
                               interval=RationalInterval(lower, upper),
                               refinements=max_refinements,)
end

function _constant_polynomial_sign(p::UnivariatePolynomial)
    degree(p) == 0 || return nothing
    return _rational_sign(p.coeffs[1])
end

function _refinable_root_interval_error(root::AlgebraicRoot)
    lower = root.interval.lower
    upper = root.interval.upper
    lower_value = _evaluate_polynomial(root.f, lower)
    upper_value = _evaluate_polynomial(root.f, upper)

    if iszero(lower_value) || iszero(upper_value)
        return "root interval endpoint is a root; expected an open isolating bracket"
    end

    root_count = _count_real_roots_in_interval(root.f, root.interval)
    root_count == 1 ||
        return "root interval must isolate exactly one real root; found $root_count"

    _rational_sign(lower_value) !== _rational_sign(upper_value) ||
        return "root polynomial does not change sign across the interval"

    return nothing
end

function _shares_selected_root(p::UnivariatePolynomial, root::AlgebraicRoot)
    common = _polynomial_gcd(p, root.f)
    degree(common) >= 1 || return false
    return _count_real_roots_in_interval(common, root.interval) > 0
end

function _bisect_root_bracket(f::UnivariatePolynomial, lower::Rational{BigInt},
                              upper::Rational{BigInt})
    lower_value = _evaluate_polynomial(f, lower)
    upper_value = _evaluate_polynomial(f, upper)
    iszero(lower_value) && return lower
    iszero(upper_value) && return upper

    lower_sign = _rational_sign(lower_value)
    upper_sign = _rational_sign(upper_value)
    lower_sign !== upper_sign || return nothing

    midpoint = (lower + upper) // 2
    midpoint_value = _evaluate_polynomial(f, midpoint)
    iszero(midpoint_value) && return midpoint

    midpoint_sign = _rational_sign(midpoint_value)
    if lower_sign !== midpoint_sign
        return (lower, midpoint)
    elseif midpoint_sign !== upper_sign
        return (midpoint, upper)
    end

    return nothing
end

function _evaluate_polynomial(p::UnivariatePolynomial, x::Rational{BigInt})
    result = Rational{BigInt}(0)
    for coefficient in reverse(p.coeffs)
        result = result * x + coefficient
    end
    return result
end

function _evaluate_polynomial_interval(p::UnivariatePolynomial, lower::Rational{BigInt},
                                       upper::Rational{BigInt})
    x_range = _RationalRange(lower, upper)
    result = _RationalRange(Rational{BigInt}(0))
    for coefficient in reverse(p.coeffs)
        result = _range_add(_range_mul(result, x_range), _RationalRange(coefficient))
    end
    return result
end

function _range_add(a::_RationalRange, b::_RationalRange)
    return _RationalRange(a.lower + b.lower, a.upper + b.upper)
end

function _range_mul(a::_RationalRange, b::_RationalRange)
    products = (a.lower * b.lower,
                a.lower * b.upper,
                a.upper * b.lower,
                a.upper * b.upper)
    return _RationalRange(minimum(products), maximum(products))
end

function _range_sign(range::_RationalRange)
    range.lower > 0 && return :positive
    range.upper < 0 && return :negative
    range.lower == 0 && range.upper == 0 && return :zero
    return nothing
end

function _rational_sign(value::Rational{BigInt})
    value > 0 && return :positive
    value < 0 && return :negative
    return :zero
end

function _count_real_roots_in_interval(p::UnivariatePolynomial, interval::RationalInterval)
    squarefree = _squarefree_part(p)
    degree(squarefree) >= 1 || return 0
    sequence = _sturm_sequence(squarefree)
    return _sign_variations_at(sequence, interval.lower) -
           _sign_variations_at(sequence, interval.upper)
end

function _sturm_sequence(p::UnivariatePolynomial)
    sequence = UnivariatePolynomial[p, _polynomial_derivative(p)]
    while !iszero(sequence[end])
        remainder = polynomial_remainder(sequence[end - 1], sequence[end])
        iszero(remainder) && break
        push!(sequence, -remainder)
    end
    return sequence
end

function _sign_variations_at(sequence::Vector{UnivariatePolynomial}, x::Rational{BigInt})
    previous = :zero
    variations = 0
    for polynomial in sequence
        current = _rational_sign(_evaluate_polynomial(polynomial, x))
        current === :zero && continue
        if previous !== :zero && current !== previous
            variations += 1
        end
        previous = current
    end
    return variations
end

function _squarefree_part(p::UnivariatePolynomial)
    iszero(p) && return p
    derivative = _polynomial_derivative(p)
    iszero(derivative) && return _monic_polynomial(p)

    common = _polynomial_gcd(p, derivative)
    quotient, remainder = _polynomial_division(p, common)
    iszero(remainder) ||
        throw(ArgumentError("internal polynomial division failed while computing squarefree part"))
    return _monic_polynomial(quotient)
end

function _polynomial_derivative(p::UnivariatePolynomial)
    degree(p) <= 0 && return UnivariatePolynomial(0)
    coeffs = Rational{BigInt}[
                              Rational{BigInt}(exponent) * p.coeffs[exponent + 1]
                              for exponent in 1:degree(p)
                              ]
    return UnivariatePolynomial(coeffs)
end

function _polynomial_gcd(a::UnivariatePolynomial, b::UnivariatePolynomial)
    left = a
    right = b
    while !iszero(right)
        left, right = right, polynomial_remainder(left, right)
    end
    return _monic_polynomial(left)
end

function _monic_polynomial(p::UnivariatePolynomial)
    iszero(p) && return p
    return p * inv(_leading_coefficient(p))
end

function _polynomial_division(a::UnivariatePolynomial, b::UnivariatePolynomial)
    iszero(b) && throw(DivideError())

    remainder = copy(a.coeffs)
    _trim_polynomial_coeffs!(remainder)
    quotient = fill(Rational{BigInt}(0), max(1, degree(a) - degree(b) + 1))

    divisor_degree = degree(b)
    divisor_lead = _leading_coefficient(b)

    while !_coeffs_are_zero(remainder) && length(remainder) - 1 >= divisor_degree
        shift = (length(remainder) - 1) - divisor_degree
        factor = remainder[end] / divisor_lead
        quotient[shift + 1] += factor

        for i in 0:divisor_degree
            remainder[shift + i + 1] -= factor * b.coeffs[i + 1]
        end
        _trim_polynomial_coeffs!(remainder)
    end

    return UnivariatePolynomial(quotient), UnivariatePolynomial(remainder)
end
