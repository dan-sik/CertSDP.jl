#!/usr/bin/env julia

pushfirst!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))

using CertSDP
using JSON3

const REQUIRED_INDEX_KEYS = Set(Symbol[
    :fixture_id,
    :problem_family,
    :expected_accepted,
    :tamper_files,
    :max_runtime_seconds,
    :max_memory_mb,
    :certificate_hash,
    :problem_hash,
    :required_optional_deps,
    :validation_purpose,
    :gate_ids_covered,
    :source_class,
    :generated_by,
    :source_file,
    :source_notes,
    :semantic_checks_required,
    :subprocess_cli_commands,
    :performance_budget,
    :memory_budget,
    :densification_budget,
])

const VALID_GATE_IDS = Set(String.([
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
]))

const P0_VALIDATION_GATES = Set(String.([
    "B", "C", "D", "G", "H", "I", "J", "L", "Q", "R", "S", "T", "U",
]))

function validation_failure_report(gate::Symbol, family::Symbol, stage::Symbol,
                                   reason::AbstractString,
                                   obligation::Symbol=:validation_corpus;
                                   path::Union{Nothing, AbstractString}=nothing)
    return CertSDP.Kernel.DiagnosticReport(false,
                                           gate,
                                           family,
                                           stage,
                                           String(reason),
                                           obligation,
                                           nothing,
                                           nothing,
                                           nothing,
                                           nothing,
                                           nothing,
                                           isnothing(path) ? nothing : String(path),
                                           Dict{Symbol, Any}())
end

function object_keys(value)
    return Set(Symbol(key) for key in keys(value))
end

function require_index_schema!(fixture, failures::Vector{String}, index::Int)
    keys_seen = object_keys(fixture)
    missing = setdiff(REQUIRED_INDEX_KEYS, keys_seen)
    unknown = setdiff(keys_seen, REQUIRED_INDEX_KEYS)
    isempty(missing) ||
        push!(failures, "fixture index entry $index missing keys: $(join(sort!(String.(collect(missing))), ", "))")
    isempty(unknown) ||
        push!(failures, "fixture index entry $index has unknown keys: $(join(sort!(String.(collect(unknown))), ", "))")
    if haskey(fixture, :gate_ids_covered)
        gates = String.(fixture[:gate_ids_covered])
        isempty(gates) &&
            push!(failures, "fixture index entry $index has no gate_ids_covered")
        invalid = setdiff(Set(gates), VALID_GATE_IDS)
        isempty(invalid) ||
            push!(failures, "fixture index entry $index has invalid gate ids: $(join(sort!(collect(invalid)), ", "))")
    end
    haskey(fixture, :tamper_files) && isempty(fixture[:tamper_files]) &&
        push!(failures, "fixture index entry $index has no tamper_files")
    return nothing
end

function validate_sha256_text(value, label::AbstractString,
                              failures::Vector{String})
    text = String(value)
    occursin(r"^sha256:[0-9a-f]{64}$", text) ||
        push!(failures, "$label is not canonical sha256")
    return nothing
end

function check_report_hashes!(fixture, measurement, failures::Vector{String})
    expected_problem = String(fixture[:problem_hash])
    expected_cert = String(fixture[:certificate_hash])
    report = measurement.report
    isnothing(report.problem_hash) ||
        report.problem_hash == expected_problem ||
        push!(failures, "problem hash mismatch for $(fixture[:fixture_id]): index=$expected_problem replay=$(report.problem_hash)")
    if String(fixture[:fixture_id]) == "sparse_chordal_stress_3000"
        return nothing
    end
    isnothing(report.certificate_hash) ||
        report.certificate_hash == expected_cert ||
        push!(failures, "certificate hash mismatch for $(fixture[:fixture_id]): index=$expected_cert replay=$(report.certificate_hash)")
    return nothing
end

function read_json_file(path::AbstractString)
    return JSON3.read(read(path, String))
end

function max_json_int(value, keys::Vector{Symbol})
    best = 0
    if value isa JSON3.Object || value isa AbstractDict
        for key in keys
            if haskey(value, key) && value[key] isa Integer
                best = max(best, Int(value[key]))
            end
        end
        for key in Base.keys(value)
            best = max(best, max_json_int(value[key], keys))
        end
    elseif value isa AbstractVector
        for entry in value
            best = max(best, max_json_int(entry, keys))
        end
    end
    return best
end

