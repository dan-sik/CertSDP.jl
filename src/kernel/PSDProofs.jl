module PSDProofs

using ..Kernel

export ExactLowRankPSDProof,
       ExactAlgebraicLowRankPSDProof,
       ChordalPSDProof,
       verify_exact_psd_proof

const ExactLowRankPSDProof = Kernel.ExactLowRankPSDProof
const ExactAlgebraicLowRankPSDProof = Kernel.ExactAlgebraicLowRankPSDProof
const ChordalPSDProof = Kernel.ChordalPSDProof

verify_exact_psd_proof(matrix::Kernel.SparseSymmetricRationalMatrix,
                       proof::Kernel.ExactLowRankPSDProof) =
    Kernel.verify_low_rank_psd(matrix, proof)

verify_exact_psd_proof(matrix::Kernel.SparseSymmetricRationalMatrix,
                       proof::Kernel.ExactAlgebraicLowRankPSDProof) =
    Kernel.verify_algebraic_low_rank_psd(matrix, proof)

verify_exact_psd_proof(matrix::Kernel.SparseSymmetricRationalMatrix,
                       proof::Kernel.ChordalPSDProof) =
    Kernel.verify_chordal_psd(matrix, proof)

end
