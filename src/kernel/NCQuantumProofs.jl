module NCQuantumProofs

using ..Kernel

export QuantumBoundCertificate,
       NCRewriteWitness,
       verify_quantum_replay,
       verify_rewrite_witness

const QuantumBoundCertificate = Kernel.QuantumBoundCertificate
const NCRewriteWitness = Kernel.NCRewriteWitness

verify_quantum_replay(cert::Kernel.QuantumBoundCertificate) =
    Kernel.verify_quantum_bound_certificate(cert)

verify_rewrite_witness(witness::Kernel.NCRewriteWitness, relations) =
    Kernel.verify_nc_rewrite_witness(witness, relations)

end
