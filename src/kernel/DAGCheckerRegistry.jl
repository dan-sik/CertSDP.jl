module DAGCheckerRegistry

using ..Kernel
using ..SOSGramExpansion
using JSON3: JSON3

export DAGCheckerResult,
       dag_checker_registry,
       dag_checker_names,
       run_dag_checker,
       reset_dag_checker_calls!,
       dag_checker_calls

struct DAGCheckerResult
    accepted::Bool
    output_hash::String
    reason::String
    details::Dict{Symbol, Any}
end

const CALLS = Symbol[]
const REGISTRY = Dict{Symbol, Function}()

function reset_dag_checker_calls!()
    empty!(CALLS)
    return nothing
end

dag_checker_calls() = copy(CALLS)
dag_checker_names() = sort!(collect(keys(REGISTRY)); by=String)
dag_checker_registry() = REGISTRY

_ok(hash::AbstractString; details=Dict{Symbol, Any}()) =
    DAGCheckerResult(true, String(hash), "accepted", Dict{Symbol, Any}(details))
_bad(reason::AbstractString; hash::AbstractString="", details=Dict{Symbol, Any}()) =
    DAGCheckerResult(false, String(hash), String(reason), Dict{Symbol, Any}(details))

function _register!(name::Symbol, fn::Function)
    REGISTRY[name] = fn
end

function run_dag_checker(name::Symbol, node::Kernel.ProofNode,
                         dag::Kernel.CertificateDAG)
    haskey(REGISTRY, name) || return _bad("unknown DAG checker `$name`")
    push!(CALLS, name)
    return REGISTRY[name](node, dag)
end

function _payload_hash(payload)
    return Kernel._sha256_payload(Kernel._canonical_json_value(payload))
end

function _json_object(payload)
    return JSON3.read(JSON3.write(Kernel._canonical_json_value(payload)))
end

function _dict_get(object, key::Symbol, default=nothing)
    if object isa NamedTuple
        return haskey(object, key) ? getfield(object, key) : default
    elseif object isa AbstractDict
        return haskey(object, key) ? object[key] :
               haskey(object, String(key)) ? object[String(key)] : default
    end
    return default
end

function _payload_required(node, keys::Vector{Symbol})
    isempty(node.typed_payload) && return "missing typed payload"
    for key in keys
        haskey(node.typed_payload, key) || return "typed payload missing $(String(key))"
    end
    return nothing
end

function _typed_hash_checker(keys::Vector{Symbol})
    return function (node, dag)
        missing = _payload_required(node, keys)
        isnothing(missing) || return _bad(missing)
        return _ok(_payload_hash(Dict(key => node.typed_payload[key] for key in keys)),
                   details=Dict{Symbol, Any}(:checker => String(node.checker),
                                             :obligation_id => String(node.obligation_id)))
    end
end

