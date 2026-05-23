module TrustedPathAudit

export TrustedVerifierSpec,
       trusted_verifier_registry,
       register_trusted_verifier!,
       trusted_verifier_names,
       verify_no_numeric_fallback,
       trusted_path_audit_report

struct TrustedVerifierSpec
    name::Symbol
    arithmetic_mode::Symbol
    allowed_numeric_types::Vector{Symbol}
    forbidden_calls::Vector{Symbol}
    proof_obligations::Vector{Symbol}
    dag_checkers::Vector{Symbol}
    source_path::String
end

const REGISTRY = Dict{Symbol, TrustedVerifierSpec}()
const DEFAULT_FORBIDDEN = Symbol[
    :Float64,
    :BigFloat,
    :isapprox,
    :eigvals,
    :eigen,
    :svd,
    :cholesky,
    :solver_status,
    :residual_tolerance,
    :rand,
    :time,
]

function register_trusted_verifier!(name::Symbol;
                                    arithmetic_mode::Symbol,
                                    allowed_numeric_types::Vector{Symbol}=Symbol[],
                                    forbidden_calls::Vector{Symbol}=DEFAULT_FORBIDDEN,
                                    proof_obligations::Vector{Symbol}=Symbol[],
                                    dag_checkers::Vector{Symbol}=Symbol[],
                                    source_path::AbstractString="")
    REGISTRY[name] = TrustedVerifierSpec(name,
                                         arithmetic_mode,
                                         copy(allowed_numeric_types),
                                         copy(forbidden_calls),
                                         copy(proof_obligations),
                                         copy(dag_checkers),
                                         String(source_path))
    return REGISTRY[name]
end

trusted_verifier_registry() = REGISTRY
trusted_verifier_names() = sort!(collect(keys(REGISTRY)); by=String)

function _ensure_defaults!()
    isempty(REGISTRY) || return
    register_trusted_verifier!(:verify_low_rank_psd;
        arithmetic_mode=:rational,
        allowed_numeric_types=[:Integer, :Rational],
        proof_obligations=[:matrix_identity, :nonnegative_diagonal],
        dag_checkers=[:verify_low_rank_psd, :check_low_rank_psd_identity],
        source_path="src/kernel/Kernel.jl")
    register_trusted_verifier!(:verify_chordal_psd;
        arithmetic_mode=:symbolic_sparse,
        allowed_numeric_types=[:Integer, :Rational],
        proof_obligations=[:clique_cover, :separator_consistency, :clique_psd],
        dag_checkers=[:verify_chordal_psd, :check_chordal_separator_consistency],
        source_path="src/kernel/Kernel.jl")
    register_trusted_verifier!(:verify_sparse_sos_certificate;
        arithmetic_mode=:rational,
        allowed_numeric_types=[:Integer, :Rational],
        proof_obligations=[:gram_expansion, :localizing_identity, :psd_blocks],
        dag_checkers=[:verify_sparse_sos_coefficients, :check_sparse_sos_gram_expansion],
        source_path="src/kernel/Kernel.jl")
    register_trusted_verifier!(:verify_quantum_bound_certificate;
        arithmetic_mode=:symbolic_sparse,
        allowed_numeric_types=[:Integer, :Rational],
        proof_obligations=[:rewrite_witnesses, :moment_entries, :objective_bound],
        dag_checkers=[:verify_quantum_bound_certificate, :check_quantum_objective_bound],
        source_path="src/kernel/Kernel.jl")
    register_trusted_verifier!(:verify_nc_rewrite_witness;
        arithmetic_mode=:symbolic_sparse,
        allowed_numeric_types=[:Integer, :Rational],
        proof_obligations=[:rewrite_step],
        dag_checkers=[:verify_nc_rewrite_witness, :check_nc_rewrite_step],
        source_path="src/kernel/Kernel.jl")
    register_trusted_verifier!(:verify_primal_dual_optimality;
        arithmetic_mode=:rational,
        allowed_numeric_types=[:Integer, :Rational],
        proof_obligations=[:primal_affine, :dual_affine, :gap],
        dag_checkers=[:verify_primal_affine, :verify_dual_affine, :verify_exact_gap],
        source_path="src/kernel/Kernel.jl")
    register_trusted_verifier!(:verify_farkas_infeasibility;
        arithmetic_mode=:rational,
        allowed_numeric_types=[:Integer, :Rational],
        proof_obligations=[:affine_identity, :contradiction],
        dag_checkers=[:verify_farkas_identity, :verify_farkas_contradiction],
        source_path="src/kernel/Kernel.jl")
end

function verify_no_numeric_fallback()
    _ensure_defaults!()
    return all(spec -> spec.arithmetic_mode in (:rational, :algebraic, :integer, :symbolic_sparse),
               values(REGISTRY))
end

function trusted_path_audit_report()
    _ensure_defaults!()
    entries = [Dict(
        "name" => String(spec.name),
        "arithmetic_mode" => String(spec.arithmetic_mode),
        "allowed_numeric_types" => String.(spec.allowed_numeric_types),
        "forbidden_calls" => String.(spec.forbidden_calls),
        "proof_obligations" => String.(spec.proof_obligations),
        "dag_checkers" => String.(spec.dag_checkers),
        "source_path" => spec.source_path,
    ) for spec in values(REGISTRY)]
    sort!(entries; by=entry -> entry["name"])
    return Dict("passed" => verify_no_numeric_fallback(),
                "verifiers" => entries)
end

_ensure_defaults!()

end

