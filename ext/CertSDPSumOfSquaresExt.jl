module CertSDPSumOfSquaresExt

using CertSDP
import CertSDP: certify_sos, extract_sos_gram_sdp

using JuMP: JuMP
import MultivariatePolynomials as MP
import SumOfSquares as SOS

"""
    extract_sos_gram_sdp(gram::SumOfSquares.GramMatrix; polynomial=nothing)

Optional SumOfSquares frontend. It converts a SumOfSquares Gram matrix into
CertSDP's exact `SOSGramProblem` plus Gram matrix. The Gram entries and
polynomial coefficients must be reconstructable as rationals; numerical solver
rounding remains outside the trusted verifier.
"""
function extract_sos_gram_sdp(gram::SOS.GramMatrix; polynomial=nothing,
                              reconstruct_floats::Bool=false,
                              tolerance=nothing,
                              max_denominator::Integer=CertSDP.DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR)
    variables = _certsdp_sos_variables(gram)
    basis = [_certsdp_exponents(monomial, variables) for monomial in gram.basis.monomials]
    target = isnothing(polynomial) ? MP.polynomial(gram) : polynomial
    terms = _certsdp_polynomial_terms(target, variables;
                                      reconstruct_floats,
                                      tolerance,
                                      max_denominator)
    problem = CertSDP.SOSGramProblem(Symbol.(string.(variables)), basis, terms)
    return (;
            problem,
            gram_matrix=_certsdp_gram_matrix(gram;
                                             reconstruct_floats,
                                             tolerance,
                                             max_denominator),)
end

"""
    extract_sos_gram_sdp(cref::JuMP.ConstraintRef; gram_matrix=nothing)

Extract the target polynomial, Gram basis, coefficient-matching metadata source,
and rational Gram matrix for a SumOfSquares constraint. If the model has not
been optimized, pass an exact `gram_matrix` explicitly.
"""
function extract_sos_gram_sdp(cref::JuMP.ConstraintRef; gram_matrix=nothing,
                              reconstruct_floats::Bool=false,
                              tolerance=nothing,
                              max_denominator::Integer=CertSDP.DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR)
    object = JuMP.constraint_object(cref)
    polynomial = _certsdp_constraint_polynomial(object)
    variables = collect(MP.variables(polynomial))

    gram = if isnothing(gram_matrix)
        _certsdp_constraint_gram_matrix(cref; require_solved=true)
    else
        _certsdp_gram_from_constraint_basis(object, gram_matrix)
    end

    basis_variables = _certsdp_sos_variables(gram)
    if Set(string.(basis_variables)) != Set(string.(variables))
        variables = _certsdp_merge_variables(variables, basis_variables)
    end
    basis = [_certsdp_exponents(monomial, variables) for monomial in gram.basis.monomials]
    terms = _certsdp_polynomial_terms(polynomial, variables;
                                      reconstruct_floats,
                                      tolerance,
                                      max_denominator)
    problem = CertSDP.SOSGramProblem(Symbol.(string.(variables)), basis, terms)
    return (;
            problem,
            gram_matrix=_certsdp_gram_matrix(gram;
                                             reconstruct_floats,
                                             tolerance,
                                             max_denominator),)
end

"""
    extract_sos_gram_sdp(model::JuMP.Model; gram_matrices=nothing)

Extract all SOS constraints from a SumOfSquares/JuMP model. A single SOS
constraint returns one `(problem, gram_matrix)` pair. Multiple constraints return
a vector of pairs for callers that want to certify each block separately.
"""
function extract_sos_gram_sdp(model::JuMP.GenericModel; gram_matrices=nothing,
                              reconstruct_floats::Bool=false,
                              tolerance=nothing,
                              max_denominator::Integer=CertSDP.DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR)
    refs = _certsdp_sos_constraint_refs(model)
    isempty(refs) &&
        throw(ArgumentError("JuMP model contains no SumOfSquares SOS constraints to extract"))
    if isnothing(gram_matrices)
        _certsdp_require_solved_model(model)
        extracted = [extract_sos_gram_sdp(ref;
                                          reconstruct_floats,
                                          tolerance,
                                          max_denominator)
                     for ref in refs]
    else
        length(gram_matrices) == length(refs) ||
            throw(ArgumentError("gram_matrices has length $(length(gram_matrices)); expected $(length(refs))"))
        extracted = [extract_sos_gram_sdp(ref;
                                          gram_matrix=gram_matrices[i],
                                          reconstruct_floats,
                                          tolerance,
                                          max_denominator)
                     for (i, ref) in enumerate(refs)]
    end
    return length(extracted) == 1 ? extracted[1] : extracted
end

function certify_sos(model::JuMP.GenericModel; gram_matrices=nothing,
                     reconstruct_floats::Bool=false,
                     tolerance=nothing,
                     max_denominator::Integer=CertSDP.DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR)
    extracted = extract_sos_gram_sdp(model;
                                     gram_matrices,
                                     reconstruct_floats,
                                     tolerance,
                                     max_denominator)
    if extracted isa AbstractVector
        return [CertSDP.certify_sos(item.problem, item.gram_matrix) for item in extracted]
    end
    return CertSDP.certify_sos(extracted.problem, extracted.gram_matrix)
end

function _certsdp_sos_variables(gram::SOS.GramMatrix)
    return collect(MP.variables(gram))
end

function _certsdp_polynomial_terms(polynomial, variables;
                                   reconstruct_floats::Bool=false,
                                   tolerance=nothing,
                                   max_denominator::Integer=CertSDP.DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR)
    terms = CertSDP.PolynomialTerm[]
    for term in MP.terms(polynomial)
        coefficient = _certsdp_exact_rational(MP.coefficient(term);
                                              reconstruct_floats,
                                              tolerance,
                                              max_denominator,
                                              path="polynomial coefficient")
        iszero(coefficient) && continue
        push!(terms,
              CertSDP.PolynomialTerm(_certsdp_exponents(term, variables), coefficient))
    end
    return terms
