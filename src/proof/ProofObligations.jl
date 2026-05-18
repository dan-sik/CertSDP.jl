"""
    ProofObligation

Small schema-v2-oriented description of one exact replay obligation. This is a
diagnostic model, not a verifier bypass: accepted certificates still use their
existing exact replay functions.
"""
struct ProofObligation
    id::Symbol
    kind::Symbol
    statement::String
    inputs::Vector{Symbol}
    exact::Bool
end

"""
    ProofObligationGraph

Typed collection of replay obligations attached to a problem/certificate
family. The graph is intentionally simple so it can be serialized in future
paper artifacts and schema-v2 drafts.
"""
struct ProofObligationGraph
    family::Symbol
    obligations::Vector{ProofObligation}
end

function proof_obligation_json(obligation::ProofObligation)
    return (;
            id=String(obligation.id),
            kind=String(obligation.kind),
            statement=obligation.statement,
            inputs=String.(obligation.inputs),
            exact=obligation.exact,)
end

function proof_obligation_graph_json(graph::ProofObligationGraph)
    return (;
            family=String(graph.family),
            obligations=[proof_obligation_json(obligation)
                         for obligation in graph.obligations],)
end

function proof_obligation_graph(cert::RationalCertificate)
    return ProofObligationGraph(:rational_lmi,
                                ProofObligation[ProofObligation(:problem_hash,
                                                                :hash,
                                                                "canonical LMI problem hash matches embedded certificate hash",
                                                                [:problem, :certificate],
                                                                true),
                                                ProofObligation(:linear_substitution,
                                                                :exact_equality,
                                                                "A(x) is recomputed over QQ from exact coordinates",
                                                                [:problem, :solution],
                                                                true),
                                                ProofObligation(:psd_replay,
                                                                :psd,
                                                                "recomputed matrix is positive semidefinite over QQ by the recorded exact PSD method",
                                                                [:substituted_matrix,
                                                                 :proof],
                                                                true)])
end

function proof_obligation_graph(cert::BlockRationalCertificate)
    return ProofObligationGraph(:block_rational_lmi,
                                ProofObligation[ProofObligation(:problem_hash,
                                                                :hash,
                                                                "canonical block LMI problem hash matches embedded certificate hash",
                                                                [:problem, :certificate],
                                                                true),
                                                ProofObligation(:block_substitution,
                                                                :exact_equality,
                                                                "each PSD block is recomputed over QQ from shared exact coordinates",
                                                                [:problem, :solution],
                                                                true),
                                                ProofObligation(:block_psd_replay,
                                                                :psd,
                                                                "each recomputed block is positive semidefinite over QQ",
                                                                [:substituted_blocks,
                                                                 :proof],
                                                                true)])
end

function proof_obligation_graph(cert::AlgebraicCertificate)
    return ProofObligationGraph(:algebraic_lmi,
                                ProofObligation[ProofObligation(:problem_hash,
                                                                :hash,
                                                                "canonical LMI problem hash matches embedded certificate hash",
                                                                [:problem, :certificate],
                                                                true),
                                                ProofObligation(:root_isolation,
                                                                :algebraic_root,
                                                                "the defining polynomial has the isolated real root used by the solution field",
                                                                [:minimal_polynomial,
                                                                 :root_interval],
                                                                true),
                                                ProofObligation(:linear_substitution,
                                                                :exact_equality,
                                                                "A(x) is recomputed in the algebraic field",
                                                                [:problem, :solution],
                                                                true),
                                                ProofObligation(:algebraic_signs,
                                                                :sign,
                                                                "PSD signs are certified using exact algebraic sign tests",
                                                                [:field, :proof],
                                                                true)])
end

function proof_obligation_graph(cert::BlockAlgebraicCertificate)
    return ProofObligationGraph(:block_algebraic_lmi,
                                ProofObligation[ProofObligation(:problem_hash,
                                                                :hash,
                                                                "canonical block LMI problem hash matches embedded certificate hash",
                                                                [:problem, :certificate],
                                                                true),
                                                ProofObligation(:root_isolation,
                                                                :algebraic_root,
                                                                "the defining polynomial has the isolated real root used by the solution field",
                                                                [:minimal_polynomial,
                                                                 :root_interval],
                                                                true),
                                                ProofObligation(:block_substitution,
                                                                :exact_equality,
                                                                "each PSD block is recomputed in the algebraic field",
                                                                [:problem, :solution],
                                                                true),
                                                ProofObligation(:block_algebraic_signs,
                                                                :sign,
                                                                "each block PSD sign obligation is certified exactly",
                                                                [:field, :proof],
                                                                true)])
