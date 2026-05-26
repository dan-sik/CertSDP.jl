module DAGCheckerRegistry

using ..Kernel
using ..SOSGramExpansion
using JSON3: JSON3

export DAGCheckerResult,
       dag_checker_registry,
       dag_checker_names,
       dag_checker_semantics,
       dag_checker_semantics_report,
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
const CHECKER_SEMANTICS = Dict{Symbol, Symbol}()

const DIAGNOSTIC_ONLY_CHECKERS = Set{Symbol}([:hash])

function reset_dag_checker_calls!()
    empty!(CALLS)
    return nothing
end

dag_checker_calls() = copy(CALLS)
dag_checker_names() = sort!(collect(keys(REGISTRY)); by=String)
dag_checker_registry() = REGISTRY
dag_checker_semantics() = copy(CHECKER_SEMANTICS)

_ok(hash::AbstractString; details=Dict{Symbol, Any}()) =
    DAGCheckerResult(true, String(hash), "accepted", Dict{Symbol, Any}(details))
_bad(reason::AbstractString; hash::AbstractString="", details=Dict{Symbol, Any}()) =
    DAGCheckerResult(false, String(hash), String(reason), Dict{Symbol, Any}(details))

function _register!(name::Symbol, fn::Function; semantics::Symbol=:mathematical_replay)
    semantics in (:mathematical_replay,
                  :typed_hash_only,
                  :payload_hash_only,
                  :metadata_only,
                  :diagnostic_only) ||
        throw(ArgumentError("unknown DAG checker semantics `$semantics`"))
    REGISTRY[name] = fn
    CHECKER_SEMANTICS[name] = semantics
end

function dag_checker_semantics_report()
    names = dag_checker_names()
    proof_relevant_hash_only = String[]
    items = Dict{String, Any}()
    for name in names
        semantics = get(CHECKER_SEMANTICS, name, :unknown)
        diagnostic = name in DIAGNOSTIC_ONLY_CHECKERS || semantics === :diagnostic_only
        hash_only = semantics in (:typed_hash_only, :payload_hash_only, :metadata_only)
        if hash_only && !diagnostic
            push!(proof_relevant_hash_only, String(name))
        end
        items[String(name)] = Dict(
            "semantics" => String(semantics),
            "mathematical_replay" => semantics === :mathematical_replay,
            "hash_only" => hash_only,
            "diagnostic_only" => diagnostic,
        )
    end
    return Dict(
        "checkers" => items,
        "proof_relevant_hash_only" => sort!(proof_relevant_hash_only),
        "proof_relevant_hash_only_count" => length(proof_relevant_hash_only),
    )
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

function _is_sha256_hash(value)
    value isa AbstractString || return false
    return occursin(r"^sha256:[0-9a-f]{64}$", String(value))
end

