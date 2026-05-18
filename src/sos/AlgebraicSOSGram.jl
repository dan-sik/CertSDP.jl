const ALGEBRAIC_SOS_GRAM_PROBLEM_TYPE = "algebraic_sos_gram_feasibility"
const ALGEBRAIC_SOS_GRAM_CERTIFICATE_TYPE = "algebraic_sos_gram_certificate"
const ALGEBRAIC_SOS_GRAM_SOLUTION_TYPE = "algebraic_gram_matrix"

"""
    AlgebraicPolynomialTerm(exponents, coefficient)

One multivariate polynomial term with coefficient in a single real number
field `QQ(alpha)`. The coefficient carries the `AlgebraicRoot` representation.
"""
struct AlgebraicPolynomialTerm
    exponents::Vector{Int}
    coefficient::AlgebraicElement

    function AlgebraicPolynomialTerm(exponents::AbstractVector{<:Integer},
                                     coefficient::AlgebraicElement)
        normalized_exponents = Int[]
        for (i, exponent) in enumerate(exponents)
            exponent >= 0 ||
                throw(ArgumentError("algebraic polynomial term exponent $i must be nonnegative"))
            push!(normalized_exponents, Int(exponent))
        end
        return new(normalized_exponents, coefficient)
    end
end

struct AlgebraicSOSContribution
    i::Int
    j::Int
    multiplier::Int
    gram_entry::AlgebraicElement
    contribution::AlgebraicElement

    function AlgebraicSOSContribution(i::Integer,
                                      j::Integer,
                                      multiplier::Integer,
                                      gram_entry::AlgebraicElement)
        1 <= i <= j ||
            throw(ArgumentError("algebraic SOS contribution indices must satisfy 1 <= i <= j"))
        multiplier in (1, 2) ||
            throw(ArgumentError("algebraic SOS contribution multiplier must be 1 or 2"))
        return new(Int(i), Int(j), Int(multiplier), gram_entry,
                   gram_entry * Int(multiplier))
    end
end

struct AlgebraicSOSCoefficientMatch
    exponents::Vector{Int}
    target_coefficient::AlgebraicElement
    gram_coefficient::AlgebraicElement
    contributions::Vector{AlgebraicSOSContribution}

    function AlgebraicSOSCoefficientMatch(exponents::AbstractVector{<:Integer},
                                          target::AlgebraicElement,
                                          gram::AlgebraicElement,
                                          contributions::AbstractVector)
        normalized_exponents = Int[]
        for (i, exponent) in enumerate(exponents)
            exponent >= 0 ||
                throw(ArgumentError("algebraic SOS coefficient exponent $i must be nonnegative"))
            push!(normalized_exponents, Int(exponent))
        end
        return new(normalized_exponents, target, gram,
                   AlgebraicSOSContribution[contributions...])
    end
end

struct AlgebraicSOSGramProblem
    variables::Vector{Symbol}
    basis::Vector{Vector{Int}}
    polynomial::Vector{AlgebraicPolynomialTerm}
    root::AlgebraicRoot

    function AlgebraicSOSGramProblem(variables::AbstractVector,
                                     basis::AbstractVector,
                                     polynomial::AbstractVector)
        variable_names = _sos_variable_symbols(variables)
        basis_exponents = [_sos_exponent_vector(entry, length(variable_names),
                                                "basis[$i]")
                           for (i, entry) in enumerate(basis)]
        isempty(basis_exponents) &&
            throw(ArgumentError("algebraic SOS Gram basis must not be empty"))
        length(unique(basis_exponents)) == length(basis_exponents) ||
            throw(ArgumentError("algebraic SOS Gram basis monomials must be unique"))

        terms = AlgebraicPolynomialTerm[]
        for (i, term) in enumerate(polynomial)
            push!(terms,
                  _as_algebraic_polynomial_term(term, length(variable_names),
                                                "polynomial[$i]"))
        end
        isempty(terms) &&
            throw(ArgumentError("algebraic SOS Gram polynomial must not be empty"))
        root = _common_algebraic_root([term.coefficient for term in terms])
        normalized = _normalize_algebraic_polynomial_terms(terms,
                                                           length(variable_names),
                                                           root)
        return new(variable_names, basis_exponents, normalized, root)
    end
