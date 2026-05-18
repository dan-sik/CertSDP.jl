const RATIONAL_FUNCTION_SOS_CERTIFICATE_TYPE = "rational_function_sos_certificate"
const POSITIVSTELLENSATZ_CERTIFICATE_TYPE = "positivstellensatz_certificate"
const PERTURBATION_COMPENSATION_CERTIFICATE_TYPE = "perturbation_compensation_sos_certificate"
const RATIONAL_FUNCTION_SOS_PROBLEM_TYPE = "rational_function_sos_claim"
const POSITIVSTELLENSATZ_PROBLEM_TYPE = "positivstellensatz_claim"
const PERTURBATION_COMPENSATION_PROBLEM_TYPE = "perturbation_compensation_sos_claim"
const EXPLICIT_RATIONAL_SQUARES_METHOD = "explicit_rational_squares"

struct NamedPolynomial
    name::String
    polynomial::Vector{PolynomialTerm}
end

struct PolynomialIdentityMatch
    exponents::Vector{Int}
    lhs_coefficient::Rational{BigInt}
    rhs_coefficient::Rational{BigInt}

    function PolynomialIdentityMatch(exponents::AbstractVector{<:Integer}, lhs, rhs)
        normalized = Int[]
        for exponent in exponents
            exponent >= 0 ||
                throw(ArgumentError("identity match exponents must be nonnegative"))
            push!(normalized, Int(exponent))
        end
        return new(normalized,
                   _to_big_rational(lhs; name=:lhs_coefficient),
                   _to_big_rational(rhs; name=:rhs_coefficient))
    end
end

struct PositivstellensatzTerm
    name::String
    constraint_product::Vector{String}
    squares::Vector{SOSSquare}
end

struct RationalFunctionSOSCertificate
    variables::Vector{Symbol}
    target::Vector{PolynomialTerm}
    numerator_squares::Vector{SOSSquare}
    denominator_squares::Vector{SOSSquare}
    coefficient_proof::Vector{PolynomialIdentityMatch}
    hash::String
    metadata::Dict{Symbol, Any}
end

struct PositivstellensatzCertificate
    variables::Vector{Symbol}
    target::Vector{PolynomialTerm}
    constraints::Vector{NamedPolynomial}
    terms::Vector{PositivstellensatzTerm}
    coefficient_proof::Vector{PolynomialIdentityMatch}
    hash::String
    metadata::Dict{Symbol, Any}
end

struct PerturbationCompensationSOSCertificate
    variables::Vector{Symbol}
    target::Vector{PolynomialTerm}
    perturbation::Vector{PolynomialTerm}
    perturbed_squares::Vector{SOSSquare}
    compensation_squares::Vector{SOSSquare}
    perturbed_identity_proof::Vector{PolynomialIdentityMatch}
    compensation_identity_proof::Vector{PolynomialIdentityMatch}
    hash::String
    metadata::Dict{Symbol, Any}
end

function RationalFunctionSOSCertificate(variables, target, numerator_squares,
                                        denominator_squares;
                                        metadata=Dict{Symbol, Any}())
    variable_names = _sos_variable_symbols(variables)
    target_terms = _normalize_polynomial_terms(target, length(variable_names))
    numerator = SOSSquare[numerator_squares...]
    denominator = SOSSquare[denominator_squares...]
    coefficient_proof = _rational_function_sos_identity_matches(variable_names,
                                                                target_terms,
                                                                numerator,
                                                                denominator)
    cert = RationalFunctionSOSCertificate(variable_names, target_terms, numerator,
                                          denominator, coefficient_proof, "",
                                          _symbol_any_dict(metadata))
    return RationalFunctionSOSCertificate(variable_names, target_terms, numerator,
                                          denominator, coefficient_proof,
                                          rational_function_sos_certificate_hash(cert),
                                          _symbol_any_dict(metadata))
end

function PositivstellensatzCertificate(variables, target, constraints, terms;
                                       metadata=Dict{Symbol, Any}())
    variable_names = _sos_variable_symbols(variables)
    target_terms = _normalize_polynomial_terms(target, length(variable_names))
    normalized_constraints = NamedPolynomial[]
    seen = Set{String}()
    for (i, constraint) in enumerate(constraints)
        named = _as_named_polynomial(constraint, length(variable_names),
                                     "constraints[$i]")
        isempty(named.name) &&
            throw(ArgumentError("constraints[$i].name must not be empty"))
        named.name in seen &&
            throw(ArgumentError("constraint name `$(named.name)` is repeated"))
        push!(seen, named.name)
        push!(normalized_constraints, named)
    end

    normalized_terms = PositivstellensatzTerm[]
    for (i, term) in enumerate(terms)
        normalized = _as_positivstellensatz_term(term, "terms[$i]")
        for constraint_name in normalized.constraint_product
            constraint_name in seen ||
                throw(ArgumentError("terms[$i].constraint_product references unknown constraint `$constraint_name`"))
        end
        push!(normalized_terms, normalized)
    end

    coefficient_proof = _positivstellensatz_identity_matches(variable_names,
                                                             target_terms,
                                                             normalized_constraints,
                                                             normalized_terms)
    cert = PositivstellensatzCertificate(variable_names, target_terms,
                                         normalized_constraints,
                                         normalized_terms, coefficient_proof, "",
                                         _symbol_any_dict(metadata))
    return PositivstellensatzCertificate(variable_names, target_terms,
                                         normalized_constraints,
                                         normalized_terms, coefficient_proof,
                                         positivstellensatz_certificate_hash(cert),
                                         _symbol_any_dict(metadata))
end

function PerturbationCompensationSOSCertificate(variables,
                                                target,
                                                perturbation,
                                                perturbed_squares,
                                                compensation_squares;
                                                metadata=Dict{Symbol, Any}())
    variable_names = _sos_variable_symbols(variables)
    target_terms = _normalize_polynomial_terms(target, length(variable_names))
    perturbation_terms = _normalize_polynomial_terms(perturbation,
                                                     length(variable_names))
    perturbed = SOSSquare[perturbed_squares...]
    compensation = SOSSquare[compensation_squares...]
    perturbed_identity = _perturbation_compensation_perturbed_matches(variable_names,
                                                                      target_terms,
                                                                      perturbation_terms,
                                                                      perturbed)
    compensation_identity = _perturbation_compensation_final_matches(variable_names,
                                                                     target_terms,
                                                                     perturbation_terms,
                                                                     perturbed,
                                                                     compensation)
    cert = PerturbationCompensationSOSCertificate(variable_names,
                                                  target_terms,
                                                  perturbation_terms,
                                                  perturbed,
                                                  compensation,
                                                  perturbed_identity,
                                                  compensation_identity,
                                                  "",
                                                  _symbol_any_dict(metadata))
    return PerturbationCompensationSOSCertificate(variable_names,
                                                  target_terms,
                                                  perturbation_terms,
                                                  perturbed,
                                                  compensation,
                                                  perturbed_identity,
                                                  compensation_identity,
                                                  perturbation_compensation_sos_certificate_hash(cert),
                                                  _symbol_any_dict(metadata))