function _schema_checker(node, dag)
    missing = _payload_required(node, [:schema])
    isnothing(missing) || return _bad(missing)
    try
        schema = _json_object(node.typed_payload[:schema])
        text = JSON3.write(schema)
        occursin("3.0", text) ||
            return _bad("schema replay did not find CertSDP 3.0 marker")
        occursin("additionalProperties", text) ||
            return _bad("schema replay did not find fail-closed additionalProperties rule")
        return _ok(_payload_hash(Dict(:schema => node.typed_payload[:schema])))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _problem_hash_checker(node, dag)
    missing = _payload_required(node, [:problem])
    isnothing(missing) || return _bad(missing)
    try
        problem = _json_object(node.typed_payload[:problem])
        if _dict_get(problem, :problem_hash, nothing) !== nothing
            supplied = String(_dict_get(problem, :problem_hash))
            _is_sha256_hash(supplied) || return _bad("problem_hash is not a canonical sha256 hash")
        elseif _dict_get(problem, :hash, nothing) !== nothing
            supplied = String(_dict_get(problem, :hash))
            _is_sha256_hash(supplied) || return _bad("problem hash is not a canonical sha256 hash")
        else
            return _bad("problem payload does not contain a canonical problem hash")
        end
        return _ok(_payload_hash(Dict(:problem => node.typed_payload[:problem])))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _tssos_import_normalization_checker(node, dag)
    missing = _payload_required(node, [:raw_hash, :normalized_hash])
    isnothing(missing) || return _bad(missing)
    try
        raw_hash = String(node.typed_payload[:raw_hash])
        normalized_hash = String(node.typed_payload[:normalized_hash])
        _is_sha256_hash(raw_hash) || return _bad("raw source hash is not canonical")
        _is_sha256_hash(normalized_hash) || return _bad("normalized certificate hash is not canonical")
        raw_hash != normalized_hash ||
            return _bad("raw source hash must not equal normalized certificate hash")
        if haskey(node.typed_payload, :raw_artifact)
            raw = _json_object(node.typed_payload[:raw_artifact])
            for key in (:certsdp_certificate_version,
                        :certsdp_sparse_sos_certificate_version,
                        :certsdp_quantum_certificate_version)
                _dict_get(raw, key, nothing) === nothing ||
                    return _bad("raw TSSOS artifact is CertSDP-native certificate schema")
            end
            Kernel._sha256_payload(raw) == raw_hash ||
                return _bad("raw TSSOS artifact hash mismatch")
        end
        return _ok(_payload_hash(Dict(:raw_hash => raw_hash,
                                      :normalized_hash => normalized_hash)))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _relation_semantics_checker(node, relation_kind::DataType, label::AbstractString)
    missing = _payload_required(node, [:relations])
    isnothing(missing) || return _bad(missing)
    try
        relations = Kernel.AbstractQuantumRelation[
            Kernel._parse_quantum_relation_object(relation,
                                                  "dag.$(node.id).relations[$i]")
            for (i, relation) in enumerate(_json_object(node.typed_payload[:relations]))
        ]
        any(relation -> relation isa relation_kind, relations) ||
            return _bad("quantum relation set does not contain $label relation")
        return _ok(Kernel._sha256_payload([Kernel.quantum_relation_json(relation)
                                           for relation in relations]))
    catch err
        return _bad(sprint(showerror, err))
    end
end

_quantum_projection_relation_checker(node, dag) =
    _relation_semantics_checker(node, Kernel.ProjectionRelation, "projection")
_quantum_commutation_relation_checker(node, dag) =
    _relation_semantics_checker(node, Kernel.CommutationRelation, "commutation")
_quantum_trace_cyclicity_checker(node, dag) =
    _relation_semantics_checker(node, Kernel.TraceCyclicRelation, "trace-cyclicity")

