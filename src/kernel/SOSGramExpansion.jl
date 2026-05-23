module SOSGramExpansion

using ..Kernel

export polynomial_dict,
       gram_polynomial,
       multiply_polynomials,
       sparse_sos_identity_polynomial,
       localizing_polynomial,
       polynomial_payload,
       polynomial_equal

const PolyDict = Dict{Vector{Int}, Rational{BigInt}}

function polynomial_dict(terms::AbstractVector{Kernel.PolynomialTerm})
    result = PolyDict()
    for term in terms
        key = copy(term.exponents)
        result[key] = get(result, key, 0//1) + term.coefficient
        iszero(result[key]) && delete!(result, key)
    end
    return result
end

function _add_monomials(a::Vector{Int}, b::Vector{Int})
    length(a) == length(b) || throw(DimensionMismatch("monomial exponent lengths differ"))
    return [a[i] + b[i] for i in eachindex(a)]
end

function _add_term!(poly::PolyDict, exponents::Vector{Int}, coeff::Rational{BigInt})
    iszero(coeff) && return poly
    key = copy(exponents)
    poly[key] = get(poly, key, 0//1) + coeff
    iszero(poly[key]) && delete!(poly, key)
    return poly
end

function gram_polynomial(block::Kernel.SparseSOSBlock)
    n_basis = length(block.basis_exponents)
    block.gram_matrix.n == n_basis ||
        throw(ArgumentError("Gram matrix dimension does not match monomial basis"))
    result = PolyDict()
    for (i, j, value) in block.gram_matrix.entries
        1 <= i <= n_basis && 1 <= j <= n_basis ||
            throw(ArgumentError("Gram entry index outside monomial basis"))
        coeff = i == j ? value : 2 * value
        exp = _add_monomials(block.basis_exponents[i], block.basis_exponents[j])
        _add_term!(result, exp, coeff)
    end
    return result
end

function multiply_polynomials(a::PolyDict, b::PolyDict)
    result = PolyDict()
    for (ea, ca) in a, (eb, cb) in b
        _add_term!(result, _add_monomials(ea, eb), ca * cb)
    end
    return result
end

function localizing_polynomial(localizing::Kernel.LocalizingMatrixProof)
    return multiply_polynomials(gram_polynomial(localizing.sos_block),
                                polynomial_dict(localizing.constraint_terms))
end

function sparse_sos_identity_polynomial(cert::Kernel.SparseSOSCertificate)
    result = PolyDict()
    for block in cert.sos_blocks
        for (exp, coeff) in gram_polynomial(block)
            _add_term!(result, exp, coeff)
        end
    end
    if !isnothing(cert.putinar)
        for localizing in cert.putinar.localizing_blocks
            for (exp, coeff) in localizing_polynomial(localizing)
                _add_term!(result, exp, coeff)
            end
        end
    end
    return result
end

polynomial_equal(a::PolyDict, b::PolyDict) = a == b

function polynomial_payload(poly::PolyDict)
    entries = [(exp, coeff) for (exp, coeff) in poly]
    sort!(entries; by=item -> (item[1], string(item[2])))
    return [Dict("exponents" => exp,
                 "coefficient" => Kernel.rational_string(coeff))
            for (exp, coeff) in entries]
end

end