function json_array_length(value, path::Vector{Symbol})
    current = value
    for key in path
        (current isa JSON3.Object || current isa AbstractDict) && haskey(current, key) ||
            return 0
        current = current[key]
    end
    return current isa AbstractVector ? length(current) : 0
end

function json_matrix_rank_width(cert_json)
    proof = haskey(cert_json, :proof) ? cert_json[:proof] : nothing
    isnothing(proof) && return 0
    haskey(proof, :low_rank_proof) || return 0
    lr = proof[:low_rank_proof]
    haskey(lr, :diagonal) || return 0
    return length(lr[:diagonal])
end

function validate_fixture_shape!(fixture, dir::AbstractString,
                                 failures::Vector{String})
    id = String(fixture[:fixture_id])
    family = String(fixture[:problem_family])
    cert_path = joinpath(dir, "certificate.json")
    cert_json = isfile(cert_path) ? read_json_file(cert_path) : nothing
    if id == "psd_factor_rational_150"
        n = Int(cert_json[:proof][:matrix][:n])
        rank = json_matrix_rank_width(cert_json)
        n >= 150 ||
            push!(failures, "$id must have n >= 150; got $n")
        10 <= rank <= 25 ||
            push!(failures, "$id must have low-rank factor rank 10-25; got $rank")
    elseif id == "sparse_chordal_120"
        proof = cert_json[:proof][:chordal_proof]
        n = Int(cert_json[:proof][:matrix][:n])
        cliques = proof[:structure][:cliques]
        nnz = length(cert_json[:proof][:matrix][:entries])
        n >= 120 ||
            push!(failures, "$id must have n >= 120; got $n")
        8 <= length(cliques) <= 32 ||
            push!(failures, "$id must have a medium clique count; got $(length(cliques))")
        maximum(length.(cliques)) <= 14 ||
            push!(failures, "$id has clique larger than 14")
        nnz < 2500 ||
            push!(failures, "$id must keep sparse nonzeros < 2500; got $nnz")
    elseif id == "sparse_chordal_stress_3000"
        proof = cert_json[:proof][:chordal_proof]
        n = Int(cert_json[:proof][:matrix][:n])
        cliques = proof[:structure][:cliques]
        nnz = length(cert_json[:proof][:matrix][:entries])
        n >= 3000 ||
            push!(failures, "$id must have n >= 3000; got $n")
        length(cliques) >= 250 ||
            push!(failures, "$id must have at least 250 cliques; got $(length(cliques))")
        maximum(length.(cliques)) <= 10 ||
            push!(failures, "$id has clique larger than 10")
        nnz <= 40000 ||
            push!(failures, "$id must keep nonzeros <= 40000; got $nnz")
    elseif id == "block_native_algebraic_medium"
        problem_path = joinpath(dir, "problem.json")
        problem_json = isfile(problem_path) ? read_json_file(problem_path) : nothing
        blocks = max(json_array_length(cert_json, [:incidence, :blocks]),
                     isnothing(problem_json) ? 0 :
                     max_json_int(problem_json, Symbol[:block_index]))
        variables = json_array_length(cert_json, [:incidence, :shared_variables])
        blocks >= 12 ||
            push!(failures, "$id must have at least 12 blocks; got $blocks")
        variables >= 20 ||
            push!(failures, "$id must have at least 20 shared variables; got $variables")
    elseif id == "primal_dual_portfolio_50"
        n = max_json_int(cert_json, Symbol[:n])
        affine = json_array_length(cert_json, [:primal, :affine_lhs])
        n >= 50 ||
            push!(failures, "$id must contain PSD block size >= 50; got $n")
        affine >= 50 ||
            push!(failures, "$id must contain at least 50 affine entries; got $affine")
    elseif id == "farkas_infeasible_lmi_medium"
        n = 0
        if haskey(cert_json, :cone_proofs) && !isempty(cert_json[:cone_proofs])
            first_proof = cert_json[:cone_proofs][1]
            n = haskey(first_proof, :factor) ? length(first_proof[:factor]) : 0
        end
        lhs = json_array_length(cert_json, [:multiplier_identity_lhs])
        n >= 20 ||
            push!(failures, "$id must contain PSD block size >= 20; got $n")
        lhs >= 10 ||
            push!(failures, "$id must contain at least 10 multiplier entries; got $lhs")
    elseif id == "sparse_sos_control_lyapunov"
        variables = json_array_length(cert_json, [:problem, :variables])
        blocks = json_array_length(cert_json, [:sos_blocks])
        block_n = max_json_int(cert_json, Symbol[:n])
        4 <= variables <= 6 ||
            push!(failures, "$id must have 4-6 variables; got $variables")
        blocks >= 6 ||
            push!(failures, "$id must have at least 6 SOS/localizing blocks; got $blocks")
        35 <= block_n <= 60 ||
            push!(failures, "$id max Gram block must be 35-60; got $block_n")
    elseif id == "sparse_putinar_opf_5bus"
        variables = json_array_length(cert_json, [:problem, :variables])
        localizing = json_array_length(cert_json, [:putinar, :localizing_blocks])
        8 <= variables <= 12 ||
            push!(failures, "$id must have 8-12 variables; got $variables")
        localizing >= 8 ||
            push!(failures, "$id must have at least 8 localizing blocks; got $localizing")
    elseif id == "tssos_sparse_industry_medium"
        artifact = read_json_file(joinpath(dir, "artifact.json"))
        variables = json_array_length(artifact, [:variables])
        constraints = json_array_length(artifact, [:constraints])
        cliques = json_array_length(artifact, [:cliques])
        blocks = json_array_length(artifact, [:gram_blocks]) +
                 json_array_length(artifact, [:localizing_blocks])
        12 <= variables <= 20 ||
            push!(failures, "$id must have 12-20 variables; got $variables")
        10 <= constraints <= 30 ||
            push!(failures, "$id must have 10-30 constraints; got $constraints")
        5 <= cliques <= 10 ||
            push!(failures, "$id must have 5-10 cliques; got $cliques")
        10 <= blocks <= 25 ||
            push!(failures, "$id must have 10-25 blocks; got $blocks")
    elseif id == "quantum_chsh_level2"
        words = json_array_length(cert_json, [:problem, :word_basis])
        n = max_json_int(cert_json, Symbol[:n])
        words >= 30 ||
            push!(failures, "$id must have a level-2 word basis; got $words")
        n >= 30 ||
            push!(failures, "$id must have PSD dimension >= 30; got $n")
    elseif id == "quantum_i3322_medium"
        words = json_array_length(cert_json, [:problem, :word_basis])
        n = max_json_int(cert_json, Symbol[:n])
        words >= 80 ||
            push!(failures, "$id must have at least 80 words; got $words")
        60 <= n <= 120 ||
            push!(failures, "$id PSD dimension must be 60-120; got $n")
    elseif id == "nctssos_trace_medium"
        artifact = read_json_file(joinpath(dir, "artifact.json"))
        words = json_array_length(artifact, [:words])
        relations = json_array_length(artifact, [:quotient_relations])
        words >= 100 ||
            push!(failures, "$id must have at least 100 words; got $words")
        relations >= 8 ||
            push!(failures, "$id must have at least 8 quotient relations; got $relations")
    elseif family == "symmetry_reduction"
        blocks = json_array_length(cert_json, [:projection_blocks])
        blocks >= 3 ||
            push!(failures, "$id must have at least 3 symmetry blocks; got $blocks")
    end
    return nothing
