const SOS_GRAM_PROBLEM_TYPE = "sos_gram_feasibility"
const SOS_GRAM_CERTIFICATE_TYPE = "sos_gram_certificate"
const SOS_GRAM_SOLUTION_TYPE = "rational_gram_matrix"
const SOS_DECOMPOSITION_SQUARES = "rational_squares"
const SOS_DECOMPOSITION_GRAM_ONLY = "gram_only"
const DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR = 1_000_000
const DEFAULT_SOS_FOUR_SQUARE_MAX_ROOT = 1_000

"""
    reconstruct_rational_value(value; tolerance, max_denominator, path="value")

Explicitly reconstruct a floating-point scalar as a nearby rational. Exact
integer/rational inputs are returned exactly. Floating-point inputs require a
caller-supplied `tolerance`; this helper is never used implicitly by the
trusted verifier.
"""
function reconstruct_rational_value(value;
                                    tolerance=nothing,
                                    max_denominator::Integer=DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR,
                                    path::AbstractString="value")
    max_denominator > 0 ||
        throw(ArgumentError("max_denominator must be positive"))
    if value isa Integer || value isa Rational
        return _to_big_rational(value; name=Symbol(replace(path, r"[^A-Za-z0-9_]" => "_")))
    elseif value isa AbstractFloat
        isfinite(value) ||
            throw(ArgumentError("$path is not finite and cannot be rationalized"))
        isnothing(tolerance) &&
            throw(ArgumentError("$path is floating-point data; pass an explicit tolerance to reconstruct it as a rational candidate"))
        tolerance >= 0 ||
            throw(ArgumentError("tolerance must be nonnegative"))
        candidate = rationalize(BigInt, value; tol=tolerance)
        denominator(candidate) <= max_denominator ||
            throw(ArgumentError("$path reconstructed denominator $(denominator(candidate)) exceeds max_denominator $max_denominator"))
        error = abs(BigFloat(value) - BigFloat(candidate))
        error <= BigFloat(tolerance) ||
            throw(ArgumentError("$path reconstruction error $error exceeds tolerance $tolerance"))
        return Rational{BigInt}(candidate)
    elseif value isa Real
        value == trunc(value) ||
            throw(ArgumentError("$path must be an integer-valued JSON number for exact reconstruction; got $value"))
        return Rational{BigInt}(BigInt(value), BigInt(1))
    end
    throw(ArgumentError("$path must be exact integer/rational data or an explicitly reconstructed finite float; got $(typeof(value))"))
end

"""
    reconstruct_rational_gram_matrix(matrix; tolerance, max_denominator)

Explicitly reconstruct a finite floating-point Gram candidate as a symmetric
rational matrix. This is a convenience for solver output; certification still
requires exact coefficient matching and exact PSD verification afterward.
"""
function reconstruct_rational_gram_matrix(matrix::AbstractMatrix;
                                          tolerance=nothing,
                                          max_denominator::Integer=DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR)
    entries = [reconstruct_rational_value(matrix[i, j];
                                          tolerance,
                                          max_denominator,
                                          path="gram_matrix[$i,$j]")
               for i in axes(matrix, 1), j in axes(matrix, 2)]
    return SymmetricRationalMatrix(entries; name=:reconstructed_gram_matrix)
end

"""
    PolynomialTerm(exponents, coefficient)

One exact term in a small multivariate polynomial used by the SOS Gram
frontend. Exponents follow the `SOSGramProblem.variables` order.
"""
struct PolynomialTerm
    exponents::Vector{Int}
    coefficient::Rational{BigInt}

    function PolynomialTerm(exponents::AbstractVector{<:Integer}, coefficient)
        normalized_exponents = Int[]
        for (i, exponent) in enumerate(exponents)
            exponent >= 0 ||
                throw(ArgumentError("polynomial term exponent $i must be nonnegative"))
            push!(normalized_exponents, Int(exponent))
        end
        return new(normalized_exponents,
                   _to_big_rational(coefficient; name=:polynomial_term_coefficient))
    end
end

"""
    SOSGramContribution(i, j, multiplier, gram_entry)

One exact contribution to a coefficient-matching equation. For a symmetric Gram
matrix, off-diagonal entries contribute `2Q[i,j]` to `v'Qv`.
"""
struct SOSGramContribution
    i::Int
    j::Int
    multiplier::Int
    gram_entry::Rational{BigInt}
    contribution::Rational{BigInt}

    function SOSGramContribution(i::Integer, j::Integer, multiplier::Integer,
                                 gram_entry)
        1 <= i <= j ||
            throw(ArgumentError("SOS Gram contribution indices must satisfy 1 <= i <= j"))
        multiplier in (1, 2) ||
            throw(ArgumentError("SOS Gram contribution multiplier must be 1 or 2"))
        entry = _to_big_rational(gram_entry; name=:gram_entry)
        return new(Int(i), Int(j), Int(multiplier), entry, Int(multiplier) * entry)
    end
end

function Base.:(==)(a::SOSGramContribution, b::SOSGramContribution)
    return a.i == b.i && a.j == b.j && a.multiplier == b.multiplier &&
           a.gram_entry == b.gram_entry && a.contribution == b.contribution
end

"""
    SOSCoefficientMatch(exponents, target, gram, contributions)

Exact coefficient-matching metadata for one monomial exponent:
`target == sum(contribution for contribution in contributions)`.
"""
struct SOSCoefficientMatch
    exponents::Vector{Int}
    target_coefficient::Rational{BigInt}
    gram_coefficient::Rational{BigInt}
    contributions::Vector{SOSGramContribution}

    function SOSCoefficientMatch(exponents::AbstractVector{<:Integer}, target,
                                 gram, contributions::AbstractVector)
        normalized_exponents = Int[]
        for (i, exponent) in enumerate(exponents)
            exponent >= 0 ||
                throw(ArgumentError("coefficient match exponent $i must be nonnegative"))
            push!(normalized_exponents, Int(exponent))
        end
        entries = SOSGramContribution[contributions...]
        return new(normalized_exponents,
                   _to_big_rational(target; name=:target_coefficient),
                   _to_big_rational(gram; name=:gram_coefficient),
                   entries)
    end
end

function Base.:(==)(a::SOSCoefficientMatch, b::SOSCoefficientMatch)
    return a.exponents == b.exponents &&
           a.target_coefficient == b.target_coefficient &&
           a.gram_coefficient == b.gram_coefficient &&
           a.contributions == b.contributions
end

"""
    SOSSquare(terms)

One exact rational polynomial square `q(x)^2` in an exported SOS
decomposition.
"""
struct SOSSquare
    terms::Vector{PolynomialTerm}

    function SOSSquare(terms::AbstractVector, variable_count::Integer)
        normalized = _normalize_polynomial_terms(terms, variable_count)
        isempty(normalized) &&
            throw(ArgumentError("SOS square polynomial must not be zero"))
        return new(normalized)
    end
end

Base.:(==)(a::SOSSquare, b::SOSSquare) = _sos_polynomial_terms_equal(a.terms, b.terms)

"""
    SOSDecomposition(status, method, squares, reason)

Optional exact rational square export. If `status == :gram_only`, the Gram
certificate remains valid but no square decomposition is claimed.
"""
struct SOSDecomposition
    status::Symbol
    method::String
    squares::Vector{SOSSquare}
    reason::String

    function SOSDecomposition(status::Symbol, method::AbstractString,
                              squares::AbstractVector{SOSSquare},
                              reason::AbstractString="")
        status in (:squares, :gram_only) ||
            throw(ArgumentError("SOS decomposition status must be :squares or :gram_only"))
        status === :squares && isempty(squares) &&
            throw(ArgumentError("SOS square decomposition must contain at least one square"))
        status === :gram_only && !isempty(squares) &&
            throw(ArgumentError("Gram-only decomposition must not contain squares"))
        return new(status, String(method), SOSSquare[squares...], String(reason))
    end
end