function _sparse_matrix_hash_checker(node, dag)
    missing = _payload_required(node, [:matrix])
    isnothing(missing) || return _bad(missing)
    try
        matrix = Kernel.parse_sparse_matrix_object(_json_object(node.typed_payload[:matrix]);
                                                   strict=true,
                                                   path="dag.$(node.id).matrix")
        return _ok(Kernel.sparse_matrix_hash(matrix))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _sparse_sos_problem_hash_checker(node, dag)
    missing = _payload_required(node, [:problem])
    isnothing(missing) || return _bad(missing)
    try
        problem = Kernel._parse_sparse_sos_problem_object(_json_object(node.typed_payload[:problem]))
        return _ok(Kernel.sparse_sos_problem_hash(problem))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _npa_problem_hash_checker(node, dag)
    missing = _payload_required(node, [:problem])
    isnothing(missing) || return _bad(missing)
    try
        problem = Kernel._parse_npa_problem_object(_json_object(node.typed_payload[:problem]))
        return _ok(Kernel.npa_problem_hash(problem))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _chordal_structure_hash_checker(node, dag)
    missing = _payload_required(node, [:structure])
    isnothing(missing) || return _bad(missing)
    try
        structure = Kernel._parse_chordal_structure_object(_json_object(node.typed_payload[:structure]);
                                                           strict=true)
        return _ok(Kernel.chordal_structure_hash(structure))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _symmetry_group_hash_checker(node, dag)
    missing = _payload_required(node, [:group])
    isnothing(missing) || return _bad(missing)
    try
        group = Kernel._parse_symmetry_group_object(_json_object(node.typed_payload[:group]))
        return _ok(Kernel.symmetry_group_hash(group))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _orbit_basis_hash_checker(node, dag)
    missing = _payload_required(node, [:orbit_basis])
    isnothing(missing) || return _bad(missing)
    try
        orbit = Kernel._parse_orbit_basis_object(_json_object(node.typed_payload[:orbit_basis]))
        return _ok(Kernel.orbit_basis_hash(orbit))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _field_hash_checker(node, dag)
    missing = _payload_required(node, [:field])
    isnothing(missing) || return _bad(missing)
    try
        field = Kernel._parse_algebraic_field_certificate_object(_json_object(node.typed_payload[:field]),
                                                                  "dag.$(node.id).field")
        return _ok(Kernel.algebraic_field_certificate_hash(field))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _incidence_hash_checker(node, dag)
    missing = _payload_required(node, [:incidence])
    isnothing(missing) || return _bad(missing)
    try
        incidence = Kernel._parse_block_native_incidence_system_object(_json_object(node.typed_payload[:incidence]))
        return _ok(Kernel.block_native_incidence_system_hash(incidence))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _block_native_active_checker(node, dag)
    missing = _payload_required(node, [:active_block_proofs])
    isnothing(missing) || return _bad(missing)
    try
        proofs = Kernel.BlockNativeActiveBlockProof[
            Kernel._parse_block_native_active_block_proof(proof,
                                                          "dag.$(node.id).active_block_proofs[$i]")
            for (i, proof) in enumerate(_json_object(node.typed_payload[:active_block_proofs]))
        ]
        return _ok(Kernel._sha256_payload([proof.proof_hash for proof in proofs]))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _block_native_inactive_checker(node, dag)
    missing = _payload_required(node, [:inactive_psd_proofs])
    isnothing(missing) || return _bad(missing)
    try
        proofs = Kernel.BlockNativeInactivePSDProof[
            Kernel._parse_block_native_inactive_psd_proof(proof,
                                                          "dag.$(node.id).inactive_psd_proofs[$i]")
            for (i, proof) in enumerate(_json_object(node.typed_payload[:inactive_psd_proofs]))
        ]
        for proof in proofs
            report = Kernel.verify_low_rank_psd(proof.margin_matrix, proof.psd_proof)
            report.accepted || return _bad(report.reason)
        end
        return _ok(Kernel._sha256_payload([proof.proof_hash for proof in proofs]))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _block_native_certificate_checker(node, dag)
    missing = _payload_required(node, [:certificate])
    isnothing(missing) || return _bad(missing)
    try
        cert_payload = _json_object(node.typed_payload[:certificate])
        incidence = Kernel._parse_block_native_incidence_system_object(cert_payload.incidence)
        active = Dict{Int, Kernel.BlockNativeActiveBlockProof}()
        for proof_payload in cert_payload.active_block_proofs
            proof = Kernel._parse_block_native_active_block_proof(proof_payload,
                                                                  "dag.$(node.id).certificate.active")
            active[proof.block_index] = proof
        end
        inactive = Dict{Int, Kernel.BlockNativeInactivePSDProof}()
        for proof_payload in cert_payload.inactive_psd_proofs
            proof = Kernel._parse_block_native_inactive_psd_proof(proof_payload,
                                                                  "dag.$(node.id).certificate.inactive")
            inactive[proof.block_index] = proof
        end
        cert = Kernel.BlockNativeAlgebraicCertificate(String(cert_payload.problem_hash),
                                                      incidence, active, inactive, "")
        return _ok(Kernel.block_native_algebraic_certificate_hash(cert))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _low_rank_psd_checker(node, dag)
    missing = _payload_required(node, [:matrix, :proof])
    isnothing(missing) || return _bad(missing)
    try
        matrix_payload = _json_object(node.typed_payload[:matrix])
        proof_payload = _json_object(node.typed_payload[:proof])
        matrix = Kernel.parse_sparse_matrix_object(matrix_payload;
                                                   strict=true,
                                                   path="dag.$(node.id).matrix")
        proof = Kernel._parse_low_rank_proof_object(proof_payload,
                                                    matrix;
                                                    strict=false,
                                                    path="dag.$(node.id).proof")
        report = Kernel.verify_low_rank_psd(matrix, proof)
        report.accepted || return _bad(report.reason)
        return _ok(proof.identity_proof_hash)
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _algebraic_low_rank_checker(node, dag)
    missing = _payload_required(node, [:matrix, :proof])
    isnothing(missing) || return _bad(missing)
    try
        matrix = Kernel.parse_sparse_matrix_object(_json_object(node.typed_payload[:matrix]);
                                                   strict=true,
                                                   path="dag.$(node.id).matrix")
        proof_payload = _json_object(node.typed_payload[:proof])
        field = Kernel._parse_algebraic_field_certificate_object(proof_payload.field,
                                                                  "dag.$(node.id).proof.field")
        factor = Vector{Kernel.AlgebraicElement}[]
        for (i, row) in enumerate(proof_payload.factor)
            push!(factor, [Kernel._parse_algebraic_element_object(value, field,
                                                                  "dag.$(node.id).proof.factor[$i]")
                           for value in row])
        end
        diagonal = [Kernel._parse_algebraic_element_object(value, field,
                                                           "dag.$(node.id).proof.diagonal[$i]")
                    for (i, value) in enumerate(proof_payload.diagonal)]
        proof = Kernel.ExactAlgebraicLowRankPSDProof(matrix, field, factor, diagonal)
        report = Kernel.verify_algebraic_low_rank_psd(matrix, proof)
        report.accepted || return _bad(report.reason)
        return _ok(proof.identity_proof_hash)
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _chordal_checker(node, dag)
    missing = _payload_required(node, [:matrix, :proof])
    isnothing(missing) || return _bad(missing)
    try
        matrix = Kernel.parse_sparse_matrix_object(_json_object(node.typed_payload[:matrix]);
                                                   strict=true,
                                                   path="dag.$(node.id).matrix")
        proof = Kernel._parse_chordal_proof_object(_json_object(node.typed_payload[:proof]),
                                                   matrix;
                                                   strict=true)
        report = Kernel.verify_chordal_psd(matrix, proof)
        report.accepted || return _bad(report.reason)
        return _ok(proof.proof_hash)
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _sos_checker(node, dag)
    missing = _payload_required(node, [:problem, :sos_blocks])
    isnothing(missing) || return _bad(missing)
    try
        problem = Kernel._parse_sparse_sos_problem_object(_json_object(node.typed_payload[:problem]))
        block_payloads = _json_object(node.typed_payload[:sos_blocks])
        blocks = Kernel.SparseSOSBlock[
            Kernel._parse_sparse_sos_block_object(block, "dag.$(node.id).sos_blocks[$i]")
            for (i, block) in enumerate(block_payloads)
        ]
        putinar_value = get(node.typed_payload, :putinar, nothing)
        putinar = isnothing(putinar_value) ? nothing :
                  Kernel._parse_putinar_certificate_object(_json_object(putinar_value),
                                                           "dag.$(node.id).putinar")
        accumulated = SOSGramExpansion.PolyDict()
        for block in blocks
            report = Kernel.verify_low_rank_psd(block.gram_matrix, block.psd_proof)
            report.accepted || return _bad(report.reason)
            derived = SOSGramExpansion.gram_polynomial(block)
            cached = SOSGramExpansion.polynomial_dict(block.coefficient_terms)
            derived == cached || return _bad("cached SOS coefficient_terms do not match Gram expansion")
            for (exp, coeff) in derived
                key = copy(exp)
                accumulated[key] = get(accumulated, key, 0//1) + coeff
                iszero(accumulated[key]) && delete!(accumulated, key)
            end
        end
        if !isnothing(putinar)
            putinar.bound == problem.lower_bound ||
                return _bad("Putinar bound does not match problem lower bound")
            for localizing in putinar.localizing_blocks
                report = Kernel.verify_low_rank_psd(localizing.sos_block.gram_matrix,
                                                    localizing.sos_block.psd_proof)
                report.accepted || return _bad(report.reason)
                derived = SOSGramExpansion.localizing_polynomial(localizing)
                cached = SOSGramExpansion.multiply_polynomials(
                    SOSGramExpansion.polynomial_dict(localizing.sos_block.coefficient_terms),
                    SOSGramExpansion.polynomial_dict(localizing.constraint_terms))
                derived == cached || return _bad("cached localizing coefficient_terms do not match Gram expansion")
                for (exp, coeff) in derived
                    key = copy(exp)
                    accumulated[key] = get(accumulated, key, 0//1) + coeff
                    iszero(accumulated[key]) && delete!(accumulated, key)
                end
            end
        end
        target = SOSGramExpansion.polynomial_dict(problem.target_terms)
        if problem.lower_bound != 0
            exp = zeros(Int, length(problem.variables))
            target[exp] = get(target, exp, 0//1) - problem.lower_bound
            iszero(target[exp]) && delete!(target, exp)
        end
        accumulated == target || return _bad("sparse SOS coefficient identity mismatch")
        expected = Kernel._sha256_payload((;
            target=[Kernel.polynomial_term_json(term) for term in problem.target_terms],
            blocks=[Kernel.sparse_sos_block_json(block) for block in blocks],
            putinar=isnothing(putinar) ? nothing : Kernel.putinar_certificate_json(putinar),
            bound=Kernel.rational_string(problem.lower_bound)))
        return _ok(expected, details=Dict{Symbol, Any}(:blocks => length(blocks)))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _quantum_objective_checker(node, dag)
    missing = _payload_required(node, [:problem, :moment_certificate, :objective_terms, :bound])
    isnothing(missing) || return _bad(missing)
    try
        problem = Kernel._parse_npa_problem_object(_json_object(node.typed_payload[:problem]))
        moment = Kernel._parse_nc_moment_certificate_object(_json_object(node.typed_payload[:moment_certificate]),
                                                            problem)
        objective = Kernel._parse_nc_terms(_json_object(node.typed_payload[:objective_terms]),
                                           "dag.$(node.id).objective_terms")
        bound = Kernel._parse_rational_string(node.typed_payload[:bound],
                                              "dag.$(node.id).bound")
        for witness in moment.witnesses
            report = Kernel.verify_nc_rewrite_witness(witness, problem.relations)
            report.accepted || return _bad(report.reason)
        end
        Kernel._nc_term_dict(objective) == Kernel._nc_term_dict(moment.coefficient_terms) ||
            return _bad("quantum objective is not reconstructed from moment coefficients")
        sum(value for value in values(Kernel._nc_term_dict(objective)); init=0//1) == bound ||
            return _bad("quantum objective bound does not replay exactly")
        expected = Kernel._sha256_payload((;
            objective=[Kernel.nc_term_json(term) for term in objective],
            bound=Kernel.rational_string(bound)))
        return _ok(expected)
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _moment_certificate_checker(node, dag)
    missing = _payload_required(node, [:problem, :moment_certificate])
    isnothing(missing) || return _bad(missing)
    try
        problem = Kernel._parse_npa_problem_object(_json_object(node.typed_payload[:problem]))
        cert = Kernel._parse_nc_moment_certificate_object(_json_object(node.typed_payload[:moment_certificate]),
                                                          problem)
        report = Kernel.verify_low_rank_psd(cert.moment_matrix, cert.psd_proof)
        report.accepted || return _bad(report.reason)
        for witness in cert.witnesses
            wreport = Kernel.verify_nc_rewrite_witness(witness, problem.relations)
            wreport.accepted || return _bad(wreport.reason)
        end
        return _ok(Kernel.nc_moment_certificate_hash(cert))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _rewrite_witness_checker(node, dag)
    missing = _payload_required(node, [:relations, :witnesses])
    isnothing(missing) || return _bad(missing)
    try
        relations = Kernel.AbstractQuantumRelation[
            Kernel._parse_quantum_relation_object(relation,
                                                  "dag.$(node.id).relations[$i]")
            for (i, relation) in enumerate(_json_object(node.typed_payload[:relations]))
        ]
        witnesses = Kernel.NCRewriteWitness[
            Kernel._parse_nc_rewrite_witness_object(witness,
                                                    "dag.$(node.id).witnesses[$i]")
            for (i, witness) in enumerate(_json_object(node.typed_payload[:witnesses]))
        ]
        for witness in witnesses
            report = Kernel.verify_nc_rewrite_witness(witness, relations)
            report.accepted || return _bad(report.reason)
        end
        return _ok(Kernel._sha256_payload([Kernel.nc_rewrite_witness_json(witness)
                                           for witness in witnesses]))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _primal_affine_checker(node, dag)
    missing = _payload_required(node, [:primal])
    isnothing(missing) || return _bad(missing)
    try
        primal = Kernel._parse_primal_feasibility_object(_json_object(node.typed_payload[:primal]),
                                                         "dag.$(node.id).primal")
        primal.affine_lhs == primal.affine_rhs ||
            return _bad("primal affine constraints do not match exactly")
        for (matrix, proof) in zip(primal.cone_matrices, primal.cone_proofs)
            report = Kernel.verify_low_rank_psd(matrix, proof)
            report.accepted || return _bad(report.reason)
        end
        return _ok(Kernel._sha256_payload(Kernel.primal_feasibility_json(primal)))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _dual_affine_checker(node, dag)
    missing = _payload_required(node, [:dual])
    isnothing(missing) || return _bad(missing)
    try
        dual = Kernel._parse_dual_feasibility_object(_json_object(node.typed_payload[:dual]),
                                                     "dag.$(node.id).dual")
        dual.affine_lhs == dual.affine_rhs ||
            return _bad("dual affine identity does not match exactly")
        for (matrix, proof) in zip(dual.cone_matrices, dual.cone_proofs)
            report = Kernel.verify_low_rank_psd(matrix, proof)
            report.accepted || return _bad(report.reason)
        end
        return _ok(Kernel._sha256_payload(Kernel.dual_feasibility_json(dual)))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _farkas_identity_checker(node, dag)
    missing = _payload_required(node, [:lhs, :rhs])
    isnothing(missing) || return _bad(missing)
    try
        lhs_values = [Kernel._parse_rational_string(value, "dag.$(node.id).lhs[$i]")
                      for (i, value) in enumerate(node.typed_payload[:lhs])]
        rhs_values = [Kernel._parse_rational_string(value, "dag.$(node.id).rhs[$i]")
                      for (i, value) in enumerate(node.typed_payload[:rhs])]
        lhs_values == rhs_values || return _bad("Farkas identity lhs/rhs mismatch")
        return _ok(Kernel._sha256_payload((;
            lhs=Kernel.rational_string.(lhs_values),
            rhs=Kernel.rational_string.(rhs_values))))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _exact_gap_checker(node, dag)
    missing = _payload_required(node, [:primal_objective, :dual_objective, :gap])
    isnothing(missing) || return _bad(missing)
    try
        primal = Kernel._parse_rational_string(node.typed_payload[:primal_objective],
                                               "dag.$(node.id).primal_objective")
        dual = Kernel._parse_rational_string(node.typed_payload[:dual_objective],
                                             "dag.$(node.id).dual_objective")
        gap = Kernel._parse_rational_string(node.typed_payload[:gap],
                                            "dag.$(node.id).gap")
        primal - dual == gap || return _bad("objective gap does not equal primal-dual difference")
        return _ok(Kernel._sha256_payload((; gap=Kernel.rational_string(gap))))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _farkas_contradiction_checker(node, dag)
    missing = _payload_required(node, [:lhs, :rhs])
    isnothing(missing) || return _bad(missing)
    try
        lhs = Kernel._parse_rational_string(node.typed_payload[:lhs], "dag.$(node.id).lhs")
        rhs = Kernel._parse_rational_string(node.typed_payload[:rhs], "dag.$(node.id).rhs")
        lhs == 0//1 && rhs < 0//1 ||
            return _bad("Farkas contradiction must have normalized form 0 <= negative")
        return _ok(Kernel._sha256_payload((; lhs=Kernel.rational_string(lhs),
                                             rhs=Kernel.rational_string(rhs))))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _symmetry_reconstruction_checker(node, dag)
    missing = _payload_required(node, [:projection_blocks, :original_matrix,
                                       :reconstructed_matrix, :group, :orbit_basis])
    isnothing(missing) || return _bad(missing)
    try
        group = Kernel._parse_symmetry_group_object(_json_object(node.typed_payload[:group]))
        orbit = Kernel._parse_orbit_basis_object(_json_object(node.typed_payload[:orbit_basis]))
        blocks = Kernel.SparseSymmetricRationalMatrix[
            Kernel.parse_sparse_matrix_object(block; strict=true,
                                              path="dag.$(node.id).projection_blocks[$i]")
            for (i, block) in enumerate(_json_object(node.typed_payload[:projection_blocks]))
        ]
        original = Kernel.parse_sparse_matrix_object(_json_object(node.typed_payload[:original_matrix]);
                                                     strict=true,
                                                     path="dag.$(node.id).original_matrix")
        reconstructed = Kernel.parse_sparse_matrix_object(_json_object(node.typed_payload[:reconstructed_matrix]);
                                                          strict=true,
                                                          path="dag.$(node.id).reconstructed_matrix")
        for generator in group.generators
            for (orbit_index, orbit_indices) in enumerate(orbit.orbits)
                mapped = sort!([Kernel._monomial_index_after_permutation(orbit,
                                                                         index,
                                                                         generator)
                                for index in orbit_indices])
                mapped == sort(orbit_indices) ||
                    return _bad("symmetry generator does not preserve orbit $(orbit_index)")
            end
        end
        summed = Kernel._sum_sparse_matrices(blocks, original.n)
        summed.entries == reconstructed.entries ||
            return _bad("projection blocks do not reconstruct declared matrix")
        original.entries == reconstructed.entries ||
            return _bad("block diagonal reconstruction does not match original matrix")
        return _ok(reconstructed.hash)
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _final_accept_checker(node, dag)
    isempty(node.inputs) && return _bad("final_accept must depend on replay nodes")
    expected_inputs = Set(n.output_hash for n in dag.nodes if n.id != node.id)
    Set(node.inputs) == expected_inputs ||
        return _bad("final_accept does not cover every proof root";
                    details=Dict{Symbol, Any}(:expected => length(expected_inputs),
                                              :actual => length(node.inputs)))
    return _ok(Kernel._final_accept_hash(dag.claim_type,
                                          [n for n in dag.nodes if n.id != node.id]))
end

_register!(:canonical_sparse_matrix_hash, _sparse_matrix_hash_checker)
_register!(:chordal_structure_hash, _chordal_structure_hash_checker)
_register!(:sparse_sos_problem_hash, _sparse_sos_problem_hash_checker)
_register!(:npa_problem_hash, _npa_problem_hash_checker)
_register!(:symmetry_group_hash, _symmetry_group_hash_checker)
_register!(:orbit_basis_hash, _orbit_basis_hash_checker)
_register!(:block_native_incidence_system_hash, _incidence_hash_checker)
_register!(:verify_low_rank_psd, _low_rank_psd_checker)
_register!(:verify_chordal_psd, _chordal_checker)
_register!(:verify_algebraic_low_rank_psd, _algebraic_low_rank_checker)
_register!(:verify_field_element, _field_hash_checker)
_register!(:verify_block_native_active_blocks, _block_native_active_checker)
_register!(:verify_block_native_inactive_blocks, _block_native_inactive_checker)
_register!(:verify_block_native_algebraic_certificate, _block_native_certificate_checker)
_register!(:verify_primal_affine, _primal_affine_checker)
_register!(:verify_dual_affine, _dual_affine_checker)
_register!(:verify_exact_gap, _exact_gap_checker)
_register!(:verify_farkas_identity, _farkas_identity_checker)
_register!(:verify_farkas_contradiction, _farkas_contradiction_checker)
_register!(:verify_sparse_sos_coefficients, _sos_checker)
_register!(:verify_nc_rewrite_witness, _rewrite_witness_checker)
_register!(:verify_quantum_bound_certificate, _quantum_objective_checker)
_register!(:verify_block_diagonalization_certificate, _symmetry_reconstruction_checker)
_register!(:check_schema, _typed_hash_checker([:schema]))
_register!(:check_problem_hash, _typed_hash_checker([:problem]))
_register!(:check_sparse_matrix_hash, _sparse_matrix_hash_checker)
_register!(:check_low_rank_psd_identity, _low_rank_psd_checker)
_register!(:check_low_rank_psd_diagonal_signs, _low_rank_psd_checker)
_register!(:check_chordal_clique_cover, _chordal_checker)
_register!(:check_chordal_running_intersection, _chordal_checker)
_register!(:check_chordal_separator_consistency, _chordal_checker)
_register!(:check_chordal_clique_psd, _chordal_checker)
_register!(:check_sparse_sos_gram_expansion, _sos_checker)
_register!(:check_putinar_localizing_identity, _sos_checker)
_register!(:check_tssos_import_normalization, _typed_hash_checker([:raw_hash, :normalized_hash]))
_register!(:check_nc_rewrite_step, _rewrite_witness_checker)
_register!(:check_npa_moment_entry, _moment_certificate_checker)
_register!(:check_npa_objective_functional, _quantum_objective_checker)
_register!(:check_quantum_objective_bound, _quantum_objective_checker)
_register!(:check_quantum_projection_relation, _typed_hash_checker([:relations]))
_register!(:check_quantum_commutation_relation, _typed_hash_checker([:relations]))
_register!(:check_quantum_trace_cyclicity, _typed_hash_checker([:relations]))
_register!(:check_algebraic_field, _field_hash_checker)
_register!(:check_algebraic_sign, _typed_hash_checker([:element, :sign_certificate]))
_register!(:check_primal_affine, _primal_affine_checker)
_register!(:check_dual_affine, _dual_affine_checker)
_register!(:check_primal_objective, _typed_hash_checker([:objective]))
_register!(:check_dual_objective, _typed_hash_checker([:objective]))
_register!(:check_exact_gap, _exact_gap_checker)
_register!(:check_farkas_dual_cone, _typed_hash_checker([:cone_proof]))
_register!(:check_farkas_contradiction, _farkas_contradiction_checker)
_register!(:check_symmetry_group_closure, _symmetry_group_hash_checker)
_register!(:check_symmetry_orbit_partition, _orbit_basis_hash_checker)
_register!(:check_symmetry_projector_idempotence, _typed_hash_checker([:projection_blocks]))
_register!(:check_symmetry_projector_orthogonality, _typed_hash_checker([:projection_blocks]))
_register!(:check_symmetry_block_reconstruction, _symmetry_reconstruction_checker)
_register!(:check_bundle_manifest, _typed_hash_checker([:manifest]))
_register!(:hash, _typed_hash_checker([:value]))
_register!(:final_accept, _final_accept_checker)

end