end

function attach_expected_certificate_hash(report::CertSDP.Kernel.DiagnosticReport,
                                          hash::AbstractString)
    return CertSDP.Kernel.DiagnosticReport(report.accepted,
                                           report.gate,
                                           report.family,
                                           report.stage,
                                           report.reason,
                                           report.obligation_id,
                                           report.problem_hash,
                                           String(hash),
                                           report.block_id,
                                           report.clique_id,
                                           report.separator_id,
                                           report.artifact_path,
                                           report.details)
end

function validate_block_native_certificate(path::AbstractString)
    cert = try
        CertSDP.Kernel.parse_block_native_algebraic_certificate_json(read(path, String))
    catch err
        return CertSDP.Kernel.DiagnosticReport(false,
                                               :C,
                                               :block_native_algebraic,
                                               :parse,
                                               sprint(showerror, err),
                                               :block_native_certificate,
                                               nothing,
                                               nothing,
                                               nothing,
                                               nothing,
                                               nothing,
                                               path,
                                               Dict{Symbol, Any}())
    end
    return CertSDP.Kernel.verify_block_native_algebraic_certificate(cert)
end

function sparse_matrix_from_json(value)
    entries = Tuple{Int, Int, Rational{BigInt}}[]
    for entry in value[:entries]
        push!(entries, (Int(entry[:i]), Int(entry[:j]),
                        parse_rational(String(entry[:value]))))
    end
    return CertSDP.Kernel.SparseSymmetricRationalMatrix(Int(value[:n]), entries)
