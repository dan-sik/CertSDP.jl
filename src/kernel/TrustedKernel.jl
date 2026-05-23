module TrustedKernel

using ..Kernel

export trusted_kernel_files,
       trusted_verifier_functions,
       trusted_arithmetic_modes,
       assert_trusted_exact_path,
       verify_no_numeric_fallback,
       trusted_replay

const TRUSTED_FILES = [
    "src/kernel/Kernel.jl",
    "src/kernel/TrustedKernel.jl",
    "src/kernel/CertificateDAG.jl",
    "src/kernel/StrictSchema.jl",
    "src/kernel/ExactArithmeticSafety.jl",
    "src/kernel/SparseBlockChordal.jl",
    "src/kernel/PSDProofs.jl",
    "src/kernel/SOSProofs.jl",
    "src/kernel/NCQuantumProofs.jl",
    "src/kernel/AlgebraicFields.jl",
    "src/kernel/CanonicalHash.jl",
]

const TRUSTED_VERIFIERS = Dict{Symbol, Symbol}(
    :parse_certificate_json_v3 => :symbolic_sparse,
    :verify_certificate => :symbolic_sparse,
    :verify_low_rank_psd => :rational,
    :verify_algebraic_low_rank_psd => :algebraic,
    :verify_chordal_psd => :symbolic_sparse,
    :verify_block_native_algebraic_certificate => :algebraic,
    :verify_primal_dual_optimality => :rational,
    :verify_farkas_infeasibility => :rational,
    :verify_sparse_sos_certificate => :rational,
    :verify_quantum_bound_certificate => :symbolic_sparse,
    :verify_proof_dag => :integer,
)

trusted_kernel_files() = copy(TRUSTED_FILES)

trusted_verifier_functions() = sort!(collect(keys(TRUSTED_VERIFIERS)); by=String)

trusted_arithmetic_modes() = copy(TRUSTED_VERIFIERS)

function assert_trusted_exact_path()
    return all(mode -> mode in (:rational, :algebraic, :integer, :symbolic_sparse),
               values(TRUSTED_VERIFIERS))
end

function verify_no_numeric_fallback()
    assert_trusted_exact_path() || return false
    return true
end

function trusted_replay(path::AbstractString)
    verify_no_numeric_fallback() ||
        return Kernel.DiagnosticReport(false,
                                       :V,
                                       :trusted_kernel,
                                       :arithmetic_mode,
                                       "trusted verifier arithmetic mode is not exact",
                                       :trusted_exact_path,
                                       nothing,
                                       nothing,
                                       nothing,
                                       nothing,
                                       nothing,
                                       String(path),
                                       Dict{Symbol, Any}())
    return Kernel.replay_file(path; strict=true, io=nothing)
end

end
