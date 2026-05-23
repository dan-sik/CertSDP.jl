module SOSProofs

using ..Kernel

export SparseSOSCertificate,
       verify_sparse_sos_replay

const SparseSOSCertificate = Kernel.SparseSOSCertificate

verify_sparse_sos_replay(cert::Kernel.SparseSOSCertificate) =
    Kernel.verify_sparse_sos_certificate(cert)

end