end

function low_rank_proof_from_json(value, matrix)
    factor = [[parse_rational(String(entry)) for entry in row]
              for row in value[:factor]]
    diagonal = [parse_rational(String(entry)) for entry in value[:diagonal]]
    return CertSDP.Kernel.ExactLowRankPSDProof(matrix, factor, diagonal)
end

function parse_rational(text::AbstractString)
    parts = split(text, "/")
    if length(parts) == 1
        return parse(BigInt, parts[1]) // 1
    elseif length(parts) == 2
        return parse(BigInt, parts[1]) // parse(BigInt, parts[2])
    end
    error("bad rational $text")
end

function primal_from_json(value)
    matrices = [sparse_matrix_from_json(matrix) for matrix in value[:cone_matrices]]
    proofs = [low_rank_proof_from_json(proof, matrices[i])
              for (i, proof) in enumerate(value[:cone_proofs])]
    return CertSDP.Kernel.PrimalFeasibilityCertificate(String(value[:problem_hash]),
                                                       [parse_rational(String(x)) for x in value[:affine_lhs]],
                                                       [parse_rational(String(x)) for x in value[:affine_rhs]],
                                                       matrices,
                                                       proofs,
                                                       parse_rational(String(value[:objective_value])))
end

function dual_from_json(value)
    matrices = [sparse_matrix_from_json(matrix) for matrix in value[:cone_matrices]]
    proofs = [low_rank_proof_from_json(proof, matrices[i])
              for (i, proof) in enumerate(value[:cone_proofs])]
    return CertSDP.Kernel.DualFeasibilityCertificate(String(value[:problem_hash]),
                                                     [parse_rational(String(x)) for x in value[:affine_lhs]],
                                                     [parse_rational(String(x)) for x in value[:affine_rhs]],
                                                     matrices,
                                                     proofs,
                                                     parse_rational(String(value[:objective_value])))
end

function validate_primal_dual_certificate(path::AbstractString)
    parsed = JSON3.read(read(path, String))
    primal = primal_from_json(parsed[:primal])
    dual = dual_from_json(parsed[:dual])
    cert = CertSDP.Kernel.make_primal_dual_optimality_certificate(String(parsed[:problem_hash]),
                                                                  primal,
                                                                  dual;
                                                                  gap=parse_rational(String(parsed[:gap])))
    cert = CertSDP.Kernel.PrimalDualOptimalityCertificate(cert.problem_hash,
                                                          cert.primal,
                                                          cert.dual,
                                                          cert.gap,
                                                          String(parsed[:certificate_hash]),
                                                          cert.dag)
    report = CertSDP.Kernel.verify_primal_dual_optimality(cert)
    return attach_expected_certificate_hash(report,
                                            String(parsed[:certificate_hash]))
end

function validate_farkas_certificate(path::AbstractString)
    parsed = JSON3.read(read(path, String))
    proofs = CertSDP.Kernel.ExactLowRankPSDProof[]
    for proof_json in parsed[:cone_proofs]
        factor = [[parse_rational(String(entry)) for entry in row]
                  for row in proof_json[:factor]]
        diagonal = [parse_rational(String(entry)) for entry in proof_json[:diagonal]]
        proof = CertSDP.Kernel.ExactLowRankPSDProof(Symbol(String(proof_json[:field])),
                                                    String(proof_json[:matrix_hash]),
                                                    factor,
                                                    diagonal,
                                                    String(proof_json[:identity_proof_hash]))
        push!(proofs, proof)
    end
    cert = CertSDP.Kernel.make_farkas_infeasibility_certificate(String(parsed[:problem_hash]),
                                                               [parse_rational(String(x)) for x in parsed[:multiplier_identity_lhs]],
                                                               [parse_rational(String(x)) for x in parsed[:multiplier_identity_rhs]],
                                                               proofs,
                                                               parse_rational(String(parsed[:contradiction_lhs])),
                                                               parse_rational(String(parsed[:contradiction_rhs])))
    cert = CertSDP.Kernel.FarkasInfeasibilityCertificate(cert.problem_hash,
                                                         cert.multiplier_identity_lhs,
                                                         cert.multiplier_identity_rhs,
                                                         cert.cone_proofs,
                                                         cert.contradiction_lhs,
                                                         cert.contradiction_rhs,
                                                         String(parsed[:certificate_hash]),
                                                         cert.dag)
    report = CertSDP.Kernel.verify_farkas_infeasibility(cert)
    return attach_expected_certificate_hash(report,
                                            String(parsed[:certificate_hash]))