end

function _certsdp_exponents(term, variables)
    raw_exponents = MP.exponents(term)
    term_variables = collect(MP.variables(term))
    length(term_variables) == length(raw_exponents) ||
        throw(ArgumentError("cannot align monomial exponents from SumOfSquares frontend"))

    by_variable = Dict(string(variable) => Int(exponent)
                       for (variable, exponent) in zip(term_variables, raw_exponents))
    return [get(by_variable, string(variable), 0) for variable in variables]
end

function _certsdp_exact_rational(value;
                                 reconstruct_floats::Bool=false,
                                 tolerance=nothing,
                                 max_denominator::Integer=CertSDP.DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR,
                                 path::AbstractString="value")
    if value isa Integer
        return Rational{BigInt}(BigInt(value), BigInt(1))
    elseif value isa Rational
        return Rational{BigInt}(BigInt(numerator(value)), BigInt(denominator(value)))
    elseif value isa AbstractFloat
        reconstruct_floats ||
            throw(ArgumentError("SOS Gram extraction found floating-point $path; call with reconstruct_floats=true and an explicit tolerance to build a rational candidate"))
        return CertSDP.reconstruct_rational_value(value;
                                                  tolerance,
                                                  max_denominator,
                                                  path)
    end
    throw(ArgumentError("SOS Gram extraction only accepts exact integer/rational coefficients; got $(typeof(value))"))
end

function _certsdp_exact_rational(value::JuMP.GenericAffExpr; kwargs...)
    isempty(value.terms) ||
        throw(ArgumentError("SOS polynomial coefficient contains JuMP decision variables; provide an exact solved target polynomial before certification"))
    return _certsdp_exact_rational(value.constant; kwargs...)
end

function _certsdp_exact_rational(value::JuMP.AbstractVariableRef; kwargs...)
    throw(ArgumentError("SOS polynomial coefficient contains JuMP variable `$value`; provide an exact solved target polynomial before certification"))
end

function _certsdp_gram_matrix(gram::SOS.GramMatrix;
                              reconstruct_floats::Bool=false,
                              tolerance=nothing,
                              max_denominator::Integer=CertSDP.DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR)
    Q = SOS.value_matrix(gram)
    return [_certsdp_exact_rational(Q[i, j];
                                    reconstruct_floats,
                                    tolerance,
                                    max_denominator,
                                    path="Gram matrix entry ($i,$j)")
            for i in axes(Q, 1), j in axes(Q, 2)]
end

function _certsdp_constraint_gram_matrix(cref::JuMP.ConstraintRef;
                                         require_solved::Bool=false)
    require_solved && _certsdp_require_solved_model(JuMP.owner_model(cref))
    try
        return SOS.gram_matrix(cref)
    catch err
        throw(ArgumentError("could not obtain a solved SumOfSquares Gram matrix for constraint `$(JuMP.name(cref))`; pass `gram_matrix=` explicitly for exact certification. Original error: $(sprint(showerror, err))"))
    end
end

function _certsdp_require_solved_model(model::JuMP.GenericModel)
    result_count = try
        JuMP.result_count(model)
    catch err
        throw(ArgumentError("could not determine whether the SumOfSquares model has solver results; pass exact gram_matrices explicitly. Original error: $(sprint(showerror, err))"))
    end
    result_count > 0 ||
        throw(ArgumentError("SumOfSquares model has no solver result; optimize the model first or pass exact gram_matrices explicitly"))
    return true
end

function _certsdp_constraint_polynomial(object)
    hasproperty(object, :func) ||
        throw(ArgumentError("unsupported SumOfSquares constraint object without `func`"))
    hasproperty(object, :shape) ||
        throw(ArgumentError("unsupported SumOfSquares constraint object without polynomial shape"))
    shape = object.shape
    hasproperty(shape, :monomials) ||
        throw(ArgumentError("unsupported SumOfSquares constraint shape without monomials"))
    polynomial = MP.polynomial(object.func, shape.monomials)
    if hasproperty(object, :set) && hasproperty(object.set, :certificate) &&
       hasproperty(object.set, :domain)
        polynomial = SOS.Certificate.reduced_polynomial(object.set.certificate,
                                                        polynomial,
                                                        object.set.domain)
    end
    return polynomial
end

function _certsdp_gram_from_constraint_basis(object, gram_matrix)
    polynomial = _certsdp_constraint_polynomial(object)
    gram_basis = if hasproperty(object, :set) && hasproperty(object.set, :certificate)
        domain_polynomial = hasproperty(object.set, :domain) ?
                            SOS.Certificate.with_variables(polynomial,
                                                           object.set.domain) :
                            polynomial
        SOS.Certificate.gram_basis(object.set.certificate, domain_polynomial)
    else
        throw(ArgumentError("cannot infer a Gram basis for this SumOfSquares constraint; pass a SumOfSquares.GramMatrix instead"))
    end
    return SOS.GramMatrix(gram_matrix, gram_basis.monomials)
end

function _certsdp_merge_variables(a, b)
    result = collect(a)
    seen = Set(string.(result))
    for variable in b
        key = string(variable)
        key in seen && continue
        push!(result, variable)
        push!(seen, key)
    end
    return result
end

function _certsdp_sos_constraint_refs(model::JuMP.GenericModel)
    refs = JuMP.ConstraintRef[]
    for (F, S) in JuMP.list_of_constraint_types(model)
        S <: SOS.SOSPolynomialSet || continue
        append!(refs, JuMP.all_constraints(model, F, S))
    end
    return refs
end

end
