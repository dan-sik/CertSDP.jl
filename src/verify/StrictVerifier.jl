const STRICT_VERIFIER_FORBIDDEN_TOP_LEVEL_KEYS = Set([:approximate_solution,
                                                      :numerical_solution,
                                                      :solver_output])

const STRICT_VERIFIER_FORBIDDEN_PROOF_KEYS = Set([:approximate_equality,
                                                  :approx_equality,
                                                  :numerical_equality,
                                                  :float_tolerance,
                                                  :tolerance,
                                                  :epsilon,
                                                  :backend_artifact,
                                                  :backend_artifacts,
                                                  :backend_log,
                                                  :backend_output,
                                                  :msolve_output,
                                                  :msolve_log])

const STRICT_VERIFIER_FORBIDDEN_METHOD_KEYWORDS = ("approx",
                                                   "floating",
                                                   "float",
                                                   "numeric",
                                                   "numerical",
                                                   "solver",
                                                   "backend",
                                                   "msolve")

"""
    verify_strict(path; io=nothing) -> Bool

Independent replay verifier entrypoint. It accepts only schema v1.0, embedded
problem hashes, and complete exact proof fields, then replays the ordinary exact
verifier. Backend logs, numerical solver output, and approximate-equality
claims are rejected before parsing as a certificate.
"""
function verify_strict(path::AbstractString; io::Union{Nothing, IO}=nothing,
                       cache::Bool=true, cache_object=nothing)
    parsed = try
        _read_json_document(read(path, String), "strict certificate")
    catch err
        _fail(io, "strict schema error: $(sprint(showerror, err))")
        return false
    end
    return verify_strict(parsed; io, cache, cache_object)
end

function verify_strict_json(json_text::AbstractString; io::Union{Nothing, IO}=nothing,
                            cache::Bool=true, cache_object=nothing)
    parsed = try
        _read_json_document(json_text, "strict certificate")
    catch err
        _fail(io, "strict schema error: $(sprint(showerror, err))")
        return false
    end
    return verify_strict(parsed; io, cache, cache_object)
end

function verify_strict(parsed::JSON3.Object; io::Union{Nothing, IO}=nothing,
                       cache::Bool=true, cache_object=nothing)
    cert = try
        _strict_validate_certificate_object(parsed)
        _parse_certificate_v1_object(parsed)
    catch err
        _fail(io, "strict schema error: $(sprint(showerror, err))")
        return false
    end
    return verify(cert; io, strict=false, cache, cache_object)
end

function _strict_verify_certificate_object(object; io::Union{Nothing, IO}=nothing,
                                           cache::Bool=true, cache_object=nothing)
    parsed = JSON3.read(JSON3.write(object))
    return verify_strict(parsed; io, cache, cache_object)
end