function _algebraic_sign_checker(node, dag)
    missing = _payload_required(node, [:element, :sign_certificate])
    isnothing(missing) || return _bad(missing)
    try
        cert = _json_object(node.typed_payload[:sign_certificate])
        field_payload = _dict_get(cert, :field, nothing)
        isnothing(field_payload) && haskey(node.typed_payload, :field) &&
            (field_payload = _json_object(node.typed_payload[:field]))
        isnothing(field_payload) && return _bad("algebraic sign certificate missing field")
        field = Kernel._parse_algebraic_field_certificate_object(field_payload,
                                                                  "dag.$(node.id).sign_certificate.field")
        element = Kernel._parse_algebraic_element_object(_json_object(node.typed_payload[:element]),
                                                         field,
                                                         "dag.$(node.id).element")
        reduced = Kernel._algebraic_reduce(element.coefficients,
                                           field.minimal_polynomial)
        supplied = Symbol(String(_dict_get(cert, :sign,
                                           _dict_get(cert, :sign_result, ""))))
        computed = if all(==(0//1), reduced)
            :zero
        elseif Kernel._algebraic_sign_positive(element, field)
            :positive
        else
            neg = Kernel.AlgebraicElement(field, [-value for value in element.coefficients])
            Kernel._algebraic_sign_positive(neg, field) ? :negative : :unknown
        end
        computed === :unknown && return _bad("algebraic sign could not be certified")
        supplied in (:positive_or_zero, :nonnegative) && computed in (:positive, :zero) ||
            supplied === computed ||
            return _bad("algebraic sign certificate result mismatch")
        return _ok(Kernel._sha256_payload((;
            element=Kernel.algebraic_element_json(element),
            sign=String(computed))))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _objective_scalar_checker(key::Symbol)
    return function (node, dag)
        missing = _payload_required(node, [key])
        isnothing(missing) || return _bad(missing)
        try
            value = Kernel._parse_rational_string(node.typed_payload[key],
                                                  "dag.$(node.id).$(String(key))")
            return _ok(Kernel._sha256_payload((; objective=Kernel.rational_string(value))))
        catch err
            return _bad(sprint(showerror, err))
        end
    end
end

function _farkas_dual_cone_checker(node, dag)
    missing = _payload_required(node, [:cone_proof])
    isnothing(missing) || return _bad(missing)
    try
        payload = _json_object(node.typed_payload[:cone_proof])
        if _dict_get(payload, :matrix, nothing) !== nothing
            matrix = Kernel.parse_sparse_matrix_object(_dict_get(payload, :matrix);
                                                       strict=true,
                                                       path="dag.$(node.id).cone_proof.matrix")
            proof = Kernel._parse_low_rank_proof_object(_dict_get(payload, :psd_proof),
                                                        matrix;
                                                        strict=true,
                                                        path="dag.$(node.id).cone_proof.psd_proof")
            report = Kernel.verify_low_rank_psd(matrix, proof)
            report.accepted || return _bad(report.reason)
            return _ok(proof.identity_proof_hash)
        end
        proof = Kernel._parse_low_rank_proof_object_without_matrix(payload;
                                                                   strict=true,
                                                                   path="dag.$(node.id).cone_proof")
        proof.field === :QQ || return _bad("Farkas dual cone proof must be rational")
        all(value -> value >= 0, proof.diagonal) ||
            return _bad("Farkas dual cone diagonal contains a negative value")
        return _ok(Kernel._sha256_payload(Kernel.low_rank_proof_json(proof)))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _matrix_full_entries(matrix::Kernel.SparseSymmetricRationalMatrix)
    entries = Dict{Tuple{Int, Int}, Rational{BigInt}}()
    for (i, j, value) in matrix.entries
        entries[(i, j)] = value
        i == j || (entries[(j, i)] = value)
    end
    return entries
end

function _matrix_product_entries(a::Kernel.SparseSymmetricRationalMatrix,
                                 b::Kernel.SparseSymmetricRationalMatrix)
    a.n == b.n || throw(DimensionMismatch("matrix dimensions differ"))
    left = _matrix_full_entries(a)
    right = _matrix_full_entries(b)
    result = Dict{Tuple{Int, Int}, Rational{BigInt}}()
    by_row = Dict{Int, Vector{Tuple{Int, Rational{BigInt}}}}()
    for ((i, j), value) in right
        push!(get!(by_row, i, Tuple{Int, Rational{BigInt}}[]), (j, value))
    end
    for ((i, k), avalue) in left
        for (j, bvalue) in get(by_row, k, Tuple{Int, Rational{BigInt}}[])
            result[(i, j)] = get(result, (i, j), 0//1) + avalue * bvalue
            iszero(result[(i, j)]) && delete!(result, (i, j))
        end
    end
    return result
end

function _matrix_entries_equal_full(entries, matrix::Kernel.SparseSymmetricRationalMatrix)
    target = _matrix_full_entries(matrix)
    keys(entries) == keys(target) || return false
    return all(key -> entries[key] == target[key], keys(entries))
end

function _symmetry_projector_idempotence_checker(node, dag)
    missing = _payload_required(node, [:projection_blocks])
    isnothing(missing) || return _bad(missing)
    try
        blocks = Kernel.SparseSymmetricRationalMatrix[
            Kernel.parse_sparse_matrix_object(block; strict=true,
                                              path="dag.$(node.id).projection_blocks[$i]")
            for (i, block) in enumerate(_json_object(node.typed_payload[:projection_blocks]))
        ]
        for (i, block) in enumerate(blocks)
            product = _matrix_product_entries(block, block)
            _matrix_entries_equal_full(product, block) ||
                return _bad("projector $i is not idempotent")
        end
        return _ok(Kernel._sha256_payload((;
            theorem="projector_idempotence",
            projectors=[Kernel.sparse_matrix_json(block) for block in blocks])))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _symmetry_projector_orthogonality_checker(node, dag)
    missing = _payload_required(node, [:projection_blocks])
    isnothing(missing) || return _bad(missing)
    try
        blocks = Kernel.SparseSymmetricRationalMatrix[
            Kernel.parse_sparse_matrix_object(block; strict=true,
                                              path="dag.$(node.id).projection_blocks[$i]")
            for (i, block) in enumerate(_json_object(node.typed_payload[:projection_blocks]))
        ]
        for i in 1:length(blocks), j in (i + 1):length(blocks)
            product = _matrix_product_entries(blocks[i], blocks[j])
            isempty(product) || return _bad("projectors $i and $j are not orthogonal")
        end
        return _ok(Kernel._sha256_payload((;
            theorem="projector_orthogonality",
            projectors=[Kernel.sparse_matrix_json(block) for block in blocks])))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _symmetry_projector_completeness_checker(node, dag)
    missing = _payload_required(node, [:projector_matrices, :dimension])
    isnothing(missing) || return _bad(missing)
    try
        n = Int(node.typed_payload[:dimension])
        projectors = Kernel.SparseSymmetricRationalMatrix[
            Kernel.parse_sparse_matrix_object(block; strict=true,
                                              path="dag.$(node.id).projector_matrices[$i]")
            for (i, block) in enumerate(_json_object(node.typed_payload[:projector_matrices]))
        ]
        summed = Kernel._sum_sparse_matrices(projectors, n)
        Kernel._matrix_equal(summed, Kernel._identity_matrix(n)) ||
            return _bad("projectors do not sum to identity")
        return _ok(Kernel._sha256_payload((;
            theorem="projector_completeness",
            dimension=n,
            projectors=[Kernel.sparse_matrix_json(block) for block in projectors])))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _bundle_manifest_checker(node, dag)
    missing = _payload_required(node, [:manifest])
    isnothing(missing) || return _bad(missing)
    try
        manifest = _json_object(node.typed_payload[:manifest])
        for key in (:certsdp_bundle_version, :certificate_hash, :problem_hash,
                    :dag_root_hash, :verify_script, :source_artifacts)
            _dict_get(manifest, key, nothing) !== nothing ||
                return _bad("bundle manifest missing $(String(key))")
        end
        for key in (:certificate_hash, :problem_hash, :dag_root_hash)
            _is_sha256_hash(String(_dict_get(manifest, key))) ||
                return _bad("bundle manifest $(String(key)) is not canonical")
        end
        return _ok(_payload_hash(Dict(:manifest => node.typed_payload[:manifest])))
    catch err
        return _bad(sprint(showerror, err))
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
        _symmetry_generated_group(group)
        return _ok(Kernel.symmetry_group_hash(group))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _compose_perm(a::Vector{Int}, b::Vector{Int})
    length(a) == length(b) || throw(DimensionMismatch("permutation dimensions differ"))
    return [a[b[i]] for i in eachindex(a)]
end

function _identity_perm(n::Int)
    return collect(1:n)
end

function _symmetry_generated_group(group::Kernel.SymmetryGroupCertificate)
    n = length(group.variables)
    generators = [generator.image for generator in group.generators]
    all(sort(generator) == collect(1:n) for generator in generators) ||
        throw(ArgumentError("symmetry generator is not a permutation"))
    id = _identity_perm(n)
    seen = Set{Tuple{Vararg{Int}}}()
    queue = Vector{Vector{Int}}([id])
    while !isempty(queue)
        current = popfirst!(queue)
        key = Tuple(current)
        key in seen && continue
        push!(seen, key)
        for generator in generators
            composed = _compose_perm(generator, current)
            Tuple(composed) in seen || push!(queue, composed)
        end
        length(seen) > 10000 &&
            throw(ArgumentError("generated symmetry group is too large for fixture replay"))
    end
    id_key = Tuple(id)
    id_key in seen || throw(ArgumentError("generated symmetry group lacks identity"))
    elements = [collect(key) for key in seen]
    for a in elements, b in elements
        Tuple(_compose_perm(a, b)) in seen ||
            throw(ArgumentError("generated symmetry group is not closed"))
    end
    for a in elements
        any(b -> _compose_perm(a, b) == id && _compose_perm(b, a) == id,
            elements) ||
            throw(ArgumentError("generated symmetry group element lacks inverse"))
    end
    return elements
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
        verified_values = Kernel._verified_moment_entries(problem, moment)
        Kernel._nc_term_dict(objective) == Kernel._nc_term_dict(moment.coefficient_terms) ||
            return _bad("quantum objective is not reconstructed from moment coefficients")
        Kernel._objective_from_verified_moments(objective, verified_values) == bound ||
            return _bad("quantum objective bound does not replay from verified moment entries")
        moment_entry_hashes = haskey(node.typed_payload, :moment_entry_hashes) ?
                              String.(node.typed_payload[:moment_entry_hashes]) :
                              String[]
        isempty(moment_entry_hashes) &&
            return _bad("quantum objective checker must declare moment-entry dependencies")
        Set(moment_entry_hashes) == Set(node.inputs) ||
            return _bad("quantum objective dependency list does not match moment-entry nodes")
        entry_nodes = [proof_node for proof_node in dag.nodes
                       if proof_node.kind === :npa_moment_entry]
        Set(n.output_hash for n in entry_nodes) == Set(moment_entry_hashes) ||
            return _bad("quantum objective does not depend on every NPA moment-entry node")
        expected = Kernel._sha256_payload((;
            objective=[Kernel.nc_term_json(term) for term in objective],
            bound=Kernel.rational_string(bound)))
        return _ok(expected)
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _moment_entry_checker(node, dag)
    missing = _payload_required(node, [:row_index, :col_index, :row_word,
                                       :col_word, :adjoint_row_word,
                                       :product_word, :relations,
                                       :relation_system_hash,
                                       :rewrite_witness_id,
                                       :rewrite_witness,
                                       :expected_normal_form,
                                       :expected_moment_value,
                                       :matrix_entry_value,
                                       :block_id])
    isnothing(missing) || return _bad(missing)
    try
        row_index = Int(node.typed_payload[:row_index])
        col_index = Int(node.typed_payload[:col_index])
        row_word = Symbol.(String.(node.typed_payload[:row_word]))
        col_word = Symbol.(String.(node.typed_payload[:col_word]))
        adjoint_row = Symbol.(String.(node.typed_payload[:adjoint_row_word]))
        product_word = Symbol.(String.(node.typed_payload[:product_word]))
        expected_normal = Symbol.(String.(node.typed_payload[:expected_normal_form]))
        expected_value = Kernel._parse_rational_string(node.typed_payload[:expected_moment_value],
                                                       "dag.$(node.id).expected_moment_value")
        matrix_value = Kernel._parse_rational_string(node.typed_payload[:matrix_entry_value],
                                                     "dag.$(node.id).matrix_entry_value")
        relations = Kernel.AbstractQuantumRelation[
            Kernel._parse_quantum_relation_object(relation,
                                                  "dag.$(node.id).relations[$i]")
            for (i, relation) in enumerate(_json_object(node.typed_payload[:relations]))
        ]
        relation_hash = Kernel.npa_relation_system_hash(relations)
        String(node.typed_payload[:relation_system_hash]) == relation_hash ||
            return _bad("moment entry relation system hash mismatch")
        computed_adjoint = reverse([Kernel._star_symbol(symbol) for symbol in row_word])
        computed_adjoint == adjoint_row ||
            return _bad("moment entry adjoint(row_word) mismatch")
        vcat(computed_adjoint, col_word) == product_word ||
            return _bad("moment entry product word mismatch")
        witness = Kernel._parse_nc_rewrite_witness_object(_json_object(node.typed_payload[:rewrite_witness]),
                                                          "dag.$(node.id).rewrite_witness")
        witness.input_word == product_word ||
            return _bad("moment entry witness input does not match adjoint(row)*col")
        report = Kernel.verify_nc_rewrite_witness(witness, relations)
        report.accepted || return _bad(report.reason)
        witness.final_word == expected_normal ||
            return _bad("moment entry witness final word does not match expected normal form")
        expected_value == matrix_value ||
            return _bad("moment entry expected value does not match matrix entry")
        return _ok(Kernel.npa_moment_entry_output_hash(row_index,
                                                       col_index,
                                                       String(node.typed_payload[:block_id]),
                                                       expected_normal,
                                                       matrix_value))
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
        problem = haskey(node.typed_payload, :problem) ?
                  Kernel._parse_exact_conic_problem_object(_json_object(node.typed_payload[:problem]),
                                                           "dag.$(node.id).problem") :
                  nothing
        isnothing(problem) && return _bad("stage=:primal_dual_affine_map exact conic problem object missing")
        primal = Kernel._parse_primal_feasibility_object(_json_object(node.typed_payload[:primal]),
                                                         "dag.$(node.id).primal")
        primal = Kernel.PrimalFeasibilityCertificate(primal.problem_hash,
                                                     problem,
                                                     primal.primal_vector,
                                                     primal.affine_lhs,
                                                     primal.affine_rhs,
                                                     primal.cone_matrices,
                                                     primal.cone_proofs,
                                                     primal.objective_value)
        report = Kernel._verify_primal_from_problem(primal)
        isnothing(report) || return _bad(report.reason)
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
        problem = haskey(node.typed_payload, :problem) ?
                  Kernel._parse_exact_conic_problem_object(_json_object(node.typed_payload[:problem]),
                                                           "dag.$(node.id).problem") :
                  nothing
        isnothing(problem) && return _bad("stage=:primal_dual_affine_map exact conic problem object missing")
        dual = Kernel._parse_dual_feasibility_object(_json_object(node.typed_payload[:dual]),
                                                     "dag.$(node.id).dual")
        dual = Kernel.DualFeasibilityCertificate(dual.problem_hash,
                                                 problem,
                                                 dual.dual_variables,
                                                 dual.affine_lhs,
                                                 dual.affine_rhs,
                                                 dual.cone_matrices,
                                                 dual.cone_proofs,
                                                 dual.objective_value)
        report = Kernel._verify_dual_from_problem(dual)
        isnothing(report) || return _bad(report.reason)
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
        haskey(node.typed_payload, :problem) ||
            return _bad("stage=:farkas_problem_data exact conic problem object missing")
        haskey(node.typed_payload, :dual_variables) ||
            return _bad("stage=:farkas_problem_data Farkas dual variables missing")
        problem = Kernel._parse_exact_conic_problem_object(_json_object(node.typed_payload[:problem]),
                                                           "dag.$(node.id).problem")
        dual_variables = Kernel.SparseSymmetricRationalMatrix[
            Kernel.parse_sparse_matrix_object(matrix; strict=true,
                                              path="dag.$(node.id).dual_variables[$i]")
            for (i, matrix) in enumerate(_json_object(node.typed_payload[:dual_variables]))
        ]
        lhs_values == Kernel._conic_dual_adjoint(problem, dual_variables) ||
            return _bad("Farkas identity lhs was not reconstructed from A*(y)")
        rhs_values == problem.objective ||
            return _bad("Farkas identity rhs does not match problem objective")
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
        haskey(node.typed_payload, :problem) ||
            return _bad("stage=:primal_dual_affine_map exact conic problem object missing")
        haskey(node.typed_payload, :primal_vector) ||
            return _bad("stage=:primal_dual_affine_map primal vector missing from gap replay")
        haskey(node.typed_payload, :dual_variables) ||
            return _bad("stage=:primal_dual_affine_map dual variables missing from gap replay")
        problem = Kernel._parse_exact_conic_problem_object(_json_object(node.typed_payload[:problem]),
                                                           "dag.$(node.id).problem")
        primal_vector = [Kernel._parse_rational_string(value,
                                                       "dag.$(node.id).primal_vector[$i]")
                         for (i, value) in enumerate(node.typed_payload[:primal_vector])]
        dual_variables = Kernel.SparseSymmetricRationalMatrix[
            Kernel.parse_sparse_matrix_object(matrix; strict=true,
                                              path="dag.$(node.id).dual_variables[$i]")
            for (i, matrix) in enumerate(_json_object(node.typed_payload[:dual_variables]))
        ]
        computed_primal = Kernel._conic_primal_objective(problem, primal_vector)
        computed_dual = Kernel._conic_dual_objective(problem, dual_variables)
        primal == computed_primal ||
            return _bad("primal objective was not reconstructed from c'x")
        dual == computed_dual ||
            return _bad("dual objective was not reconstructed from <B,y>")
        Kernel._conic_gap(problem, computed_primal, computed_dual) == gap ||
            return _bad("objective gap does not equal sense-correct primal-dual difference")
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
        haskey(node.typed_payload, :problem) ||
            return _bad("stage=:farkas_problem_data exact conic problem object missing")
        haskey(node.typed_payload, :dual_variables) ||
            return _bad("stage=:farkas_problem_data Farkas dual variables missing")
        problem = Kernel._parse_exact_conic_problem_object(_json_object(node.typed_payload[:problem]),
                                                           "dag.$(node.id).problem")
        dual_variables = Kernel.SparseSymmetricRationalMatrix[
            Kernel.parse_sparse_matrix_object(matrix; strict=true,
                                              path="dag.$(node.id).dual_variables[$i]")
            for (i, matrix) in enumerate(_json_object(node.typed_payload[:dual_variables]))
        ]
        rhs == Kernel._conic_dual_objective(problem, dual_variables) ||
            return _bad("Farkas contradiction scalar was not reconstructed from <B,y>")
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

function _symmetry_psd_transfer_checker(node, dag)
    missing = _payload_required(node, [:projector_idempotence_hash,
                                       :projector_orthogonality_hash,
                                       :projector_completeness_hash,
                                       :block_reconstruction_hash,
                                       :original_matrix])
    isnothing(missing) || return _bad(missing)
    try
        for key in (:projector_idempotence_hash,
                    :projector_orthogonality_hash,
                    :projector_completeness_hash,
                    :block_reconstruction_hash)
            hash = String(node.typed_payload[key])
            hash in node.inputs || return _bad("PSD transfer theorem missing dependency $(String(key))")
            _is_sha256_hash(hash) || return _bad("PSD transfer theorem dependency $(String(key)) is not canonical")
        end
        original = Kernel.parse_sparse_matrix_object(_json_object(node.typed_payload[:original_matrix]);
                                                     strict=true,
                                                     path="dag.$(node.id).original_matrix")
        return _ok(Kernel._sha256_payload((;
            theorem="symmetry_psd_transfer",
            original_matrix=Kernel.sparse_matrix_json(original),
            dependencies=sort(String.(node.inputs)))))
    catch err
        return _bad(sprint(showerror, err))
    end
end

function _final_accept_checker(node, dag)
    isempty(node.inputs) && return _bad("final_accept must depend on replay nodes")
    node.kind === :final_accept ||
        return _bad("final_accept checker may only be used by final_accept nodes")
    claim = _dict_get(node.typed_payload, :claim_type, nothing)
    isnothing(claim) ||
        Symbol(String(claim)) === dag.claim_type ||
        return _bad("final_accept claim type mismatch")
    for proof_node in dag.nodes
        proof_node.id == node.id && continue
        proof_node.status in (:rejected, :skipped, :unknown, :stale, :diagnostic_only) &&
            return _bad("final_accept proof path contains rejected-status node";
                        details=Dict{Symbol, Any}(:node => String(proof_node.id),
                                                  :status => String(proof_node.status)))
        semantics = get(CHECKER_SEMANTICS, proof_node.checker, :unknown)
        diagnostic = proof_node.checker in DIAGNOSTIC_ONLY_CHECKERS ||
                     semantics === :diagnostic_only
        diagnostic &&
            return _bad("final_accept proof path contains diagnostic-only node";
                        details=Dict{Symbol, Any}(:node => String(proof_node.id),
                                                  :checker => String(proof_node.checker)))
        semantics === :unknown &&
            return _bad("final_accept proof path contains unclassified checker";
                        details=Dict{Symbol, Any}(:node => String(proof_node.id),
                                                  :checker => String(proof_node.checker)))
    end
    expected_inputs = Set(n.output_hash for n in dag.nodes if n.id != node.id)
    Set(node.inputs) == expected_inputs ||
        return _bad("final_accept does not cover every proof root";
                    details=Dict{Symbol, Any}(:expected => length(expected_inputs),
                                              :actual => length(node.inputs)))
    required = _dict_get(node.typed_payload, :required_inputs, nothing)
    if !isnothing(required)
        Set(String.(required)) == expected_inputs ||
            return _bad("final_accept required_inputs payload is stale")
    end
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
_register!(:check_schema, _schema_checker)
_register!(:check_problem_hash, _problem_hash_checker)
_register!(:check_sparse_matrix_hash, _sparse_matrix_hash_checker)
_register!(:check_low_rank_psd_identity, _low_rank_psd_checker)
_register!(:check_low_rank_psd_diagonal_signs, _low_rank_psd_checker)
_register!(:check_chordal_clique_cover, _chordal_checker)
_register!(:check_chordal_running_intersection, _chordal_checker)
_register!(:check_chordal_separator_consistency, _chordal_checker)
_register!(:check_chordal_clique_psd, _chordal_checker)
_register!(:check_sparse_sos_gram_expansion, _sos_checker)
_register!(:check_putinar_localizing_identity, _sos_checker)
_register!(:check_tssos_import_normalization, _tssos_import_normalization_checker)
_register!(:check_nc_rewrite_step, _rewrite_witness_checker)
_register!(:check_npa_moment_entry, _moment_entry_checker)
_register!(:check_npa_objective_functional, _quantum_objective_checker)
_register!(:check_quantum_objective_bound, _quantum_objective_checker)
_register!(:check_quantum_projection_relation, _quantum_projection_relation_checker)
_register!(:check_quantum_commutation_relation, _quantum_commutation_relation_checker)
_register!(:check_quantum_trace_cyclicity, _quantum_trace_cyclicity_checker)
_register!(:check_algebraic_field, _field_hash_checker)
_register!(:check_algebraic_sign, _algebraic_sign_checker)
_register!(:check_primal_affine, _primal_affine_checker)
_register!(:check_dual_affine, _dual_affine_checker)
_register!(:check_primal_objective, _objective_scalar_checker(:objective))
_register!(:check_dual_objective, _objective_scalar_checker(:objective))
_register!(:check_exact_gap, _exact_gap_checker)
_register!(:check_farkas_dual_cone, _farkas_dual_cone_checker)
_register!(:check_farkas_contradiction, _farkas_contradiction_checker)
_register!(:check_symmetry_group_closure, _symmetry_group_hash_checker)
_register!(:check_symmetry_orbit_partition, _orbit_basis_hash_checker)
_register!(:check_symmetry_projector_idempotence, _symmetry_projector_idempotence_checker)
_register!(:check_symmetry_projector_orthogonality, _symmetry_projector_orthogonality_checker)
_register!(:check_symmetry_projector_completeness, _symmetry_projector_completeness_checker)
_register!(:check_symmetry_block_reconstruction, _symmetry_reconstruction_checker)
_register!(:check_symmetry_psd_transfer, _symmetry_psd_transfer_checker)
_register!(:check_bundle_manifest, _bundle_manifest_checker)
_register!(:hash, _typed_hash_checker([:value]); semantics=:diagnostic_only)
_register!(:final_accept, _final_accept_checker)

end
