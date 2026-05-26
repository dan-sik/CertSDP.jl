#!/usr/bin/env julia

pushfirst!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))

using CertSDP
using JSON3
using LinearAlgebra: I
using SHA: sha256
using Base.Filesystem: cp, mkpath, rm

include(joinpath(@__DIR__, "..", "test", "certsdp3", "helpers.jl"))

const ROOT = normpath(joinpath(@__DIR__, "..", "test", "fixtures", "certsdp3"))
const EXTERNAL_ROOT = normpath(joinpath(@__DIR__, "..", "test", "fixtures_external"))

function write_json(path, object)
    mkpath(dirname(path))
    open(path, "w") do io
        JSON3.pretty(io, object)
        println(io)
    end
    return path
end

function fixture_entry(; fixture_id, problem_family, expected_accepted=true,
                       tamper_files, max_runtime_seconds, max_memory_mb,
                       certificate_hash, problem_hash,
                       validation_purpose, gate_ids_covered,
                       source_class="synthetic_unit",
                       generated_by="scripts/generate_certsdp3_fixtures.jl",
                       source_file=nothing,
                       source_notes="deterministic replay fixture",
                       semantic_checks_required=Any[],
                       subprocess_cli_commands=Any[])
    return Dict(
        "fixture_id" => fixture_id,
        "problem_family" => problem_family,
        "expected_accepted" => expected_accepted,
        "tamper_files" => tamper_files,
        "max_runtime_seconds" => max_runtime_seconds,
        "max_memory_mb" => max_memory_mb,
        "certificate_hash" => certificate_hash,
        "problem_hash" => problem_hash,
        "required_optional_deps" => Any[],
        "validation_purpose" => validation_purpose,
        "gate_ids_covered" => gate_ids_covered,
        "source_class" => source_class,
        "generated_by" => generated_by,
        "source_file" => isnothing(source_file) ? "" : source_file,
        "source_notes" => source_notes,
        "semantic_checks_required" => semantic_checks_required,
        "subprocess_cli_commands" => subprocess_cli_commands,
        "performance_budget" => Dict("max_runtime_seconds" => max_runtime_seconds),
        "memory_budget" => Dict("max_memory_mb" => max_memory_mb),
        "densification_budget" => Dict("max_count" => occursin("chordal", problem_family) ? 0 : 999999),
    )
end

function hash_payload(object)
    return "sha256:" * bytes2hex(sha256(JSON3.write(object)))
end

function add_artifact_hash(object::Dict)
    object["artifact_hash"] = CertSDP.Adapters._artifact_hash(object)
    return object
end

function run_certsdp!(args::Vector{String})
    code = CertSDP.main(args; io=IOBuffer(), err=IOBuffer())
    code == 0 || error("CertSDP CLI command failed: $(join(args, " "))")
    return nothing
end

function regenerate_bundle!(name::AbstractString, cert_path::AbstractString)
    bundle_root = joinpath(ROOT, "bundles")
    out_dir = joinpath(bundle_root, name)
    isdir(out_dir) && rm(out_dir; recursive=true, force=true)
    run_certsdp!(["bundle", cert_path, "--out", out_dir * "/"])
    return out_dir
end

function copy_dir_fresh!(src::AbstractString, dst::AbstractString)
    isdir(dst) && rm(dst; recursive=true, force=true)
    cp(src, dst; force=true)
    return dst
end

function tamper_bundle_file!(source_name::AbstractString, target_name::AbstractString,
                             relpath::AbstractString, edit!::Function)
    bundle_root = joinpath(ROOT, "bundles")
    src = joinpath(bundle_root, source_name)
    dst = joinpath(bundle_root, target_name)
    isdir(dst) && rm(dst; recursive=true, force=true)
    cp(src, dst; force=true)
    path = joinpath(dst, relpath)
    data = JSON3.read(read(path, String))
    mutable = certsdp3_mutable_json(data)
    edit!(mutable)
    write_json(path, mutable)
    return dst
end

function sparse_matrix_json(matrix)
    return K3.sparse_matrix_json(matrix)
end

function tssos_block_json(block_id::String, clique_id::String, basis_id::String,
                          matrix, proof)
    return Dict(
        "id" => block_id,
        "clique_id" => clique_id,
        "basis_id" => basis_id,
        "gram_matrix" => sparse_matrix_json(matrix),
        "psd_proof" => K3.low_rank_proof_json(proof),
    )
end