end

function rational_function_sos_problem_hash(cert::RationalFunctionSOSCertificate)
    return rational_function_sos_problem_hash(cert.variables, cert.target)
end

function rational_function_sos_problem_hash(variables::Vector{Symbol},
                                            target::Vector{PolynomialTerm})
    canonical = _rational_function_sos_problem_json(variables, target)
    return "sha256:" * bytes2hex(sha256(JSON3.write(canonical)))
end

function positivstellensatz_problem_hash(cert::PositivstellensatzCertificate)
    return positivstellensatz_problem_hash(cert.variables, cert.target,
                                           cert.constraints)
end

function perturbation_compensation_sos_problem_hash(cert::PerturbationCompensationSOSCertificate)
    return perturbation_compensation_sos_problem_hash(cert.variables,
                                                      cert.target,
                                                      cert.perturbation)
end

function perturbation_compensation_sos_problem_hash(variables::Vector{Symbol},
                                                    target::Vector{PolynomialTerm},
                                                    perturbation::Vector{PolynomialTerm})
    canonical = _perturbation_compensation_sos_problem_json(variables, target,
                                                            perturbation)
    return "sha256:" * bytes2hex(sha256(JSON3.write(canonical)))
end

function positivstellensatz_problem_hash(variables::Vector{Symbol},
                                         target::Vector{PolynomialTerm},
                                         constraints::Vector{NamedPolynomial})
    canonical = _positivstellensatz_problem_json(variables, target, constraints)
    return "sha256:" * bytes2hex(sha256(JSON3.write(canonical)))
end

function rational_function_sos_certificate_hash(cert::RationalFunctionSOSCertificate)
    canonical = _canonical_rational_function_sos_certificate_json(cert)
    return "sha256:" * bytes2hex(sha256(JSON3.write(canonical)))
end

function positivstellensatz_certificate_hash(cert::PositivstellensatzCertificate)
    canonical = _canonical_positivstellensatz_certificate_json(cert)
    return "sha256:" * bytes2hex(sha256(JSON3.write(canonical)))
end

function perturbation_compensation_sos_certificate_hash(cert::PerturbationCompensationSOSCertificate)
    canonical = _canonical_perturbation_compensation_sos_certificate_json(cert)
    return "sha256:" * bytes2hex(sha256(JSON3.write(canonical)))
end

function certificate_json_v1(cert::RationalFunctionSOSCertificate)
    return merge(_canonical_rational_function_sos_certificate_json(cert),
                 (; certificate_id=cert.hash,))
end

function certificate_json_v1(cert::PositivstellensatzCertificate)
    return merge(_canonical_positivstellensatz_certificate_json(cert),
                 (; certificate_id=cert.hash,))
end

function certificate_json_v1(cert::PerturbationCompensationSOSCertificate)
    return merge(_canonical_perturbation_compensation_sos_certificate_json(cert),
                 (; certificate_id=cert.hash,))
end

function write_certificate(path::AbstractString, cert::RationalFunctionSOSCertificate)
    open(path, "w") do io
        return write(io, certificate_json_v1_string(cert))
    end
    return path
end

function write_certificate(path::AbstractString, cert::PositivstellensatzCertificate)
    open(path, "w") do io
        return write(io, certificate_json_v1_string(cert))
    end
    return path
end

function write_certificate(path::AbstractString,
                           cert::PerturbationCompensationSOSCertificate)
    open(path, "w") do io
        return write(io, certificate_json_v1_string(cert))
    end
    return path
end

function save_certificate(path::AbstractString, cert::RationalFunctionSOSCertificate)
    return write_certificate(path, cert)
end
function save_certificate(path::AbstractString, cert::PositivstellensatzCertificate)
    return write_certificate(path, cert)
end
function save_certificate(path::AbstractString,
                          cert::PerturbationCompensationSOSCertificate)
    return write_certificate(path, cert)
end

function verify(cert::RationalFunctionSOSCertificate; io::Union{Nothing, IO}=nothing,
                strict::Bool=false, kwargs...)
    if strict
        return _strict_verify_certificate_object(certificate_json_v1(cert); io,
                                                 kwargs...)
    end

    try
        _check_or_report(io,
                         cert.hash == rational_function_sos_certificate_hash(cert),
                         "rational-function SOS certificate hash matches") ||
            return false
        _check_or_report(io,
                         rational_function_sos_problem_hash(cert) ==
                         _require_string(certificate_json_v1(cert).problem.data, :hash,
                                         "problem.data.hash"),
                         "rational-function SOS problem hash matches") || return false
        _check_or_report(io,
                         !isempty(_polynomial_from_squares(cert.denominator_squares,
                                                           length(cert.variables))),
                         "denominator SOS is not the zero polynomial") || return false
        expected = _rational_function_sos_identity_matches(cert.variables, cert.target,
                                                           cert.numerator_squares,
                                                           cert.denominator_squares)
        _check_or_report(io, _identity_matches_equal(cert.coefficient_proof, expected),
                         "rational-function identity metadata matches recomputation") ||
            return false
        _check_or_report(io, _identity_matches_all_exact(cert.coefficient_proof),
                         "denominator * target equals numerator SOS exactly") ||
            return false
        _ok(io, "rational-function SOS certificate accepted")
        return true
    catch err
        _fail(io,
              "rational-function SOS verification error: $(sprint(showerror, err))")
        return false
    end
end

function verify(cert::PositivstellensatzCertificate; io::Union{Nothing, IO}=nothing,
                strict::Bool=false, kwargs...)
    if strict
        return _strict_verify_certificate_object(certificate_json_v1(cert); io,
                                                 kwargs...)
    end

    try
        _check_or_report(io,
                         cert.hash == positivstellensatz_certificate_hash(cert),
                         "Positivstellensatz certificate hash matches") || return false
        _check_or_report(io,
                         positivstellensatz_problem_hash(cert) ==
                         _require_string(certificate_json_v1(cert).problem.data, :hash,
                                         "problem.data.hash"),
                         "Positivstellensatz problem hash matches") || return false
        expected = _positivstellensatz_identity_matches(cert.variables, cert.target,
                                                        cert.constraints, cert.terms)
        _check_or_report(io, _identity_matches_equal(cert.coefficient_proof, expected),
                         "Positivstellensatz identity metadata matches recomputation") ||
            return false
        _check_or_report(io, _identity_matches_all_exact(cert.coefficient_proof),
                         "target equals SOS constraint assembly exactly") ||
            return false
        _ok(io, "Positivstellensatz certificate accepted")
        return true
    catch err
        _fail(io,
              "Positivstellensatz verification error: $(sprint(showerror, err))")
        return false
    end
