const POLYNOMIAL_RING_BACKEND = :internal_sparse_qq

"""
    PolynomialRingAdapter(vars; backend=:internal_sparse_qq)

Store a small exact multivariate polynomial ring over `QQ` with a stable
variable order. CertSDP uses an internal sparse adapter instead of binding the
core IR to an external CAS; backend adapters can translate this object to
msolve or other solvers.
"""
struct PolynomialRingAdapter
    variables::Vector{Symbol}
    backend::Symbol

    function PolynomialRingAdapter(vars::AbstractVector{Symbol};
                                   backend::Symbol=POLYNOMIAL_RING_BACKEND)
        backend === POLYNOMIAL_RING_BACKEND ||
            throw(ArgumentError("unsupported polynomial ring backend `$backend`; expected `$POLYNOMIAL_RING_BACKEND`"))

        variable_names = collect(vars)
        isempty(variable_names) &&
            throw(ArgumentError("polynomial ring must have at least one variable"))
        for (i, name) in enumerate(variable_names)
            isempty(String(name)) &&
                throw(ArgumentError("variable name at index $i must not be empty"))
        end
        length(unique(variable_names)) == length(variable_names) ||
            throw(ArgumentError("polynomial ring variable names must be unique"))

        return new(variable_names, backend)
    end
end

function PolynomialRingAdapter(vars::AbstractVector{<:AbstractString};
                               backend::Symbol=POLYNOMIAL_RING_BACKEND)
    return PolynomialRingAdapter(Symbol.(vars); backend)
end

"""
    PolynomialVariable

A variable in a `PolynomialRingAdapter`. Variables remember their ring and
1-based position, so monomial display and export preserve the original order.
"""
struct PolynomialVariable
    ring::PolynomialRingAdapter
    index::Int

    function PolynomialVariable(ring::PolynomialRingAdapter, index::Integer)
        1 <= index <= length(ring.variables) ||
            throw(ArgumentError("variable index $index is out of range for $(length(ring.variables)) variables"))
        return new(ring, Int(index))
    end
end