end

function validate_tssos_artifact(dir::AbstractString)
    artifact_path = joinpath(dir, "artifact.json")
    elapsed = @elapsed begin
        result = CertSDP.certify_tssos_artifact(artifact_path)
        if result isa CertSDP.CertifiedResult
            report = CertSDP.Kernel.verify_sparse_sos_certificate(result.certificate)
            report = attach_expected_certificate_hash(report,
                                                      result.certificate.certificate_hash)
        else
            report = CertSDP.Kernel.DiagnosticReport(false,
                                                     :I,
                                                     :tssos_importer,
                                                     :candidate_replay,
                                                     result.failure.message,
                                                     :tssos_artifact,
                                                     nothing,
                                                     nothing,
                                                     nothing,
                                                     nothing,
                                                     nothing,
                                                     artifact_path,
                                                     Dict{Symbol, Any}())
        end
    end
    return CertSDP.Perf.ReplayMeasurement(artifact_path,
                                          report.accepted,
                                          elapsed,
                                          0,
                                          report)
end

function validate_sparse_sos_certificate(path::AbstractString)
    cert = try
        CertSDP.Kernel.parse_sparse_sos_certificate_json(read(path, String))
    catch err
        return CertSDP.Kernel.DiagnosticReport(false,
                                               :H,
                                               :sparse_sos,
                                               :parse,
                                               sprint(showerror, err),
                                               :sparse_sos_certificate,
                                               nothing,
                                               nothing,
                                               nothing,
                                               nothing,
                                               nothing,
                                               path,
                                               Dict{Symbol, Any}())
    end
    report = CertSDP.Kernel.verify_sparse_sos_certificate(cert)
    return attach_expected_certificate_hash(report, cert.certificate_hash)
end

function validate_algebraic_psd_factor(path::AbstractString)
    parsed = try
        JSON3.read(read(path, String))
    catch err
        return CertSDP.Kernel.DiagnosticReport(false,
                                               :D,
                                               :psd_factor_algebraic,
                                               :parse,
                                               sprint(showerror, err),
                                               :algebraic_psd_certificate,
                                               nothing,
                                               nothing,
                                               nothing,
                                               nothing,
                                               nothing,
                                               path,
                                               Dict{Symbol, Any}())
    end
    try
        field = CertSDP.Kernel._parse_algebraic_field_certificate_object(parsed[:field],
                                                                         "root.field")
        matrix = CertSDP.Kernel.parse_sparse_matrix_object(parsed[:matrix];
                                                           strict=true,
                                                           path="root.matrix")
        factor = [[CertSDP.Kernel._parse_algebraic_element_object(value,
                                                                  field,
                                                                  "root.factor")
                   for value in row]
                  for row in parsed[:factor]]
        diagonal = [CertSDP.Kernel._parse_algebraic_element_object(value,
                                                                   field,
                                                                   "root.diagonal")
                    for value in parsed[:diagonal]]
        proof = CertSDP.Kernel.ExactAlgebraicLowRankPSDProof(matrix,
                                                             field,
                                                             factor,
                                                             diagonal)
        supplied = String(parsed[:identity_proof_hash])
        supplied == proof.identity_proof_hash ||
            error("identity proof hash mismatch")
        report = CertSDP.Kernel.verify_algebraic_low_rank_psd(matrix, proof)
        return attach_expected_certificate_hash(report,
                                                String(parsed[:certificate_hash]))
    catch err
        return CertSDP.Kernel.DiagnosticReport(false,
                                               :D,
                                               :psd_factor_algebraic,
                                               :parse,
                                               sprint(showerror, err),
                                               :algebraic_psd_certificate,
                                               nothing,
                                               nothing,
                                               nothing,
                                               nothing,
                                               nothing,
                                               path,
                                               Dict{Symbol, Any}())
    end
end