function Base.:(==)(a::SOSDecomposition, b::SOSDecomposition)
    return a.status == b.status && a.method == b.method && a.squares == b.squares &&
           a.reason == b.reason
end

"""
    SOSGramProblem(variables, basis, polynomial)

Represent an exported SOS Gram problem

```text
p(y) = v(y)' * Q * v(y),  Q >= 0
```

where the monomial basis `v` and target polynomial `p` are exact rational data.
This core type intentionally has no hard dependency on SumOfSquares.jl or JuMP.
"""
struct SOSGramProblem
    variables::Vector{Symbol}
    basis::Vector{Vector{Int}}
    polynomial::Vector{PolynomialTerm}
    lmi::LMIProblem

    function SOSGramProblem(variables::AbstractVector, basis::AbstractVector,
                            polynomial::AbstractVector)
        variable_names = _sos_variable_symbols(variables)
        basis_exponents = [_sos_exponent_vector(entry, length(variable_names), "basis[$i]")
                           for (i, entry) in enumerate(basis)]
        isempty(basis_exponents) && throw(ArgumentError("SOS Gram basis must not be empty"))
        length(unique(basis_exponents)) == length(basis_exponents) ||
            throw(ArgumentError("SOS Gram basis monomials must be unique"))

        terms = _normalize_polynomial_terms(polynomial, length(variable_names))
        lmi = _sos_lmi_problem(length(basis_exponents))
        return new(variable_names, basis_exponents, terms, lmi)
    end
end

"""
    SOSGramCertificate(problem, gram_matrix)

Certificate that a rational Gram matrix exactly represents the exported SOS
polynomial and is positive semidefinite. The embedded LMI certificate proves
the PSD part using the existing Type R verifier.
"""
struct SOSGramCertificate
    problem::SOSGramProblem
    gram_matrix::SymmetricRationalMatrix
    lmi_certificate::RationalCertificate
    coefficient_proof::Vector{SOSCoefficientMatch}
    decomposition::SOSDecomposition
    hash::String
end

function SOSGramCertificate(problem::SOSGramProblem, gram_matrix)
    Q = _as_symmetric_rational_matrix(gram_matrix, :gram_matrix)
    size(Q) == (length(problem.basis), length(problem.basis)) ||
        throw(DimensionMismatch("Gram matrix has size $(size(Q)); expected $((length(problem.basis), length(problem.basis)))"))
    _sos_polynomial_terms_equal(_sos_polynomial_from_gram_matrix(problem, Q),
                                problem.polynomial) ||
        throw(ArgumentError("Gram matrix does not exactly match the target polynomial"))
    psd_plan = choose_psd_proof(Q, nothing; method=:auto)
    psd_plan.status === :accepted ||
        throw(ArgumentError("Gram matrix is not positive semidefinite over QQ"))

    solution = _sos_solution_from_gram_matrix(Q)
    lmi_cert = RationalCertificate(problem.lmi, solution; psd_method=:auto)
    coefficient_matches = coefficient_matching_metadata(problem, Q)
    decomposition = _sos_decomposition_from_gram_matrix(problem, Q)
    cert_without_hash = SOSGramCertificate(problem, Q, lmi_cert, coefficient_matches,
                                           decomposition, "")
    return SOSGramCertificate(problem, Q, lmi_cert, coefficient_matches,
                              decomposition,
                              sos_gram_certificate_hash(cert_without_hash))
end

"""
    build_sos_gram_problem(variables, basis, polynomial) -> SOSGramProblem

Build an exact exported Gram SDP from rational polynomial data. `basis` is a
list of exponent vectors and `polynomial` is either `PolynomialTerm`s or
`(exponents, coefficient)` pairs.
"""
build_sos_gram_problem(variables, basis, polynomial) = SOSGramProblem(variables, basis,
                                                                      polynomial)

"""
    extract_sos_gram_sdp(args...; kwargs...)

Placeholder for optional frontend extensions. The core package supports
exported Gram SDP JSON without loading SumOfSquares/JuMP. When the optional
extension is available, methods are added for SumOfSquares Gram matrices and
constraint references.
"""
function extract_sos_gram_sdp(args...; kwargs...)
    throw(ArgumentError("no SOS frontend extractor is available for these arguments; load SumOfSquares/JuMP or use exported SOS Gram JSON"))
end

"""
    certify_sos(problem, gram_matrix) -> CertifiedResult or FailureResult

Build and verify a minimal rational Gram certificate for an exported SOS Gram
problem.
"""
function certify_sos(problem::SOSGramProblem, gram_matrix)
    result = try
        CertifiedResult(SOSGramCertificate(problem, gram_matrix))
    catch err
        FailureResult(_sos_certification_failure(problem, gram_matrix, err))
    end
    return result
end

function certify_sos(path::AbstractString, gram_matrix=nothing)
    problem = parse_sos_gram_json(read(path, String))
    if isnothing(gram_matrix)
        throw(ArgumentError("certify_sos(path) needs a Gram matrix; use the CLI or pass `gram_matrix` explicitly"))
    end
    return certify_sos(problem, gram_matrix)
end

"""
    certify_sos(model_or_constraint_or_gram; kwargs...)

Use an available optional frontend, such as SumOfSquares.jl, to extract an
exact Gram SDP plus rational Gram matrix, then build an independently
verifiable SOS certificate.
"""
function certify_sos(source; kwargs...)
    extracted = extract_sos_gram_sdp(source; kwargs...)
    if extracted isa SOSGramCertificate
        return CertifiedResult(extracted)
    elseif extracted isa NamedTuple && haskey(extracted, :problem) &&
           haskey(extracted, :gram_matrix)
        return certify_sos(extracted.problem, extracted.gram_matrix)
    elseif extracted isa Tuple && length(extracted) == 2
        return certify_sos(extracted[1], extracted[2])
    end
    throw(ArgumentError("SOS extractor must return `(problem, gram_matrix)`, a named tuple with `problem` and `gram_matrix`, or an SOSGramCertificate"))
end

function _sos_certification_failure(problem::SOSGramProblem, gram_matrix, err)
    diagnostics = Dict{Symbol, Any}(:exception_type => string(typeof(err)),
                                    :message => sprint(showerror, err),
                                    :basis_size => length(problem.basis),
                                    :polynomial_terms => length(problem.polynomial))
    Q = try
        _as_symmetric_rational_matrix(gram_matrix, :gram_matrix)
    catch parse_err
        diagnostics[:matrix_error] = sprint(showerror, parse_err)
        return CertificationFailure(:sos_matching_failed,
                                    "SOS Gram matrix could not be parsed as an exact symmetric rational matrix",
                                    :sos_matching,
                                    diagnostics)
    end

    diagnostics[:gram_size] = string(size(Q))
    coefficient_ok = try
        _sos_polynomial_terms_equal(_sos_polynomial_from_gram_matrix(problem, Q),
                                    problem.polynomial)
    catch coeff_err
        diagnostics[:coefficient_error] = sprint(showerror, coeff_err)
        false
    end
    diagnostics[:coefficient_matching] = coefficient_ok

    if !coefficient_ok
        return CertificationFailure(:sos_matching_failed,
                                    "Gram matrix does not exactly match the target SOS polynomial",
                                    :sos_matching,
                                    diagnostics)
    end

    psd_ok = try
        choose_psd_proof(Q, nothing; method=:auto).status === :accepted
    catch psd_err
        diagnostics[:psd_error] = sprint(showerror, psd_err)
        false
    end
    diagnostics[:psd_verified] = psd_ok
    if !psd_ok
        return CertificationFailure(:sos_matching_failed,
                                    "Gram matrix matches coefficients but is not positive semidefinite over QQ",
                                    :sos_psd,
                                    diagnostics)
    end

    return CertificationFailure(:sos_certificate_failed,
                                sprint(showerror, err),
                                :sos_certificate,
                                diagnostics)
end

"""
    verify_sos(cert; io=nothing) -> Bool

Verify an SOS Gram certificate by exact coefficient matching and exact PSD.
"""
verify_sos(cert::SOSGramCertificate; io::Union{Nothing, IO}=nothing, kwargs...) = verify(cert;
                                                                                         io,
                                                                                         kwargs...)

