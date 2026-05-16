"""
    UnivariatePolynomial(coeffs)

Store a polynomial in `QQ[t]` with coefficients in ascending degree order.
This is a deliberately small polynomial layer for certificate verification; it
is not intended to be a full CAS.
"""
struct UnivariatePolynomial
    coeffs::Vector{Rational{BigInt}}

    function UnivariatePolynomial(coeffs::AbstractVector)
        data = Rational{BigInt}[_to_big_rational(coeff; name=:polynomial_coefficient)
                                for coeff in coeffs]
        _trim_polynomial_coeffs!(data)
        return new(data)
    end
end

UnivariatePolynomial(value::Integer) = UnivariatePolynomial([value])
UnivariatePolynomial(value::Rational) = UnivariatePolynomial([value])

"""
    RationalInterval(lower, upper)

Store an exact rational isolating interval candidate `[lower, upper]`.
The constructor checks only that the interval is nonempty; uniqueness of the
root is handled by certified root-verification routines.
"""
struct RationalInterval
    lower::Rational{BigInt}
    upper::Rational{BigInt}

    function RationalInterval(lower, upper)
        lo = _parse_rational_like(lower; name=:interval_lower)
        hi = _parse_rational_like(upper; name=:interval_upper)
        lo < hi || throw(ArgumentError("isolating interval must satisfy lower < upper"))
        return new(lo, hi)
    end
end

"""
    AlgebraicRoot(f, interval)

Represent a real algebraic root by a nonconstant polynomial `f(t)` and a
rational isolating interval.
"""
struct AlgebraicRoot
    f::UnivariatePolynomial
    interval::RationalInterval

    function AlgebraicRoot(f::UnivariatePolynomial, interval::RationalInterval)
        normalized = _canonical_root_polynomial(f)
        degree(normalized) >= 1 ||
            throw(ArgumentError("algebraic root polynomial must be nonconstant"))
        return new(normalized, interval)
    end
end

function AlgebraicRoot(f::AbstractString, lower, upper)
    return AlgebraicRoot(parse_polynomial(f), RationalInterval(lower, upper))
end
function AlgebraicRoot(f::AbstractString, interval::Tuple)
    return AlgebraicRoot(f, interval[1], interval[2])
end
function AlgebraicRoot(f::UnivariatePolynomial, lower, upper)
    return AlgebraicRoot(f, RationalInterval(lower, upper))
end

"""
    AlgebraicElement(root, numerator, denominator=1)

Represent an element of `QQ(alpha)` as `g(alpha) / h(alpha)` for the given
`AlgebraicRoot`. The numerator and denominator are reduced modulo `f`.
"""
struct AlgebraicElement
    root::AlgebraicRoot
    numerator::UnivariatePolynomial
    denominator::UnivariatePolynomial

    function AlgebraicElement(root::AlgebraicRoot, numerator::UnivariatePolynomial,
                              denominator::UnivariatePolynomial=UnivariatePolynomial(1))
        reduced_numerator = polynomial_remainder(numerator, root.f)
        reduced_denominator = polynomial_remainder(denominator, root.f)
        iszero(reduced_denominator) &&
            throw(ArgumentError("algebraic element denominator is zero modulo the root polynomial"))
        if iszero(reduced_numerator)
            _root_polynomial_shares_selected_root(reduced_denominator, root) &&
                throw(ArgumentError("algebraic element denominator evaluates to zero at the selected root"))
            return new(root, reduced_numerator, UnivariatePolynomial(1))
        end
        return new(root, reduced_numerator, reduced_denominator)
    end
end

function AlgebraicElement(root::AlgebraicRoot, numerator::AbstractString)
    return AlgebraicElement(root, parse_rational_function(numerator)...)
end
function AlgebraicElement(root::AlgebraicRoot, numerator::AbstractString,
                          denominator::AbstractString)
    return AlgebraicElement(root, parse_polynomial(numerator),
                            parse_polynomial(denominator))
end
function AlgebraicElement(root::AlgebraicRoot, value::Integer)
    return AlgebraicElement(root, UnivariatePolynomial(value))
end
function AlgebraicElement(root::AlgebraicRoot, value::Rational)
    return AlgebraicElement(root, UnivariatePolynomial(value))
end

