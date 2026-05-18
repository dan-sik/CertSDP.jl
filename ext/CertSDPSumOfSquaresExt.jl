module CertSDPSumOfSquaresExt

using CertSDP
import CertSDP: certify_sos, extract_sos_gram_sdp
import MathOptInterface as MOI

using JuMP: JuMP
using MultivariatePolynomials: MultivariatePolynomials
using MultivariateBases: MultivariateBases
using SumOfSquares: SumOfSquares

const MP = MultivariatePolynomials
const MB = MultivariateBases
const SOS = SumOfSquares

# ---------------------------------------------------------------------------
# Constraint attributes
# ---------------------------------------------------------------------------

"""
    Problem(; multiplier_index = 1,
             result_index = 1,
             reconstruct_floats = false,
             tolerance = nothing,
             max_denominator = ...)

`MOI.AbstractConstraintAttribute` returning a NamedTuple
`(; problem, gram_matrix)` where `problem` is a CertSDP `SOSGramProblem` and
`gram_matrix` the corresponding rational Gram matrix.

The getter for `SumOfSquares.Bridges.Variable.KernelBridge` reads the target
polynomial basis from `bridge.set.basis`, the evaluated polynomial coefficients
via `MOI.ConstraintPrimal`, the gram basis from
`bridge.set.gram_bases[multiplier_index]` and the Gram matrix via
`SumOfSquares.GramMatrixAttribute`.
"""
Base.@kwdef struct Problem <: MOI.AbstractConstraintAttribute
    multiplier_index::Int = 1
    result_index::Int = 1
    reconstruct_floats::Bool = false
    tolerance::Union{Nothing,Real} = nothing
    max_denominator::Integer = CertSDP.DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR
end

"""
    SOSCertificate(; multiplier_index = 1,
                    result_index = 1,
                    reconstruct_floats = false,
                    tolerance = nothing,
                    max_denominator = ...)

`MOI.AbstractConstraintAttribute` returning a `CertSDP.CertifiedResult` for a
SumOfSquares constraint: the getter queries `Problem` and applies
`CertSDP.certify_sos` to the extracted problem and rational Gram matrix.
"""
Base.@kwdef struct SOSCertificate <: MOI.AbstractConstraintAttribute
    multiplier_index::Int = 1
    result_index::Int = 1
    reconstruct_floats::Bool = false
    tolerance::Union{Nothing,Real} = nothing
    max_denominator::Integer = CertSDP.DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR
end

MOI.is_set_by_optimize(::Union{Problem,SOSCertificate}) = true

function MOI.get(
    model::MOI.ModelLike,
    attr::Problem,
    bridge::SOS.Bridges.Variable.KernelBridge{T,M},
) where {T,M}
    SOS.check_multiplier_index_bounds(
        SOS.GramMatrixAttribute(;
            multiplier_index = attr.multiplier_index,
            result_index = attr.result_index,
        ),
        eachindex(bridge.constraints),
    )
    set = bridge.set
    target_monos = MB.keys_as_monomials(set.basis)
    target_coeffs = MOI.get(model, MOI.ConstraintPrimal(attr.result_index), bridge)
    gram = MOI.get(
        model,
        SOS.GramMatrixAttribute(;
            multiplier_index = attr.multiplier_index,
            result_index = attr.result_index,
        ),
        bridge,
    )
    gram_monos = MB.keys_as_monomials(set.gram_bases[attr.multiplier_index])
    return _build_problem(
        attr, target_monos, target_coeffs, gram_monos, SOS.value_matrix(gram),
    )
end

function MOI.get(
    model::MOI.ModelLike,
    attr::SOSCertificate,
    bridge::SOS.Bridges.Variable.KernelBridge,
)
    extracted = MOI.get(
        model,
        Problem(;
            multiplier_index = attr.multiplier_index,
            result_index = attr.result_index,
            reconstruct_floats = attr.reconstruct_floats,
            tolerance = attr.tolerance,
            max_denominator = attr.max_denominator,
        ),
        bridge,
    )
    return CertSDP.certify_sos(extracted.problem, extracted.gram_matrix)
end

# ---------------------------------------------------------------------------
# Public API — per-constraint convenience wrappers
# ---------------------------------------------------------------------------

function extract_sos_gram_sdp(
    cref::JuMP.ConstraintRef;
    gram_matrix = nothing,
    reconstruct_floats::Bool = false,
    tolerance = nothing,
    max_denominator::Integer = CertSDP.DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR,
)
    attr = Problem(; reconstruct_floats, tolerance, max_denominator)
    if isnothing(gram_matrix)
        return MOI.get(JuMP.owner_model(cref), attr, cref)
    end
    target_monos, target_coeffs, gram_monos = _constraint_data(cref)
    return _build_problem(attr, target_monos, target_coeffs, gram_monos, gram_matrix)
end