function verify_sos(path::AbstractString; io::Union{Nothing, IO}=nothing, kwargs...)
    cert = read_certificate(path)
    cert isa SOSGramCertificate ||
        throw(ArgumentError("certificate at `$path` is not an SOS Gram certificate"))
    return verify_sos(cert; io, kwargs...)
end

"""
    gram_matrix_from_solution(problem, x) -> SymmetricRationalMatrix

Rebuild the Gram matrix associated with the triangular LMI coordinates of an
exported SOS Gram problem.
"""
function gram_matrix_from_solution(problem::SOSGramProblem, x::AbstractVector)
    return _as_symmetric_rational_matrix(substitute(problem.lmi, x), :gram_matrix)
end

"""
    verify_sos_gram_matrix(problem, Q) -> Bool

Check exact coefficient matching `p == v'Qv` and exact rational PSD for a Gram
matrix. No numerical evidence is accepted.
"""
function verify_sos_gram_matrix(problem::SOSGramProblem, gram_matrix;
                                max_size::Integer=DEFAULT_MAX_PSD_PRINCIPAL_MINOR_SIZE)
    Q = _as_symmetric_rational_matrix(gram_matrix, :gram_matrix)
    size(Q) == (length(problem.basis), length(problem.basis)) || return false
    _sos_polynomial_terms_equal(_sos_polynomial_from_gram_matrix(problem, Q),
                                problem.polynomial) || return false
    return choose_psd_proof(Q, nothing; method=:auto, max_size).status === :accepted
end

"""
    coefficient_matching_metadata(problem, Q) -> Vector{SOSCoefficientMatch}

Return the exact coefficient-matching equations for `p == v'Qv`, including the
individual Gram entries contributing to each monomial.
"""
function coefficient_matching_metadata(problem::SOSGramProblem, gram_matrix)
    Q = _as_symmetric_rational_matrix(gram_matrix, :gram_matrix)
    return _sos_coefficient_matches(problem, Q)
end

"""
    export_sos_decomposition(cert) -> NamedTuple

Return a data-only exact SOS export. When rational square reconstruction is not
safe, the export falls back to the verified Gram certificate.
"""
function export_sos_decomposition(cert::SOSGramCertificate)
    verify_sos(cert) || throw(ArgumentError("cannot export an unverified SOS certificate"))
    if cert.decomposition.status === :squares
        return (;
                type=SOS_DECOMPOSITION_SQUARES,
                variables=String.(cert.problem.variables),
                squares=[_sos_terms_json(square.terms)
                         for square in
                             cert.decomposition.squares],
                polynomial=_sos_terms_json(cert.problem.polynomial),
                certificate_id=cert.hash,)
    end
    return (;
            type=SOS_DECOMPOSITION_GRAM_ONLY,
            variables=String.(cert.problem.variables),
            basis=[_sos_exponent_entry_json(entry) for entry in cert.problem.basis],
            gram_matrix=_json_matrix(cert.gram_matrix),
            polynomial=_sos_terms_json(cert.problem.polynomial),
            reason=cert.decomposition.reason,
            certificate_id=cert.hash,)
end

function export_sos_decomposition(path::AbstractString)
    cert = read_certificate(path)
    cert isa SOSGramCertificate ||
        throw(ArgumentError("certificate at `$path` is not an SOS Gram certificate"))
    return export_sos_decomposition(cert)
end

"""
    sos_decomposition_text(cert) -> String

Human-readable exact SOS decomposition, or a compact Gram form when square
reconstruction is unavailable.
"""
function sos_decomposition_text(cert::SOSGramCertificate)
    verify_sos(cert) || throw(ArgumentError("cannot export an unverified SOS certificate"))
    if cert.decomposition.status === :squares
        pieces = ["(" * _sos_polynomial_text(square.terms, cert.problem.variables) * ")^2"
                  for square in cert.decomposition.squares]
        return _sos_polynomial_text(cert.problem.polynomial, cert.problem.variables) *
               " = " * join(pieces, " + ")
    end
    return _sos_polynomial_text(cert.problem.polynomial, cert.problem.variables) *
           " = v'Qv with v = [" *
           join([_sos_monomial_text(exponents, cert.problem.variables)
                 for exponents in cert.problem.basis], ", ") *
           "] and verified Q >= 0 over QQ"
end

"""
    sos_decomposition_latex(cert) -> String

Return a LaTeX equality for the verified SOS decomposition, or a compact Gram
form when CertSDP intentionally kept the certificate Gram-only.
"""
function sos_decomposition_latex(cert::SOSGramCertificate)
    verify_sos(cert) || throw(ArgumentError("cannot export an unverified SOS certificate"))
    lhs = _sos_polynomial_latex(cert.problem.polynomial, cert.problem.variables)
    if cert.decomposition.status === :squares
        pieces = ["\\left(" * _sos_polynomial_latex(square.terms, cert.problem.variables) *
                  "\\right)^2" for square in cert.decomposition.squares]
        return lhs * " = " * join(pieces, " + ")
    end
    basis = join([_sos_monomial_latex(exponents, cert.problem.variables)
                  for exponents in cert.problem.basis], ", ")
    return lhs * " = v^{T} Q v,\\quad v = \\left[" * basis *
           "\\right],\\quad Q \\succeq 0"
end

"""
    sos_decomposition_sage(cert) -> String

Return a SageMath replay script for the verified SOS equality. The generated
script is an export convenience; CertSDP's verifier remains the authority.
"""
function sos_decomposition_sage(cert::SOSGramCertificate)
    verify_sos(cert) || throw(ArgumentError("cannot export an unverified SOS certificate"))
    vars = String.(cert.problem.variables)
    io = IOBuffer()
    println(io, "R = PolynomialRing(QQ, ", repr(vars), ")")
    println(io, join(vars, ", "), " = R.gens()")
    println(io, "lhs = ",
            _sos_polynomial_code(cert.problem.polynomial, vars; power="^",
                                 rational="/"))
    if cert.decomposition.status === :squares
        pieces = ["(" * _sos_polynomial_code(square.terms, vars; power="^",
                                             rational="/") * ")^2"
                  for square in cert.decomposition.squares]
        println(io, "rhs = ", join(pieces, " + "))
    else
        println(io, "basis = [",
                join([_sos_monomial_code(exponents, vars; power="^")
                      for exponents in cert.problem.basis], ", "), "]")
        println(io, "Q = Matrix(QQ, ",
                _sos_rational_matrix_code(cert.gram_matrix; rational="/"), ")")
        println(io, "rhs = vector(basis).row() * Q * vector(basis).column()")
        println(io, "rhs = rhs[0, 0]")
    end
    println(io, "assert lhs == rhs")
    return String(take!(io))
end

"""
    sos_decomposition_julia(cert) -> String

Return a Julia/DynamicPolynomials replay snippet for the verified SOS equality.
"""
function sos_decomposition_julia(cert::SOSGramCertificate)
    verify_sos(cert) || throw(ArgumentError("cannot export an unverified SOS certificate"))
    vars = String.(cert.problem.variables)
    io = IOBuffer()
    println(io, "using DynamicPolynomials")
    println(io, "@polyvar ", join(vars, " "))
    println(io, "lhs = ", _sos_polynomial_code(cert.problem.polynomial, vars; power="^"))
    if cert.decomposition.status === :squares
        pieces = ["(" * _sos_polynomial_code(square.terms, vars; power="^") * ")^2"
                  for square in cert.decomposition.squares]
        println(io, "rhs = ", join(pieces, " + "))
    else
        println(io, "basis = Any[",
                join([_sos_monomial_code(exponents, vars; power="^")
                      for exponents in cert.problem.basis], ", "), "]")
        println(io, "Q = ",
                _sos_rational_matrix_code(cert.gram_matrix; rational="//"))
        println(io,
                "rhs = sum(Q[i, j] * basis[i] * basis[j] for i in eachindex(basis), j in eachindex(basis))")
    end
    println(io, "@assert lhs == rhs")
    return String(take!(io))
