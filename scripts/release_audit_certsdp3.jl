#!/usr/bin/env julia

pushfirst!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))

using CertSDP
using JSON3

const ROOT = normpath(joinpath(@__DIR__, ".."))

include(joinpath(@__DIR__, "validate_certsdp3.jl"))

const REQUIRED_TESTS = [
    "kernel_trust_boundary.jl",
    "sparse_ir.jl",
    "chordal_psd_certificate.jl",
    "psd_low_rank_factor.jl",
    "proof_dag_roundtrip.jl",
    "schema_strict.jl",
    "diagnostics_report.jl",
    "cli_product_surface.jl",
    "hash_stability.jl",
    "mutation_corpus.jl",
]

const GATES = [
    (:A_trusted_kernel, ["kernel_trust_boundary.jl",
                         "adapter_untrusted_metadata_rejection.jl",
                         "exactify_candidates_must_replay.jl"]),
    (:B_sparse_ir, ["sparse_ir.jl", "chordal_psd_certificate.jl",
                    "no_densification_budget.jl"]),
    (:C_block_native_algebraic, ["block_native_incidence.jl", "block_native_algebraic_certificate.jl"]),
    (:D_large_psd_engine, ["psd_low_rank_factor.jl",
                           "psd_chordal_completion.jl",
                           "psd_planner_policy.jl",
                           "chordal_psd_certificate.jl"]),
    (:E_proof_dag, ["proof_dag_roundtrip.jl", "proof_dag_tamper.jl"]),
    (:F_schema_strict, ["schema_strict.jl", "schema_fuzz_mutations.jl"]),
    (:G_primal_dual_farkas, ["primal_dual_optimality.jl",
                             "farkas_certificate.jl",
                             "objective_bound_certificate.jl"]),
    (:H_sparse_sos, ["sparse_sos_certificate.jl"]),
    (:I_tssos_importer, ["tssos_importer.jl"]),
    (:J_nc_quantum, ["nc_rewrite_witness.jl", "quantum_bound_certificate.jl"]),
    (:K_nctssos_importer, ["nctssos_importer.jl"]),
    (:L_field_layer, ["field_layer.jl"]),
    (:O_diagnostics, ["diagnostics_report.jl", "cli_replay_explain.jl"]),
    (:P_cli, ["cli_product_surface.jl"]),
    (:Q_validation_corpus, ["../fixtures/certsdp3/index.json"]),
    (:R_tamper_tests, ["mutation_corpus.jl"]),
    (:S_performance, ["../../scripts/validate_certsdp3.jl"]),
    (:T_no_densification, ["chordal_psd_certificate.jl"]),
    (:U_hash_stability, ["hash_stability.jl"]),
    (:V_exact_arithmetic_safety, ["../../scripts/check_certsdp3_static_rules.jl"]),
    (:Y_backward_compatibility, ["backward_compatibility.jl"]),
    (:M_backend_interface, ["algebraic_backend_interface.jl",
                            "msolve_fixture_backend.jl",
                            "backend_failure_semantics.jl"]),
    (:N_adapters, ["sdpa_sparse_adapter.jl", "tssos_importer.jl"]),
    (:W_symmetry_reduction, ["symmetry_reduction.jl"]),
    (:X_paper_bundle, ["paper_bundle.jl"]),
    (:Z_release_audit, ["../../scripts/release_audit_certsdp3.jl"]),
]

const MIN_MUTATION_CASES = 300

const COVERAGE_THRESHOLDS = [
    (:kernel_exact_replay, 0.90, ["src/kernel/Kernel.jl",
                                  "src/systems/IncidenceBuilder.jl"]),
    (:schema_parser, 0.90, ["src/kernel/Kernel.jl"]),
    (:psd_proof_engine, 0.85, ["src/kernel/Kernel.jl"]),
    (:sos_nc_replay, 0.85, ["src/kernel/Kernel.jl",
                            "src/adapters/Adapters.jl"]),
    (:cli, 0.75, ["src/apps/Apps.jl"]),
    (:overall_certsdp3, 0.80, ["src/kernel/Kernel.jl",
                               "src/adapters/Adapters.jl",
                               "src/apps/Apps.jl",
                               "src/exactify/Backends3.jl",
                               "src/systems/IncidenceBuilder.jl"]),
]

function parse_args(args)
    return (; json=("--json" in args))
end

function exists_requirement(path)
    if startswith(path, "../fixtures")
        return isfile(normpath(joinpath(ROOT, "test", "certsdp3", path)))
    elseif startswith(path, "../../scripts")
        script_name = basename(path)
        return isfile(joinpath(ROOT, "scripts", script_name))
    end
    return isfile(joinpath(ROOT, "test", "certsdp3", path))
end

