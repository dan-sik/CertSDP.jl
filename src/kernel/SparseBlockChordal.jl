module SparseBlockChordal

using ..Kernel
using ..Debug

export SparseSymmetricRationalMatrix,
       ChordalPSDStructure,
       ChordalPSDProof,
       reset_densification_counter!,
       densification_counter,
       replay_chordal_psd

const SparseSymmetricRationalMatrix = Kernel.SparseSymmetricRationalMatrix
const ChordalPSDStructure = Kernel.ChordalPSDStructure
const ChordalPSDProof = Kernel.ChordalPSDProof

reset_densification_counter!() = Debug.reset_densification_counter!()

densification_counter() = Debug.densification_counter()

replay_chordal_psd(matrix, proof) = Kernel.verify_chordal_psd(matrix, proof)

end