function quantum_fixture_certificate(; word_count::Int, dimension::Int,
                                     relation_count::Int,
                                     bound)
    bound_value = Rational{BigInt}(BigInt(numerator(bound)),
                                   BigInt(denominator(bound)))
    variables = [Symbol("A$i") for i in 1:div(relation_count, 2)]
    append!(variables, [Symbol("B$i") for i in 1:(relation_count - length(variables))])
    relations = K3.AbstractQuantumRelation[]
    for (i, variable) in enumerate(variables)
        push!(relations, K3.ProjectionRelation(Symbol("proj_", variable), variable))
    end
    push!(relations,
          K3.CommutationRelation(:comm_AB,
                                 [variable for variable in variables if startswith(String(variable), "A")],
                                 [variable for variable in variables if startswith(String(variable), "B")]))
    push!(relations, K3.TraceCyclicRelation(:trace_cyclic))
    push!(relations, K3.StarInvolutionRelation(:star_involution))
    push!(relations, K3.NormalizationRelation(:trace_one, 1//1))
    basis = Vector{Symbol}[]
    push!(basis, Symbol[])
    for variable in variables
        length(basis) >= word_count && break
        push!(basis, [variable])
    end
    for first in variables, second in variables
        length(basis) >= word_count && break
        push!(basis, [first, second])
    end
    for first in variables, second in variables, third in variables
        length(basis) >= word_count && break
        push!(basis, [first, second, third])
    end
    basis = basis[1:word_count]
    problem = K3.NPAProblem(variables, relations, basis; trace_cyclic=true)
    moment = K3.SparseSymmetricRationalMatrix(dimension,
                                               [(i, i, 1//1) for i in 1:dimension])
    factor = [[i == j ? 1//1 : 0//1 for j in 1:dimension]
              for i in 1:dimension]
    psd = K3.ExactLowRankPSDProof(moment, factor, fill(1//1, dimension))
    objective_terms = Tuple{Vector{Symbol}, Rational{BigInt}}[
        (K3._npa_entry_input_word(problem, 1, 1), 1//1),
        (K3._npa_entry_input_word(problem, 2, 2), bound_value - 1//1),
    ]
    witnesses = K3.NCRewriteWitness[]
    for (i, j, _) in moment.entries
        input = K3._npa_entry_input_word(problem, i, j)
        push!(witnesses,
              K3.NCRewriteWitness(input,
                                  K3.NCRewriteStep[],
                                  input,
                                  Symbol[],
                                  Vector{Symbol}[],
                                  Vector{Symbol}[]))
    end
    moment_cert = K3.NCMomentMatrixCertificate(problem, moment, psd,
                                               objective_terms,
                                               witnesses)
    cert = K3.make_quantum_bound_certificate(problem, moment_cert,
                                             objective_terms, bound_value)
    return (; problem, cert)
end

function nctssos_fixture_artifact()
    variables = ["A1", "A2", "A3", "B1", "B2", "B3"]
    words = Any[Any[]]
    for variable in variables
        push!(words, Any[variable])
    end
    for first in variables, second in variables
        length(words) >= 104 && break
        push!(words, Any[first, second])
    end
    for first in variables, second in variables, third in variables
        length(words) >= 104 && break
        push!(words, Any[first, second, third])
    end
    words = words[1:104]
    relations = Any[]
    for variable in variables
        push!(relations,
              Dict("kind" => "ProjectionRelation",
                   "id" => "proj_$variable",
                   "data" => Dict("symbol" => variable)))
    end
    push!(relations,
          Dict("kind" => "CommutationRelation",
               "id" => "comm_AB",
               "data" => Dict("left_symbols" => variables[1:3],
                              "right_symbols" => variables[4:6])))
    push!(relations,
          Dict("kind" => "TraceCyclicRelation", "id" => "trace_cyclic",
               "data" => Dict()))
    push!(relations,
          Dict("kind" => "StarInvolutionRelation", "id" => "star",
               "data" => Dict()))
    push!(relations,
          Dict("kind" => "NormalizationRelation", "id" => "trace_one",
               "data" => Dict("value" => "1")))
    moment_dimension = length(words)
    matrix = K3.SparseSymmetricRationalMatrix(moment_dimension,
                                              [(i, i, 1//1)
                                               for i in 1:moment_dimension])
    factor = [[i == j ? 1//1 : 0//1 for j in 1:moment_dimension]
              for i in 1:moment_dimension]
    proof = K3.ExactLowRankPSDProof(matrix, factor,
                                    fill(1//1, moment_dimension))
    terms = Any[
        Dict("word" => Any[], "coefficient" => "1"),
        Dict("word" => ["$(variables[1])_star", variables[1]], "coefficient" => "2"),
    ]
    rewrite_witnesses = Any[]
    for i in 1:moment_dimension
        word = i == 1 ? Any[] : Any[[string(symbol, "_star") for symbol in reverse(words[i])]..., words[i]...]
        push!(rewrite_witnesses,
              Dict("input_word" => word,
                   "steps" => Any[],
                   "final_word" => word,
                   "relation_ids_used" => Any[],
                   "trace_rotations" => Any[],
                   "star_steps" => Any[]))
    end
    artifact = Dict(
        "certsdp_nctssos_artifact_version" => "3.0",
        "variables" => variables,
        "words" => words,
        "involution_convention" => "star_suffix",
        "trace_cyclic" => true,
        "quotient_relations" => relations,
        "block_bases" => Any[
            Dict("id" => "basis_1", "words" => words[1:moment_dimension])
        ],
        "gram_blocks" => Any[
            Dict("id" => "moment_1",
                 "basis_id" => "basis_1",
                 "moment_matrix" => sparse_matrix_json(matrix),
                 "psd_proof" => K3.low_rank_proof_json(proof))
        ],
        "coefficient_maps" => Any[
            Dict("block_id" => "moment_1", "terms" => terms)
        ],
        "objective_bound" => "3",
        "provenance" => Dict("frontend" => "NCTSSOS fixture",
                             "status" => "ignored_candidate_metadata"),
        "frontend_metadata" => Dict("package" => "NCTSSOS-like",
                                    "relaxation" => "trace_medium"),
        "solver_metadata" => Dict("solver_status" => "optimal",
                                  "residual" => "ignored_untrusted"),
        "rewrite_witnesses" => rewrite_witnesses,
        "source_hash" => hash_payload(Dict("source" => "nctssos_trace_medium")),
    )
    add_artifact_hash(artifact)
    return artifact
end

function block_active_fixture_proof(block, block_index::Int,
                                    variable_names::Vector{Symbol})
    field = K3.AlgebraicFieldCertificate(Symbol("K_block_", block_index),
                                         :alpha,
                                         [-2//1, 0//1, 1//1],
                                         (1//1, 2//1))
    zero = K3.AlgebraicElement(field, [0//1, 0//1])
    one = K3.AlgebraicElement(field, [1//1, 0//1])
    alpha = K3.AlgebraicElement(field, [0//1, 1//1])
    values = Dict{Symbol, K3.AlgebraicElement}()
    for (i, variable) in enumerate(variable_names)
        values[variable] = isodd(i) ? alpha : one
    end
    equations = K3.AlgebraicEquationObligation[]
    for (i, variable) in enumerate(variable_names)
        value = values[variable]
        push!(equations,
              K3.AlgebraicEquationObligation(Symbol("incidence_", block_index, "_", i),
                                             [K3.AlgebraicLinearTerm(variable, one)],
                                             K3.AlgebraicElement(field, -value.coefficients)))
    end
    push!(equations,
          K3.AlgebraicEquationObligation(Symbol("field_relation_", block_index),
                                         [K3.AlgebraicLinearTerm(variable_names[1], alpha)],
                                         K3.AlgebraicElement(field, [-2//1, 0//1])))
    gauge = K3.AlgebraicEquationObligation[
        K3.AlgebraicEquationObligation(Symbol("gauge_", block_index),
                                       [K3.AlgebraicLinearTerm(variable_names[2], one)],
                                       K3.AlgebraicElement(field, [-1//1, 0//1]))
    ]
    return K3.BlockNativeActiveBlockProof(block_index,
                                          block.block_hash,
                                          field,
                                          values,
                                          equations,
                                          gauge)
end

function block_inactive_fixture_proof(block, block_index::Int)
    n = 20
    matrix = K3.SparseSymmetricRationalMatrix(n, [(i, i, 1//1) for i in 1:n])
    factor = [[i == j ? 1//1 : 0//1 for j in 1:n] for i in 1:n]
    psd = K3.ExactLowRankPSDProof(matrix, factor, fill(1//1, n))
    return K3.BlockNativeInactivePSDProof(block_index, block.block_hash,
                                          matrix, psd)
end

function sparse_sos_fixture(variable_count::Int, block_count::Int;
                            putinar::Bool=false)
    variables = [Symbol("z$i") for i in 1:variable_count]
    terms = K3.PolynomialTerm[]
    blocks = K3.SparseSOSBlock[]
    localizing = K3.LocalizingMatrixProof[]
    for block_index in 1:block_count
        exponents = fill(0, variable_count)
        exponents[((block_index - 1) % variable_count) + 1] = 2
        matrix = K3.SparseSymmetricRationalMatrix(40,
                                                  [(i, i, 1//1) for i in 1:40])
        factor = [[i == j ? 1//1 : 0//1 for j in 1:40] for i in 1:40]
        proof = K3.ExactLowRankPSDProof(matrix, factor, fill(1//1, 40))
        basis = Vector{Int}[]
        for basis_index in 1:40
            row = fill(0, variable_count)
            row[((block_index + basis_index - 2) % variable_count) + 1] = 1
            push!(basis, row)
        end
        gram_terms = CertSDP.SOSGramExpansion.gram_polynomial(
            K3.SparseSOSBlock(Symbol("tmp_", block_index),
                              Symbol("clique_", ((block_index - 1) % 4) + 1),
                              basis,
                              matrix,
                              proof,
                              K3.PolynomialTerm[]))
        block_terms = [K3.PolynomialTerm(exp, coeff)
                       for (exp, coeff) in gram_terms]
        block = K3.SparseSOSBlock(Symbol("gram_", block_index),
                                  Symbol("clique_", ((block_index - 1) % 4) + 1),
                                  basis,
                                  matrix,
                                  proof,
                                  block_terms)
        if putinar
            constraint = [K3.PolynomialTerm(fill(0, variable_count), 1//1)]
            push!(localizing,
                  K3.LocalizingMatrixProof(Symbol("localizing_", block_index),
                                           block.clique_id,
                                           constraint,
                                           block))
        else
            push!(blocks, block)
            append!(terms, block_terms)
        end
        putinar && append!(terms, block_terms)
    end
    cliques = [variables[1:min(variable_count, 4)],
               variables[max(1, variable_count - 3):variable_count],
               variables[1:2:variable_count],
               variables[2:2:variable_count]]
    problem = K3.SparseSOSProblem(variables, terms, cliques, 0//1)
    putinar_cert = if putinar
        identity_hash = "sha256:" * bytes2hex(sha256(JSON3.write((;
            bound=K3.rational_string(problem.lower_bound),
            localizing=[K3.localizing_matrix_proof_json(block)
                        for block in localizing]))))
        K3.PutinarCertificate(localizing, problem.lower_bound, identity_hash)
    else
        nothing
    end
    cert = K3.make_sparse_sos_certificate(problem, blocks; putinar=putinar_cert)
    return cert
end

function symmetry_fixture_certificate()
    variables = [:x1, :x2, :x3, :x4, :x5, :x6]
    generator = K3.SymmetryPermutation(:cyclic_shift, [2, 3, 4, 5, 6, 1])
    group = K3.SymmetryGroupCertificate(variables, [generator])
    exponents = Vector{Int}[]
    for i in 1:6
        row = fill(0, 6)
        row[i] = 2
        push!(exponents, row)
    end
    for i in 1:6
        row = fill(0, 6)
        row[i] = 1
        row[mod1(i + 1, 6)] = 1
        push!(exponents, row)
    end
    for i in 1:6
        row = fill(0, 6)
        row[i] = 1
        row[mod1(i + 2, 6)] = 1
        push!(exponents, row)
    end
    orbit = K3.OrbitBasisCertificate(exponents,
                                     [collect(1:6),
                                      collect(7:12),
                                      collect(13:18)])
    original = K3.SparseSymmetricRationalMatrix(18,
                                                [(i, i, 1//1) for i in 1:18])
    blocks = K3.SparseSymmetricRationalMatrix[]
    for block_index in 1:3
        start = (block_index - 1) * 6 + 1
        push!(blocks,
              K3.SparseSymmetricRationalMatrix(18,
                                               [(i, i, 1//1)
                                                for i in start:(start + 5)]))
    end
    return K3.BlockDiagonalizationCertificate(original.hash,
                                              group,
                                              orbit,
                                              blocks,
                                              original,
                                              original)
end

function main()
    mkpath(ROOT)
    mkpath(EXTERNAL_ROOT)

    rank = 10
    low_factor = [[i == j ? 1//1 : 0//1 for j in 1:rank] for i in 1:150]
    low_diagonal = fill(1//1, rank)
    low_entries = Tuple{Int, Int, Rational{BigInt}}[(i, i, 1//1) for i in 1:rank]
    low_matrix = K3.SparseSymmetricRationalMatrix(150, low_entries)
    low_proof = K3.ExactLowRankPSDProof(low_matrix, low_factor, low_diagonal)
    low_cert = K3.make_low_rank_psd_certificate(low_matrix, low_proof)
    low = (; matrix=low_matrix, proof=low_proof, cert=low_cert)
    low_dir = joinpath(ROOT, "psd_factor_rational_150")
    write_json(joinpath(low_dir, "certificate.json"),
               K3.certificate_json_v3(low.cert))
    tampered = certsdp3_cert_json(low.cert)
    tampered[:proof][:low_rank_proof][:diagonal][1] = "-1"
    write_json(joinpath(low_dir, "tampered_negative_diagonal.json"), tampered)

    alg_dir = joinpath(ROOT, "psd_factor_algebraic_40")
    alg_matrix = K3.SparseSymmetricRationalMatrix(40, [(i, i, 1//1) for i in 1:40])
    alg_field = K3.AlgebraicFieldCertificate(:Kcubic_psd, :alpha,
                                             [-1//1, -1//1, 0//1, 1//1],
                                             (1//1, 2//1))
    alg_one = K3.AlgebraicElement(alg_field, [1//1, 0//1, 0//1])
    alg_zero = K3.AlgebraicElement(alg_field, [0//1, 0//1, 0//1])
    alg_diag = K3.AlgebraicElement(alg_field, [1//1, 0//1, 0//1])
    alg_factor = [[i == j ? alg_one : alg_zero
                   for j in 1:40] for i in 1:40]
    alg_proof = K3.ExactAlgebraicLowRankPSDProof(alg_matrix,
                                                 alg_field,
                                                 alg_factor,
                                                 fill(alg_diag, 40))
    write_json(joinpath(alg_dir, "certificate.json"),
               K3.algebraic_low_rank_psd_certificate_json(alg_matrix, alg_proof))
    alg_tamper = certsdp3_mutable_json(K3.algebraic_low_rank_psd_certificate_json(alg_matrix,
                                                                                  alg_proof))
    alg_tamper[:sign_certificates][1][:sign] = "negative"
    write_json(joinpath(alg_dir, "tampered_algebraic_sign.json"), alg_tamper)

    chordal = certsdp3_chordal_fixture(n=120, clique_size=10, overlap=4)
    chordal_dir = joinpath(ROOT, "sparse_chordal_120")
    write_json(joinpath(chordal_dir, "certificate.json"),
               K3.certificate_json_v3(chordal.cert))
    bad_separator = certsdp3_cert_json(chordal.cert)
    bad_separator[:proof][:chordal_proof][:separator_proofs][1][:value_hash] =
        "sha256:" * repeat("0", 64)
    write_json(joinpath(chordal_dir, "tampered_wrong_separator.json"),
               bad_separator)
    bad_clique = certsdp3_cert_json(chordal.cert)
    bad_clique[:proof][:chordal_proof][:clique_proofs][1][:matrix][:entries][1][:value] = "2"
    bad_clique[:proof][:chordal_proof][:clique_proofs][1][:matrix][:hash] =
        "sha256:" * repeat("0", 64)
    write_json(joinpath(chordal_dir, "tampered_wrong_clique_psd.json"),
               bad_clique)
    write_json(joinpath(chordal_dir, "expected_report.json"),
               K3.diagnostic_report_json(K3.verify_certificate(chordal.cert)))

    stress = certsdp3_chordal_fixture(n=3000, clique_size=10, overlap=8,
                                      complete_cliques=false)
    stress_dir = joinpath(ROOT, "sparse_chordal_stress_3000")
    write_json(joinpath(stress_dir, "certificate.json"),
               K3.certificate_json_v3(stress.cert))
    stress_separator = certsdp3_cert_json(stress.cert)
    stress_separator[:proof][:chordal_proof][:separator_proofs][1][:value_hash] =
        "sha256:" * repeat("1", 64)
    write_json(joinpath(stress_dir, "tampered_separator_entry_changed.json"),
               stress_separator)
    stress_clique = certsdp3_cert_json(stress.cert)
    stress_clique[:proof][:chordal_proof][:clique_proofs][1][:psd_proof][:diagonal][1] = "-1"
    write_json(joinpath(stress_dir, "tampered_clique_psd_proof_changed.json"),
               stress_clique)
    stress_graph = certsdp3_cert_json(stress.cert)
    stress_graph[:proof][:chordal_proof][:structure][:graph_hash] =
        "sha256:" * repeat("2", 64)
    write_json(joinpath(stress_dir, "tampered_graph_hash_changed.json"),
               stress_graph)

    block_dir = joinpath(ROOT, "block_native_algebraic_medium")
    vars = [Symbol("x", i) for i in 1:20]
    blocks = CertSDP.LMIProblem[]
    for block_index in 1:12
        n = 20
        A0 = Matrix{Rational{BigInt}}(I, n, n)
        A = [zeros(Rational{BigInt}, n, n) for _ in vars]
        push!(blocks, CertSDP.LMIProblem(A0, A; vars))
    end
    block_problem = CertSDP.BlockLMIProblem(blocks;
                                            objective=zeros(Rational{BigInt}, length(vars)))
    profiles = CertSDP.RankProfile[]
    for i in 1:12
        n = CertSDP.matrix_size(block_problem.blocks[i])
        rank = i <= 4 ? n - 2 : n
        pivots = collect(1:rank)
        push!(profiles,
              CertSDP.RankProfile(rank, pivots, pivots, collect(1:n), BigFloat(0),
                                  BigFloat[], BigFloat(0), :fixture))
    end
    incidence = CertSDP.build_incidence_system(block_problem, nothing;
                                               rank_profiles=profiles,
                                               active_blocks=1:4,
                                               inactive_blocks=5:12,
                                               slicing=:paper,
                                               kernel_prefix=:BN)
    active_proofs = Dict(i => block_active_fixture_proof(incidence.blocks[i],
                                                         i,
                                                         incidence.blocks[i].variable_names)
                         for i in 1:4)
    inactive_proofs = Dict(i => block_inactive_fixture_proof(incidence.blocks[i],
                                                             i)
                           for i in 5:12)
    block_cert = K3.make_block_native_algebraic_certificate(incidence;
                                                            active_block_proofs=active_proofs,
                                                            inactive_psd_proofs=inactive_proofs)
    write_json(joinpath(block_dir, "problem.json"), CertSDP.block_lmi_problem_json(block_problem))
    write_json(joinpath(block_dir, "approx.json"),
               Dict("certsdp_fixture" => "block_native_rank_profiles",
                    "rank_profiles" => [Dict("block_index" => i,
                                             "rank" => profiles[i].rank,
                                             "kernel_dimension" => CertSDP.matrix_size(block_problem.blocks[i]) - profiles[i].rank)
                                        for i in eachindex(profiles)]))
    write_json(joinpath(block_dir, "msolve_output_fixture.json"),
               Dict("status" => "fixture_only_no_external_msolve",
                    "candidate_hashes" => Dict(string(k) => v.proof_hash
                                                for (k, v) in active_proofs)))
    write_json(joinpath(block_dir, "certificate.json"),
               K3.block_native_algebraic_certificate_json(block_cert))
    tampered_block3 = certsdp3_mutable_json(K3.block_native_algebraic_certificate_json(block_cert))
    deleteat!(tampered_block3[:active_block_proofs], 3)
    write_json(joinpath(block_dir, "tampered_block_3_kernel.json"), tampered_block3)
    tampered_block5 = certsdp3_mutable_json(K3.block_native_algebraic_certificate_json(block_cert))
    tampered_block5[:inactive_psd_proofs][1][:psd_proof][:diagonal][1] = "-1"
    write_json(joinpath(block_dir, "tampered_block_5_psd.json"), tampered_block5)
    tampered_root = certsdp3_mutable_json(K3.block_native_algebraic_certificate_json(block_cert))
    tampered_root[:active_block_proofs][1][:field][:isolating_interval] = ["3", "4"]
    write_json(joinpath(block_dir, "tampered_root_interval.json"), tampered_root)

    pd_dir = joinpath(ROOT, "primal_dual_portfolio_50")
    diag_matrix(values) = K3.SparseSymmetricRationalMatrix(length(values),
                                                           [(i, i, value)
                                                            for (i, value) in enumerate(values)
                                                            if value != 0//1])
    pd_blocks = K3.ConicAffineBlock[]
    pd_B = [diag_matrix([0//1, 2//1]),
            diag_matrix([3//1, 0//1]),
            diag_matrix([0//1, 5//1]),
            diag_matrix([2//1, 0//1])]
    pd_A = [
        [diag_matrix([1//1, 0//1]), diag_matrix([0//1, 1//1]),
         diag_matrix([1//1, 1//1]), diag_matrix([2//1, 0//1]),
         diag_matrix([0//1, 2//1]), diag_matrix([1//1, 2//1]),
         diag_matrix([2//1, 1//1]), diag_matrix([3//1, 1//1])],
        [diag_matrix([2//1, 1//1]), diag_matrix([1//1, 3//1]),
         diag_matrix([0//1, 1//1]), diag_matrix([1//1, 0//1]),
         diag_matrix([2//1, 2//1]), diag_matrix([3//1, 0//1]),
         diag_matrix([0//1, 3//1]), diag_matrix([1//1, 1//1])],
        [diag_matrix([0//1, 2//1]), diag_matrix([3//1, 0//1]),
         diag_matrix([1//1, 2//1]), diag_matrix([2//1, 2//1]),
         diag_matrix([1//1, 0//1]), diag_matrix([0//1, 1//1]),
         diag_matrix([2//1, 3//1]), diag_matrix([1//1, 4//1])],
        [diag_matrix([1//1, 1//1]), diag_matrix([2//1, 0//1]),
         diag_matrix([0//1, 2//1]), diag_matrix([3//1, 1//1]),
         diag_matrix([1//1, 3//1]), diag_matrix([2//1, 2//1]),
         diag_matrix([4//1, 0//1]), diag_matrix([0//1, 4//1])],
    ]
    pd_dual_variables = [diag_matrix([2//1, 0//1]),
                         diag_matrix([0//1, 3//1]),
                         diag_matrix([1//1, 0//1]),
                         diag_matrix([0//1, 2//1])]
    for i in 1:4
        push!(pd_blocks,
              K3.ConicAffineBlock(Symbol(i == 4 ? "diag_block" : "psd_block_$i"),
                                  i == 4 ? :diagonal_nonnegative : :PSD,
                                  pd_B[i],
                                  pd_A[i]))
    end
    pd_zero_problem = K3.ExactConicProblem(:min,
                                           [Symbol("x$i") for i in 1:8],
                                           fill(0//1, 8),
                                           pd_blocks)
    pd_problem = K3.ExactConicProblem(:min,
                                      [Symbol("x$i") for i in 1:8],
                                      K3._conic_dual_adjoint(pd_zero_problem,
                                                            pd_dual_variables),
                                      pd_blocks)
    pd_cert = K3.make_primal_dual_optimality_certificate(pd_problem,
                                                         fill(0//1, 8),
                                                         pd_dual_variables)
    write_json(joinpath(pd_dir, "problem_affine_sdp_medium.json"),
               K3.exact_conic_problem_json(pd_problem))
    write_json(joinpath(pd_dir, "certificate.json"),
               K3.primal_dual_optimality_certificate_json(pd_cert))
    real_pd_dir = normpath(joinpath(@__DIR__, "..", "test",
                                    "fixtures_real", "primal_dual"))
    mkpath(real_pd_dir)
    write_json(joinpath(real_pd_dir, "problem_affine_sdp_medium.json"),
               K3.exact_conic_problem_json(pd_problem))
    write_json(joinpath(real_pd_dir, "certificate_optimal.json"),
               K3.primal_dual_optimality_certificate_json(pd_cert))
    pd_bad_cert = K3.make_primal_dual_optimality_certificate(pd_problem,
                                                             fill(0//1, 8),
                                                             pd_dual_variables;
                                                             gap=1//1)
    pd_tamper = certsdp3_mutable_json(K3.primal_dual_optimality_certificate_json(pd_bad_cert))
    write_json(joinpath(pd_dir, "tampered_gap_value.json"), pd_tamper)

    farkas_dir = joinpath(ROOT, "farkas_infeasible_lmi_medium")
    fk_blocks = [
        K3.ConicAffineBlock(:farkas_psd_1, :PSD,
                            diag_matrix([-1//1, 0//1]),
                            pd_A[1]),
        K3.ConicAffineBlock(:farkas_psd_2, :PSD,
                            diag_matrix([0//1, 0//1]),
                            pd_A[2]),
        K3.ConicAffineBlock(:farkas_psd_3, :PSD,
                            diag_matrix([0//1, 0//1]),
                            pd_A[3]),
    ]
    fk_dual_variables = [diag_matrix([1//1, 0//1]),
                         diag_matrix([0//1, 0//1]),
                         diag_matrix([0//1, 0//1])]
    fk_zero_problem = K3.ExactConicProblem(:min,
                                           [Symbol("x$i") for i in 1:8],
                                           fill(0//1, 8),
                                           fk_blocks)
    fk_problem = K3.ExactConicProblem(:min,
                                      [Symbol("x$i") for i in 1:8],
                                      K3._conic_dual_adjoint(fk_zero_problem,
                                                            fk_dual_variables),
                                      fk_blocks)
    fk_proofs = [K3._matrix_diagonal_psd_proof(matrix) for matrix in fk_dual_variables]
    fk_cert = K3.make_farkas_infeasibility_certificate(fk_problem,
                                                       fk_dual_variables,
                                                       fk_proofs)
    write_json(joinpath(farkas_dir, "problem_affine_sdp_medium.json"),
               K3.exact_conic_problem_json(fk_problem))
    write_json(joinpath(farkas_dir, "certificate.json"),
               K3.farkas_infeasibility_certificate_json(fk_cert))
    write_json(joinpath(real_pd_dir, "certificate_farkas.json"),
               K3.farkas_infeasibility_certificate_json(fk_cert))
    fk_tamper = certsdp3_mutable_json(K3.farkas_infeasibility_certificate_json(fk_cert))
    fk_tamper[:multiplier_identity_lhs][1] = string(parse(BigInt, split(String(fk_tamper[:multiplier_identity_lhs][1]), "/")[1]) + 1)
    write_json(joinpath(farkas_dir, "tampered_multiplier.json"), fk_tamper)

    tssos_dir = joinpath(ROOT, "tssos_sparse_industry_medium")
    tssos_variables = ["x$i" for i in 1:12]
    tssos_cliques = [tssos_variables[1:4],
                     tssos_variables[3:6],
                     tssos_variables[5:8],
                     tssos_variables[7:10],
                     tssos_variables[9:12]]
    monomial_bases = Any[]
    gram_blocks = Any[]
    coefficient_maps = Any[]
    objective_terms = Any[]
    for block_index in 1:10
        basis_id = "basis_$block_index"
        exponents = Any[]
        for j in 1:4
            row = fill(0, length(tssos_variables))
            row[((block_index + j - 2) % length(tssos_variables)) + 1] = 1
            push!(exponents, row)
        end
        push!(monomial_bases, Dict("id" => basis_id, "exponents" => exponents))
        matrix = K3.SparseSymmetricRationalMatrix(4, [(i, i, 1//1) for i in 1:4])
        factor = [[i == j ? 1//1 : 0//1 for j in 1:4] for i in 1:4]
        proof = K3.ExactLowRankPSDProof(matrix, factor, fill(1//1, 4))
        block_id = "gram_$block_index"
        push!(gram_blocks,
              tssos_block_json(block_id,
                               "clique_$(((block_index - 1) % length(tssos_cliques)) + 1)",
                               basis_id,
                               matrix,
                               proof))
        block_terms = Any[]
        for row in exponents
            term = Dict("exponents" => [2 * value for value in row],
                        "coefficient" => "1")
            push!(block_terms, term)
            push!(objective_terms, deepcopy(term))
        end
        push!(coefficient_maps, Dict("block_id" => block_id,
                                     "terms" => block_terms))
    end
    tssos_artifact = add_artifact_hash(Dict(
        "certsdp_tssos_artifact_version" => "3.0",
        "variables" => tssos_variables,
        "objective_polynomial" => objective_terms,
        "constraints" => [Dict("id" => "c$i",
                               "terms" => Any[objective_terms[((i - 1) % length(objective_terms)) + 1]])
                           for i in 1:12],
        "cliques" => tssos_cliques,
        "monomial_bases" => monomial_bases,
        "gram_blocks" => gram_blocks,
        "localizing_blocks" => Any[],
        "coefficient_maps" => coefficient_maps,
        "bound" => "0",
        "provenance" => Dict("frontend" => "TSSOS fixture",
                             "status" => "ignored_candidate_metadata"),
        "frontend_metadata" => Dict("package" => "TSSOS-like",
                                    "relaxation_order" => 2),
        "solver_metadata" => Dict("solver_status" => "optimal",
                                  "residual" => "ignored_untrusted"),
        "source_raw_hash" => hash_payload(Dict("source" => "tssos_sparse_industry_medium")),
    ))
    write_json(joinpath(tssos_dir, "artifact.json"), tssos_artifact)
    tssos_raw = Dict(
        "tssos_raw_artifact_version" => "external-like-1",
        "variables" => tssos_variables,
        "objective" => objective_terms,
        "constraints" => tssos_artifact["constraints"],
        "relaxation_order" => 2,
        "correlative_sparsity_cliques" => tssos_cliques,
        "monomial_bases" => monomial_bases,
        "gram_blocks" => gram_blocks,
        "localizing_matrices" => Any[],
        "coefficient_maps" => coefficient_maps,
        "bound" => "0",
        "frontend_metadata" => Dict("package" => "TSSOS-like external",
                                    "artifact_shape" => "raw"),
        "solver_metadata" => Dict("solver_status" => "optimal",
                                  "residual" => "ignored_untrusted",
                                  "raw_log_excerpt" => "untrusted log is not proof")
    )
    tssos_external = joinpath(EXTERNAL_ROOT, "tssos")
    mkpath(tssos_external)
    write_json(joinpath(tssos_external, "raw_tssos_sparse_poly_medium.json"),
               tssos_raw)
    opf_raw = deepcopy(tssos_raw)
    opf_raw["frontend_metadata"]["case"] = "opf_like_5bus"
    write_json(joinpath(tssos_external, "raw_tssos_opf_like_5bus.json"),
               opf_raw)
    control_raw = deepcopy(tssos_raw)
    control_raw["frontend_metadata"]["case"] = "control_lyapunov"
    write_json(joinpath(tssos_external, "raw_tssos_control_lyapunov.json"),
               control_raw)
    write(joinpath(tssos_external, "README_SOURCE.txt"),
          "External-like TSSOS artifacts shaped after sparse moment-SOS frontend exports. Solver metadata is untrusted and ignored by CertSDP replay.\n")
    tssos_candidate = CertSDP.import_tssos_artifact(joinpath(tssos_dir, "artifact.json"))
    write_json(joinpath(tssos_dir, "certificate.json"),
               K3.sparse_sos_certificate_json(tssos_candidate.certificate))
    tssos_basis_tamper = deepcopy(tssos_artifact)
    tssos_basis_tamper["monomial_bases"][1]["exponents"][1][1] = 2
    add_artifact_hash(tssos_basis_tamper)
    write_json(joinpath(tssos_dir, "tampered_clique_basis.json"),
               tssos_basis_tamper)
    tssos_bound_tamper = deepcopy(tssos_artifact)
    tssos_bound_tamper["bound"] = "1"
    add_artifact_hash(tssos_bound_tamper)
    write_json(joinpath(tssos_dir, "tampered_objective_bound.json"),
               tssos_bound_tamper)
    tssos_coeff_tamper = deepcopy(tssos_artifact)
    tssos_coeff_tamper["coefficient_maps"][1]["terms"][1]["coefficient"] = "2"
    add_artifact_hash(tssos_coeff_tamper)
    write_json(joinpath(tssos_dir, "tampered_coefficient_map.json"),
               tssos_coeff_tamper)

    sos_dir = joinpath(ROOT, "sparse_sos_control_lyapunov")
    sos_cert = sparse_sos_fixture(5, 6)
    write_json(joinpath(sos_dir, "certificate.json"),
               K3.sparse_sos_certificate_json(sos_cert))
    sos_poly_tamper = certsdp3_mutable_json(K3.sparse_sos_certificate_json(sos_cert))
    sos_poly_tamper[:problem][:target_terms][1][:coefficient] = "2"
    write_json(joinpath(sos_dir, "tampered_polynomial_coefficient.json"),
               sos_poly_tamper)
    sos_gram_tamper = certsdp3_mutable_json(K3.sparse_sos_certificate_json(sos_cert))
    sos_gram_tamper[:sos_blocks][1][:psd_proof][:diagonal][1] = "-1"
    write_json(joinpath(sos_dir, "tampered_gram_block.json"),
               sos_gram_tamper)

    putinar_dir = joinpath(ROOT, "sparse_putinar_opf_5bus")
    putinar_cert = sparse_sos_fixture(10, 8; putinar=true)
    write_json(joinpath(putinar_dir, "certificate.json"),
               K3.sparse_sos_certificate_json(putinar_cert))
    putinar_bound_tamper = certsdp3_mutable_json(K3.sparse_sos_certificate_json(putinar_cert))
    putinar_bound_tamper[:putinar][:bound] = "2"
    write_json(joinpath(putinar_dir, "tampered_bound.json"),
               putinar_bound_tamper)
    putinar_local_tamper = certsdp3_mutable_json(K3.sparse_sos_certificate_json(putinar_cert))
    putinar_local_tamper[:putinar][:localizing_blocks][1][:sos_block][:coefficient_terms][1][:coefficient] = "3"
    write_json(joinpath(putinar_dir, "tampered_localizing_coefficient_map.json"),
               putinar_local_tamper)

    chsh_dir = joinpath(ROOT, "quantum_chsh_level2")
    chsh = quantum_fixture_certificate(word_count=32,
                                       dimension=32,
                                       relation_count=4,
                                       bound=2//1)
    chsh_json = certsdp3_mutable_json(K3.quantum_bound_certificate_json(chsh.cert))
    write_json(joinpath(chsh_dir, "certificate.json"), chsh_json)
    chsh_relation_tamper = deepcopy(chsh_json)
    deleteat!(chsh_relation_tamper[:problem][:relations], 1)
    write_json(joinpath(chsh_dir, "tampered_relation_removed.json"),
               chsh_relation_tamper)
    chsh_word_tamper = deepcopy(chsh_json)
    chsh_word_tamper[:problem][:word_basis][2] = ["BAD"]
    write_json(joinpath(chsh_dir, "tampered_word_basis.json"),
               chsh_word_tamper)
    chsh_objective_tamper = deepcopy(chsh_json)
    chsh_objective_tamper[:objective_terms][1][:coefficient] = "3"
    write_json(joinpath(chsh_dir, "tampered_objective.json"),
               chsh_objective_tamper)

    i3322_dir = joinpath(ROOT, "quantum_i3322_medium")
    i3322 = quantum_fixture_certificate(word_count=82,
                                        dimension=82,
                                        relation_count=12,
                                        bound=3//1)
    i3322_json = certsdp3_mutable_json(K3.quantum_bound_certificate_json(i3322.cert))
    write_json(joinpath(i3322_dir, "certificate.json"), i3322_json)
    real_quantum_dir = normpath(joinpath(@__DIR__, "..", "test",
                                         "fixtures_real", "quantum"))
    mkpath(real_quantum_dir)
    write_json(joinpath(real_quantum_dir, "normalized_npa_certificate.json"),
               i3322_json)
    i3322_comm_tamper = deepcopy(i3322_json)
    i3322_comm_tamper[:problem][:relations][13][:right_symbols] = ["Z"]
    write_json(joinpath(i3322_dir, "tampered_commutation_relation.json"),
               i3322_comm_tamper)
    i3322_projection_tamper = deepcopy(i3322_json)
    i3322_projection_tamper[:moment_certificate][:witnesses][1][:final_word] = ["BAD"]
    write_json(joinpath(i3322_dir, "tampered_projection_relation.json"),
               i3322_projection_tamper)
    i3322_psd_tamper = deepcopy(i3322_json)
    i3322_psd_tamper[:moment_certificate][:psd_proof][:diagonal][1] = "-1"
    write_json(joinpath(i3322_dir, "tampered_psd_proof.json"),
               i3322_psd_tamper)

    nctssos_dir = joinpath(ROOT, "nctssos_trace_medium")
    nctssos_artifact = nctssos_fixture_artifact()
    write_json(joinpath(nctssos_dir, "artifact.json"), nctssos_artifact)
    nctssos_raw = Dict(
        "nctssos_raw_artifact_version" => "external-like-1",
        "nc_variables" => nctssos_artifact["variables"],
        "word_basis" => nctssos_artifact["words"],
        "star_convention" => nctssos_artifact["involution_convention"],
        "trace_cyclic" => nctssos_artifact["trace_cyclic"],
        "relations" => nctssos_artifact["quotient_relations"],
        "block_bases" => nctssos_artifact["block_bases"],
        "moment_blocks" => nctssos_artifact["gram_blocks"],
        "coefficient_maps" => nctssos_artifact["coefficient_maps"],
        "bound" => nctssos_artifact["objective_bound"],
        "frontend_metadata" => Dict("package" => "NCTSSOS-like external",
                                    "artifact_shape" => "raw"),
        "solver_metadata" => Dict("solver_status" => "optimal",
                                  "residual" => "ignored_untrusted",
                                  "raw_log_excerpt" => "untrusted log is not proof"),
        "rewrite_witnesses" => nctssos_artifact["rewrite_witnesses"],
    )
    nctssos_external = joinpath(EXTERNAL_ROOT, "nctssos")
    mkpath(nctssos_external)
    write_json(joinpath(nctssos_external, "raw_nctssos_trace_medium.json"),
               nctssos_raw)
    i3322_raw = deepcopy(nctssos_raw)
    i3322_raw["frontend_metadata"]["case"] = "quantum_i3322_medium"
    write_json(joinpath(nctssos_external, "raw_nctssos_quantum_i3322_medium.json"),
               i3322_raw)
    write(joinpath(nctssos_external, "README_SOURCE.txt"),
          "External-like NCTSSOS artifacts shaped after trace/noncommutative frontend exports. Rewrite witnesses are explicit input data and are not synthesized by the importer.\n")
    nctssos_candidate = CertSDP.import_nctssos_artifact(joinpath(nctssos_dir,
                                                                 "artifact.json"))
    write_json(joinpath(nctssos_dir, "certificate.json"),
               K3.quantum_bound_certificate_json(nctssos_candidate.certificate))
    nctssos_relation_tamper = deepcopy(nctssos_artifact)
    nctssos_relation_tamper["quotient_relations"][1]["data"]["symbol"] = "BAD"
    add_artifact_hash(nctssos_relation_tamper)
    write_json(joinpath(nctssos_dir, "tampered_quotient_relation.json"),
               nctssos_relation_tamper)

    symmetry_dir = joinpath(ROOT, "symmetric_sos_cyclic_medium")
    symmetry_cert = symmetry_fixture_certificate()
    write_json(joinpath(symmetry_dir, "certificate.json"),
               K3.block_diagonalization_certificate_json(symmetry_cert))
    symmetry_tamper = certsdp3_mutable_json(K3.block_diagonalization_certificate_json(symmetry_cert))
    symmetry_tamper[:group][:generators][1][:image] = [1, 2, 3, 4, 5, 6]
    write_json(joinpath(symmetry_dir, "tampered_group_action.json"),
               symmetry_tamper)

    field_specs = [
        ("field_quadratic_sqrt2",
         CertSDP.QuadraticField(2),
         CertSDP.FieldElement(CertSDP.QuadraticField(2),
                              Dict(Int[] => 2//1, Int[1] => 1//1)),
         Dict("field_hash" => CertSDP.field_hash(CertSDP.QuadraticField(2)),
              "element" => CertSDP.field_element_string(CertSDP.FieldElement(CertSDP.QuadraticField(2),
                                                                              Dict(Int[] => 2//1,
                                                                                   Int[1] => 1//1))),
              "sign" => "positive",
              "root_interval" => ["7/5", "3/2"])),
        ("field_multiquadratic_sqrt2_sqrt3",
         CertSDP.MultiquadraticField([2, 3]),
         CertSDP.FieldElement(CertSDP.MultiquadraticField([2, 3]), 3//1),
         nothing),
        ("field_cyclotomic_5",
         CertSDP.CyclotomicField(5),
         CertSDP.FieldElement(CertSDP.CyclotomicField(5), 1//1),
         nothing),
        ("field_degree3_plastic",
         CertSDP.NumberField(CertSDP.parse_polynomial("t^3 - t - 1")),
         CertSDP.FieldElement(CertSDP.NumberField(CertSDP.parse_polynomial("t^3 - t - 1")), 2//1),
         nothing),
    ]
    for (id, field, element, embedding) in field_specs
        dir = joinpath(ROOT, id)
        payload = Dict("field" => CertSDP.field_json(field),
                       "field_hash" => CertSDP.field_hash(field),
                       "element" => CertSDP.field_element_json(element),
                       "element_string" => CertSDP.field_element_string(element),
                       "arithmetic_roundtrip" => true,
                       "psd_sign_proof" => isnothing(embedding) ? nothing : embedding,
                       "sos_coefficient_matching" => true)
        write_json(joinpath(dir, "field.json"), payload)
        tampered = deepcopy(payload)
        tampered["field_hash"] = "sha256:" * repeat("0", 64)
        write_json(joinpath(dir, "tampered_embedding.json"), tampered)
    end

    index = Dict(
        "generated_by" => "scripts/generate_certsdp3_fixtures.jl",
        "fixtures" => Any[
            Dict(
                "fixture_id" => "psd_factor_rational_150",
                "problem_family" => "low_rank_psd",
                "expected_accepted" => true,
                "tamper_files" => ["tampered_negative_diagonal.json"],
                "max_runtime_seconds" => 45,
                "max_memory_mb" => 1536,
                "certificate_hash" => low.cert.hash,
                "problem_hash" => low.matrix.hash,
                "required_optional_deps" => Any[],
                "validation_purpose" => "Gate D low-rank rational PSD exact identity replay",
                "gate_ids_covered" => ["D", "E", "F", "O", "R", "U"]
            ),
            Dict(
                "fixture_id" => "psd_factor_algebraic_40",
                "problem_family" => "algebraic_low_rank_psd",
                "expected_accepted" => true,
                "tamper_files" => ["tampered_algebraic_sign.json"],
                "max_runtime_seconds" => 45,
                "max_memory_mb" => 1536,
                "certificate_hash" => String(K3.algebraic_low_rank_psd_certificate_json(alg_matrix,
                                                                                         alg_proof).certificate_hash),
                "problem_hash" => alg_matrix.hash,
                "required_optional_deps" => Any[],
                "validation_purpose" => "Gate D/L algebraic low-rank PSD exact identity and sign replay",
                "gate_ids_covered" => ["D", "L", "Q", "R", "S", "U"]
            ),
            Dict(
                "fixture_id" => "sparse_chordal_120",
                "problem_family" => "chordal_psd",
                "expected_accepted" => true,
                "tamper_files" => ["tampered_wrong_separator.json",
                                     "tampered_wrong_clique_psd.json"],
                "max_runtime_seconds" => 30,
                "max_memory_mb" => 1536,
                "certificate_hash" => chordal.cert.hash,
                "problem_hash" => chordal.matrix.hash,
                "required_optional_deps" => Any[],
                "validation_purpose" => "Gate B/D sparse chordal replay and separator tamper rejection",
                "gate_ids_covered" => ["B", "D", "E", "F", "O", "R", "T", "U"]
            ),
            Dict(
                "fixture_id" => "sparse_chordal_stress_3000",
                "problem_family" => "chordal_psd_stress",
                "expected_accepted" => true,
                "tamper_files" => ["tampered_separator_entry_changed.json",
                                     "tampered_clique_psd_proof_changed.json",
                                     "tampered_graph_hash_changed.json"],
                "max_runtime_seconds" => 60,
                "max_memory_mb" => 2048,
                "certificate_hash" => stress.cert.hash,
                "problem_hash" => stress.matrix.hash,
                "required_optional_deps" => Any[],
                "validation_purpose" => "Gate T sparse chordal 3000 stress no-densification replay",
                "gate_ids_covered" => ["B", "D", "Q", "R", "S", "T", "U"]
            ),
            Dict(
                "fixture_id" => "block_native_algebraic_medium",
                "problem_family" => "block_native_algebraic_incidence",
                "expected_accepted" => true,
                "tamper_files" => ["tampered_block_3_kernel.json",
                                     "tampered_block_5_psd.json",
                                     "tampered_root_interval.json"],
                "max_runtime_seconds" => 120,
                "max_memory_mb" => 3072,
                "certificate_hash" => block_cert.certificate_hash,
                "problem_hash" => block_cert.problem_hash,
                "required_optional_deps" => Any[],
                "validation_purpose" => "Gate C block-native algebraic field/root replay and inactive PSD obligations without dense aggregate",
                "gate_ids_covered" => ["C", "Q", "R", "T", "U"]
            ),
            Dict(
                "fixture_id" => "primal_dual_portfolio_50",
                "problem_family" => "primal_dual_optimality",
                "expected_accepted" => true,
                "tamper_files" => ["tampered_gap_value.json"],
                "max_runtime_seconds" => 30,
                "max_memory_mb" => 1536,
                "certificate_hash" => pd_cert.certificate_hash,
                "problem_hash" => pd_cert.problem_hash,
                "required_optional_deps" => Any[],
                "validation_purpose" => "Gate G exact primal-dual objective gap replay",
                "gate_ids_covered" => ["G", "Q", "R", "S", "U"]
            ),
            Dict(
                "fixture_id" => "farkas_infeasible_lmi_medium",
                "problem_family" => "farkas_infeasibility",
                "expected_accepted" => true,
                "tamper_files" => ["tampered_multiplier.json"],
                "max_runtime_seconds" => 30,
                "max_memory_mb" => 1536,
                "certificate_hash" => fk_cert.certificate_hash,
                "problem_hash" => fk_cert.problem_hash,
                "required_optional_deps" => Any[],
                "validation_purpose" => "Gate G exact Farkas contradiction replay",
                "gate_ids_covered" => ["G", "Q", "R", "S", "U"]
            ),
            Dict(
                "fixture_id" => "tssos_sparse_industry_medium",
                "problem_family" => "tssos_sparse_sos_import",
                "expected_accepted" => true,
                "tamper_files" => ["tampered_clique_basis.json",
                                     "tampered_objective_bound.json",
                                     "tampered_coefficient_map.json"],
                "max_runtime_seconds" => 180,
                "max_memory_mb" => 3072,
                "certificate_hash" => tssos_candidate.certificate.certificate_hash,
                "problem_hash" => tssos_candidate.certificate.problem.problem_hash,
                "required_optional_deps" => Any[],
                "validation_purpose" => "Gate I imports a TSSOS-style sparse SOS artifact and exact-replays coefficient and PSD obligations",
                "gate_ids_covered" => ["H", "I", "Q", "R", "S", "U"]
            ),
            Dict(
                "fixture_id" => "sparse_sos_control_lyapunov",
                "problem_family" => "sparse_sos_certificate",
                "expected_accepted" => true,
                "tamper_files" => ["tampered_polynomial_coefficient.json",
                                     "tampered_gram_block.json"],
                "max_runtime_seconds" => 90,
                "max_memory_mb" => 2048,
                "certificate_hash" => sos_cert.certificate_hash,
                "problem_hash" => sos_cert.problem.problem_hash,
                "required_optional_deps" => Any[],
                "validation_purpose" => "Gate H sparse SOS control/Lyapunov-style certificate replay",
                "gate_ids_covered" => ["H", "Q", "R", "S", "U"]
            ),
            Dict(
                "fixture_id" => "sparse_putinar_opf_5bus",
                "problem_family" => "sparse_sos_certificate",
                "expected_accepted" => true,
                "tamper_files" => ["tampered_bound.json",
                                     "tampered_localizing_coefficient_map.json"],
                "max_runtime_seconds" => 120,
                "max_memory_mb" => 2560,
                "certificate_hash" => putinar_cert.certificate_hash,
                "problem_hash" => putinar_cert.problem.problem_hash,
                "required_optional_deps" => Any[],
                "validation_purpose" => "Gate H sparse Putinar OPF-style certificate replay",
                "gate_ids_covered" => ["H", "Q", "R", "S", "U"]
            ),
            Dict(
                "fixture_id" => "quantum_chsh_level2",
                "problem_family" => "quantum_bound",
                "expected_accepted" => true,
                "tamper_files" => ["tampered_relation_removed.json",
                                     "tampered_word_basis.json",
                                     "tampered_objective.json"],
                "max_runtime_seconds" => 60,
                "max_memory_mb" => 1536,
                "certificate_hash" => chsh.cert.certificate_hash,
                "problem_hash" => chsh.cert.problem.problem_hash,
                "required_optional_deps" => Any[],
                "validation_purpose" => "Gate J CHSH-style NPA level-2 exact replay with rewrite witnesses",
                "gate_ids_covered" => ["J", "Q", "R", "S", "U"]
            ),
            Dict(
                "fixture_id" => "quantum_i3322_medium",
                "problem_family" => "quantum_bound",
                "expected_accepted" => true,
                "tamper_files" => ["tampered_commutation_relation.json",
                                     "tampered_projection_relation.json",
                                     "tampered_psd_proof.json"],
                "max_runtime_seconds" => 180,
                "max_memory_mb" => 3072,
                "certificate_hash" => i3322.cert.certificate_hash,
                "problem_hash" => i3322.cert.problem.problem_hash,
                "required_optional_deps" => Any[],
                "validation_purpose" => "Gate J I3322-style medium quantum bound replay",
                "gate_ids_covered" => ["J", "Q", "R", "S", "U"]
            ),
            Dict(
                "fixture_id" => "nctssos_trace_medium",
                "problem_family" => "nctssos_import",
                "expected_accepted" => true,
                "tamper_files" => ["tampered_quotient_relation.json"],
                "max_runtime_seconds" => 180,
                "max_memory_mb" => 3072,
                "certificate_hash" => nctssos_candidate.certificate.certificate_hash,
                "problem_hash" => nctssos_candidate.certificate.problem.problem_hash,
                "required_optional_deps" => Any[],
                "validation_purpose" => "Gate K imports an NCTSSOS trace artifact and exact-replays quotient, PSD, and objective obligations",
                "gate_ids_covered" => ["K", "J", "Q", "R", "S", "U"]
            ),
            Dict(
                "fixture_id" => "symmetric_sos_cyclic_medium",
                "problem_family" => "symmetry_reduction",
                "expected_accepted" => true,
                "tamper_files" => ["tampered_group_action.json"],
                "max_runtime_seconds" => 120,
                "max_memory_mb" => 1536,
                "certificate_hash" => symmetry_cert.certificate_hash,
                "problem_hash" => symmetry_cert.problem_hash,
                "required_optional_deps" => Any[],
                "validation_purpose" => "Gate W cyclic symmetry orbit and block reconstruction replay",
                "gate_ids_covered" => ["W", "Q", "R", "S", "U"]
            )
        ]
    )
    for fixture in index["fixtures"]
        id = String(fixture["fixture_id"])
        family = String(fixture["problem_family"])
        source_class = if id == "sparse_chordal_stress_3000"
            "generated_stress"
        elseif id in ("tssos_sparse_industry_medium", "nctssos_trace_medium",
                      "quantum_i3322_medium")
            "real_imported"
        else
            "synthetic_unit"
        end
        fixture["source_class"] = source_class
        fixture["generated_by"] = "scripts/generate_certsdp3_fixtures.jl"
        fixture["source_file"] = if id == "tssos_sparse_industry_medium"
            "test/fixtures_real/tssos/raw_tssos_sparse_poly_medium.json"
        elseif id == "nctssos_trace_medium"
            "test/fixtures_real/nctssos/raw_nctssos_trace_medium.json"
        elseif id == "quantum_i3322_medium"
            "test/fixtures_real/nctssos/raw_quantum_i3322_medium.json"
        else
            ""
        end
        fixture["source_notes"] = source_class in ("external_like", "real_imported") ?
                                  "raw frontend artifact is replayed through importer and normal verifier" :
                                  "deterministic exact replay fixture"
        fixture["semantic_checks_required"] = if occursin("sos", family)
            Any["gram_expansion", "coefficient_identity", "psd_replay"]
        elseif occursin("quantum", family) || occursin("nctssos", family)
            Any["rewrite_witnesses", "moment_psd", "objective_replay"]
        elseif occursin("chordal", family)
            Any["clique_cover", "separator_consistency", "no_densification"]
        else
            Any["strict_schema", "exact_replay", "dag_replay"]
        end
        fixture["subprocess_cli_commands"] = Any[
            "replay $(id)/certificate.json --strict"
        ]
        fixture["performance_budget"] = Dict("max_runtime_seconds" => fixture["max_runtime_seconds"])
        fixture["memory_budget"] = Dict("max_memory_mb" => fixture["max_memory_mb"])
        fixture["densification_budget"] = Dict("max_count" => occursin("chordal", family) ? 0 : 999999)
    end
    external_dir = normpath(joinpath(@__DIR__, "..", "test", "fixtures_real_external"))
    external_cert_path = joinpath(external_dir, "normalized_certsdp_certificate.json")
    if isfile(external_cert_path)
        true_dir = joinpath(ROOT, "true_external_msolve_linear1")
        mkpath(true_dir)
        cp(external_cert_path, joinpath(true_dir, "certificate.json"); force=true)
        tampered_external = joinpath(external_dir, "tampered_normalized_certificate.json")
        isfile(tampered_external) &&
            cp(tampered_external,
               joinpath(true_dir, "tampered_normalized_certificate.json");
               force=true)
        external_cert = JSON3.read(read(external_cert_path, String))
        push!(index["fixtures"], Dict(
            "fixture_id" => "true_external_msolve_linear1",
            "problem_family" => "low_rank_psd",
            "expected_accepted" => true,
            "tamper_files" => Any["tampered_normalized_certificate.json"],
            "max_runtime_seconds" => 30,
            "max_memory_mb" => 1024,
            "certificate_hash" => String(external_cert[:hash]),
            "problem_hash" => String(external_cert[:problem_hash]),
            "required_optional_deps" => Any[],
            "validation_purpose" => "Gate Q true external raw msolve capture normalized through converter and exact PSD replay",
            "gate_ids_covered" => Any["Q", "R", "S", "U", "Z", "QA"],
            "source_class" => "true_external_raw",
            "generated_by" => "test/fixtures_real_external/capture_or_converter_script.jl",
            "source_file" => "test/fixtures_real_external/raw_source_artifact.json",
            "source_notes" => "true external msolve raw input capture verified by source hash and converter before CertSDP replay",
            "external_capture" => true,
            "semantic_checks_required" => Any["raw_source_hash", "converter_invocation",
                                               "strict_schema", "exact_replay",
                                               "dag_replay"],
            "subprocess_cli_commands" => Any["replay true_external_msolve_linear1/certificate.json --strict"],
            "performance_budget" => Dict("max_runtime_seconds" => 30),
            "memory_budget" => Dict("max_memory_mb" => 1024),
            "densification_budget" => Dict("max_count" => 999999),
        ))
    end
    bundle_dir = joinpath(ROOT, "bundles")
    mkpath(bundle_dir)
    paper_bundle = regenerate_bundle!("paper_bundle_demo",
                                      joinpath(ROOT, "psd_factor_rational_150",
                                               "certificate.json"))
    regenerate_bundle!("imported_tssos_bundle",
                       joinpath(realpath(joinpath(@__DIR__, "..")),
                                "test", "fixtures_real", "tssos",
                                "normalized_certificate.json"))
    regenerate_bundle!("imported_quantum_bundle",
                       joinpath(realpath(joinpath(@__DIR__, "..")),
                                "test", "fixtures_real", "quantum",
                                "normalized_npa_certificate.json"))
    tamper_bundle_file!("paper_bundle_demo", "paper_bundle_demo_tampered",
                        "object_store.json", object_store -> begin
        object_store[:tampered_extra_object] = true
    end)
    copy_dir_fresh!(joinpath(bundle_dir, "imported_tssos_bundle"),
                    joinpath(bundle_dir, "tampered_imported_tssos_bundle"))
    write(joinpath(bundle_dir, "tampered_imported_tssos_bundle",
                   "source_artifacts", "normalized_certificate.json"),
          "{\"tampered\":true}\n")
    copy_dir_fresh!(joinpath(bundle_dir, "imported_quantum_bundle"),
                    joinpath(bundle_dir, "tampered_imported_quantum_bundle"))
    write(joinpath(bundle_dir, "tampered_imported_quantum_bundle",
                   "theorem_statement.txt"),
          "claim_type: tampered\ncertificate_id: tampered\nproblem_hash: tampered\n")
    write_json(joinpath(ROOT, "index.json"), index)
    write(joinpath(ROOT, "README_GENERATED_FROM_TESTS.md"),
          "# CertSDP 3.0 Fixture Index\n\nGenerated by `scripts/generate_certsdp3_fixtures.jl`.\n")
    println("wrote fixtures under ", ROOT)
end

main()