end

function verify(cert::PerturbationCompensationSOSCertificate;
                io::Union{Nothing, IO}=nothing,
                strict::Bool=false,
                kwargs...)
    if strict
        return _strict_verify_certificate_object(certificate_json_v1(cert); io,
                                                 kwargs...)
    end

    try
        _check_or_report(io,
                         cert.hash ==
                         perturbation_compensation_sos_certificate_hash(cert),
                         "perturbation/compensation certificate hash matches") ||
            return false
        _check_or_report(io,
                         perturbation_compensation_sos_problem_hash(cert) ==
                         _require_string(certificate_json_v1(cert).problem.data,
                                         :hash,
                                         "problem.data.hash"),
                         "perturbation/compensation problem hash matches") ||
            return false
        expected_perturbed = _perturbation_compensation_perturbed_matches(cert.variables,
                                                                          cert.target,
                                                                          cert.perturbation,
                                                                          cert.perturbed_squares)
        _check_or_report(io,
                         _identity_matches_equal(cert.perturbed_identity_proof,
                                                 expected_perturbed),
                         "perturbed SOS identity metadata matches recomputation") ||
            return false
        _check_or_report(io,
                         _identity_matches_all_exact(cert.perturbed_identity_proof),
                         "target plus perturbation equals perturbed SOS exactly") ||
            return false
        expected_final = _perturbation_compensation_final_matches(cert.variables,
                                                                  cert.target,
                                                                  cert.perturbation,
                                                                  cert.perturbed_squares,
                                                                  cert.compensation_squares)
        _check_or_report(io,
                         _identity_matches_equal(cert.compensation_identity_proof,
                                                 expected_final),
                         "compensation identity metadata matches recomputation") ||
            return false
        _check_or_report(io,
                         _identity_matches_all_exact(cert.compensation_identity_proof),
                         "target equals perturbed SOS minus compensation exactly") ||
            return false
        _ok(io, "perturbation/compensation SOS certificate accepted")
        return true
    catch err
        _fail(io,
              "perturbation/compensation SOS verification error: $(sprint(showerror, err))")
        return false
    end
end

function _rational_function_sos_problem_json(variables::Vector{Symbol},
                                             target::Vector{PolynomialTerm})
    return (;
            certsdp_problem_version=SCHEMA_V1_VERSION,
            type=RATIONAL_FUNCTION_SOS_PROBLEM_TYPE,
            field=LMI_FIELD,
            variables=String.(variables),
            polynomial=_sos_terms_json(target),)
end

function _positivstellensatz_problem_json(variables::Vector{Symbol},
                                          target::Vector{PolynomialTerm},
                                          constraints::Vector{NamedPolynomial})
    return (;
            certsdp_problem_version=SCHEMA_V1_VERSION,
            type=POSITIVSTELLENSATZ_PROBLEM_TYPE,
            field=LMI_FIELD,
            variables=String.(variables),
            polynomial=_sos_terms_json(target),
            constraints=[(;
                          name=constraint.name,
                          polynomial=_sos_terms_json(constraint.polynomial),)
                         for constraint in constraints],)
end

function _perturbation_compensation_sos_problem_json(variables::Vector{Symbol},
                                                     target::Vector{PolynomialTerm},
                                                     perturbation::Vector{PolynomialTerm})
    return (;
            certsdp_problem_version=SCHEMA_V1_VERSION,
            type=PERTURBATION_COMPENSATION_PROBLEM_TYPE,
            field=LMI_FIELD,
            variables=String.(variables),
            polynomial=_sos_terms_json(target),
            perturbation=_sos_terms_json(perturbation),)
end

function _canonical_rational_function_sos_certificate_json(cert::RationalFunctionSOSCertificate)
    problem = _rational_function_sos_problem_json(cert.variables, cert.target)
    problem_hash = rational_function_sos_problem_hash(cert)
    return (;
            certsdp_certificate_version=SCHEMA_V1_VERSION,
            certificate_type=RATIONAL_FUNCTION_SOS_CERTIFICATE_TYPE,
            problem_hash,
            problem=(;
                     embedded=true,
                     type=RATIONAL_FUNCTION_SOS_PROBLEM_TYPE,
                     data=merge(problem, (; hash=problem_hash,)),),
            solution=(;
                      field=LMI_FIELD,
                      representation="rational_function_sos",
                      numerator_sos=_sos_square_block_json(cert.numerator_squares),
                      denominator_sos=_sos_square_block_json(cert.denominator_squares),),
            coefficient_proof=(;
                               method="exact_coefficient_matching",
                               identity="denominator_times_target_equals_numerator",
                               matches=_identity_matches_json(cert.coefficient_proof),),
            proof=(;
                   identity=(;
                             method="exact_coefficient_matching",
                             status="claimed",
                             equations=length(cert.coefficient_proof),),
                   sos=(;
                        method=EXPLICIT_RATIONAL_SQUARES_METHOD,
                        numerator_squares=length(cert.numerator_squares),
                        denominator_squares=length(cert.denominator_squares),),),
            provenance=_positive_certificate_provenance_json(cert.metadata,
                                                             "rational_function_sos_showcase"),
            verification=_positive_certificate_verification_json(cert.metadata),)
end

function _canonical_positivstellensatz_certificate_json(cert::PositivstellensatzCertificate)
    problem = _positivstellensatz_problem_json(cert.variables, cert.target,
                                               cert.constraints)
    problem_hash = positivstellensatz_problem_hash(cert)
    return (;
            certsdp_certificate_version=SCHEMA_V1_VERSION,
            certificate_type=POSITIVSTELLENSATZ_CERTIFICATE_TYPE,
            problem_hash,
            problem=(;
                     embedded=true,
                     type=POSITIVSTELLENSATZ_PROBLEM_TYPE,
                     data=merge(problem, (; hash=problem_hash,)),),
            solution=(;
                      field=LMI_FIELD,
                      representation="sos_multipliers",
                      terms=[_positivstellensatz_term_json(term)
                             for term in cert.terms],),
            coefficient_proof=(;
                               method="exact_coefficient_matching",
                               identity="target_equals_sos_constraint_assembly",
                               matches=_identity_matches_json(cert.coefficient_proof),),
            proof=(;
                   identity=(;
                             method="exact_coefficient_matching",
                             status="claimed",
                             equations=length(cert.coefficient_proof),),
                   sos=(;
                        method=EXPLICIT_RATIONAL_SQUARES_METHOD,
                        multiplier_terms=length(cert.terms),),),
            provenance=_positive_certificate_provenance_json(cert.metadata,
                                                             "positivstellensatz_showcase"),
            verification=_positive_certificate_verification_json(cert.metadata),)
