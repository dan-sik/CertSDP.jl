const NC_SOS_GRAM_CERTIFICATE_TYPE = "nc_sos_gram_certificate"

"""
    NCSOSGramProblem

Internal noncommutative SOS Gram problem:

```text
p = v^* Q v,  Q >= 0
```

Words are replayed exactly. When `trace_cyclic=true`, coefficient matching is
performed modulo cyclic rotations, matching the trace-polynomial setting used
by many quantum and noncommutative SOS workflows.
"""
struct NCSOSGramProblem
    variables::Vector{Symbol}
    basis::Vector{NCWord}
    polynomial::Vector{NCPolynomialTerm}
    trace_cyclic::Bool
    reduction::Union{Nothing, NCRelationReduction}
    lmi::LMIProblem

    function NCSOSGramProblem(variables::AbstractVector,
                              basis::AbstractVector{NCWord},
                              polynomial::AbstractVector{NCPolynomialTerm};
                              trace_cyclic::Bool=false,
                              reduction::Union{Nothing, NCRelationReduction}=nothing)
        variable_names = Symbol.(variables)
        length(unique(variable_names)) == length(variable_names) ||
            throw(ArgumentError("NC variables must be unique"))
        isempty(basis) && throw(ArgumentError("NC SOS basis must not be empty"))
        length(unique(basis)) == length(basis) ||
            throw(ArgumentError("NC SOS basis words must be unique"))
        if !isnothing(reduction)
            reduction.trace_cyclic == Bool(trace_cyclic) ||
                throw(ArgumentError("NC reduction trace_cyclic must match the problem trace_cyclic setting"))
        end
        lmi = _sos_lmi_problem(length(basis))
        return new(variable_names, NCWord[basis...],
                   NCPolynomialTerm[polynomial...], Bool(trace_cyclic),
                   reduction, lmi)
    end
end

struct NCCoefficientMatch
    word::NCWord
    target_coefficient::Rational{BigInt}
    gram_coefficient::Rational{BigInt}
end

struct NCSOSGramCertificate
    problem::NCSOSGramProblem
    gram_matrix::SymmetricRationalMatrix
    lmi_certificate::RationalCertificate
    coefficient_proof::Vector{NCCoefficientMatch}
    hash::String
end

function certify_nc_sos(problem::NCSOSGramProblem, gram_matrix)
    result = try
        CertifiedResult(NCSOSGramCertificate(problem, gram_matrix))
    catch err
        diagnostics = Dict{Symbol, Any}(:exception_type => string(typeof(err)),
                                        :message => sprint(showerror, err),
                                        :basis_size => length(problem.basis),
                                        :polynomial_terms => length(problem.polynomial),
                                        :trace_cyclic => problem.trace_cyclic)
        FailureResult(SOSMatchingFailure(:nc_sos_matching_failed,
                                         "NC SOS Gram certificate could not be constructed",
                                         :nc_sos,
                                         diagnostics))
    end
    return result
end

function NCSOSGramCertificate(problem::NCSOSGramProblem, gram_matrix)
    Q = _as_symmetric_rational_matrix(gram_matrix, :nc_gram_matrix)
    size(Q) == (length(problem.basis), length(problem.basis)) ||
        throw(DimensionMismatch("NC Gram matrix has size $(size(Q)); expected $((length(problem.basis), length(problem.basis)))"))
    matches = nc_sos_coefficient_matching(problem, Q)
    all(match -> match.target_coefficient == match.gram_coefficient, matches) ||
        throw(ArgumentError("NC Gram matrix does not exactly match the target word polynomial"))
    psd_plan = choose_psd_proof(Q, nothing; method=:auto)
    psd_plan.status === :accepted ||
        throw(ArgumentError("NC Gram matrix is not positive semidefinite over QQ"))
    lmi_cert = RationalCertificate(problem.lmi, _sos_solution_from_gram_matrix(Q);
                                   psd_method=:auto)
    cert = NCSOSGramCertificate(problem, Q, lmi_cert, matches, "")
    return NCSOSGramCertificate(problem, Q, lmi_cert, matches,
                                nc_sos_gram_certificate_hash(cert))
end