"""
    parse_polynomial(text) -> UnivariatePolynomial

Parse a small `QQ[t]` polynomial such as `"t^2 - 2"` or `"1/2*t + 3"`.
Supported terms are rational constants and rational multiples of `t^k`.
"""
function parse_polynomial(text::AbstractString)
    source = _strip_enclosing_parentheses(replace(strip(String(text)), " " => ""))
    isempty(source) && throw(ArgumentError("polynomial string must not be empty"))

    terms = _split_polynomial_terms(source)
    coeffs = Rational{BigInt}[0 // 1]

    for term in terms
        coefficient, exponent = _parse_polynomial_term(term)
        if exponent + 1 > length(coeffs)
            old_length = length(coeffs)
            resize!(coeffs, exponent + 1)
            for i in (old_length + 1):(exponent + 1)
                coeffs[i] = 0 // 1
            end
        end
        coeffs[exponent + 1] += coefficient
    end

    return UnivariatePolynomial(coeffs)
end

"""
    parse_rational_function(text) -> (numerator, denominator)

Parse `g(t)` or `g(t)/h(t)` into two `UnivariatePolynomial`s. Rational
coefficient slashes like `1/2*t` are not treated as rational-function dividers.
"""
function parse_rational_function(text::AbstractString)
    source = _strip_enclosing_parentheses(replace(strip(String(text)), " " => ""))
    divider = _find_rational_function_divider(source)
    if isnothing(divider)
        return (parse_polynomial(source), UnivariatePolynomial(1))
    end

    numerator_text = divider == firstindex(source) ? "" :
                     _strip_enclosing_parentheses(source[firstindex(source):prevind(source,
                                                                                    divider)])
    denominator_text = divider == lastindex(source) ? "" :
                       _strip_enclosing_parentheses(source[nextind(source, divider):lastindex(source)])
    isempty(numerator_text) &&
        throw(ArgumentError("rational function numerator must not be empty"))
    isempty(denominator_text) &&
        throw(ArgumentError("rational function denominator must not be empty"))
    return (parse_polynomial(numerator_text), parse_polynomial(denominator_text))
end

parse_algebraic_root(f::AbstractString, lower, upper) = AlgebraicRoot(f, lower, upper)
parse_algebraic_root(f::AbstractString, interval::Tuple) = AlgebraicRoot(f, interval)
function parse_algebraic_element(root::AlgebraicRoot, expression::AbstractString)
    return AlgebraicElement(root, expression)
end

"""
    degree(p) -> Int

Return the degree of `p`, using `-1` for the zero polynomial.
"""
function degree(p::UnivariatePolynomial)
    iszero(p) && return -1
    return length(p.coeffs) - 1
end

"""
    polynomial_remainder(a, b) -> UnivariatePolynomial

Return `a mod b` over `QQ[t]`.
"""
function polynomial_remainder(a::UnivariatePolynomial, b::UnivariatePolynomial)
    iszero(b) && throw(DivideError())
    return _cache_fetch(:polynomial_remainder,
                        _polynomial_remainder_cache_key(a, b),
                        :polynomial_remainder_seconds) do
        return _polynomial_remainder_uncached(a, b)
    end
end

function _polynomial_remainder_uncached(a::UnivariatePolynomial, b::UnivariatePolynomial)
    remainder = copy(a.coeffs)
    _trim_polynomial_coeffs!(remainder)
    divisor_degree = degree(b)
    divisor_lead = _leading_coefficient(b)

    while !_coeffs_are_zero(remainder) && length(remainder) - 1 >= divisor_degree
        shift = (length(remainder) - 1) - divisor_degree
        factor = remainder[end] / divisor_lead

        for i in 0:divisor_degree
            remainder[shift + i + 1] -= factor * b.coeffs[i + 1]
        end
        _trim_polynomial_coeffs!(remainder)
    end

    return UnivariatePolynomial(remainder)
end

function _canonical_root_polynomial(f::UnivariatePolynomial)
    degree(f) >= 1 || return f
    return _root_squarefree_part(f)
end

function _root_squarefree_part(p::UnivariatePolynomial)
    derivative = _root_polynomial_derivative(p)
    iszero(derivative) && return _root_monic_polynomial(p)
    common = _root_polynomial_gcd(p, derivative)
    quotient, remainder = _root_polynomial_division(p, common)
    iszero(remainder) ||
        throw(ArgumentError("internal polynomial division failed while normalizing algebraic root polynomial"))
    return _root_monic_polynomial(quotient)
end

function _root_polynomial_derivative(p::UnivariatePolynomial)
    degree(p) <= 0 && return UnivariatePolynomial(0)
    return UnivariatePolynomial([Rational{BigInt}(exponent) * p.coeffs[exponent + 1]
                                 for exponent in 1:degree(p)])
end

function _root_polynomial_gcd(a::UnivariatePolynomial, b::UnivariatePolynomial)
    left = a
    right = b
    while !iszero(right)
        left, right = right, polynomial_remainder(left, right)
    end
    return _root_monic_polynomial(left)
end

function _root_monic_polynomial(p::UnivariatePolynomial)
    iszero(p) && return p
    return p * inv(_leading_coefficient(p))
end

function _root_polynomial_division(a::UnivariatePolynomial, b::UnivariatePolynomial)
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

function _root_polynomial_shares_selected_root(p::UnivariatePolynomial,
                                               root::AlgebraicRoot)
    common = _root_polynomial_gcd(p, root.f)
    degree(common) >= 1 || return false
    return _root_count_real_roots_in_interval(common, root.interval) > 0
end

function _root_count_real_roots_in_interval(p::UnivariatePolynomial,
                                            interval::RationalInterval)
    squarefree = _root_squarefree_part(p)
    degree(squarefree) >= 1 || return 0
    sequence = _root_sturm_sequence(squarefree)
    return _root_sign_variations_at(sequence, interval.lower) -
           _root_sign_variations_at(sequence, interval.upper)
end

function _root_sturm_sequence(p::UnivariatePolynomial)
    sequence = UnivariatePolynomial[p, _root_polynomial_derivative(p)]
    while !iszero(sequence[end])
        remainder = polynomial_remainder(sequence[end - 1], sequence[end])
        iszero(remainder) && break
        push!(sequence, -remainder)
    end
    return sequence
end

function _root_sign_variations_at(sequence::Vector{UnivariatePolynomial},
                                  x::Rational{BigInt})
    previous = :zero
    variations = 0
    for polynomial in sequence
        current = _root_rational_sign(_root_evaluate_polynomial(polynomial, x))
        current === :zero && continue
        if previous !== :zero && current !== previous
            variations += 1
        end
        previous = current
    end
    return variations
end

function _root_evaluate_polynomial(p::UnivariatePolynomial, x::Rational{BigInt})
    result = Rational{BigInt}(0)
    for coefficient in reverse(p.coeffs)
        result = result * x + coefficient
    end
    return result
end

function _root_rational_sign(value::Rational{BigInt})
    value > 0 && return :positive
    value < 0 && return :negative
    return :zero
end

function _polynomial_remainder_cache_key(a::UnivariatePolynomial, b::UnivariatePolynomial)
    return (_polynomial_coeff_cache_key(a), _polynomial_coeff_cache_key(b))
end

_polynomial_coeff_cache_key(p::UnivariatePolynomial) = Tuple(p.coeffs)

Base.rem(a::UnivariatePolynomial, b::UnivariatePolynomial) = polynomial_remainder(a, b)

function Base.iszero(p::UnivariatePolynomial)
    return length(p.coeffs) == 1 && iszero(p.coeffs[1])
end

Base.copy(p::UnivariatePolynomial) = UnivariatePolynomial(copy(p.coeffs))
Base.:(==)(a::UnivariatePolynomial, b::UnivariatePolynomial) = a.coeffs == b.coeffs
function Base.:(==)(a::RationalInterval, b::RationalInterval)
    return a.lower == b.lower && a.upper == b.upper
end
Base.:(==)(a::AlgebraicRoot, b::AlgebraicRoot) = a.f == b.f && a.interval == b.interval

function Base.:+(a::UnivariatePolynomial, b::UnivariatePolynomial)
    n = max(length(a.coeffs), length(b.coeffs))
    coeffs = Rational{BigInt}[
                              _coefficient(a, exponent) + _coefficient(b, exponent)
                              for exponent in 0:(n - 1)
                              ]
    return UnivariatePolynomial(coeffs)
end

Base.:+(a::UnivariatePolynomial, b::Integer) = a + UnivariatePolynomial(b)
Base.:+(a::Integer, b::UnivariatePolynomial) = UnivariatePolynomial(a) + b
Base.:+(a::UnivariatePolynomial, b::Rational) = a + UnivariatePolynomial(b)
Base.:+(a::Rational, b::UnivariatePolynomial) = UnivariatePolynomial(a) + b

function Base.:-(a::UnivariatePolynomial)
    return UnivariatePolynomial([-coeff for coeff in a.coeffs])
end

Base.:-(a::UnivariatePolynomial, b::UnivariatePolynomial) = a + (-b)
Base.:-(a::UnivariatePolynomial, b::Integer) = a - UnivariatePolynomial(b)
Base.:-(a::Integer, b::UnivariatePolynomial) = UnivariatePolynomial(a) - b
Base.:-(a::UnivariatePolynomial, b::Rational) = a - UnivariatePolynomial(b)
Base.:-(a::Rational, b::UnivariatePolynomial) = UnivariatePolynomial(a) - b

function Base.:*(a::UnivariatePolynomial, b::UnivariatePolynomial)
    if iszero(a) || iszero(b)
        return UnivariatePolynomial(0)
    end

    coeffs = fill(Rational{BigInt}(0), degree(a) + degree(b) + 1)
    for i in eachindex(a.coeffs), j in eachindex(b.coeffs)
        coeffs[i + j - 1] += a.coeffs[i] * b.coeffs[j]
    end
    return UnivariatePolynomial(coeffs)
end

Base.:*(a::UnivariatePolynomial, b::Integer) = a * UnivariatePolynomial(b)
Base.:*(a::Integer, b::UnivariatePolynomial) = UnivariatePolynomial(a) * b
Base.:*(a::UnivariatePolynomial, b::Rational) = a * UnivariatePolynomial(b)
Base.:*(a::Rational, b::UnivariatePolynomial) = UnivariatePolynomial(a) * b

function Base.:(==)(a::AlgebraicElement, b::AlgebraicElement)
    a.root == b.root || return false
    witness = a.numerator * b.denominator - b.numerator * a.denominator
    return iszero(polynomial_remainder(witness, a.root.f))
end

Base.:(==)(a::AlgebraicElement, b::Integer) = a == AlgebraicElement(a.root, b)
Base.:(==)(a::Integer, b::AlgebraicElement) = AlgebraicElement(b.root, a) == b
Base.:(==)(a::AlgebraicElement, b::Rational) = a == AlgebraicElement(a.root, b)
Base.:(==)(a::Rational, b::AlgebraicElement) = AlgebraicElement(b.root, a) == b
Base.iszero(a::AlgebraicElement) = iszero(polynomial_remainder(a.numerator, a.root.f))
Base.zero(a::AlgebraicElement) = AlgebraicElement(a.root, 0)
Base.one(a::AlgebraicElement) = AlgebraicElement(a.root, 1)

function Base.:+(a::AlgebraicElement, b::AlgebraicElement)
    root = _common_root(a, b)
    numerator = a.numerator * b.denominator + b.numerator * a.denominator
    denominator = a.denominator * b.denominator
    return AlgebraicElement(root, numerator, denominator)
end

Base.:+(a::AlgebraicElement, b::Integer) = a + AlgebraicElement(a.root, b)
Base.:+(a::Integer, b::AlgebraicElement) = AlgebraicElement(b.root, a) + b
Base.:+(a::AlgebraicElement, b::Rational) = a + AlgebraicElement(a.root, b)
Base.:+(a::Rational, b::AlgebraicElement) = AlgebraicElement(b.root, a) + b

Base.:-(a::AlgebraicElement) = AlgebraicElement(a.root, -a.numerator, a.denominator)
Base.:-(a::AlgebraicElement, b::AlgebraicElement) = a + (-b)
Base.:-(a::AlgebraicElement, b::Integer) = a - AlgebraicElement(a.root, b)
Base.:-(a::Integer, b::AlgebraicElement) = AlgebraicElement(b.root, a) - b
Base.:-(a::AlgebraicElement, b::Rational) = a - AlgebraicElement(a.root, b)
Base.:-(a::Rational, b::AlgebraicElement) = AlgebraicElement(b.root, a) - b

function Base.:*(a::AlgebraicElement, b::AlgebraicElement)
    root = _common_root(a, b)
    return AlgebraicElement(root, a.numerator * b.numerator, a.denominator * b.denominator)
end

Base.:*(a::AlgebraicElement, b::Integer) = a * AlgebraicElement(a.root, b)
Base.:*(a::Integer, b::AlgebraicElement) = AlgebraicElement(b.root, a) * b
Base.:*(a::AlgebraicElement, b::Rational) = a * AlgebraicElement(a.root, b)
Base.:*(a::Rational, b::AlgebraicElement) = AlgebraicElement(b.root, a) * b

Base.inv(a::AlgebraicElement) = AlgebraicElement(a.root, a.denominator, a.numerator)
Base.:/(a::AlgebraicElement, b::AlgebraicElement) = a * inv(b)
Base.:/(a::AlgebraicElement, b::Integer) = a / AlgebraicElement(a.root, b)
Base.:/(a::Integer, b::AlgebraicElement) = AlgebraicElement(b.root, a) / b
Base.:/(a::AlgebraicElement, b::Rational) = a / AlgebraicElement(a.root, b)
Base.:/(a::Rational, b::AlgebraicElement) = AlgebraicElement(b.root, a) / b

function Base.:^(a::AlgebraicElement, n::Integer)
    if n < 0
        return inv(a)^(-n)
    end

    result = AlgebraicElement(a.root, 1)
    base = a
    exponent = n
    while exponent > 0
        if isodd(exponent)
            result *= base
        end
        base *= base
        exponent = div(exponent, 2)
    end
    return result
end

function Base.show(io::IO, p::UnivariatePolynomial)
    return print(io, _polynomial_string(p))
end

function Base.show(io::IO, interval::RationalInterval)
    return print(io, "[", _rational_string(interval.lower), ", ",
                 _rational_string(interval.upper), "]")
end

function Base.show(io::IO, root::AlgebraicRoot)
    return print(io, "AlgebraicRoot(", root.f, ", ", root.interval, ")")
end

function Base.show(io::IO, element::AlgebraicElement)
    return print(io, "AlgebraicElement(",
                 _rational_function_string(element.numerator, element.denominator),
                 "; root=", element.root, ")")
end

"""
    algebraic_element_string(x) -> String

Return the certificate-format rational function string for an algebraic element,
using `t` as the root variable.
"""
algebraic_element_string(x::AlgebraicElement) = _rational_function_string(x.numerator,
                                                                          x.denominator)

function _parse_rational_like(value; name::Symbol)
    value isa AbstractString && return _parse_rational_string(value, String(name))
    return _to_big_rational(value; name)
end

function _trim_polynomial_coeffs!(coeffs::Vector{Rational{BigInt}})
    while length(coeffs) > 1 && iszero(coeffs[end])
        pop!(coeffs)
    end
    if isempty(coeffs)
        push!(coeffs, 0 // 1)
    end
    return coeffs
end

function _coeffs_are_zero(coeffs::Vector{Rational{BigInt}})
    return all(iszero, coeffs)
end

function _coefficient(p::UnivariatePolynomial, exponent::Integer)
    exponent < 0 && throw(ArgumentError("polynomial exponent must be nonnegative"))
    index = exponent + 1
    return index <= length(p.coeffs) ? p.coeffs[index] : Rational{BigInt}(0)
end

function _leading_coefficient(p::UnivariatePolynomial)
    iszero(p) && throw(ArgumentError("zero polynomial has no leading coefficient"))
    return p.coeffs[end]
end

function _split_polynomial_terms(source::AbstractString)
    terms = String[]
    start = firstindex(source)
    depth = 0

    for i in eachindex(source)
        char = source[i]
        if char == '('
            depth += 1
        elseif char == ')'
            depth -= 1
            depth >= 0 ||
                throw(ArgumentError("unbalanced parentheses in polynomial: $source"))
        elseif (char == '+' || char == '-') && depth == 0 && i != firstindex(source)
            push!(terms, source[start:prevind(source, i)])
            start = i
        end
    end

    depth == 0 || throw(ArgumentError("unbalanced parentheses in polynomial: $source"))
    push!(terms, source[start:lastindex(source)])
    return terms
end

function _parse_polynomial_term(term::AbstractString)
    source = String(term)
    isempty(source) && throw(ArgumentError("empty polynomial term"))

    sign = 1 // 1
    if startswith(source, "+")
        source = source[nextind(source, firstindex(source)):lastindex(source)]
    elseif startswith(source, "-")
        sign = -1 // 1
        source = source[nextind(source, firstindex(source)):lastindex(source)]
    end
    isempty(source) && throw(ArgumentError("empty polynomial term"))

    variable_count = count(==('t'), source)
    if variable_count == 0
        return sign * _parse_rational_string(source, "polynomial term"), 0
    elseif variable_count > 1
        throw(ArgumentError("polynomial term has more than one variable occurrence: $term"))
    end

    variable_index = findfirst(==('t'), source)
    coefficient_text = variable_index == firstindex(source) ? "" :
                       source[firstindex(source):prevind(source, variable_index)]
    exponent_text = variable_index == lastindex(source) ? "" :
                    source[nextind(source, variable_index):lastindex(source)]

    if endswith(coefficient_text, "*")
        coefficient_text = coefficient_text[firstindex(coefficient_text):prevind(coefficient_text,
                                                                                 lastindex(coefficient_text))]
        isempty(coefficient_text) &&
            throw(ArgumentError("missing coefficient before `*` in term: $term"))
    end

    coefficient = isempty(coefficient_text) ? 1 // 1 :
                  _parse_rational_string(coefficient_text, "polynomial term coefficient")

    exponent = if isempty(exponent_text)
        1
    elseif startswith(exponent_text, "^")
        raw_exponent = exponent_text[nextind(exponent_text, firstindex(exponent_text)):lastindex(exponent_text)]
        occursin(r"^\d+$", raw_exponent) ||
            throw(ArgumentError("invalid polynomial exponent in term: $term"))
        parse(Int, raw_exponent)
    else
        throw(ArgumentError("invalid polynomial term suffix: $term"))
    end

    return sign * coefficient, exponent
end

function _strip_enclosing_parentheses(source::AbstractString)
    text = strip(String(source))
    while startswith(text, "(") && endswith(text, ")") && _outer_parentheses_cover(text)
        text = text[nextind(text, firstindex(text)):prevind(text, lastindex(text))]
    end
    return text
end

function _outer_parentheses_cover(source::AbstractString)
    depth = 0
    for i in eachindex(source)
        char = source[i]
        if char == '('
            depth += 1
        elseif char == ')'
            depth -= 1
            depth < 0 && return false
            if depth == 0 && i != lastindex(source)
                return false
            end
        end
    end
    return depth == 0
end

function _find_rational_function_divider(source::AbstractString)
    depth = 0
    for i in eachindex(source)
        char = source[i]
        if char == '('
            depth += 1
        elseif char == ')'
            depth -= 1
            depth >= 0 ||
                throw(ArgumentError("unbalanced parentheses in rational function: $source"))
        elseif char == '/' && depth == 0
            previous = i == firstindex(source) ? '\0' : source[prevind(source, i)]
            next = i == lastindex(source) ? '\0' : source[nextind(source, i)]
            if !(isdigit(previous) && isdigit(next))
                return i
            end
        end
    end
    depth == 0 ||
        throw(ArgumentError("unbalanced parentheses in rational function: $source"))
    return nothing
end

function _common_root(a::AlgebraicElement, b::AlgebraicElement)
    a.root == b.root ||
        throw(ArgumentError("algebraic operations require the same root representation"))
    return a.root
end

function _common_algebraic_root(elements::AbstractVector)
    isempty(elements) &&
        throw(ArgumentError("at least one algebraic element is required to determine the root representation"))
    first_element = elements[begin]
    first_element isa AlgebraicElement || throw(ArgumentError("expected AlgebraicElement"))
    root = first_element.root
    for element in elements
        element isa AlgebraicElement || throw(ArgumentError("expected AlgebraicElement"))
        element.root == root ||
            throw(ArgumentError("algebraic elements must share the same root representation"))
    end
    return root
end

function _polynomial_string(p::UnivariatePolynomial)
    iszero(p) && return "0"

    terms = String[]
    for exponent in reverse(0:degree(p))
        coefficient = _coefficient(p, exponent)
        iszero(coefficient) && continue

        abs_coefficient = abs(coefficient)
        sign_text = isempty(terms) ? (coefficient < 0 ? "-" : "") :
                    (coefficient < 0 ? " - " : " + ")
        body = _polynomial_term_body(abs_coefficient, exponent)
        push!(terms, sign_text * body)
    end

    return join(terms, "")
end

function _polynomial_term_body(coefficient::Rational{BigInt}, exponent::Integer)
    if exponent == 0
        return _rational_string(coefficient)
    end

    monomial = exponent == 1 ? "t" : "t^$exponent"
    coefficient == 1 // 1 && return monomial
    return _rational_string(coefficient) * "*" * monomial
end

function _rational_function_string(numerator::UnivariatePolynomial,
                                   denominator::UnivariatePolynomial)
    if denominator == UnivariatePolynomial(1)
        return string(numerator)
    end
    return "(" * string(numerator) * ")/(" * string(denominator) * ")"
end
