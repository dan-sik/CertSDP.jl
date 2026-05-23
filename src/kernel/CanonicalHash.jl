module CanonicalHash

using ..Kernel

export canonical_hash,
       canonical_certificate_hash,
       canonical_dag_hash,
       canonical_sparse_matrix_hash

canonical_sparse_matrix_hash(matrix::Kernel.SparseSymmetricRationalMatrix) =
    Kernel.sparse_matrix_hash(matrix)

canonical_dag_hash(dag::Kernel.CertificateDAG) =
    Kernel.certificate_dag_hash_without_root(dag)

canonical_certificate_hash(cert::Kernel.V3Certificate) =
    Kernel.certificate_hash_v3(cert)

function canonical_hash(value)
    if value isa Kernel.V3Certificate
        return canonical_certificate_hash(value)
    elseif value isa Kernel.CertificateDAG
        return canonical_dag_hash(value)
    elseif value isa Kernel.SparseSymmetricRationalMatrix
        return canonical_sparse_matrix_hash(value)
    end
    throw(ArgumentError("unsupported canonical hash payload type"))
end

end