end

struct AlgebraicSOSGramCertificate
    problem::AlgebraicSOSGramProblem
    gram_matrix::Matrix{AlgebraicElement}
    psd_proof::AlgebraicPSDProof
    coefficient_proof::Vector{AlgebraicSOSCoefficientMatch}
    hash::String
    metadata::Dict{Symbol, Any}
end

function AlgebraicSOSGramCertificate(problem::AlgebraicSOSGramProblem,
                                     gram_matrix;
                                     psd_method::Union{Symbol, AbstractString}=Symbol(RATIONAL_PSD_METHOD),
                                     metadata=Dict{Symbol, Any}())
    Q = _as_symmetric_algebraic_gram_matrix(gram_matrix, problem.root,
                                            length(problem.basis))
    matches = algebraic_sos_coefficient_matching(problem, Q)
    all(match -> match.target_coefficient == match.gram_coefficient, matches) ||
        throw(ArgumentError("algebraic Gram matrix does not exactly match the target polynomial"))
    proof = algebraic_psd_proof(Q; method=psd_method)
    cert_without_hash = AlgebraicSOSGramCertificate(problem, Q, proof, matches,
                                                    "",
                                                    _symbol_any_dict(metadata))
    return AlgebraicSOSGramCertificate(problem, Q, proof, matches,
                                       algebraic_sos_gram_certificate_hash(cert_without_hash),
                                       _symbol_any_dict(metadata))
end

function certify_algebraic_sos(problem::AlgebraicSOSGramProblem,
                               gram_matrix;
                               kwargs...)
    result = try
        CertifiedResult(AlgebraicSOSGramCertificate(problem, gram_matrix; kwargs...))
    catch err
        FailureResult(SOSMatchingFailure(:algebraic_sos_matching_failed,
                                         "algebraic SOS Gram certificate could not be constructed",
                                         :algebraic_sos,
                                         Dict{Symbol, Any}(:exception_type => string(typeof(err)),
                                                           :message => sprint(showerror,
                                                                              err),
                                                           :basis_size => length(problem.basis),
                                                           :polynomial_terms => length(problem.polynomial))))
    end
    return result
end

function algebraic_sos_coefficient_matching(problem::AlgebraicSOSGramProblem,
                                            gram_matrix)
    Q = _as_symmetric_algebraic_gram_matrix(gram_matrix, problem.root,
                                            length(problem.basis))
    target = _algebraic_terms_dict(problem.polynomial, problem.root)
    gram = Dict{Tuple{Vararg{Int}}, AlgebraicElement}()
    contribution_map = Dict{Tuple{Vararg{Int}}, Vector{AlgebraicSOSContribution}}()
    root = problem.root
    for i in eachindex(problem.basis), j in i:length(problem.basis)
        multiplier = i == j ? 1 : 2
        entry = Q[i, j]
        exponent = tuple((problem.basis[i][k] + problem.basis[j][k]
                          for k in eachindex(problem.basis[i]))...)
        contribution = AlgebraicSOSContribution(i, j, multiplier, entry)
        gram[exponent] = get(gram, exponent, AlgebraicElement(root, 0)) +
                         contribution.contribution
        iszero(gram[exponent]) && delete!(gram, exponent)
        push!(get!(contribution_map, exponent, AlgebraicSOSContribution[]),
              contribution)
    end

    exponents = sort(collect(union(Set(keys(target)), Set(keys(gram))));
                     lt=_sos_exponent_order_lt)
    return AlgebraicSOSCoefficientMatch[
                                        AlgebraicSOSCoefficientMatch(collect(exponent),
                                                                     get(target,
                                                                         exponent,
                                                                         AlgebraicElement(root,
                                                                                          0)),
                                                                     get(gram,
                                                                         exponent,
                                                                         AlgebraicElement(root,
                                                                                          0)),
                                                                     get(contribution_map,
                                                                         exponent,
                                                                         AlgebraicSOSContribution[]))
                                        for exponent in exponents
                                        ]