end

function sos_decomposition_latex(path::AbstractString)
    cert = read_certificate(path)
    cert isa SOSGramCertificate ||
        throw(ArgumentError("certificate at `$path` is not an SOS Gram certificate"))
    return sos_decomposition_latex(cert)
end

function sos_decomposition_sage(path::AbstractString)
    cert = read_certificate(path)
    cert isa SOSGramCertificate ||
        throw(ArgumentError("certificate at `$path` is not an SOS Gram certificate"))
    return sos_decomposition_sage(cert)
end

function sos_decomposition_julia(path::AbstractString)
    cert = read_certificate(path)
    cert isa SOSGramCertificate ||
        throw(ArgumentError("certificate at `$path` is not an SOS Gram certificate"))
    return sos_decomposition_julia(cert)
end

"""
    sos_gram_problem_hash(problem) -> String

Stable hash of the canonical exported SOS Gram problem.
"""
function sos_gram_problem_hash(problem::SOSGramProblem)
    canonical = _canonical_sos_gram_problem_json(problem)
    return "sha256:" * bytes2hex(sha256(JSON3.write(canonical)))
end

function sos_gram_problem_json(problem::SOSGramProblem)
    payload = _canonical_sos_gram_problem_json(problem)
    return (;
            certsdp_problem_version=SCHEMA_V1_VERSION,
            sos_problem=merge(payload, (; hash=sos_gram_problem_hash(problem))),)
end

function sos_gram_problem_json_string(problem::SOSGramProblem)
    io = IOBuffer()
    JSON3.pretty(io, sos_gram_problem_json(problem))
    println(io)
    return String(take!(io))
end

function write_sos_gram_json(path::AbstractString, problem::SOSGramProblem)
    open(path, "w") do io
        return write(io, sos_gram_problem_json_string(problem))
    end
    return path
end

"""
    read_sos_gram_json(path) -> SOSGramProblem

Read an exported exact SOS Gram JSON v0.1 problem from `path`.
"""
read_sos_gram_json(path::AbstractString) = parse_sos_gram_json(read(path, String))

"""
    parse_sos_gram_json(json_text) -> SOSGramProblem

Parse exported exact SOS Gram JSON. A supplied hash is checked against the
canonical problem representation.
"""
function parse_sos_gram_json(json_text::AbstractString)
    parsed = try
        JSON3.read(json_text)
    catch err
        throw(ArgumentError("invalid SOS Gram JSON: $(sprint(showerror, err))"))
    end

    _require_object(parsed, "root")
    if haskey(parsed, :certsdp_problem_version)
        _require_value(parsed, :certsdp_problem_version, SCHEMA_V1_VERSION,
                       "root.certsdp_problem_version")
    else
        _require_value(parsed, :certsdp_version, LMI_JSON_VERSION, "root.certsdp_version")
    end
    problem = _require_key(parsed, :sos_problem, "root")
    return _parse_sos_gram_problem_object(problem)
end

function _parse_sos_gram_problem_object(problem)
    _require_object(problem, "sos_problem")
    _require_value(problem, :type, SOS_GRAM_PROBLEM_TYPE, "sos_problem.type")
    _require_value(problem, :field, LMI_FIELD, "sos_problem.field")

    variables = _parse_sos_variables(_require_key(problem, :variables, "sos_problem"))
    basis = _parse_sos_basis(_require_key(problem, :basis, "sos_problem"),
                             length(variables))
    terms = _parse_sos_polynomial_terms(_require_key(problem, :polynomial, "sos_problem"),
                                        length(variables))
    parsed_problem = SOSGramProblem(variables, basis, terms)

    if haskey(problem, :hash)
        expected_hash = _require_string(problem, :hash, "sos_problem.hash")
        actual_hash = sos_gram_problem_hash(parsed_problem)
        legacy_hash = sos_gram_problem_legacy_hash(parsed_problem)
        (expected_hash == actual_hash || expected_hash == legacy_hash) ||
            throw(ArgumentError("sos_problem.hash mismatch: expected $expected_hash, computed $actual_hash"))
    end

    return parsed_problem
end

function sos_gram_problem_legacy_hash(problem::SOSGramProblem)
    canonical = _canonical_sos_gram_problem_json(problem; include_lmi_problem=true)
    return "sha256:" * bytes2hex(sha256(JSON3.write(canonical)))
end

function sos_gram_certificate_hash(cert::SOSGramCertificate)
    canonical = _canonical_sos_gram_certificate_json(cert)
    return "sha256:" * bytes2hex(sha256(JSON3.write(canonical)))
end

function sos_gram_certificate_json(cert::SOSGramCertificate)
    return merge(_canonical_sos_gram_certificate_json(cert),
                 (;
                  certificate_id=cert.hash,
                  hash=cert.hash,))
end

function sos_gram_certificate_json_string(cert::SOSGramCertificate)
    io = IOBuffer()
    JSON3.pretty(io, sos_gram_certificate_json(cert))
    println(io)
    return String(take!(io))
end

function write_certificate(path::AbstractString, cert::SOSGramCertificate)
    open(path, "w") do io
        return write(io, sos_gram_certificate_json_string(cert))
    end
    return path
end

function save_certificate(path::AbstractString, cert::SOSGramCertificate)
    return write_certificate(path, cert)
end

function _parse_sos_gram_certificate_object(parsed)
    problem = _parse_sos_gram_problem_object(_require_key(parsed, :sos_problem, "root"))

    solution = _require_key(parsed, :solution, "root")
    _require_object(solution, "solution")
    _require_value(solution, :type, SOS_GRAM_SOLUTION_TYPE, "solution.type")
    gram = SymmetricRationalMatrix(_parse_rational_matrix(_require_key(solution,
                                                                       :gram_matrix,
                                                                       "solution"),
                                                          length(problem.basis),
                                                          "solution.gram_matrix");
                                   name=:gram_matrix,)

    lmi_certificate_value = _require_key(parsed, :lmi_certificate, "root")
    lmi_certificate = if haskey(lmi_certificate_value, CERTSDP_CERTIFICATE_VERSION_KEY)
        embedded = _parse_certificate_v1_object(lmi_certificate_value)
        embedded isa RationalCertificate ||
            throw(ArgumentError("root.lmi_certificate must be an embedded rational PSD certificate"))
        embedded
    else
        _parse_rational_certificate_object(lmi_certificate_value)
    end
    coefficient_value = _require_key(parsed, :coefficient_proof, "root")
    coefficient_proof = if _is_legacy_sos_coefficient_proof(coefficient_value)
        _legacy_coefficient_matches(problem, gram,
                                    _parse_sos_coefficient_proof(coefficient_value,
                                                                 length(problem.variables)))
    else
        _parse_sos_coefficient_matches(coefficient_value, length(problem.variables))
    end
    decomposition = haskey(parsed, :decomposition) ?
                    _parse_sos_decomposition(_require_key(parsed, :decomposition,
                                                          "root"),
                                             length(problem.variables)) :
                    _sos_decomposition_from_gram_matrix(problem, gram)
    hash = _require_string(parsed, :hash, "root.hash")

    return SOSGramCertificate(problem, gram, lmi_certificate, coefficient_proof,
                              decomposition, hash)
end

function verify(cert::SOSGramCertificate; io::Union{Nothing, IO}=nothing,
                cache::Bool=true, cache_object=nothing, strict::Bool=false)
    if strict
        return _strict_verify_certificate_object(certificate_json_v1(cert); io,
                                                 cache, cache_object)
    end
    return _with_verification_cache(; cache, cache_object) do
        return _verify_sos_gram_certificate(cert, io)
    end
end