"""
    MultivariatePolynomial

Sparse exact polynomial over a `PolynomialRingAdapter`. Terms are stored as
`exponents => coefficient`, where exponents follow the ring variable order and
coefficients are exact `Rational{BigInt}` values.
"""
struct MultivariatePolynomial
    ring::PolynomialRingAdapter
    terms::Dict{Tuple{Vararg{Int}}, Rational{BigInt}}

    function MultivariatePolynomial(ring::PolynomialRingAdapter, terms::AbstractDict)
        normalized = Dict{Tuple{Vararg{Int}}, Rational{BigInt}}()
        expected_length = length(ring.variables)

        for (raw_exponents, raw_coefficient) in terms
            exponents = _normalize_monomial_exponents(raw_exponents, expected_length)
            coefficient = _to_big_rational(raw_coefficient; name=:polynomial_coefficient)
            iszero(coefficient) && continue
            normalized[exponents] = get(normalized, exponents, 0 // 1) + coefficient
            if iszero(normalized[exponents])
                delete!(normalized, exponents)
            end
        end

        return new(ring, normalized)
    end
end

"""
    PolynomialSystem(ring, equations; metadata=Dict())

Internal representation for a polynomial system over `QQ`. Equations are
normalized into `MultivariatePolynomial`s over the same ring, and metadata is
copied so construction preserves the system description without aliasing the
caller's outer dictionary.
"""
struct PolynomialSystem
    ring::PolynomialRingAdapter
    variables::Vector{PolynomialVariable}
    equations::Vector{MultivariatePolynomial}
    metadata::Dict{Symbol, Any}

    function PolynomialSystem(ring::PolynomialRingAdapter,
                              equations::AbstractVector;
                              metadata=Dict{Symbol, Any}(),)
        normalized_equations = MultivariatePolynomial[
                                                      _as_polynomial_in_ring(ring, equation,
                                                                             "equations[$i]")
                                                      for (i, equation) in
                                                          enumerate(equations)
                                                      ]
        return new(ring, variables(ring), normalized_equations, _metadata_dict(metadata))
    end
end

"""
    polynomial_ring(vars...) -> PolynomialRingAdapter

Create an exact sparse `QQ` polynomial ring with variables in the given order.
"""
polynomial_ring(vars::Symbol...; backend::Symbol=POLYNOMIAL_RING_BACKEND) = PolynomialRingAdapter(collect(vars);
                                                                                                  backend)
function polynomial_ring(vars::AbstractVector; backend::Symbol=POLYNOMIAL_RING_BACKEND)
    return PolynomialRingAdapter(_symbol_vector(vars); backend)
end

"""
    variables(ring) -> Vector{PolynomialVariable}

Return polynomial variables in the ring's stable order.
"""
variables(ring::PolynomialRingAdapter) = [PolynomialVariable(ring, i)
                                          for i in eachindex(ring.variables)]
variables(system::PolynomialSystem) = copy(system.variables)

"""
    variable_symbols(ring_or_system) -> Vector{Symbol}

Return the stable variable order as symbols.
"""
variable_symbols(ring::PolynomialRingAdapter) = copy(ring.variables)
variable_symbols(system::PolynomialSystem) = variable_symbols(system.ring)

"""
    constant_polynomial(ring, value)

Create a constant polynomial over `ring`.
"""
function constant_polynomial(ring::PolynomialRingAdapter, value::Union{Integer, Rational})
    coefficient = _to_big_rational(value; name=:constant)
    iszero(coefficient) &&
        return MultivariatePolynomial(ring, Dict{Tuple{Vararg{Int}}, Rational{BigInt}}())
    return MultivariatePolynomial(ring, Dict(_zero_exponents(ring) => coefficient))
end

"""
    zero_polynomial(ring)

Create the zero polynomial over `ring`.
"""
zero_polynomial(ring::PolynomialRingAdapter) = constant_polynomial(ring, 0)

"""
    monomial(ring, coefficient, exponents)

Create `coefficient * prod(variables[i]^exponents[i])`.
"""
function monomial(ring::PolynomialRingAdapter, coefficient::Union{Integer, Rational},
                  exponents)
    return MultivariatePolynomial(ring,
                                  Dict(_normalize_monomial_exponents(exponents, length(ring.variables)) => coefficient))
end

"""
    polynomial_system_text(system) -> String

Export a stable, human-readable text representation of a polynomial system.
This is intentionally not a solver input format; backend-specific writers are
implemented separately so this diagnostic representation stays stable.
"""
function polynomial_system_text(system::PolynomialSystem; include_metadata::Bool=true)
    io = IOBuffer()
    println(io, "PolynomialSystem")
    println(io, "ring: ", _ring_string(system.ring))
    println(io, "variables:")
    for (i, variable) in enumerate(system.variables)
        println(io, "  ", i, ": ", variable)
    end
    println(io, "equations:")
    if isempty(system.equations)
        println(io, "  (none)")
    else
        for (i, equation) in enumerate(system.equations)
            println(io, "  f", i, " = ", equation)
        end
    end

    if include_metadata && !isempty(system.metadata)
        println(io, "metadata:")
        for key in sort(collect(keys(system.metadata)); by=String)
            println(io, "  ", key, " = ", repr(system.metadata[key]))
        end
    end

    return String(take!(io))
end

"""
    polynomial_system_hash(system) -> String

Stable SHA-256 identity for an exact polynomial system. It includes the ring
variable order, equations, and metadata so optional backend result caches are
tied to the precise system they solved.
"""
function polynomial_system_hash(system::PolynomialSystem)
    payload = (;
               backend=String(system.ring.backend),
               variables=String.(variable_symbols(system)),
               equations=[_multivariate_polynomial_cache_json(equation)
                          for equation in system.equations],
               metadata=_certification_diagnostics_json(system.metadata),)
    return "sha256:" * bytes2hex(sha256(JSON3.write(payload)))
end

"""
    write_polynomial_system_text(path, system)

Write `polynomial_system_text(system)` to a file and return `path`.
"""
function write_polynomial_system_text(path::AbstractString, system::PolynomialSystem;
                                      kwargs...)
    open(path, "w") do io
        return write(io, polynomial_system_text(system; kwargs...))
    end
    return path
end

function Base.:(==)(a::PolynomialRingAdapter, b::PolynomialRingAdapter)
    return a.backend == b.backend && a.variables == b.variables
end
function Base.:(==)(a::PolynomialVariable, b::PolynomialVariable)
    return a.ring == b.ring && a.index == b.index
end
function Base.:(==)(a::MultivariatePolynomial, b::MultivariatePolynomial)
    return a.ring == b.ring && a.terms == b.terms
end

Base.iszero(p::MultivariatePolynomial) = isempty(p.terms)
Base.zero(p::MultivariatePolynomial) = zero_polynomial(p.ring)
Base.one(p::MultivariatePolynomial) = constant_polynomial(p.ring, 1)

function Base.:+(a::MultivariatePolynomial, b::MultivariatePolynomial)
    ring = _common_polynomial_ring(a, b)
    terms = copy(a.terms)
    for (exponents, coefficient) in b.terms
        terms[exponents] = get(terms, exponents, 0 // 1) + coefficient
        if iszero(terms[exponents])
            delete!(terms, exponents)
        end
    end
    return MultivariatePolynomial(ring, terms)
end

Base.:+(a::MultivariatePolynomial, b::PolynomialVariable) = a + _variable_polynomial(b)
Base.:+(a::PolynomialVariable, b::MultivariatePolynomial) = _variable_polynomial(a) + b
function Base.:+(a::PolynomialVariable, b::PolynomialVariable)
    return _variable_polynomial(a) + _variable_polynomial(b)
end
function Base.:+(a::MultivariatePolynomial, b::Union{Integer, Rational})
    return a + constant_polynomial(a.ring, b)
end
function Base.:+(a::Union{Integer, Rational}, b::MultivariatePolynomial)
    return constant_polynomial(b.ring, a) + b
end
Base.:+(a::PolynomialVariable, b::Union{Integer, Rational}) = _variable_polynomial(a) + b
Base.:+(a::Union{Integer, Rational}, b::PolynomialVariable) = a + _variable_polynomial(b)

function Base.:-(a::MultivariatePolynomial)
    return MultivariatePolynomial(a.ring,
                                  Dict(exponents => -coefficient
                                       for (exponents, coefficient) in a.terms))
end
Base.:-(a::PolynomialVariable) = -_variable_polynomial(a)
Base.:-(a::MultivariatePolynomial, b::MultivariatePolynomial) = a + (-b)
Base.:-(a::MultivariatePolynomial, b::PolynomialVariable) = a - _variable_polynomial(b)
Base.:-(a::PolynomialVariable, b::MultivariatePolynomial) = _variable_polynomial(a) - b
function Base.:-(a::PolynomialVariable, b::PolynomialVariable)
    return _variable_polynomial(a) - _variable_polynomial(b)
end
function Base.:-(a::MultivariatePolynomial, b::Union{Integer, Rational})
    return a - constant_polynomial(a.ring, b)
end
function Base.:-(a::Union{Integer, Rational}, b::MultivariatePolynomial)
    return constant_polynomial(b.ring, a) - b
end
Base.:-(a::PolynomialVariable, b::Union{Integer, Rational}) = _variable_polynomial(a) - b
Base.:-(a::Union{Integer, Rational}, b::PolynomialVariable) = a - _variable_polynomial(b)

function Base.:*(a::MultivariatePolynomial, b::MultivariatePolynomial)
    ring = _common_polynomial_ring(a, b)
    iszero(a) && return zero_polynomial(ring)
    iszero(b) && return zero_polynomial(ring)

    terms = Dict{Tuple{Vararg{Int}}, Rational{BigInt}}()
    for (a_exponents, a_coefficient) in a.terms, (b_exponents, b_coefficient) in b.terms
        exponents = tuple((a_exponents[i] + b_exponents[i] for i in eachindex(a_exponents))...)
        terms[exponents] = get(terms, exponents, 0 // 1) + a_coefficient * b_coefficient
        if iszero(terms[exponents])
            delete!(terms, exponents)
        end
    end
    return MultivariatePolynomial(ring, terms)
end

Base.:*(a::MultivariatePolynomial, b::PolynomialVariable) = a * _variable_polynomial(b)
Base.:*(a::PolynomialVariable, b::MultivariatePolynomial) = _variable_polynomial(a) * b
function Base.:*(a::PolynomialVariable, b::PolynomialVariable)
    return _variable_polynomial(a) * _variable_polynomial(b)
end
function Base.:*(a::MultivariatePolynomial, b::Union{Integer, Rational})
    return a * constant_polynomial(a.ring, b)
end
function Base.:*(a::Union{Integer, Rational}, b::MultivariatePolynomial)
    return constant_polynomial(b.ring, a) * b
end
Base.:*(a::PolynomialVariable, b::Union{Integer, Rational}) = _variable_polynomial(a) * b
Base.:*(a::Union{Integer, Rational}, b::PolynomialVariable) = a * _variable_polynomial(b)

function Base.:^(p::MultivariatePolynomial, exponent::Integer)
    exponent >= 0 || throw(ArgumentError("polynomial exponent must be nonnegative"))
    result = constant_polynomial(p.ring, 1)
    base = p
    n = exponent
    while n > 0
        if isodd(n)
            result *= base
        end
        base *= base
        n = div(n, 2)
    end
    return result
end

function Base.:^(variable::PolynomialVariable, exponent::Integer)
    return _variable_polynomial(variable)^exponent
end

function Base.show(io::IO, ring::PolynomialRingAdapter)
    return print(io, _ring_string(ring))
end

function Base.show(io::IO, variable::PolynomialVariable)
    return print(io, String(variable.ring.variables[variable.index]))
end

function Base.show(io::IO, polynomial::MultivariatePolynomial)
    return print(io, _multivariate_polynomial_string(polynomial))
end

function Base.show(io::IO, system::PolynomialSystem)
    return print(io, "PolynomialSystem(", length(system.equations), " equations over ",
                 _ring_string(system.ring), ")")
end

function _symbol_vector(vars::AbstractVector)
    return Symbol[
                  if value isa Symbol
                      value
                  elseif value isa AbstractString
                      Symbol(String(value))
                  else
                      throw(ArgumentError("polynomial ring variables must be symbols or strings"))
                  end
                  for value in vars
                  ]
end

function _normalize_monomial_exponents(raw_exponents, expected_length::Integer)
    raw_exponents isa Tuple || raw_exponents isa AbstractVector ||
        throw(ArgumentError("monomial exponents must be a tuple or vector"))
    length(raw_exponents) == expected_length ||
        throw(ArgumentError("monomial exponent length $(length(raw_exponents)) does not match variable count $expected_length"))

    exponents = Int[]
    for (i, exponent) in enumerate(raw_exponents)
        exponent isa Integer ||
            throw(ArgumentError("monomial exponent $i must be an integer"))
        exponent >= 0 || throw(ArgumentError("monomial exponent $i must be nonnegative"))
        push!(exponents, Int(exponent))
    end
    return tuple(exponents...)
end

function _zero_exponents(ring::PolynomialRingAdapter)
    return ntuple(_ -> 0, length(ring.variables))
end

function _variable_polynomial(variable::PolynomialVariable)
    exponents = fill(0, length(variable.ring.variables))
    exponents[variable.index] = 1
    return monomial(variable.ring, 1, exponents)
end

function _common_polynomial_ring(a::MultivariatePolynomial, b::MultivariatePolynomial)
    a.ring == b.ring ||
        throw(ArgumentError("polynomial operations require the same polynomial ring"))
    return a.ring
end

function _as_polynomial_in_ring(ring::PolynomialRingAdapter, value, path::AbstractString)
    if value isa MultivariatePolynomial
        value.ring == ring ||
            throw(ArgumentError("$path belongs to a different polynomial ring"))
        return value
    elseif value isa PolynomialVariable
        value.ring == ring ||
            throw(ArgumentError("$path belongs to a different polynomial ring"))
        return _variable_polynomial(value)
    elseif value isa Integer || value isa Rational
        return constant_polynomial(ring, value)
    end
    throw(ArgumentError("$path must be a polynomial, variable, integer, or rational"))
end

function _metadata_dict(metadata)
    if metadata isa NamedTuple
        return Dict{Symbol, Any}(Symbol(key) => value for (key, value) in pairs(metadata))
    elseif metadata isa AbstractDict
        result = Dict{Symbol, Any}()
        for (key, value) in metadata
            if key isa Symbol
                result[key] = value
            elseif key isa AbstractString
                result[Symbol(String(key))] = value
            else
                throw(ArgumentError("metadata keys must be symbols or strings"))
            end
        end
        return result
    end
    throw(ArgumentError("metadata must be a dictionary or named tuple"))
end

function _ring_string(ring::PolynomialRingAdapter)
    return "QQ[" * join(String.(ring.variables), ", ") * "]"
end

function _sorted_monomial_exponents(polynomial::MultivariatePolynomial)
    return sort(collect(keys(polynomial.terms)); lt=_monomial_order_lt)
end

function _monomial_order_lt(a::Tuple, b::Tuple)
    total_a = sum(a)
    total_b = sum(b)
    total_a != total_b && return total_a > total_b

    for i in eachindex(a)
        a[i] == b[i] && continue
        return a[i] > b[i]
    end
    return false
end

function _multivariate_polynomial_string(polynomial::MultivariatePolynomial)
    iszero(polynomial) && return "0"

    terms = String[]
    for exponents in _sorted_monomial_exponents(polynomial)
        coefficient = polynomial.terms[exponents]
        abs_coefficient = abs(coefficient)
        sign_text = isempty(terms) ? (coefficient < 0 ? "-" : "") :
                    (coefficient < 0 ? " - " : " + ")
        push!(terms,
              sign_text *
              _multivariate_term_body(polynomial.ring, abs_coefficient, exponents))
    end
    return join(terms, "")
end

function _multivariate_polynomial_cache_json(polynomial::MultivariatePolynomial)
    return [(;
             exponents=collect(exponents),
             coefficient=_rational_string(polynomial.terms[exponents]),)
            for exponents in _sorted_monomial_exponents(polynomial)]
end

function _multivariate_term_body(ring::PolynomialRingAdapter, coefficient::Rational{BigInt},
                                 exponents::Tuple)
    factors = String[]
    for (variable_name, exponent) in zip(ring.variables, exponents)
        exponent == 0 && continue
        push!(factors,
              exponent == 1 ? String(variable_name) : string(variable_name, "^", exponent))
    end

    isempty(factors) && return _rational_string(coefficient)
    monomial_text = join(factors, "*")
    coefficient == 1 // 1 && return monomial_text
    return _rational_string(coefficient) * "*" * monomial_text
end