end

function verify(cert::AlgebraicSOSGramCertificate;
                io::Union{Nothing, IO}=nothing,
                strict::Bool=false,
                kwargs...)
    if strict
        return _strict_verify_certificate_object(certificate_json_v1(cert); io,
                                                 kwargs...)
    end

    try
        _check_or_report(io,
                         cert.hash == algebraic_sos_gram_certificate_hash(cert),
                         "algebraic SOS Gram certificate hash matches") ||
            return false
        _check_or_report(io,
                         _algebraic_root_interval_verified(cert.problem.root),
                         "algebraic SOS root interval isolates one real root") ||
            return false
        expected = algebraic_sos_coefficient_matching(cert.problem,
                                                      cert.gram_matrix)
        _check_or_report(io,
                         _algebraic_sos_matches_equal(cert.coefficient_proof,
                                                      expected),
                         "algebraic SOS coefficient metadata matches recomputation") ||
            return false
        _check_or_report(io,
                         all(match -> match.target_coefficient ==
                                      match.gram_coefficient,
                             cert.coefficient_proof),
                         "algebraic SOS coefficient matching is exact") ||
            return false
        _check_or_report(io,
                         _algebraic_matrices_equal(cert.gram_matrix,
                                                   cert.psd_proof.matrix),
                         "algebraic SOS PSD proof matrix matches Gram matrix") ||
            return false
        _verify_algebraic_psd_proof_for_block(cert.gram_matrix,
                                              cert.psd_proof,
                                              io;
                                              block_index=1) ||
            return false
        _ok(io, "algebraic SOS Gram certificate accepted")
        return true
    catch err
        _fail(io,
              "algebraic SOS Gram certificate verification error: $(sprint(showerror, err))")
        return false
    end
end

function algebraic_sos_gram_problem_hash(problem::AlgebraicSOSGramProblem)
    return "sha256:" *
           bytes2hex(sha256(JSON3.write(_algebraic_sos_gram_problem_json(problem))))
end

function algebraic_sos_gram_certificate_hash(cert::AlgebraicSOSGramCertificate)
    return "sha256:" *
           bytes2hex(sha256(JSON3.write(_canonical_algebraic_sos_gram_certificate_json(cert))))
end

function certificate_json_v1(cert::AlgebraicSOSGramCertificate)
    return merge(_canonical_algebraic_sos_gram_certificate_json(cert),
                 (; certificate_id=cert.hash,))
end

function write_certificate(path::AbstractString, cert::AlgebraicSOSGramCertificate)
    open(path, "w") do io
        return write(io, certificate_json_v1_string(cert))
    end
    return path
end

function save_certificate(path::AbstractString, cert::AlgebraicSOSGramCertificate)
    return write_certificate(path, cert)
end

function _canonical_algebraic_sos_gram_certificate_json(cert::AlgebraicSOSGramCertificate)
    problem_hash = algebraic_sos_gram_problem_hash(cert.problem)
    return (;
            certsdp_certificate_version=SCHEMA_V1_VERSION,
            certificate_type=ALGEBRAIC_SOS_GRAM_CERTIFICATE_TYPE,
            problem_hash,
            problem=(;
                     embedded=true,
                     type=ALGEBRAIC_SOS_GRAM_PROBLEM_TYPE,
                     data=merge(_algebraic_sos_gram_problem_json(cert.problem),
                                (; hash=problem_hash,)),),
            solution=(;
                      field="QQ(alpha)",
                      representation=ALGEBRAIC_SOS_GRAM_SOLUTION_TYPE,
                      root_symbol="t",
                      minimal_polynomial=string(cert.problem.root.f),
                      root_interval=[_rational_string(cert.problem.root.interval.lower),
                                     _rational_string(cert.problem.root.interval.upper)],
                      gram_matrix=_json_algebraic_matrix(cert.gram_matrix),),
            coefficient_proof=(;
                               method="exact_coefficient_matching",
                               identity="target_equals_v_transpose_Q_v_over_QQ_alpha",
                               matches=_algebraic_sos_matches_json(cert.coefficient_proof),),
            proof=(;
                   coefficient_matching=(;
                                         method="exact_coefficient_matching",
                                         status="claimed",
                                         equations=length(cert.coefficient_proof),),
                   psd=_algebraic_psd_proof_json(cert.psd_proof),),
            provenance=_positive_certificate_provenance_json(cert.metadata,
                                                             "algebraic_sos_gram"),
            verification=_positive_certificate_verification_json(cert.metadata),)