function _verify_sos_gram_certificate(cert::SOSGramCertificate, io::Union{Nothing, IO})
    try
        _check_or_report(io, cert.hash == sos_gram_certificate_hash(cert),
                         "SOS certificate hash matches") || return false
        _check_or_report(io,
                         sos_gram_problem_hash(cert.problem) ==
                         _canonical_sos_problem_hash_from_certificate(cert),
                         "SOS problem hash matches") || return false

        solution = _sos_solution_from_gram_matrix(cert.gram_matrix)
        _check_or_report(io, cert.lmi_certificate.solution == solution,
                         "embedded LMI solution matches Gram matrix") || return false
        _check_or_report(io,
                         lmi_problem_hash(cert.lmi_certificate.problem) ==
                         lmi_problem_hash(cert.problem.lmi),
                         "embedded LMI problem matches Gram PSD cone") || return false
        _check_or_report(io, verify(cert.lmi_certificate),
                         "embedded rational PSD certificate accepted") || return false

        expected_matches = coefficient_matching_metadata(cert.problem, cert.gram_matrix)
        _check_or_report(io,
                         _sos_coefficient_matches_equal(cert.coefficient_proof,
                                                        expected_matches),
                         "SOS coefficient metadata matches recomputation") || return false
        _check_or_report(io,
                         _sos_coefficient_matches_all_exact(cert.coefficient_proof),
                         "SOS coefficient matching is exact") || return false
        expected_terms = _sos_polynomial_from_matches(expected_matches)
        _check_or_report(io,
                         _sos_polynomial_terms_equal(expected_terms,
                                                     cert.problem.polynomial),
                         "Gram polynomial matches target polynomial") || return false
        _check_or_report(io, verify_sos_gram_matrix(cert.problem, cert.gram_matrix),
                         "Gram certificate verified over QQ") || return false
        _check_or_report(io, _verify_sos_decomposition(cert),
                         "SOS decomposition export verified or safely omitted") ||
            return false

        _ok(io, "SOS Gram certificate accepted")
        return true
    catch err
        _fail(io, "SOS Gram certificate verification error: $(sprint(showerror, err))")
        return false
    end
end

function _canonical_sos_gram_problem_json(problem::SOSGramProblem;
                                          include_lmi_problem::Bool=false)
    base = (;
            type=SOS_GRAM_PROBLEM_TYPE,
            field=LMI_FIELD,
            variables=String.(problem.variables),
            basis=[_sos_exponent_entry_json(entry) for entry in problem.basis],
            polynomial=_sos_terms_json(problem.polynomial),)
    include_lmi_problem || return base
    return merge(base,
                 (;
                  lmi_problem=merge(_canonical_lmi_problem_json(problem.lmi),
                                    (; hash=lmi_problem_hash(problem.lmi))),))
end

function _canonical_sos_gram_certificate_json(cert::SOSGramCertificate)
    return (;
            certsdp_certificate_version=SCHEMA_V1_VERSION,
            certificate_type=SOS_GRAM_CERTIFICATE_TYPE,
            problem_hash=sos_gram_problem_hash(cert.problem),
            sos_problem=merge(_canonical_sos_gram_problem_json(cert.problem),
                              (; hash=sos_gram_problem_hash(cert.problem))),
            solution=(;
                      type=SOS_GRAM_SOLUTION_TYPE,
                      gram_matrix=_json_matrix(cert.gram_matrix),),
            coefficient_proof=(;
                               method="exact_coefficient_matching",
                               matches=_sos_coefficient_matches_json(cert.coefficient_proof),),
            decomposition=_sos_decomposition_json(cert.decomposition),
            proof=(;
                   coefficient_matching=(;
                                         method="exact_coefficient_matching",
                                         status="claimed",
                                         equations=length(cert.coefficient_proof),),
                   psd=(;
                        method="embedded_rational_psd_certificate",
                        certificate_id=cert.lmi_certificate.hash,),),
            provenance=(;
                        certsdp_version=string(package_version()),
                        julia_version=string(VERSION),
                        schema_version=SCHEMA_V1_VERSION,
                        source="sos_gram_workflow",),
            verification=(;
                          verifier_version=string(package_version()),
                          verified_at_creation=nothing,),
            lmi_certificate=certificate_json_v1(cert.lmi_certificate),)
end

function _canonical_sos_problem_hash_from_certificate(cert::SOSGramCertificate)
    return _require_string(_canonical_sos_gram_certificate_json(cert).sos_problem, :hash,
                           "sos_problem.hash")
end

function _sos_lmi_problem(n::Integer)
    variables = Symbol[_sos_gram_variable(i, j) for j in 1:n for i in 1:j]
    A0 = zeros(Rational{BigInt}, n, n)
    matrices = Matrix{Rational{BigInt}}[]

    for j in 1:n, i in 1:j
        matrix = zeros(Rational{BigInt}, n, n)
        matrix[i, j] = 1 // 1
        matrix[j, i] = 1 // 1
        push!(matrices, matrix)
    end

    return LMIProblem(A0, matrices; vars=variables)
end

function _sos_gram_variable(i::Integer, j::Integer)
    return Symbol("q", i, "_", j)
end

function _sos_solution_from_gram_matrix(Q::SymmetricRationalMatrix)
    matrix = rational_matrix(Q)
    n = size(matrix, 1)
    return Rational{BigInt}[matrix[i, j] for j in 1:n for i in 1:j]
end