function certify_sos(
    cref::JuMP.ConstraintRef;
    gram_matrix = nothing,
    reconstruct_floats::Bool = false,
    tolerance = nothing,
    max_denominator::Integer = CertSDP.DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR,
)
    if isnothing(gram_matrix)
        attr = SOSCertificate(; reconstruct_floats, tolerance, max_denominator)
        return MOI.get(JuMP.owner_model(cref), attr, cref)
    end
    extracted = extract_sos_gram_sdp(
        cref;
        gram_matrix,
        reconstruct_floats,
        tolerance,
        max_denominator,
    )
    return CertSDP.certify_sos(extracted.problem, extracted.gram_matrix)
end

function extract_sos_gram_sdp(
    gram::SOS.GramMatrix;
    polynomial = nothing,
    reconstruct_floats::Bool = false,
    tolerance = nothing,
    max_denominator::Integer = CertSDP.DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR,
)
    attr = Problem(; reconstruct_floats, tolerance, max_denominator)
    target = isnothing(polynomial) ? MP.polynomial(gram) : polynomial
    return _build_problem(
        attr,
        MP.monomials(target),
        MP.coefficients(target),
        MB.keys_as_monomials(gram.basis),
        SOS.value_matrix(gram),
    )
end

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

function _build_problem(attr::Problem, target_monos, target_coeffs, gram_monos, Q)
    variables = _merge_variables(target_monos, gram_monos)
    terms = CertSDP.PolynomialTerm[]
    for (mono, coeff) in zip(target_monos, target_coeffs)
        rcoeff = _exact_rational(coeff, attr; path = "polynomial coefficient")
        iszero(rcoeff) && continue
        push!(terms, CertSDP.PolynomialTerm(_exponents(mono, variables), rcoeff))
    end
    basis_exponents = [_exponents(mono, variables) for mono in gram_monos]
    problem = CertSDP.SOSGramProblem(
        Symbol.(string.(variables)),
        basis_exponents,
        terms,
    )
    gram_matrix = [
        _exact_rational(Q[i, j], attr; path = "Gram matrix entry ($i,$j)") for
        i in axes(Q, 1), j in axes(Q, 2)
    ]
    return (; problem, gram_matrix)
end

function _constraint_data(cref::JuMP.ConstraintRef)
    object = JuMP.constraint_object(cref)
    set = object.set
    basis = object.shape.basis
    poly_element = MB.algebra_element(
        MB.sparse_coefficients(
            MP.polynomial(object.func, MB.keys_as_monomials(basis)),
        ),
        MB.implicit_basis(basis),
    )
    reduced = SOS.Certificate.reduced_polynomial(
        set.certificate, poly_element, set.domain,
    )
    gram_basis = SOS.Certificate.gram_basis(
        set.certificate,
        SOS.Certificate.with_variables(reduced, set.domain),
    )
    poly = MP.polynomial(reduced)
    return MP.monomials(poly), MP.coefficients(poly), MB.keys_as_monomials(gram_basis)
end

function _merge_variables(target_monos, gram_monos)
    vars = collect(MP.variables(target_monos))
    seen = Set(string.(vars))
    for v in MP.variables(gram_monos)
        key = string(v)
        key in seen && continue
        push!(vars, v)
        push!(seen, key)
    end
    return vars
end

function _exact_rational(value, attr::Problem; path::AbstractString = "value")
    return _exact_rational(
        value;
        reconstruct_floats = attr.reconstruct_floats,
        tolerance = attr.tolerance,
        max_denominator = attr.max_denominator,
        path,
    )
end

function _exact_rational(
    value;
    reconstruct_floats::Bool = false,
    tolerance = nothing,
    max_denominator::Integer = CertSDP.DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR,
    path::AbstractString = "value",
)
    if value isa Integer
        return Rational{BigInt}(BigInt(value), BigInt(1))
    elseif value isa Rational
        return Rational{BigInt}(
            BigInt(numerator(value)),
            BigInt(denominator(value)),
        )
    elseif value isa AbstractFloat
        reconstruct_floats || throw(
            ArgumentError(
                "SOS Gram extraction found floating-point $path; call with `reconstruct_floats=true` and an explicit `tolerance` to build a rational candidate",
            ),
        )
        return CertSDP.reconstruct_rational_value(
            value;
            tolerance,
            max_denominator,
            path,
        )
    end
    throw(
        ArgumentError(
            "SOS Gram extraction only accepts exact integer/rational coefficients; got $(typeof(value))",
        ),
    )
end

function _exact_rational(value::JuMP.GenericAffExpr; kwargs...)
    isempty(value.terms) || throw(
        ArgumentError(
            "SOS polynomial coefficient contains JuMP decision variables; provide an exact solved target polynomial before certification",
        ),
    )
    return _exact_rational(value.constant; kwargs...)
end

function _exact_rational(value::JuMP.AbstractVariableRef; kwargs...)
    return throw(
        ArgumentError(
            "SOS polynomial coefficient contains JuMP variable `$value`; provide an exact solved target polynomial before certification",
        ),
    )
end

function _exponents(term, variables)
    by_variable = Dict{String,Int}()
    for (v, e) in zip(MP.variables(term), MP.exponents(term))
        by_variable[string(v)] = Int(e)
    end
    return [get(by_variable, string(v), 0) for v in variables]
end

end