function nc_sos_coefficient_matching(problem::NCSOSGramProblem,
                                     gram_matrix)
    Q = _as_symmetric_rational_matrix(gram_matrix, :nc_gram_matrix)
    gram_terms = _nc_sos_polynomial_from_gram(problem, Q)
    target_terms = _nc_terms_for_problem(problem, problem.polynomial)
    gram_terms = _nc_terms_for_problem(problem, gram_terms)
    target = nc_terms_dict(target_terms; trace_cyclic=problem.trace_cyclic)
    gram = nc_terms_dict(gram_terms; trace_cyclic=problem.trace_cyclic)
    words = sort(collect(union(Set(keys(target)), Set(keys(gram)))))
    return NCCoefficientMatch[
                              NCCoefficientMatch(word,
                                                 get(target, word, 0 // 1),
                                                 get(gram, word, 0 // 1))
                              for word in words
                              ]
end

function _nc_sos_polynomial_from_gram(problem::NCSOSGramProblem,
                                      Q::SymmetricRationalMatrix)
    matrix = rational_matrix(Q)
    n = length(problem.basis)
    terms = NCPolynomialTerm[]
    for i in 1:n, j in 1:n
        coefficient = matrix[i, j]
        iszero(coefficient) && continue
        word = nc_multiply(nc_involution(problem.basis[i]), problem.basis[j])
        push!(terms, NCPolynomialTerm(word, coefficient))
    end
    return terms
end

function verify(cert::NCSOSGramCertificate; io::Union{Nothing, IO}=nothing,
                kwargs...)
    try
        _check_or_report(io, cert.hash == nc_sos_gram_certificate_hash(cert),
                         "NC SOS certificate hash matches") || return false
        _check_or_report(io,
                         cert.coefficient_proof ==
                         nc_sos_coefficient_matching(cert.problem, cert.gram_matrix),
                         "NC coefficient metadata matches recomputation") ||
            return false
        _check_or_report(io,
                         all(match -> match.target_coefficient ==
                                      match.gram_coefficient,
                             cert.coefficient_proof),
                         "NC coefficient matching is exact") || return false
        if !isnothing(cert.problem.reduction)
            _check_or_report(io,
                             nc_relation_reduction_matches(cert.problem.reduction,
                                                           cert.problem.reduction.fingerprint),
                             "NC relation-reduction fingerprint matches recorded metadata") ||
                return false
        end
        _check_or_report(io,
                         verify(cert.lmi_certificate),
                         "embedded rational PSD certificate accepted") ||
            return false
        _check_or_report(io,
                         cert.lmi_certificate.solution ==
                         _sos_solution_from_gram_matrix(cert.gram_matrix),
                         "embedded LMI solution matches NC Gram matrix") ||
            return false
        _ok(io, "NC SOS Gram certificate accepted")
        return true
    catch err
        _fail(io, "NC SOS Gram certificate verification error: $(sprint(showerror, err))")
        return false
    end
end

function nc_sos_gram_problem_hash(problem::NCSOSGramProblem)
    payload = (;
               type="nc_sos_gram_problem",
               field=LMI_FIELD,
               variables=String.(problem.variables),
               basis=[_nc_word_string(word) for word in problem.basis],
               polynomial=[(;
                            word=_nc_word_string(term.word),
                            coefficient=_rational_string(term.coefficient),)
                           for term in problem.polynomial],
               trace_cyclic=problem.trace_cyclic,
               reduction=isnothing(problem.reduction) ? nothing :
                         _nc_relation_reduction_json(problem.reduction),)
    return "sha256:" * bytes2hex(sha256(JSON3.write(payload)))
end

function nc_sos_gram_certificate_hash(cert::NCSOSGramCertificate)
    payload = (;
               certificate_type=NC_SOS_GRAM_CERTIFICATE_TYPE,
               problem_hash=nc_sos_gram_problem_hash(cert.problem),
               gram_matrix=_json_matrix(cert.gram_matrix),
               coefficient_proof=[(;
                                   word=_nc_word_string(match.word),
                                   target_coefficient=_rational_string(match.target_coefficient),
                                   gram_coefficient=_rational_string(match.gram_coefficient),)
                                  for match in cert.coefficient_proof],
               reduction_fingerprint=isnothing(cert.problem.reduction) ? nothing :
                                     cert.problem.reduction.fingerprint,
               lmi_certificate_id=cert.lmi_certificate.hash,)
    return "sha256:" * bytes2hex(sha256(JSON3.write(payload)))
end

function _nc_word_string(word::NCWord)
    return isempty(word.letters) ? "1" : join(String.(word.letters), "*")
end

function _nc_terms_for_problem(problem::NCSOSGramProblem, terms)
    isnothing(problem.reduction) && return terms
    return nc_reduce_terms(terms, problem.reduction)
end

function _nc_relation_reduction_json(reduction::NCRelationReduction)
    return (;
            trace_cyclic=reduction.trace_cyclic,
            fingerprint=reduction.fingerprint,
            rules=[(;
                    lhs=_nc_word_string(rule.lhs),
                    rhs=_nc_word_string(rule.rhs),)
                   for rule in reduction.rules],)
end

function Base.:(==)(a::NCCoefficientMatch, b::NCCoefficientMatch)
    return a.word == b.word &&
           a.target_coefficient == b.target_coefficient &&
           a.gram_coefficient == b.gram_coefficient
end
