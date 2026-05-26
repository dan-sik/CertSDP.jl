module Kernel

using JSON3: JSON3
using SHA: sha256

export CERTSDP3_SCHEMA_VERSION,
       AbstractExactConeBlock,
       SparseSymmetricRationalMatrix,
       SparseAffineLMI,
       ChordalPSDStructure,
       ExactLowRankPSDProof,
       ExactAlgebraicLowRankPSDProof,
       SeparatorConsistencyProof,
       CliquePSDProof,
       ChordalPSDProof,
       ProofNode,
       CertificateDAG,
       DiagnosticReport,
       BlockNativeIncidenceBlock,
       BlockNativeIncidenceSystem,
       AlgebraicFieldCertificate,
       AlgebraicElement,
       AlgebraicLinearTerm,
       AlgebraicEquationObligation,
       BlockNativeActiveBlockProof,
       BlockNativeInactivePSDProof,
       BlockNativeAlgebraicCertificate,
       ConicAffineBlock,
       ExactConicProblem,
       PrimalFeasibilityCertificate,
       DualFeasibilityCertificate,
       PrimalDualOptimalityCertificate,
       ObjectiveBoundCertificate,
       FarkasInfeasibilityCertificate,
       PolynomialTerm,
       SparseSOSBlock,
       LocalizingMatrixProof,
       SparseSOSProblem,
       PutinarCertificate,
       SparseSOSCertificate,
       SymmetryPermutation,
       SymmetryGroupCertificate,
       OrbitBasisCertificate,
       BlockDiagonalizationCertificate,
       AbstractQuantumRelation,
       ProjectionRelation,
       UnitaryRelation,
       CommutationRelation,
       TraceCyclicRelation,
       StarInvolutionRelation,
       NormalizationRelation,
       NCRewriteStep,
       NCRewriteWitness,
       NPAProblem,
       NCMomentMatrixCertificate,
       QuantumBoundCertificate,
       V3Certificate,
       sparse_matrix_hash,
       sparse_affine_lmi_hash,
       chordal_structure_hash,
       low_rank_identity_hash,
       substitute,
       entries_dict,
       verify_low_rank_psd,
       verify_algebraic_low_rank_psd,
       verify_chordal_psd,
       verify_block_native_algebraic_certificate,
       verify_primal_dual_optimality,
       verify_farkas_infeasibility,
       verify_sparse_sos_certificate,
       verify_block_diagonalization_certificate,
       block_native_incidence_block_json,
       block_native_incidence_system_json,
       algebraic_field_certificate_json,
       algebraic_element_json,
       algebraic_equation_obligation_json,
       block_native_active_block_proof_json,
       block_native_inactive_psd_proof_json,
       block_native_algebraic_certificate_json,
       block_native_algebraic_certificate_dag,
       block_native_algebraic_certificate_dag_json,
       parse_block_native_algebraic_certificate_json,
       primal_dual_optimality_certificate_json,
       parse_primal_dual_optimality_certificate_json,
       farkas_infeasibility_certificate_json,
       parse_farkas_infeasibility_certificate_json,
       algebraic_low_rank_psd_certificate_json,
       parse_algebraic_low_rank_psd_certificate_json,
       sparse_affine_lmi_json,
       sparse_sos_certificate_json,
       parse_sparse_sos_certificate_json,
       block_diagonalization_certificate_json,
       parse_block_diagonalization_certificate_json,
       proof_dag,
       proof_dag_json,
       verify_proof_dag,
       parse_certificate_json_v3,
       certificate_json_v3,
       verify_certificate,
       replay_file,
       diagnose_file,
       diagnostic_report_json,
       diagnostic_report_text,
       diagnostic_report_html,
       validate_certificate_schema_v3,
       validate_problem_schema_v3,
       make_low_rank_psd_certificate,
       make_chordal_psd_certificate,
       make_block_native_algebraic_certificate,
       make_primal_dual_optimality_certificate,
       make_farkas_infeasibility_certificate,
       make_sparse_sos_certificate,
       npa_problem_hash,
       verify_nc_rewrite_witness,
       verify_quantum_bound_certificate,
       make_quantum_bound_certificate,
       quantum_bound_certificate_json,
       parse_quantum_bound_certificate_json

const CERTSDP3_SCHEMA_VERSION = "3.0"
const SHA256_PREFIX = "sha256:"
const FORBIDDEN_TRUST_KEYS = Set(Symbol[
    :accepted,
    :verified,
    :certificate_valid,
    :solver_log,
    :solver_output,
    :raw_solver_log,
    :raw_solver_stdout,
    :raw_solver_stderr,
    :backend_log,
    :backend_output,
    :msolve_log,
    :msolve_output,
    :numerical_solution,
    :approximate_solution,
])

abstract type AbstractExactConeBlock end

struct SparseSymmetricRationalMatrix
    n::Int
    entries::Vector{Tuple{Int, Int, Rational{BigInt}}}
    hash::String
end

struct SparseAffineLMI
    variables::Vector{Symbol}
    A0::SparseSymmetricRationalMatrix
    A::Vector{SparseSymmetricRationalMatrix}
    blocks::Vector{AbstractExactConeBlock}
    metadata::Dict{Symbol, Any}
    hash::String
end

struct ChordalPSDStructure <: AbstractExactConeBlock
    n::Int
    cliques::Vector{Vector{Int}}
    separators::Vector{Vector{Int}}
    graph_hash::String
end

struct ExactLowRankPSDProof
    field::Symbol
    matrix_hash::String
    factor::Vector{Vector{Rational{BigInt}}}
    diagonal::Vector{Rational{BigInt}}
    identity_proof_hash::String
end

struct SeparatorConsistencyProof
    id::Symbol
    left_clique::Int
    right_clique::Int
    vertices::Vector{Int}
    value_hash::String
end

struct CliquePSDProof
    id::Symbol
    clique_index::Int
    vertices::Vector{Int}
    matrix::SparseSymmetricRationalMatrix
    psd_proof::ExactLowRankPSDProof
end

struct ChordalPSDProof
    theorem_tag::Symbol
    matrix_hash::String
    structure::ChordalPSDStructure
    clique_proofs::Vector{CliquePSDProof}
    separator_proofs::Vector{SeparatorConsistencyProof}
    proof_hash::String
end

struct ProofNode
    id::Symbol
    kind::Symbol
    inputs::Vector{String}
    output_hash::String
    checker::Symbol
    status::Symbol
    typed_payload::Dict{Symbol, Any}
    input_hashes::Vector{String}
    arithmetic_mode::Symbol
    source_location::Union{Nothing, String}
    obligation_id::Symbol
    version::String
end

struct CertificateDAG
    claim_type::Symbol
    nodes::Vector{ProofNode}
    root_hash::String
    schema_version::String
    object_store::Dict{String, Any}
end

function _canonical_json_value(value)
    value isa Symbol && return String(value)
    value isa Rational && return rational_string(value)
    value isa AbstractString && return String(value)
    value isa Integer && return Int(value)
    value isa Bool && return Bool(value)
    value === nothing && return nothing
    if value isa NamedTuple
        return Dict(String(key) => _canonical_json_value(getfield(value, key))
                    for key in sort!(collect(keys(value)); by=String))
    elseif value isa AbstractDict
        return Dict(String(key) => _canonical_json_value(val)
                    for (key, val) in sort!(collect(value); by=pair -> String(pair[1])))
    elseif value isa Tuple || value isa AbstractVector
        return [_canonical_json_value(item) for item in value]
    end
    return value
end

function ProofNode(id::Symbol,
                   kind::Symbol,
                   inputs::Vector{String},
                   output_hash::AbstractString,
                   checker::Symbol,
                   status::Symbol;
                   typed_payload::AbstractDict=Dict{Symbol, Any}(),
                   input_hashes::AbstractVector{<:AbstractString}=inputs,
                   arithmetic_mode::Symbol=:rational,
                   source_location::Union{Nothing, AbstractString}=nothing,
                   obligation_id::Union{Nothing, Symbol}=nothing,
                   version::AbstractString=CERTSDP3_SCHEMA_VERSION)
    payload = Dict{Symbol, Any}(Symbol(key) => value for (key, value) in typed_payload)
    return ProofNode(id,
                     kind,
                     String.(inputs),
                     String(output_hash),
                     checker,
                     status,
                     payload,
                     String.(input_hashes),
                     arithmetic_mode,
                     isnothing(source_location) ? nothing : String(source_location),
                     isnothing(obligation_id) ? id : obligation_id,
                     String(version))
end

function _final_accept_hash(claim_type::Symbol, nodes::AbstractVector{ProofNode})
    return _sha256_payload((; claim_type=String(claim_type),
                              inputs=sort([node.output_hash for node in nodes])))
end

function _ensure_final_accept_node(claim_type::Symbol,
                                   nodes::Vector{ProofNode})
    any(node -> node.checker === :final_accept, nodes) && return nodes
    inputs = [node.output_hash for node in nodes]
    final = ProofNode(:final_accept,
                      :final_accept,
                      inputs,
                      _final_accept_hash(claim_type, nodes),
                      :final_accept,
                      :pending;
                      typed_payload=Dict(:claim_type => String(claim_type),
                                         :required_inputs => sort(inputs)),
                      input_hashes=inputs,
                      arithmetic_mode=:integer,
                      obligation_id=:final_accept)
    return vcat(nodes, ProofNode[final])
end

function _dag_object_store(nodes::AbstractVector{ProofNode})
    store = Dict{String, Any}()
    for node in nodes
        payload = Dict{String, Any}(
            "id" => String(node.id),
            "kind" => String(node.kind),
            "checker" => String(node.checker),
            "payload" => _canonical_json_value(node.typed_payload),
            "arithmetic_mode" => String(node.arithmetic_mode),
            "obligation_id" => String(node.obligation_id),
            "version" => node.version,
        )
        if haskey(store, node.output_hash) && store[node.output_hash] != payload
            throw(ArgumentError("DAG object store duplicate hash with different payload: $(node.output_hash)"))
        end
        store[node.output_hash] = payload
    end
    return store
end

function CertificateDAG(claim_type::Symbol,
                        nodes::Vector{ProofNode},
                        root_hash::AbstractString,
                        schema_version::AbstractString)
    full_nodes = _ensure_final_accept_node(claim_type, nodes)
    store = _dag_object_store(full_nodes)
    effective_root = isempty(String(root_hash)) ?
                     certificate_dag_hash_without_root(CertificateDAG(claim_type,
                                                                      full_nodes,
                                                                      String(root_hash),
                                                                      String(schema_version),
                                                                      store)) :
                     String(root_hash)
    return CertificateDAG(claim_type,
                          full_nodes,
                          effective_root,
                          String(schema_version),
                          store)
end

struct DiagnosticReport
    accepted::Bool
    gate::Symbol
    family::Symbol
    stage::Symbol
    reason::String
    obligation_id::Symbol
    problem_hash::Union{Nothing, String}
    certificate_hash::Union{Nothing, String}
    block_id::Union{Nothing, Symbol}
    clique_id::Union{Nothing, Symbol}
    separator_id::Union{Nothing, Symbol}
    artifact_path::Union{Nothing, String}
    details::Dict{Symbol, Any}
end

struct BlockNativeIncidenceBlock
    block_index::Int
    block_hash::String
    rank::Int
    kernel_dimension::Int
    variable_names::Vector{Symbol}
    gauge_rows::Vector{Int}
    slicing_strategy::Symbol
    active::Bool
    system_hash::String
end

struct BlockNativeIncidenceSystem
    problem_hash::String
    shared_variables::Vector{Symbol}
    blocks::Vector{BlockNativeIncidenceBlock}
    system_hash::String
end

struct AlgebraicFieldCertificate
    id::Symbol
    generator::Symbol
    minimal_polynomial::Vector{Rational{BigInt}}
    isolating_interval::Tuple{Rational{BigInt}, Rational{BigInt}}
    field_hash::String
end

struct AlgebraicElement
    field_hash::String
    coefficients::Vector{Rational{BigInt}}
    element_hash::String
end

struct ExactAlgebraicLowRankPSDProof
    matrix_hash::String
    field::AlgebraicFieldCertificate
    factor::Vector{Vector{AlgebraicElement}}
    diagonal::Vector{AlgebraicElement}
    identity_proof_hash::String
end

struct AlgebraicLinearTerm
    variable::Symbol
    coefficient::AlgebraicElement
end

struct AlgebraicEquationObligation
    id::Symbol
    terms::Vector{AlgebraicLinearTerm}
    constant::AlgebraicElement
end

struct BlockNativeActiveBlockProof
    block_index::Int
    block_hash::String
    field::AlgebraicFieldCertificate
    values::Dict{Symbol, AlgebraicElement}
    incidence_equations::Vector{AlgebraicEquationObligation}
    gauge_equations::Vector{AlgebraicEquationObligation}
    proof_hash::String
end

struct BlockNativeInactivePSDProof
    block_index::Int
    block_hash::String
    margin_matrix::SparseSymmetricRationalMatrix
    psd_proof::ExactLowRankPSDProof
    proof_hash::String
end

struct BlockNativeAlgebraicCertificate
    problem_hash::String
    incidence::BlockNativeIncidenceSystem
    active_block_proofs::Dict{Int, BlockNativeActiveBlockProof}
    inactive_psd_proofs::Dict{Int, BlockNativeInactivePSDProof}
    certificate_hash::String
end

struct ConicAffineBlock
    id::Symbol
    cone::Symbol
    B::SparseSymmetricRationalMatrix
    A::Vector{SparseSymmetricRationalMatrix}
end

struct ExactConicProblem
    sense::Symbol
    variables::Vector{Symbol}
    objective::Vector{Rational{BigInt}}
    blocks::Vector{ConicAffineBlock}
    dual_objective_coefficients::Vector{Rational{BigInt}}
    problem_hash::String
end

struct PrimalFeasibilityCertificate
    problem_hash::String
    problem::Union{Nothing, ExactConicProblem}
    primal_vector::Vector{Rational{BigInt}}
    affine_lhs::Vector{Rational{BigInt}}
    affine_rhs::Vector{Rational{BigInt}}
    cone_matrices::Vector{SparseSymmetricRationalMatrix}
    cone_proofs::Vector{ExactLowRankPSDProof}
    objective_value::Rational{BigInt}
end

struct DualFeasibilityCertificate
    problem_hash::String
    problem::Union{Nothing, ExactConicProblem}
    dual_variables::Vector{SparseSymmetricRationalMatrix}
    affine_lhs::Vector{Rational{BigInt}}
    affine_rhs::Vector{Rational{BigInt}}
    cone_matrices::Vector{SparseSymmetricRationalMatrix}
    cone_proofs::Vector{ExactLowRankPSDProof}
    objective_value::Rational{BigInt}
end

PrimalFeasibilityCertificate(problem_hash::String,
                             affine_lhs::Vector{Rational{BigInt}},
                             affine_rhs::Vector{Rational{BigInt}},
                             cone_matrices::Vector{SparseSymmetricRationalMatrix},
                             cone_proofs::Vector{ExactLowRankPSDProof},
                             objective_value::Rational{BigInt}) =
    PrimalFeasibilityCertificate(problem_hash, nothing, Rational{BigInt}[],
                                 affine_lhs, affine_rhs, cone_matrices,
                                 cone_proofs, objective_value)

PrimalFeasibilityCertificate(problem_hash::AbstractString,
                             affine_lhs::AbstractVector,
                             affine_rhs::AbstractVector,
                             cone_matrices::AbstractVector{SparseSymmetricRationalMatrix},
                             cone_proofs::AbstractVector{ExactLowRankPSDProof},
                             objective_value) =
    PrimalFeasibilityCertificate(String(problem_hash),
                                 [_to_big_rational(value, "primal.affine_lhs[$i]")
                                  for (i, value) in enumerate(affine_lhs)],
                                 [_to_big_rational(value, "primal.affine_rhs[$i]")
                                  for (i, value) in enumerate(affine_rhs)],
                                 SparseSymmetricRationalMatrix[cone_matrices...],
                                 ExactLowRankPSDProof[cone_proofs...],
                                 _to_big_rational(objective_value,
                                                  "primal.objective_value"))

DualFeasibilityCertificate(problem_hash::String,
                           affine_lhs::Vector{Rational{BigInt}},
                           affine_rhs::Vector{Rational{BigInt}},
                           cone_matrices::Vector{SparseSymmetricRationalMatrix},
                           cone_proofs::Vector{ExactLowRankPSDProof},
                           objective_value::Rational{BigInt}) =
    DualFeasibilityCertificate(problem_hash, nothing,
                               SparseSymmetricRationalMatrix[], affine_lhs,
                               affine_rhs, cone_matrices, cone_proofs,
                               objective_value)

DualFeasibilityCertificate(problem_hash::AbstractString,
                           affine_lhs::AbstractVector,
                           affine_rhs::AbstractVector,
                           cone_matrices::AbstractVector{SparseSymmetricRationalMatrix},
                           cone_proofs::AbstractVector{ExactLowRankPSDProof},
                           objective_value) =
    DualFeasibilityCertificate(String(problem_hash),
                               [_to_big_rational(value, "dual.affine_lhs[$i]")
                                for (i, value) in enumerate(affine_lhs)],
                               [_to_big_rational(value, "dual.affine_rhs[$i]")
                                for (i, value) in enumerate(affine_rhs)],
                               SparseSymmetricRationalMatrix[cone_matrices...],
                               ExactLowRankPSDProof[cone_proofs...],
                               _to_big_rational(objective_value,
                                                "dual.objective_value"))

struct PrimalDualOptimalityCertificate
    problem_hash::String
    primal::PrimalFeasibilityCertificate
    dual::DualFeasibilityCertificate
    gap::Rational{BigInt}
    certificate_hash::String
    dag::CertificateDAG
end

struct ObjectiveBoundCertificate
    problem_hash::String
    bound::Rational{BigInt}
    sense::Symbol
    optimality_certificate_hash::String
end

struct FarkasInfeasibilityCertificate
    problem_hash::String
    problem::Union{Nothing, ExactConicProblem}
    dual_variables::Vector{SparseSymmetricRationalMatrix}
    multiplier_identity_lhs::Vector{Rational{BigInt}}
    multiplier_identity_rhs::Vector{Rational{BigInt}}
    cone_proofs::Vector{ExactLowRankPSDProof}
    contradiction_lhs::Rational{BigInt}
    contradiction_rhs::Rational{BigInt}
    certificate_hash::String
    dag::CertificateDAG
end

FarkasInfeasibilityCertificate(problem_hash::String,
                               multiplier_identity_lhs::Vector{Rational{BigInt}},
                               multiplier_identity_rhs::Vector{Rational{BigInt}},
                               cone_proofs::Vector{ExactLowRankPSDProof},
                               contradiction_lhs::Rational{BigInt},
                               contradiction_rhs::Rational{BigInt},
                               certificate_hash::String,
                               dag::CertificateDAG) =
    FarkasInfeasibilityCertificate(problem_hash, nothing,
                                   SparseSymmetricRationalMatrix[],
                                   multiplier_identity_lhs,
                                   multiplier_identity_rhs,
                                   cone_proofs,
                                   contradiction_lhs,
                                   contradiction_rhs,
                                   certificate_hash,
                                   dag)

struct PolynomialTerm
    exponents::Vector{Int}
    coefficient::Rational{BigInt}
end

struct SparseSOSBlock
    id::Symbol
    clique_id::Symbol
    basis_exponents::Vector{Vector{Int}}
    gram_matrix::SparseSymmetricRationalMatrix
    psd_proof::ExactLowRankPSDProof
    coefficient_terms::Vector{PolynomialTerm}
end

struct LocalizingMatrixProof
    id::Symbol
    clique_id::Symbol
    constraint_terms::Vector{PolynomialTerm}
    sos_block::SparseSOSBlock
end

struct SparseSOSProblem
    variables::Vector{Symbol}
    target_terms::Vector{PolynomialTerm}
    cliques::Vector{Vector{Symbol}}
    lower_bound::Rational{BigInt}
    problem_hash::String
end

struct PutinarCertificate
    localizing_blocks::Vector{LocalizingMatrixProof}
    bound::Rational{BigInt}
    identity_hash::String
end

struct SparseSOSCertificate
    problem::SparseSOSProblem
    sos_blocks::Vector{SparseSOSBlock}
    putinar::Union{Nothing, PutinarCertificate}
    certificate_hash::String
    dag::CertificateDAG
end

struct SymmetryPermutation
    id::Symbol
    image::Vector{Int}
end

struct SymmetryGroupCertificate
    variables::Vector{Symbol}
    generators::Vector{SymmetryPermutation}
    action_hash::String
end

struct OrbitBasisCertificate
    monomial_exponents::Vector{Vector{Int}}
    orbits::Vector{Vector{Int}}
    orbit_hash::String
end

struct BlockDiagonalizationCertificate
    problem_hash::String
    group::SymmetryGroupCertificate
    orbit_basis::OrbitBasisCertificate
    projection_blocks::Vector{SparseSymmetricRationalMatrix}
    projector_matrices::Vector{SparseSymmetricRationalMatrix}
    original_matrix::SparseSymmetricRationalMatrix
    reconstructed_matrix::SparseSymmetricRationalMatrix
    certificate_hash::String
    dag::CertificateDAG
end

abstract type AbstractQuantumRelation end

struct ProjectionRelation <: AbstractQuantumRelation
    id::Symbol
    symbol::Symbol
end

struct UnitaryRelation <: AbstractQuantumRelation
    id::Symbol
    symbol::Symbol
end

struct CommutationRelation <: AbstractQuantumRelation
    id::Symbol
    left_symbols::Vector{Symbol}
    right_symbols::Vector{Symbol}
end

struct TraceCyclicRelation <: AbstractQuantumRelation
    id::Symbol
end

struct StarInvolutionRelation <: AbstractQuantumRelation
    id::Symbol
end

struct NormalizationRelation <: AbstractQuantumRelation
    id::Symbol
    value::Rational{BigInt}
end

struct NCRewriteStep
    relation_id::Symbol
    rule::Symbol
    before::Vector{Symbol}
    after::Vector{Symbol}
end

struct NCRewriteWitness
    input_word::Vector{Symbol}
    steps::Vector{NCRewriteStep}
    final_word::Vector{Symbol}
    relation_ids_used::Vector{Symbol}
    trace_rotations::Vector{Vector{Symbol}}
    star_steps::Vector{Vector{Symbol}}
end

struct NPAProblem
    variables::Vector{Symbol}
    relations::Vector{AbstractQuantumRelation}
    word_basis::Vector{Vector{Symbol}}
    trace_cyclic::Bool
    problem_hash::String
end

struct NCMomentMatrixCertificate
    problem_hash::String
    moment_matrix::SparseSymmetricRationalMatrix
    psd_proof::ExactLowRankPSDProof
    coefficient_terms::Vector{Tuple{Vector{Symbol}, Rational{BigInt}}}
    witnesses::Vector{NCRewriteWitness}
    certificate_hash::String
end

struct QuantumBoundCertificate
    problem::NPAProblem
    moment_certificate::NCMomentMatrixCertificate
    objective_terms::Vector{Tuple{Vector{Symbol}, Rational{BigInt}}}
    bound::Rational{BigInt}
    certificate_hash::String
    dag::CertificateDAG
end

struct V3Certificate
    certificate_type::Symbol
    certificate_id::String
    problem_hash::String
    claim::Dict{Symbol, Any}
    proof::Any
    dag::CertificateDAG
    metadata::Dict{Symbol, Any}
    hash::String
end

SparseSymmetricRationalMatrix(n::Integer,
                              entries::AbstractVector{<:Tuple}) =
    _sparse_matrix_from_entries(Int(n), entries; reject_conflicts=true)

function SparseAffineLMI(variables::AbstractVector{Symbol},
                         A0::SparseSymmetricRationalMatrix,
                         A::AbstractVector{SparseSymmetricRationalMatrix};
                         blocks::AbstractVector{<:AbstractExactConeBlock}=AbstractExactConeBlock[],
                         metadata::AbstractDict=Dict{Symbol, Any}())
    vars = collect(variables)
    length(unique(vars)) == length(vars) ||
        throw(ArgumentError("SparseAffineLMI variables must be unique"))
    length(A) == length(vars) ||
        throw(ArgumentError("SparseAffineLMI coefficient count must match variables"))
    all(matrix -> matrix.n == A0.n, A) ||
        throw(ArgumentError("SparseAffineLMI coefficient dimensions must match A0"))
    copied_metadata = Dict{Symbol, Any}(Symbol(key) => value for (key, value) in metadata)
    blocks_vector = AbstractExactConeBlock[blocks...]
    obj = SparseAffineLMI(vars, A0, collect(A), blocks_vector, copied_metadata, "")
    return SparseAffineLMI(vars, A0, collect(A), blocks_vector, copied_metadata,
                           sparse_affine_lmi_hash(obj))
end

function ChordalPSDStructure(n::Integer,
                             cliques::AbstractVector,
                             separators::AbstractVector)
    n_value = Int(n)
    n_value > 0 || throw(ArgumentError("ChordalPSDStructure n must be positive"))
    parsed_cliques = [_parse_index_vector(clique, n_value, "clique")
                      for clique in cliques]
    parsed_separators = [_parse_index_vector(separator, n_value, "separator")
                         for separator in separators]
    isempty(parsed_cliques) &&
        throw(ArgumentError("ChordalPSDStructure requires at least one clique"))
    payload = _canonical_chordal_structure_payload(n_value, parsed_cliques,
                                                   parsed_separators)
    return ChordalPSDStructure(n_value, parsed_cliques, parsed_separators,
                               _sha256_payload(payload))
end

function ExactLowRankPSDProof(matrix::SparseSymmetricRationalMatrix,
                              factor,
                              diagonal;
                              field::Symbol=:QQ)
    rows = _parse_rational_row_matrix(factor, "factor")
    diag = [_to_big_rational(value, "diagonal[$i]")
            for (i, value) in enumerate(diagonal)]
    proof = ExactLowRankPSDProof(field, matrix.hash, rows, diag, "")
    return ExactLowRankPSDProof(field, matrix.hash, rows, diag,
                                low_rank_identity_hash(proof))
end

function ExactAlgebraicLowRankPSDProof(matrix::SparseSymmetricRationalMatrix,
                                       field::AlgebraicFieldCertificate,
                                       factor,
                                       diagonal)
    parsed_factor = Vector{AlgebraicElement}[]
    rank = length(diagonal)
    for (i, row) in enumerate(factor)
        length(row) == rank ||
            throw(ArgumentError("algebraic factor row $i has wrong width"))
        parsed_row = AlgebraicElement[]
        for entry in row
            entry.field_hash == field.field_hash ||
                throw(ArgumentError("algebraic factor entry belongs to the wrong field"))
            push!(parsed_row, entry)
        end
        push!(parsed_factor, parsed_row)
    end
    parsed_diag = AlgebraicElement[]
    for entry in diagonal
        entry.field_hash == field.field_hash ||
            throw(ArgumentError("algebraic diagonal entry belongs to the wrong field"))
        push!(parsed_diag, entry)
    end
    proof0 = ExactAlgebraicLowRankPSDProof(matrix.hash, field,
                                          parsed_factor, parsed_diag, "")
    return ExactAlgebraicLowRankPSDProof(matrix.hash, field,
                                         parsed_factor, parsed_diag,
                                         algebraic_low_rank_identity_hash(proof0))
end

function ChordalPSDProof(matrix::SparseSymmetricRationalMatrix,
                         structure::ChordalPSDStructure,
                         clique_proofs::AbstractVector{CliquePSDProof},
                         separator_proofs::AbstractVector{SeparatorConsistencyProof};
                         theorem_tag::Symbol=:positive_semidefinite_completion_for_chordal_graph)
    proof = ChordalPSDProof(theorem_tag, matrix.hash, structure,
                            CliquePSDProof[clique_proofs...],
                            SeparatorConsistencyProof[separator_proofs...], "")
    return ChordalPSDProof(theorem_tag, matrix.hash, structure,
                           CliquePSDProof[clique_proofs...],
                           SeparatorConsistencyProof[separator_proofs...],
                           chordal_proof_hash(proof))
end

function sparse_matrix_hash(matrix::SparseSymmetricRationalMatrix)
    return _sha256_payload(_canonical_sparse_matrix_payload(matrix.n,
                                                            matrix.entries))
end

function sparse_affine_lmi_hash(problem::SparseAffineLMI)
    return _sha256_payload(_canonical_sparse_affine_lmi_payload(problem))
end

function chordal_structure_hash(structure::ChordalPSDStructure)
    return _sha256_payload(_canonical_chordal_structure_payload(structure.n,
                                                                structure.cliques,
                                                                structure.separators))
end

function chordal_proof_hash(proof::ChordalPSDProof)
    return _sha256_payload(_canonical_chordal_proof_payload(proof))
end

function ConicAffineBlock(id::Symbol,
                          cone::Symbol,
                          B::SparseSymmetricRationalMatrix,
                          A::AbstractVector{SparseSymmetricRationalMatrix})
    cone in (:PSD, :diagonal_nonnegative, :nonnegative_vector, :equality) ||
        throw(ArgumentError("unsupported conic block cone `$cone`"))
    all(matrix -> matrix.n == B.n, A) ||
        throw(ArgumentError("affine block coefficient dimensions must match B"))
    return ConicAffineBlock(id, cone, B, SparseSymmetricRationalMatrix[A...])
end

function ExactConicProblem(sense::Symbol,
                           variables::AbstractVector{Symbol},
                           objective,
                           blocks::AbstractVector{ConicAffineBlock};
                           dual_objective_coefficients=Rational{BigInt}[])
    sense in (:min, :max) || throw(ArgumentError("conic problem sense must be :min or :max"))
    vars = Symbol.(collect(variables))
    length(unique(vars)) == length(vars) ||
        throw(ArgumentError("conic problem variables must be unique"))
    c = [_to_big_rational(value, "objective[$i]")
         for (i, value) in enumerate(objective)]
    length(c) == length(vars) ||
        throw(ArgumentError("objective length must match variables"))
    parsed_blocks = ConicAffineBlock[blocks...]
    isempty(parsed_blocks) && throw(ArgumentError("conic problem needs at least one block"))
    for block in parsed_blocks
        length(block.A) == length(vars) ||
            throw(ArgumentError("affine block $(block.id) coefficient count must match variables"))
    end
    dual_coeffs = [_to_big_rational(value, "dual_objective_coefficients[$i]")
                   for (i, value) in enumerate(dual_objective_coefficients)]
    problem0 = ExactConicProblem(sense, vars, c, parsed_blocks, dual_coeffs, "")
    return ExactConicProblem(sense, vars, c, parsed_blocks, dual_coeffs,
                             exact_conic_problem_hash(problem0))
end

function conic_affine_block_json(block::ConicAffineBlock)
    return (;
        id=String(block.id),
        cone=String(block.cone),
        B=sparse_matrix_json(block.B),
        A=[sparse_matrix_json(matrix) for matrix in block.A],
    )
end

function exact_conic_problem_json(problem::ExactConicProblem)
    return (;
        sense=String(problem.sense),
        variables=String.(problem.variables),
        objective=rational_string.(problem.objective),
        blocks=[conic_affine_block_json(block) for block in problem.blocks],
        dual_objective_coefficients=rational_string.(problem.dual_objective_coefficients),
        problem_hash=problem.problem_hash,
    )
end

function exact_conic_problem_hash(problem::ExactConicProblem)
    return _sha256_payload((;
        sense=String(problem.sense),
        variables=String.(problem.variables),
        objective=rational_string.(problem.objective),
        blocks=[conic_affine_block_json(block) for block in problem.blocks],
        dual_objective_coefficients=rational_string.(problem.dual_objective_coefficients),
    ))
end

function block_native_incidence_block_json(block::BlockNativeIncidenceBlock)
    return (;
        block_index=block.block_index,
        block_hash=block.block_hash,
        rank=block.rank,
        kernel_dimension=block.kernel_dimension,
        variable_names=String.(block.variable_names),
        gauge_rows=block.gauge_rows,
        slicing_strategy=String(block.slicing_strategy),
        active=block.active,
        system_hash=block.system_hash,
    )
end

function block_native_incidence_system_json(system::BlockNativeIncidenceSystem)
    return (;
        problem_hash=system.problem_hash,
        shared_variables=String.(system.shared_variables),
        blocks=[block_native_incidence_block_json(block) for block in system.blocks],
        system_hash=system.system_hash,
    )
end

function block_native_incidence_system_hash(system::BlockNativeIncidenceSystem)
    payload = (;
        problem_hash=system.problem_hash,
        shared_variables=String.(system.shared_variables),
        blocks=[merge(block_native_incidence_block_json(block),
                      (; system_hash=block.system_hash))
                for block in system.blocks],
    )
    return _sha256_payload(payload)
end

