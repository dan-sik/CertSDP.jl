module GateRegistry

using JSON3: JSON3
using ..TrustedKernel

export GateSpec,
       gate_registry,
       gate_ids,
       gate_spec,
       fixture_index,
       fixture_by_id,
       fixtures_for_gate,
       tamper_paths_for_fixture,
       exact_verifiers_for_gate,
       gate_score

struct GateSpec
    id::Symbol
    title::String
    required_fixtures::Vector{String}
    required_tamper_fixtures::Vector{String}
    required_tests::Vector{String}
    required_cli_checks::Vector{String}
    required_audit_checks::Vector{String}
    required_exact_verifier_functions::Vector{Symbol}
    semi_real_required::Bool
end

const GATE_SPECS = GateSpec[
    GateSpec(:A, "Trusted verification boundary",
             ["psd_factor_rational_150"], ["psd_factor_rational_150/tampered_negative_diagonal.json"],
             ["kernel_trust_boundary.jl", "adapter_untrusted_metadata_rejection.jl",
              "exactify_candidates_must_replay.jl"],
             ["replay_valid", "replay_tamper"], ["static_rules", "trusted_exact_path"],
             [:verify_certificate, :verify_low_rank_psd], true),
    GateSpec(:B, "Sparse/block/chordal IR",
             ["sparse_chordal_120", "sparse_chordal_stress_3000"],
             ["sparse_chordal_120/tampered_wrong_separator.json",
              "sparse_chordal_stress_3000/tampered_separator_entry_changed.json"],
             ["sparse_ir.jl", "chordal_psd_certificate.jl", "no_densification_budget.jl"],
             ["replay_valid", "replay_tamper"], ["no_densification", "fixture_shape"],
             [:verify_chordal_psd], true),
    GateSpec(:C, "Block-native algebraic",
             ["block_native_algebraic_medium"],
             ["block_native_algebraic_medium/tampered_block_3_kernel.json"],
             ["block_native_incidence.jl", "block_native_algebraic_certificate.jl"],
             ["replay_valid", "replay_tamper", "certify_candidate"],
             ["block_native_replay", "no_densification"],
             [:verify_block_native_algebraic_certificate], true),
    GateSpec(:D, "Large PSD proof engine",
             ["psd_factor_rational_150", "psd_factor_algebraic_40", "sparse_chordal_120"],
             ["psd_factor_rational_150/tampered_negative_diagonal.json",
              "psd_factor_algebraic_40/tampered_algebraic_sign.json",
              "sparse_chordal_120/tampered_wrong_clique_psd.json"],
             ["psd_low_rank_factor.jl", "psd_chordal_completion.jl",
              "psd_planner_policy.jl"],
             ["replay_valid", "replay_tamper"], ["exact_psd_proof", "planner_policy"],
             [:verify_low_rank_psd, :verify_algebraic_low_rank_psd,
              :verify_chordal_psd], true),
    GateSpec(:E, "CertificateDAG mandatory",
             ["psd_factor_rational_150", "quantum_i3322_medium"],
             ["psd_factor_rational_150/tampered_negative_diagonal.json"],
             ["proof_dag_roundtrip.jl", "proof_dag_tamper.jl"],
             ["replay_valid", "replay_tamper"], ["dag_replay", "dag_root_hash"],
             [:verify_proof_dag], true),
    GateSpec(:F, "Strict semantic schema",
             ["psd_factor_rational_150"],
             ["psd_factor_rational_150/tampered_negative_diagonal.json"],
             ["schema_strict.jl", "schema_fuzz_mutations.jl"],
             ["schema_valid", "schema_tamper"], ["strict_schema", "semantic_schema"],
             [:parse_certificate_json_v3], true),
    GateSpec(:G, "Primal-dual/Farkas",
             ["primal_dual_portfolio_50", "farkas_infeasible_lmi_medium"],
             ["primal_dual_portfolio_50/tampered_gap_value.json",
              "farkas_infeasible_lmi_medium/tampered_multiplier.json"],
             ["primal_dual_optimality.jl", "farkas_certificate.jl",
              "objective_bound_certificate.jl"],
             ["replay_valid", "replay_tamper"], ["exact_gap", "farkas_contradiction"],
             [:verify_primal_dual_optimality, :verify_farkas_infeasibility],
             true),
    GateSpec(:H, "Sparse SOS/Putinar",
             ["sparse_sos_control_lyapunov", "sparse_putinar_opf_5bus"],
             ["sparse_sos_control_lyapunov/tampered_gram_block.json",
              "sparse_putinar_opf_5bus/tampered_localizing_coefficient_map.json"],
             ["sparse_sos_certificate.jl", "localizing_matrix_replay.jl",
              "putinar_certificate.jl"],
             ["replay_valid", "replay_tamper"], ["coefficient_matching", "sos_psd"],
             [:verify_sparse_sos_certificate], true),
    GateSpec(:I, "TSSOS importer",
             ["tssos_sparse_industry_medium"],
             ["tssos_sparse_industry_medium/tampered_coefficient_map.json"],
             ["tssos_importer.jl", "tssos_tamper_rejection.jl"],
             ["import_tssos", "replay_tamper"], ["adapter_untrusted", "normal_verify"],
             [:verify_sparse_sos_certificate], true),
    GateSpec(:J, "NC/Quantum/NPA",
             ["quantum_chsh_level2", "quantum_i3322_medium"],
             ["quantum_i3322_medium/tampered_commutation_relation.json"],
             ["nc_rewrite_witness.jl", "quantum_bound_certificate.jl",
              "npa_certificate_replay.jl"],
             ["replay_valid", "replay_tamper"], ["rewrite_witness", "moment_psd"],
             [:verify_quantum_bound_certificate], true),
    GateSpec(:K, "NCTSSOS importer",
             ["nctssos_trace_medium"],
             ["nctssos_trace_medium/tampered_quotient_relation.json"],
             ["nctssos_importer.jl"],
             ["import_nctssos", "replay_tamper"], ["adapter_untrusted", "normal_verify"],
             [:verify_quantum_bound_certificate], true),
    GateSpec(:L, "Number field/algebraic layer",
             ["psd_factor_algebraic_40"],
             ["psd_factor_algebraic_40/tampered_algebraic_sign.json"],
             ["field_layer.jl", "psd_low_rank_factor.jl"],
             ["replay_valid", "replay_tamper"], ["field_hash", "exact_sign"],
             [:verify_algebraic_low_rank_psd], true),
    GateSpec(:M, "Algebraic candidate backend",
             ["block_native_algebraic_medium"],
             ["block_native_algebraic_medium/tampered_block_3_kernel.json"],
             ["algebraic_backend_interface.jl", "msolve_fixture_backend.jl",
              "backend_failure_semantics.jl"],
             ["certify_candidate"], ["fixture_backend_replay", "null_backend_reject"],
             [:verify_block_native_algebraic_certificate], false),
    GateSpec(:N, "Untrusted adapters",
             ["tssos_sparse_industry_medium", "nctssos_trace_medium"],
             ["tssos_sparse_industry_medium/tampered_clique_basis.json",
              "nctssos_trace_medium/tampered_quotient_relation.json"],
             ["sdpa_sparse_adapter.jl", "tssos_importer.jl", "nctssos_importer.jl"],
             ["import_tssos", "import_nctssos"], ["metadata_ignored", "normal_verify"],
             [:verify_sparse_sos_certificate, :verify_quantum_bound_certificate],
             true),
    GateSpec(:O, "Diagnostics/explain",
             ["psd_factor_rational_150"], ["psd_factor_rational_150/tampered_negative_diagonal.json"],
             ["diagnostics_report.jl", "cli_replay_explain.jl"],
             ["diagnose_valid", "diagnose_tamper"], ["structured_failure"],
             [:verify_certificate], false),
    GateSpec(:P, "CLI product surface",
             ["psd_factor_rational_150"], ["psd_factor_rational_150/tampered_negative_diagonal.json"],
             ["cli_product_surface.jl", "validation_cli_surface.jl"],
             ["replay_valid", "replay_tamper", "schema_valid"], ["subprocess_cli"],
             [:verify_certificate], false),
    GateSpec(:Q, "Validation corpus",
             ["psd_factor_rational_150", "sparse_chordal_stress_3000",
              "primal_dual_portfolio_50", "farkas_infeasible_lmi_medium",
              "tssos_sparse_industry_medium", "sparse_putinar_opf_5bus",
              "sparse_sos_control_lyapunov", "quantum_i3322_medium",
              "nctssos_trace_medium", "psd_factor_algebraic_40"],
             ["psd_factor_rational_150/tampered_negative_diagonal.json"],
             ["validation_cli_surface.jl"], ["replay_valid", "replay_tamper"],
             ["semi_real_minimums", "index_schema"], [:verify_certificate], true),
    GateSpec(:R, "Tamper/negative testing",
             ["psd_factor_rational_150"], ["psd_factor_rational_150/tampered_negative_diagonal.json"],
             ["mutation_corpus.jl"], ["replay_tamper"], ["mutation_harness"],
             [:verify_certificate], false),
    GateSpec(:S, "Performance budgets",
             ["sparse_chordal_stress_3000"], ["sparse_chordal_stress_3000/tampered_graph_hash_changed.json"],
             ["no_densification_budget.jl"], ["replay_valid"], ["runtime_budget", "memory_budget"],
             [:verify_chordal_psd], true),
    GateSpec(:T, "No silent densification",
             ["sparse_chordal_stress_3000"], ["sparse_chordal_stress_3000/tampered_separator_entry_changed.json"],
             ["no_densification_budget.jl"], ["replay_valid"], ["densification_counter"],
             [:verify_chordal_psd], true),
    GateSpec(:U, "Hash stability/canonicalization",
             ["psd_factor_rational_150", "sparse_chordal_120"],
             ["psd_factor_rational_150/tampered_negative_diagonal.json"],
             ["hash_stability.jl"], ["schema_valid"], ["canonical_roundtrip"],
             [:parse_certificate_json_v3], true),
    GateSpec(:V, "Exact arithmetic safety",
             ["psd_factor_rational_150"], ["psd_factor_rational_150/tampered_negative_diagonal.json"],
             ["psd_low_rank_factor.jl"], ["replay_valid", "replay_tamper"],
             ["static_rules", "trusted_exact_path"], [:verify_low_rank_psd], true),
    GateSpec(:W, "Symmetry reduction",
             ["symmetric_sos_cyclic_medium"], ["symmetric_sos_cyclic_medium/tampered_group_action.json"],
             ["symmetry_reduction.jl"], ["replay_valid", "replay_tamper"],
             ["block_reconstruction"], [:verify_block_diagonalization_certificate], true),
    GateSpec(:X, "Paper bundle",
             ["psd_factor_rational_150"], ["psd_factor_rational_150/tampered_negative_diagonal.json"],
             ["paper_bundle.jl"], ["bundle_verify"], ["offline_bundle_replay"],
             [:verify_certificate], false),
    GateSpec(:Y, "Backward compatibility/migration",
             ["psd_factor_rational_150"], ["psd_factor_rational_150/tampered_negative_diagonal.json"],
             ["backward_compatibility.jl", "migration_v1_v2_to_v3.jl"],
             ["replay_valid"], ["legacy_api_preserved"], [:verify_certificate], false),
    GateSpec(:Z, "Release audit",
             ["psd_factor_rational_150"], ["psd_factor_rational_150/tampered_negative_diagonal.json"],
             ["test_release_audit.jl"], ["audit_strict_full"], ["audit_report", "gate_scores"],
             [:verify_certificate], false),
    GateSpec(:QA, "QA/determinism/coverage",
             ["psd_factor_rational_150", "quantum_i3322_medium"],
             ["quantum_i3322_medium/tampered_psd_proof.json"],
             ["test_qa_determinism.jl"], ["replay_valid"], ["determinism", "negative_coverage"],
             TrustedKernel.trusted_verifier_functions(), true),
]