end

function proof_obligation_graph(cert::SOSGramCertificate)
    return ProofObligationGraph(:sos_gram,
                                ProofObligation[ProofObligation(:problem_hash,
                                                                :hash,
                                                                "canonical SOS Gram problem hash matches embedded certificate hash",
                                                                [:problem, :certificate],
                                                                true),
                                                ProofObligation(:coefficient_matching,
                                                                :exact_equality,
                                                                "target polynomial equals v'Qv coefficient-by-coefficient over QQ",
                                                                [:sos_problem,
                                                                 :gram_matrix],
                                                                true),
                                                ProofObligation(:gram_psd,
                                                                :psd,
                                                                "Gram matrix PSD is replayed through an embedded rational LMI certificate",
                                                                [:gram_matrix,
                                                                 :lmi_certificate],
                                                                true),
                                                ProofObligation(:decomposition_export,
                                                                :export_safety,
                                                                "SOS square export is replayed when present or safely omitted",
                                                                [:decomposition],
                                                                true)])
end

function proof_obligation_graph(cert::PerturbationCompensationSOSCertificate)
    return ProofObligationGraph(:perturbation_compensation_sos,
                                ProofObligation[ProofObligation(:problem_hash,
                                                                :hash,
                                                                "canonical perturbation/compensation problem hash matches embedded certificate hash",
                                                                [:problem, :certificate],
                                                                true),
                                                ProofObligation(:perturbed_identity,
                                                                :exact_equality,
                                                                "target plus perturbation equals the perturbed SOS over QQ",
                                                                [:target, :perturbation,
                                                                 :perturbed_sos],
                                                                true),
                                                ProofObligation(:compensation_identity,
                                                                :exact_equality,
                                                                "target equals perturbed SOS minus compensation SOS over QQ",
                                                                [:target, :perturbed_sos,
                                                                 :compensation_sos],
                                                                true)])
end

function proof_obligation_graph(cert::AlgebraicSOSGramCertificate)
    return ProofObligationGraph(:algebraic_sos_gram,
                                ProofObligation[ProofObligation(:problem_hash,
                                                                :hash,
                                                                "canonical algebraic SOS Gram problem hash matches embedded certificate hash",
                                                                [:problem, :certificate],
                                                                true),
                                                ProofObligation(:root_isolation,
                                                                :algebraic_root,
                                                                "the defining polynomial isolates the selected real root for QQ(alpha)",
                                                                [:minimal_polynomial,
                                                                 :root_interval],
                                                                true),
                                                ProofObligation(:coefficient_matching,
                                                                :exact_equality,
                                                                "target polynomial equals v'Qv coefficient-by-coefficient over QQ(alpha)",
                                                                [:sos_problem,
                                                                 :gram_matrix],
                                                                true),
                                                ProofObligation(:gram_psd,
                                                                :psd,
                                                                "Gram matrix PSD is replayed by algebraic sign obligations",
                                                                [:gram_matrix, :psd_proof],
                                                                true)])
end

function proof_obligation_graph(cert::NCSOSGramCertificate)
    return ProofObligationGraph(:nc_sos_gram,
                                ProofObligation[ProofObligation(:problem_hash,
                                                                :hash,
                                                                "canonical NC SOS Gram problem hash matches embedded certificate hash",
                                                                [:problem, :certificate],
                                                                true),
                                                ProofObligation(:word_coefficient_matching,
                                                                :exact_equality,
                                                                "target word polynomial equals v^*Qv over QQ, optionally modulo trace-cyclic rotations",
                                                                [:nc_problem, :gram_matrix],
                                                                true),
                                                ProofObligation(:word_relations,
                                                                :symbolic_rewrite,
                                                                "involution and trace-cyclic canonicalization are replayed symbolically",
                                                                [:basis, :relations],
                                                                true),
                                                ProofObligation(:gram_psd,
                                                                :psd,
                                                                "NC Gram matrix PSD is replayed through an embedded rational LMI certificate",
                                                                [:gram_matrix,
                                                                 :lmi_certificate],
                                                                true)])
end