function _strict_validate_certificate_object(parsed)
    _require_object(parsed, "root")
    _strict_reject_forbidden_keys(parsed, STRICT_VERIFIER_FORBIDDEN_TOP_LEVEL_KEYS,
                                  "root")
    _require_value(parsed, CERTSDP_CERTIFICATE_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.certsdp_certificate_version")

    certificate_type = _require_string(parsed, :certificate_type,
                                       "root.certificate_type")
    _require_string(parsed, :certificate_id, "root.certificate_id")
    _require_string(parsed, :problem_hash, "root.problem_hash")
    _require_object(_require_key(parsed, :solution, "root"), "root.solution")
    _strict_require_problem_hash_complete(parsed, certificate_type)
    _strict_require_exact_proof_complete(parsed, certificate_type)
    _strict_reject_forbidden_trust_claims(parsed, "root")
    _strict_validate_provenance_block(_require_key(parsed, :provenance, "root"))
    _strict_validate_verification_block(_require_key(parsed, :verification, "root"))

    # Schema parsing checks canonical hashes, field shapes, and method-specific
    # exact proof data. Strict mode keeps this before exact replay so malformed
    # user-supplied files fail without touching backend code.
    _parse_certificate_v1_object(parsed)
    return true
end

function _strict_require_problem_hash_complete(parsed, certificate_type::AbstractString)
    problem_hash = _require_string(parsed, :problem_hash, "root.problem_hash")
    _validate_sha256_identifier(problem_hash, "root.problem_hash")

    if certificate_type == SOS_GRAM_CERTIFICATE_TYPE
        sos_problem = _require_key(parsed, :sos_problem, "root")
        _require_object(sos_problem, "root.sos_problem")
        _require_value(sos_problem, :type, SOS_GRAM_PROBLEM_TYPE,
                       "root.sos_problem.type")
        _require_value(sos_problem, :field, LMI_FIELD, "root.sos_problem.field")
        embedded_hash = _require_string(sos_problem, :hash, "root.sos_problem.hash")
        embedded_hash == problem_hash ||
            throw(ArgumentError("root.problem_hash mismatch: must match root.sos_problem.hash in strict mode"))
        lmi_certificate = _require_key(parsed, :lmi_certificate, "root")
        _require_object(lmi_certificate, "root.lmi_certificate")
        _strict_require_embedded_lmi_certificate_v1(lmi_certificate,
                                                    "root.lmi_certificate")
        return true
    end

    if certificate_type == ALGEBRAIC_SOS_GRAM_CERTIFICATE_TYPE
        problem = _require_key(parsed, :problem, "root")
        _require_object(problem, "root.problem")
        _require_value(problem, :embedded, true, "root.problem.embedded")
        _require_value(problem, :type, ALGEBRAIC_SOS_GRAM_PROBLEM_TYPE,
                       "root.problem.type")
        data = _require_key(problem, :data, "root.problem")
        _require_object(data, "root.problem.data")
        _require_value(data, CERTSDP_PROBLEM_VERSION_KEY, SCHEMA_V1_VERSION,
                       "root.problem.data.certsdp_problem_version")
        _require_value(data, :type, ALGEBRAIC_SOS_GRAM_PROBLEM_TYPE,
                       "root.problem.data.type")
        _require_value(data, :field, "QQ(alpha)", "root.problem.data.field")
        embedded_hash = _require_string(data, :hash, "root.problem.data.hash")
        embedded_hash == problem_hash ||
            throw(ArgumentError("root.problem_hash mismatch: must match root.problem.data.hash in strict mode"))
        return true
    end

    if certificate_type == RATIONAL_FUNCTION_SOS_CERTIFICATE_TYPE ||
       certificate_type == POSITIVSTELLENSATZ_CERTIFICATE_TYPE ||
       certificate_type == PERTURBATION_COMPENSATION_CERTIFICATE_TYPE
        expected_problem_type = if certificate_type ==
                                   RATIONAL_FUNCTION_SOS_CERTIFICATE_TYPE
            RATIONAL_FUNCTION_SOS_PROBLEM_TYPE
        elseif certificate_type == POSITIVSTELLENSATZ_CERTIFICATE_TYPE
            POSITIVSTELLENSATZ_PROBLEM_TYPE
        else
            PERTURBATION_COMPENSATION_PROBLEM_TYPE
        end
        problem = _require_key(parsed, :problem, "root")
        _require_object(problem, "root.problem")
        embedded = _require_key(problem, :embedded, "root.problem")
        embedded === true ||
            throw(ArgumentError("root.problem.embedded must be true in strict mode"))
        _require_value(problem, :type, expected_problem_type, "root.problem.type")
        data = _require_key(problem, :data, "root.problem")
        _require_object(data, "root.problem.data")
        _require_value(data, CERTSDP_PROBLEM_VERSION_KEY, SCHEMA_V1_VERSION,
                       "root.problem.data.certsdp_problem_version")
        _require_value(data, :type, expected_problem_type, "root.problem.data.type")
        embedded_hash = _require_string(data, :hash, "root.problem.data.hash")
        embedded_hash == problem_hash ||
            throw(ArgumentError("root.problem_hash mismatch: must match root.problem.data.hash in strict mode"))
        return true
    end

    problem = _require_key(parsed, :problem, "root")
    _require_object(problem, "root.problem")
    embedded = _require_key(problem, :embedded, "root.problem")
    embedded === true ||
        throw(ArgumentError("root.problem.embedded must be true in strict mode"))
    expected_problem_type = certificate_type == BLOCK_RATIONAL_CERTIFICATE_TYPE ||
                            certificate_type == BLOCK_ALGEBRAIC_CERTIFICATE_TYPE ?
                            SDPA_PROBLEM_TYPE : LMI_PROBLEM_TYPE
    _require_value(problem, :type, expected_problem_type, "root.problem.type")
    data = _require_key(problem, :data, "root.problem")
    _require_object(data, "root.problem.data")
    _require_value(data, CERTSDP_PROBLEM_VERSION_KEY, SCHEMA_V1_VERSION,
                   "root.problem.data.certsdp_problem_version")
    embedded_hash = _require_string(data, :hash, "root.problem.data.hash")
    embedded_hash == problem_hash ||
        throw(ArgumentError("root.problem_hash mismatch: must match root.problem.data.hash in strict mode"))
    return true
end

function _strict_require_embedded_lmi_certificate_v1(cert, path::AbstractString)
    haskey(cert, CERTSDP_CERTIFICATE_VERSION_KEY) ||
        throw(ArgumentError("$path.certsdp_certificate_version is missing required key `certsdp_certificate_version`"))
    _require_value(cert, CERTSDP_CERTIFICATE_VERSION_KEY, SCHEMA_V1_VERSION,
                   "$path.certsdp_certificate_version")
    _require_string(cert, :certificate_id, "$path.certificate_id")
    _require_string(cert, :problem_hash, "$path.problem_hash")
    _strict_require_problem_hash_complete(cert,
                                          _require_string(cert, :certificate_type,
                                                          "$path.certificate_type"))
    _strict_require_exact_proof_complete(cert,
                                         _require_string(cert, :certificate_type,
                                                         "$path.certificate_type"))
    _strict_reject_forbidden_trust_claims(cert, path)
    _strict_validate_provenance_block(_require_key(cert, :provenance, path),
                                      "$path.provenance")
    _strict_validate_verification_block(_require_key(cert, :verification, path),
                                        "$path.verification")
    return true
end

function _strict_require_exact_proof_complete(parsed, certificate_type::AbstractString)
    if certificate_type == SOS_GRAM_CERTIFICATE_TYPE
        _strict_require_sos_exact_proof_complete(parsed)
        return true
    elseif certificate_type == ALGEBRAIC_SOS_GRAM_CERTIFICATE_TYPE
        _strict_require_algebraic_sos_exact_proof_complete(parsed)
        return true
    elseif certificate_type == RATIONAL_FUNCTION_SOS_CERTIFICATE_TYPE ||
           certificate_type == POSITIVSTELLENSATZ_CERTIFICATE_TYPE ||
           certificate_type == PERTURBATION_COMPENSATION_CERTIFICATE_TYPE
        _strict_require_positive_exact_proof_complete(parsed, certificate_type)
        return true
    end

    proof = _require_key(parsed, :proof, "root")
    _require_object(proof, "root.proof")
    linear = _require_key(proof, :linear_constraints, "root.proof")
    _require_object(linear, "root.proof.linear_constraints")
    _require_value(linear, :method, "exact_substitution",
                   "root.proof.linear_constraints.method")
    haskey(linear, :status) ||
        throw(ArgumentError("root.proof.linear_constraints.status is missing required key `status`"))
    _require_value(linear, :status, "claimed", "root.proof.linear_constraints.status")
    psd = _require_key(proof, :psd, "root.proof")
    _strict_require_psd_proof_complete(psd, "root.proof.psd")
    return true
end

function _strict_require_algebraic_sos_exact_proof_complete(parsed)
    solution = _require_key(parsed, :solution, "root")
    _require_object(solution, "root.solution")
    _require_value(solution, :field, "QQ(alpha)", "root.solution.field")
    _require_value(solution, :representation, ALGEBRAIC_SOS_GRAM_SOLUTION_TYPE,
                   "root.solution.representation")
    _require_value(solution, :root_symbol, "t", "root.solution.root_symbol")
    _require_string(solution, :minimal_polynomial,
                    "root.solution.minimal_polynomial")
    interval = _require_key(solution, :root_interval, "root.solution")
    _require_array(interval, "root.solution.root_interval")
    length(interval) == 2 ||
        throw(ArgumentError("root.solution.root_interval must contain exactly two rational endpoints"))
    _require_key(solution, :gram_matrix, "root.solution")

    coefficient = _require_key(parsed, :coefficient_proof, "root")
    _require_object(coefficient, "root.coefficient_proof")
    _require_value(coefficient, :method, "exact_coefficient_matching",
                   "root.coefficient_proof.method")
    _require_value(coefficient, :identity,
                   "target_equals_v_transpose_Q_v_over_QQ_alpha",
                   "root.coefficient_proof.identity")
    _require_array(_require_key(coefficient, :matches, "root.coefficient_proof"),
                   "root.coefficient_proof.matches")

    proof = _require_key(parsed, :proof, "root")
    _require_object(proof, "root.proof")
    matching = _require_key(proof, :coefficient_matching, "root.proof")
    _require_object(matching, "root.proof.coefficient_matching")
    _require_value(matching, :method, "exact_coefficient_matching",
                   "root.proof.coefficient_matching.method")
    _require_value(matching, :status, "claimed",
                   "root.proof.coefficient_matching.status")
    _strict_require_psd_proof_complete(_require_key(proof, :psd, "root.proof"),
                                       "root.proof.psd")
    return true
end

function _strict_require_positive_exact_proof_complete(parsed,
                                                       certificate_type::AbstractString)
    solution = _require_key(parsed, :solution, "root")
    _require_object(solution, "root.solution")
    _require_value(solution, :field, LMI_FIELD, "root.solution.field")
    expected_representation = if certificate_type == RATIONAL_FUNCTION_SOS_CERTIFICATE_TYPE
        "rational_function_sos"
    elseif certificate_type == POSITIVSTELLENSATZ_CERTIFICATE_TYPE
        "sos_multipliers"
    else
        "perturbation_compensation_sos"
    end
    _require_value(solution, :representation, expected_representation,
                   "root.solution.representation")
    if certificate_type == RATIONAL_FUNCTION_SOS_CERTIFICATE_TYPE
        _strict_require_sos_square_block(_require_key(solution, :numerator_sos,
                                                      "root.solution"),
                                         "root.solution.numerator_sos")
        _strict_require_sos_square_block(_require_key(solution, :denominator_sos,
                                                      "root.solution"),
                                         "root.solution.denominator_sos")
    elseif certificate_type == POSITIVSTELLENSATZ_CERTIFICATE_TYPE
        terms = _require_key(solution, :terms, "root.solution")
        _require_array(terms, "root.solution.terms")
        isempty(terms) && throw(ArgumentError("root.solution.terms must not be empty"))
        for (i, term) in enumerate(terms)
            term_path = "root.solution.terms[$i]"
            _require_object(term, term_path)
            _require_array(_require_key(term, :constraint_product, term_path),
                           "$term_path.constraint_product")
            _strict_require_sos_square_block(_require_key(term, :sos, term_path),
                                             "$term_path.sos")
        end
    else
        _strict_require_sos_square_block(_require_key(solution, :perturbed_sos,
                                                      "root.solution"),
                                         "root.solution.perturbed_sos")
        _strict_require_sos_square_block(_require_key(solution, :compensation_sos,
                                                      "root.solution"),
                                         "root.solution.compensation_sos")
    end

    coefficient = _require_key(parsed, :coefficient_proof, "root")
    _require_object(coefficient, "root.coefficient_proof")
    _require_value(coefficient, :method, "exact_coefficient_matching",
                   "root.coefficient_proof.method")
    expected_identity = if certificate_type == RATIONAL_FUNCTION_SOS_CERTIFICATE_TYPE
        "denominator_times_target_equals_numerator"
    elseif certificate_type == POSITIVSTELLENSATZ_CERTIFICATE_TYPE
        "target_equals_sos_constraint_assembly"
    else
        "target_plus_perturbation_equals_perturbed_sos_and_target_equals_perturbed_minus_compensation"
    end
    _require_value(coefficient, :identity, expected_identity,
                   "root.coefficient_proof.identity")
    if certificate_type == PERTURBATION_COMPENSATION_CERTIFICATE_TYPE
        _require_array(_require_key(coefficient, :perturbed_matches,
                                    "root.coefficient_proof"),
                       "root.coefficient_proof.perturbed_matches")
        _require_array(_require_key(coefficient, :compensation_matches,
                                    "root.coefficient_proof"),
                       "root.coefficient_proof.compensation_matches")
    else
        _require_array(_require_key(coefficient, :matches, "root.coefficient_proof"),
                       "root.coefficient_proof.matches")
    end

    proof = _require_key(parsed, :proof, "root")
    _require_object(proof, "root.proof")
    if certificate_type == PERTURBATION_COMPENSATION_CERTIFICATE_TYPE
        for key in (:perturbed_identity, :compensation_identity)
            identity = _require_key(proof, key, "root.proof")
            path = "root.proof.$(String(key))"
            _require_object(identity, path)
            _require_value(identity, :method, "exact_coefficient_matching",
                           "$path.method")
            _require_value(identity, :status, "claimed", "$path.status")
        end
    else
        identity = _require_key(proof, :identity, "root.proof")
        _require_object(identity, "root.proof.identity")
        _require_value(identity, :method, "exact_coefficient_matching",
                       "root.proof.identity.method")
        _require_value(identity, :status, "claimed", "root.proof.identity.status")
    end
    sos = _require_key(proof, :sos, "root.proof")
    _require_object(sos, "root.proof.sos")
    _require_value(sos, :method, EXPLICIT_RATIONAL_SQUARES_METHOD,
                   "root.proof.sos.method")
    return true
end

function _strict_require_sos_square_block(block, path::AbstractString)
    _require_object(block, path)
    _require_value(block, :method, EXPLICIT_RATIONAL_SQUARES_METHOD,
                   "$path.method")
    _require_array(_require_key(block, :squares, path), "$path.squares")
    return true
end

function _strict_require_sos_exact_proof_complete(parsed)
    coefficient = _require_key(parsed, :coefficient_proof, "root")
    _require_object(coefficient, "root.coefficient_proof")
    _require_value(coefficient, :method, "exact_coefficient_matching",
                   "root.coefficient_proof.method")
    _require_array(_require_key(coefficient, :matches, "root.coefficient_proof"),
                   "root.coefficient_proof.matches")

    proof = _require_key(parsed, :proof, "root")
    _require_object(proof, "root.proof")
    matching = _require_key(proof, :coefficient_matching, "root.proof")
    _require_object(matching, "root.proof.coefficient_matching")
    _require_value(matching, :method, "exact_coefficient_matching",
                   "root.proof.coefficient_matching.method")
    _require_value(matching, :status, "claimed",
                   "root.proof.coefficient_matching.status")
    psd = _require_key(proof, :psd, "root.proof")
    _require_object(psd, "root.proof.psd")
    _require_value(psd, :method, "embedded_rational_psd_certificate",
                   "root.proof.psd.method")
    _require_string(psd, :certificate_id, "root.proof.psd.certificate_id")
    _require_object(_require_key(parsed, :lmi_certificate, "root"),
                    "root.lmi_certificate")
    return true
end

function _strict_require_psd_proof_complete(proof, path::AbstractString)
    _require_object(proof, path)
    method = _require_string(proof, :method, "$path.method")
    _strict_exact_method(method, "$path.method")

    if method == BLOCKWISE_PSD_METHOD
        blocks = _require_key(proof, :blocks, path)
        _require_array(blocks, "$path.blocks")
        isempty(blocks) && throw(ArgumentError("$path.blocks must not be empty"))
        for (i, block) in enumerate(blocks)
            block_path = "$path.blocks[$i]"
            _require_object(block, block_path)
            index = _require_integer(block, :block_index, "$block_path.block_index")
            index == i || throw(ArgumentError("$block_path.block_index must be $i"))
            _strict_require_psd_proof_complete(block, block_path)
        end
        return true
    end

    _require_key(proof, :substituted_matrix, path)
    data = _require_key(proof, :data, path)
    _require_object(data, "$path.data")

    if method == RATIONAL_PSD_METHOD
        _require_array(_require_key(data, :principal_minors, "$path.data"),
                       "$path.data.principal_minors")
    elseif method == SCHUR_ZERO_PSD_METHOD
        _require_key(data, :pivot_block, "$path.data")
        positive = _require_key(data, :positive_block, "$path.data")
        _require_object(positive, "$path.data.positive_block")
        _require_key(positive, :indices, "$path.data.positive_block")
        _require_value(positive, :proof, "sylvester_principal_minors_positive",
                       "$path.data.positive_block.proof")
        _require_array(_require_key(positive, :leading_principal_minors,
                                    "$path.data.positive_block"),
                       "$path.data.positive_block.leading_principal_minors")
        schur = _require_key(data, :schur_complement, "$path.data")
        _require_object(schur, "$path.data.schur_complement")
        _require_value(schur, :status, "zero", "$path.data.schur_complement.status")
        _require_key(schur, :entries, "$path.data.schur_complement")
    elseif method == LDL_PSD_METHOD
        _require_array(_require_key(data, :pivots, "$path.data"),
                       "$path.data.pivots")
    else
        throw(ArgumentError("$path.method is not an exact PSD method accepted by strict mode: `$method`"))
    end
    return true
end

function _strict_reject_forbidden_trust_claims(value, path::AbstractString)
    if value isa JSON3.Object
        for key in keys(value)
            symbol_key = Symbol(String(key))
            child_path = "$path.$(String(key))"
            if symbol_key in STRICT_VERIFIER_FORBIDDEN_PROOF_KEYS
                throw(ArgumentError("$child_path is forbidden in strict mode"))
            end
            if symbol_key in (:method, :representation)
                method = getproperty(value, symbol_key)
                method isa AbstractString &&
                    _strict_exact_method(String(method), child_path)
            end
            if symbol_key in (:provenance, :verification)
                continue
            end
            _strict_reject_forbidden_trust_claims(getproperty(value, symbol_key),
                                                  child_path)
        end
    elseif value isa JSON3.Array
        for (i, item) in enumerate(value)
            _strict_reject_forbidden_trust_claims(item, "$path[$i]")
        end
    end
    return true
end

function _strict_reject_forbidden_keys(object, forbidden::Set{Symbol},
                                       path::AbstractString)
    for key in keys(object)
        symbol_key = Symbol(String(key))
        symbol_key in forbidden &&
            throw(ArgumentError("$path.$(String(key)) is forbidden in strict mode"))
    end
    return true
end

function _strict_exact_method(method::AbstractString, path::AbstractString)
    lowered = lowercase(method)
    for keyword in STRICT_VERIFIER_FORBIDDEN_METHOD_KEYWORDS
        occursin(keyword, lowered) &&
            throw(ArgumentError("$path uses non-exact or backend-dependent method `$method`, forbidden in strict mode"))
    end
    return true
end

function _strict_validate_provenance_block(provenance,
                                           path::AbstractString="root.provenance")
    _require_object(provenance, path)
    if haskey(provenance, :numerical_solver)
        value = getproperty(provenance, :numerical_solver)
        !(isnothing(value) || value == "none") &&
            throw(ArgumentError("$path.numerical_solver must be absent, null, or `none` in strict mode"))
    end
    return true
end

function _strict_validate_verification_block(verification,
                                             path::AbstractString="root.verification")
    _require_object(verification, path)
    verifier_version = _require_string(verification, :verifier_version,
                                       "$path.verifier_version")
    isempty(verifier_version) &&
        throw(ArgumentError("$path.verifier_version must not be empty"))
    haskey(verification, :verified_at_creation) ||
        throw(ArgumentError("$path is missing required key `verified_at_creation`"))
    return true
end