function audit(; quiet_validation::Bool=false)
    gate_status = Dict{Symbol, String}()
    for (gate, requirements) in GATES
        gate_status[gate] = all(exists_requirement, requirements) ? "PASS" : "FAIL"
    end
    validation_exit = main_validate_for_audit(; quiet=quiet_validation)
    validation_exit == 0 || begin
        gate_status[:Q_validation_corpus] = "FAIL"
        gate_status[:S_performance] = "FAIL"
        gate_status[:R_tamper_tests] = "FAIL"
        gate_status[:Z_release_audit] = "FAIL"
    end
    qa = audit_qa_evidence()
    gate_status[:R_tamper_tests] = qa.mutation_cases >= MIN_MUTATION_CASES ? gate_status[:R_tamper_tests] : "FAIL"
    thresholds = Dict(name => threshold
                      for (name, threshold, _) in COVERAGE_THRESHOLDS)
    coverage_pass = all(((name, value),) -> value >= thresholds[name],
                        qa.coverage)
    coverage_pass || (gate_status[:Z_release_audit] = "FAIL")

    index_path = joinpath(ROOT, "test", "fixtures", "certsdp3", "index.json")
    accepted = 0
    rejected_tamper = 0
    runtime = 0.0
    peak_memory = 0.0
    if isfile(index_path)
        index = JSON3.read(read(index_path, String))
        for fixture in index[:fixtures]
            dir = joinpath(ROOT, "test", "fixtures", "certsdp3",
                           String(fixture[:fixture_id]))
            cert_path = joinpath(dir, "certificate.json")
            family = String(fixture[:problem_family])
            measurement = _audit_measure_family(family, dir, cert_path)
            runtime += measurement.elapsed_seconds
            peak_memory = max(peak_memory, measurement.allocated_bytes / 1024^2)
            accepted += measurement.accepted ? 1 : 0
            for tamper in fixture[:tamper_files]
                tamper_path = joinpath(dir, String(tamper))
                report = _audit_tamper_family(family, tamper_path)
                rejected_tamper += report.accepted ? 0 : 1
            end
        end
    end
    result = all(==("PASS"), values(gate_status)) ? "PASS" : "FAIL"
    return (; gate_status, accepted, rejected_tamper, runtime, peak_memory,
            mutation_cases=qa.mutation_cases,
            coverage=qa.coverage,
            result)
end

function main_validate_for_audit(; quiet::Bool=false)
    try
        args = ["--max-memory-gb=12", "--timeout-minutes=30"]
        quiet && push!(args, "--quiet")
        return validate_certsdp3_main(args)
    catch err
        println(stderr, "release audit validation check failed: ",
                sprint(showerror, err))
        return 1
    end
end

function audit_qa_evidence()
    coverage = coverage_summary()
    mutation_cases = mutation_case_count()
    return (; coverage, mutation_cases)
end

function mutation_case_count()
    source = read(joinpath(ROOT, "test", "certsdp3", "mutation_corpus.jl"),
                  String)
    base_cases = length(collect(eachmatch(r"=>\s*obj\s*->", source)))
    range_cases = 0
    for match_result in eachmatch(r"for\s+\w+\s+in\s+1:(\d+)", source)
        count_value = parse(Int, match_result.captures[1])
        block_start = match_result.offset
        next_for = findnext("for ", source, block_start + 1)
        block_stop = isnothing(next_for) ? lastindex(source) : first(next_for) - 1
        block = source[block_start:block_stop]
        pushes = length(collect(eachmatch(r"push!\(mutations", block)))
        range_cases += count_value * pushes
    end
    return base_cases + range_cases
end

function coverage_summary()
    run_coverage_tests()
    try
        cov_files = collect_cov_files()
        return [(name, coverage_ratio(cov_files, paths))
                for (name, _, paths) in COVERAGE_THRESHOLDS]
    finally
        cleanup_coverage_files()
    end
end

function run_coverage_tests()
    cleanup_coverage_files()
    command = `julia --project=$(ROOT) --startup-file=no --code-coverage=@$(joinpath(ROOT, "src")) $(joinpath(ROOT, "test", "certsdp3", "runtests_certsdp3.jl"))`
    success(command) || error("CertSDP 3.0 coverage test run failed")
    return nothing
end

function cleanup_coverage_files()
    for path in collect(eachline(`find $(joinpath(ROOT, "src")) -name "*.cov"`))
        rm(path; force=true)
    end
    return nothing
end

function collect_cov_files()
    files = Dict{String, Vector{String}}()
    for path in eachline(`find $(joinpath(ROOT, "src")) -name "*.cov"`)
        rel = relpath(path, ROOT)
        base = replace(rel, r"\.\d+\.cov$" => "")
        push!(get!(files, base, String[]), path)
    end
    return files
end

function coverage_ratio(cov_files::Dict{String, Vector{String}},
                        relpaths::Vector{String})
    covered = 0
    total = 0
    for relpath_value in relpaths
        haskey(cov_files, relpath_value) ||
            error("missing coverage file for $relpath_value")
        for path in cov_files[relpath_value]
            c, t = coverage_counts(path)
            covered += c
            total += t
        end
    end
    total > 0 || error("no coverable lines in $(join(relpaths, ", "))")
    return covered / total
end