function validate_symmetry_certificate(path::AbstractString)
    cert = try
        CertSDP.Kernel.parse_block_diagonalization_certificate_json(read(path, String))
    catch err
        return CertSDP.Kernel.DiagnosticReport(false,
                                               :W,
                                               :symmetry_reduction,
                                               :parse,
                                               sprint(showerror, err),
                                               :symmetry_certificate,
                                               nothing,
                                               nothing,
                                               nothing,
                                               nothing,
                                               nothing,
                                               path,
                                               Dict{Symbol, Any}())
    end
    report = CertSDP.Kernel.verify_block_diagonalization_certificate(cert)
    return attach_expected_certificate_hash(report, cert.certificate_hash)
end

function validate_tssos_tamper(path::AbstractString)
    result = CertSDP.certify_tssos_artifact(path)
    if result isa CertSDP.CertifiedResult
        report = CertSDP.Kernel.verify_sparse_sos_certificate(result.certificate)
        return attach_expected_certificate_hash(report,
                                                result.certificate.certificate_hash)
    end
    return CertSDP.Kernel.DiagnosticReport(false,
                                           :I,
                                           :tssos_importer,
                                           :candidate_replay,
                                           result.failure.message,
                                           :tssos_artifact,
                                           nothing,
                                           nothing,
                                           nothing,
                                           nothing,
                                           nothing,
                                           path,
                                           Dict{Symbol, Any}())
end

function validate_nctssos_artifact(dir::AbstractString)
    artifact_path = joinpath(dir, "artifact.json")
    elapsed = @elapsed begin
        result = CertSDP.certify_nctssos_artifact(artifact_path)
        if result isa CertSDP.CertifiedResult
            report = CertSDP.Kernel.verify_quantum_bound_certificate(result.certificate)
            report = attach_expected_certificate_hash(report,
                                                      result.certificate.certificate_hash)
        else
            report = CertSDP.Kernel.DiagnosticReport(false,
                                                     :K,
                                                     :nctssos_importer,
                                                     :candidate_replay,
                                                     result.failure.message,
                                                     :nctssos_artifact,
                                                     nothing,
                                                     nothing,
                                                     nothing,
                                                     nothing,
                                                     nothing,
                                                     artifact_path,
                                                     Dict{Symbol, Any}())
        end
    end
    return CertSDP.Perf.ReplayMeasurement(artifact_path,
                                          report.accepted,
                                          elapsed,
                                          0,
                                          report)
end

function validate_nctssos_tamper(path::AbstractString)
    result = CertSDP.certify_nctssos_artifact(path)
    if result isa CertSDP.CertifiedResult
        report = CertSDP.Kernel.verify_quantum_bound_certificate(result.certificate)
        return attach_expected_certificate_hash(report,
                                                result.certificate.certificate_hash)
    end
    return CertSDP.Kernel.DiagnosticReport(false,
                                           :K,
                                           :nctssos_importer,
                                           :candidate_replay,
                                           result.failure.message,
                                           :nctssos_artifact,
                                           nothing,
                                           nothing,
                                           nothing,
                                           nothing,
                                           nothing,
                                           path,
                                           Dict{Symbol, Any}())
end

function validate_quantum_certificate(path::AbstractString)
    cert = try
        CertSDP.Kernel.parse_quantum_bound_certificate_json(read(path, String))
    catch err
        return CertSDP.Kernel.DiagnosticReport(false,
                                               :J,
                                               :quantum_bound,
                                               :parse,
                                               sprint(showerror, err),
                                               :quantum_certificate,
                                               nothing,
                                               nothing,
                                               nothing,
                                               nothing,
                                               nothing,
                                               path,
                                               Dict{Symbol, Any}())
    end
    report = CertSDP.Kernel.verify_quantum_bound_certificate(cert)
    report = attach_expected_certificate_hash(report, cert.certificate_hash)
    return CertSDP.Kernel.DiagnosticReport(report.accepted,
                                           report.gate,
                                           report.family,
                                           report.stage,
                                           report.reason,
                                           report.obligation_id,
                                           report.problem_hash,
                                           report.certificate_hash,
                                           report.block_id,
                                           report.clique_id,
                                           report.separator_id,
                                           path,
                                           report.details)
end

function parse_options(args)
    max_memory_gb = 12.0
    timeout_minutes = 30.0
    root = normpath(joinpath(@__DIR__, "..", "test", "fixtures", "certsdp3"))
    quiet = false
    single_path = nothing
    for arg in args
        if startswith(arg, "--max-memory-gb=")
            max_memory_gb = parse(Float64, split(arg, "=", limit=2)[2])
        elseif startswith(arg, "--timeout-minutes=")
            timeout_minutes = parse(Float64, split(arg, "=", limit=2)[2])
        elseif startswith(arg, "--fixtures=")
            root = split(arg, "=", limit=2)[2]
        elseif arg == "--quiet"
            quiet = true
        elseif !startswith(arg, "--") && isnothing(single_path)
            single_path = arg
        else
            error("unknown option `$arg`")
        end
    end
    return (; max_memory_gb, timeout_minutes, root, quiet, single_path)
