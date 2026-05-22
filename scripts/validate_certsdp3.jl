#!/usr/bin/env julia

pushfirst!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))

using CertSDP
using JSON3

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
    return CertSDP.Kernel.verify_primal_dual_optimality(cert)
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
    return CertSDP.Kernel.verify_farkas_infeasibility(cert)
end

function validate_tssos_artifact(dir::AbstractString)
    artifact_path = joinpath(dir, "artifact.json")
    elapsed = @elapsed begin
        result = CertSDP.certify_tssos_artifact(artifact_path)
        report = result isa CertSDP.CertifiedResult ?
                 CertSDP.Kernel.verify_sparse_sos_certificate(result.certificate) :
                 CertSDP.Kernel.DiagnosticReport(false,
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
    return CertSDP.Kernel.verify_sparse_sos_certificate(cert)
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
        return CertSDP.Kernel.verify_algebraic_low_rank_psd(matrix, proof)
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
    return CertSDP.Kernel.verify_block_diagonalization_certificate(cert)
end

function validate_tssos_tamper(path::AbstractString)
    result = CertSDP.certify_tssos_artifact(path)
    if result isa CertSDP.CertifiedResult
        return CertSDP.Kernel.verify_sparse_sos_certificate(result.certificate)
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
        report = result isa CertSDP.CertifiedResult ?
                 CertSDP.Kernel.verify_quantum_bound_certificate(result.certificate) :
                 CertSDP.Kernel.DiagnosticReport(false,
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
    return CertSDP.Perf.ReplayMeasurement(artifact_path,
                                          report.accepted,
                                          elapsed,
                                          0,
                                          report)
end

function validate_nctssos_tamper(path::AbstractString)
    result = CertSDP.certify_nctssos_artifact(path)
    if result isa CertSDP.CertifiedResult
        return CertSDP.Kernel.verify_quantum_bound_certificate(result.certificate)
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
    for arg in args
        if startswith(arg, "--max-memory-gb=")
            max_memory_gb = parse(Float64, split(arg, "=", limit=2)[2])
        elseif startswith(arg, "--timeout-minutes=")
            timeout_minutes = parse(Float64, split(arg, "=", limit=2)[2])
        elseif startswith(arg, "--fixtures=")
            root = split(arg, "=", limit=2)[2]
        else
            error("unknown option `$arg`")
        end
    end
    return (; max_memory_gb, timeout_minutes, root)
end

function main(args=ARGS)
    options = parse_options(args)
    index_path = joinpath(options.root, "index.json")
    isfile(index_path) || error("missing fixture index: $index_path")
    index = JSON3.read(read(index_path, String))
    measurements = CertSDP.Perf.ReplayMeasurement[]
    failures = String[]

    for fixture in index[:fixtures]
        dir = joinpath(options.root, String(fixture[:fixture_id]))
        cert_path = joinpath(dir, "certificate.json")
        CertSDP.Debug.reset_densification_counter!()
        family = String(fixture[:problem_family])
        if family == "block_native_algebraic_incidence"
            elapsed = @elapsed report = validate_block_native_certificate(cert_path)
            measurement = CertSDP.Perf.ReplayMeasurement(cert_path,
                                                         report.accepted,
                                                         elapsed,
                                                         0,
                                                         report)
        elseif family == "primal_dual_optimality"
            elapsed = @elapsed report = validate_primal_dual_certificate(cert_path)
            measurement = CertSDP.Perf.ReplayMeasurement(cert_path,
                                                         report.accepted,
                                                         elapsed,
                                                         0,
                                                         report)
        elseif family == "farkas_infeasibility"
            elapsed = @elapsed report = validate_farkas_certificate(cert_path)
            measurement = CertSDP.Perf.ReplayMeasurement(cert_path,
                                                         report.accepted,
                                                         elapsed,
                                                         0,
                                                         report)
        elseif family == "tssos_sparse_sos_import"
            measurement = validate_tssos_artifact(dir)
        elseif family == "sparse_sos_certificate"
            elapsed = @elapsed report = validate_sparse_sos_certificate(cert_path)
            measurement = CertSDP.Perf.ReplayMeasurement(cert_path,
                                                         report.accepted,
                                                         elapsed,
                                                         0,
                                                         report)
        elseif family == "algebraic_low_rank_psd"
            elapsed = @elapsed report = validate_algebraic_psd_factor(cert_path)
            measurement = CertSDP.Perf.ReplayMeasurement(cert_path,
                                                         report.accepted,
                                                         elapsed,
                                                         0,
                                                         report)
        elseif family == "symmetry_reduction"
            elapsed = @elapsed report = validate_symmetry_certificate(cert_path)
            measurement = CertSDP.Perf.ReplayMeasurement(cert_path,
                                                         report.accepted,
                                                         elapsed,
                                                         0,
                                                         report)
        elseif family == "nctssos_import"
            measurement = validate_nctssos_artifact(dir)
        elseif family == "quantum_bound"
            elapsed = @elapsed report = validate_quantum_certificate(cert_path)
            measurement = CertSDP.Perf.ReplayMeasurement(cert_path,
                                                         report.accepted,
                                                         elapsed,
                                                         0,
                                                         report)
        else
            measurement = CertSDP.Perf.measure_replay(cert_path)
        end
        push!(measurements, measurement)
        measurement.accepted || push!(failures, "accepted fixture rejected: $cert_path")
        limit_mb = Float64(fixture[:max_memory_mb])
        CertSDP.Perf.memory_budget_check(measurement; max_memory_mb=limit_mb) ||
            push!(failures, "memory budget exceeded for $cert_path")
        measurement.elapsed_seconds <= Float64(fixture[:max_runtime_seconds]) ||
            push!(failures, "runtime budget exceeded for $cert_path")
        if occursin("chordal", String(fixture[:problem_family]))
            CertSDP.Debug.densification_counter() == 0 ||
                push!(failures, "densification counter nonzero for $cert_path")
        end

        for tamper in fixture[:tamper_files]
            tamper_path = joinpath(dir, String(tamper))
            report = if family == "block_native_algebraic_incidence"
                validate_block_native_certificate(tamper_path)
            elseif family == "primal_dual_optimality"
                validate_primal_dual_certificate(tamper_path)
            elseif family == "farkas_infeasibility"
                validate_farkas_certificate(tamper_path)
            elseif family == "tssos_sparse_sos_import"
                validate_tssos_tamper(tamper_path)
            elseif family == "sparse_sos_certificate"
                validate_sparse_sos_certificate(tamper_path)
            elseif family == "algebraic_low_rank_psd"
                validate_algebraic_psd_factor(tamper_path)
            elseif family == "symmetry_reduction"
                validate_symmetry_certificate(tamper_path)
            elseif family == "nctssos_import"
                validate_nctssos_tamper(tamper_path)
            elseif family == "quantum_bound"
                validate_quantum_certificate(tamper_path)
            else
                CertSDP.Kernel.replay_file(tamper_path; strict=true)
            end
            report.accepted &&
                push!(failures, "tamper fixture accepted: $tamper_path")
            report.stage === :unknown &&
                push!(failures, "tamper fixture has unknown stage: $tamper_path")
        end
    end

    summary = CertSDP.Perf.validation_summary(measurements)
    println("CERTSDP3_VALIDATION")
    println("fixtures: ", summary.count)
    println("accepted: ", summary.accepted)
    println("total_runtime_seconds: ", round(summary.total_runtime_seconds; digits=3))
    println("peak_memory_mb: ", round(summary.peak_memory_mb; digits=3))

    summary.total_runtime_seconds <= options.timeout_minutes * 60 ||
        push!(failures, "total runtime budget exceeded")
    summary.peak_memory_mb <= options.max_memory_gb * 1024 ||
        push!(failures, "peak memory budget exceeded")

    if isempty(failures)
        println("result: PASS")
        return 0
    end
    println("result: FAIL")
    for failure in failures
        println("failure: ", failure)
    end
    return 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