end

function _canonical_perturbation_compensation_sos_certificate_json(cert::PerturbationCompensationSOSCertificate)
    problem = _perturbation_compensation_sos_problem_json(cert.variables,
                                                          cert.target,
                                                          cert.perturbation)
    problem_hash = perturbation_compensation_sos_problem_hash(cert)
    return (;
            certsdp_certificate_version=SCHEMA_V1_VERSION,
            certificate_type=PERTURBATION_COMPENSATION_CERTIFICATE_TYPE,
            problem_hash,
            problem=(;
                     embedded=true,
                     type=PERTURBATION_COMPENSATION_PROBLEM_TYPE,
                     data=merge(problem, (; hash=problem_hash,)),),
            solution=(;
                      field=LMI_FIELD,
                      representation="perturbation_compensation_sos",
                      perturbed_sos=_sos_square_block_json(cert.perturbed_squares),
                      compensation_sos=_sos_square_block_json(cert.compensation_squares),),
            coefficient_proof=(;
                               method="exact_coefficient_matching",
                               identity="target_plus_perturbation_equals_perturbed_sos_and_target_equals_perturbed_minus_compensation",
                               perturbed_matches=_identity_matches_json(cert.perturbed_identity_proof),
                               compensation_matches=_identity_matches_json(cert.compensation_identity_proof),),
            proof=(;
                   perturbed_identity=(;
                                       method="exact_coefficient_matching",
                                       status="claimed",
                                       equations=length(cert.perturbed_identity_proof),),
                   compensation_identity=(;
                                          method="exact_coefficient_matching",
                                          status="claimed",
                                          equations=length(cert.compensation_identity_proof),),
                   sos=(;
                        method=EXPLICIT_RATIONAL_SQUARES_METHOD,
                        perturbed_squares=length(cert.perturbed_squares),
                        compensation_squares=length(cert.compensation_squares),),),
            provenance=_positive_certificate_provenance_json(cert.metadata,
                                                             "perturbation_compensation_sos"),
            verification=_positive_certificate_verification_json(cert.metadata),)
end

function _positive_certificate_provenance_json(metadata::Dict{Symbol, Any},
                                               default_source::AbstractString)
    return (;
            certsdp_version=string(get(metadata, :certsdp_version,
                                       string(package_version()))),
            julia_version=string(get(metadata, :julia_version, string(VERSION))),
            schema_version=string(get(metadata, :schema_version, SCHEMA_V1_VERSION)),
            source=string(get(metadata, :source, default_source)),)
end

function _positive_certificate_verification_json(metadata::Dict{Symbol, Any})
    return (;
            verifier_version=string(get(metadata, :verifier_version,
                                        string(package_version()))),
            verified_at_creation=get(metadata, :verified_at_creation, nothing),)
end

function _parse_positive_certificate_v1_object(parsed, certificate_type::AbstractString)
    certificate_type == RATIONAL_FUNCTION_SOS_CERTIFICATE_TYPE &&
        return _parse_rational_function_sos_certificate_v1_object(parsed)
    certificate_type == POSITIVSTELLENSATZ_CERTIFICATE_TYPE &&
        return _parse_positivstellensatz_certificate_v1_object(parsed)
    certificate_type == PERTURBATION_COMPENSATION_CERTIFICATE_TYPE &&
        return _parse_perturbation_compensation_sos_certificate_v1_object(parsed)
    throw(ArgumentError("unsupported positive certificate type `$certificate_type`"))
end