end

function _algebraic_sos_gram_problem_json(problem::AlgebraicSOSGramProblem)
    return (;
            certsdp_problem_version=SCHEMA_V1_VERSION,
            type=ALGEBRAIC_SOS_GRAM_PROBLEM_TYPE,
            field="QQ(alpha)",
            variables=String.(problem.variables),
            basis=[copy(entry) for entry in problem.basis],
            root_symbol="t",
            minimal_polynomial=string(problem.root.f),
            root_interval=[_rational_string(problem.root.interval.lower),
                           _rational_string(problem.root.interval.upper)],
            polynomial=[(;
                         exponents=copy(term.exponents),
                         coefficient=algebraic_element_string(term.coefficient),)
                        for term in problem.polynomial],)
end

function _parse_algebraic_sos_gram_certificate_v1_object(parsed)
    _require_value(parsed, CERTSDP_CERTIFICATE_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.certsdp_certificate_version")
    _require_value(parsed, :certificate_type, ALGEBRAIC_SOS_GRAM_CERTIFICATE_TYPE,
                   "root.certificate_type")
    certificate_id = _require_string(parsed, :certificate_id, "root.certificate_id")
    _validate_sha256_identifier(certificate_id, "root.certificate_id")
    problem_block = _require_key(parsed, :problem, "root")
    _require_object(problem_block, "root.problem")
    _require_value(problem_block, :embedded, true, "root.problem.embedded")
    _require_value(problem_block, :type, ALGEBRAIC_SOS_GRAM_PROBLEM_TYPE,
                   "root.problem.type")
    problem = _parse_algebraic_sos_gram_problem_v1_document(_require_key(problem_block,
                                                                         :data,
                                                                         "root.problem"))
    supplied_problem_hash = _require_string(parsed, :problem_hash,
                                            "root.problem_hash")
    problem_hash = algebraic_sos_gram_problem_hash(problem)
    supplied_problem_hash == problem_hash ||
        throw(ArgumentError("root.problem_hash mismatch: expected $supplied_problem_hash, computed $problem_hash"))
    _require_string(_require_key(problem_block, :data, "root.problem"), :hash,
                    "root.problem.data.hash") == problem_hash ||
        throw(ArgumentError("root.problem.data.hash must match root.problem_hash"))

    solution = _require_key(parsed, :solution, "root")
    _require_object(solution, "root.solution")
    _require_value(solution, :field, "QQ(alpha)", "root.solution.field")
    _require_value(solution, :representation, ALGEBRAIC_SOS_GRAM_SOLUTION_TYPE,
                   "root.solution.representation")
    _require_value(solution, :root_symbol, "t", "root.solution.root_symbol")
    _require_value(solution, :minimal_polynomial, string(problem.root.f),
                   "root.solution.minimal_polynomial")
    interval_value = _require_key(solution, :root_interval, "root.solution")
    _require_array(interval_value, "root.solution.root_interval")
    length(interval_value) == 2 ||
        throw(ArgumentError("root.solution.root_interval must contain exactly two rational endpoints"))
    _parse_rational_string(interval_value[1], "root.solution.root_interval[1]") ==
    problem.root.interval.lower ||
        throw(ArgumentError("root.solution.root_interval[1] must match problem root interval"))
    _parse_rational_string(interval_value[2], "root.solution.root_interval[2]") ==
    problem.root.interval.upper ||
        throw(ArgumentError("root.solution.root_interval[2] must match problem root interval"))

    gram = _parse_algebraic_matrix(_require_key(solution, :gram_matrix,
                                                "root.solution"),
                                   length(problem.basis),
                                   problem.root,
                                   "root.solution.gram_matrix")
    coefficient = _require_key(parsed, :coefficient_proof, "root")
    _require_object(coefficient, "root.coefficient_proof")
    _require_value(coefficient, :method, "exact_coefficient_matching",
                   "root.coefficient_proof.method")
    _require_value(coefficient, :identity,
                   "target_equals_v_transpose_Q_v_over_QQ_alpha",
                   "root.coefficient_proof.identity")
    matches = _parse_algebraic_sos_matches_array(_require_key(coefficient,
                                                              :matches,
                                                              "root.coefficient_proof"),
                                                 length(problem.variables),
                                                 problem.root,
                                                 "root.coefficient_proof.matches")
    proof = _require_key(parsed, :proof, "root")
    _require_object(proof, "root.proof")
    psd = _parse_algebraic_psd_proof(_require_key(proof, :psd, "root.proof"),
                                     length(problem.basis), problem.root)
    provenance = _require_key(parsed, :provenance, "root")
    verification = _require_key(parsed, :verification, "root")
    _require_object(provenance, "root.provenance")
    _require_object(verification, "root.verification")
    metadata = _positive_certificate_metadata_from_blocks(provenance, verification)

    cert = AlgebraicSOSGramCertificate(problem, gram, psd, matches,
                                       certificate_id, metadata)
    cert.hash == algebraic_sos_gram_certificate_hash(cert) ||
        throw(ArgumentError("root.certificate_id must match the algebraic SOS Gram certificate hash"))
    return cert
end

function _parse_algebraic_sos_gram_problem_v1_document(value)
    _require_object(value, "root.problem.data")
    _require_value(value, CERTSDP_PROBLEM_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.problem.data.certsdp_problem_version")
    _require_value(value, :type, ALGEBRAIC_SOS_GRAM_PROBLEM_TYPE,
                   "root.problem.data.type")
    _require_value(value, :field, "QQ(alpha)", "root.problem.data.field")
    _require_value(value, :root_symbol, "t", "root.problem.data.root_symbol")
    root = AlgebraicRoot(parse_polynomial(_require_string(value,
                                                          :minimal_polynomial,
                                                          "root.problem.data.minimal_polynomial")),
                         _parse_algebraic_sos_root_interval(_require_key(value,
                                                                         :root_interval,
                                                                         "root.problem.data"),
                                                            "root.problem.data.root_interval"))
    variables = _parse_sos_variables_at(_require_key(value, :variables,
                                                     "root.problem.data"),
                                        "root.problem.data.variables")
    basis = _parse_sos_basis(_require_key(value, :basis, "root.problem.data"),
                             length(variables))
    polynomial = _parse_algebraic_polynomial_terms_at(_require_key(value,
                                                                   :polynomial,
                                                                   "root.problem.data"),
                                                      length(variables),
                                                      root,
                                                      "root.problem.data.polynomial")
    return AlgebraicSOSGramProblem(variables, basis, polynomial)
end

function _parse_algebraic_sos_root_interval(value, path::AbstractString)
    _require_array(value, path)
    length(value) == 2 ||
        throw(ArgumentError("$path must contain exactly two rational endpoints"))
    return RationalInterval(_parse_rational_string(value[1], "$path[1]"),
                            _parse_rational_string(value[2], "$path[2]"))
end

function _parse_algebraic_polynomial_terms_at(value,
                                              variable_count::Integer,
                                              root::AlgebraicRoot,
                                              path::AbstractString)
    _require_array(value, path)
    terms = AlgebraicPolynomialTerm[]
    for (i, entry) in enumerate(value)
        term_path = "$path[$i]"
        _require_object(entry, term_path)
        exponents = _sos_exponent_vector(_require_key(entry, :exponents,
                                                      term_path),
                                         variable_count,
                                         "$term_path.exponents")
        coefficient = AlgebraicElement(root,
                                       _require_string(entry, :coefficient,
                                                       "$term_path.coefficient"))
        push!(terms, AlgebraicPolynomialTerm(exponents, coefficient))
    end
    return _normalize_algebraic_polynomial_terms(terms, variable_count, root)
end

function _parse_algebraic_sos_matches_array(value,
                                            variable_count::Integer,
                                            root::AlgebraicRoot,
                                            path::AbstractString)
    _require_array(value, path)
    matches = AlgebraicSOSCoefficientMatch[]
    for (i, entry) in enumerate(value)
        match_path = "$path[$i]"
        _require_object(entry, match_path)
        exponents = _sos_exponent_vector(_require_key(entry, :exponents,
                                                      match_path),
                                         variable_count,
                                         "$match_path.exponents")
        target = AlgebraicElement(root,
                                  _require_string(entry, :target_coefficient,
                                                  "$match_path.target_coefficient"))
        gram = AlgebraicElement(root,
                                _require_string(entry, :gram_coefficient,
                                                "$match_path.gram_coefficient"))
        contributions_value = _require_key(entry, :contributions, match_path)
        _require_array(contributions_value, "$match_path.contributions")
        contributions = AlgebraicSOSContribution[]
        for (j, contribution_value) in enumerate(contributions_value)
            contribution_path = "$match_path.contributions[$j]"
            _require_object(contribution_value, contribution_path)
            i_index = _require_integer(contribution_value, :i,
                                       "$contribution_path.i")
            j_index = _require_integer(contribution_value, :j,
                                       "$contribution_path.j")
            multiplier = _require_integer(contribution_value, :multiplier,
                                          "$contribution_path.multiplier")
            entry_value = AlgebraicElement(root,
                                           _require_string(contribution_value,
                                                           :gram_entry,
                                                           "$contribution_path.gram_entry"))
            push!(contributions,
                  AlgebraicSOSContribution(i_index, j_index, multiplier,
                                           entry_value))
        end
        push!(matches, AlgebraicSOSCoefficientMatch(exponents, target, gram,
                                                    contributions))
    end
    return matches
end

function _algebraic_sos_matches_json(matches::Vector{AlgebraicSOSCoefficientMatch})
    return [(;
             exponents=copy(match.exponents),
             target_coefficient=algebraic_element_string(match.target_coefficient),
             gram_coefficient=algebraic_element_string(match.gram_coefficient),
             contributions=[(;
                             i=contribution.i,
                             j=contribution.j,
                             multiplier=contribution.multiplier,
                             gram_entry=algebraic_element_string(contribution.gram_entry),
                             contribution=algebraic_element_string(contribution.contribution),)
                            for contribution in match.contributions],)
            for match in matches]
end

function _as_algebraic_polynomial_term(value::AlgebraicPolynomialTerm,
                                       variable_count::Integer,
                                       path::AbstractString)
    length(value.exponents) == variable_count ||
        throw(ArgumentError("$path exponent length $(length(value.exponents)) does not match variable count $variable_count"))
    return value
end

function _as_algebraic_polynomial_term(value::NamedTuple,
                                       variable_count::Integer,
                                       path::AbstractString)
    haskey(value, :exponents) || throw(ArgumentError("$path is missing `exponents`"))
    haskey(value, :coefficient) ||
        throw(ArgumentError("$path is missing `coefficient`"))
    value.coefficient isa AlgebraicElement ||
        throw(ArgumentError("$path.coefficient must be an AlgebraicElement"))
    return AlgebraicPolynomialTerm(_sos_exponent_vector(value.exponents,
                                                        variable_count,
                                                        "$path.exponents"),
                                   value.coefficient)
end

function _as_algebraic_polynomial_term(value,
                                       variable_count::Integer,
                                       path::AbstractString)
    throw(ArgumentError("$path must be an AlgebraicPolynomialTerm or named tuple"))
end

function _normalize_algebraic_polynomial_terms(terms::AbstractVector,
                                               variable_count::Integer,
                                               root::AlgebraicRoot)
    dict = Dict{Tuple{Vararg{Int}}, AlgebraicElement}()
    for (i, term) in enumerate(terms)
        normalized = _as_algebraic_polynomial_term(term, variable_count,
                                                   "polynomial[$i]")
        normalized.coefficient.root == root ||
            throw(ArgumentError("algebraic polynomial coefficients must share one root representation"))
        exponent = tuple(normalized.exponents...)
        dict[exponent] = get(dict, exponent, AlgebraicElement(root, 0)) +
                         normalized.coefficient
        iszero(dict[exponent]) && delete!(dict, exponent)
    end
    return [AlgebraicPolynomialTerm(collect(exponent), dict[exponent])
            for exponent in sort(collect(keys(dict)); lt=_sos_exponent_order_lt)]
end

function _algebraic_terms_dict(terms::Vector{AlgebraicPolynomialTerm},
                               root::AlgebraicRoot)
    result = Dict{Tuple{Vararg{Int}}, AlgebraicElement}()
    for term in terms
        term.coefficient.root == root ||
            throw(ArgumentError("algebraic polynomial coefficients must share one root representation"))
        exponent = tuple(term.exponents...)
        result[exponent] = get(result, exponent, AlgebraicElement(root, 0)) +
                           term.coefficient
        iszero(result[exponent]) && delete!(result, exponent)
    end
    return result
end

function _as_symmetric_algebraic_gram_matrix(matrix,
                                             root::AlgebraicRoot,
                                             expected_size::Integer)
    expected_size > 0 ||
        throw(ArgumentError("algebraic Gram matrix expected size must be positive"))
    matrix isa AbstractMatrix ||
        throw(ArgumentError("algebraic Gram matrix must be a matrix"))
    size(matrix) == (expected_size, expected_size) ||
        throw(DimensionMismatch("algebraic Gram matrix has size $(size(matrix)); expected $((expected_size, expected_size))"))
    result = Matrix{AlgebraicElement}(undef, expected_size, expected_size)
    for i in 1:expected_size, j in 1:expected_size
        value = matrix[i, j]
        element = if value isa AlgebraicElement
            value.root == root ||
                throw(ArgumentError("algebraic Gram matrix entries must share the problem root representation"))
            value
        elseif value isa AbstractString
            AlgebraicElement(root, value)
        elseif value isa Integer || value isa Rational
            AlgebraicElement(root, value)
        else
            throw(ArgumentError("algebraic Gram matrix entry [$i,$j] must be an AlgebraicElement, rational-function string, integer, or rational"))
        end
        result[i, j] = element
    end
    _check_algebraic_symmetric(result; name=:algebraic_sos_gram_matrix)
    return result
end

function _algebraic_sos_matches_equal(a::Vector{AlgebraicSOSCoefficientMatch},
                                      b::Vector{AlgebraicSOSCoefficientMatch})
    length(a) == length(b) || return false
    for (left, right) in zip(a, b)
        left.exponents == right.exponents || return false
        left.target_coefficient == right.target_coefficient || return false
        left.gram_coefficient == right.gram_coefficient || return false
        _algebraic_sos_contributions_equal(left.contributions,
                                           right.contributions) || return false
    end
    return true
end

function _algebraic_sos_contributions_equal(a::Vector{AlgebraicSOSContribution},
                                            b::Vector{AlgebraicSOSContribution})
    length(a) == length(b) || return false
    for (left, right) in zip(a, b)
        left.i == right.i || return false
        left.j == right.j || return false
        left.multiplier == right.multiplier || return false
        left.gram_entry == right.gram_entry || return false
        left.contribution == right.contribution || return false
    end
    return true
end
