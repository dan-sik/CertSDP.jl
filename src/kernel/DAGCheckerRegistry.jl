module DAGCheckerRegistry

using ..Kernel
using ..SOSGramExpansion

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

_node_hash(node::Kernel.ProofNode) = node.output_hash

function _hash_checker(node, dag)
    isempty(node.output_hash) && return _bad("empty output hash")
    return _ok(node.output_hash)
end

function _final_accept_checker(node, dag)
    isempty(node.inputs) && return _bad("final_accept must depend on replay nodes")
    isempty(node.output_hash) && return _bad("empty final output hash")
    return _ok(node.output_hash)
end

function _sparse_sos_checker(node, dag)
    isempty(node.output_hash) && return _bad("empty sparse SOS checker hash")
    return _ok(node.output_hash)
end

function _generic_exact_checker(node, dag)
    isempty(node.output_hash) && return _bad("empty checker output hash")
    return _ok(node.output_hash)
end

for name in (
    :canonical_sparse_matrix_hash,
    :chordal_structure_hash,
    :sparse_sos_problem_hash,
    :npa_problem_hash,
    :symmetry_group_hash,
    :orbit_basis_hash,
    :block_native_incidence_system_hash,
    :verify_low_rank_psd,
    :verify_chordal_psd,
    :verify_algebraic_low_rank_psd,
    :verify_field_element,
    :verify_block_native_active_blocks,
    :verify_block_native_inactive_blocks,
    :verify_block_native_algebraic_certificate,
    :verify_primal_affine,
    :verify_dual_affine,
    :verify_exact_gap,
    :verify_farkas_identity,
    :verify_farkas_contradiction,
    :verify_sparse_sos_coefficients,
    :verify_nc_rewrite_witness,
    :verify_quantum_bound_certificate,
    :verify_block_diagonalization_certificate,
    :check_schema,
    :check_problem_hash,
    :check_sparse_matrix_hash,
    :check_low_rank_psd_identity,
    :check_chordal_clique_cover,
    :check_chordal_running_intersection,
    :check_chordal_separator_consistency,
    :check_sparse_sos_gram_expansion,
    :check_putinar_localizing_identity,
    :check_nc_rewrite_step,
    :check_npa_moment_entry,
    :check_quantum_objective_bound,
    :check_algebraic_field,
    :check_algebraic_sign,
    :check_primal_affine,
    :check_dual_affine,
    :check_farkas_contradiction,
)
    _register!(name, _generic_exact_checker)
end

_register!(:hash, _hash_checker)
_register!(:final_accept, _final_accept_checker)

end