function _parse_perturbation_compensation_sos_certificate_v1_object(parsed)
    _require_value(parsed, CERTSDP_CERTIFICATE_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.certsdp_certificate_version")
    _require_value(parsed, :certificate_type,
                   PERTURBATION_COMPENSATION_CERTIFICATE_TYPE,
                   "root.certificate_type")
    certificate_id = _require_string(parsed, :certificate_id, "root.certificate_id")
    _validate_sha256_identifier(certificate_id, "root.certificate_id")
    problem_block = _require_key(parsed, :problem, "root")
    _require_object(problem_block, "root.problem")
    _require_value(problem_block, :embedded, true, "root.problem.embedded")
    _require_value(problem_block, :type, PERTURBATION_COMPENSATION_PROBLEM_TYPE,
                   "root.problem.type")
    problem = _parse_perturbation_compensation_sos_problem_v1_document(_require_key(problem_block,
                                                                                    :data,
                                                                                    "root.problem"))
    supplied_problem_hash = _require_string(parsed, :problem_hash,
                                            "root.problem_hash")
    problem_hash = perturbation_compensation_sos_problem_hash(problem.variables,
                                                              problem.polynomial,
                                                              problem.perturbation)
    supplied_problem_hash == problem_hash ||
        throw(ArgumentError("root.problem_hash mismatch: expected $supplied_problem_hash, computed $problem_hash"))
    _require_string(problem, :hash, "root.problem.data.hash") == problem_hash ||
        throw(ArgumentError("root.problem.data.hash must match root.problem_hash"))

    solution = _require_key(parsed, :solution, "root")
    _require_object(solution, "root.solution")
    _require_value(solution, :field, LMI_FIELD, "root.solution.field")
    _require_value(solution, :representation, "perturbation_compensation_sos",
                   "root.solution.representation")
    perturbed = _parse_sos_square_block(_require_key(solution, :perturbed_sos,
                                                     "root.solution"),
                                        length(problem.variables),
                                        "root.solution.perturbed_sos")
    compensation = _parse_sos_square_block(_require_key(solution, :compensation_sos,
                                                        "root.solution"),
                                           length(problem.variables),
                                           "root.solution.compensation_sos")
    coefficient_proof = _require_key(parsed, :coefficient_proof, "root")
    _require_object(coefficient_proof, "root.coefficient_proof")
    _require_value(coefficient_proof, :method, "exact_coefficient_matching",
                   "root.coefficient_proof.method")
    _require_value(coefficient_proof,
                   :identity,
                   "target_plus_perturbation_equals_perturbed_sos_and_target_equals_perturbed_minus_compensation",
                   "root.coefficient_proof.identity")
    perturbed_matches = _parse_identity_matches_array(_require_key(coefficient_proof,
                                                                   :perturbed_matches,
                                                                   "root.coefficient_proof"),
                                                      length(problem.variables),
                                                      "root.coefficient_proof.perturbed_matches")
    compensation_matches = _parse_identity_matches_array(_require_key(coefficient_proof,
                                                                      :compensation_matches,
                                                                      "root.coefficient_proof"),
                                                         length(problem.variables),
                                                         "root.coefficient_proof.compensation_matches")
    _validate_perturbation_compensation_proof(parsed, "root")
    provenance = _require_key(parsed, :provenance, "root")
    verification = _require_key(parsed, :verification, "root")
    _require_object(provenance, "root.provenance")
    _require_object(verification, "root.verification")
    metadata = _positive_certificate_metadata_from_blocks(provenance, verification)

    cert = PerturbationCompensationSOSCertificate(problem.variables,
                                                  problem.polynomial,
                                                  problem.perturbation,
                                                  perturbed,
                                                  compensation,
                                                  perturbed_matches,
                                                  compensation_matches,
                                                  certificate_id,
                                                  metadata)
    cert.hash == perturbation_compensation_sos_certificate_hash(cert) ||
        throw(ArgumentError("root.certificate_id must match the perturbation/compensation SOS certificate hash"))
    return cert
end

function _parse_rational_function_sos_certificate_v1_object(parsed)
    _require_value(parsed, CERTSDP_CERTIFICATE_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.certsdp_certificate_version")
    _require_value(parsed, :certificate_type, RATIONAL_FUNCTION_SOS_CERTIFICATE_TYPE,
                   "root.certificate_type")
    certificate_id = _require_string(parsed, :certificate_id, "root.certificate_id")
    _validate_sha256_identifier(certificate_id, "root.certificate_id")
    problem_block = _require_key(parsed, :problem, "root")
    _require_object(problem_block, "root.problem")
    _require_value(problem_block, :embedded, true, "root.problem.embedded")
    _require_value(problem_block, :type, RATIONAL_FUNCTION_SOS_PROBLEM_TYPE,
                   "root.problem.type")
    problem = _parse_rational_function_sos_problem_v1_document(_require_key(problem_block,
                                                                            :data,
                                                                            "root.problem"))
    supplied_problem_hash = _require_string(parsed, :problem_hash, "root.problem_hash")
    problem_hash = rational_function_sos_problem_hash(problem.variables,
                                                      problem.polynomial)
    supplied_problem_hash == problem_hash ||
        throw(ArgumentError("root.problem_hash mismatch: expected $supplied_problem_hash, computed $problem_hash"))
    _require_string(problem, :hash, "root.problem.data.hash") == problem_hash ||
        throw(ArgumentError("root.problem.data.hash must match root.problem_hash"))

    solution = _require_key(parsed, :solution, "root")
    _require_object(solution, "root.solution")
    _require_value(solution, :field, LMI_FIELD, "root.solution.field")
    _require_value(solution, :representation, "rational_function_sos",
                   "root.solution.representation")
    numerator = _parse_sos_square_block(_require_key(solution, :numerator_sos,
                                                     "root.solution"),
                                        length(problem.variables),
                                        "root.solution.numerator_sos")
    denominator = _parse_sos_square_block(_require_key(solution, :denominator_sos,
                                                       "root.solution"),
                                          length(problem.variables),
                                          "root.solution.denominator_sos")
    coefficient_proof = _parse_identity_coefficient_proof(_require_key(parsed,
                                                                       :coefficient_proof,
                                                                       "root"),
                                                          length(problem.variables),
                                                          "denominator_times_target_equals_numerator")
    _validate_positive_certificate_proof(parsed, "root")
    provenance = _require_key(parsed, :provenance, "root")
    verification = _require_key(parsed, :verification, "root")
    _require_object(provenance, "root.provenance")
    _require_object(verification, "root.verification")
    metadata = _positive_certificate_metadata_from_blocks(provenance, verification)

    cert = RationalFunctionSOSCertificate(problem.variables, problem.polynomial,
                                          numerator, denominator, coefficient_proof,
                                          certificate_id, metadata)
    cert.hash == rational_function_sos_certificate_hash(cert) ||
        throw(ArgumentError("root.certificate_id must match the rational-function SOS certificate hash"))
    return cert
end

function _parse_positivstellensatz_certificate_v1_object(parsed)
    _require_value(parsed, CERTSDP_CERTIFICATE_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.certsdp_certificate_version")
    _require_value(parsed, :certificate_type, POSITIVSTELLENSATZ_CERTIFICATE_TYPE,
                   "root.certificate_type")
    certificate_id = _require_string(parsed, :certificate_id, "root.certificate_id")
    _validate_sha256_identifier(certificate_id, "root.certificate_id")
    problem_block = _require_key(parsed, :problem, "root")
    _require_object(problem_block, "root.problem")
    _require_value(problem_block, :embedded, true, "root.problem.embedded")
    _require_value(problem_block, :type, POSITIVSTELLENSATZ_PROBLEM_TYPE,
                   "root.problem.type")
    problem = _parse_positivstellensatz_problem_v1_document(_require_key(problem_block,
                                                                         :data,
                                                                         "root.problem"))
    supplied_problem_hash = _require_string(parsed, :problem_hash, "root.problem_hash")
    problem_hash = positivstellensatz_problem_hash(problem.variables,
                                                   problem.polynomial,
                                                   problem.constraints)
    supplied_problem_hash == problem_hash ||
        throw(ArgumentError("root.problem_hash mismatch: expected $supplied_problem_hash, computed $problem_hash"))
    _require_string(problem, :hash, "root.problem.data.hash") == problem_hash ||
        throw(ArgumentError("root.problem.data.hash must match root.problem_hash"))

    solution = _require_key(parsed, :solution, "root")
    _require_object(solution, "root.solution")
    _require_value(solution, :field, LMI_FIELD, "root.solution.field")
    _require_value(solution, :representation, "sos_multipliers",
                   "root.solution.representation")
    solution_terms_value = _require_key(solution, :terms, "root.solution")
    _require_array(solution_terms_value, "root.solution.terms")
    known_constraints = Set(constraint.name for constraint in problem.constraints)
    terms = PositivstellensatzTerm[]
    for (i, term_value) in enumerate(solution_terms_value)
        push!(terms,
              _parse_positivstellensatz_term(term_value, length(problem.variables),
                                             known_constraints,
                                             "root.solution.terms[$i]"))
    end
    coefficient_proof = _parse_identity_coefficient_proof(_require_key(parsed,
                                                                       :coefficient_proof,
                                                                       "root"),
                                                          length(problem.variables),
                                                          "target_equals_sos_constraint_assembly")
    _validate_positive_certificate_proof(parsed, "root")
    provenance = _require_key(parsed, :provenance, "root")
    verification = _require_key(parsed, :verification, "root")
    _require_object(provenance, "root.provenance")
    _require_object(verification, "root.verification")
    metadata = _positive_certificate_metadata_from_blocks(provenance, verification)

    cert = PositivstellensatzCertificate(problem.variables, problem.polynomial,
                                         problem.constraints, terms,
                                         coefficient_proof, certificate_id, metadata)
    cert.hash == positivstellensatz_certificate_hash(cert) ||
        throw(ArgumentError("root.certificate_id must match the Positivstellensatz certificate hash"))
    return cert
end

function _positive_certificate_metadata_from_blocks(provenance, verification)
    metadata = _json_object_to_symbol_dict(provenance)
    for (key, value) in _json_object_to_symbol_dict(verification)
        metadata[key] = value
    end
    return metadata
end

function _parse_rational_function_sos_problem_v1_document(value)
    _require_object(value, "root.problem.data")
    _require_value(value, CERTSDP_PROBLEM_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.problem.data.certsdp_problem_version")
    _require_value(value, :type, RATIONAL_FUNCTION_SOS_PROBLEM_TYPE,
                   "root.problem.data.type")
    _require_value(value, :field, LMI_FIELD, "root.problem.data.field")
    variables = _parse_sos_variables_at(_require_key(value, :variables,
                                                     "root.problem.data"),
                                        "root.problem.data.variables")
    polynomial = _parse_polynomial_terms_at(_require_key(value, :polynomial,
                                                         "root.problem.data"),
                                            length(variables),
                                            "root.problem.data.polynomial")
    return merge((;
                  variables,
                  polynomial,),
                 (; hash=_require_string(value, :hash,
                                         "root.problem.data.hash"),))
end

function _parse_positivstellensatz_problem_v1_document(value)
    _require_object(value, "root.problem.data")
    _require_value(value, CERTSDP_PROBLEM_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.problem.data.certsdp_problem_version")
    _require_value(value, :type, POSITIVSTELLENSATZ_PROBLEM_TYPE,
                   "root.problem.data.type")
    _require_value(value, :field, LMI_FIELD, "root.problem.data.field")
    variables = _parse_sos_variables_at(_require_key(value, :variables,
                                                     "root.problem.data"),
                                        "root.problem.data.variables")
    polynomial = _parse_polynomial_terms_at(_require_key(value, :polynomial,
                                                         "root.problem.data"),
                                            length(variables),
                                            "root.problem.data.polynomial")
    constraints_value = _require_key(value, :constraints, "root.problem.data")
    _require_array(constraints_value, "root.problem.data.constraints")
    constraints = NamedPolynomial[]
    seen = Set{String}()
    for (i, constraint_value) in enumerate(constraints_value)
        path = "root.problem.data.constraints[$i]"
        _require_object(constraint_value, path)
        name = _require_string(constraint_value, :name, "$path.name")
        isempty(name) && throw(ArgumentError("$path.name must not be empty"))
        name in seen && throw(ArgumentError("constraint name `$name` is repeated"))
        push!(seen, name)
        terms = _parse_polynomial_terms_at(_require_key(constraint_value,
                                                        :polynomial, path),
                                           length(variables),
                                           "$path.polynomial")
        push!(constraints, NamedPolynomial(name, terms))
    end
    return merge((;
                  variables,
                  polynomial,
                  constraints,),
                 (; hash=_require_string(value, :hash,
                                         "root.problem.data.hash"),))
end

function _parse_perturbation_compensation_sos_problem_v1_document(value)
    _require_object(value, "root.problem.data")
    _require_value(value, CERTSDP_PROBLEM_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.problem.data.certsdp_problem_version")
    _require_value(value, :type, PERTURBATION_COMPENSATION_PROBLEM_TYPE,
                   "root.problem.data.type")
    _require_value(value, :field, LMI_FIELD, "root.problem.data.field")
    variables = _parse_sos_variables_at(_require_key(value, :variables,
                                                     "root.problem.data"),
                                        "root.problem.data.variables")
    polynomial = _parse_polynomial_terms_at(_require_key(value, :polynomial,
                                                         "root.problem.data"),
                                            length(variables),
                                            "root.problem.data.polynomial")
    perturbation = _parse_polynomial_terms_at(_require_key(value, :perturbation,
                                                           "root.problem.data"),
                                              length(variables),
                                              "root.problem.data.perturbation")
    return merge((;
                  variables,
                  polynomial,
                  perturbation,),
                 (; hash=_require_string(value, :hash,
                                         "root.problem.data.hash"),))
end

function _validate_perturbation_compensation_proof(parsed, path::AbstractString)
    proof = _require_key(parsed, :proof, path)
    _require_object(proof, "$path.proof")
    for field in (:perturbed_identity, :compensation_identity)
        block = _require_key(proof, field, "$path.proof")
        block_path = "$path.proof.$(String(field))"
        _require_object(block, block_path)
        _require_value(block, :method, "exact_coefficient_matching",
                       "$block_path.method")
        _require_value(block, :status, "claimed", "$block_path.status")
        _require_integer(block, :equations, "$block_path.equations")
    end
    sos = _require_key(proof, :sos, "$path.proof")
    _require_object(sos, "$path.proof.sos")
    _require_value(sos, :method, EXPLICIT_RATIONAL_SQUARES_METHOD,
                   "$path.proof.sos.method")
    return true
end

function _validate_positive_certificate_proof(parsed, path::AbstractString)
    proof = _require_key(parsed, :proof, path)
    _require_object(proof, "$path.proof")
    identity = _require_key(proof, :identity, "$path.proof")
    _require_object(identity, "$path.proof.identity")
    _require_value(identity, :method, "exact_coefficient_matching",
                   "$path.proof.identity.method")
    _require_value(identity, :status, "claimed", "$path.proof.identity.status")
    _require_integer(identity, :equations, "$path.proof.identity.equations")
    sos = _require_key(proof, :sos, "$path.proof")
    _require_object(sos, "$path.proof.sos")
    _require_value(sos, :method, EXPLICIT_RATIONAL_SQUARES_METHOD,
                   "$path.proof.sos.method")
    return true
end

function _sos_square_block_json(squares::Vector{SOSSquare})
    return (;
            method=EXPLICIT_RATIONAL_SQUARES_METHOD,
            squares=[_sos_terms_json(square.terms) for square in squares],)
end

function _positivstellensatz_term_json(term::PositivstellensatzTerm)
    return (;
            name=term.name,
            constraint_product=copy(term.constraint_product),
            sos=_sos_square_block_json(term.squares),)
end

function _identity_matches_json(matches::Vector{PolynomialIdentityMatch})
    return [(;
             exponents=copy(match.exponents),
             lhs_coefficient=_rational_string(match.lhs_coefficient),
             rhs_coefficient=_rational_string(match.rhs_coefficient),)
            for match in matches]
end

function _parse_sos_square_block(value, variable_count::Integer, path::AbstractString)
    _require_object(value, path)
    _require_value(value, :method, EXPLICIT_RATIONAL_SQUARES_METHOD,
                   "$path.method")
    squares_value = _require_key(value, :squares, path)
    _require_array(squares_value, "$path.squares")
    squares = SOSSquare[]
    for (i, square_value) in enumerate(squares_value)
        square_path = "$path.squares[$i]"
        terms = _parse_polynomial_terms_at(square_value, variable_count, square_path)
        push!(squares, SOSSquare(terms, variable_count))
    end
    return squares
end

function _parse_positivstellensatz_term(value, variable_count::Integer,
                                        known_constraints::Set{String},
                                        path::AbstractString)
    _require_object(value, path)
    name = haskey(value, :name) ? _require_string(value, :name, "$path.name") :
           "term"
    product_value = _require_key(value, :constraint_product, path)
    _require_array(product_value, "$path.constraint_product")
    product = String[]
    for (i, entry) in enumerate(product_value)
        entry isa AbstractString ||
            throw(ArgumentError("$path.constraint_product[$i] must be a string"))
        text = String(entry)
        text in known_constraints ||
            throw(ArgumentError("$path.constraint_product[$i] references unknown constraint `$text`"))
        push!(product, text)
    end
    squares = _parse_sos_square_block(_require_key(value, :sos, path),
                                      variable_count, "$path.sos")
    return PositivstellensatzTerm(name, product, squares)
end

function _parse_identity_coefficient_proof(value, variable_count::Integer,
                                           expected_identity::AbstractString)
    _require_object(value, "coefficient_proof")
    _require_value(value, :method, "exact_coefficient_matching",
                   "coefficient_proof.method")
    _require_value(value, :identity, expected_identity, "coefficient_proof.identity")
    matches_value = _require_key(value, :matches, "coefficient_proof")
    return _parse_identity_matches_array(matches_value, variable_count,
                                         "coefficient_proof.matches")
end

function _parse_identity_matches_array(matches_value,
                                       variable_count::Integer,
                                       path_prefix::AbstractString)
    _require_array(matches_value, path_prefix)
    matches = PolynomialIdentityMatch[]
    for (i, match_value) in enumerate(matches_value)
        path = "$path_prefix[$i]"
        _require_object(match_value, path)
        exponents = _sos_exponent_vector(_require_key(match_value, :exponents, path),
                                         variable_count, "$path.exponents")
        lhs = _parse_rational_string(_require_key(match_value, :lhs_coefficient, path),
                                     "$path.lhs_coefficient")
        rhs = _parse_rational_string(_require_key(match_value, :rhs_coefficient, path),
                                     "$path.rhs_coefficient")
        push!(matches, PolynomialIdentityMatch(exponents, lhs, rhs))
    end
    return matches
end

function _parse_sos_variables_at(value, path::AbstractString)
    _require_array(value, path)
    variables = Symbol[]
    for (i, entry) in enumerate(value)
        entry isa AbstractString || throw(ArgumentError("$path[$i] must be a string"))
        isempty(entry) && throw(ArgumentError("$path[$i] must not be empty"))
        push!(variables, Symbol(String(entry)))
    end
    isempty(variables) && throw(ArgumentError("$path must contain at least one variable"))
    length(unique(variables)) == length(variables) ||
        throw(ArgumentError("$path must contain unique variables"))
    return variables
end

function _parse_polynomial_terms_at(value, variable_count::Integer, path::AbstractString)
    _require_array(value, path)
    parsed = PolynomialTerm[]
    for (i, entry) in enumerate(value)
        term_path = "$path[$i]"
        _require_object(entry, term_path)
        exponents = _sos_exponent_vector(_require_key(entry, :exponents, term_path),
                                         variable_count, "$term_path.exponents")
        coefficient = _parse_rational_string(_require_key(entry, :coefficient,
                                                          term_path),
                                             "$term_path.coefficient")
        push!(parsed, PolynomialTerm(exponents, coefficient))
    end
    return _normalize_polynomial_terms(parsed, variable_count)
end

function _as_named_polynomial(value::NamedPolynomial, variable_count::Integer,
                              path::AbstractString)
    terms = _normalize_polynomial_terms(value.polynomial, variable_count)
    return NamedPolynomial(value.name, terms)
end

function _as_named_polynomial(value::NamedTuple, variable_count::Integer,
                              path::AbstractString)
    haskey(value, :name) || throw(ArgumentError("$path is missing `name`"))
    haskey(value, :polynomial) ||
        throw(ArgumentError("$path is missing `polynomial`"))
    return NamedPolynomial(String(value.name),
                           _normalize_polynomial_terms(value.polynomial,
                                                       variable_count))
end

function _as_named_polynomial(value, variable_count::Integer, path::AbstractString)
    throw(ArgumentError("$path must be a NamedPolynomial or named tuple"))
end

function _as_positivstellensatz_term(value::PositivstellensatzTerm,
                                     path::AbstractString)
    return value
end

function _as_positivstellensatz_term(value::NamedTuple, path::AbstractString)
    haskey(value, :constraint_product) ||
        throw(ArgumentError("$path is missing `constraint_product`"))
    haskey(value, :squares) || throw(ArgumentError("$path is missing `squares`"))
    name = haskey(value, :name) ? String(value.name) : "term"
    return PositivstellensatzTerm(name, String.(value.constraint_product),
                                  SOSSquare[value.squares...])
end

function _as_positivstellensatz_term(value, path::AbstractString)
    throw(ArgumentError("$path must be a PositivstellensatzTerm or named tuple"))
end

function _rational_function_sos_identity_matches(variables::Vector{Symbol},
                                                 target::Vector{PolynomialTerm},
                                                 numerator_squares::Vector{SOSSquare},
                                                 denominator_squares::Vector{SOSSquare})
    variable_count = length(variables)
    lhs = _poly_mul(_poly_from_terms(target),
                    _polynomial_from_squares(denominator_squares, variable_count))
    rhs = _polynomial_from_squares(numerator_squares, variable_count)
    return _polynomial_identity_matches(lhs, rhs, variable_count)
end

function _positivstellensatz_identity_matches(variables::Vector{Symbol},
                                              target::Vector{PolynomialTerm},
                                              constraints::Vector{NamedPolynomial},
                                              terms::Vector{PositivstellensatzTerm})
    variable_count = length(variables)
    constraint_polys = Dict{String, Dict{Tuple{Vararg{Int}}, Rational{BigInt}}}()
    for constraint in constraints
        constraint_polys[constraint.name] = _poly_from_terms(constraint.polynomial)
    end
    rhs = _poly_zero()
    one = _poly_one(variable_count)
    for term in terms
        sos = _polynomial_from_squares(term.squares, variable_count)
        product = one
        for constraint_name in term.constraint_product
            product = _poly_mul(product, constraint_polys[constraint_name])
        end
        rhs = _poly_add(rhs, _poly_mul(sos, product))
    end
    return _polynomial_identity_matches(_poly_from_terms(target), rhs,
                                        variable_count)
end

function _perturbation_compensation_perturbed_matches(variables::Vector{Symbol},
                                                      target::Vector{PolynomialTerm},
                                                      perturbation::Vector{PolynomialTerm},
                                                      perturbed_squares::Vector{SOSSquare})
    variable_count = length(variables)
    lhs = _poly_add(_poly_from_terms(target), _poly_from_terms(perturbation))
    rhs = _polynomial_from_squares(perturbed_squares, variable_count)
    return _polynomial_identity_matches(lhs, rhs, variable_count)
end

function _perturbation_compensation_final_matches(variables::Vector{Symbol},
                                                  target::Vector{PolynomialTerm},
                                                  perturbation::Vector{PolynomialTerm},
                                                  perturbed_squares::Vector{SOSSquare},
                                                  compensation_squares::Vector{SOSSquare})
    variable_count = length(variables)
    lhs = _poly_from_terms(target)
    rhs = _poly_add(_polynomial_from_squares(perturbed_squares, variable_count),
                    _poly_scale(_polynomial_from_squares(compensation_squares,
                                                         variable_count),
                                -1 // 1))
    return _polynomial_identity_matches(lhs, rhs, variable_count)
end

function _polynomial_identity_matches(lhs::Dict, rhs::Dict, variable_count::Integer)
    exponents = union(Set(keys(lhs)), Set(keys(rhs)))
    matches = PolynomialIdentityMatch[]
    for exponent in sort(collect(exponents); lt=_sos_exponent_order_lt)
        length(exponent) == variable_count ||
            throw(ArgumentError("identity exponent length does not match variable count"))
        push!(matches,
              PolynomialIdentityMatch(collect(exponent), get(lhs, exponent, 0 // 1),
                                      get(rhs, exponent, 0 // 1)))
    end
    return matches
end

function _identity_matches_equal(a::Vector{PolynomialIdentityMatch},
                                 b::Vector{PolynomialIdentityMatch})
    length(a) == length(b) || return false
    for i in eachindex(a)
        a[i].exponents == b[i].exponents || return false
        a[i].lhs_coefficient == b[i].lhs_coefficient || return false
        a[i].rhs_coefficient == b[i].rhs_coefficient || return false
    end
    return true
end

function _identity_matches_all_exact(matches::Vector{PolynomialIdentityMatch})
    return all(match -> match.lhs_coefficient == match.rhs_coefficient, matches)
end

function _polynomial_from_squares(squares::Vector{SOSSquare}, variable_count::Integer)
    result = _poly_zero()
    for square in squares
        terms = _poly_from_terms(square.terms)
        result = _poly_add(result, _poly_mul(terms, terms))
    end
    return result
end

function _poly_zero()
    return Dict{Tuple{Vararg{Int}}, Rational{BigInt}}()
end

function _poly_one(variable_count::Integer)
    result = _poly_zero()
    result[tuple(fill(0, variable_count)...)] = 1 // 1
    return result
end

function _poly_from_terms(terms::Vector{PolynomialTerm})
    return _sos_terms_dict(terms)
end

function _poly_add(a::Dict, b::Dict)
    result = Dict{Tuple{Vararg{Int}}, Rational{BigInt}}()
    for (exponent, coefficient) in a
        result[exponent] = coefficient
    end
    for (exponent, coefficient) in b
        result[exponent] = get(result, exponent, 0 // 1) + coefficient
        iszero(result[exponent]) && delete!(result, exponent)
    end
    return result
end

function _poly_mul(a::Dict, b::Dict)
    result = _poly_zero()
    for (exp_a, coeff_a) in a, (exp_b, coeff_b) in b
        length(exp_a) == length(exp_b) ||
            throw(ArgumentError("cannot multiply polynomials with different variable counts"))
        exponent = tuple((exp_a[i] + exp_b[i] for i in eachindex(exp_a))...)
        result[exponent] = get(result, exponent, 0 // 1) + coeff_a * coeff_b
        iszero(result[exponent]) && delete!(result, exponent)
    end
    return result
end

function _poly_scale(a::Dict, factor)
    scale = _to_big_rational(factor; name=:polynomial_scale_factor)
    iszero(scale) && return _poly_zero()
    result = _poly_zero()
    for (exponent, coefficient) in a
        value = scale * coefficient
        iszero(value) && continue
        result[exponent] = value
    end
    return result
end

function _sostools_lite_problem_and_solution(value)
    _require_object(value, "root")
    if haskey(value, :source_format)
        _require_value(value, :source_format, "sostools_lite", "root.source_format")
    end
    variables = _parse_sos_variables_at(_require_key(value, :variables, "root"),
                                        "root.variables")
    basis = _parse_sos_basis(_require_key(value, :basis, "root"),
                             length(variables))
    polynomial = _parse_polynomial_terms_at(_require_key(value, :polynomial, "root"),
                                            length(variables), "root.polynomial")
    problem = SOSGramProblem(variables, basis, polynomial)
    gram = SymmetricRationalMatrix(_parse_rational_matrix(_require_key(value,
                                                                       :gram_matrix,
                                                                       "root"),
                                                          length(basis),
                                                          "root.gram_matrix");
                                   name=:gram_matrix)
    return problem, gram
end

function convert_sostools_lite_json(input_path::AbstractString;
                                    problem_out::Union{Nothing, AbstractString}=nothing,
                                    solution_out::Union{Nothing, AbstractString}=nothing,
                                    cert_out::Union{Nothing, AbstractString}=nothing)
    parsed = try
        JSON3.read(read(input_path, String))
    catch err
        throw(ArgumentError("invalid SOSTOOLS-lite JSON: $(sprint(showerror, err))"))
    end
    problem, gram = _sostools_lite_problem_and_solution(parsed)
    if !isnothing(problem_out)
        write_sos_gram_json(problem_out, problem)
    end
    if !isnothing(solution_out)
        open(solution_out, "w") do io
            JSON3.pretty(io,
                         (;
                          certsdp_problem_version=SCHEMA_V1_VERSION,
                          sos_problem=merge(_canonical_sos_gram_problem_json(problem),
                                            (; hash=sos_gram_problem_hash(problem))),
                          solution=(;
                                    type=SOS_GRAM_SOLUTION_TYPE,
                                    gram_matrix=_json_matrix(gram),),))
            return println(io)
        end
    end
    cert = if isnothing(cert_out)
        nothing
    else
        result = certify_sos(problem, gram)
        result isa FailureResult &&
            throw(ArgumentError("converted SOSTOOLS-lite Gram data did not certify"))
        certificate_value = certificate(result)
        write_certificate(cert_out, certificate_value)
        certificate_value
    end
    return (;
            problem,
            gram_matrix=gram,
            problem_out,
            solution_out,
            cert_out,
            certificate=cert,)
end