function AlgebraicFieldCertificate(id::Symbol,
                                   generator::Symbol,
                                   minimal_polynomial,
                                   isolating_interval)
    coefficients = [_to_big_rational(value, "minimal_polynomial[$i]")
                    for (i, value) in enumerate(minimal_polynomial)]
    length(coefficients) >= 2 ||
        throw(ArgumentError("algebraic field minimal polynomial must have positive degree"))
    last(coefficients) == 0 &&
        throw(ArgumentError("algebraic field minimal polynomial leading coefficient must be nonzero"))
    left = _to_big_rational(isolating_interval[1], "isolating_interval[1]")
    right = _to_big_rational(isolating_interval[2], "isolating_interval[2]")
    left < right ||
        throw(ArgumentError("algebraic field isolating interval must have positive width"))
    root_count = _sturm_root_count(coefficients, left, right)
    root_count == 1 ||
        throw(ArgumentError("algebraic field isolating interval must isolate exactly one real root; got $root_count"))
    field0 = AlgebraicFieldCertificate(id, generator, coefficients,
                                       (left, right), "")
    return AlgebraicFieldCertificate(id, generator, coefficients,
                                     (left, right),
                                     algebraic_field_certificate_hash(field0))
end

function AlgebraicElement(field::AlgebraicFieldCertificate, coefficients)
    values = [_to_big_rational(value, "algebraic_element[$i]")
              for (i, value) in enumerate(coefficients)]
    degree = length(field.minimal_polynomial) - 1
    length(values) <= degree ||
        throw(ArgumentError("algebraic element has degree $(length(values) - 1); field degree is $degree"))
    normalized = vcat(values, fill(0//1, degree - length(values)))
    element0 = AlgebraicElement(field.field_hash, normalized, "")
    return AlgebraicElement(field.field_hash, normalized,
                            algebraic_element_hash(element0))
end

function AlgebraicEquationObligation(id::Symbol,
                                     terms::AbstractVector{AlgebraicLinearTerm},
                                     constant::AlgebraicElement)
    return AlgebraicEquationObligation(id,
                                       AlgebraicLinearTerm[terms...],
                                       constant)
end

function BlockNativeActiveBlockProof(block_index::Integer,
                                     block_hash::AbstractString,
                                     field::AlgebraicFieldCertificate,
                                     values::AbstractDict,
                                     incidence_equations::AbstractVector{AlgebraicEquationObligation},
                                     gauge_equations::AbstractVector{AlgebraicEquationObligation})
    parsed_values = Dict{Symbol, AlgebraicElement}()
    for (key, value) in values
        symbol_key = Symbol(key)
        value.field_hash == field.field_hash ||
            throw(ArgumentError("active block value `$symbol_key` belongs to the wrong field"))
        parsed_values[symbol_key] = value
    end
    for equation in vcat(incidence_equations, gauge_equations)
        equation.constant.field_hash == field.field_hash ||
            throw(ArgumentError("equation $(equation.id) constant belongs to the wrong field"))
        for term in equation.terms
            term.coefficient.field_hash == field.field_hash ||
                throw(ArgumentError("equation $(equation.id) term $(term.variable) belongs to the wrong field"))
        end
    end
    proof0 = BlockNativeActiveBlockProof(Int(block_index), String(block_hash),
                                         field, parsed_values,
                                         AlgebraicEquationObligation[incidence_equations...],
                                         AlgebraicEquationObligation[gauge_equations...],
                                         "")
    return BlockNativeActiveBlockProof(Int(block_index), String(block_hash),
                                       field, parsed_values,
                                       AlgebraicEquationObligation[incidence_equations...],
                                       AlgebraicEquationObligation[gauge_equations...],
                                       block_native_active_block_proof_hash(proof0))
end

function BlockNativeInactivePSDProof(block_index::Integer,
                                     block_hash::AbstractString,
                                     margin_matrix::SparseSymmetricRationalMatrix,
                                     psd_proof::ExactLowRankPSDProof)
    proof0 = BlockNativeInactivePSDProof(Int(block_index),
                                         String(block_hash),
                                         margin_matrix,
                                         psd_proof,
                                         "")
    return BlockNativeInactivePSDProof(Int(block_index),
                                       String(block_hash),
                                       margin_matrix,
                                       psd_proof,
                                       block_native_inactive_psd_proof_hash(proof0))
end

function algebraic_field_certificate_json(field::AlgebraicFieldCertificate)
    return (;
        id=String(field.id),
        generator=String(field.generator),
        minimal_polynomial=rational_string.(field.minimal_polynomial),
        isolating_interval=(rational_string(field.isolating_interval[1]),
                            rational_string(field.isolating_interval[2])),
        field_hash=field.field_hash,
    )
end

function algebraic_field_certificate_hash(field::AlgebraicFieldCertificate)
    payload = (;
        id=String(field.id),
        generator=String(field.generator),
        minimal_polynomial=rational_string.(field.minimal_polynomial),
        isolating_interval=[rational_string(field.isolating_interval[1]),
                            rational_string(field.isolating_interval[2])],
    )
    return _sha256_payload(payload)
end

function algebraic_low_rank_proof_json(proof::ExactAlgebraicLowRankPSDProof)
    return (;
        matrix_hash=proof.matrix_hash,
        field=algebraic_field_certificate_json(proof.field),
        factor=[[algebraic_element_json(value) for value in row]
                for row in proof.factor],
        diagonal=[algebraic_element_json(value) for value in proof.diagonal],
        identity_proof_hash=proof.identity_proof_hash,
    )
end

function algebraic_element_json(element::AlgebraicElement)
    return (;
        field_hash=element.field_hash,
        coefficients=rational_string.(element.coefficients),
        element_hash=element.element_hash,
    )
end

function algebraic_element_hash(element::AlgebraicElement)
    payload = (;
        field_hash=element.field_hash,
        coefficients=rational_string.(element.coefficients),
    )
    return _sha256_payload(payload)
end

function algebraic_linear_term_json(term::AlgebraicLinearTerm)
    return (;
        variable=String(term.variable),
        coefficient=algebraic_element_json(term.coefficient),
    )
end

function algebraic_equation_obligation_json(equation::AlgebraicEquationObligation)
    return (;
        id=String(equation.id),
        terms=[algebraic_linear_term_json(term) for term in equation.terms],
        constant=algebraic_element_json(equation.constant),
    )
end

function block_native_active_block_proof_json(proof::BlockNativeActiveBlockProof)
    value_pairs = sort(collect(proof.values); by=first)
    return (;
        block_index=proof.block_index,
        block_hash=proof.block_hash,
        field=algebraic_field_certificate_json(proof.field),
        values=Dict(String(key) => algebraic_element_json(value)
                    for (key, value) in value_pairs),
        incidence_equations=[algebraic_equation_obligation_json(equation)
                             for equation in proof.incidence_equations],
        gauge_equations=[algebraic_equation_obligation_json(equation)
                         for equation in proof.gauge_equations],
        proof_hash=proof.proof_hash,
    )
end

function block_native_active_block_proof_hash(proof::BlockNativeActiveBlockProof)
    payload = merge(block_native_active_block_proof_json(proof),
                    (; proof_hash=""))
    return _sha256_payload(payload)
end

function block_native_inactive_psd_proof_json(proof::BlockNativeInactivePSDProof)
    return (;
        block_index=proof.block_index,
        block_hash=proof.block_hash,
        margin_matrix=sparse_matrix_json(proof.margin_matrix),
        psd_proof=low_rank_proof_json(proof.psd_proof),
        proof_hash=proof.proof_hash,
    )
end

function block_native_inactive_psd_proof_hash(proof::BlockNativeInactivePSDProof)
    payload = merge(block_native_inactive_psd_proof_json(proof),
                    (; proof_hash=""))
    return _sha256_payload(payload)
end

function block_native_algebraic_certificate_json(cert::BlockNativeAlgebraicCertificate)
    active_pairs = sort(collect(cert.active_block_proofs); by=first)
    inactive_pairs = sort(collect(cert.inactive_psd_proofs); by=first)
    return (;
        certsdp_block_native_certificate_version=CERTSDP3_SCHEMA_VERSION,
        problem_hash=cert.problem_hash,
        incidence=block_native_incidence_system_json(cert.incidence),
        active_block_proofs=[block_native_active_block_proof_json(proof)
                             for (_, proof) in active_pairs],
        inactive_psd_proofs=[block_native_inactive_psd_proof_json(proof)
                             for (_, proof) in inactive_pairs],
        proof_dag=block_native_algebraic_certificate_dag_json(cert),
        certificate_hash=cert.certificate_hash,
    )
end

function block_native_algebraic_certificate_hash(cert::BlockNativeAlgebraicCertificate)
    payload = (;
        problem_hash=cert.problem_hash,
        incidence=block_native_incidence_system_json(cert.incidence),
        active_block_proofs=[block_native_active_block_proof_json(proof)
                             for (_, proof) in sort(collect(cert.active_block_proofs);
                                                    by=first)],
        inactive_psd_proofs=[block_native_inactive_psd_proof_json(proof)
                             for (_, proof) in sort(collect(cert.inactive_psd_proofs);
                                                    by=first)],
    )
    return _sha256_payload(payload)
end

function block_native_algebraic_certificate_dag(cert::BlockNativeAlgebraicCertificate)
    active_hash = _sha256_payload([proof.proof_hash
                                   for (_, proof) in sort(collect(cert.active_block_proofs);
                                                          by=first)])
    inactive_hash = _sha256_payload([proof.proof_hash
                                     for (_, proof) in sort(collect(cert.inactive_psd_proofs);
                                                            by=first)])
    nodes = ProofNode[
        ProofNode(:block_native_incidence, :hash, String[],
                  cert.incidence.system_hash,
                  :block_native_incidence_system_hash, :accepted;
                  typed_payload=Dict(:incidence => block_native_incidence_system_json(cert.incidence)),
                  obligation_id=:block_native_incidence),
        ProofNode(:active_block_replay, :exact_algebraic_replay,
                  [cert.incidence.system_hash], active_hash,
                  :verify_block_native_active_blocks, :accepted;
                  typed_payload=Dict(:active_hash => active_hash,
                                     :active_block_proofs => [block_native_active_block_proof_json(proof)
                                                              for (_, proof) in sort(collect(cert.active_block_proofs);
                                                                                     by=first)]),
                  obligation_id=:active_block_replay),
        ProofNode(:inactive_psd_replay, :psd_margin,
                  [cert.incidence.system_hash], inactive_hash,
                  :verify_block_native_inactive_blocks, :accepted;
                  typed_payload=Dict(:inactive_hash => inactive_hash,
                                     :inactive_psd_proofs => [block_native_inactive_psd_proof_json(proof)
                                                              for (_, proof) in sort(collect(cert.inactive_psd_proofs);
                                                                                     by=first)]),
                  obligation_id=:inactive_psd_replay),
        ProofNode(:block_native_certificate, :exact_replay,
                  [active_hash, inactive_hash], cert.certificate_hash,
                  :verify_block_native_algebraic_certificate, :accepted;
                  typed_payload=Dict(:certificate_hash => cert.certificate_hash,
                                     :certificate => Dict(
                      :problem_hash => cert.problem_hash,
                      :incidence => block_native_incidence_system_json(cert.incidence),
                      :active_block_proofs => [block_native_active_block_proof_json(proof)
                                               for (_, proof) in sort(collect(cert.active_block_proofs);
                                                                      by=first)],
                      :inactive_psd_proofs => [block_native_inactive_psd_proof_json(proof)
                                               for (_, proof) in sort(collect(cert.inactive_psd_proofs);
                                                                      by=first)])),
                  obligation_id=:block_native_certificate),
    ]
    return CertificateDAG(:block_native_algebraic, nodes, "",
                          CERTSDP3_SCHEMA_VERSION)
end

block_native_algebraic_certificate_dag_json(cert::BlockNativeAlgebraicCertificate) =
    certificate_dag_json(block_native_algebraic_certificate_dag(cert))

function primal_dual_optimality_hash(cert::PrimalDualOptimalityCertificate)
    payload = Dict{Symbol, Any}(
        :problem_hash => cert.problem_hash,
        :primal => primal_feasibility_json(cert.primal),
        :dual => dual_feasibility_json(cert.dual),
        :gap => rational_string(cert.gap),
        :dag => certificate_dag_json(cert.dag),
    )
    isnothing(cert.primal.problem) ||
        (payload[:problem] = exact_conic_problem_json(cert.primal.problem))
    return _sha256_payload(payload)
end

function farkas_infeasibility_hash(cert::FarkasInfeasibilityCertificate)
    payload = Dict{Symbol, Any}(
        :problem_hash => cert.problem_hash,
        :multiplier_identity_lhs => rational_string.(cert.multiplier_identity_lhs),
        :multiplier_identity_rhs => rational_string.(cert.multiplier_identity_rhs),
        :cone_proofs => [low_rank_proof_json(proof) for proof in cert.cone_proofs],
        :contradiction_lhs => rational_string(cert.contradiction_lhs),
        :contradiction_rhs => rational_string(cert.contradiction_rhs),
        :dag => certificate_dag_json(cert.dag),
    )
    isnothing(cert.problem) ||
        (payload[:problem] = exact_conic_problem_json(cert.problem))
    isempty(cert.dual_variables) ||
        (payload[:dual_variables] = [sparse_matrix_json(matrix)
                                     for matrix in cert.dual_variables])
    return _sha256_payload(payload)
end

function polynomial_term_json(term::PolynomialTerm)
    return (;
        exponents=term.exponents,
        coefficient=rational_string(term.coefficient),
    )
end

function sparse_sos_problem_hash(problem::SparseSOSProblem)
    payload = (;
        variables=String.(problem.variables),
        target_terms=[polynomial_term_json(term) for term in problem.target_terms],
        cliques=[[String(variable) for variable in clique]
                 for clique in problem.cliques],
        lower_bound=rational_string(problem.lower_bound),
    )
    return _sha256_payload(payload)
end

function sparse_sos_block_json(block::SparseSOSBlock)
    return (;
        id=String(block.id),
        clique_id=String(block.clique_id),
        basis_exponents=block.basis_exponents,
        gram_matrix=sparse_matrix_json(block.gram_matrix),
        psd_proof=low_rank_proof_json(block.psd_proof),
        coefficient_terms=[polynomial_term_json(term)
                           for term in block.coefficient_terms],
    )
end

function localizing_matrix_proof_json(proof::LocalizingMatrixProof)
    return (;
        id=String(proof.id),
        clique_id=String(proof.clique_id),
        constraint_terms=[polynomial_term_json(term)
                          for term in proof.constraint_terms],
        sos_block=sparse_sos_block_json(proof.sos_block),
    )
end

function putinar_certificate_json(cert::PutinarCertificate)
    return (;
        localizing_blocks=[localizing_matrix_proof_json(block)
                           for block in cert.localizing_blocks],
        bound=rational_string(cert.bound),
        identity_hash=cert.identity_hash,
    )
end

function sparse_sos_certificate_hash(cert::SparseSOSCertificate)
    payload = (;
        problem_hash=cert.problem.problem_hash,
        sos_blocks=[sparse_sos_block_json(block) for block in cert.sos_blocks],
        putinar=isnothing(cert.putinar) ? nothing : putinar_certificate_json(cert.putinar),
        dag=certificate_dag_json(cert.dag),
    )
    return _sha256_payload(payload)
end

function sparse_sos_problem_json(problem::SparseSOSProblem)
    return (;
        variables=String.(problem.variables),
        target_terms=[polynomial_term_json(term) for term in problem.target_terms],
        cliques=[[String(variable) for variable in clique]
                 for clique in problem.cliques],
        lower_bound=rational_string(problem.lower_bound),
        problem_hash=problem.problem_hash,
    )
end

function sparse_sos_certificate_json(cert::SparseSOSCertificate)
    return (;
        certsdp_sparse_sos_certificate_version=CERTSDP3_SCHEMA_VERSION,
        problem=sparse_sos_problem_json(cert.problem),
        sos_blocks=[sparse_sos_block_json(block) for block in cert.sos_blocks],
        putinar=isnothing(cert.putinar) ? nothing : putinar_certificate_json(cert.putinar),
        proof_dag=certificate_dag_json(cert.dag),
        certificate_hash=cert.certificate_hash,
    )
end

function SymmetryPermutation(id::Symbol, image)
    values = Int.(collect(image))
    sort(values) == collect(1:length(values)) ||
        throw(ArgumentError("symmetry permutation image must be a bijection on 1:n"))
    return SymmetryPermutation(id, values)
end

function SymmetryGroupCertificate(variables::AbstractVector{Symbol},
                                  generators::AbstractVector{SymmetryPermutation})
    vars = collect(variables)
    length(unique(vars)) == length(vars) ||
        throw(ArgumentError("symmetry variables must be unique"))
    for generator in generators
        length(generator.image) == length(vars) ||
            throw(ArgumentError("symmetry generator $(generator.id) dimension mismatch"))
    end
    group0 = SymmetryGroupCertificate(vars,
                                      SymmetryPermutation[generators...],
                                      "")
    return SymmetryGroupCertificate(vars,
                                    SymmetryPermutation[generators...],
                                    symmetry_group_hash(group0))
end

function OrbitBasisCertificate(monomial_exponents::AbstractVector,
                               orbits::AbstractVector)
    exponents = [Int.(collect(row)) for row in monomial_exponents]
    orbit_values = [sort!(Int.(collect(orbit))) for orbit in orbits]
    flattened = sort!(vcat(orbit_values...))
    flattened == collect(1:length(exponents)) ||
        throw(ArgumentError("orbit basis must partition every monomial index"))
    orbit0 = OrbitBasisCertificate(exponents, orbit_values, "")
    return OrbitBasisCertificate(exponents, orbit_values,
                                 orbit_basis_hash(orbit0))
end

function BlockDiagonalizationCertificate(problem_hash::AbstractString,
                                         group::SymmetryGroupCertificate,
                                         orbit_basis::OrbitBasisCertificate,
                                         projection_blocks::AbstractVector{SparseSymmetricRationalMatrix},
                                         original_matrix::SparseSymmetricRationalMatrix,
                                         reconstructed_matrix::SparseSymmetricRationalMatrix;
                                         projector_matrices::AbstractVector{SparseSymmetricRationalMatrix}=projection_blocks)
    projector_payload = [sparse_matrix_json(block) for block in projector_matrices]
    idempotence_hash = _sha256_payload((;
        theorem="projector_idempotence",
        projectors=projector_payload))
    orthogonality_hash = _sha256_payload((;
        theorem="projector_orthogonality",
        projectors=projector_payload))
    completeness_hash = _sha256_payload((;
        theorem="projector_completeness",
        dimension=original_matrix.n,
        projectors=projector_payload))
    reconstruction_hash = reconstructed_matrix.hash
    psd_transfer_hash = _sha256_payload((;
        theorem="symmetry_psd_transfer",
        original_matrix=sparse_matrix_json(original_matrix),
        dependencies=sort(String[idempotence_hash,
                                 orthogonality_hash,
                                 completeness_hash,
                                 reconstruction_hash])))
    nodes = ProofNode[
        ProofNode(:symmetry_group, :hash, String[], group.action_hash,
                  :symmetry_group_hash, :accepted;
                  typed_payload=Dict(:group => symmetry_group_json(group)),
                  obligation_id=:symmetry_group_closure),
        ProofNode(:orbit_basis, :hash, [group.action_hash],
                  orbit_basis.orbit_hash, :orbit_basis_hash, :accepted;
                  typed_payload=Dict(:orbit_basis => orbit_basis_json(orbit_basis),
                                     :group_hash => group.action_hash),
                  obligation_id=:symmetry_orbit_partition),
        ProofNode(:projector_idempotence, :exact_identity,
                  [orbit_basis.orbit_hash],
                  idempotence_hash,
                  :check_symmetry_projector_idempotence, :accepted;
                  typed_payload=Dict(:projection_blocks => projector_payload),
                  obligation_id=:symmetry_projector_idempotence),
        ProofNode(:projector_orthogonality, :exact_identity,
                  [orbit_basis.orbit_hash],
                  orthogonality_hash,
                  :check_symmetry_projector_orthogonality, :accepted;
                  typed_payload=Dict(:projection_blocks => projector_payload),
                  obligation_id=:symmetry_projector_orthogonality),
        ProofNode(:projector_completeness, :exact_identity,
                  [idempotence_hash, orthogonality_hash],
                  completeness_hash,
                  :check_symmetry_projector_completeness, :accepted;
                  typed_payload=Dict(:projector_matrices => projector_payload,
                                     :dimension => original_matrix.n),
                  obligation_id=:symmetry_projector_completeness),
        ProofNode(:block_reconstruction, :exact_identity,
                  [orbit_basis.orbit_hash, completeness_hash],
                  reconstruction_hash,
                  :verify_block_diagonalization_certificate, :accepted;
                  typed_payload=Dict(:reconstruction_hash => reconstruction_hash,
                                     :projection_blocks => [sparse_matrix_json(block)
                                                            for block in projection_blocks],
                                     :projector_matrices => projector_payload,
                                     :projector_semantics => true,
                                     :original_matrix => sparse_matrix_json(original_matrix),
                                     :reconstructed_matrix => sparse_matrix_json(reconstructed_matrix),
                                     :group => symmetry_group_json(group),
                                     :orbit_basis => orbit_basis_json(orbit_basis)),
                  obligation_id=:symmetry_block_reconstruction),
        ProofNode(:psd_transfer_theorem, :theorem_replay,
                  [idempotence_hash,
                   orthogonality_hash,
                   completeness_hash,
                   reconstruction_hash],
                  psd_transfer_hash,
                  :check_symmetry_psd_transfer, :accepted;
                  typed_payload=Dict(:projector_idempotence_hash => idempotence_hash,
                                     :projector_orthogonality_hash => orthogonality_hash,
                                     :projector_completeness_hash => completeness_hash,
                                     :block_reconstruction_hash => reconstruction_hash,
                                     :original_matrix => sparse_matrix_json(original_matrix)),
                  obligation_id=:symmetry_psd_transfer),
    ]
    dag = CertificateDAG(:symmetry_reduction, nodes, "",
                         CERTSDP3_SCHEMA_VERSION)
    cert0 = BlockDiagonalizationCertificate(String(problem_hash),
                                            group,
                                            orbit_basis,
                                            SparseSymmetricRationalMatrix[projection_blocks...],
                                            SparseSymmetricRationalMatrix[projector_matrices...],
                                            original_matrix,
                                            reconstructed_matrix,
                                            "",
                                            dag)
    return BlockDiagonalizationCertificate(String(problem_hash),
                                           group,
                                           orbit_basis,
                                           SparseSymmetricRationalMatrix[projection_blocks...],
                                           SparseSymmetricRationalMatrix[projector_matrices...],
                                           original_matrix,
                                           reconstructed_matrix,
                                           block_diagonalization_certificate_hash(cert0),
                                           dag)
end

function symmetry_permutation_json(perm::SymmetryPermutation)
    return (; id=String(perm.id), image=perm.image)
end

function symmetry_group_json(group::SymmetryGroupCertificate)
    return (;
        variables=String.(group.variables),
        generators=[symmetry_permutation_json(generator)
                    for generator in group.generators],
        action_hash=group.action_hash,
    )
end

function symmetry_group_hash(group::SymmetryGroupCertificate)
    payload = (;
        variables=String.(group.variables),
        generators=[symmetry_permutation_json(generator)
                    for generator in group.generators],
    )
    return _sha256_payload(payload)
end

function orbit_basis_json(orbit::OrbitBasisCertificate)
    return (;
        monomial_exponents=orbit.monomial_exponents,
        orbits=orbit.orbits,
        orbit_hash=orbit.orbit_hash,
    )
end

function orbit_basis_hash(orbit::OrbitBasisCertificate)
    payload = (;
        monomial_exponents=orbit.monomial_exponents,
        orbits=orbit.orbits,
    )
    return _sha256_payload(payload)
end

function block_diagonalization_certificate_json(cert::BlockDiagonalizationCertificate)
    return (;
        certsdp_symmetry_certificate_version=CERTSDP3_SCHEMA_VERSION,
        problem_hash=cert.problem_hash,
        group=symmetry_group_json(cert.group),
        orbit_basis=orbit_basis_json(cert.orbit_basis),
        projection_blocks=[sparse_matrix_json(block)
                           for block in cert.projection_blocks],
        projector_matrices=[sparse_matrix_json(block)
                            for block in cert.projector_matrices],
        projector_semantics=(;
            idempotence=true,
            orthogonality=true,
            completeness=true,
        ),
        original_matrix=sparse_matrix_json(cert.original_matrix),
        reconstructed_matrix=sparse_matrix_json(cert.reconstructed_matrix),
        proof_dag=certificate_dag_json(cert.dag),
        certificate_hash=cert.certificate_hash,
    )
end

function block_diagonalization_certificate_hash(cert::BlockDiagonalizationCertificate)
    payload = (;
        problem_hash=cert.problem_hash,
        group=symmetry_group_json(cert.group),
        orbit_basis=orbit_basis_json(cert.orbit_basis),
        projection_blocks=[sparse_matrix_json(block)
                           for block in cert.projection_blocks],
        projector_matrices=[sparse_matrix_json(block)
                            for block in cert.projector_matrices],
        projector_semantics=(;
            idempotence=true,
            orthogonality=true,
            completeness=true,
        ),
        original_matrix=sparse_matrix_json(cert.original_matrix),
        reconstructed_matrix=sparse_matrix_json(cert.reconstructed_matrix),
        dag=certificate_dag_json(cert.dag),
    )
    return _sha256_payload(payload)
end

function quantum_relation_json(relation::ProjectionRelation)
    return (; kind="ProjectionRelation", id=String(relation.id),
             symbol=String(relation.symbol))
end

function quantum_relation_json(relation::UnitaryRelation)
    return (; kind="UnitaryRelation", id=String(relation.id),
             symbol=String(relation.symbol))
end

function quantum_relation_json(relation::CommutationRelation)
    return (; kind="CommutationRelation", id=String(relation.id),
             left_symbols=String.(relation.left_symbols),
             right_symbols=String.(relation.right_symbols))
end

function quantum_relation_json(relation::TraceCyclicRelation)
    return (; kind="TraceCyclicRelation", id=String(relation.id))
end

function quantum_relation_json(relation::StarInvolutionRelation)
    return (; kind="StarInvolutionRelation", id=String(relation.id))
end

function quantum_relation_json(relation::NormalizationRelation)
    return (; kind="NormalizationRelation", id=String(relation.id),
             value=rational_string(relation.value))
end

function npa_problem_hash(problem::NPAProblem)
    payload = (;
        type="npa_problem",
        variables=String.(problem.variables),
        relations=[quantum_relation_json(relation)
                   for relation in problem.relations],
        word_basis=[String.(word) for word in problem.word_basis],
        trace_cyclic=problem.trace_cyclic,
    )
    return _sha256_payload(payload)
end

function nc_rewrite_step_json(step::NCRewriteStep)
    return (;
        relation_id=String(step.relation_id),
        rule=String(step.rule),
        before=String.(step.before),
        after=String.(step.after),
    )
end

function nc_rewrite_witness_json(witness::NCRewriteWitness)
    return (;
        input_word=String.(witness.input_word),
        steps=[nc_rewrite_step_json(step) for step in witness.steps],
        final_word=String.(witness.final_word),
        relation_ids_used=String.(witness.relation_ids_used),
        trace_rotations=[String.(word) for word in witness.trace_rotations],
        star_steps=[String.(word) for word in witness.star_steps],
    )
end

function nc_term_json(term::Tuple{Vector{Symbol}, Rational{BigInt}})
    return (; word=String.(term[1]), coefficient=rational_string(term[2]))
end

function npa_relation_system_hash(relations::AbstractVector{<:AbstractQuantumRelation})
    return _sha256_payload([quantum_relation_json(relation) for relation in relations])
end

function npa_moment_entry_output_hash(row_index::Integer,
                                      col_index::Integer,
                                      block_id::AbstractString,
                                      normal_form::AbstractVector{Symbol},
                                      matrix_entry::Rational{BigInt})
    return _sha256_payload((;
        row_index=Int(row_index),
        col_index=Int(col_index),
        block_id=String(block_id),
        normal_form=String.(normal_form),
        matrix_entry=rational_string(matrix_entry),
    ))
end

function nc_moment_certificate_hash(cert::NCMomentMatrixCertificate)
    payload = (;
        problem_hash=cert.problem_hash,
        moment_matrix=sparse_matrix_json(cert.moment_matrix),
        psd_proof=low_rank_proof_json(cert.psd_proof),
        coefficient_terms=[nc_term_json(term)
                           for term in cert.coefficient_terms],
        witnesses=[nc_rewrite_witness_json(witness)
                   for witness in cert.witnesses],
    )
    return _sha256_payload(payload)
end

function quantum_bound_certificate_hash(cert::QuantumBoundCertificate)
    payload = (;
        problem=npa_problem_json(cert.problem),
        moment_certificate=nc_moment_certificate_json(cert.moment_certificate),
        objective_terms=[nc_term_json(term) for term in cert.objective_terms],
        bound=rational_string(cert.bound),
        dag=certificate_dag_json(cert.dag),
    )
    return _sha256_payload(payload)
end

function npa_problem_json(problem::NPAProblem)
    return (;
        variables=String.(problem.variables),
        relations=[quantum_relation_json(relation)
                   for relation in problem.relations],
        word_basis=[String.(word) for word in problem.word_basis],
        trace_cyclic=problem.trace_cyclic,
        problem_hash=problem.problem_hash,
    )
end

function nc_moment_certificate_json(cert::NCMomentMatrixCertificate)
    return (;
        problem_hash=cert.problem_hash,
        moment_matrix=sparse_matrix_json(cert.moment_matrix),
        psd_proof=low_rank_proof_json(cert.psd_proof),
        coefficient_terms=[nc_term_json(term)
                           for term in cert.coefficient_terms],
        witnesses=[nc_rewrite_witness_json(witness)
                   for witness in cert.witnesses],
        certificate_hash=cert.certificate_hash,
    )
end

function quantum_bound_certificate_json(cert::QuantumBoundCertificate)
    return (;
        certsdp_quantum_certificate_version=CERTSDP3_SCHEMA_VERSION,
        problem=npa_problem_json(cert.problem),
        moment_certificate=nc_moment_certificate_json(cert.moment_certificate),
        objective_terms=[nc_term_json(term) for term in cert.objective_terms],
        bound=rational_string(cert.bound),
        proof_dag=certificate_dag_json(cert.dag),
        certificate_hash=cert.certificate_hash,
    )
end

function primal_feasibility_json(cert::PrimalFeasibilityCertificate)
    payload = Dict{Symbol, Any}(
        :problem_hash => cert.problem_hash,
        :affine_lhs => rational_string.(cert.affine_lhs),
        :affine_rhs => rational_string.(cert.affine_rhs),
        :cone_matrices => [sparse_matrix_json(matrix) for matrix in cert.cone_matrices],
        :cone_proofs => [low_rank_proof_json(proof) for proof in cert.cone_proofs],
        :objective_value => rational_string(cert.objective_value),
    )
    isempty(cert.primal_vector) ||
        (payload[:primal_vector] = rational_string.(cert.primal_vector))
    return payload
end

function primal_dual_optimality_certificate_json(cert::PrimalDualOptimalityCertificate)
    payload = Dict{Symbol, Any}(
        :certsdp_primal_dual_certificate_version => CERTSDP3_SCHEMA_VERSION,
        :problem_hash => cert.problem_hash,
        :primal => primal_feasibility_json(cert.primal),
        :dual => dual_feasibility_json(cert.dual),
        :gap => rational_string(cert.gap),
        :proof_dag => certificate_dag_json(cert.dag),
        :certificate_hash => cert.certificate_hash,
    )
    isnothing(cert.primal.problem) ||
        (payload[:problem] = exact_conic_problem_json(cert.primal.problem))
    return payload
end

function farkas_infeasibility_certificate_json(cert::FarkasInfeasibilityCertificate)
    payload = Dict{Symbol, Any}(
        :certsdp_farkas_certificate_version => CERTSDP3_SCHEMA_VERSION,
        :problem_hash => cert.problem_hash,
        :multiplier_identity_lhs => rational_string.(cert.multiplier_identity_lhs),
        :multiplier_identity_rhs => rational_string.(cert.multiplier_identity_rhs),
        :cone_proofs => [low_rank_proof_json(proof) for proof in cert.cone_proofs],
        :contradiction_lhs => rational_string(cert.contradiction_lhs),
        :contradiction_rhs => rational_string(cert.contradiction_rhs),
        :proof_dag => certificate_dag_json(cert.dag),
        :certificate_hash => cert.certificate_hash,
    )
    isempty(cert.dual_variables) ||
        (payload[:dual_variables] = [sparse_matrix_json(matrix) for matrix in cert.dual_variables])
    isnothing(cert.problem) ||
        (payload[:problem] = exact_conic_problem_json(cert.problem))
    return payload
end

function dual_feasibility_json(cert::DualFeasibilityCertificate)
    payload = Dict{Symbol, Any}(
        :problem_hash => cert.problem_hash,
        :affine_lhs => rational_string.(cert.affine_lhs),
        :affine_rhs => rational_string.(cert.affine_rhs),
        :cone_matrices => [sparse_matrix_json(matrix) for matrix in cert.cone_matrices],
        :cone_proofs => [low_rank_proof_json(proof) for proof in cert.cone_proofs],
        :objective_value => rational_string(cert.objective_value),
    )
    isempty(cert.dual_variables) ||
        (payload[:dual_variables] = [sparse_matrix_json(matrix) for matrix in cert.dual_variables])
    return payload
end

function low_rank_identity_hash(proof::ExactLowRankPSDProof)
    payload = (;
        field=String(proof.field),
        matrix_hash=proof.matrix_hash,
        factor=[[rational_string(value) for value in row] for row in proof.factor],
        diagonal=[rational_string(value) for value in proof.diagonal],
    )
    return _sha256_payload(payload)
end

function algebraic_low_rank_identity_hash(proof::ExactAlgebraicLowRankPSDProof)
    payload = (;
        matrix_hash=proof.matrix_hash,
        field=algebraic_field_certificate_json(proof.field),
        factor=[[algebraic_element_json(value) for value in row]
                for row in proof.factor],
        diagonal=[algebraic_element_json(value) for value in proof.diagonal],
    )
    return _sha256_payload(payload)
end

function algebraic_low_rank_psd_certificate_hash(matrix::SparseSymmetricRationalMatrix,
                                                 proof::ExactAlgebraicLowRankPSDProof,
                                                 dag::CertificateDAG)
    sign_certificates = [algebraic_sign_certificate_json(value, proof.field)
                         for value in proof.diagonal]
    payload = (;
        certsdp_algebraic_psd_factor_version=CERTSDP3_SCHEMA_VERSION,
        matrix=sparse_matrix_json(matrix),
        field=algebraic_field_certificate_json(proof.field),
        factor=[[algebraic_element_json(value) for value in row]
                for row in proof.factor],
        diagonal=[algebraic_element_json(value) for value in proof.diagonal],
        sign_certificates,
        identity_proof_hash=proof.identity_proof_hash,
        proof_dag=certificate_dag_json(dag),
    )
    return _sha256_payload(payload)
end

function algebraic_sign_certificate_json(element::AlgebraicElement,
                                         field::AlgebraicFieldCertificate)
    reduced = _algebraic_reduce(element.coefficients,
                                field.minimal_polynomial)
    root_count = _sturm_root_count(reduced,
                                   field.isolating_interval[1],
                                   field.isolating_interval[2])
    sign = all(==(0//1), reduced) ? :zero :
           (_poly_eval_sign(reduced, field.isolating_interval[1]) > 0 ? :positive : :negative)
    payload = (;
        method="sturm_interval_root_exclusion",
        field_hash=field.field_hash,
        expression=rational_string.(reduced),
        isolating_interval=[rational_string(field.isolating_interval[1]),
                            rational_string(field.isolating_interval[2])],
        roots_in_interval=root_count,
        sign=String(sign),
    )
    return merge(payload, (; sign_certificate_hash=_sha256_payload(payload)))
end

function algebraic_low_rank_psd_certificate_json(matrix::SparseSymmetricRationalMatrix,
                                                 proof::ExactAlgebraicLowRankPSDProof)
    nodes = ProofNode[
        ProofNode(:matrix_hash, :hash, String[], matrix.hash,
                  :canonical_sparse_matrix_hash, :accepted;
                  typed_payload=Dict(:matrix => sparse_matrix_json(matrix)),
                  obligation_id=:matrix_hash),
        ProofNode(:algebraic_field, :field_certificate, [matrix.hash],
                  proof.field.field_hash, :verify_field_element, :accepted;
                  typed_payload=Dict(:field => algebraic_field_certificate_json(proof.field)),
                  arithmetic_mode=:algebraic,
                  obligation_id=:algebraic_field),
        ProofNode(:algebraic_low_rank_identity, :exact_identity,
                  [matrix.hash, proof.field.field_hash],
                  proof.identity_proof_hash,
                  :verify_algebraic_low_rank_psd, :accepted;
                  typed_payload=Dict(:matrix => sparse_matrix_json(matrix),
                                     :proof => algebraic_low_rank_proof_json(proof)),
                  arithmetic_mode=:algebraic,
                  obligation_id=:algebraic_low_rank_identity),
    ]
    dag = CertificateDAG(:algebraic_low_rank_psd, nodes, "",
                         CERTSDP3_SCHEMA_VERSION)
    hash = algebraic_low_rank_psd_certificate_hash(matrix, proof, dag)
    return (;
        certsdp_algebraic_psd_factor_version=CERTSDP3_SCHEMA_VERSION,
        matrix=sparse_matrix_json(matrix),
        field=algebraic_field_certificate_json(proof.field),
        factor=[[algebraic_element_json(value) for value in row]
                for row in proof.factor],
        diagonal=[algebraic_element_json(value) for value in proof.diagonal],
        sign_certificates=[algebraic_sign_certificate_json(value, proof.field)
                           for value in proof.diagonal],
        identity_proof_hash=proof.identity_proof_hash,
        proof_dag=certificate_dag_json(dag),
        certificate_hash=hash,
    )
end

function entries_dict(matrix::SparseSymmetricRationalMatrix)
    map = Dict{Tuple{Int, Int}, Rational{BigInt}}()
    for (i, j, value) in matrix.entries
        value == 0 && continue
        map[(i, j)] = value
    end
    return map
end

function _matrix_inner(a::SparseSymmetricRationalMatrix,
                       b::SparseSymmetricRationalMatrix)
    a.n == b.n || throw(DimensionMismatch("matrix inner dimensions differ"))
    left = entries_dict(a)
    right = entries_dict(b)
    result = Rational{BigInt}(0)
    for (key, value) in left
        result += value * get(right, key, 0//1)
    end
    return result
end

function _matrix_linear_combination(matrices::AbstractVector{SparseSymmetricRationalMatrix},
                                    coefficients::AbstractVector)
    length(matrices) == length(coefficients) ||
        throw(DimensionMismatch("matrix coefficient count mismatch"))
    isempty(matrices) && throw(ArgumentError("matrix linear combination needs at least one matrix"))
    accum = Dict{Tuple{Int, Int}, Rational{BigInt}}()
    n = matrices[1].n
    for (matrix, coefficient) in zip(matrices, coefficients)
        matrix.n == n || throw(DimensionMismatch("matrix dimensions differ"))
        coeff = _to_big_rational(coefficient, "linear_combination.coefficient")
        _accumulate_entries!(accum, matrix.entries, coeff)
    end
    return _sparse_matrix_from_accumulator(n, accum)
end

function _matrix_subtract(a::SparseSymmetricRationalMatrix,
                          b::SparseSymmetricRationalMatrix)
    a.n == b.n || throw(DimensionMismatch("matrix dimensions differ"))
    accum = Dict{Tuple{Int, Int}, Rational{BigInt}}()
    _accumulate_entries!(accum, a.entries, 1//1)
    _accumulate_entries!(accum, b.entries, -1//1)
    return _sparse_matrix_from_accumulator(a.n, accum)
end

function _matrix_equal(a::SparseSymmetricRationalMatrix,
                       b::SparseSymmetricRationalMatrix)
    return a.n == b.n && entries_dict(a) == entries_dict(b)
end

function _identity_matrix(n::Int)
    return SparseSymmetricRationalMatrix(n, [(i, i, 1//1) for i in 1:n])
end

function _matrix_multiply(a::SparseSymmetricRationalMatrix,
                          b::SparseSymmetricRationalMatrix)
    a.n == b.n || throw(DimensionMismatch("matrix dimensions differ"))
    left = entries_dict(a)
    right = entries_dict(b)
    accum = Dict{Tuple{Int, Int}, Rational{BigInt}}()
    for i in 1:a.n, j in i:a.n
        value = Rational{BigInt}(0)
        for k in 1:a.n
            value += get(left, (min(i, k), max(i, k)), 0//1) *
                     get(right, (min(k, j), max(k, j)), 0//1)
        end
        value != 0//1 && (accum[(i, j)] = value)
    end
    return _sparse_matrix_from_accumulator(a.n, accum)
end

function _zero_matrix(n::Int)
    return SparseSymmetricRationalMatrix(n, Tuple{Int, Int, Rational{BigInt}}[])
end

function _verify_projector_semantics(projectors::AbstractVector{SparseSymmetricRationalMatrix},
                                     n::Int)
    isempty(projectors) && return "missing projector matrices"
    all(matrix -> matrix.n == n, projectors) ||
        return "projector matrix dimension mismatch"
    for (i, projector) in enumerate(projectors)
        _matrix_equal(_matrix_multiply(projector, projector), projector) ||
            return "projector $i is not idempotent"
    end
    zero = _zero_matrix(n)
    for i in 1:length(projectors), j in (i + 1):length(projectors)
        _matrix_equal(_matrix_multiply(projectors[i], projectors[j]), zero) ||
            return "projectors $i and $j are not orthogonal"
    end
    completeness = _sum_sparse_matrices(projectors, n)
    _matrix_equal(completeness, _identity_matrix(n)) ||
        return "projectors do not sum to identity"
    return nothing
end

function _conic_primal_slack(problem::ExactConicProblem,
                             block::ConicAffineBlock,
                             x::AbstractVector)
    return _matrix_subtract(block.B, _matrix_linear_combination(block.A, x))
end

function _conic_dual_adjoint(problem::ExactConicProblem,
                             dual_variables::AbstractVector{SparseSymmetricRationalMatrix})
    length(dual_variables) == length(problem.blocks) ||
        throw(DimensionMismatch("dual variable block count mismatch"))
    result = fill(Rational{BigInt}(0), length(problem.variables))
    for (block, y) in zip(problem.blocks, dual_variables)
        y.n == block.B.n || throw(DimensionMismatch("dual variable dimension mismatch for $(block.id)"))
        for j in eachindex(problem.variables)
            result[j] += _matrix_inner(block.A[j], y)
        end
    end
    return result
end

function _conic_dual_objective(problem::ExactConicProblem,
                               dual_variables::AbstractVector{SparseSymmetricRationalMatrix})
    length(dual_variables) == length(problem.blocks) ||
        throw(DimensionMismatch("dual variable block count mismatch"))
    result = Rational{BigInt}(0)
    for (block, y) in zip(problem.blocks, dual_variables)
        result += _matrix_inner(block.B, y)
    end
    return result
end

function _conic_primal_objective(problem::ExactConicProblem,
                                 primal_vector::AbstractVector)
    length(primal_vector) == length(problem.variables) ||
        throw(DimensionMismatch("primal vector length mismatch"))
    result = Rational{BigInt}(0)
    for (coefficient, value) in zip(problem.objective, primal_vector)
        result += coefficient * _to_big_rational(value, "primal_vector")
    end
    return result
end

function _conic_primal_slacks(problem::ExactConicProblem,
                              primal_vector::AbstractVector)
    return SparseSymmetricRationalMatrix[
        _conic_primal_slack(problem, block, primal_vector)
        for block in problem.blocks
    ]
end

function _conic_gap(problem::ExactConicProblem,
                    primal_objective::Rational{BigInt},
                    dual_objective::Rational{BigInt})
    return problem.sense === :max ? dual_objective - primal_objective :
           primal_objective - dual_objective
end

function _matrix_diagonal_psd_proof(matrix::SparseSymmetricRationalMatrix)
    entries = entries_dict(matrix)
    factor = [[i == j ? 1//1 : 0//1 for j in 1:matrix.n] for i in 1:matrix.n]
    diagonal = Rational{BigInt}[]
    for i in 1:matrix.n
        for j in 1:matrix.n
            i == j && continue
            get(entries, (min(i, j), max(i, j)), 0//1) == 0//1 ||
                throw(ArgumentError("automatic PSD proof only supports diagonal matrices"))
        end
        value = get(entries, (i, i), 0//1)
        value >= 0//1 ||
            throw(ArgumentError("automatic PSD proof requires nonnegative diagonal entries"))
        push!(diagonal, value)
    end
    return ExactLowRankPSDProof(matrix, factor, diagonal)
end

function Base.getindex(matrix::SparseSymmetricRationalMatrix, i::Integer, j::Integer)
    1 <= i <= matrix.n || throw(BoundsError(matrix, (i, j)))
    1 <= j <= matrix.n || throw(BoundsError(matrix, (i, j)))
    key = Int(i) <= Int(j) ? (Int(i), Int(j)) : (Int(j), Int(i))
    return get(entries_dict(matrix), key, Rational{BigInt}(0))
end

function substitute(problem::SparseAffineLMI, values::AbstractVector)
    length(values) == length(problem.variables) ||
        throw(DimensionMismatch("substitution has length $(length(values)); expected $(length(problem.variables))"))
    assignments = [_to_big_rational(value, "x[$i]")
                   for (i, value) in enumerate(values)]
    accum = Dict{Tuple{Int, Int}, Rational{BigInt}}()
    _accumulate_entries!(accum, problem.A0.entries, 1)
    for (coefficient, matrix) in zip(assignments, problem.A)
        _accumulate_entries!(accum, matrix.entries, coefficient)
    end
    return _sparse_matrix_from_accumulator(problem.A0.n, accum)
end

function verify_low_rank_psd(matrix::SparseSymmetricRationalMatrix,
                             proof::ExactLowRankPSDProof)
    try
        matrix.hash == sparse_matrix_hash(matrix) ||
            return _reject(:D, :psd_factor, :hash, :matrix_hash,
                           "sparse matrix hash mismatch"; problem_hash=matrix.hash)
        matrix.hash == proof.matrix_hash ||
            return _reject(:D, :psd_factor, :hash, :matrix_hash,
                           "proof matrix hash does not match matrix";
                           problem_hash=matrix.hash,
                           certificate_hash=proof.matrix_hash)
        proof.identity_proof_hash == low_rank_identity_hash(proof) ||
            return _reject(:D, :psd_factor, :identity_replay,
                           :identity_proof_hash,
                           "low-rank identity proof hash mismatch";
                           problem_hash=matrix.hash,
                           certificate_hash=proof.identity_proof_hash)
        proof.field === :QQ ||
            return _reject(:D, :psd_factor, :field, :field,
                           "only rational low-rank PSD proof replay is implemented in this kernel slice";
                           problem_hash=matrix.hash)
        length(proof.factor) == matrix.n ||
            return _reject(:D, :psd_factor, :dimension, :factor_rows,
                           "factor row count does not match matrix dimension";
                           problem_hash=matrix.hash)
        rank = length(proof.diagonal)
        for (i, row) in enumerate(proof.factor)
            length(row) == rank ||
                return _reject(:D, :psd_factor, :dimension, :factor_columns,
                               "factor row $i has length $(length(row)); expected $rank";
                               problem_hash=matrix.hash)
        end
        for (i, value) in enumerate(proof.diagonal)
            value >= 0 ||
                return _reject(:D, :psd_factor, :sign, Symbol("D", i),
                               "diagonal entry $i is negative";
                               problem_hash=matrix.hash,
                               details=Dict{Symbol, Any}(:value => rational_string(value)))
        end
        expected = _low_rank_product_entries(proof.factor, proof.diagonal)
        actual = entries_dict(matrix)
        expected == actual ||
            return _reject(:D, :psd_factor, :identity_replay, :matrix_identity,
                           "exact low-rank matrix identity mismatch";
                           problem_hash=matrix.hash,
                           details=_first_sparse_difference(actual, expected))
        return _accept(:D, :psd_factor, :identity_replay, :matrix_identity;
                       problem_hash=matrix.hash,
                       certificate_hash=proof.identity_proof_hash)
    catch err
        return _reject(:D, :psd_factor, :exception, :low_rank_replay,
                       sprint(showerror, err); problem_hash=matrix.hash)
    end
end

function verify_algebraic_low_rank_psd(matrix::SparseSymmetricRationalMatrix,
                                       proof::ExactAlgebraicLowRankPSDProof)
    try
        matrix.hash == sparse_matrix_hash(matrix) ||
            return _reject(:D, :psd_factor_algebraic, :hash,
                           :matrix_hash,
                           "sparse matrix hash mismatch";
                           problem_hash=matrix.hash)
        matrix.hash == proof.matrix_hash ||
            return _reject(:D, :psd_factor_algebraic, :hash,
                           :matrix_hash,
                           "algebraic proof matrix hash does not match matrix";
                           problem_hash=matrix.hash,
                           certificate_hash=proof.identity_proof_hash)
        proof.field.field_hash == algebraic_field_certificate_hash(proof.field) ||
            return _reject(:D, :psd_factor_algebraic, :field,
                           :field_hash,
                           "algebraic PSD field hash mismatch";
                           problem_hash=matrix.hash,
                           certificate_hash=proof.identity_proof_hash)
        proof.identity_proof_hash == algebraic_low_rank_identity_hash(proof) ||
            return _reject(:D, :psd_factor_algebraic,
                           :identity_replay,
                           :identity_proof_hash,
                           "algebraic low-rank identity proof hash mismatch";
                           problem_hash=matrix.hash,
                           certificate_hash=proof.identity_proof_hash)
        length(proof.factor) == matrix.n ||
            return _reject(:D, :psd_factor_algebraic, :dimension,
                           :factor_rows,
                           "algebraic factor row count does not match matrix dimension";
                           problem_hash=matrix.hash,
                           certificate_hash=proof.identity_proof_hash)
        rank = length(proof.diagonal)
        for (i, row) in enumerate(proof.factor)
            length(row) == rank ||
                return _reject(:D, :psd_factor_algebraic, :dimension,
                               :factor_columns,
                               "algebraic factor row $i has wrong width";
                               problem_hash=matrix.hash,
                               certificate_hash=proof.identity_proof_hash)
        end
        for (i, diagonal) in enumerate(proof.diagonal)
            _algebraic_sign_positive(diagonal, proof.field) ||
                return _reject(:D, :psd_factor_algebraic, :sign,
                               Symbol("D", i),
                               "algebraic diagonal sign proof is not nonnegative";
                               problem_hash=matrix.hash,
                               certificate_hash=proof.identity_proof_hash)
        end
        expected = _algebraic_low_rank_product_entries(proof)
        actual = entries_dict(matrix)
        for key in union(keys(expected), keys(actual))
            expected_value = get(expected, key,
                                 fill(0//1,
                                      length(proof.field.minimal_polynomial) - 1))
            actual_value = _algebraic_rational_element(get(actual, key, 0//1),
                                                       proof.field)
            expected_value == actual_value ||
                return _reject(:D, :psd_factor_algebraic,
                               :identity_replay,
                               :matrix_identity,
                               "algebraic low-rank matrix identity mismatch";
                               problem_hash=matrix.hash,
                               certificate_hash=proof.identity_proof_hash,
                               details=Dict{Symbol, Any}(:entry => [key[1], key[2]],
                                                         :expected => rational_string.(expected_value),
                                                         :actual => rational_string.(actual_value)))
        end
        return _accept(:D, :psd_factor_algebraic, :identity_replay,
                       :matrix_identity;
                       problem_hash=matrix.hash,
                       certificate_hash=proof.identity_proof_hash)
    catch err
        return _reject(:D, :psd_factor_algebraic, :exception,
                       :algebraic_low_rank_replay,
                       sprint(showerror, err);
                       problem_hash=matrix.hash,
                       certificate_hash=proof.identity_proof_hash)
    end
end

function _algebraic_low_rank_product_entries(proof::ExactAlgebraicLowRankPSDProof)
    n = length(proof.factor)
    rank = length(proof.diagonal)
    result = Dict{Tuple{Int, Int}, Vector{Rational{BigInt}}}()
    zero = fill(0//1, length(proof.field.minimal_polynomial) - 1)
    for i in 1:n, j in i:n
        value = copy(zero)
        for k in 1:rank
            partial = _algebraic_mul(proof.factor[i][k].coefficients,
                                     proof.diagonal[k].coefficients,
                                     proof.field.minimal_polynomial)
            partial = _algebraic_mul(partial,
                                     proof.factor[j][k].coefficients,
                                     proof.field.minimal_polynomial)
            value = _algebraic_add(value, partial,
                                   proof.field.minimal_polynomial)
        end
        all(==(0//1), value) || (result[(i, j)] = value)
    end
    return result
end

function _algebraic_rational_element(value::Rational,
                                     field::AlgebraicFieldCertificate)
    degree = length(field.minimal_polynomial) - 1
    return vcat([Rational{BigInt}(value)], fill(0//1, degree - 1))
end

function _algebraic_sign_positive(element::AlgebraicElement,
                                  field::AlgebraicFieldCertificate)
    reduced = _algebraic_reduce(element.coefficients,
                                field.minimal_polynomial)
    all(==(0//1), reduced) && return true
    root_count = _sturm_root_count(reduced,
                                   field.isolating_interval[1],
                                   field.isolating_interval[2])
    root_count == 0 || return false
    return _poly_eval_sign(reduced, field.isolating_interval[1]) > 0
end

function verify_chordal_psd(matrix::SparseSymmetricRationalMatrix,
                            proof::ChordalPSDProof)
    try
        proof.theorem_tag === :positive_semidefinite_completion_for_chordal_graph ||
            return _reject(:D, :chordal_psd, :theorem, :theorem_tag,
                           "unsupported chordal PSD theorem tag";
                           problem_hash=matrix.hash,
                           certificate_hash=proof.proof_hash)
        matrix.hash == proof.matrix_hash ||
            return _reject(:D, :chordal_psd, :hash, :matrix_hash,
                           "chordal proof matrix hash mismatch";
                           problem_hash=matrix.hash,
                           certificate_hash=proof.proof_hash)
        proof.structure.graph_hash == chordal_structure_hash(proof.structure) ||
            return _reject(:B, :chordal_psd, :hash, :graph_hash,
                           "chordal graph hash mismatch";
                           problem_hash=matrix.hash,
                           certificate_hash=proof.proof_hash)
        proof.proof_hash == chordal_proof_hash(proof) ||
            return _reject(:D, :chordal_psd, :hash, :proof_hash,
                           "chordal proof hash mismatch";
                           problem_hash=matrix.hash,
                           certificate_hash=proof.proof_hash)
        clique_count = length(proof.structure.cliques)
        seen = Set{Int}()
        clique_by_index = Dict{Int, CliquePSDProof}()
        for clique_proof in proof.clique_proofs
            1 <= clique_proof.clique_index <= clique_count ||
                return _reject(:B, :chordal_psd, :clique_replay,
                               Symbol("clique_", clique_proof.clique_index),
                               "unknown clique index";
                               problem_hash=matrix.hash,
                               certificate_hash=proof.proof_hash,
                               clique_id=clique_proof.id)
            clique_proof.clique_index in seen &&
                return _reject(:B, :chordal_psd, :clique_replay,
                               clique_proof.id,
                               "duplicate clique proof index";
                               problem_hash=matrix.hash,
                               certificate_hash=proof.proof_hash,
                               clique_id=clique_proof.id)
            push!(seen, clique_proof.clique_index)
            expected_vertices = proof.structure.cliques[clique_proof.clique_index]
            clique_proof.vertices == expected_vertices ||
                return _reject(:B, :chordal_psd, :clique_replay,
                               clique_proof.id,
                               "clique vertices do not match chordal structure";
                               problem_hash=matrix.hash,
                               certificate_hash=proof.proof_hash,
                               clique_id=clique_proof.id)
            local_result = verify_low_rank_psd(clique_proof.matrix,
                                               clique_proof.psd_proof)
            local_result.accepted ||
                return _with_location(local_result;
                                      family=:chordal_psd,
                                      clique_id=clique_proof.id,
                                      certificate_hash=proof.proof_hash)
            clique_by_index[clique_proof.clique_index] = clique_proof
        end
        length(seen) == clique_count ||
            return _reject(:B, :chordal_psd, :clique_replay, :clique_count,
                           "not every chordal clique has a PSD proof";
                           problem_hash=matrix.hash,
                           certificate_hash=proof.proof_hash)
        coverage = _verify_clique_entry_coverage(matrix, proof, clique_by_index)
        coverage.accepted || return coverage
        for separator in proof.separator_proofs
            1 <= separator.left_clique <= clique_count &&
                1 <= separator.right_clique <= clique_count ||
                return _reject(:B, :chordal_psd, :separator_replay,
                               separator.id,
                               "separator references an unknown clique index";
                               problem_hash=matrix.hash,
                               certificate_hash=proof.proof_hash,
                               separator_id=separator.id)
            left = clique_by_index[separator.left_clique]
            right = clique_by_index[separator.right_clique]
            all(vertex -> vertex in left.vertices && vertex in right.vertices,
                separator.vertices) ||
                return _reject(:B, :chordal_psd, :separator_replay,
                               separator.id,
                               "separator vertices are not contained in both cliques";
                               problem_hash=matrix.hash,
                               certificate_hash=proof.proof_hash,
                               separator_id=separator.id)
            value_payload = _separator_value_payload(separator.vertices,
                                                     left.matrix,
                                                     right.matrix)
            separator.value_hash == _sha256_payload(value_payload) ||
                return _reject(:B, :chordal_psd, :separator_replay,
                               separator.id,
                               "separator value hash mismatch";
                               problem_hash=matrix.hash,
                               certificate_hash=proof.proof_hash,
                               separator_id=separator.id)
            for a in eachindex(separator.vertices), b in a:length(separator.vertices)
                u = separator.vertices[a]
                v = separator.vertices[b]
                left_value = _clique_original_value(left, u, v)
                right_value = _clique_original_value(right, u, v)
                left_value == right_value ||
                    return _reject(:B, :chordal_psd, :separator_replay,
                                   separator.id,
                                   "separator entry mismatch";
                                   problem_hash=matrix.hash,
                                   certificate_hash=proof.proof_hash,
                                   separator_id=separator.id,
                                   details=Dict{Symbol, Any}(:entry => [u, v],
                                                             :left => rational_string(left_value),
                                                             :right => rational_string(right_value)))
            end
        end
        return _accept(:D, :chordal_psd, :chordal_replay, :chordal_psd;
                       problem_hash=matrix.hash,
                       certificate_hash=proof.proof_hash)
    catch err
        return _reject(:D, :chordal_psd, :exception, :chordal_replay,
                       sprint(showerror, err);
                       problem_hash=matrix.hash,
                       certificate_hash=proof.proof_hash)
    end
end

function make_block_native_algebraic_certificate(incidence::BlockNativeIncidenceSystem;
                                                 active_block_proofs=Dict{Int, BlockNativeActiveBlockProof}(),
                                                 inactive_psd_proofs=Dict{Int, BlockNativeInactivePSDProof}(),
                                                 block_solution_hashes=nothing,
                                                 inactive_psd_hashes=nothing)
    isnothing(block_solution_hashes) ||
        throw(ArgumentError("block_solution_hashes are not accepted as trusted block-native algebraic evidence; provide active_block_proofs"))
    isnothing(inactive_psd_hashes) ||
        throw(ArgumentError("inactive_psd_hashes are not accepted as trusted block-native PSD evidence; provide inactive_psd_proofs"))
    active_proofs = Dict{Int, BlockNativeActiveBlockProof}(Int(key) => value
                                                           for (key, value) in active_block_proofs)
    inactive_proofs = Dict{Int, BlockNativeInactivePSDProof}(Int(key) => value
                                                             for (key, value) in inactive_psd_proofs)
    cert = BlockNativeAlgebraicCertificate(incidence.problem_hash,
                                           incidence,
                                           active_proofs,
                                           inactive_proofs,
                                           "")
    return BlockNativeAlgebraicCertificate(incidence.problem_hash,
                                           incidence,
                                           active_proofs,
                                           inactive_proofs,
                                           block_native_algebraic_certificate_hash(cert))
end

function verify_block_native_algebraic_certificate(cert::BlockNativeAlgebraicCertificate;
                                                   expected_problem_hash=nothing)
    try
        isnothing(expected_problem_hash) || cert.problem_hash == expected_problem_hash ||
            return _reject(:C, :block_native_algebraic, :hash,
                           :problem_hash,
                           "block-native certificate problem hash mismatch";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        cert.incidence.problem_hash == cert.problem_hash ||
            return _reject(:C, :block_native_algebraic, :incidence_replay,
                           :incidence_problem_hash,
                           "incidence problem hash does not match certificate";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        cert.incidence.system_hash == block_native_incidence_system_hash(cert.incidence) ||
            return _reject(:C, :block_native_algebraic, :incidence_replay,
                           :incidence_system_hash,
                           "block-native incidence system hash mismatch";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        cert.certificate_hash == block_native_algebraic_certificate_hash(cert) ||
            return _reject(:C, :block_native_algebraic, :hash,
                           :certificate_hash,
                           "block-native algebraic certificate hash mismatch";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        seen = Set{Int}()
        for block in cert.incidence.blocks
            block.block_index in seen &&
                return _reject(:C, :block_native_algebraic, :incidence_replay,
                               Symbol("block_", block.block_index),
                               "duplicate block incidence entry";
                               problem_hash=cert.problem_hash,
                               certificate_hash=cert.certificate_hash,
                               block_id=Symbol("block_", block.block_index))
            push!(seen, block.block_index)
            if block.active
                haskey(cert.active_block_proofs, block.block_index) ||
                    return _reject(:C, :block_native_algebraic, :candidate_replay,
                                   Symbol("block_", block.block_index),
                                   "active block is missing algebraic solution proof";
                                   problem_hash=cert.problem_hash,
                                   certificate_hash=cert.certificate_hash,
                                   block_id=Symbol("block_", block.block_index),
                                   details=Dict{Symbol, Any}(:rank => block.rank,
                                                             :kernel_dimension => block.kernel_dimension,
                                                             :slicing_strategy => String(block.slicing_strategy)))
                isempty(block.variable_names) &&
                    return _reject(:C, :block_native_algebraic,
                                   :incidence_replay,
                                   Symbol("block_", block.block_index),
                                   "active block has no kernel variables";
                                   problem_hash=cert.problem_hash,
                                   certificate_hash=cert.certificate_hash,
                                   block_id=Symbol("block_", block.block_index))
                active_report = _verify_block_native_active_proof(block,
                                                                  cert.active_block_proofs[block.block_index],
                                                                  cert)
                active_report.accepted || return active_report
            else
                haskey(cert.inactive_psd_proofs, block.block_index) ||
                    return _reject(:C, :block_native_algebraic, :psd_margin,
                                   Symbol("block_", block.block_index),
                                   "inactive block is missing exact PSD margin proof";
                                   problem_hash=cert.problem_hash,
                                   certificate_hash=cert.certificate_hash,
                                   block_id=Symbol("block_", block.block_index),
                                   details=Dict{Symbol, Any}(:rank => block.rank,
                                                             :kernel_dimension => block.kernel_dimension,
                                                             :slicing_strategy => String(block.slicing_strategy)))
                inactive_report = _verify_block_native_inactive_proof(block,
                                                                      cert.inactive_psd_proofs[block.block_index],
                                                                      cert)
                inactive_report.accepted || return inactive_report
            end
        end
        dag_report = verify_proof_dag(block_native_algebraic_certificate_dag(cert))
        dag_report.accepted || return dag_report
        return _accept(:C, :block_native_algebraic, :incidence_replay,
                       :block_native_incidence;
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash)
    catch err
        return _reject(:C, :block_native_algebraic, :exception,
                       :block_native_incidence,
                       sprint(showerror, err);
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash)
    end
end

function _verify_block_native_active_proof(block::BlockNativeIncidenceBlock,
                                           proof::BlockNativeActiveBlockProof,
                                           cert::BlockNativeAlgebraicCertificate)
    proof.block_index == block.block_index ||
        return _reject(:C, :block_native_algebraic, :candidate_replay,
                       Symbol("block_", block.block_index),
                       "active proof block index does not match incidence block";
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash,
                       block_id=Symbol("block_", block.block_index))
    proof.block_hash == block.block_hash ||
        return _reject(:C, :block_native_algebraic, :hash,
                       Symbol("block_", block.block_index),
                       "active proof block hash does not match incidence block";
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash,
                       block_id=Symbol("block_", block.block_index))
    proof.field.field_hash == algebraic_field_certificate_hash(proof.field) ||
        return _reject(:C, :block_native_algebraic, :field,
                       Symbol("block_", block.block_index),
                       "active proof field hash mismatch";
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash,
                       block_id=Symbol("block_", block.block_index))
    proof.proof_hash == block_native_active_block_proof_hash(proof) ||
        return _reject(:C, :block_native_algebraic, :hash,
                       Symbol("block_", block.block_index),
                       "active block proof hash mismatch";
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash,
                       block_id=Symbol("block_", block.block_index))
    for variable in block.variable_names
        haskey(proof.values, variable) ||
            return _reject(:C, :block_native_algebraic, :candidate_replay,
                           variable,
                           "active block algebraic solution is missing a kernel variable";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash,
                           block_id=Symbol("block_", block.block_index),
                           details=Dict{Symbol, Any}(:variable => String(variable)))
    end
    isempty(proof.incidence_equations) &&
        return _reject(:C, :block_native_algebraic, :candidate_replay,
                       Symbol("block_", block.block_index),
                       "active block has no incidence equations to replay";
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash,
                       block_id=Symbol("block_", block.block_index))
    for equation in proof.incidence_equations
        equation_report = _verify_algebraic_equation(equation, proof)
        equation_report.accepted ||
            return _with_location(equation_report;
                                  family=:block_native_algebraic,
                                  block_id=Symbol("block_", block.block_index),
                                  certificate_hash=cert.certificate_hash)
    end
    for equation in proof.gauge_equations
        equation_report = _verify_algebraic_equation(equation, proof)
        equation_report.accepted ||
            return _with_location(equation_report;
                                  family=:block_native_algebraic,
                                  block_id=Symbol("block_", block.block_index),
                                  certificate_hash=cert.certificate_hash)
    end
    return _accept(:C, :block_native_algebraic, :candidate_replay,
                   Symbol("block_", block.block_index);
                   problem_hash=cert.problem_hash,
                   certificate_hash=cert.certificate_hash,
                   block_id=Symbol("block_", block.block_index),
                   details=Dict{Symbol, Any}(:rank => block.rank,
                                             :kernel_dimension => block.kernel_dimension,
                                             :slicing_strategy => String(block.slicing_strategy)))
end

function _verify_block_native_inactive_proof(block::BlockNativeIncidenceBlock,
                                             proof::BlockNativeInactivePSDProof,
                                             cert::BlockNativeAlgebraicCertificate)
    proof.block_index == block.block_index ||
        return _reject(:C, :block_native_algebraic, :psd_margin,
                       Symbol("block_", block.block_index),
                       "inactive PSD proof block index does not match incidence block";
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash,
                       block_id=Symbol("block_", block.block_index))
    proof.block_hash == block.block_hash ||
        return _reject(:C, :block_native_algebraic, :hash,
                       Symbol("block_", block.block_index),
                       "inactive PSD proof block hash does not match incidence block";
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash,
                       block_id=Symbol("block_", block.block_index))
    proof.proof_hash == block_native_inactive_psd_proof_hash(proof) ||
        return _reject(:C, :block_native_algebraic, :hash,
                       Symbol("block_", block.block_index),
                       "inactive PSD proof hash mismatch";
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash,
                       block_id=Symbol("block_", block.block_index))
    psd_report = verify_low_rank_psd(proof.margin_matrix, proof.psd_proof)
    psd_report.accepted ||
        return _with_location(psd_report;
                              family=:block_native_algebraic,
                              block_id=Symbol("block_", block.block_index),
                              certificate_hash=cert.certificate_hash)
    return _accept(:C, :block_native_algebraic, :psd_margin,
                   Symbol("block_", block.block_index);
                   problem_hash=cert.problem_hash,
                   certificate_hash=cert.certificate_hash,
                   block_id=Symbol("block_", block.block_index),
                   details=Dict{Symbol, Any}(:rank => block.rank,
                                             :kernel_dimension => block.kernel_dimension,
                                             :slicing_strategy => String(block.slicing_strategy)))
end

function _verify_algebraic_equation(equation::AlgebraicEquationObligation,
                                    proof::BlockNativeActiveBlockProof)
    field = proof.field
    accum = copy(equation.constant.coefficients)
    accum = _algebraic_reduce(accum, field.minimal_polynomial)
    for term in equation.terms
        haskey(proof.values, term.variable) ||
            return _reject(:C, :block_native_algebraic, :candidate_replay,
                           equation.id,
                           "equation references a missing algebraic variable";
                           details=Dict{Symbol, Any}(:variable => String(term.variable)))
        value = proof.values[term.variable]
        product = _algebraic_mul(term.coefficient.coefficients,
                                 value.coefficients,
                                 field.minimal_polynomial)
        accum = _algebraic_add(accum, product, field.minimal_polynomial)
    end
    iszero = all(==(0//1), accum)
    iszero ||
        return _reject(:C, :block_native_algebraic, :candidate_replay,
                       equation.id,
                       "algebraic incidence equation does not reduce to zero";
                       details=Dict{Symbol, Any}(:residual => rational_string.(accum)))
    return _accept(:C, :block_native_algebraic, :candidate_replay,
                   equation.id)
end

function make_primal_dual_optimality_certificate(problem_hash::AbstractString,
                                                 primal::PrimalFeasibilityCertificate,
                                                 dual::DualFeasibilityCertificate;
                                                 gap=primal.objective_value - dual.objective_value)
    gap_value = _to_big_rational(gap, "gap")
    primal_legacy_hash = _sha256_payload((; role="legacy_primal_without_problem",
                                           payload=primal_feasibility_json(primal)))
    dual_legacy_hash = _sha256_payload((; role="legacy_dual_without_problem",
                                         payload=dual_feasibility_json(dual)))
    nodes = ProofNode[
        ProofNode(:primal_affine, :exact_equality, String[],
                  primal_legacy_hash,
                  :verify_primal_affine, :accepted;
                  typed_payload=Dict(:primal_hash => primal_legacy_hash,
                                     :primal => primal_feasibility_json(primal)),
                  obligation_id=:primal_affine_map),
        ProofNode(:dual_affine, :exact_equality, String[],
                  dual_legacy_hash,
                  :verify_dual_affine, :accepted;
                  typed_payload=Dict(:dual_hash => dual_legacy_hash,
                                     :dual => dual_feasibility_json(dual)),
                  obligation_id=:dual_affine_map),
        ProofNode(:objective_gap, :exact_equality,
                  [primal_legacy_hash, dual_legacy_hash],
                  _sha256_payload((; gap=rational_string(gap_value))),
                  :verify_exact_gap, :accepted;
                  typed_payload=Dict(:primal_objective => rational_string(primal.objective_value),
                                     :dual_objective => rational_string(dual.objective_value),
                                     :gap => rational_string(gap_value)),
                  obligation_id=:exact_gap),
    ]
    dag = CertificateDAG(:primal_dual_optimality, nodes, "",
                         CERTSDP3_SCHEMA_VERSION)
    cert0 = PrimalDualOptimalityCertificate(String(problem_hash), primal, dual,
                                            gap_value, "", dag)
    return PrimalDualOptimalityCertificate(String(problem_hash), primal, dual,
                                           gap_value,
                                          primal_dual_optimality_hash(cert0),
                                          dag)
end

function make_primal_dual_optimality_certificate(problem::ExactConicProblem,
                                                 primal_vector,
                                                 dual_variables::AbstractVector{SparseSymmetricRationalMatrix};
                                                 primal_cone_proofs::Union{Nothing, AbstractVector{ExactLowRankPSDProof}}=nothing,
                                                 dual_cone_proofs::Union{Nothing, AbstractVector{ExactLowRankPSDProof}}=nothing,
                                                 gap=nothing)
    x = [_to_big_rational(value, "primal_vector[$i]")
         for (i, value) in enumerate(primal_vector)]
    length(x) == length(problem.variables) ||
        throw(DimensionMismatch("primal vector length does not match problem variables"))
    ys = SparseSymmetricRationalMatrix[dual_variables...]
    length(ys) == length(problem.blocks) ||
        throw(DimensionMismatch("dual variable count does not match problem blocks"))
    primal_slacks = _conic_primal_slacks(problem, x)
    dual_adj = _conic_dual_adjoint(problem, ys)
    dual_adj == problem.objective ||
        throw(ArgumentError("dual adjoint replay requires A*(y) == c for exact optimality"))
    primal_proofs = isnothing(primal_cone_proofs) ?
                    [_matrix_diagonal_psd_proof(matrix) for matrix in primal_slacks] :
                    ExactLowRankPSDProof[primal_cone_proofs...]
    dual_proofs = isnothing(dual_cone_proofs) ?
                  [_matrix_diagonal_psd_proof(matrix) for matrix in ys] :
                  ExactLowRankPSDProof[dual_cone_proofs...]
    length(primal_proofs) == length(primal_slacks) ||
        throw(ArgumentError("primal cone proof count mismatch"))
    length(dual_proofs) == length(ys) ||
        throw(ArgumentError("dual cone proof count mismatch"))
    primal_objective = _conic_primal_objective(problem, x)
    dual_objective = _conic_dual_objective(problem, ys)
    gap_value = isnothing(gap) ? _conic_gap(problem, primal_objective, dual_objective) :
                _to_big_rational(gap, "gap")
    # Legacy affine arrays stay empty on problem-backed certificates; the replay
    # obligation is the exact conic problem data above.
    primal = PrimalFeasibilityCertificate(problem.problem_hash, problem, x,
                                          Rational{BigInt}[],
                                          Rational{BigInt}[],
                                          primal_slacks, primal_proofs,
                                          primal_objective)
    dual = DualFeasibilityCertificate(problem.problem_hash, problem, ys,
                                      Rational{BigInt}[],
                                      Rational{BigInt}[],
                                      ys, dual_proofs,
                                      dual_objective)
    problem_payload = exact_conic_problem_json(problem)
    primal_payload = primal_feasibility_json(primal)
    dual_payload = dual_feasibility_json(dual)
    primal_hash = _sha256_payload(primal_payload)
    dual_hash = _sha256_payload(dual_payload)
    nodes = ProofNode[
        ProofNode(:primal_affine, :exact_affine_replay, String[],
                  primal_hash,
                  :verify_primal_affine, :accepted;
                  typed_payload=Dict(:problem => problem_payload,
                                     :primal_hash => primal_hash,
                                     :primal => primal_payload),
                  obligation_id=:primal_affine_map),
        ProofNode(:dual_affine, :exact_affine_adjoint_replay, String[],
                  dual_hash,
                  :verify_dual_affine, :accepted;
                  typed_payload=Dict(:problem => problem_payload,
                                     :dual_hash => dual_hash,
                                     :dual => dual_payload),
                  obligation_id=:dual_affine_map),
        ProofNode(:objective_gap, :exact_equality,
                  [primal_hash, dual_hash],
                  _sha256_payload((; gap=rational_string(gap_value))),
                  :verify_exact_gap, :accepted;
                  typed_payload=Dict(:problem => problem_payload,
                                     :primal_vector => rational_string.(x),
                                     :dual_variables => [sparse_matrix_json(matrix) for matrix in ys],
                                     :primal_objective => rational_string(primal_objective),
                                     :dual_objective => rational_string(dual_objective),
                                     :gap => rational_string(gap_value)),
                  obligation_id=:exact_gap),
    ]
    dag = CertificateDAG(:primal_dual_optimality, nodes, "",
                         CERTSDP3_SCHEMA_VERSION)
    cert0 = PrimalDualOptimalityCertificate(problem.problem_hash, primal, dual,
                                            gap_value, "", dag)
    return PrimalDualOptimalityCertificate(problem.problem_hash, primal, dual,
                                           gap_value,
                                           primal_dual_optimality_hash(cert0),
                                           dag)
end

function make_farkas_infeasibility_certificate(problem_hash::AbstractString,
                                               lhs,
                                               rhs,
                                               cone_proofs::AbstractVector{ExactLowRankPSDProof},
                                               contradiction_lhs,
                                               contradiction_rhs)
    lhs_values = [_to_big_rational(value, "multiplier_identity_lhs[$i]")
                  for (i, value) in enumerate(lhs)]
    rhs_values = [_to_big_rational(value, "multiplier_identity_rhs[$i]")
                  for (i, value) in enumerate(rhs)]
    left = _to_big_rational(contradiction_lhs, "contradiction_lhs")
    right = _to_big_rational(contradiction_rhs, "contradiction_rhs")
    nodes = ProofNode[
        ProofNode(:farkas_identity, :exact_equality, String[],
                  _sha256_payload((; lhs=rational_string.(lhs_values),
                                     rhs=rational_string.(rhs_values))),
                  :verify_farkas_identity, :accepted;
                  typed_payload=Dict(:lhs => rational_string.(lhs_values),
                                     :rhs => rational_string.(rhs_values)),
                  obligation_id=:farkas_dual_identity),
        ProofNode(:farkas_contradiction, :exact_order,
                  [_sha256_payload((; lhs=rational_string.(lhs_values),
                                     rhs=rational_string.(rhs_values)))],
                  _sha256_payload((; lhs=rational_string(left),
                                     rhs=rational_string(right))),
                  :verify_farkas_contradiction, :accepted;
                  typed_payload=Dict(:contradiction_hash => _sha256_payload((; lhs=rational_string(left),
                                                                               rhs=rational_string(right))),
                                     :lhs => rational_string(left),
                                     :rhs => rational_string(right)),
                  obligation_id=:farkas_contradiction),
    ]
    dag = CertificateDAG(:farkas_infeasibility, nodes, "",
                         CERTSDP3_SCHEMA_VERSION)
    cert0 = FarkasInfeasibilityCertificate(String(problem_hash), lhs_values,
                                           rhs_values,
                                           ExactLowRankPSDProof[cone_proofs...],
                                           left, right, "", dag)
    return FarkasInfeasibilityCertificate(String(problem_hash), lhs_values,
                                          rhs_values,
                                          ExactLowRankPSDProof[cone_proofs...],
                                          left, right,
                                          farkas_infeasibility_hash(cert0),
                                          dag)
end

function make_farkas_infeasibility_certificate(problem::ExactConicProblem,
                                               dual_variables::AbstractVector{SparseSymmetricRationalMatrix},
                                               cone_proofs::AbstractVector{ExactLowRankPSDProof};
                                               contradiction_lhs=0//1,
                                               contradiction_rhs=nothing)
    ys = SparseSymmetricRationalMatrix[dual_variables...]
    length(ys) == length(problem.blocks) ||
        throw(DimensionMismatch("dual variable count does not match problem blocks"))
    lhs = _conic_dual_adjoint(problem, ys)
    rhs = copy(problem.objective)
    left = _to_big_rational(contradiction_lhs, "contradiction_lhs")
    right = isnothing(contradiction_rhs) ? _conic_dual_objective(problem, ys) :
            _to_big_rational(contradiction_rhs, "contradiction_rhs")
    identity_hash = _sha256_payload((; lhs=rational_string.(lhs),
                                      rhs=rational_string.(rhs)))
    nodes = ProofNode[
        ProofNode(:farkas_identity, :exact_affine_adjoint_replay, String[],
                  identity_hash,
                  :verify_farkas_identity, :accepted;
                  typed_payload=Dict(:problem => exact_conic_problem_json(problem),
                                     :dual_variables => [sparse_matrix_json(matrix) for matrix in ys],
                                     :lhs => rational_string.(lhs),
                                     :rhs => rational_string.(rhs)),
                  obligation_id=:farkas_dual_identity),
        ProofNode(:farkas_contradiction, :exact_order,
                  [identity_hash],
                  _sha256_payload((; lhs=rational_string(left),
                                     rhs=rational_string(right))),
                  :verify_farkas_contradiction, :accepted;
                  typed_payload=Dict(:problem => exact_conic_problem_json(problem),
                                     :dual_variables => [sparse_matrix_json(matrix) for matrix in ys],
                                     :contradiction_hash => _sha256_payload((; lhs=rational_string(left),
                                                                               rhs=rational_string(right))),
                                     :lhs => rational_string(left),
                                     :rhs => rational_string(right)),
                  obligation_id=:farkas_contradiction),
    ]
    dag = CertificateDAG(:farkas_infeasibility, nodes, "",
                         CERTSDP3_SCHEMA_VERSION)
    cert0 = FarkasInfeasibilityCertificate(problem.problem_hash,
                                           problem,
                                           ys,
                                           lhs,
                                           rhs,
                                           ExactLowRankPSDProof[cone_proofs...],
                                           left,
                                           right,
                                           "",
                                           dag)
    return FarkasInfeasibilityCertificate(problem.problem_hash,
                                          problem,
                                          ys,
                                          lhs,
                                          rhs,
                                          ExactLowRankPSDProof[cone_proofs...],
                                          left,
                                          right,
                                          farkas_infeasibility_hash(cert0),
                                          dag)
end

function _verify_primal_from_problem(cert::PrimalFeasibilityCertificate)
    problem = cert.problem
    isnothing(problem) && return nothing
    problem.problem_hash == cert.problem_hash ||
        return _reject(:G, :primal_dual_optimality, :hash,
                       :problem_hash,
                       "primal problem hash does not match exact conic problem";
                       problem_hash=cert.problem_hash)
    length(cert.primal_vector) == length(problem.variables) ||
        return _reject(:G, :primal_dual_optimality, :primal_affine,
                       :primal_vector,
                       "primal vector length does not match problem variables";
                       problem_hash=cert.problem_hash)
    expected_slacks = _conic_primal_slacks(problem, cert.primal_vector)
    length(expected_slacks) == length(cert.cone_matrices) ||
        return _reject(:G, :primal_dual_optimality, :primal_affine,
                       :primal_cone_count,
                       "primal slack block count does not match problem blocks";
                       problem_hash=cert.problem_hash)
    for (i, (expected, supplied)) in enumerate(zip(expected_slacks, cert.cone_matrices))
        _matrix_equal(expected, supplied) ||
            return _reject(:G, :primal_dual_optimality, :primal_affine,
                           Symbol("primal_block_", i),
                           "primal slack block does not equal B - A(x)";
                           problem_hash=cert.problem_hash,
                           details=_first_sparse_difference(entries_dict(supplied),
                                                            entries_dict(expected)))
    end
    objective = _conic_primal_objective(problem, cert.primal_vector)
    objective == cert.objective_value ||
        return _reject(:G, :primal_dual_optimality, :primal_objective,
                       :primal_objective,
                       "primal objective was not reconstructed from c'x";
                       problem_hash=cert.problem_hash,
                       details=Dict{Symbol, Any}(:expected => rational_string(objective),
                                                 :actual => rational_string(cert.objective_value)))
    return nothing
end

function _verify_dual_from_problem(cert::DualFeasibilityCertificate)
    problem = cert.problem
    isnothing(problem) && return nothing
    problem.problem_hash == cert.problem_hash ||
        return _reject(:G, :primal_dual_optimality, :hash,
                       :problem_hash,
                       "dual problem hash does not match exact conic problem";
                       problem_hash=cert.problem_hash)
    length(cert.dual_variables) == length(problem.blocks) ||
        return _reject(:G, :primal_dual_optimality, :dual_affine,
                       :dual_variables,
                       "dual variable block count does not match problem blocks";
                       problem_hash=cert.problem_hash)
    dual_adj = _conic_dual_adjoint(problem, cert.dual_variables)
    dual_adj == problem.objective ||
        return _reject(:G, :primal_dual_optimality, :dual_affine,
                       :dual_adjoint,
                       "dual adjoint replay does not satisfy A*(y) == c";
                       problem_hash=cert.problem_hash,
                       details=Dict{Symbol, Any}(:expected => rational_string.(problem.objective),
                                                 :actual => rational_string.(dual_adj)))
    length(cert.cone_matrices) == length(cert.dual_variables) ||
        return _reject(:G, :primal_dual_optimality, :dual_affine,
                       :dual_cone_count,
                       "dual cone block count does not match dual variable count";
                       problem_hash=cert.problem_hash,
                       details=Dict{Symbol, Any}(:expected => length(cert.dual_variables),
                                                 :actual => length(cert.cone_matrices)))
    for (i, (expected, supplied)) in enumerate(zip(cert.dual_variables, cert.cone_matrices))
        _matrix_equal(expected, supplied) ||
            return _reject(:G, :primal_dual_optimality, :dual_affine,
                           Symbol("dual_block_", i),
                           "dual cone block does not equal supplied dual variable";
                           problem_hash=cert.problem_hash,
                           details=_first_sparse_difference(entries_dict(supplied),
                                                            entries_dict(expected)))
    end
    objective = _conic_dual_objective(problem, cert.dual_variables)
    objective == cert.objective_value ||
        return _reject(:G, :primal_dual_optimality, :dual_objective,
                       :dual_objective,
                       "dual objective was not reconstructed from <B,y>";
                       problem_hash=cert.problem_hash,
                       details=Dict{Symbol, Any}(:expected => rational_string(objective),
                                                 :actual => rational_string(cert.objective_value)))
    return nothing
end

function _verify_farkas_from_problem(cert::FarkasInfeasibilityCertificate)
    problem = cert.problem
    isnothing(problem) && return nothing
    problem.problem_hash == cert.problem_hash ||
        return _reject(:G, :farkas_infeasibility, :hash,
                       :problem_hash,
                       "Farkas problem hash does not match exact conic problem";
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash)
    length(cert.dual_variables) == length(problem.blocks) ||
        return _reject(:G, :farkas_infeasibility, :farkas_identity,
                       :dual_variables,
                       "Farkas dual variable block count does not match problem blocks";
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash)
    lhs = _conic_dual_adjoint(problem, cert.dual_variables)
    rhs = copy(problem.objective)
    lhs == cert.multiplier_identity_lhs ||
        return _reject(:G, :farkas_infeasibility, :farkas_identity,
                       :dual_multiplier_identity,
                       "Farkas identity lhs was not reconstructed from A*(y)";
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash)
    rhs == cert.multiplier_identity_rhs ||
        return _reject(:G, :farkas_infeasibility, :farkas_identity,
                       :dual_multiplier_identity,
                       "Farkas identity rhs does not match problem objective";
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash)
    contradiction = _conic_dual_objective(problem, cert.dual_variables)
    contradiction == cert.contradiction_rhs ||
        return _reject(:G, :farkas_infeasibility, :contradiction,
                       :normalized_contradiction,
                       "Farkas contradiction scalar was not reconstructed from <B,y>";
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash,
                       details=Dict{Symbol, Any}(:expected => rational_string(contradiction),
                                                 :actual => rational_string(cert.contradiction_rhs)))
    return nothing
end

function verify_primal_dual_optimality(cert::PrimalDualOptimalityCertificate)
    try
        cert.problem_hash == cert.primal.problem_hash == cert.dual.problem_hash ||
            return _reject(:G, :primal_dual_optimality, :hash,
                           :problem_hash,
                           "primal/dual problem hashes do not agree";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        cert.certificate_hash == primal_dual_optimality_hash(cert) ||
            return _reject(:G, :primal_dual_optimality, :hash,
                           :certificate_hash,
                           "primal-dual certificate hash mismatch";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        (!isnothing(cert.primal.problem) && !isnothing(cert.dual.problem)) ||
            return _reject(:G, :primal_dual_optimality,
                           :primal_dual_affine_map,
                           :problem_data,
                           "exact conic problem object is required; supplied lhs/rhs arrays are not proof";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        cert.primal.problem === cert.dual.problem ||
            cert.primal.problem.problem_hash == cert.dual.problem.problem_hash ||
            return _reject(:G, :primal_dual_optimality, :hash,
                           :problem_hash,
                           "primal and dual do not reference the same exact conic problem";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        primal_problem_report = _verify_primal_from_problem(cert.primal)
        isnothing(primal_problem_report) || return primal_problem_report
        dual_problem_report = _verify_dual_from_problem(cert.dual)
        isnothing(dual_problem_report) || return dual_problem_report
        length(cert.primal.cone_matrices) == length(cert.primal.cone_proofs) ||
            return _reject(:G, :primal_dual_optimality, :primal_cone,
                           :primal_cone_count,
                           "primal cone matrix/proof count mismatch";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        length(cert.dual.cone_matrices) == length(cert.dual.cone_proofs) ||
            return _reject(:G, :primal_dual_optimality, :dual_cone,
                           :dual_cone_count,
                           "dual cone matrix/proof count mismatch";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        for (i, (matrix, proof)) in enumerate(zip(cert.primal.cone_matrices,
                                                 cert.primal.cone_proofs))
            cone_report = verify_low_rank_psd(matrix, proof)
            cone_report.accepted ||
                return _with_location(cone_report;
                                      family=:primal_dual_optimality,
                                      block_id=Symbol("primal_cone_", i),
                                      certificate_hash=cert.certificate_hash)
        end
        for (i, (matrix, proof)) in enumerate(zip(cert.dual.cone_matrices,
                                                 cert.dual.cone_proofs))
            cone_report = verify_low_rank_psd(matrix, proof)
            cone_report.accepted ||
                return _with_location(cone_report;
                                      family=:primal_dual_optimality,
                                      block_id=Symbol("dual_cone_", i),
                                      certificate_hash=cert.certificate_hash)
        end
        expected_gap = _conic_gap(cert.primal.problem,
                                  cert.primal.objective_value,
                                  cert.dual.objective_value)
        expected_gap == cert.gap ||
            return _reject(:G, :primal_dual_optimality, :objective_gap,
                           :exact_gap,
                           "declared objective gap does not equal primal-dual difference";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        cert.gap == 0 ||
            return _reject(:G, :primal_dual_optimality, :objective_gap,
                           :exact_gap,
                           "primal-dual gap is not zero";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash,
                           details=Dict{Symbol, Any}(:gap => rational_string(cert.gap)))
        dag_report = verify_proof_dag(cert.dag)
        dag_report.accepted || return dag_report
        return _accept(:G, :primal_dual_optimality, :objective_gap,
                       :exact_gap;
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash)
    catch err
        return _reject(:G, :primal_dual_optimality, :exception,
                       :primal_dual_replay,
                       sprint(showerror, err);
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash)
    end
end

function verify_farkas_infeasibility(cert::FarkasInfeasibilityCertificate)
    try
        cert.certificate_hash == farkas_infeasibility_hash(cert) ||
            return _reject(:G, :farkas_infeasibility, :hash,
                           :certificate_hash,
                           "Farkas certificate hash mismatch";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        isnothing(cert.problem) &&
            return _reject(:G, :farkas_infeasibility,
                           :farkas_problem_data,
                           :problem_data,
                           "exact conic problem object is required; supplied lhs/rhs arrays are not proof";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        problem_report = _verify_farkas_from_problem(cert)
        isnothing(problem_report) || return problem_report
        cert.multiplier_identity_lhs == cert.multiplier_identity_rhs ||
            return _reject(:G, :farkas_infeasibility,
                           :farkas_identity,
                           :dual_multiplier_identity,
                           "Farkas multiplier identity does not replay exactly";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        for (i, proof) in enumerate(cert.cone_proofs)
            proof.field === :QQ ||
                return _reject(:G, :farkas_infeasibility,
                               :cone_membership,
                               Symbol("cone_", i),
                               "Farkas cone proof is not over QQ";
                               problem_hash=cert.problem_hash,
                               certificate_hash=cert.certificate_hash)
            all(value -> value >= 0, proof.diagonal) ||
                return _reject(:G, :farkas_infeasibility,
                               :cone_membership,
                               Symbol("cone_", i),
                               "Farkas cone proof has negative diagonal";
                               problem_hash=cert.problem_hash,
                               certificate_hash=cert.certificate_hash)
        end
        cert.contradiction_lhs == 0 && cert.contradiction_rhs < 0 ||
            return _reject(:G, :farkas_infeasibility,
                           :contradiction,
                           :normalized_contradiction,
                           "Farkas contradiction must have normalized form 0 <= negative";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash,
                           details=Dict{Symbol, Any}(:lhs => rational_string(cert.contradiction_lhs),
                                                     :rhs => rational_string(cert.contradiction_rhs)))
        dag_report = verify_proof_dag(cert.dag)
        dag_report.accepted || return dag_report
        return _accept(:G, :farkas_infeasibility, :contradiction,
                       :normalized_contradiction;
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash)
    catch err
        return _reject(:G, :farkas_infeasibility, :exception,
                       :farkas_replay,
                       sprint(showerror, err);
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash)
    end
end

function SparseSOSProblem(variables::AbstractVector{Symbol},
                          target_terms::AbstractVector{PolynomialTerm},
                          cliques::AbstractVector,
                          lower_bound=0//1)
    vars = collect(variables)
    length(unique(vars)) == length(vars) ||
        throw(ArgumentError("SparseSOSProblem variables must be unique"))
    bound = _to_big_rational(lower_bound, "lower_bound")
    clique_symbols = [Symbol.(collect(clique)) for clique in cliques]
    problem0 = SparseSOSProblem(vars, PolynomialTerm[target_terms...],
                                clique_symbols, bound, "")
    return SparseSOSProblem(vars, PolynomialTerm[target_terms...],
                            clique_symbols, bound,
                            sparse_sos_problem_hash(problem0))
end

function NPAProblem(variables::AbstractVector{Symbol},
                    relations::AbstractVector{<:AbstractQuantumRelation},
                    word_basis::AbstractVector;
                    trace_cyclic::Bool=false)
    vars = Symbol.(collect(variables))
    length(unique(vars)) == length(vars) ||
        throw(ArgumentError("NPAProblem variables must be unique"))
    basis = [Symbol.(collect(word)) for word in word_basis]
    length(unique(basis)) == length(basis) ||
        throw(ArgumentError("NPAProblem word basis must be unique"))
    problem0 = NPAProblem(vars, AbstractQuantumRelation[relations...],
                          basis, Bool(trace_cyclic), "")
    return NPAProblem(vars, AbstractQuantumRelation[relations...],
                      basis, Bool(trace_cyclic), npa_problem_hash(problem0))
end

function NCMomentMatrixCertificate(problem::NPAProblem,
                                   moment_matrix::SparseSymmetricRationalMatrix,
                                   psd_proof::ExactLowRankPSDProof,
                                   coefficient_terms,
                                   witnesses::AbstractVector{NCRewriteWitness})
    terms = Tuple{Vector{Symbol}, Rational{BigInt}}[]
    for (i, term) in enumerate(coefficient_terms)
        length(term) == 2 ||
            throw(ArgumentError("NC coefficient term $i must contain word and coefficient"))
        push!(terms, (Symbol.(collect(term[1])),
                     _to_big_rational(term[2], "nc_coefficient_terms[$i]")))
    end
    cert0 = NCMomentMatrixCertificate(problem.problem_hash,
                                      moment_matrix,
                                      psd_proof,
                                      terms,
                                      NCRewriteWitness[witnesses...],
                                      "")
    return NCMomentMatrixCertificate(problem.problem_hash,
                                     moment_matrix,
                                     psd_proof,
                                     terms,
                                     NCRewriteWitness[witnesses...],
                                     nc_moment_certificate_hash(cert0))
end

function _npa_moment_entry_records(problem::NPAProblem,
                                   cert::NCMomentMatrixCertificate)
    entries = sort!(collect(entries_dict(cert.moment_matrix)); by=item -> (item[1][1], item[1][2]))
    length(entries) == length(cert.witnesses) ||
        throw(ArgumentError("moment certificate witness count $(length(cert.witnesses)) does not cover every declared moment entry $(length(entries))"))
    used = Set{Int}()
    records = Vector{NamedTuple}()
    relation_hash = npa_relation_system_hash(problem.relations)
    for ((row_index, col_index), value) in entries
        row_word = problem.word_basis[row_index]
        col_word = problem.word_basis[col_index]
        adjoint_row = reverse([_star_symbol(symbol) for symbol in row_word])
        product_word = vcat(adjoint_row, col_word)
        matches = findall(witness -> witness.input_word == product_word, cert.witnesses)
        length(matches) == 1 ||
            throw(ArgumentError("moment entry ($row_index,$col_index) does not have exactly one rewrite witness"))
        witness_index = only(matches)
        witness_index in used &&
            throw(ArgumentError("rewrite witness $witness_index is reused across moment entries"))
        push!(used, witness_index)
        witness = cert.witnesses[witness_index]
        report = verify_nc_rewrite_witness(witness, problem.relations)
        report.accepted ||
            throw(ArgumentError("moment entry ($row_index,$col_index) witness rejected: $(report.reason)"))
        block_id = "moment_block_1"
        output_hash = npa_moment_entry_output_hash(row_index, col_index,
                                                   block_id,
                                                   witness.final_word,
                                                   value)
        payload = Dict{Symbol, Any}(
            :row_index => row_index,
            :col_index => col_index,
            :row_word => String.(row_word),
            :col_word => String.(col_word),
            :adjoint_row_word => String.(adjoint_row),
            :product_word => String.(product_word),
            :relations => [quantum_relation_json(relation) for relation in problem.relations],
            :relation_system_hash => relation_hash,
            :rewrite_witness_id => "witness_$witness_index",
            :rewrite_witness => nc_rewrite_witness_json(witness),
            :expected_normal_form => String.(witness.final_word),
            :expected_moment_value => rational_string(value),
            :matrix_entry_value => rational_string(value),
            :block_id => block_id,
        )
        push!(records, (row_index=row_index,
                        col_index=col_index,
                        witness_index=witness_index,
                        output_hash=output_hash,
                        payload=payload))
    end
    length(used) == length(cert.witnesses) ||
        throw(ArgumentError("moment certificate contains rewrite witnesses not tied to declared matrix entries"))
    return records
end

function make_quantum_bound_certificate(problem::NPAProblem,
                                        moment_certificate::NCMomentMatrixCertificate,
                                        objective_terms,
                                        bound)
    terms = Tuple{Vector{Symbol}, Rational{BigInt}}[]
    for (i, term) in enumerate(objective_terms)
        length(term) == 2 ||
            throw(ArgumentError("quantum objective term $i must contain word and coefficient"))
        push!(terms, (Symbol.(collect(term[1])),
                     _to_big_rational(term[2], "quantum_objective_terms[$i]")))
    end
    bound_value = _to_big_rational(bound, "quantum_bound")
    entry_records = _npa_moment_entry_records(problem, moment_certificate)
    entry_nodes = ProofNode[
        ProofNode(Symbol("npa_moment_entry_$(record.row_index)_$(record.col_index)"),
                  :npa_moment_entry,
                  [problem.problem_hash, moment_certificate.moment_matrix.hash],
                  record.output_hash,
                  :check_npa_moment_entry,
                  :accepted;
                  typed_payload=record.payload,
                  arithmetic_mode=:symbolic_sparse,
                  obligation_id=Symbol("npa_moment_entry_$(record.row_index)_$(record.col_index)"))
        for record in entry_records
    ]
    entry_hashes = [record.output_hash for record in entry_records]
    nodes = ProofNode[
        ProofNode(:npa_problem, :hash, String[],
                  problem.problem_hash, :npa_problem_hash, :accepted;
                  typed_payload=Dict(:problem => npa_problem_json(problem)),
                  arithmetic_mode=:symbolic_sparse,
                  obligation_id=:npa_problem),
        ProofNode(:moment_matrix, :sparse_matrix, [problem.problem_hash],
                  moment_certificate.moment_matrix.hash,
                  :canonical_sparse_matrix_hash, :accepted;
                  typed_payload=Dict(:matrix => sparse_matrix_json(moment_certificate.moment_matrix)),
                  arithmetic_mode=:symbolic_sparse,
                  obligation_id=:moment_matrix_hash),
        ProofNode(:nc_rewrite_witnesses, :exact_rewrite, [problem.problem_hash],
                  _sha256_payload([nc_rewrite_witness_json(witness)
                                   for witness in moment_certificate.witnesses]),
                  :verify_nc_rewrite_witness, :accepted;
                  typed_payload=Dict(:relations => [quantum_relation_json(relation)
                                                    for relation in problem.relations],
                                     :witnesses => [nc_rewrite_witness_json(witness)
                                                    for witness in moment_certificate.witnesses]),
                  arithmetic_mode=:symbolic_sparse,
                  obligation_id=:nc_rewrite_witnesses),
        ProofNode(:moment_psd, :psd, [moment_certificate.moment_matrix.hash],
                  moment_certificate.psd_proof.identity_proof_hash,
                  :verify_low_rank_psd, :accepted;
                  typed_payload=Dict(:matrix => sparse_matrix_json(moment_certificate.moment_matrix),
                                     :proof => low_rank_proof_json(moment_certificate.psd_proof)),
                  obligation_id=:moment_psd),
        ProofNode(:objective_bound, :exact_equality,
                  entry_hashes,
                  _sha256_payload((; objective=[nc_term_json(term)
                                                for term in terms],
                                     bound=rational_string(bound_value))),
                  :verify_quantum_bound_certificate, :accepted;
                  typed_payload=Dict(:problem => npa_problem_json(problem),
                                     :moment_certificate => nc_moment_certificate_json(moment_certificate),
                                     :objective_terms => [nc_term_json(term) for term in terms],
                                     :bound => rational_string(bound_value),
                                     :moment_entry_hashes => entry_hashes),
                  arithmetic_mode=:symbolic_sparse,
                  obligation_id=:npa_objective_functional),
    ]
    nodes = vcat(nodes[1:4], entry_nodes, nodes[5:end])
    dag = CertificateDAG(:quantum_bound, nodes, "", CERTSDP3_SCHEMA_VERSION)
    cert0 = QuantumBoundCertificate(problem, moment_certificate, terms,
                                    bound_value, "", dag)
    return QuantumBoundCertificate(problem, moment_certificate, terms,
                                   bound_value,
                                   quantum_bound_certificate_hash(cert0),
                                   dag)
end

function verify_nc_rewrite_witness(witness::NCRewriteWitness,
                                   relations::AbstractVector{<:AbstractQuantumRelation})
    try
        relation_ids = Set(relation.id for relation in relations)
        current = copy(witness.input_word)
        used = Symbol[]
        for (i, step) in enumerate(witness.steps)
            step.before == current ||
                return _reject(:J, :nc_rewrite, :rewrite_witness,
                               Symbol("step_", i),
                               "rewrite step input does not match previous output";
                               details=Dict{Symbol, Any}(:expected => String.(current),
                                                         :actual => String.(step.before)))
            step.relation_id in relation_ids ||
                return _reject(:J, :nc_rewrite, :rewrite_witness,
                               Symbol("step_", i),
                               "rewrite step references an unknown relation";
                               details=Dict{Symbol, Any}(:relation_id => String(step.relation_id)))
            _quantum_step_allowed(step, relations) ||
                return _reject(:J, :nc_rewrite, :rewrite_witness,
                               Symbol("step_", i),
                               "rewrite step is not justified by its relation";
                               details=Dict{Symbol, Any}(:rule => String(step.rule),
                                                         :relation_id => String(step.relation_id)))
            current = copy(step.after)
            push!(used, step.relation_id)
        end
        current == witness.final_word ||
            return _reject(:J, :nc_rewrite, :rewrite_witness,
                           :final_word,
                           "rewrite witness final word mismatch")
        sort(unique(used)) == sort(unique(witness.relation_ids_used)) ||
            return _reject(:J, :nc_rewrite, :rewrite_witness,
                           :relation_ids_used,
                           "rewrite witness relation id summary mismatch")
        return _accept(:J, :nc_rewrite, :rewrite_witness, :nc_rewrite_witness)
    catch err
        return _reject(:J, :nc_rewrite, :exception, :nc_rewrite_witness,
                       sprint(showerror, err))
    end
end

function verify_quantum_bound_certificate(cert::QuantumBoundCertificate)
    try
        cert.problem.problem_hash == npa_problem_hash(cert.problem) ||
            return _reject(:J, :quantum_bound, :hash, :problem_hash,
                           "NPA problem hash mismatch";
                           problem_hash=cert.problem.problem_hash,
                           certificate_hash=cert.certificate_hash)
        cert.moment_certificate.problem_hash == cert.problem.problem_hash ||
            return _reject(:J, :quantum_bound, :moment_replay,
                           :moment_problem_hash,
                           "moment certificate problem hash does not match NPA problem";
                           problem_hash=cert.problem.problem_hash,
                           certificate_hash=cert.certificate_hash)
        cert.moment_certificate.certificate_hash ==
            nc_moment_certificate_hash(cert.moment_certificate) ||
            return _reject(:J, :quantum_bound, :hash,
                           :moment_certificate_hash,
                           "NC moment certificate hash mismatch";
                           problem_hash=cert.problem.problem_hash,
                           certificate_hash=cert.certificate_hash)
        canonical_cert = make_quantum_bound_certificate(cert.problem,
                                                        cert.moment_certificate,
                                                        cert.objective_terms,
                                                        cert.bound)
        cert.certificate_hash == canonical_cert.certificate_hash ||
            return _reject(:J, :quantum_bound, :hash,
                           :certificate_hash,
                           "quantum bound certificate hash mismatch";
                           problem_hash=cert.problem.problem_hash,
                           certificate_hash=cert.certificate_hash)
        psd_report = verify_low_rank_psd(cert.moment_certificate.moment_matrix,
                                         cert.moment_certificate.psd_proof)
        psd_report.accepted ||
            return _with_location(psd_report;
                                  family=:quantum_bound,
                                  block_id=:moment_matrix,
                                  certificate_hash=cert.certificate_hash)
        basis_set = Set(cert.problem.word_basis)
        for (i, word) in enumerate(cert.problem.word_basis)
            word in basis_set ||
                return _reject(:J, :quantum_bound, :word_basis,
                               Symbol("word_", i),
                               "word basis contains an unknown word";
                               problem_hash=cert.problem.problem_hash,
                               certificate_hash=cert.certificate_hash)
        end
        for (i, witness) in enumerate(cert.moment_certificate.witnesses)
            report = verify_nc_rewrite_witness(witness, cert.problem.relations)
            report.accepted ||
                return _with_location(report;
                                      family=:quantum_bound,
                                      block_id=Symbol("rewrite_witness_", i),
                                      certificate_hash=cert.certificate_hash)
        end
        verified_values = _verified_moment_entries(cert.problem,
                                                   cert.moment_certificate)
        objective = _nc_term_dict(cert.objective_terms)
        coefficients = _nc_term_dict(cert.moment_certificate.coefficient_terms)
        objective == coefficients ||
            return _reject(:J, :quantum_bound, :coefficient_matching,
                           :objective_coefficients,
                           "quantum objective coefficients do not match moment certificate";
                           problem_hash=cert.problem.problem_hash,
                           certificate_hash=cert.certificate_hash)
        objective_value = _objective_from_verified_moments(cert.objective_terms,
                                                           verified_values)
        objective_value == cert.bound ||
            return _reject(:J, :quantum_bound, :objective_bound,
                           :exact_bound,
                           "quantum objective bound does not replay from verified moment entries";
                           problem_hash=cert.problem.problem_hash,
                           certificate_hash=cert.certificate_hash,
                           details=Dict{Symbol, Any}(:computed => rational_string(objective_value),
                                                     :bound => rational_string(cert.bound)))
        dag_report = verify_proof_dag(cert.dag)
        dag_report.accepted || return dag_report
        return _accept(:J, :quantum_bound, :objective_bound, :exact_bound;
                       problem_hash=cert.problem.problem_hash,
                       certificate_hash=cert.certificate_hash)
    catch err
        return _reject(:J, :quantum_bound, :exception, :quantum_bound_replay,
                       sprint(showerror, err);
                       problem_hash=cert.problem.problem_hash,
                       certificate_hash=cert.certificate_hash)
    end
end

function make_sparse_sos_certificate(problem::SparseSOSProblem,
                                     sos_blocks::AbstractVector{SparseSOSBlock};
                                     putinar::Union{Nothing, PutinarCertificate}=nothing)
    nodes = ProofNode[
        ProofNode(:sparse_sos_problem, :hash, String[],
                  problem.problem_hash, :sparse_sos_problem_hash, :accepted;
                  typed_payload=Dict(:problem => sparse_sos_problem_json(problem)),
                  arithmetic_mode=:symbolic_sparse,
                  obligation_id=:sparse_sos_problem),
        ProofNode(:coefficient_matching, :exact_equality, [problem.problem_hash],
                  _sha256_payload((; target=[polynomial_term_json(term)
                                             for term in problem.target_terms],
                                     blocks=[sparse_sos_block_json(block)
                                             for block in sos_blocks],
                                     putinar=isnothing(putinar) ? nothing :
                                             putinar_certificate_json(putinar),
                                     bound=rational_string(problem.lower_bound))),
                  :verify_sparse_sos_coefficients, :accepted;
                  typed_payload=Dict(:problem => sparse_sos_problem_json(problem),
                                     :sos_blocks => [sparse_sos_block_json(block)
                                                     for block in sos_blocks],
                                     :putinar => isnothing(putinar) ? nothing :
                                                 putinar_certificate_json(putinar)),
                  arithmetic_mode=:symbolic_sparse,
                  obligation_id=:sparse_sos_gram_expansion),
    ]
    dag = CertificateDAG(:sparse_sos, nodes, "", CERTSDP3_SCHEMA_VERSION)
    cert0 = SparseSOSCertificate(problem, SparseSOSBlock[sos_blocks...],
                                 putinar, "", dag)
    return SparseSOSCertificate(problem, SparseSOSBlock[sos_blocks...],
                                putinar, sparse_sos_certificate_hash(cert0),
                                dag)
end

function verify_sparse_sos_certificate(cert::SparseSOSCertificate)
    try
        cert.problem.problem_hash == sparse_sos_problem_hash(cert.problem) ||
            return _reject(:H, :sparse_sos, :hash, :problem_hash,
                           "sparse SOS problem hash mismatch";
                           problem_hash=cert.problem.problem_hash,
                           certificate_hash=cert.certificate_hash)
        cert.certificate_hash == sparse_sos_certificate_hash(cert) ||
            return _reject(:H, :sparse_sos, :hash, :certificate_hash,
                           "sparse SOS certificate hash mismatch";
                           problem_hash=cert.problem.problem_hash,
                           certificate_hash=cert.certificate_hash)
        expansion = getfield(parentmodule(@__MODULE__), :SOSGramExpansion)
        accumulated = Dict{Vector{Int}, Rational{BigInt}}()
        for block in cert.sos_blocks
            report = verify_low_rank_psd(block.gram_matrix, block.psd_proof)
            report.accepted ||
                return _with_location(report;
                                      family=:sparse_sos,
                                      block_id=block.id,
                                      certificate_hash=cert.certificate_hash)
            derived = expansion.gram_polynomial(block)
            cached = expansion.polynomial_dict(block.coefficient_terms)
            derived == cached ||
                return _reject(:H, :sparse_sos, :coefficient_matching,
                               Symbol("cached_terms_", block.id),
                               "cached SOS coefficient_terms do not match Gram expansion";
                               problem_hash=cert.problem.problem_hash,
                               certificate_hash=cert.certificate_hash,
                               block_id=block.id,
                               details=Dict{Symbol, Any}(:derived_terms => length(derived),
                                                         :cached_terms => length(cached)))
            for (exp, coeff) in derived
                _add_polynomial_coefficient!(accumulated, exp, coeff)
            end
        end
        if !isnothing(cert.putinar)
            cert.putinar.bound == cert.problem.lower_bound ||
                return _reject(:H, :putinar, :objective_bound,
                               :putinar_bound,
                               "Putinar bound does not match problem lower bound";
                               problem_hash=cert.problem.problem_hash,
                               certificate_hash=cert.certificate_hash)
            for localizing in cert.putinar.localizing_blocks
                report = verify_low_rank_psd(localizing.sos_block.gram_matrix,
                                             localizing.sos_block.psd_proof)
                report.accepted ||
                    return _with_location(report;
                                          family=:putinar,
                                          block_id=localizing.id,
                                          certificate_hash=cert.certificate_hash)
                derived_local = expansion.localizing_polynomial(localizing)
                cached_local = expansion.multiply_polynomials(
                    expansion.polynomial_dict(localizing.sos_block.coefficient_terms),
                    expansion.polynomial_dict(localizing.constraint_terms))
                derived_local == cached_local ||
                    return _reject(:H, :putinar, :coefficient_matching,
                                   Symbol("cached_localizing_", localizing.id),
                                   "cached localizing coefficient_terms do not match Gram expansion";
                                   problem_hash=cert.problem.problem_hash,
                                   certificate_hash=cert.certificate_hash,
                                   block_id=localizing.id,
                                   details=Dict{Symbol, Any}(:derived_terms => length(derived_local),
                                                             :cached_terms => length(cached_local)))
                for (exp, coeff) in derived_local
                    _add_polynomial_coefficient!(accumulated, exp, coeff)
                end
            end
            cert.putinar.identity_hash == _sha256_payload((;
                bound=rational_string(cert.putinar.bound),
                localizing=[localizing_matrix_proof_json(block)
                            for block in cert.putinar.localizing_blocks])) ||
                return _reject(:H, :putinar, :coefficient_matching,
                               :putinar_identity_hash,
                               "Putinar identity hash mismatch";
                               problem_hash=cert.problem.problem_hash,
                               certificate_hash=cert.certificate_hash)
        end
        target = Dict{Vector{Int}, Rational{BigInt}}()
        _accumulate_polynomial_terms!(target, cert.problem.target_terms)
        if cert.problem.lower_bound != 0
            zero_exp = isempty(cert.problem.variables) ? Int[] :
                       zeros(Int, length(cert.problem.variables))
            _add_polynomial_coefficient!(target, zero_exp, -cert.problem.lower_bound)
        end
        accumulated == target ||
            return _reject(:H, :sparse_sos, :coefficient_matching,
                           :polynomial_identity,
                           "sparse SOS coefficient identity mismatch";
                           problem_hash=cert.problem.problem_hash,
                           certificate_hash=cert.certificate_hash,
                           details=Dict{Symbol, Any}(:actual_terms => length(accumulated),
                                                     :target_terms => length(target),
                                                     :actual => expansion.polynomial_payload(accumulated),
                                                     :target => expansion.polynomial_payload(target)))
        dag_report = verify_proof_dag(cert.dag)
        dag_report.accepted || return dag_report
        return _accept(:H, :sparse_sos, :coefficient_matching,
                       :polynomial_identity;
                       problem_hash=cert.problem.problem_hash,
                       certificate_hash=cert.certificate_hash)
    catch err
        return _reject(:H, :sparse_sos, :exception, :sparse_sos_replay,
                       sprint(showerror, err);
                       problem_hash=cert.problem.problem_hash,
                       certificate_hash=cert.certificate_hash)
    end
end

function verify_block_diagonalization_certificate(cert::BlockDiagonalizationCertificate)
    try
        cert.group.action_hash == symmetry_group_hash(cert.group) ||
            return _reject(:W, :symmetry_reduction, :group_action,
                           :action_hash,
                           "symmetry group action hash mismatch";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        cert.orbit_basis.orbit_hash == orbit_basis_hash(cert.orbit_basis) ||
            return _reject(:W, :symmetry_reduction, :orbit_partition,
                           :orbit_hash,
                           "orbit basis hash mismatch";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        cert.certificate_hash == block_diagonalization_certificate_hash(cert) ||
            return _reject(:W, :symmetry_reduction, :hash,
                           :certificate_hash,
                           "symmetry certificate hash mismatch";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        projector_error = _verify_projector_semantics(cert.projector_matrices,
                                                      cert.original_matrix.n)
        isnothing(projector_error) ||
            return _reject(:W, :symmetry_reduction,
                           :projector_semantics,
                           :projector_idempotence,
                           projector_error;
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        for generator in cert.group.generators
            for (orbit_index, orbit) in enumerate(cert.orbit_basis.orbits)
                mapped = sort!([_monomial_index_after_permutation(cert.orbit_basis,
                                                                  index,
                                                                  generator)
                                for index in orbit])
                mapped == sort(orbit) ||
                    return _reject(:W, :symmetry_reduction,
                                   :group_action,
                                   Symbol("orbit_", orbit_index),
                                   "generator does not preserve orbit partition";
                                   problem_hash=cert.problem_hash,
                                   certificate_hash=cert.certificate_hash)
            end
        end
        reconstructed = _sum_sparse_matrices(cert.projection_blocks,
                                             cert.original_matrix.n)
        reconstructed.entries == cert.reconstructed_matrix.entries ||
            return _reject(:W, :symmetry_reduction,
                           :block_reconstruction,
                           :projection_blocks,
                           "projection blocks do not reconstruct declared matrix";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        cert.original_matrix.entries == cert.reconstructed_matrix.entries ||
            return _reject(:W, :symmetry_reduction,
                           :block_reconstruction,
                           :original_identity,
                           "block diagonal reconstruction does not match original matrix";
                           problem_hash=cert.problem_hash,
                           certificate_hash=cert.certificate_hash)
        dag_report = verify_proof_dag(cert.dag)
        dag_report.accepted || return dag_report
        return _accept(:W, :symmetry_reduction, :block_reconstruction,
                       :original_identity;
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash)
    catch err
        return _reject(:W, :symmetry_reduction, :exception,
                       :symmetry_replay,
                       sprint(showerror, err);
                       problem_hash=cert.problem_hash,
                       certificate_hash=cert.certificate_hash)
    end
end

function _monomial_index_after_permutation(orbit::OrbitBasisCertificate,
                                           index::Int,
                                           generator::SymmetryPermutation)
    exponents = orbit.monomial_exponents[index]
    mapped = fill(0, length(exponents))
    for i in eachindex(exponents)
        mapped[generator.image[i]] = exponents[i]
    end
    found = findfirst(==(mapped), orbit.monomial_exponents)
    isnothing(found) &&
        throw(ArgumentError("permuted monomial exponent is not in orbit basis"))
    return found
end

function _sum_sparse_matrices(blocks::AbstractVector{SparseSymmetricRationalMatrix},
                              n::Int)
    accum = Dict{Tuple{Int, Int}, Rational{BigInt}}()
    for block in blocks
        block.n == n ||
            throw(ArgumentError("projection block dimension mismatch"))
        _accumulate_entries!(accum, block.entries, 1//1)
    end
    return _sparse_matrix_from_accumulator(n, accum)
end

function _accumulate_polynomial_terms!(target::Dict{Vector{Int}, Rational{BigInt}},
                                       terms::AbstractVector{PolynomialTerm})
    for term in terms
        _add_polynomial_coefficient!(target, term.exponents, term.coefficient)
    end
    return target
end

function _add_polynomial_coefficient!(target::Dict{Vector{Int}, Rational{BigInt}},
                                      exponents::Vector{Int},
                                      coefficient::Rational{BigInt})
    key = copy(exponents)
    target[key] = get(target, key, 0//1) + coefficient
    iszero(target[key]) && delete!(target, key)
    return target
end

function _nc_term_dict(terms::AbstractVector{Tuple{Vector{Symbol}, Rational{BigInt}}})
    result = Dict{Vector{Symbol}, Rational{BigInt}}()
    for (word, coefficient) in terms
        key = copy(word)
        result[key] = get(result, key, 0//1) + coefficient
        iszero(result[key]) && delete!(result, key)
    end
    return result
end

function _npa_entry_input_word(problem::NPAProblem, i::Int, j::Int)
    1 <= i <= length(problem.word_basis) ||
        throw(BoundsError(problem.word_basis, i))
    1 <= j <= length(problem.word_basis) ||
        throw(BoundsError(problem.word_basis, j))
    return vcat(reverse([_star_symbol(symbol) for symbol in problem.word_basis[i]]),
                problem.word_basis[j])
end

function _verified_moment_entries(problem::NPAProblem,
                                  cert::NCMomentMatrixCertificate)
    entries = entries_dict(cert.moment_matrix)
    entry_count = length(entries)
    entry_count == length(cert.witnesses) ||
        throw(ArgumentError("moment certificate witness count $(length(cert.witnesses)) does not cover every declared moment entry $entry_count"))
    values = Dict{Vector{Symbol}, Rational{BigInt}}()
    seen_entries = Set{Tuple{Int, Int}}()
    for (witness_index, witness) in enumerate(cert.witnesses)
        matched = Tuple{Int, Int}[]
        for ((i, j), value) in entries
            witness.input_word == _npa_entry_input_word(problem, i, j) &&
                push!(matched, (i, j))
        end
        length(matched) == 1 ||
            throw(ArgumentError("rewrite witness $witness_index does not match exactly one moment entry"))
        entry_key = only(matched)
        entry_key in seen_entries &&
            throw(ArgumentError("duplicate rewrite witness for moment entry $(entry_key)"))
        push!(seen_entries, entry_key)
        report = verify_nc_rewrite_witness(witness, problem.relations)
        report.accepted || throw(ArgumentError("moment entry rewrite witness rejected: $(report.reason)"))
        word_key = copy(witness.final_word)
        value = entries[entry_key]
        if haskey(values, word_key) && values[word_key] != value
            throw(ArgumentError("moment normal form $(String.(word_key)) has inconsistent values"))
        end
        values[word_key] = value
    end
    return values
end

function _objective_from_verified_moments(objective_terms,
                                          verified_values::Dict{Vector{Symbol}, Rational{BigInt}})
    total = Rational{BigInt}(0)
    for (word, coefficient) in objective_terms
        haskey(verified_values, word) ||
            throw(ArgumentError("objective word $(String.(word)) was not verified as a moment normal form"))
        total += coefficient * verified_values[word]
    end
    return total
end

function _quantum_step_allowed(step::NCRewriteStep,
                               relations::AbstractVector{<:AbstractQuantumRelation})
    relation = _find_relation(relations, step.relation_id)
    isnothing(relation) && return false
    if relation isa ProjectionRelation
        target = relation.symbol
        return step.rule === :projection_idempotent &&
               _replace_first_subword(step.before, [target, target], [target]) == step.after
    elseif relation isa UnitaryRelation
        target = relation.symbol
        return step.rule === :unitary_cancel &&
               (_replace_first_subword(step.before, [target, _star_symbol(target)], Symbol[]) == step.after ||
                _replace_first_subword(step.before, [_star_symbol(target), target], Symbol[]) == step.after)
    elseif relation isa CommutationRelation
        return step.rule === :commutation &&
               _commutation_swapped(step.before, step.after,
                                    relation.left_symbols,
                                    relation.right_symbols)
    elseif relation isa TraceCyclicRelation
        return step.rule === :trace_rotation &&
               _is_rotation(step.before, step.after)
    elseif relation isa StarInvolutionRelation
        return step.rule === :star_involution &&
               step.after == reverse([_star_symbol(symbol) for symbol in step.before])
    elseif relation isa NormalizationRelation
        return step.rule === :normalization &&
               isempty(step.before) && isempty(step.after) &&
               relation.value == 1//1
    end
    return false
end

function _find_relation(relations, id::Symbol)
    for relation in relations
        relation.id === id && return relation
    end
    return nothing
end

function _replace_first_subword(word::Vector{Symbol},
                                lhs::Vector{Symbol},
                                rhs::Vector{Symbol})
    isempty(lhs) && return word
    length(word) < length(lhs) && return word
    for start in 1:(length(word) - length(lhs) + 1)
        if word[start:(start + length(lhs) - 1)] == lhs
            return vcat(word[1:(start - 1)], rhs,
                        word[(start + length(lhs)):end])
        end
    end
    return word
end

function _commutation_swapped(before::Vector{Symbol},
                              after::Vector{Symbol},
                              left_symbols::Vector{Symbol},
                              right_symbols::Vector{Symbol})
    length(before) == length(after) || return false
    for i in 1:(length(before) - 1)
        before[i] in left_symbols && before[i + 1] in right_symbols || continue
        candidate = copy(before)
        candidate[i], candidate[i + 1] = candidate[i + 1], candidate[i]
        candidate == after && return true
    end
    return false
end

function _is_rotation(before::Vector{Symbol}, after::Vector{Symbol})
    length(before) == length(after) || return false
    isempty(before) && return isempty(after)
    for shift in 0:(length(before) - 1)
        rotated = [before[((i + shift - 1) % length(before)) + 1]
                   for i in 1:length(before)]
        rotated == after && return true
    end
    return false
end

function _star_symbol(symbol::Symbol)
    text = String(symbol)
    endswith(text, "_star") && return Symbol(text[1:(end - 5)])
    return Symbol(text, "_star")
end

function proof_dag(cert::V3Certificate)
    return cert.dag
end

proof_dag_json(cert::V3Certificate) = certificate_dag_json(cert.dag)

function verify_proof_dag(cert::V3Certificate)
    report = verify_certificate(cert)
    report.accepted ||
        return report
    dag_report = verify_proof_dag(cert.dag)
    dag_report.accepted || return dag_report
    return _accept(:E, cert.certificate_type, :proof_dag, :root_hash;
                   problem_hash=cert.problem_hash,
                   certificate_hash=cert.hash)
end

function verify_proof_dag(dag::CertificateDAG)
    checker_module = getfield(parentmodule(@__MODULE__), :DAGCheckerRegistry)
    checker_module.reset_dag_checker_calls!()
    dag.schema_version == CERTSDP3_SCHEMA_VERSION ||
        return _reject(:E, dag.claim_type, :proof_dag, :schema_version,
                       "DAG schema version mismatch";
                       certificate_hash=dag.root_hash)
    isempty(dag.nodes) &&
        return _reject(:E, dag.claim_type, :proof_dag, :nodes,
                       "DAG has no proof nodes";
                       certificate_hash=dag.root_hash)
    ids = Set{Symbol}()
    outputs = Dict{String, Symbol}()
    for node in dag.nodes
        node.id in ids &&
            return _reject(:E, dag.claim_type, :proof_dag, node.id,
                           "duplicate DAG node id";
                           certificate_hash=dag.root_hash)
        push!(ids, node.id)
        isempty(node.output_hash) &&
            return _reject(:E, dag.claim_type, :proof_dag, node.id,
                           "DAG node output hash is empty";
                           certificate_hash=dag.root_hash)
        haskey(outputs, node.output_hash) &&
            return _reject(:E, dag.claim_type, :proof_dag, node.id,
                           "DAG duplicate output hash";
                           certificate_hash=dag.root_hash,
                           details=Dict{Symbol, Any}(:first_node => String(outputs[node.output_hash])))
        outputs[node.output_hash] = node.id
    end
    final_nodes = [node for node in dag.nodes if node.checker === :final_accept]
    length(final_nodes) == 1 ||
        return _reject(:E, dag.claim_type, :proof_dag, :final_accept,
                       "DAG must contain exactly one final_accept node";
                       certificate_hash=dag.root_hash)
    for node in dag.nodes
        for input in node.inputs
            haskey(outputs, input) ||
                return _reject(:E, dag.claim_type, :proof_dag, node.id,
                               "DAG node depends on missing output hash";
                               certificate_hash=dag.root_hash,
                               details=Dict{Symbol, Any}(:missing_input => input))
        end
    end
    rejected_statuses = Set(Symbol[:rejected, :skipped, :unknown,
                                   :stale, :diagnostic_only])
    for node in dag.nodes
        if node.checker !== :final_accept && node.status in rejected_statuses
            return _reject(:E, dag.claim_type, :proof_dag, node.id,
                           "proof-relevant DAG node has rejected status";
                           certificate_hash=dag.root_hash,
                           details=Dict{Symbol, Any}(:status => String(node.status)))
        end
        haskey(dag.object_store, node.output_hash) ||
            return _reject(:E, dag.claim_type, :proof_dag, node.id,
                           "DAG node output is missing from object store";
                           certificate_hash=dag.root_hash)
        get(dag.object_store, node.output_hash, nothing) !=
            _dag_object_store(ProofNode[node])[node.output_hash] &&
            return _reject(:E, dag.claim_type, :proof_dag, node.id,
                           "DAG object store payload mismatch";
                           certificate_hash=dag.root_hash)
        checker_report = checker_module.run_dag_checker(node.checker, node, dag)
        checker_report.accepted ||
            return _reject(:E, dag.claim_type, :proof_dag, node.id,
                           checker_report.reason;
                           certificate_hash=dag.root_hash,
                           details=checker_report.details)
        checker_report.output_hash == node.output_hash ||
            return _reject(:E, dag.claim_type, :proof_dag, node.id,
                           "DAG checker output hash mismatch";
                           certificate_hash=dag.root_hash,
                           details=Dict{Symbol, Any}(:expected => node.output_hash,
                                                     :actual => checker_report.output_hash,
                                                     :checker => String(node.checker)))
    end
    expected = certificate_dag_hash_without_root(dag)
    canonical = CertificateDAG(dag.claim_type, dag.nodes, "", dag.schema_version)
    dag.root_hash == expected || dag.root_hash == canonical.root_hash ||
        return _reject(:E, dag.claim_type, :proof_dag, :root_hash,
                       "DAG root hash mismatch";
                       certificate_hash=dag.root_hash,
                       details=Dict{Symbol, Any}(:expected => expected,
                                                 :actual => dag.root_hash))
    return _accept(:E, dag.claim_type, :proof_dag, :root_hash;
                   certificate_hash=dag.root_hash,
                       details=Dict{Symbol, Any}(
                       :checker_calls => String.(checker_module.dag_checker_calls())))
end

function certificate_dag_json(dag::CertificateDAG)
    return (;
        claim_type=String(dag.claim_type),
        nodes=[proof_node_json(node) for node in dag.nodes],
        root_hash=dag.root_hash,
        schema_version=dag.schema_version,
        object_store=dag.object_store,
    )
end

function proof_node_json(node::ProofNode)
    serialized_status = node.status === :accepted ? :pending : node.status
    return (;
        id=String(node.id),
        kind=String(node.kind),
        inputs=node.inputs,
        output_hash=node.output_hash,
        checker=String(node.checker),
        status=String(serialized_status),
        typed_payload=_canonical_json_value(node.typed_payload),
        input_hashes=node.input_hashes,
        arithmetic_mode=String(node.arithmetic_mode),
        source_location=node.source_location,
        obligation_id=String(node.obligation_id),
        version=node.version,
    )
end

function certificate_dag_hash_without_root(dag::CertificateDAG)
    payload = (;
        claim_type=String(dag.claim_type),
        nodes=[proof_node_json(node) for node in dag.nodes],
        schema_version=dag.schema_version,
        object_store=dag.object_store,
    )
    return _sha256_payload(payload)
end

function parse_certificate_json_v3(json_text::AbstractString; strict::Bool=true)
    parsed = _read_json_document(json_text, "CertSDP v3 certificate")
    _require_object(parsed, "root")
    return parse_certificate_object_v3(parsed; strict)
end

function parse_certificate_object_v3(parsed; strict::Bool=true)
    strict && _strict_validate_top_object(parsed, _v3_top_level_keys(),
                                          "root")
    _reject_forbidden_trust_claims(parsed, "root")
    _require_value(parsed, :certsdp_certificate_version,
                   CERTSDP3_SCHEMA_VERSION,
                   "root.certsdp_certificate_version")
    cert_type = Symbol(_require_string(parsed, :certificate_type,
                                       "root.certificate_type"))
    certificate_id = _require_string(parsed, :certificate_id,
                                     "root.certificate_id")
    problem_hash = _require_string(parsed, :problem_hash,
                                   "root.problem_hash")
    _validate_sha256(problem_hash, "root.problem_hash")
    claim = _json_object_to_symbol_dict(_require_key(parsed, :claim, "root"))
    metadata = haskey(parsed, :metadata) ?
               _json_object_to_symbol_dict(_require_key(parsed, :metadata,
                                                        "root")) :
               Dict{Symbol, Any}()
    proof_object = _require_key(parsed, :proof, "root")
    dag_object = _require_key(parsed, :proof_dag, "root")
    proof = _parse_proof_for_type(cert_type, proof_object; strict)
    dag = _parse_certificate_dag(dag_object; strict)
    hash = _require_string(parsed, :hash, "root.hash")
    cert = V3Certificate(cert_type, certificate_id, problem_hash, claim, proof,
                         dag, metadata, hash)
    expected_hash = certificate_hash_v3(cert)
    hash == expected_hash ||
        throw(ArgumentError("root.hash mismatch: expected $hash, computed $expected_hash"))
    certificate_id == hash ||
        throw(ArgumentError("root.certificate_id must equal the canonical certificate hash"))
    problem_hash == _problem_hash_from_proof(cert_type, proof) ||
        throw(ArgumentError("root.problem_hash does not match proof matrix/problem hash"))
    return cert
end

function certificate_json_v3(cert::V3Certificate)
    return merge(_canonical_certificate_payload_v3(cert), (; hash=cert.hash))
end

function verify_certificate(cert::V3Certificate; io::Union{Nothing, IO}=nothing)
    report = if cert.certificate_type === :low_rank_psd_certificate
        verify_low_rank_psd(cert.proof.matrix, cert.proof.low_rank_proof)
    elseif cert.certificate_type === :chordal_psd_certificate
        verify_chordal_psd(cert.proof.matrix, cert.proof.chordal_proof)
    else
        _reject(:A, cert.certificate_type, :dispatch, :certificate_type,
                "unsupported CertSDP v3 certificate type";
                problem_hash=cert.problem_hash,
                certificate_hash=cert.hash)
    end
    if report.accepted
        dag_report = verify_proof_dag(cert.dag)
        if !dag_report.accepted
            report = dag_report
        end
    end
    report = _with_location(report; certificate_hash=cert.hash)
    _print_report(io, report)
    return report
end

function replay_file(path::AbstractString; strict::Bool=true,
                     io::Union{Nothing, IO}=nothing)
    text = read(path, String)
    parsed = try
        _read_json_document(text, "CertSDP replay artifact")
    catch err
        report = _reject(:F, :schema, :parse, :schema,
                         sprint(showerror, err); artifact_path=path)
        _print_report(io, report)
        return report
    end
    report = _replay_parsed_certificate_text(text, parsed; strict,
                                             artifact_path=path)
    _print_report(io, report)
    return report
end

function diagnose_file(path::AbstractString; strict::Bool=true)
    return replay_file(path; strict, io=nothing)
end

function _replay_parsed_certificate_text(text::AbstractString, parsed;
                                         strict::Bool=true,
                                         artifact_path::Union{Nothing, AbstractString}=nothing)
    try
        _require_object(parsed, "root")
        if haskey(parsed, :certsdp_certificate_version)
            cert = parse_certificate_json_v3(text; strict)
            report = verify_certificate(cert; io=nothing)
            return _with_location(report; artifact_path)
        elseif haskey(parsed, :certsdp_algebraic_psd_factor_version)
            matrix, proof, dag, certificate_hash =
                parse_algebraic_low_rank_psd_certificate_json(text)
            report = verify_algebraic_low_rank_psd(matrix, proof)
            report.accepted && (report = verify_proof_dag(dag))
            if report.accepted
                expected_hash = algebraic_low_rank_psd_certificate_hash(matrix,
                                                                        proof,
                                                                        dag)
                certificate_hash == expected_hash ||
                    return _reject(:D, :psd_factor_algebraic, :hash,
                                   :certificate_hash,
                                   "algebraic PSD certificate hash mismatch";
                                   problem_hash=matrix.hash,
                                   certificate_hash,
                                   artifact_path)
            end
            return _with_location(report; certificate_hash, artifact_path)
        elseif haskey(parsed, :certsdp_block_native_certificate_version)
            cert = parse_block_native_algebraic_certificate_json(text)
            return _with_location(verify_block_native_algebraic_certificate(cert);
                                  artifact_path)
        elseif haskey(parsed, :certsdp_primal_dual_certificate_version)
            cert = parse_primal_dual_optimality_certificate_json(text)
            return _with_location(verify_primal_dual_optimality(cert);
                                  artifact_path)
        elseif haskey(parsed, :certsdp_farkas_certificate_version)
            cert = parse_farkas_infeasibility_certificate_json(text)
            return _with_location(verify_farkas_infeasibility(cert);
                                  artifact_path)
        elseif haskey(parsed, :certsdp_sparse_sos_certificate_version)
            cert = parse_sparse_sos_certificate_json(text)
            return _with_location(verify_sparse_sos_certificate(cert);
                                  artifact_path)
        elseif haskey(parsed, :certsdp_quantum_certificate_version)
            cert = parse_quantum_bound_certificate_json(text)
            return _with_location(verify_quantum_bound_certificate(cert);
                                  artifact_path)
        elseif haskey(parsed, :certsdp_symmetry_certificate_version)
            cert = parse_block_diagonalization_certificate_json(text)
            return _with_location(verify_block_diagonalization_certificate(cert);
                                  artifact_path)
        end
        return _reject(:F, :schema, :parse, :schema,
                       "unsupported CertSDP replay artifact schema";
                       artifact_path)
    catch err
        return _reject(:F, :schema, :parse, :schema,
                       sprint(showerror, err); artifact_path)
    end
end

function diagnostic_report_json(report::DiagnosticReport)
    return (;
        certsdp_report_version=CERTSDP3_SCHEMA_VERSION,
        accepted=report.accepted,
        gate=String(report.gate),
        family=String(report.family),
        stage=String(report.stage),
        reason=report.reason,
        obligation_id=String(report.obligation_id),
        problem_hash=report.problem_hash,
        certificate_hash=report.certificate_hash,
        block_id=isnothing(report.block_id) ? nothing : String(report.block_id),
        clique_id=isnothing(report.clique_id) ? nothing : String(report.clique_id),
        separator_id=isnothing(report.separator_id) ? nothing : String(report.separator_id),
        artifact_path=report.artifact_path,
        details=_jsonify(report.details),
    )
end

function diagnostic_report_text(report::DiagnosticReport)
    lines = String[
        report.accepted ? "CertSDP replay: accepted" : "CertSDP replay: rejected",
        "gate: $(report.gate)",
        "family: $(report.family)",
        "stage: $(report.stage)",
        "obligation_id: $(report.obligation_id)",
        "reason: $(report.reason)",
    ]
    isnothing(report.problem_hash) || push!(lines, "problem_hash: $(report.problem_hash)")
    isnothing(report.certificate_hash) ||
        push!(lines, "certificate_hash: $(report.certificate_hash)")
    isnothing(report.clique_id) || push!(lines, "clique_id: $(report.clique_id)")
    isnothing(report.separator_id) ||
        push!(lines, "separator_id: $(report.separator_id)")
    return join(lines, "\n") * "\n"
end

function diagnostic_report_html(report::DiagnosticReport)
    escaped_reason = _escape_html(report.reason)
    return """
<!doctype html>
<html><head><meta charset=\"utf-8\"><title>CertSDP Diagnostic</title></head>
<body>
<h1>CertSDP Diagnostic</h1>
<p><strong>Status:</strong> $(report.accepted ? "accepted" : "rejected")</p>
<p><strong>Gate:</strong> $(report.gate)</p>
<p><strong>Family:</strong> $(report.family)</p>
<p><strong>Stage:</strong> $(report.stage)</p>
<p><strong>Obligation:</strong> $(report.obligation_id)</p>
<p><strong>Reason:</strong> $(escaped_reason)</p>
</body></html>
"""
end

function validate_certificate_schema_v3(json_text::AbstractString)
    parse_certificate_json_v3(json_text; strict=true)
    return true
end

function validate_problem_schema_v3(json_text::AbstractString)
    parsed = _read_json_document(json_text, "CertSDP v3 problem")
    _require_object(parsed, "root")
    _require_value(parsed, :certsdp_problem_version, CERTSDP3_SCHEMA_VERSION,
                   "root.certsdp_problem_version")
    type = Symbol(_require_string(parsed, :type, "root.type"))
    type === :sparse_lmi ||
        throw(ArgumentError("root.type must be `sparse_lmi` for this kernel slice"))
    parse_sparse_affine_lmi_object(_require_key(parsed, :problem, "root");
                                   strict=true)
    return true
end

function parse_sparse_matrix_object(object; strict::Bool=true,
                                    path::AbstractString="matrix")
    strict && _strict_validate_top_object(object,
                                          Set(Symbol[:n, :entries, :hash]),
                                          path)
    n = _require_integer(object, :n, "$path.n")
    entries_value = _require_key(object, :entries, path)
    _require_array(entries_value, "$path.entries")
    entries = Tuple{Int, Int, Rational{BigInt}}[]
    for (k, entry) in enumerate(entries_value)
        entry_path = "$path.entries[$k]"
        _require_object(entry, entry_path)
        strict && _strict_validate_top_object(entry,
                                              Set(Symbol[:i, :j, :value]),
                                              entry_path)
        push!(entries, (_require_integer(entry, :i, "$entry_path.i"),
                        _require_integer(entry, :j, "$entry_path.j"),
                        _parse_rational_string(_require_key(entry, :value,
                                                            entry_path),
                                               "$entry_path.value")))
    end
    matrix = SparseSymmetricRationalMatrix(n, entries)
    supplied = _require_string(object, :hash, "$path.hash")
    supplied == matrix.hash ||
        throw(ArgumentError("$path.hash mismatch: expected $supplied, computed $(matrix.hash)"))
    return matrix
end

function sparse_matrix_json(matrix::SparseSymmetricRationalMatrix)
    return (;
        n=matrix.n,
        entries=[(; i=i, j=j, value=rational_string(value))
                 for (i, j, value) in matrix.entries],
        hash=matrix.hash,
    )
end

function sparse_affine_lmi_json(problem::SparseAffineLMI)
    return (;
        variables=String.(problem.variables),
        A0=sparse_matrix_json(problem.A0),
        A=[sparse_matrix_json(matrix) for matrix in problem.A],
        blocks=[_block_hash_payload(block) for block in problem.blocks],
        metadata=_jsonify(problem.metadata),
        hash=problem.hash,
    )
end

function parse_sparse_affine_lmi_object(object; strict::Bool=true)
    strict && _strict_validate_top_object(object,
                                          Set(Symbol[:variables, :A0, :A, :blocks,
                                                     :metadata, :hash]),
                                          "problem")
    variables_value = _require_key(object, :variables, "problem")
    _require_array(variables_value, "problem.variables")
    variables = Symbol[]
    for (i, value) in enumerate(variables_value)
        value isa AbstractString ||
            throw(ArgumentError("problem.variables[$i] must be a string"))
        push!(variables, Symbol(String(value)))
    end
    length(unique(variables)) == length(variables) ||
        throw(ArgumentError("problem.variables must be unique"))
    A0 = parse_sparse_matrix_object(_require_key(object, :A0, "problem");
                                    strict, path="problem.A0")
    A_value = _require_key(object, :A, "problem")
    _require_array(A_value, "problem.A")
    A = [parse_sparse_matrix_object(entry; strict,
                                    path="problem.A[$i]")
         for (i, entry) in enumerate(A_value)]
    metadata = haskey(object, :metadata) ?
               _json_object_to_symbol_dict(_require_key(object, :metadata,
                                                        "problem")) :
               Dict{Symbol, Any}()
    problem = SparseAffineLMI(variables, A0, A; metadata)
    supplied = _require_string(object, :hash, "problem.hash")
    supplied == problem.hash ||
        throw(ArgumentError("problem.hash mismatch: expected $supplied, computed $(problem.hash)"))
    return problem
end

function rational_string(value::Rational{BigInt})
    den = denominator(value)
    den == 1 && return string(numerator(value))
    return string(numerator(value), "/", den)
end

function rational_string(value::Integer)
    return string(value)
end

function _parse_proof_for_type(cert_type::Symbol, proof_object; strict::Bool=true)
    if cert_type === :low_rank_psd_certificate
        strict && _strict_validate_top_object(proof_object,
                                              Set(Symbol[:matrix, :low_rank_proof]),
                                              "root.proof")
        matrix = parse_sparse_matrix_object(_require_key(proof_object, :matrix,
                                                         "root.proof");
                                            strict, path="root.proof.matrix")
        low_rank = _parse_low_rank_proof_object(_require_key(proof_object,
                                                             :low_rank_proof,
                                                             "root.proof"),
                                                matrix; strict)
        return (; matrix, low_rank_proof=low_rank)
    elseif cert_type === :chordal_psd_certificate
        strict && _strict_validate_top_object(proof_object,
                                              Set(Symbol[:matrix, :chordal_proof]),
                                              "root.proof")
        matrix = parse_sparse_matrix_object(_require_key(proof_object, :matrix,
                                                         "root.proof");
                                            strict, path="root.proof.matrix")
        chordal = _parse_chordal_proof_object(_require_key(proof_object,
                                                           :chordal_proof,
                                                           "root.proof"),
                                              matrix; strict)
        return (; matrix, chordal_proof=chordal)
    end
    throw(ArgumentError("unsupported CertSDP v3 certificate_type `$cert_type`"))
end

function _parse_low_rank_proof_object(object,
                                      matrix::SparseSymmetricRationalMatrix;
                                      strict::Bool=true,
                                      path::AbstractString="root.proof.low_rank_proof")
    strict && _strict_validate_top_object(object,
                                          Set(Symbol[:field, :matrix_hash, :factor,
                                                     :diagonal,
                                                     :identity_proof_hash]),
                                          path)
    field = Symbol(_require_string(object, :field, "$path.field"))
    matrix_hash = _require_string(object, :matrix_hash, "$path.matrix_hash")
    matrix_hash == matrix.hash ||
        throw(ArgumentError("$path.matrix_hash does not match matrix hash"))
    factor_value = _require_key(object, :factor, path)
    diagonal_value = _require_key(object, :diagonal, path)
    factor = _parse_rational_row_matrix(factor_value, "$path.factor")
    _require_array(diagonal_value, "$path.diagonal")
    diagonal = [_parse_rational_string(value, "$path.diagonal[$i]")
                for (i, value) in enumerate(diagonal_value)]
    proof = ExactLowRankPSDProof(field, matrix_hash, factor, diagonal,
                                 _require_string(object, :identity_proof_hash,
                                                 "$path.identity_proof_hash"))
    proof.identity_proof_hash == low_rank_identity_hash(proof) ||
        throw(ArgumentError("$path.identity_proof_hash mismatch"))
    return proof
end

function _parse_low_rank_proof_object_without_matrix(object;
                                                     strict::Bool=true,
                                                     path::AbstractString="low_rank_proof")
    strict && _strict_validate_top_object(object,
                                          Set(Symbol[:field, :matrix_hash, :factor,
                                                     :diagonal,
                                                     :identity_proof_hash]),
                                          path)
    factor_value = _require_key(object, :factor, path)
    diagonal_value = _require_key(object, :diagonal, path)
    factor = _parse_rational_row_matrix(factor_value, "$path.factor")
    _require_array(diagonal_value, "$path.diagonal")
    diagonal = [_parse_rational_string(value, "$path.diagonal[$i]")
                for (i, value) in enumerate(diagonal_value)]
    proof = ExactLowRankPSDProof(Symbol(_require_string(object, :field,
                                                        "$path.field")),
                                 _require_string(object, :matrix_hash,
                                                 "$path.matrix_hash"),
                                 factor,
                                 diagonal,
                                 _require_string(object, :identity_proof_hash,
                                                 "$path.identity_proof_hash"))
    proof.identity_proof_hash == low_rank_identity_hash(proof) ||
        throw(ArgumentError("$path.identity_proof_hash mismatch"))
    return proof
end

function _parse_chordal_proof_object(object,
                                     matrix::SparseSymmetricRationalMatrix;
                                     strict::Bool=true)
    path = "root.proof.chordal_proof"
    strict && _strict_validate_top_object(object,
                                          Set(Symbol[:theorem_tag, :matrix_hash,
                                                     :structure,
                                                     :clique_proofs,
                                                     :separator_proofs,
                                                     :proof_hash]),
                                          path)
    theorem_tag = Symbol(_require_string(object, :theorem_tag,
                                         "$path.theorem_tag"))
    matrix_hash = _require_string(object, :matrix_hash, "$path.matrix_hash")
    matrix_hash == matrix.hash ||
        throw(ArgumentError("$path.matrix_hash does not match matrix hash"))
    structure = _parse_chordal_structure_object(_require_key(object, :structure,
                                                             path);
                                               strict)
    clique_values = _require_key(object, :clique_proofs, path)
    _require_array(clique_values, "$path.clique_proofs")
    clique_proofs = [parse_clique_psd_proof(entry; strict,
                                            path="$path.clique_proofs[$i]")
                     for (i, entry) in enumerate(clique_values)]
    separator_values = _require_key(object, :separator_proofs, path)
    _require_array(separator_values, "$path.separator_proofs")
    separator_proofs = [parse_separator_proof(entry; strict,
                                              path="$path.separator_proofs[$i]")
                        for (i, entry) in enumerate(separator_values)]
    proof = ChordalPSDProof(theorem_tag, matrix_hash, structure, clique_proofs,
                            separator_proofs,
                            _require_string(object, :proof_hash,
                                            "$path.proof_hash"))
    proof.proof_hash == chordal_proof_hash(proof) ||
        throw(ArgumentError("$path.proof_hash mismatch"))
    return proof
end

function _parse_chordal_structure_object(object; strict::Bool=true)
    path = "root.proof.chordal_proof.structure"
    strict && _strict_validate_top_object(object,
                                          Set(Symbol[:n, :cliques, :separators,
                                                     :graph_hash]),
                                          path)
    n = _require_integer(object, :n, "$path.n")
    cliques_value = _require_key(object, :cliques, path)
    separators_value = _require_key(object, :separators, path)
    _require_array(cliques_value, "$path.cliques")
    _require_array(separators_value, "$path.separators")
    structure = ChordalPSDStructure(n, [collect(clique) for clique in cliques_value],
                                    [collect(separator)
                                     for separator in separators_value])
    supplied = _require_string(object, :graph_hash, "$path.graph_hash")
    supplied == structure.graph_hash ||
        throw(ArgumentError("$path.graph_hash mismatch"))
    return structure
end

function parse_clique_psd_proof(object; strict::Bool=true,
                                path::AbstractString="clique_proof")
    strict && _strict_validate_top_object(object,
                                          Set(Symbol[:id, :clique_index,
                                                     :vertices, :matrix,
                                                     :psd_proof]),
                                          path)
    id = Symbol(_require_string(object, :id, "$path.id"))
    clique_index = _require_integer(object, :clique_index,
                                    "$path.clique_index")
    vertices_value = _require_key(object, :vertices, path)
    _require_array(vertices_value, "$path.vertices")
    vertices = [Int(value) for value in vertices_value]
    matrix = parse_sparse_matrix_object(_require_key(object, :matrix, path);
                                        strict, path="$path.matrix")
    proof = _parse_low_rank_proof_object(_require_key(object, :psd_proof,
                                                      path),
                                         matrix; strict,
                                         path="$path.psd_proof")
    return CliquePSDProof(id, clique_index, vertices, matrix, proof)
end

function parse_separator_proof(object; strict::Bool=true,
                               path::AbstractString="separator_proof")
    strict && _strict_validate_top_object(object,
                                          Set(Symbol[:id, :left_clique,
                                                     :right_clique, :vertices,
                                                     :value_hash]),
                                          path)
    vertices_value = _require_key(object, :vertices, path)
    _require_array(vertices_value, "$path.vertices")
    return SeparatorConsistencyProof(Symbol(_require_string(object, :id,
                                                            "$path.id")),
                                     _require_integer(object, :left_clique,
                                                      "$path.left_clique"),
                                     _require_integer(object, :right_clique,
                                                      "$path.right_clique"),
                                     [Int(value) for value in vertices_value],
                                     _require_string(object, :value_hash,
                                                     "$path.value_hash"))
end

function _parse_certificate_dag(object; strict::Bool=true)
    strict && _strict_validate_top_object(object,
                                          Set(Symbol[:claim_type, :nodes,
                                                     :root_hash,
                                                     :schema_version,
                                                     :object_store]),
                                          "root.proof_dag")
    if strict && !haskey(object, :object_store)
        throw(ArgumentError("root.proof_dag.object_store missing"))
    end
    nodes_value = _require_key(object, :nodes, "root.proof_dag")
    _require_array(nodes_value, "root.proof_dag.nodes")
    nodes = ProofNode[_parse_proof_node(node;
                                        strict,
                                        path="root.proof_dag.nodes[$i]")
                      for (i, node) in enumerate(nodes_value)]
    store_object = _require_key(object, :object_store, "root.proof_dag")
    store = _canonical_object_store_from_json(store_object)
    dag = CertificateDAG(Symbol(_require_string(object, :claim_type,
                                                "root.proof_dag.claim_type")),
                         nodes,
                         _require_string(object, :root_hash,
                                         "root.proof_dag.root_hash"),
                         _require_string(object, :schema_version,
                                         "root.proof_dag.schema_version"),
                         store)
    expected_store = _dag_object_store(nodes)
    store == expected_store ||
        throw(ArgumentError("root.proof_dag.object_store mismatch"))
    dag.root_hash == String(_require_key(object, :root_hash, "root.proof_dag")) ||
        throw(ArgumentError("root.proof_dag.root_hash mismatch"))
    canonical = CertificateDAG(dag.claim_type, dag.nodes, "",
                               dag.schema_version)
    dag.root_hash == canonical.root_hash ||
        throw(ArgumentError("root.proof_dag.root_hash mismatch"))
    Set(keys(dag.object_store)) == Set(keys(canonical.object_store)) ||
        throw(ArgumentError("root.proof_dag.object_store mismatch"))
    return dag
end

function _canonical_object_store_from_json(object)
    _require_object(object, "root.proof_dag.object_store")
    store = Dict{String, Any}()
    for key in keys(object)
        name = String(key)
        store[name] = _jsonify(_object_value(object, Symbol(key)))
    end
    return store
end

function _parse_proof_node(object; strict::Bool=true, path::AbstractString)
    strict && _strict_validate_top_object(object,
                                          Set(Symbol[:id, :kind, :inputs,
                                                     :output_hash, :checker,
                                                     :status, :typed_payload,
                                                     :input_hashes,
                                                     :arithmetic_mode,
                                                     :source_location,
                                                     :obligation_id,
                                                     :version]),
                                          path)
    if strict
        for key in (:typed_payload, :input_hashes, :arithmetic_mode,
                    :obligation_id, :version)
            haskey(object, key) ||
                throw(ArgumentError("$path.$(String(key)) missing"))
        end
    end
    inputs_value = _require_key(object, :inputs, path)
    _require_array(inputs_value, "$path.inputs")
    input_hashes_value = haskey(object, :input_hashes) ?
                         _require_key(object, :input_hashes, path) :
                         inputs_value
    _require_array(input_hashes_value, "$path.input_hashes")
    payload = haskey(object, :typed_payload) ?
              _json_object_to_symbol_dict(_require_key(object, :typed_payload,
                                                       path)) :
              Dict{Symbol, Any}()
    source_location = haskey(object, :source_location) &&
                      object[:source_location] !== nothing ?
                      _require_string(object, :source_location,
                                      "$path.source_location") :
                      nothing
    return ProofNode(Symbol(_require_string(object, :id, "$path.id")),
                     Symbol(_require_string(object, :kind, "$path.kind")),
                     [String(value) for value in inputs_value],
                     _require_string(object, :output_hash,
                                     "$path.output_hash"),
                     Symbol(_require_string(object, :checker,
                                            "$path.checker")),
                     Symbol(_require_string(object, :status,
                                            "$path.status"));
                     typed_payload=payload,
                     input_hashes=[String(value) for value in input_hashes_value],
                     arithmetic_mode=Symbol(_require_string(object,
                                                            :arithmetic_mode,
                                                            "$path.arithmetic_mode")),
                     source_location=source_location,
                     obligation_id=Symbol(_require_string(object,
                                                          :obligation_id,
                                                          "$path.obligation_id")),
                     version=_require_string(object, :version,
                                             "$path.version"))
end

function parse_quantum_bound_certificate_json(json_text::AbstractString)
    parsed = _read_json_document(json_text, "CertSDP quantum certificate")
    _strict_validate_top_object(parsed,
                                Set(Symbol[:certsdp_quantum_certificate_version,
                                           :problem,
                                           :moment_certificate,
                                           :objective_terms,
                                           :bound,
                                           :proof_dag,
                                           :certificate_hash]),
                                "root")
    _reject_forbidden_trust_claims(parsed, "root")
    _require_value(parsed, :certsdp_quantum_certificate_version,
                   CERTSDP3_SCHEMA_VERSION,
                   "root.certsdp_quantum_certificate_version")
    problem = _parse_npa_problem_object(_require_key(parsed, :problem, "root"))
    moment = _parse_nc_moment_certificate_object(_require_key(parsed, :moment_certificate,
                                                              "root"),
                                                problem)
    objective = _parse_nc_terms(_require_key(parsed, :objective_terms, "root"),
                                "root.objective_terms")
    cert = make_quantum_bound_certificate(problem,
                                          moment,
                                          objective,
                                          _parse_rational_string(_require_key(parsed, :bound, "root"),
                                                                 "root.bound"))
    dag = _parse_certificate_dag(_require_key(parsed, :proof_dag, "root");
                                 strict=true)
    hash = _require_string(parsed, :certificate_hash, "root.certificate_hash")
    expected_dag = make_quantum_bound_certificate(problem,
                                                  moment,
                                                  objective,
                                                  _parse_rational_string(_require_key(parsed, :bound, "root"),
                                                                         "root.bound")).dag
    dag.root_hash == expected_dag.root_hash ||
        throw(ArgumentError("root.proof_dag does not match quantum replay obligations"))
    hash == cert.certificate_hash ||
        throw(ArgumentError("root.certificate_hash mismatch"))
    return QuantumBoundCertificate(cert.problem,
                                   cert.moment_certificate,
                                   cert.objective_terms,
                                   cert.bound,
                                   hash,
                                   dag)
end

function parse_block_native_algebraic_certificate_json(json_text::AbstractString)
    parsed = _read_json_document(json_text, "CertSDP block-native algebraic certificate")
    _strict_validate_top_object(parsed,
                                Set(Symbol[:certsdp_block_native_certificate_version,
                                           :problem_hash,
                                           :incidence,
                                           :active_block_proofs,
                                           :inactive_psd_proofs,
                                           :proof_dag,
                                           :certificate_hash]),
                                "root")
    _reject_forbidden_trust_claims(parsed, "root")
    _require_value(parsed, :certsdp_block_native_certificate_version,
                   CERTSDP3_SCHEMA_VERSION,
                   "root.certsdp_block_native_certificate_version")
    incidence = _parse_block_native_incidence_system_object(_require_key(parsed,
                                                                         :incidence,
                                                                         "root"))
    problem_hash = _require_string(parsed, :problem_hash, "root.problem_hash")
    problem_hash == incidence.problem_hash ||
        throw(ArgumentError("root.problem_hash does not match incidence problem hash"))
    active_values = _require_key(parsed, :active_block_proofs, "root")
    inactive_values = _require_key(parsed, :inactive_psd_proofs, "root")
    _require_array(active_values, "root.active_block_proofs")
    _require_array(inactive_values, "root.inactive_psd_proofs")
    active = Dict{Int, BlockNativeActiveBlockProof}()
    for (i, value) in enumerate(active_values)
        proof = _parse_block_native_active_block_proof(value,
                                                       "root.active_block_proofs[$i]")
        haskey(active, proof.block_index) &&
            throw(ArgumentError("duplicate active block proof for block $(proof.block_index)"))
        active[proof.block_index] = proof
    end
    inactive = Dict{Int, BlockNativeInactivePSDProof}()
    for (i, value) in enumerate(inactive_values)
        proof = _parse_block_native_inactive_psd_proof(value,
                                                       "root.inactive_psd_proofs[$i]")
        haskey(inactive, proof.block_index) &&
            throw(ArgumentError("duplicate inactive PSD proof for block $(proof.block_index)"))
        inactive[proof.block_index] = proof
    end
    cert = BlockNativeAlgebraicCertificate(problem_hash,
                                           incidence,
                                           active,
                                           inactive,
                                           _require_string(parsed,
                                                           :certificate_hash,
                                                           "root.certificate_hash"))
    cert.certificate_hash == block_native_algebraic_certificate_hash(cert) ||
        throw(ArgumentError("root.certificate_hash mismatch"))
    dag = _parse_certificate_dag(_require_key(parsed, :proof_dag, "root");
                                 strict=true)
    return cert
end

function parse_primal_dual_optimality_certificate_json(json_text::AbstractString)
    parsed = _read_json_document(json_text, "CertSDP primal-dual certificate")
    _validate_object_keys(parsed,
                          Set(Symbol[:certsdp_primal_dual_certificate_version,
                                     :problem_hash, :primal, :dual, :gap,
                                     :proof_dag, :certificate_hash]),
                          Set(Symbol[:problem]),
                          "root")
    _reject_forbidden_trust_claims(parsed, "root")
    _require_value(parsed, :certsdp_primal_dual_certificate_version,
                   CERTSDP3_SCHEMA_VERSION,
                   "root.certsdp_primal_dual_certificate_version")
    problem_hash = _require_string(parsed, :problem_hash, "root.problem_hash")
    problem = haskey(parsed, :problem) ?
              _parse_exact_conic_problem_object(_require_key(parsed, :problem, "root"),
                                                "root.problem") :
              nothing
    primal = _parse_primal_feasibility_object(_require_key(parsed, :primal,
                                                           "root"),
                                              "root.primal")
    dual = _parse_dual_feasibility_object(_require_key(parsed, :dual, "root"),
                                          "root.dual")
    if !isnothing(problem)
        primal = PrimalFeasibilityCertificate(primal.problem_hash, problem,
                                              primal.primal_vector,
                                              primal.affine_lhs,
                                              primal.affine_rhs,
                                              primal.cone_matrices,
                                              primal.cone_proofs,
                                              primal.objective_value)
        dual = DualFeasibilityCertificate(dual.problem_hash, problem,
                                          dual.dual_variables,
                                          dual.affine_lhs,
                                          dual.affine_rhs,
                                          dual.cone_matrices,
                                          dual.cone_proofs,
                                          dual.objective_value)
    end
    problem_hash == primal.problem_hash == dual.problem_hash ||
        throw(ArgumentError("root.problem_hash does not match primal/dual problem hash"))
    dag = _parse_certificate_dag(_require_key(parsed, :proof_dag, "root");
                                 strict=true)
    cert = PrimalDualOptimalityCertificate(problem_hash,
                                           primal,
                                           dual,
                                           _parse_rational_string(_require_key(parsed,
                                                                               :gap,
                                                                               "root"),
                                                                  "root.gap"),
                                           _require_string(parsed,
                                                           :certificate_hash,
                                                           "root.certificate_hash"),
                                           dag)
    cert.certificate_hash == primal_dual_optimality_hash(cert) ||
        throw(ArgumentError("root.certificate_hash mismatch"))
    return cert
end

function parse_farkas_infeasibility_certificate_json(json_text::AbstractString)
    parsed = _read_json_document(json_text, "CertSDP Farkas certificate")
    _validate_object_keys(parsed,
                          Set(Symbol[:certsdp_farkas_certificate_version,
                                     :problem_hash,
                                     :multiplier_identity_lhs,
                                     :multiplier_identity_rhs,
                                     :cone_proofs,
                                     :contradiction_lhs,
                                     :contradiction_rhs,
                                     :proof_dag,
                                     :certificate_hash]),
                          Set(Symbol[:problem, :dual_variables]),
                          "root")
    _reject_forbidden_trust_claims(parsed, "root")
    _require_value(parsed, :certsdp_farkas_certificate_version,
                   CERTSDP3_SCHEMA_VERSION,
                   "root.certsdp_farkas_certificate_version")
    problem_hash = _require_string(parsed, :problem_hash, "root.problem_hash")
    problem = haskey(parsed, :problem) ?
              _parse_exact_conic_problem_object(_require_key(parsed, :problem, "root"),
                                                "root.problem") :
              nothing
    dual_variables = haskey(parsed, :dual_variables) ?
                     SparseSymmetricRationalMatrix[
                         parse_sparse_matrix_object(matrix_object; strict=true,
                                                    path="root.dual_variables[$i]")
                         for (i, matrix_object) in enumerate(_require_key(parsed,
                                                                          :dual_variables,
                                                                          "root"))
                     ] :
                     SparseSymmetricRationalMatrix[]
    cone_proofs = ExactLowRankPSDProof[]
    for (i, proof_object) in enumerate(_require_key(parsed, :cone_proofs, "root"))
        push!(cone_proofs, _parse_low_rank_proof_object_without_matrix(proof_object;
                                                                       strict=true,
                                                                       path="root.cone_proofs[$i]"))
    end
    lhs = [_parse_rational_string(value, "root.multiplier_identity_lhs[$i]")
           for (i, value) in enumerate(_require_key(parsed,
                                                    :multiplier_identity_lhs,
                                                    "root"))]
    rhs = [_parse_rational_string(value, "root.multiplier_identity_rhs[$i]")
           for (i, value) in enumerate(_require_key(parsed,
                                                    :multiplier_identity_rhs,
                                                    "root"))]
    dag = _parse_certificate_dag(_require_key(parsed, :proof_dag, "root");
                                 strict=true)
    cert = FarkasInfeasibilityCertificate(problem_hash,
                                          problem,
                                          dual_variables,
                                          lhs,
                                          rhs,
                                          cone_proofs,
                                          _parse_rational_string(_require_key(parsed,
                                                                              :contradiction_lhs,
                                                                              "root"),
                                                                 "root.contradiction_lhs"),
                                          _parse_rational_string(_require_key(parsed,
                                                                              :contradiction_rhs,
                                                                              "root"),
                                                                 "root.contradiction_rhs"),
                                          _require_string(parsed,
                                                          :certificate_hash,
                                                          "root.certificate_hash"),
                                          dag)
    cert.certificate_hash == farkas_infeasibility_hash(cert) ||
        throw(ArgumentError("root.certificate_hash mismatch"))
    return cert
end

function parse_algebraic_low_rank_psd_certificate_json(json_text::AbstractString)
    parsed = _read_json_document(json_text, "CertSDP algebraic PSD certificate")
    _strict_validate_top_object(parsed,
                                Set(Symbol[:certsdp_algebraic_psd_factor_version,
                                           :matrix, :field, :factor, :diagonal,
                                           :sign_certificates,
                                           :identity_proof_hash, :proof_dag,
                                           :certificate_hash]),
                                "root")
    _reject_forbidden_trust_claims(parsed, "root")
    _require_value(parsed, :certsdp_algebraic_psd_factor_version,
                   CERTSDP3_SCHEMA_VERSION,
                   "root.certsdp_algebraic_psd_factor_version")
    matrix = parse_sparse_matrix_object(_require_key(parsed, :matrix, "root");
                                        strict=true,
                                        path="root.matrix")
    field = _parse_algebraic_field_certificate_object(_require_key(parsed,
                                                                   :field,
                                                                   "root"),
                                                      "root.field")
    factor_rows = _require_key(parsed, :factor, "root")
    _require_array(factor_rows, "root.factor")
    factor = Vector{AlgebraicElement}[]
    for (i, row) in enumerate(factor_rows)
        _require_array(row, "root.factor[$i]")
        push!(factor, [_parse_algebraic_element_object(value, field,
                                                       "root.factor[$i][$j]")
                       for (j, value) in enumerate(row)])
    end
    diagonal = [_parse_algebraic_element_object(value, field,
                                               "root.diagonal[$i]")
                for (i, value) in enumerate(_require_key(parsed, :diagonal,
                                                         "root"))]
    sign_values = _require_key(parsed, :sign_certificates, "root")
    _require_array(sign_values, "root.sign_certificates")
    length(sign_values) == length(diagonal) ||
        throw(ArgumentError("root.sign_certificates length mismatch"))
    for (i, sign_certificate) in enumerate(sign_values)
        _verify_algebraic_sign_certificate_object(sign_certificate,
                                                  diagonal[i],
                                                  field,
                                                  "root.sign_certificates[$i]")
    end
    proof = ExactAlgebraicLowRankPSDProof(matrix, field, factor, diagonal)
    supplied_identity = _require_string(parsed, :identity_proof_hash,
                                        "root.identity_proof_hash")
    supplied_identity == proof.identity_proof_hash ||
        throw(ArgumentError("root.identity_proof_hash mismatch"))
    dag = _parse_certificate_dag(_require_key(parsed, :proof_dag, "root");
                                 strict=true)
    supplied_hash = _require_string(parsed, :certificate_hash,
                                    "root.certificate_hash")
    supplied_hash == algebraic_low_rank_psd_certificate_hash(matrix, proof, dag) ||
        throw(ArgumentError("root.certificate_hash mismatch"))
    return matrix, proof, dag, supplied_hash
end

function _verify_algebraic_sign_certificate_object(object,
                                                   element::AlgebraicElement,
                                                   field::AlgebraicFieldCertificate,
                                                   path::AbstractString)
    _strict_validate_top_object(object,
                                Set(Symbol[:method,
                                           :field_hash,
                                           :expression,
                                           :isolating_interval,
                                           :roots_in_interval,
                                           :sign,
                                           :sign_certificate_hash]),
                                path)
    _require_string(object, :method, "$path.method") == "sturm_interval_root_exclusion" ||
        throw(ArgumentError("$path.method is unsupported"))
    _require_string(object, :field_hash, "$path.field_hash") == field.field_hash ||
        throw(ArgumentError("$path.field_hash mismatch"))
    expected = algebraic_sign_certificate_json(element, field)
    expected_hash = String(expected.sign_certificate_hash)
    _require_string(object, :sign_certificate_hash, "$path.sign_certificate_hash") == expected_hash ||
        throw(ArgumentError("$path.sign_certificate_hash mismatch"))
    String(_require_key(object, :sign, path)) == String(expected.sign) ||
        throw(ArgumentError("$path.sign mismatch"))
    Int(_require_key(object, :roots_in_interval, path)) == Int(expected.roots_in_interval) ||
        throw(ArgumentError("$path.roots_in_interval mismatch"))
    String.(_require_key(object, :expression, path)) == String.(expected.expression) ||
        throw(ArgumentError("$path.expression mismatch"))
    String.(_require_key(object, :isolating_interval, path)) == String.(expected.isolating_interval) ||
        throw(ArgumentError("$path.isolating_interval mismatch"))
    return true
end

function parse_sparse_sos_certificate_json(json_text::AbstractString)
    parsed = _read_json_document(json_text, "CertSDP sparse SOS certificate")
    _strict_validate_top_object(parsed,
                                Set(Symbol[:certsdp_sparse_sos_certificate_version,
                                           :problem, :sos_blocks,
                                           :putinar, :proof_dag,
                                           :certificate_hash]),
                                "root")
    _reject_forbidden_trust_claims(parsed, "root")
    _require_value(parsed, :certsdp_sparse_sos_certificate_version,
                   CERTSDP3_SCHEMA_VERSION,
                   "root.certsdp_sparse_sos_certificate_version")
    problem = _parse_sparse_sos_problem_object(_require_key(parsed,
                                                            :problem,
                                                            "root"))
    sos_blocks = SparseSOSBlock[]
    for (i, block_object) in enumerate(_require_key(parsed, :sos_blocks,
                                                    "root"))
        push!(sos_blocks,
              _parse_sparse_sos_block_object(block_object,
                                             "root.sos_blocks[$i]"))
    end
    putinar_value = _require_key(parsed, :putinar, "root")
    putinar = isnothing(putinar_value) ? nothing :
              _parse_putinar_certificate_object(putinar_value,
                                                "root.putinar")
    dag = _parse_certificate_dag(_require_key(parsed, :proof_dag, "root");
                                 strict=true)
    hash = _require_string(parsed, :certificate_hash, "root.certificate_hash")
    cert = SparseSOSCertificate(problem, sos_blocks, putinar, hash, dag)
    cert.certificate_hash == sparse_sos_certificate_hash(cert) ||
        throw(ArgumentError("root.certificate_hash mismatch"))
    return cert
end

function parse_block_diagonalization_certificate_json(json_text::AbstractString)
    parsed = _read_json_document(json_text, "CertSDP symmetry certificate")
    _strict_validate_top_object(parsed,
                                Set(Symbol[:certsdp_symmetry_certificate_version,
                                           :problem_hash, :group,
                                           :orbit_basis, :projection_blocks,
                                           :projector_matrices,
                                           :projector_semantics,
                                           :original_matrix,
                                           :reconstructed_matrix,
                                           :proof_dag,
                                           :certificate_hash]),
                                "root")
    _reject_forbidden_trust_claims(parsed, "root")
    _require_value(parsed, :certsdp_symmetry_certificate_version,
                   CERTSDP3_SCHEMA_VERSION,
                   "root.certsdp_symmetry_certificate_version")
    group = _parse_symmetry_group_object(_require_key(parsed, :group, "root"))
    orbit = _parse_orbit_basis_object(_require_key(parsed, :orbit_basis, "root"))
    blocks = [parse_sparse_matrix_object(entry; strict=true,
                                         path="root.projection_blocks[$i]")
              for (i, entry) in enumerate(_require_key(parsed,
                                                       :projection_blocks,
                                                       "root"))]
    projectors = [parse_sparse_matrix_object(entry; strict=true,
                                             path="root.projector_matrices[$i]")
                  for (i, entry) in enumerate(_require_key(parsed,
                                                           :projector_matrices,
                                                           "root"))]
    semantics = _require_key(parsed, :projector_semantics, "root")
    _strict_validate_top_object(semantics,
                                Set(Symbol[:idempotence,
                                           :orthogonality,
                                           :completeness]),
                                "root.projector_semantics")
    Bool(semantics[:idempotence]) && Bool(semantics[:orthogonality]) &&
        Bool(semantics[:completeness]) ||
        throw(ArgumentError("root.projector_semantics must assert idempotence, orthogonality, and completeness"))
    original = parse_sparse_matrix_object(_require_key(parsed,
                                                       :original_matrix,
                                                       "root");
                                          strict=true,
                                          path="root.original_matrix")
    reconstructed = parse_sparse_matrix_object(_require_key(parsed,
                                                            :reconstructed_matrix,
                                                            "root");
                                               strict=true,
                                               path="root.reconstructed_matrix")
    dag = _parse_certificate_dag(_require_key(parsed, :proof_dag, "root");
                                 strict=true)
    cert = BlockDiagonalizationCertificate(_require_string(parsed,
                                                           :problem_hash,
                                                           "root.problem_hash"),
                                           group,
                                           orbit,
                                           blocks,
                                           projectors,
                                           original,
                                           reconstructed,
                                           _require_string(parsed,
                                                           :certificate_hash,
                                                           "root.certificate_hash"),
                                           dag)
    cert.certificate_hash == block_diagonalization_certificate_hash(cert) ||
        throw(ArgumentError("root.certificate_hash mismatch"))
    return cert
end

function _parse_symmetry_group_object(object)
    _strict_validate_top_object(object,
                                Set(Symbol[:variables, :generators,
                                           :action_hash]),
                                "root.group")
    generators = SymmetryPermutation[]
    for (i, generator) in enumerate(_require_key(object, :generators,
                                                 "root.group"))
        _strict_validate_top_object(generator,
                                    Set(Symbol[:id, :image]),
                                    "root.group.generators[$i]")
        push!(generators,
              SymmetryPermutation(Symbol(_require_string(generator, :id,
                                                         "root.group.generators[$i].id")),
                                  Int.(_require_key(generator, :image,
                                                    "root.group.generators[$i]"))))
    end
    group = SymmetryGroupCertificate(Symbol.(String.(_require_key(object,
                                                                  :variables,
                                                                  "root.group"))),
                                     generators)
    supplied = _require_string(object, :action_hash,
                               "root.group.action_hash")
    supplied == group.action_hash ||
        throw(ArgumentError("root.group.action_hash mismatch"))
    return group
end

function _parse_orbit_basis_object(object)
    _strict_validate_top_object(object,
                                Set(Symbol[:monomial_exponents, :orbits,
                                           :orbit_hash]),
                                "root.orbit_basis")
    orbit = OrbitBasisCertificate([Int.(row)
                                   for row in _require_key(object,
                                                           :monomial_exponents,
                                                           "root.orbit_basis")],
                                  [Int.(row)
                                   for row in _require_key(object,
                                                           :orbits,
                                                           "root.orbit_basis")])
    supplied = _require_string(object, :orbit_hash,
                               "root.orbit_basis.orbit_hash")
    supplied == orbit.orbit_hash ||
        throw(ArgumentError("root.orbit_basis.orbit_hash mismatch"))
    return orbit
end

function _parse_sparse_sos_problem_object(object)
    _strict_validate_top_object(object,
                                Set(Symbol[:variables, :target_terms,
                                           :cliques, :lower_bound,
                                           :problem_hash]),
                                "root.problem")
    variables = Symbol.(String.(_require_key(object, :variables, "root.problem")))
    terms = _parse_polynomial_terms_object(_require_key(object,
                                                        :target_terms,
                                                        "root.problem"),
                                           length(variables),
                                           "root.problem.target_terms")
    cliques = [Symbol.(String.(clique))
               for clique in _require_key(object, :cliques, "root.problem")]
    problem = SparseSOSProblem(variables, terms, cliques,
                               _parse_rational_string(_require_key(object,
                                                                   :lower_bound,
                                                                   "root.problem"),
                                                      "root.problem.lower_bound"))
    supplied = _require_string(object, :problem_hash,
                               "root.problem.problem_hash")
    supplied == problem.problem_hash ||
        throw(ArgumentError("root.problem.problem_hash mismatch"))
    return problem
end

function _parse_sparse_sos_block_object(object, path::AbstractString)
    _strict_validate_top_object(object,
                                Set(Symbol[:id, :clique_id,
                                           :basis_exponents, :gram_matrix,
                                           :psd_proof, :coefficient_terms]),
                                path)
    matrix = parse_sparse_matrix_object(_require_key(object, :gram_matrix,
                                                     path);
                                        strict=true,
                                        path="$path.gram_matrix")
    proof = _parse_low_rank_proof_object(_require_key(object, :psd_proof,
                                                      path),
                                         matrix;
                                         strict=true,
                                         path="$path.psd_proof")
    basis = [Int.(row)
             for row in _require_key(object, :basis_exponents, path)]
    terms = _parse_polynomial_terms_object(_require_key(object,
                                                        :coefficient_terms,
                                                        path),
                                           isempty(basis) ? 0 : length(first(basis)),
                                           "$path.coefficient_terms")
    return SparseSOSBlock(Symbol(_require_string(object, :id,
                                                 "$path.id")),
                          Symbol(_require_string(object, :clique_id,
                                                 "$path.clique_id")),
                          basis,
                          matrix,
                          proof,
                          terms)
end

function _parse_putinar_certificate_object(object, path::AbstractString)
    _strict_validate_top_object(object,
                                Set(Symbol[:localizing_blocks, :bound,
                                           :identity_hash]),
                                path)
    localizing = LocalizingMatrixProof[]
    for (i, entry) in enumerate(_require_key(object,
                                             :localizing_blocks,
                                             path))
        push!(localizing,
              _parse_localizing_matrix_proof_object(entry,
                                                    "$path.localizing_blocks[$i]"))
    end
    return PutinarCertificate(localizing,
                              _parse_rational_string(_require_key(object,
                                                                  :bound,
                                                                  path),
                                                     "$path.bound"),
                              _require_string(object, :identity_hash,
                                              "$path.identity_hash"))
end

function _parse_localizing_matrix_proof_object(object, path::AbstractString)
    _strict_validate_top_object(object,
                                Set(Symbol[:id, :clique_id,
                                           :constraint_terms, :sos_block]),
                                path)
    block = _parse_sparse_sos_block_object(_require_key(object, :sos_block,
                                                        path),
                                          "$path.sos_block")
    variable_count = isempty(block.basis_exponents) ? 0 :
                     length(first(block.basis_exponents))
    return LocalizingMatrixProof(Symbol(_require_string(object, :id,
                                                        "$path.id")),
                                 Symbol(_require_string(object, :clique_id,
                                                        "$path.clique_id")),
                                 _parse_polynomial_terms_object(_require_key(object,
                                                                             :constraint_terms,
                                                                             path),
                                                                variable_count,
                                                                "$path.constraint_terms"),
                                 block)
end

function _parse_polynomial_terms_object(values,
                                        variable_count::Int,
                                        path::AbstractString)
    _require_array(values, path)
    terms = PolynomialTerm[]
    for (i, term) in enumerate(values)
        _strict_validate_top_object(term,
                                    Set(Symbol[:exponents, :coefficient]),
                                    "$path[$i]")
        exponents = Int.(_require_key(term, :exponents, "$path[$i]"))
        variable_count == 0 || length(exponents) == variable_count ||
            throw(ArgumentError("$path[$i].exponents length mismatch"))
        push!(terms,
              PolynomialTerm(exponents,
                             _parse_rational_string(_require_key(term,
                                                                 :coefficient,
                                                                 "$path[$i]"),
                                                    "$path[$i].coefficient")))
    end
    return terms
end

function _parse_block_native_incidence_system_object(object)
    _strict_validate_top_object(object,
                                Set(Symbol[:problem_hash, :shared_variables,
                                           :blocks, :system_hash]),
                                "root.incidence")
    blocks_value = _require_key(object, :blocks, "root.incidence")
    _require_array(blocks_value, "root.incidence.blocks")
    blocks = BlockNativeIncidenceBlock[]
    for (i, block_object) in enumerate(blocks_value)
        push!(blocks,
              _parse_block_native_incidence_block_object(block_object,
                                                         "root.incidence.blocks[$i]"))
    end
    system = BlockNativeIncidenceSystem(_require_string(object,
                                                        :problem_hash,
                                                        "root.incidence.problem_hash"),
                                        Symbol.(String.(_require_key(object,
                                                                     :shared_variables,
                                                                     "root.incidence"))),
                                        blocks,
                                        _require_string(object,
                                                        :system_hash,
                                                        "root.incidence.system_hash"))
    system.system_hash == block_native_incidence_system_hash(system) ||
        throw(ArgumentError("root.incidence.system_hash mismatch"))
    return system
end

function _parse_block_native_incidence_block_object(object, path::AbstractString)
    _strict_validate_top_object(object,
                                Set(Symbol[:block_index, :block_hash, :rank,
                                           :kernel_dimension, :variable_names,
                                           :gauge_rows, :slicing_strategy,
                                           :active, :system_hash]),
                                path)
    return BlockNativeIncidenceBlock(_require_integer(object,
                                                      :block_index,
                                                      "$path.block_index"),
                                     _require_string(object,
                                                     :block_hash,
                                                     "$path.block_hash"),
                                     _require_integer(object, :rank,
                                                      "$path.rank"),
                                     _require_integer(object,
                                                      :kernel_dimension,
                                                      "$path.kernel_dimension"),
                                     Symbol.(String.(_require_key(object,
                                                                  :variable_names,
                                                                  path))),
                                     Int.(_require_key(object, :gauge_rows,
                                                       path)),
                                     Symbol(_require_string(object,
                                                            :slicing_strategy,
                                                            "$path.slicing_strategy")),
                                     Bool(_require_key(object, :active, path)),
                                     _require_string(object, :system_hash,
                                                     "$path.system_hash"))
end

function _parse_block_native_active_block_proof(object, path::AbstractString)
    _strict_validate_top_object(object,
                                Set(Symbol[:block_index, :block_hash, :field,
                                           :values, :incidence_equations,
                                           :gauge_equations, :proof_hash]),
                                path)
    field = _parse_algebraic_field_certificate_object(_require_key(object,
                                                                   :field,
                                                                   path),
                                                      "$path.field")
    values_object = _require_key(object, :values, path)
    _require_object(values_object, "$path.values")
    values = Dict{Symbol, AlgebraicElement}()
    for key in keys(values_object)
        values[Symbol(key)] = _parse_algebraic_element_object(_object_value(values_object,
                                                                            Symbol(key)),
                                                              field,
                                                              "$path.values.$(String(key))")
    end
    incidence = AlgebraicEquationObligation[]
    for (i, equation_object) in enumerate(_require_key(object,
                                                       :incidence_equations,
                                                       path))
        push!(incidence,
              _parse_algebraic_equation_obligation_object(equation_object,
                                                          field,
                                                          "$path.incidence_equations[$i]"))
    end
    gauge = AlgebraicEquationObligation[]
    for (i, equation_object) in enumerate(_require_key(object,
                                                       :gauge_equations,
                                                       path))
        push!(gauge,
              _parse_algebraic_equation_obligation_object(equation_object,
                                                          field,
                                                          "$path.gauge_equations[$i]"))
    end
    proof = BlockNativeActiveBlockProof(_require_integer(object,
                                                         :block_index,
                                                         "$path.block_index"),
                                        _require_string(object,
                                                        :block_hash,
                                                        "$path.block_hash"),
                                        field,
                                        values,
                                        incidence,
                                        gauge)
    supplied = _require_string(object, :proof_hash, "$path.proof_hash")
    supplied == proof.proof_hash ||
        throw(ArgumentError("$path.proof_hash mismatch"))
    return proof
end

function _parse_block_native_inactive_psd_proof(object, path::AbstractString)
    _strict_validate_top_object(object,
                                Set(Symbol[:block_index, :block_hash,
                                           :margin_matrix, :psd_proof,
                                           :proof_hash]),
                                path)
    matrix = parse_sparse_matrix_object(_require_key(object, :margin_matrix,
                                                     path);
                                        strict=true,
                                        path="$path.margin_matrix")
    psd = _parse_low_rank_proof_object(_require_key(object, :psd_proof,
                                                    path),
                                       matrix;
                                       strict=true,
                                       path="$path.psd_proof")
    proof = BlockNativeInactivePSDProof(_require_integer(object,
                                                         :block_index,
                                                         "$path.block_index"),
                                        _require_string(object,
                                                        :block_hash,
                                                        "$path.block_hash"),
                                        matrix,
                                        psd)
    supplied = _require_string(object, :proof_hash, "$path.proof_hash")
    supplied == proof.proof_hash ||
        throw(ArgumentError("$path.proof_hash mismatch"))
    return proof
end

function _parse_primal_feasibility_object(object, path::AbstractString)
    _validate_object_keys(object,
                          Set(Symbol[:problem_hash,
                                     :affine_lhs,
                                     :affine_rhs,
                                     :cone_matrices,
                                     :cone_proofs,
                                     :objective_value]),
                          Set(Symbol[:primal_vector]),
                          path)
    matrices_value = _require_key(object, :cone_matrices, path)
    proofs_value = _require_key(object, :cone_proofs, path)
    _require_array(matrices_value, "$path.cone_matrices")
    _require_array(proofs_value, "$path.cone_proofs")
    length(matrices_value) == length(proofs_value) ||
        throw(ArgumentError("$path cone matrix/proof count mismatch"))
    matrices = SparseSymmetricRationalMatrix[
        parse_sparse_matrix_object(matrix_object; strict=true,
                                   path="$path.cone_matrices[$i]")
        for (i, matrix_object) in enumerate(matrices_value)
    ]
    proofs = ExactLowRankPSDProof[
        _parse_low_rank_proof_object(proof_object, matrices[i];
                                     strict=true,
                                     path="$path.cone_proofs[$i]")
        for (i, proof_object) in enumerate(proofs_value)
    ]
    primal_vector = haskey(object, :primal_vector) ?
                    [_parse_rational_string(value, "$path.primal_vector[$i]")
                     for (i, value) in enumerate(_require_key(object, :primal_vector, path))] :
                    Rational{BigInt}[]
    return PrimalFeasibilityCertificate(_require_string(object, :problem_hash,
                                                        "$path.problem_hash"),
                                        nothing,
                                        primal_vector,
                                        [_parse_rational_string(value,
                                                                "$path.affine_lhs[$i]")
                                         for (i, value) in enumerate(_require_key(object,
                                                                                 :affine_lhs,
                                                                                 path))],
                                        [_parse_rational_string(value,
                                                                "$path.affine_rhs[$i]")
                                         for (i, value) in enumerate(_require_key(object,
                                                                                 :affine_rhs,
                                                                                 path))],
                                        matrices,
                                        proofs,
                                        _parse_rational_string(_require_key(object,
                                                                            :objective_value,
                                                                            path),
                                                               "$path.objective_value"))
end

function _parse_dual_feasibility_object(object, path::AbstractString)
    _validate_object_keys(object,
                          Set(Symbol[:problem_hash,
                                     :affine_lhs,
                                     :affine_rhs,
                                     :cone_matrices,
                                     :cone_proofs,
                                     :objective_value]),
                          Set(Symbol[:dual_variables]),
                          path)
    matrices_value = _require_key(object, :cone_matrices, path)
    proofs_value = _require_key(object, :cone_proofs, path)
    _require_array(matrices_value, "$path.cone_matrices")
    _require_array(proofs_value, "$path.cone_proofs")
    length(matrices_value) == length(proofs_value) ||
        throw(ArgumentError("$path cone matrix/proof count mismatch"))
    matrices = SparseSymmetricRationalMatrix[
        parse_sparse_matrix_object(matrix_object; strict=true,
                                   path="$path.cone_matrices[$i]")
        for (i, matrix_object) in enumerate(matrices_value)
    ]
    proofs = ExactLowRankPSDProof[
        _parse_low_rank_proof_object(proof_object, matrices[i];
                                     strict=true,
                                     path="$path.cone_proofs[$i]")
        for (i, proof_object) in enumerate(proofs_value)
    ]
    dual_variables = haskey(object, :dual_variables) ?
                     SparseSymmetricRationalMatrix[
                         parse_sparse_matrix_object(matrix_object; strict=true,
                                                    path="$path.dual_variables[$i]")
                         for (i, matrix_object) in enumerate(_require_key(object,
                                                                          :dual_variables,
                                                                          path))
                     ] :
                     SparseSymmetricRationalMatrix[]
    return DualFeasibilityCertificate(_require_string(object, :problem_hash,
                                                      "$path.problem_hash"),
                                      nothing,
                                      dual_variables,
                                      [_parse_rational_string(value,
                                                              "$path.affine_lhs[$i]")
                                       for (i, value) in enumerate(_require_key(object,
                                                                               :affine_lhs,
                                                                               path))],
                                      [_parse_rational_string(value,
                                                              "$path.affine_rhs[$i]")
                                       for (i, value) in enumerate(_require_key(object,
                                                                               :affine_rhs,
                                                                               path))],
                                      matrices,
                                      proofs,
                                      _parse_rational_string(_require_key(object,
                                                                          :objective_value,
                                                                          path),
                                                              "$path.objective_value"))
end

function _parse_conic_affine_block_object(object, path::AbstractString)
    _strict_validate_top_object(object,
                                Set(Symbol[:id, :cone, :B, :A]),
                                path)
    B = parse_sparse_matrix_object(_require_key(object, :B, path);
                                   strict=true,
                                   path="$path.B")
    A_value = _require_key(object, :A, path)
    _require_array(A_value, "$path.A")
    A = SparseSymmetricRationalMatrix[
        parse_sparse_matrix_object(matrix; strict=true, path="$path.A[$i]")
        for (i, matrix) in enumerate(A_value)
    ]
    return ConicAffineBlock(Symbol(_require_string(object, :id, "$path.id")),
                            Symbol(_require_string(object, :cone, "$path.cone")),
                            B,
                            A)
end

function _parse_exact_conic_problem_object(object, path::AbstractString)
    _validate_object_keys(object,
                          Set(Symbol[:sense, :variables, :objective,
                                     :blocks, :problem_hash]),
                          Set(Symbol[:dual_objective_coefficients]),
                          path)
    blocks_value = _require_key(object, :blocks, path)
    _require_array(blocks_value, "$path.blocks")
    blocks = ConicAffineBlock[
        _parse_conic_affine_block_object(block, "$path.blocks[$i]")
        for (i, block) in enumerate(blocks_value)
    ]
    dual_coeffs = haskey(object, :dual_objective_coefficients) ?
                  [_parse_rational_string(value,
                                          "$path.dual_objective_coefficients[$i]")
                   for (i, value) in enumerate(_require_key(object,
                                                            :dual_objective_coefficients,
                                                            path))] :
                  Rational{BigInt}[]
    problem = ExactConicProblem(Symbol(_require_string(object, :sense,
                                                       "$path.sense")),
                                Symbol.(String.(_require_key(object, :variables, path))),
                                [_parse_rational_string(value, "$path.objective[$i]")
                                 for (i, value) in enumerate(_require_key(object,
                                                                          :objective,
                                                                          path))],
                                blocks;
                                dual_objective_coefficients=dual_coeffs)
    supplied = _require_string(object, :problem_hash, "$path.problem_hash")
    supplied == problem.problem_hash ||
        throw(ArgumentError("$path.problem_hash mismatch"))
    return problem
end

function _parse_algebraic_field_certificate_object(object, path::AbstractString)
    _strict_validate_top_object(object,
                                Set(Symbol[:id, :generator,
                                           :minimal_polynomial,
                                           :isolating_interval,
                                           :field_hash]),
                                path)
    coefficients = [_parse_rational_string(value,
                                           "$path.minimal_polynomial[$i]")
                    for (i, value) in enumerate(_require_key(object,
                                                             :minimal_polynomial,
                                                             path))]
    interval_value = _require_key(object, :isolating_interval, path)
    _require_array(interval_value, "$path.isolating_interval")
    length(interval_value) == 2 ||
        throw(ArgumentError("$path.isolating_interval must contain two rational endpoints"))
    field = AlgebraicFieldCertificate(Symbol(_require_string(object,
                                                             :id,
                                                             "$path.id")),
                                      Symbol(_require_string(object,
                                                             :generator,
                                                             "$path.generator")),
                                      coefficients,
                                      (_parse_rational_string(interval_value[1],
                                                              "$path.isolating_interval[1]"),
                                       _parse_rational_string(interval_value[2],
                                                              "$path.isolating_interval[2]")))
    supplied = _require_string(object, :field_hash, "$path.field_hash")
    supplied == field.field_hash ||
        throw(ArgumentError("$path.field_hash mismatch"))
    return field
end

function _parse_algebraic_element_object(object,
                                         field::AlgebraicFieldCertificate,
                                         path::AbstractString)
    _strict_validate_top_object(object,
                                Set(Symbol[:field_hash, :coefficients,
                                           :element_hash]),
                                path)
    _require_string(object, :field_hash, "$path.field_hash") == field.field_hash ||
        throw(ArgumentError("$path.field_hash does not match field certificate"))
    coefficients = [_parse_rational_string(value, "$path.coefficients[$i]")
                    for (i, value) in enumerate(_require_key(object,
                                                             :coefficients,
                                                             path))]
    element = AlgebraicElement(field, coefficients)
    supplied = _require_string(object, :element_hash, "$path.element_hash")
    supplied == element.element_hash ||
        throw(ArgumentError("$path.element_hash mismatch"))
    return element
end

function _parse_algebraic_equation_obligation_object(object,
                                                     field::AlgebraicFieldCertificate,
                                                     path::AbstractString)
    _strict_validate_top_object(object,
                                Set(Symbol[:id, :terms, :constant]),
                                path)
    terms = AlgebraicLinearTerm[]
    for (i, term_object) in enumerate(_require_key(object, :terms, path))
        _strict_validate_top_object(term_object,
                                    Set(Symbol[:variable, :coefficient]),
                                    "$path.terms[$i]")
        push!(terms,
              AlgebraicLinearTerm(Symbol(_require_string(term_object,
                                                         :variable,
                                                         "$path.terms[$i].variable")),
                                  _parse_algebraic_element_object(_require_key(term_object,
                                                                               :coefficient,
                                                                               "$path.terms[$i]"),
                                                                  field,
                                                                  "$path.terms[$i].coefficient")))
    end
    return AlgebraicEquationObligation(Symbol(_require_string(object, :id,
                                                              "$path.id")),
                                       terms,
                                       _parse_algebraic_element_object(_require_key(object,
                                                                                   :constant,
                                                                                   path),
                                                                      field,
                                                                      "$path.constant"))
end

function _parse_npa_problem_object(object)
    _strict_validate_top_object(object,
                                Set(Symbol[:variables, :relations, :word_basis,
                                           :trace_cyclic, :problem_hash]),
                                "root.problem")
    variables = Symbol.(String.(_require_key(object, :variables, "root.problem")))
    relations = AbstractQuantumRelation[]
    for (i, relation_object) in enumerate(_require_key(object, :relations, "root.problem"))
        push!(relations, _parse_quantum_relation_object(relation_object,
                                                        "root.problem.relations[$i]"))
    end
    basis = [Symbol.(String.(word))
             for word in _require_key(object, :word_basis, "root.problem")]
    trace_cyclic = Bool(_require_key(object, :trace_cyclic, "root.problem"))
    problem = NPAProblem(variables, relations, basis; trace_cyclic)
    supplied = _require_string(object, :problem_hash, "root.problem.problem_hash")
    supplied == problem.problem_hash ||
        throw(ArgumentError("root.problem.problem_hash mismatch"))
    return problem
end

function _parse_quantum_relation_object(object, path::AbstractString)
    _require_object(object, path)
    kind = _require_string(object, :kind, "$path.kind")
    if kind == "ProjectionRelation"
        _strict_validate_top_object(object, Set(Symbol[:kind, :id, :symbol]), path)
        return ProjectionRelation(Symbol(_require_string(object, :id, "$path.id")),
                                  Symbol(_require_string(object, :symbol, "$path.symbol")))
    elseif kind == "UnitaryRelation"
        _strict_validate_top_object(object, Set(Symbol[:kind, :id, :symbol]), path)
        return UnitaryRelation(Symbol(_require_string(object, :id, "$path.id")),
                               Symbol(_require_string(object, :symbol, "$path.symbol")))
    elseif kind == "CommutationRelation"
        _strict_validate_top_object(object,
                                    Set(Symbol[:kind, :id, :left_symbols,
                                               :right_symbols]),
                                    path)
        return CommutationRelation(Symbol(_require_string(object, :id, "$path.id")),
                                   Symbol.(String.(_require_key(object, :left_symbols, path))),
                                   Symbol.(String.(_require_key(object, :right_symbols, path))))
    elseif kind == "TraceCyclicRelation"
        _strict_validate_top_object(object, Set(Symbol[:kind, :id]), path)
        return TraceCyclicRelation(Symbol(_require_string(object, :id, "$path.id")))
    elseif kind == "StarInvolutionRelation"
        _strict_validate_top_object(object, Set(Symbol[:kind, :id]), path)
        return StarInvolutionRelation(Symbol(_require_string(object, :id, "$path.id")))
    elseif kind == "NormalizationRelation"
        _strict_validate_top_object(object, Set(Symbol[:kind, :id, :value]), path)
        return NormalizationRelation(Symbol(_require_string(object, :id, "$path.id")),
                                     _parse_rational_string(_require_key(object, :value, path),
                                                            "$path.value"))
    end
    throw(ArgumentError("$path.kind is unsupported"))
end

function _parse_nc_moment_certificate_object(object, problem::NPAProblem)
    _strict_validate_top_object(object,
                                Set(Symbol[:problem_hash, :moment_matrix,
                                           :psd_proof, :coefficient_terms,
                                           :witnesses, :certificate_hash]),
                                "root.moment_certificate")
    matrix = parse_sparse_matrix_object(_require_key(object, :moment_matrix,
                                                     "root.moment_certificate");
                                        strict=true,
                                        path="root.moment_certificate.moment_matrix")
    proof = _parse_low_rank_proof_object(_require_key(object, :psd_proof,
                                                      "root.moment_certificate"),
                                         matrix;
                                         strict=true,
                                         path="root.moment_certificate.psd_proof")
    witnesses = NCRewriteWitness[]
    for (i, witness_object) in enumerate(_require_key(object, :witnesses,
                                                      "root.moment_certificate"))
        push!(witnesses,
              _parse_nc_rewrite_witness_object(witness_object,
                                               "root.moment_certificate.witnesses[$i]"))
    end
    cert = NCMomentMatrixCertificate(problem,
                                     matrix,
                                     proof,
                                     _parse_nc_terms(_require_key(object, :coefficient_terms,
                                                                  "root.moment_certificate"),
                                                     "root.moment_certificate.coefficient_terms"),
                                     witnesses)
    supplied_problem = _require_string(object, :problem_hash,
                                      "root.moment_certificate.problem_hash")
    supplied_problem == problem.problem_hash ||
        throw(ArgumentError("root.moment_certificate.problem_hash mismatch"))
    supplied_hash = _require_string(object, :certificate_hash,
                                    "root.moment_certificate.certificate_hash")
    supplied_hash == cert.certificate_hash ||
        throw(ArgumentError("root.moment_certificate.certificate_hash mismatch"))
    return cert
end

function _parse_nc_rewrite_witness_object(object, path::AbstractString)
    _strict_validate_top_object(object,
                                Set(Symbol[:input_word, :steps, :final_word,
                                           :relation_ids_used, :trace_rotations,
                                           :star_steps]),
                                path)
    steps = NCRewriteStep[]
    for (i, step_object) in enumerate(_require_key(object, :steps, path))
        push!(steps, _parse_nc_rewrite_step_object(step_object, "$path.steps[$i]"))
    end
    return NCRewriteWitness(Symbol.(String.(_require_key(object, :input_word, path))),
                            steps,
                            Symbol.(String.(_require_key(object, :final_word, path))),
                            Symbol.(String.(_require_key(object, :relation_ids_used, path))),
                            [Symbol.(String.(word))
                             for word in _require_key(object, :trace_rotations, path)],
                            [Symbol.(String.(word))
                             for word in _require_key(object, :star_steps, path)])
end

function _parse_nc_rewrite_step_object(object, path::AbstractString)
    _strict_validate_top_object(object,
                                Set(Symbol[:relation_id, :rule, :before, :after]),
                                path)
    return NCRewriteStep(Symbol(_require_string(object, :relation_id,
                                                "$path.relation_id")),
                         Symbol(_require_string(object, :rule, "$path.rule")),
                         Symbol.(String.(_require_key(object, :before, path))),
                         Symbol.(String.(_require_key(object, :after, path))))
end

function _parse_nc_terms(values, path::AbstractString)
    _require_array(values, path)
    terms = Tuple{Vector{Symbol}, Rational{BigInt}}[]
    for (i, term) in enumerate(values)
        _strict_validate_top_object(term,
                                    Set(Symbol[:word, :coefficient]),
                                    "$path[$i]")
        push!(terms,
              (Symbol.(String.(_require_key(term, :word, "$path[$i]"))),
               _parse_rational_string(_require_key(term, :coefficient, "$path[$i]"),
                                      "$path[$i].coefficient")))
    end
    return terms
end

function make_low_rank_psd_certificate(matrix::SparseSymmetricRationalMatrix,
                                       proof::ExactLowRankPSDProof;
                                       claim=Dict{Symbol, Any}(:description => "exact low-rank PSD replay"),
                                       metadata=Dict{Symbol, Any}())
    nodes = ProofNode[
        ProofNode(:matrix_hash, :hash, String[], matrix.hash,
                  :canonical_sparse_matrix_hash, :accepted;
                  typed_payload=Dict(:matrix => sparse_matrix_json(matrix)),
                  obligation_id=:matrix_hash),
        ProofNode(:low_rank_identity, :exact_identity, [matrix.hash],
                  proof.identity_proof_hash, :verify_low_rank_psd, :accepted;
                  typed_payload=Dict(:matrix => sparse_matrix_json(matrix),
                                     :proof => low_rank_proof_json(proof)),
                  obligation_id=:low_rank_psd_identity),
    ]
    dag = CertificateDAG(:low_rank_psd, nodes, "", CERTSDP3_SCHEMA_VERSION)
    cert_without_hash = V3Certificate(:low_rank_psd_certificate, "",
                                      matrix.hash, claim,
                                      (; matrix, low_rank_proof=proof),
                                      dag,
                                      Dict{Symbol, Any}(metadata), "")
    hash = certificate_hash_v3(cert_without_hash)
    return V3Certificate(:low_rank_psd_certificate, hash, matrix.hash, claim,
                         (; matrix, low_rank_proof=proof), dag,
                         Dict{Symbol, Any}(metadata), hash)
end

function make_chordal_psd_certificate(matrix::SparseSymmetricRationalMatrix,
                                      proof::ChordalPSDProof;
                                      claim=Dict{Symbol, Any}(:description => "exact chordal PSD replay"),
                                      metadata=Dict{Symbol, Any}())
    nodes = ProofNode[
        ProofNode(:matrix_hash, :hash, String[], matrix.hash,
                  :canonical_sparse_matrix_hash, :accepted;
                  typed_payload=Dict(:matrix => sparse_matrix_json(matrix)),
                  obligation_id=:matrix_hash),
        ProofNode(:chordal_structure, :hash, [matrix.hash],
                  proof.structure.graph_hash, :chordal_structure_hash,
                  :accepted;
                  typed_payload=Dict(:structure => chordal_structure_json(proof.structure),
                                     :matrix_hash => matrix.hash),
                  arithmetic_mode=:symbolic_sparse,
                  obligation_id=:chordal_structure),
        ProofNode(:chordal_replay, :psd, [proof.structure.graph_hash],
                  proof.proof_hash, :verify_chordal_psd, :accepted;
                  typed_payload=Dict(:matrix => sparse_matrix_json(matrix),
                                     :proof => chordal_proof_json(proof)),
                  arithmetic_mode=:symbolic_sparse,
                  obligation_id=:chordal_psd_replay),
    ]
    dag = CertificateDAG(:chordal_psd, nodes, "", CERTSDP3_SCHEMA_VERSION)
    cert_without_hash = V3Certificate(:chordal_psd_certificate, "",
                                      matrix.hash, claim,
                                      (; matrix, chordal_proof=proof),
                                      dag,
                                      Dict{Symbol, Any}(metadata), "")
    hash = certificate_hash_v3(cert_without_hash)
    return V3Certificate(:chordal_psd_certificate, hash, matrix.hash, claim,
                         (; matrix, chordal_proof=proof), dag,
                         Dict{Symbol, Any}(metadata), hash)
end

function _canonical_certificate_payload_v3(cert::V3Certificate; for_hash::Bool=false)
    return (;
        certsdp_certificate_version=CERTSDP3_SCHEMA_VERSION,
        certificate_type=String(cert.certificate_type),
        certificate_id=for_hash ? "" : cert.certificate_id,
        problem_hash=cert.problem_hash,
        claim=_jsonify(cert.claim),
        proof=_proof_json(cert),
        proof_dag=certificate_dag_json(cert.dag),
        metadata=for_hash ? Dict{String, Any}() : _jsonify(cert.metadata),
    )
end

certificate_hash_v3(cert::V3Certificate) =
    _sha256_payload(_canonical_certificate_payload_v3(cert; for_hash=true))

function _proof_json(cert::V3Certificate)
    if cert.certificate_type === :low_rank_psd_certificate
        return (;
            matrix=sparse_matrix_json(cert.proof.matrix),
            low_rank_proof=low_rank_proof_json(cert.proof.low_rank_proof),
        )
    elseif cert.certificate_type === :chordal_psd_certificate
        return (;
            matrix=sparse_matrix_json(cert.proof.matrix),
            chordal_proof=chordal_proof_json(cert.proof.chordal_proof),
        )
    end
    throw(ArgumentError("unsupported v3 certificate type $(cert.certificate_type)"))
end

function low_rank_proof_json(proof::ExactLowRankPSDProof)
    return (;
        field=String(proof.field),
        matrix_hash=proof.matrix_hash,
        factor=[[rational_string(value) for value in row] for row in proof.factor],
        diagonal=[rational_string(value) for value in proof.diagonal],
        identity_proof_hash=proof.identity_proof_hash,
    )
end

function chordal_structure_json(structure::ChordalPSDStructure)
    return (;
        n=structure.n,
        cliques=structure.cliques,
        separators=structure.separators,
        graph_hash=structure.graph_hash,
    )
end

function chordal_proof_json(proof::ChordalPSDProof)
    return (;
        theorem_tag=String(proof.theorem_tag),
        matrix_hash=proof.matrix_hash,
        structure=chordal_structure_json(proof.structure),
        clique_proofs=[clique_proof_json(entry) for entry in proof.clique_proofs],
        separator_proofs=[separator_proof_json(entry) for entry in proof.separator_proofs],
        proof_hash=proof.proof_hash,
    )
end

function clique_proof_json(proof::CliquePSDProof)
    return (;
        id=String(proof.id),
        clique_index=proof.clique_index,
        vertices=proof.vertices,
        matrix=sparse_matrix_json(proof.matrix),
        psd_proof=low_rank_proof_json(proof.psd_proof),
    )
end

function separator_proof_json(proof::SeparatorConsistencyProof)
    return (;
        id=String(proof.id),
        left_clique=proof.left_clique,
        right_clique=proof.right_clique,
        vertices=proof.vertices,
        value_hash=proof.value_hash,
    )
end

function _problem_hash_from_proof(cert_type::Symbol, proof)
    if cert_type === :low_rank_psd_certificate ||
       cert_type === :chordal_psd_certificate
        return proof.matrix.hash
    end
    return ""
end

function _canonical_sparse_matrix_payload(n::Int,
                                          entries::Vector{Tuple{Int, Int, Rational{BigInt}}})
    return (;
        type="sparse_symmetric_rational_matrix",
        n,
        entries=[(; i=i, j=j, value=rational_string(value))
                 for (i, j, value) in entries],
    )
end

function _canonical_sparse_affine_lmi_payload(problem::SparseAffineLMI)
    return (;
        type="sparse_affine_lmi",
        variables=String.(problem.variables),
        A0=_canonical_sparse_matrix_payload(problem.A0.n, problem.A0.entries),
        A=[_canonical_sparse_matrix_payload(matrix.n, matrix.entries)
           for matrix in problem.A],
        blocks=[_block_hash_payload(block) for block in problem.blocks],
    )
end

function _canonical_chordal_structure_payload(n::Int,
                                              cliques::Vector{Vector{Int}},
                                              separators::Vector{Vector{Int}})
    return (;
        type="chordal_psd_structure",
        n,
        cliques,
        separators,
    )
end

function _canonical_chordal_proof_payload(proof::ChordalPSDProof)
    return (;
        theorem_tag=String(proof.theorem_tag),
        matrix_hash=proof.matrix_hash,
        structure=chordal_structure_json(proof.structure),
        clique_proofs=[clique_proof_json(entry) for entry in proof.clique_proofs],
        separator_proofs=[separator_proof_json(entry) for entry in proof.separator_proofs],
    )
end

function _block_hash_payload(block::AbstractExactConeBlock)
    if block isa ChordalPSDStructure
        return chordal_structure_json(block)
    end
    return string(typeof(block))
end

function _sparse_matrix_from_entries(n::Int, raw_entries;
                                     reject_conflicts::Bool)
    n > 0 || throw(ArgumentError("sparse matrix dimension must be positive"))
    values = Dict{Tuple{Int, Int}, Rational{BigInt}}()
    for (k, raw) in enumerate(raw_entries)
        length(raw) == 3 ||
            throw(ArgumentError("sparse entry $k must have three values"))
        i = Int(raw[1])
        j = Int(raw[2])
        value = _to_big_rational(raw[3], "entries[$k].value")
        1 <= i <= n || throw(ArgumentError("entries[$k].i out of range"))
        1 <= j <= n || throw(ArgumentError("entries[$k].j out of range"))
        i <= j || ((i, j) = (j, i))
        value == 0 && continue
        key = (i, j)
        if haskey(values, key)
            if reject_conflicts && values[key] != value
                throw(ArgumentError("conflicting duplicate sparse entry at ($i, $j)"))
            end
            reject_conflicts || (values[key] += value)
        else
            values[key] = value
        end
    end
    entries = Vector{Tuple{Int, Int, Rational{BigInt}}}(undef, length(values))
    idx = 1
    for ((i, j), value) in values
        if value != 0
            entries[idx] = (i, j, value)
            idx += 1
        end
    end
    resize!(entries, idx - 1)
    sort!(entries, by=entry -> (entry[1], entry[2]))
    matrix = SparseSymmetricRationalMatrix(n, entries, "")
    return SparseSymmetricRationalMatrix(n, entries, sparse_matrix_hash(matrix))
end

function _sparse_matrix_from_accumulator(n::Int,
                                         accum::Dict{Tuple{Int, Int},
                                                     Rational{BigInt}})
    entries = [(i, j, value) for ((i, j), value) in accum if value != 0]
    sort!(entries, by=entry -> (entry[1], entry[2]))
    matrix = SparseSymmetricRationalMatrix(n, entries, "")
    return SparseSymmetricRationalMatrix(n, entries, sparse_matrix_hash(matrix))
end

function _accumulate_entries!(accum, entries, coefficient)
    for (i, j, value) in entries
        accum[(i, j)] = get(accum, (i, j), Rational{BigInt}(0)) +
                        coefficient * value
    end
    return accum
end

function _parse_index_vector(values, n::Int, label::AbstractString)
    vector = Int.(collect(values))
    isempty(vector) && throw(ArgumentError("$label must not be empty"))
    issorted(vector) || throw(ArgumentError("$label indices must be sorted"))
    length(unique(vector)) == length(vector) ||
        throw(ArgumentError("$label indices must be unique"))
    all(index -> 1 <= index <= n, vector) ||
        throw(ArgumentError("$label contains an out-of-range index"))
    return vector
end

function _parse_rational_row_matrix(value, path::AbstractString)
    _require_array(value, path)
    rows = Vector{Rational{BigInt}}[]
    width = nothing
    for (i, row) in enumerate(value)
        _require_array(row, "$path[$i]")
        parsed = [_to_big_rational(entry, "$path[$i][$j]")
                  for (j, entry) in enumerate(row)]
        isnothing(width) && (width = length(parsed))
        length(parsed) == width ||
            throw(ArgumentError("$path[$i] has length $(length(parsed)); expected $width"))
        push!(rows, parsed)
    end
    return rows
end

function _low_rank_product_entries(factor::Vector{Vector{Rational{BigInt}}},
                                   diagonal::Vector{Rational{BigInt}})
    n = length(factor)
    rank = length(diagonal)
    entries = Dict{Tuple{Int, Int}, Rational{BigInt}}()
    for i in 1:n
        for j in i:n
            value = Rational{BigInt}(0)
            for k in 1:rank
                value += factor[i][k] * diagonal[k] * factor[j][k]
            end
            value == 0 || (entries[(i, j)] = value)
        end
    end
    return entries
end

function _first_sparse_difference(actual, expected)
    keys_union = sort!(collect(union(keys(actual), keys(expected))))
    for key in keys_union
        a = get(actual, key, Rational{BigInt}(0))
        b = get(expected, key, Rational{BigInt}(0))
        a == b && continue
        return Dict{Symbol, Any}(:entry => [key[1], key[2]],
                                 :actual => rational_string(a),
                                 :expected => rational_string(b))
    end
    return Dict{Symbol, Any}()
end

function _algebraic_add(a::AbstractVector{<:Rational},
                        b::AbstractVector{<:Rational},
                        modulus::AbstractVector{<:Rational})
    n = max(length(a), length(b))
    result = fill(Rational{BigInt}(0), n)
    for i in 1:n
        result[i] = Rational{BigInt}(i <= length(a) ? a[i] : 0//1) +
                    Rational{BigInt}(i <= length(b) ? b[i] : 0//1)
    end
    return _algebraic_reduce(result, modulus)
end

function _algebraic_mul(a::AbstractVector{<:Rational},
                        b::AbstractVector{<:Rational},
                        modulus::AbstractVector{<:Rational})
    (isempty(a) || isempty(b)) && return Rational{BigInt}[]
    result = fill(Rational{BigInt}(0), length(a) + length(b) - 1)
    for i in eachindex(a), j in eachindex(b)
        result[i + j - 1] += Rational{BigInt}(a[i]) * Rational{BigInt}(b[j])
    end
    return _algebraic_reduce(result, modulus)
end

function _algebraic_reduce(poly::AbstractVector{<:Rational},
                           modulus::AbstractVector{<:Rational})
    result = Rational{BigInt}[Rational{BigInt}(value) for value in poly]
    modulus_values = Rational{BigInt}[Rational{BigInt}(value) for value in modulus]
    degree = length(modulus_values) - 1
    leading = modulus_values[end]
    while length(result) > degree
        coeff = result[end]
        if coeff != 0
            shift = length(result) - length(modulus_values)
            for i in 1:length(modulus_values)
                result[shift + i] -= coeff * modulus_values[i] / leading
            end
        end
        pop!(result)
    end
    while length(result) < degree
        push!(result, Rational{BigInt}(0))
    end
    return result
end

function _poly_trim(poly::AbstractVector{<:Rational})
    result = Rational{BigInt}[Rational{BigInt}(value) for value in poly]
    while !isempty(result) && result[end] == 0
        pop!(result)
    end
    return result
end

function _poly_derivative(poly::AbstractVector{<:Rational})
    length(poly) <= 1 && return Rational{BigInt}[Rational{BigInt}(0)]
    return [Rational{BigInt}(i - 1) * Rational{BigInt}(poly[i])
            for i in 2:length(poly)]
end

function _poly_divrem(a::AbstractVector{<:Rational},
                      b::AbstractVector{<:Rational})
    divisor = _poly_trim(b)
    isempty(divisor) && throw(ArgumentError("polynomial division by zero"))
    remainder = _poly_trim(a)
    isempty(remainder) && return Rational{BigInt}[], Rational{BigInt}[]
    quotient = fill(Rational{BigInt}(0),
                    max(0, length(remainder) - length(divisor) + 1))
    while length(remainder) >= length(divisor) && !isempty(remainder)
        coeff = remainder[end] / divisor[end]
        shift = length(remainder) - length(divisor)
        quotient[shift + 1] += coeff
        for i in 1:length(divisor)
            remainder[shift + i] -= coeff * divisor[i]
        end
        remainder = _poly_trim(remainder)
    end
    return _poly_trim(quotient), remainder
end

function _poly_neg(poly::AbstractVector{<:Rational})
    return Rational{BigInt}[-Rational{BigInt}(value) for value in poly]
end

function _poly_eval_sign(poly::AbstractVector{<:Rational},
                         x::Rational{BigInt})
    value = Rational{BigInt}(0)
    for coefficient in Iterators.reverse(poly)
        value = value * x + Rational{BigInt}(coefficient)
    end
    return value > 0 ? 1 : value < 0 ? -1 : 0
end

function _sign_variations(signs::Vector{Int})
    filtered = [sign for sign in signs if sign != 0]
    length(filtered) <= 1 && return 0
    return count(i -> filtered[i] != filtered[i + 1],
                 1:(length(filtered) - 1))
end

function _sturm_sequence(poly::AbstractVector{<:Rational})
    p0 = _poly_trim(poly)
    isempty(p0) && throw(ArgumentError("zero polynomial has no isolating interval"))
    p1 = _poly_trim(_poly_derivative(p0))
    sequence = Vector{Rational{BigInt}}[p0]
    isempty(p1) && return sequence
    push!(sequence, p1)
    while true
        _, remainder = _poly_divrem(sequence[end - 1], sequence[end])
        remainder = _poly_trim(_poly_neg(remainder))
        isempty(remainder) && break
        push!(sequence, remainder)
    end
    return sequence
end

function _sturm_root_count(poly::AbstractVector{<:Rational},
                           left::Rational{BigInt},
                           right::Rational{BigInt})
    sequence = _sturm_sequence(poly)
    left_signs = [_poly_eval_sign(entry, left) for entry in sequence]
    right_signs = [_poly_eval_sign(entry, right) for entry in sequence]
    return _sign_variations(left_signs) - _sign_variations(right_signs)
end

function _verify_clique_entry_coverage(matrix::SparseSymmetricRationalMatrix,
                                       proof::ChordalPSDProof,
                                       clique_by_index)
    for (i, j, value) in matrix.entries
        found = false
        for clique_proof in values(clique_by_index)
            if i in clique_proof.vertices && j in clique_proof.vertices
                found = true
                clique_value = _clique_original_value(clique_proof, i, j)
                clique_value == value ||
                    return _reject(:B, :chordal_psd, :clique_replay,
                                   clique_proof.id,
                                   "clique entry does not match original sparse matrix";
                                   problem_hash=matrix.hash,
                                   certificate_hash=proof.proof_hash,
                                   clique_id=clique_proof.id,
                                   details=Dict{Symbol, Any}(:entry => [i, j],
                                                             :actual => rational_string(clique_value),
                                                             :expected => rational_string(value)))
            end
        end
        found ||
            return _reject(:B, :chordal_psd, :clique_replay, :coverage,
                           "sparse matrix entry is not covered by any clique";
                           problem_hash=matrix.hash,
                           certificate_hash=proof.proof_hash,
                           details=Dict{Symbol, Any}(:entry => [i, j]))
    end
    return _accept(:B, :chordal_psd, :clique_replay, :coverage;
                   problem_hash=matrix.hash,
                   certificate_hash=proof.proof_hash)
end

function _clique_original_value(clique::CliquePSDProof, original_i::Int,
                                original_j::Int)
    local_i = findfirst(==(original_i), clique.vertices)
    local_j = findfirst(==(original_j), clique.vertices)
    (isnothing(local_i) || isnothing(local_j)) &&
        throw(ArgumentError("entry is outside clique"))
    return clique.matrix[local_i, local_j]
end

function _separator_value_payload(vertices::Vector{Int},
                                  left::SparseSymmetricRationalMatrix,
                                  right::SparseSymmetricRationalMatrix)
    left_entries = Any[]
    right_entries = Any[]
    for a in eachindex(vertices)
        for b in a:length(vertices)
            push!(left_entries, (; i=a, j=b, value=rational_string(left[a, b])))
            push!(right_entries, (; i=a, j=b, value=rational_string(right[a, b])))
        end
    end
    return (;
        vertices,
        left=left_entries,
        right=right_entries,
    )
end

function _read_json_document(json_text::AbstractString, label::AbstractString)
    try
        return JSON3.read(json_text)
    catch err
        throw(ArgumentError("invalid $label JSON: $(sprint(showerror, err))"))
    end
end

function _require_object(value, path::AbstractString)
    value isa JSON3.Object ||
        value isa AbstractDict ||
        throw(ArgumentError("$path must be a JSON object"))
    return value
end

function _require_array(value, path::AbstractString)
    value isa AbstractVector ||
        throw(ArgumentError("$path must be a JSON array"))
    return value
end

function _require_key(object, key::Symbol, path::AbstractString)
    haskey(object, key) || throw(ArgumentError("$path is missing required key `$key`"))
    return _object_value(object, key)
end

function _require_value(object, key::Symbol, expected, path::AbstractString)
    actual = _require_key(object, key, split(path, ".")[1])
    actual == expected || throw(ArgumentError("$path must be `$expected`; got `$actual`"))
    return actual
end

function _require_string(object, key::Symbol, path::AbstractString)
    value = _require_key(object, key, split(path, ".")[1])
    value isa AbstractString || throw(ArgumentError("$path must be a string"))
    return String(value)
end

function _require_integer(object, key::Symbol, path::AbstractString)
    value = _require_key(object, key, split(path, ".")[1])
    value isa Integer || throw(ArgumentError("$path must be an integer"))
    return Int(value)
end

function _parse_rational_string(value, path::AbstractString)
    value isa AbstractString || throw(ArgumentError("$path must be a rational string"))
    text = strip(String(value))
    m = match(r"^([+-]?\d+)(?:/(\d+))?$", text)
    isnothing(m) && throw(ArgumentError("$path is not a valid rational string: $value"))
    numerator_value = parse(BigInt, m.captures[1])
    denominator_value = isnothing(m.captures[2]) ? BigInt(1) :
                        parse(BigInt, m.captures[2])
    denominator_value != 0 || throw(ArgumentError("$path has zero denominator"))
    return Rational{BigInt}(numerator_value, denominator_value)
end

function _to_big_rational(value, path::AbstractString)
    value isa Integer && return Rational{BigInt}(BigInt(value), BigInt(1))
    value isa Rational && return Rational{BigInt}(BigInt(numerator(value)),
                                                  BigInt(denominator(value)))
    value isa AbstractString && return _parse_rational_string(value, path)
    throw(ArgumentError("$path contains non-exact value; expected integer or rational string"))
end

function _strict_validate_top_object(object, allowed::Set{Symbol},
                                     path::AbstractString)
    _require_object(object, path)
    for key in keys(object)
        symbol = Symbol(key)
        symbol in allowed ||
            throw(ArgumentError("$path contains unknown field `$(String(symbol))`"))
    end
    for key in allowed
        haskey(object, key) || throw(ArgumentError("$path is missing required key `$key`"))
    end
    return true
end

function _validate_object_keys(object,
                               required::Set{Symbol},
                               optional::Set{Symbol},
                               path::AbstractString)
    _require_object(object, path)
    allowed = union(required, optional)
    for key in keys(object)
        symbol = Symbol(key)
        symbol in allowed ||
            throw(ArgumentError("$path contains unknown field `$(String(symbol))`"))
    end
    for key in required
        haskey(object, key) || throw(ArgumentError("$path is missing required key `$key`"))
    end
    return true
end

function _reject_forbidden_trust_claims(value, path::AbstractString)
    if value isa JSON3.Object || value isa AbstractDict
        for key in keys(value)
            symbol = Symbol(key)
            symbol in FORBIDDEN_TRUST_KEYS &&
                throw(ArgumentError("$path.$(String(symbol)) is forbidden in trusted certificate data"))
            _reject_forbidden_trust_claims(_object_value(value, symbol),
                                           "$path.$(String(symbol))")
        end
    elseif value isa AbstractVector
        for (i, entry) in enumerate(value)
            _reject_forbidden_trust_claims(entry, "$path[$i]")
        end
    elseif value isa AbstractFloat
        throw(ArgumentError("$path contains a floating JSON number in trusted certificate data"))
    end
    return true
end

function _validate_sha256(value::AbstractString, path::AbstractString)
    startswith(value, SHA256_PREFIX) && length(value) == length(SHA256_PREFIX) + 64 ||
        throw(ArgumentError("$path must be a sha256 digest"))
    return true
end

function _v3_top_level_keys()
    return Set(Symbol[:certsdp_certificate_version, :certificate_type,
                      :certificate_id, :problem_hash, :claim, :proof,
                      :proof_dag, :metadata, :hash])
end

function _json_object_to_symbol_dict(object)
    _require_object(object, "object")
    dict = Dict{Symbol, Any}()
    for key in keys(object)
        dict[Symbol(key)] = _jsonify(_object_value(object, Symbol(key)))
    end
    return dict
end

function _jsonify(value)
    if value isa Dict
        return Dict(String(key) => _jsonify(entry) for (key, entry) in value)
    elseif value isa JSON3.Object
        return Dict(String(key) => _jsonify(_object_value(value, Symbol(key)))
                    for key in keys(value))
    elseif value isa AbstractVector
        return [_jsonify(entry) for entry in value]
    elseif value isa Symbol
        return String(value)
    elseif value isa Rational
        return rational_string(Rational{BigInt}(BigInt(numerator(value)),
                                                BigInt(denominator(value))))
    end
    return value
end

function _sha256_payload(payload)
    return SHA256_PREFIX * bytes2hex(sha256(JSON3.write(payload)))
end

function _accept(gate::Symbol, family::Symbol, stage::Symbol,
                 obligation_id::Symbol;
                 problem_hash=nothing,
                 certificate_hash=nothing,
                 block_id=nothing,
                 clique_id=nothing,
                 separator_id=nothing,
                 artifact_path=nothing,
                 details=Dict{Symbol, Any}())
    return DiagnosticReport(true, gate, family, stage, "accepted",
                            obligation_id, problem_hash, certificate_hash,
                            block_id, clique_id, separator_id, artifact_path,
                            details)
end

function _reject(gate::Symbol, family::Symbol, stage::Symbol,
                 obligation_id::Symbol, reason::AbstractString;
                 problem_hash=nothing,
                 certificate_hash=nothing,
                 block_id=nothing,
                 clique_id=nothing,
                 separator_id=nothing,
                 artifact_path=nothing,
                 details=Dict{Symbol, Any}())
    return DiagnosticReport(false, gate, family, stage, String(reason),
                            obligation_id, problem_hash, certificate_hash,
                            block_id, clique_id, separator_id, artifact_path,
                            details)
end

function _with_location(report::DiagnosticReport;
                        family=report.family,
                        block_id=report.block_id,
                        clique_id=report.clique_id,
                        separator_id=report.separator_id,
                        certificate_hash=report.certificate_hash,
                        artifact_path=report.artifact_path)
    return DiagnosticReport(report.accepted, report.gate, family, report.stage,
                            report.reason, report.obligation_id,
                            report.problem_hash, certificate_hash, block_id,
                            clique_id, separator_id, artifact_path,
                            report.details)
end

function _print_report(io::Union{Nothing, IO}, report::DiagnosticReport)
    isnothing(io) && return nothing
    print(io, diagnostic_report_text(report))
    return nothing
end

function _escape_html(text::AbstractString)
    return replace(String(text), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;",
                   "\"" => "&quot;")
end

function _object_value(object::JSON3.Object, key::Symbol)
    return getproperty(object, key)
end

function _object_value(object::AbstractDict, key::Symbol)
    haskey(object, key) && return object[key]
    return object[String(key)]
end

end