function coverage_counts(path::AbstractString)
    covered = 0
    total = 0
    for line in eachline(path)
        match_result = match(r"^\s*(-|\d+)\s", line)
        isnothing(match_result) && continue
        value = match_result.captures[1]
        value == "-" && continue
        total += 1
        parse(Int, value) > 0 && (covered += 1)
    end
    return covered, total
end

function _audit_measure_family(family::String, dir::AbstractString,
                               cert_path::AbstractString)
    if family == "block_native_algebraic_incidence"
        elapsed = @elapsed report = validate_block_native_certificate(cert_path)
        return CertSDP.Perf.ReplayMeasurement(cert_path, report.accepted,
                                              elapsed, 0, report)
    elseif family == "primal_dual_optimality"
        elapsed = @elapsed report = validate_primal_dual_certificate(cert_path)
        return CertSDP.Perf.ReplayMeasurement(cert_path, report.accepted,
                                              elapsed, 0, report)
    elseif family == "farkas_infeasibility"
        elapsed = @elapsed report = validate_farkas_certificate(cert_path)
        return CertSDP.Perf.ReplayMeasurement(cert_path, report.accepted,
                                              elapsed, 0, report)
    elseif family == "tssos_sparse_sos_import"
        return validate_tssos_artifact(dir)
    elseif family == "sparse_sos_certificate"
        elapsed = @elapsed report = validate_sparse_sos_certificate(cert_path)
        return CertSDP.Perf.ReplayMeasurement(cert_path, report.accepted,
                                              elapsed, 0, report)
    elseif family == "algebraic_low_rank_psd"
        elapsed = @elapsed report = validate_algebraic_psd_factor(cert_path)
        return CertSDP.Perf.ReplayMeasurement(cert_path, report.accepted,
                                              elapsed, 0, report)
    elseif family == "symmetry_reduction"
        elapsed = @elapsed report = validate_symmetry_certificate(cert_path)
        return CertSDP.Perf.ReplayMeasurement(cert_path, report.accepted,
                                              elapsed, 0, report)
    elseif family == "nctssos_import"
        return validate_nctssos_artifact(dir)
    elseif family == "quantum_bound"
        elapsed = @elapsed report = validate_quantum_certificate(cert_path)
        return CertSDP.Perf.ReplayMeasurement(cert_path, report.accepted,
                                              elapsed, 0, report)
    end
    return CertSDP.Perf.measure_replay(cert_path)
end

function _audit_tamper_family(family::String, tamper_path::AbstractString)
    if family == "block_native_algebraic_incidence"
        return validate_block_native_certificate(tamper_path)
    elseif family == "primal_dual_optimality"
        return validate_primal_dual_certificate(tamper_path)
    elseif family == "farkas_infeasibility"
        return validate_farkas_certificate(tamper_path)
    elseif family == "tssos_sparse_sos_import"
        return validate_tssos_tamper(tamper_path)
    elseif family == "sparse_sos_certificate"
        return validate_sparse_sos_certificate(tamper_path)
    elseif family == "algebraic_low_rank_psd"
        return validate_algebraic_psd_factor(tamper_path)
    elseif family == "symmetry_reduction"
        return validate_symmetry_certificate(tamper_path)
    elseif family == "nctssos_import"
        return validate_nctssos_tamper(tamper_path)
    elseif family == "quantum_bound"
        return validate_quantum_certificate(tamper_path)
    end
    return CertSDP.Kernel.replay_file(tamper_path; strict=true)
end

function print_text(result)
    println("CERTSDP_3_0_RELEASE_AUDIT")
    println("environment:")
    println("julia: ", VERSION)
    println("cpu_threads: ", Threads.nthreads())
    println("max_memory_gb: 12")
    println("timeout_minutes: 30")
    println()
    println("gates:")
    for (gate, _) in GATES
        println(String(gate), ": ", result.gate_status[gate])
    end
    println()
    println("summary:")
    println("accepted_fixtures: ", result.accepted)
    println("rejected_tamper_fixtures: ", result.rejected_tamper)
    println("mutation_cases: ", result.mutation_cases)
    for (name, value) in result.coverage
        println("coverage_", String(name), ": ", round(100 * value; digits=2), "%")
    end
    println("total_runtime_seconds: ", round(result.runtime; digits=3))
    println("peak_memory_mb: ", round(result.peak_memory; digits=3))
    println("result: ", result.result)
end

function main(args=ARGS)
    options = parse_args(args)
    result = audit(; quiet_validation=options.json)
    if options.json
        JSON3.pretty(stdout, Dict(
            "result" => result.result,
            "gates" => Dict(String(key) => value
                            for (key, value) in result.gate_status),
            "accepted_fixtures" => result.accepted,
            "rejected_tamper_fixtures" => result.rejected_tamper,
            "mutation_cases" => result.mutation_cases,
            "coverage" => Dict(String(name) => value
                               for (name, value) in result.coverage),
            "total_runtime_seconds" => result.runtime,
            "peak_memory_mb" => result.peak_memory,
        ))
        println()
    else
        print_text(result)
    end
    return result.result == "PASS" ? 0 : 1
end

exit(main())