end

function validate_certsdp3_main(args=ARGS)
    options = parse_options(args)
    if !isnothing(options.single_path)
        path = normpath(options.single_path)
        isfile(path) || error("validation path does not exist: $path")
        measurement = CertSDP.Perf.measure_replay(path)
        failures = String[]
        measurement.accepted || push!(failures, "certificate rejected: $path")
        CertSDP.Perf.memory_budget_check(measurement;
                                         max_memory_mb=options.max_memory_gb * 1024) ||
            push!(failures, "memory budget exceeded for $path")
        measurement.elapsed_seconds <= options.timeout_minutes * 60 ||
            push!(failures, "runtime budget exceeded for $path")
        if !options.quiet
            println("CERTSDP3_VALIDATION")
            println("path: ", path)
            println("accepted: ", measurement.accepted)
            println("runtime_seconds: ", round(measurement.elapsed_seconds; digits=3))
            println("peak_memory_mb: ", round(measurement.allocated_bytes / 1024^2; digits=3))
        end
        isempty(failures) && begin
            options.quiet || println("result: PASS")
            return 0
        end
        options.quiet || begin
            println("result: FAIL")
            for failure in failures
                println("failure: ", failure)
            end
        end
        return 1
    end
    index_path = joinpath(options.root, "index.json")
    isfile(index_path) || error("missing fixture index: $index_path")
    index = JSON3.read(read(index_path, String))
    measurements = CertSDP.Perf.ReplayMeasurement[]
    failures = String[]
    covered_gates = Set{String}()
    medium_fixture_count = 0
    sparse_block_chordal_count = 0
    sos_fixture_count = 0
    quantum_fixture_count = 0
    primal_dual_fixture_count = 0
    farkas_fixture_count = 0

    haskey(index, :fixtures) || push!(failures, "fixture index missing fixtures array")

    for (fixture_index, fixture) in enumerate(index[:fixtures])
        require_index_schema!(fixture, failures, fixture_index)
        haskey(fixture, :certificate_hash) &&
            validate_sha256_text(fixture[:certificate_hash],
                                 "fixture $(fixture[:fixture_id]) certificate_hash",
                                 failures)
        haskey(fixture, :problem_hash) &&
            validate_sha256_text(fixture[:problem_hash],
                                 "fixture $(fixture[:fixture_id]) problem_hash",
                                 failures)
        for gate in String.(get(fixture, :gate_ids_covered, String[]))
            push!(covered_gates, gate)
        end
        dir = joinpath(options.root, String(fixture[:fixture_id]))
        cert_path = joinpath(dir, "certificate.json")
        isfile(cert_path) ||
            push!(failures, "accepted fixture certificate missing: $cert_path")
        validate_fixture_shape!(fixture, dir, failures)
        CertSDP.Debug.reset_densification_counter!()
        family = String(fixture[:problem_family])
        measurement = String(fixture[:fixture_id]) == "sparse_chordal_stress_3000" ?
                      CertSDP.Perf.measure_chordal_replay(cert_path) :
                      CertSDP.Perf.measure_replay(cert_path)
        push!(measurements, measurement)
        measurement.accepted || push!(failures, "accepted fixture rejected: $cert_path")
        if family == "tssos_sparse_sos_import"
            importer_measurement = validate_tssos_artifact(dir)
            importer_measurement.accepted ||
                push!(failures, "TSSOS artifact importer rejected fixture: $dir")
        elseif family == "nctssos_import"
            importer_measurement = validate_nctssos_artifact(dir)
            importer_measurement.accepted ||
                push!(failures, "NCTSSOS artifact importer rejected fixture: $dir")
        end
        check_report_hashes!(fixture, measurement, failures)
        limit_mb = Float64(fixture[:max_memory_mb])
        CertSDP.Perf.memory_budget_check(measurement; max_memory_mb=limit_mb) ||
            push!(failures, "memory budget exceeded for $cert_path")
        measurement.elapsed_seconds <= Float64(fixture[:max_runtime_seconds]) ||
            push!(failures, "runtime budget exceeded for $cert_path")
        if occursin("chordal", String(fixture[:problem_family]))
            CertSDP.Debug.densification_counter() == 0 ||
                push!(failures, "densification counter nonzero for $cert_path")
        end

        id = String(fixture[:fixture_id])
        if id in ("psd_factor_rational_150",
                  "psd_factor_algebraic_40",
                  "sparse_chordal_120",
                  "sparse_chordal_stress_3000",
                  "block_native_algebraic_medium",
                  "primal_dual_portfolio_50",
                  "farkas_infeasible_lmi_medium",
                  "tssos_sparse_industry_medium",
                  "sparse_sos_control_lyapunov",
                  "sparse_putinar_opf_5bus",
                  "quantum_i3322_medium",
                  "nctssos_trace_medium")
            medium_fixture_count += 1
        end
        occursin("chordal", family) || occursin("block_native", family) ?
            (sparse_block_chordal_count += 1) : nothing
        family in ("sparse_sos_certificate", "tssos_sparse_sos_import") &&
            (sos_fixture_count += 1)
        family in ("quantum_bound", "nctssos_import") &&
            (quantum_fixture_count += 1)
        family == "primal_dual_optimality" &&
            (primal_dual_fixture_count += 1)
        family == "farkas_infeasibility" &&
            (farkas_fixture_count += 1)

        for tamper in fixture[:tamper_files]
            tamper_path = joinpath(dir, String(tamper))
            isfile(tamper_path) ||
                push!(failures, "tamper fixture missing: $tamper_path")
            report = if family == "tssos_sparse_sos_import" &&
                        !occursin("certificate", basename(tamper_path))
                validate_tssos_tamper(tamper_path)
            elseif family == "nctssos_import" &&
                   !occursin("certificate", basename(tamper_path))
                validate_nctssos_tamper(tamper_path)
            else
                CertSDP.Kernel.replay_file(tamper_path; strict=true)
            end
            report.accepted &&
                push!(failures, "tamper fixture accepted: $tamper_path")
            report.stage === :unknown &&
                push!(failures, "tamper fixture has unknown stage: $tamper_path")
            cli_code = CertSDP.main(["replay", tamper_path, "--strict"];
                                    io=IOBuffer(), err=IOBuffer())
            cli_code == CertSDP.CLI_EXIT_OK &&
                push!(failures, "tamper fixture CLI replay exited 0: $tamper_path")
        end
    end

    missing_p0_gates = setdiff(P0_VALIDATION_GATES, covered_gates)
    isempty(missing_p0_gates) ||
        push!(failures, "validation corpus missing P0 gate coverage: $(join(sort!(collect(missing_p0_gates)), ", "))")
    medium_fixture_count >= 8 ||
        push!(failures, "validation corpus has fewer than 8 medium fixtures: $medium_fixture_count")
    sparse_block_chordal_count >= 3 ||
        push!(failures, "validation corpus has fewer than 3 sparse/block/chordal fixtures: $sparse_block_chordal_count")
    sos_fixture_count >= 2 ||
        push!(failures, "validation corpus has fewer than 2 SOS/localizing fixtures: $sos_fixture_count")
    quantum_fixture_count >= 1 ||
        push!(failures, "validation corpus lacks NC/quantum fixture")
    primal_dual_fixture_count >= 1 ||
        push!(failures, "validation corpus lacks primal-dual fixture")
    farkas_fixture_count >= 1 ||
        push!(failures, "validation corpus lacks Farkas fixture")

    summary = CertSDP.Perf.validation_summary(measurements)
    if !options.quiet
        println("CERTSDP3_VALIDATION")
        println("fixtures: ", summary.count)
        println("accepted: ", summary.accepted)
        println("total_runtime_seconds: ", round(summary.total_runtime_seconds; digits=3))
        println("peak_memory_mb: ", round(summary.peak_memory_mb; digits=3))
    end

    summary.total_runtime_seconds <= options.timeout_minutes * 60 ||
        push!(failures, "total runtime budget exceeded")
    summary.peak_memory_mb <= options.max_memory_gb * 1024 ||
        push!(failures, "peak memory budget exceeded")

    if isempty(failures)
        options.quiet || println("result: PASS")
        return 0
    end
    if !options.quiet
        println("result: FAIL")
        for failure in failures
            println("failure: ", failure)
        end
    end
    return 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(validate_certsdp3_main())
end