function _sos_polynomial_from_gram_matrix(problem::SOSGramProblem,
                                          Q::SymmetricRationalMatrix)
    matrix = rational_matrix(Q)
    n = length(problem.basis)
    size(matrix) == (n, n) ||
        throw(DimensionMismatch("Gram matrix has size $(size(matrix)); expected $((n, n))"))

    terms = Dict{Tuple{Vararg{Int}}, Rational{BigInt}}()
    for i in 1:n, j in 1:n
        coefficient = matrix[i, j]
        iszero(coefficient) && continue
        exponent = tuple((problem.basis[i][k] + problem.basis[j][k] for k in
                                                                        eachindex(problem.variables))...)
        terms[exponent] = get(terms, exponent, 0 // 1) + coefficient
        if iszero(terms[exponent])
            delete!(terms, exponent)
        end
    end

    return _terms_dict_to_polynomial_terms(terms)
end

function _sos_coefficient_matches(problem::SOSGramProblem, Q::SymmetricRationalMatrix)
    matrix = rational_matrix(Q)
    n = length(problem.basis)
    size(matrix) == (n, n) ||
        throw(DimensionMismatch("Gram matrix has size $(size(matrix)); expected $((n, n))"))

    contributions = Dict{Tuple{Vararg{Int}}, Vector{SOSGramContribution}}()
    for i in 1:n, j in i:n
        coefficient = matrix[i, j]
        iszero(coefficient) && continue
        exponent = tuple((problem.basis[i][k] + problem.basis[j][k] for k in
                                                                        eachindex(problem.variables))...)
        multiplier = i == j ? 1 : 2
        push!(get!(contributions, exponent, SOSGramContribution[]),
              SOSGramContribution(i, j, multiplier, coefficient))
    end

    target_terms = _sos_terms_dict(problem.polynomial)
    exponents = union(Set(keys(target_terms)), Set(keys(contributions)))
    result = SOSCoefficientMatch[]
    for exponent in sort(collect(exponents); lt=_sos_exponent_order_lt)
        contribs = sort!(get(contributions, exponent, SOSGramContribution[]);
                         by=contribution -> (contribution.i, contribution.j))
        gram_coefficient = sum(contribution.contribution for contribution in contribs;
                               init=0 // 1)
        target = get(target_terms, exponent, 0 // 1)
        push!(result,
              SOSCoefficientMatch(collect(exponent), target, gram_coefficient,
                                  contribs))
    end
    return result
end

function _sos_polynomial_from_matches(matches::Vector{SOSCoefficientMatch})
    terms = Dict{Tuple{Vararg{Int}}, Rational{BigInt}}()
    for match in matches
        exponent = tuple(match.exponents...)
        iszero(match.gram_coefficient) && continue
        terms[exponent] = get(terms, exponent, 0 // 1) + match.gram_coefficient
    end
    return _terms_dict_to_polynomial_terms(terms)
end

function _legacy_coefficient_matches(problem::SOSGramProblem, Q::SymmetricRationalMatrix,
                                     terms::Vector{PolynomialTerm})
    matches = _sos_coefficient_matches(problem, Q)
    _sos_polynomial_terms_equal(_sos_polynomial_from_matches(matches), terms) ||
        throw(ArgumentError("legacy SOS coefficient proof polynomial does not match Gram matrix"))
    return matches
end

function _sos_coefficient_matches_equal(a::Vector{SOSCoefficientMatch},
                                        b::Vector{SOSCoefficientMatch})
    return a == b
end

function _sos_coefficient_matches_all_exact(matches::Vector{SOSCoefficientMatch})
    for match in matches
        total = sum(contribution.contribution for contribution in match.contributions;
                    init=0 // 1)
        total == match.gram_coefficient || return false
        match.gram_coefficient == match.target_coefficient || return false
        for contribution in match.contributions
            contribution.contribution ==
            contribution.multiplier * contribution.gram_entry || return false
        end
    end
    return true
end

function _normalize_polynomial_terms(polynomial::AbstractVector, variable_count::Integer)
    terms = Dict{Tuple{Vararg{Int}}, Rational{BigInt}}()
    for (i, entry) in enumerate(polynomial)
        term = _as_polynomial_term(entry, variable_count, "polynomial[$i]")
        exponent = tuple(term.exponents...)
        terms[exponent] = get(terms, exponent, 0 // 1) + term.coefficient
        if iszero(terms[exponent])
            delete!(terms, exponent)
        end
    end
    return _terms_dict_to_polynomial_terms(terms)
end

function _as_polynomial_term(entry::PolynomialTerm, variable_count::Integer,
                             path::AbstractString)
    length(entry.exponents) == variable_count ||
        throw(ArgumentError("$path exponent length $(length(entry.exponents)) does not match variable count $variable_count"))
    return entry
end

function _as_polynomial_term(entry::Tuple, variable_count::Integer, path::AbstractString)
    length(entry) == 2 ||
        throw(ArgumentError("$path tuple term must be `(exponents, coefficient)`"))
    return _as_polynomial_term(PolynomialTerm(entry[1], entry[2]), variable_count, path)
end

function _as_polynomial_term(entry::NamedTuple, variable_count::Integer,
                             path::AbstractString)
    haskey(entry, :exponents) || throw(ArgumentError("$path is missing `exponents`"))
    haskey(entry, :coefficient) || throw(ArgumentError("$path is missing `coefficient`"))
    return _as_polynomial_term(PolynomialTerm(entry.exponents, entry.coefficient),
                               variable_count, path)
end

function _as_polynomial_term(entry, variable_count::Integer, path::AbstractString)
    throw(ArgumentError("$path must be a PolynomialTerm, named tuple, or `(exponents, coefficient)` tuple"))
end

function _terms_dict_to_polynomial_terms(terms::Dict)
    result = PolynomialTerm[]
    for exponents in sort(collect(keys(terms)); lt=_sos_exponent_order_lt)
        coefficient = terms[exponents]
        iszero(coefficient) && continue
        push!(result, PolynomialTerm(collect(exponents), coefficient))
    end
    return result
end

function _sos_exponent_order_lt(a::Tuple, b::Tuple)
    total_a = sum(a)
    total_b = sum(b)
    total_a != total_b && return total_a > total_b
    for i in eachindex(a)
        a[i] == b[i] && continue
        return a[i] > b[i]
    end
    return false
end

function _sos_polynomial_terms_equal(a::Vector{PolynomialTerm}, b::Vector{PolynomialTerm})
    return _sos_terms_dict(a) == _sos_terms_dict(b)
end

function _sos_terms_dict(terms::Vector{PolynomialTerm})
    result = Dict{Tuple{Vararg{Int}}, Rational{BigInt}}()
    for term in terms
        exponent = tuple(term.exponents...)
        result[exponent] = get(result, exponent, 0 // 1) + term.coefficient
        if iszero(result[exponent])
            delete!(result, exponent)
        end
    end
    return result
end

function _sos_decomposition_from_gram_matrix(problem::SOSGramProblem,
                                             Q::SymmetricRationalMatrix)
    matrix = rational_matrix(Q)
    n = length(problem.basis)
    factors = _sos_ldl_rational_linear_forms(matrix)
    isnothing(factors) &&
        return SOSDecomposition(:gram_only, "not_safely_reconstructed", SOSSquare[],
                                "exact LDL factorization did not produce a safe rational square decomposition")

    squares = SOSSquare[]
    used_four_square = false
    for (pivot, form) in factors
        coefficients = _rational_square_coefficients(pivot)
        if isnothing(coefficients)
            return SOSDecomposition(:gram_only, "not_safely_reconstructed",
                                    SOSSquare[],
                                    "positive LDL pivot $(_rational_string(pivot)) was too large to decompose into rational squares within the safety budget")
        end
        used_four_square |= length(coefficients) > 1
        for coefficient in coefficients
            terms = PolynomialTerm[]
            for (basis_index, form_coefficient) in enumerate(form)
                iszero(form_coefficient) && continue
                push!(terms,
                      PolynomialTerm(problem.basis[basis_index],
                                     coefficient * form_coefficient))
            end
            isempty(terms) && continue
            push!(squares, SOSSquare(terms, length(problem.variables)))
        end
    end

    isempty(squares) &&
        return SOSDecomposition(:gram_only, "not_reconstructed", SOSSquare[],
                                "zero Gram matrix has no nonzero square decomposition to export")

    method = used_four_square ? "exact_rational_ldl_four_squares" :
             "exact_rational_ldl_square_pivots"
    decomposition = SOSDecomposition(:squares, method, squares)
    terms = _sos_terms_from_squares(decomposition, length(problem.variables))
    _sos_polynomial_terms_equal(terms, problem.polynomial) ||
        return SOSDecomposition(:gram_only, "not_safely_reconstructed", SOSSquare[],
                                "candidate square decomposition did not exactly match target polynomial")
    return decomposition
end

function _sos_ldl_rational_linear_forms(A::AbstractMatrix{<:Rational})
    entries = _as_psd_rational_matrix(A)
    n = size(entries, 1)
    work = Matrix{Rational{BigInt}}(entries)
    lower = zeros(Rational{BigInt}, n, n)
    for i in 1:n
        lower[i, i] = 1 // 1
    end
    factors = Vector{Tuple{Rational{BigInt}, Vector{Rational{BigInt}}}}()

    for k in 1:n
        pivot = work[k, k]
        pivot < 0 && return nothing
        if iszero(pivot)
            for j in (k + 1):n
                iszero(work[k, j]) || return nothing
            end
            continue
        end

        for i in (k + 1):n
            lower[i, k] = work[i, k] / pivot
        end
        for i in (k + 1):n, j in i:n
            work[i, j] -= work[i, k] * work[k, j] / pivot
            work[j, i] = work[i, j]
        end
        form = Rational{BigInt}[lower[i, k] for i in 1:n]
        push!(factors, (pivot, form))
    end

    return factors
end

function _rational_square_coefficients(value::Rational{BigInt};
                                       max_root::Integer=DEFAULT_SOS_FOUR_SQUARE_MAX_ROOT)
    value < 0 && return nothing
    numerator_root = isqrt(numerator(value))
    denominator_root = isqrt(denominator(value))
    if numerator_root^2 == numerator(value) && denominator_root^2 == denominator(value)
        return Rational{BigInt}[Rational{BigInt}(numerator_root, denominator_root)]
    end

    scaled = numerator(value) * denominator(value)
    scaled < 0 && return nothing
    decomposition = _integer_four_squares(scaled; max_root)
    isnothing(decomposition) && return nothing
    coefficients = Rational{BigInt}[Rational{BigInt}(entry, denominator(value))
                                    for entry in decomposition if !iszero(entry)]
    sum(coefficient^2 for coefficient in coefficients; init=0 // 1) == value ||
        return nothing
    return coefficients
end

function _rational_square_root(value::Rational{BigInt})
    coefficients = _rational_square_coefficients(value)
    isnothing(coefficients) && return nothing
    length(coefficients) == 1 || return nothing
    return only(coefficients)
end

function _integer_four_squares(value::BigInt;
                               max_root::Integer=DEFAULT_SOS_FOUR_SQUARE_MAX_ROOT)
    value < 0 && return nothing
    iszero(value) && return BigInt[0]
    limit_big = isqrt(value)
    limit_big <= BigInt(max_root) || return nothing
    limit = Int(limit_big)

    pair_sums = Dict{BigInt, Tuple{BigInt, BigInt}}()
    for a in 0:limit, b in a:limit
        a_big = BigInt(a)
        b_big = BigInt(b)
        sum_ab = a_big^2 + b_big^2
        sum_ab <= value || continue
        haskey(pair_sums, sum_ab) || (pair_sums[sum_ab] = (a_big, b_big))
    end

    for (sum_ab, (a, b)) in pair_sums
        complement = value - sum_ab
        if haskey(pair_sums, complement)
            c, d = pair_sums[complement]
            return BigInt[a, b, c, d]
        end
    end
    return nothing
end

function _sos_terms_from_squares(decomposition::SOSDecomposition,
                                 variable_count::Integer)
    terms = Dict{Tuple{Vararg{Int}}, Rational{BigInt}}()
    for square in decomposition.squares
        polynomial = _sos_terms_dict(square.terms)
        entries = collect(polynomial)
        for (exp_a, coeff_a) in entries, (exp_b, coeff_b) in entries
            exponent = tuple((exp_a[k] + exp_b[k] for k in 1:variable_count)...)
            terms[exponent] = get(terms, exponent, 0 // 1) + coeff_a * coeff_b
            if iszero(terms[exponent])
                delete!(terms, exponent)
            end
        end
    end
    return _terms_dict_to_polynomial_terms(terms)
end

function _verify_sos_decomposition(cert::SOSGramCertificate)
    if cert.decomposition.status === :gram_only
        return isempty(cert.decomposition.squares) && !isempty(cert.decomposition.reason)
    end
    cert.decomposition.status === :squares || return false
    terms = _sos_terms_from_squares(cert.decomposition, length(cert.problem.variables))
    return _sos_polynomial_terms_equal(terms, cert.problem.polynomial)
end

function _sos_variable_symbols(values::AbstractVector)
    variable_names = Symbol[]
    for (i, value) in enumerate(values)
        name = if value isa Symbol
            value
        elseif value isa AbstractString
            Symbol(String(value))
        else
            throw(ArgumentError("SOS variable $i must be a symbol or string"))
        end
        isempty(String(name)) && throw(ArgumentError("SOS variable $i must not be empty"))
        push!(variable_names, name)
    end
    isempty(variable_names) &&
        throw(ArgumentError("SOS Gram problem must have at least one polynomial variable"))
    length(unique(variable_names)) == length(variable_names) ||
        throw(ArgumentError("SOS polynomial variables must be unique"))
    return variable_names
end

function _sos_exponent_vector(entry, variable_count::Integer, path::AbstractString)
    entry isa AbstractVector || throw(ArgumentError("$path must be an exponent vector"))
    length(entry) == variable_count ||
        throw(ArgumentError("$path has exponent length $(length(entry)); expected $variable_count"))
    result = Int[]
    for (i, exponent) in enumerate(entry)
        exponent isa Integer || throw(ArgumentError("$path[$i] must be an integer"))
        exponent >= 0 || throw(ArgumentError("$path[$i] must be nonnegative"))
        push!(result, Int(exponent))
    end
    return result
end

function _sos_exponent_entry_json(exponents::Vector{Int})
    return copy(exponents)
end

function _sos_terms_json(terms::Vector{PolynomialTerm})
    return [(;
             exponents=copy(term.exponents),
             coefficient=_rational_string(term.coefficient),)
            for term in terms]
end

function _sos_coefficient_matches_json(matches::Vector{SOSCoefficientMatch})
    return [(;
             exponents=copy(match.exponents),
             target_coefficient=_rational_string(match.target_coefficient),
             gram_coefficient=_rational_string(match.gram_coefficient),
             contributions=[(;
                             basis_pair=[contribution.i, contribution.j],
                             multiplier=contribution.multiplier,
                             gram_entry=_rational_string(contribution.gram_entry),
                             contribution=_rational_string(contribution.contribution),)
                            for contribution in match.contributions],)
            for match in matches]
end

function _sos_decomposition_json(decomposition::SOSDecomposition)
    if decomposition.status === :squares
        return (;
                type=SOS_DECOMPOSITION_SQUARES,
                method=decomposition.method,
                squares=[_sos_terms_json(square.terms) for square in
                                                           decomposition.squares],)
    end
    return (;
            type=SOS_DECOMPOSITION_GRAM_ONLY,
            method=decomposition.method,
            reason=decomposition.reason,)
end

function _parse_sos_variables(value)
    _require_array(value, "sos_problem.variables")
    variables = Symbol[]
    for (i, entry) in enumerate(value)
        entry isa AbstractString ||
            throw(ArgumentError("sos_problem.variables[$i] must be a string"))
        isempty(entry) &&
            throw(ArgumentError("sos_problem.variables[$i] must not be empty"))
        push!(variables, Symbol(String(entry)))
    end
    return variables
end

function _parse_sos_basis(value, variable_count::Integer)
    _require_array(value, "sos_problem.basis")
    return [_sos_exponent_vector(entry, variable_count, "sos_problem.basis[$i]")
            for (i, entry) in enumerate(value)]
end

function _parse_sos_polynomial_terms(value, variable_count::Integer)
    _require_array(value, "sos_problem.polynomial")
    parsed = PolynomialTerm[]
    for (i, entry) in enumerate(value)
        path = "sos_problem.polynomial[$i]"
        _require_object(entry, path)
        exponents = _sos_exponent_vector(_require_key(entry, :exponents, path),
                                         variable_count, "$path.exponents")
        coefficient = _parse_rational_string(_require_key(entry, :coefficient, path),
                                             "$path.coefficient")
        push!(parsed, PolynomialTerm(exponents, coefficient))
    end
    return parsed
end

function _parse_sos_coefficient_proof(value, variable_count::Integer)
    _require_object(value, "coefficient_proof")
    _require_value(value, :method, "exact_coefficient_matching", "coefficient_proof.method")
    terms_value = _require_key(value, :polynomial, "coefficient_proof")
    _require_array(terms_value, "coefficient_proof.polynomial")
    parsed = PolynomialTerm[]
    for (i, entry) in enumerate(terms_value)
        path = "coefficient_proof.polynomial[$i]"
        _require_object(entry, path)
        exponents = _sos_exponent_vector(_require_key(entry, :exponents, path),
                                         variable_count, "$path.exponents")
        coefficient = _parse_rational_string(_require_key(entry, :coefficient, path),
                                             "$path.coefficient")
        push!(parsed, PolynomialTerm(exponents, coefficient))
    end
    return _normalize_polynomial_terms(parsed, variable_count)
end

function _is_legacy_sos_coefficient_proof(value)
    _require_object(value, "coefficient_proof")
    return haskey(value, :polynomial)
end

function _parse_sos_coefficient_matches(value, variable_count::Integer)
    _require_object(value, "coefficient_proof")
    _require_value(value, :method, "exact_coefficient_matching", "coefficient_proof.method")
    matches_value = _require_key(value, :matches, "coefficient_proof")
    _require_array(matches_value, "coefficient_proof.matches")
    matches = SOSCoefficientMatch[]
    for (i, entry) in enumerate(matches_value)
        path = "coefficient_proof.matches[$i]"
        _require_object(entry, path)
        exponents = _sos_exponent_vector(_require_key(entry, :exponents, path),
                                         variable_count, "$path.exponents")
        target = _parse_rational_string(_require_key(entry, :target_coefficient, path),
                                        "$path.target_coefficient")
        gram = _parse_rational_string(_require_key(entry, :gram_coefficient, path),
                                      "$path.gram_coefficient")
        contributions_value = _require_key(entry, :contributions, path)
        _require_array(contributions_value, "$path.contributions")
        contributions = SOSGramContribution[]
        for (j, contribution) in enumerate(contributions_value)
            contribution_path = "$path.contributions[$j]"
            _require_object(contribution, contribution_path)
            pair_value = _require_key(contribution, :basis_pair, contribution_path)
            _require_array(pair_value, "$contribution_path.basis_pair")
            length(pair_value) == 2 ||
                throw(ArgumentError("$contribution_path.basis_pair must contain two indices"))
            pair_value[1] isa Integer ||
                throw(ArgumentError("$contribution_path.basis_pair[1] must be an integer"))
            pair_value[2] isa Integer ||
                throw(ArgumentError("$contribution_path.basis_pair[2] must be an integer"))
            multiplier = _require_integer(contribution, :multiplier,
                                          "$contribution_path.multiplier")
            gram_entry = _parse_rational_string(_require_key(contribution, :gram_entry,
                                                             contribution_path),
                                                "$contribution_path.gram_entry")
            claimed = _parse_rational_string(_require_key(contribution, :contribution,
                                                          contribution_path),
                                             "$contribution_path.contribution")
            parsed = SOSGramContribution(pair_value[1], pair_value[2], multiplier,
                                         gram_entry)
            parsed.contribution == claimed ||
                throw(ArgumentError("$contribution_path.contribution must equal multiplier * gram_entry"))
            push!(contributions, parsed)
        end
        push!(matches, SOSCoefficientMatch(exponents, target, gram, contributions))
    end
    return matches
end

function _parse_sos_decomposition(value, variable_count::Integer)
    _require_object(value, "decomposition")
    decomposition_type = _require_string(value, :type, "decomposition.type")
    if decomposition_type == SOS_DECOMPOSITION_GRAM_ONLY
        method = haskey(value, :method) ?
                 _require_string(value, :method,
                                 "decomposition.method") :
                 "not_reconstructed"
        reason = haskey(value, :reason) ?
                 _require_string(value, :reason,
                                 "decomposition.reason") : ""
        return SOSDecomposition(:gram_only, method, SOSSquare[], reason)
    elseif decomposition_type == SOS_DECOMPOSITION_SQUARES
        method = haskey(value, :method) ?
                 _require_string(value, :method,
                                 "decomposition.method") :
                 "unknown"
        squares_value = _require_key(value, :squares, "decomposition")
        _require_array(squares_value, "decomposition.squares")
        squares = SOSSquare[]
        for (i, square_terms_value) in enumerate(squares_value)
            path = "decomposition.squares[$i]"
            _require_array(square_terms_value, path)
            terms = PolynomialTerm[]
            for (j, entry) in enumerate(square_terms_value)
                term_path = "$path[$j]"
                _require_object(entry, term_path)
                exponents = _sos_exponent_vector(_require_key(entry, :exponents,
                                                              term_path),
                                                 variable_count,
                                                 "$term_path.exponents")
                coefficient = _parse_rational_string(_require_key(entry, :coefficient,
                                                                  term_path),
                                                     "$term_path.coefficient")
                push!(terms, PolynomialTerm(exponents, coefficient))
            end
            push!(squares, SOSSquare(terms, variable_count))
        end
        return SOSDecomposition(:squares, method, squares)
    end
    throw(ArgumentError("decomposition.type must be `$SOS_DECOMPOSITION_SQUARES` or `$SOS_DECOMPOSITION_GRAM_ONLY`; got `$decomposition_type`"))
end

function _sos_polynomial_text(terms::Vector{PolynomialTerm}, variables::Vector{Symbol})
    isempty(terms) && return "0"
    pieces = String[]
    for term in terms
        monomial = _sos_monomial_text(term.exponents, variables)
        coefficient = term.coefficient
        piece = if monomial == "1"
            _rational_string(coefficient)
        elseif coefficient == 1
            monomial
        elseif coefficient == -1
            "-" * monomial
        else
            _rational_string(coefficient) * "*" * monomial
        end
        push!(pieces, piece)
    end
    text = pieces[1]
    for piece in pieces[2:end]
        if startswith(piece, "-")
            text *= " - " * piece[2:end]
        else
            text *= " + " * piece
        end
    end
    return text
end

function _sos_monomial_text(exponents::Vector{Int}, variables::Vector{Symbol})
    parts = String[]
    for (variable, exponent) in zip(variables, exponents)
        iszero(exponent) && continue
        if exponent == 1
            push!(parts, String(variable))
        else
            push!(parts, string(variable, "^", exponent))
        end
    end
    return isempty(parts) ? "1" : join(parts, "*")
end

function _sos_polynomial_latex(terms::Vector{PolynomialTerm}, variables::Vector{Symbol})
    isempty(terms) && return "0"
    pieces = String[]
    for term in terms
        monomial = _sos_monomial_latex(term.exponents, variables)
        coefficient = term.coefficient
        piece = if monomial == "1"
            _rational_latex(coefficient)
        elseif coefficient == 1
            monomial
        elseif coefficient == -1
            "-" * monomial
        else
            _rational_latex(coefficient) * " " * monomial
        end
        push!(pieces, piece)
    end
    text = pieces[1]
    for piece in pieces[2:end]
        if startswith(piece, "-")
            text *= " - " * piece[2:end]
        else
            text *= " + " * piece
        end
    end
    return text
end

function _sos_monomial_latex(exponents::Vector{Int}, variables::Vector{Symbol})
    parts = String[]
    for (variable, exponent) in zip(variables, exponents)
        iszero(exponent) && continue
        if exponent == 1
            push!(parts, String(variable))
        else
            push!(parts, string(variable, "^{", exponent, "}"))
        end
    end
    return isempty(parts) ? "1" : join(parts, " ")
end

function _rational_latex(value::Rational)
    denominator(value) == 1 && return string(numerator(value))
    return "\\frac{$(numerator(value))}{$(denominator(value))}"
end

function _sos_polynomial_code(terms::Vector{PolynomialTerm},
                              variables::Vector{String};
                              power::AbstractString="^",
                              rational::AbstractString="//")
    isempty(terms) && return "0"
    pieces = String[]
    for term in terms
        monomial = _sos_monomial_code(term.exponents, variables; power)
        coefficient = _rational_code(term.coefficient; rational)
        piece = if monomial == "1"
            coefficient
        elseif term.coefficient == 1
            monomial
        elseif term.coefficient == -1
            "-" * monomial
        else
            coefficient * "*" * monomial
        end
        push!(pieces, piece)
    end
    text = pieces[1]
    for piece in pieces[2:end]
        if startswith(piece, "-")
            text *= " - " * piece[2:end]
        else
            text *= " + " * piece
        end
    end
    return text
end

function _sos_monomial_code(exponents::Vector{Int},
                            variables::Vector{String};
                            power::AbstractString="^")
    parts = String[]
    for (variable, exponent) in zip(variables, exponents)
        iszero(exponent) && continue
        if exponent == 1
            push!(parts, variable)
        else
            push!(parts, string(variable, power, exponent))
        end
    end
    return isempty(parts) ? "1" : join(parts, "*")
end

function _rational_code(value::Rational; rational::AbstractString="//")
    denominator(value) == 1 && return string(numerator(value))
    return string(numerator(value), rational, denominator(value))
end

function _sos_rational_matrix_code(matrix::SymmetricRationalMatrix;
                                   rational::AbstractString="//")
    entries = rational_matrix(matrix)
    rows = String[]
    for i in axes(entries, 1)
        push!(rows,
              "[" *
              join([_rational_code(entries[i, j]; rational)
                    for j in axes(entries, 2)], ", ") *
              "]")
    end
    return "[" * join(rows, ", ") * "]"
end
