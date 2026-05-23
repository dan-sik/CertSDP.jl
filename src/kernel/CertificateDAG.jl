module CertificateDAG3

using ..Kernel

export build_certificate_dag,
       verify_certificate_dag,
       dag_root_hash,
       dag_node_count

const ALLOWED_DAG_NODE_TYPES = Set(Symbol[
    :schema,
    :problem_hash,
    :field,
    :sparse_matrix,
    :block_matrix,
    :cone_membership,
    :psd_factor,
    :chordal_psd,
    :primal_objective,
    :dual_objective,
    :objective_bound,
    :polynomial_identity,
    :sos_gram,
    :localizing_matrix,
    :nc_word_reduction,
    :npa_moment_matrix,
    :adapter_import,
    :final_accept,
    :hash,
    :exact_identity,
    :psd,
    :exact_equality,
    :exact_gap,
    :exact_rewrite,
    :symmetry,
])

build_certificate_dag(cert::Kernel.V3Certificate) = Kernel.proof_dag(cert)

function build_certificate_dag(cert)
    hasproperty(cert, :dag) && return getproperty(cert, :dag)
    return nothing
end

verify_certificate_dag(cert::Kernel.V3Certificate) =
    Kernel.verify_proof_dag(build_certificate_dag(cert))

function verify_certificate_dag(dag::Kernel.CertificateDAG)
    unknown = [node.kind for node in dag.nodes if !(node.kind in ALLOWED_DAG_NODE_TYPES)]
    isempty(unknown) ||
        return Kernel.DiagnosticReport(false,
                                       :E,
                                       dag.claim_type,
                                       :proof_dag,
                                       :node_type,
                                       "DAG contains an unknown node type",
                                       :dag_node_type,
                                       nothing,
                                       dag.root_hash,
                                       nothing,
                                       nothing,
                                       nothing,
                                       nothing,
                                       Dict{Symbol, Any}(:unknown => String.(unknown)))
    return Kernel.verify_proof_dag(dag)
end

function verify_certificate_dag(cert)
    dag = build_certificate_dag(cert)
    dag isa Kernel.CertificateDAG ||
        return Kernel.DiagnosticReport(false,
                                       :E,
                                       :certificate_dag,
                                       :proof_dag,
                                       :missing_dag,
                                       "certificate has no CertificateDAG",
                                       :proof_dag,
                                       nothing,
                                       nothing,
                                       nothing,
                                       nothing,
                                       nothing,
                                       nothing,
                                       Dict{Symbol, Any}())
    return verify_certificate_dag(dag)
end

dag_root_hash(dag::Kernel.CertificateDAG) = dag.root_hash

dag_node_count(dag::Kernel.CertificateDAG) = length(dag.nodes)

end