gate_registry() = copy(GATE_SPECS)

gate_ids() = [spec.id for spec in GATE_SPECS]

function gate_spec(id::Symbol)
    for spec in GATE_SPECS
        spec.id === id && return spec
    end
    throw(ArgumentError("unknown CertSDP 3.0 gate `$id`"))
end

function fixture_index(root::AbstractString)
    return JSON3.read(read(joinpath(root, "index.json"), String))[:fixtures]
end

function fixture_by_id(root::AbstractString)
    return Dict(String(fixture[:fixture_id]) => fixture
                for fixture in fixture_index(root))
end

function fixtures_for_gate(root::AbstractString, id::Symbol)
    wanted = String(id)
    return [fixture for fixture in fixture_index(root)
            if wanted in String.(fixture[:gate_ids_covered])]
end

function tamper_paths_for_fixture(root::AbstractString, fixture)
    dir = joinpath(root, String(fixture[:fixture_id]))
    return [joinpath(dir, String(path)) for path in fixture[:tamper_files]]
end

exact_verifiers_for_gate(id::Symbol) =
    gate_spec(id).required_exact_verifier_functions

function gate_score(; valid::Bool,
                    has_tamper::Bool,
                    has_cli::Bool,
                    has_dag::Bool,
                    has_audit::Bool,
                    semi_real::Bool,
                    diagnostics::Bool,
                    mutations::Bool,
                    performance::Bool)
    score = 0
    valid && (score = max(score, 6))
    has_tamper && (score = max(score, 8))
    has_cli && has_dag && has_audit && (score = max(score, 8))
    semi_real && mutations && performance && diagnostics && (score = max(score, 10))
    has_tamper || (score = min(score, 4))
    has_cli || (score = min(score, 5))
    has_dag || (score = min(score, 6))
    has_audit || (score = min(score, 7))
    semi_real || (score = min(score, 8))
    diagnostics || (score = min(score, 8))
    mutations || (score = min(score, 9))
    return score
end

end
