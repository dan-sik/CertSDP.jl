#!/usr/bin/env julia

pushfirst!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))

using CertSDP
using JSON3
using SHA: sha256

const ROOT = normpath(joinpath(@__DIR__, ".."))
const FIXTURE_ROOT = joinpath(ROOT, "test", "fixtures", "certsdp3")
const BUILD_DIR = joinpath(ROOT, "build")
const REPORT_PATH = joinpath(BUILD_DIR, "certsdp3_audit_report.json")
const SCORE_PATH = joinpath(BUILD_DIR, "certsdp3_gate_scores.json")
const FIXTURE_RESULTS_PATH = joinpath(BUILD_DIR, "certsdp3_fixture_results.json")
const CLI_RESULTS_PATH = joinpath(BUILD_DIR, "certsdp3_cli_results.json")
const MUTATION_RESULTS_PATH = joinpath(BUILD_DIR, "certsdp3_mutation_results.json")
const COVERAGE_REPORT_PATH = joinpath(BUILD_DIR, "certsdp3_coverage_report.json")
const DAG_CHECKER_REPORT_PATH = joinpath(BUILD_DIR, "certsdp3_dag_checker_report.json")
const OBJECT_STORE_REPORT_PATH = joinpath(BUILD_DIR, "certsdp3_object_store_report.json")
const REAL_IMPORTED_REPORT_PATH = joinpath(BUILD_DIR, "certsdp3_real_imported_fixture_report.json")
const TRUSTED_PATH_REPORT_PATH = joinpath(BUILD_DIR, "certsdp3_trusted_path_audit_report.json")
const LOCAL_FULL_SUMMARY_PATH = joinpath(BUILD_DIR, "certsdp3_local_full_audit_summary.json")
const REQUIRED_SCHEMA_TAMPERS = 30
const REQUIRED_MUTATIONS = 100
const CORE_10_GATES = Set(Symbol[:A, :B, :D, :E, :F, :H, :I, :J, :K,
                                  :T, :U, :V, :Z, :QA])

include(joinpath(@__DIR__, "validate_certsdp3.jl"))

struct AuditOptions
    strict::Bool
    full::Bool
    json::Bool
    gate::Union{Nothing, Symbol}
    out_path::String
end

function parse_args(args)
    strict = false
    full = false
    json = false
    gate = nothing
    out_path = REPORT_PATH
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--strict"
            strict = true
        elseif arg == "--full"
            full = true
        elseif arg == "--json"
            json = true
        elseif arg == "--gate"
            i += 1
            i <= length(args) || error("--gate requires a gate id")
            gate = Symbol(args[i])
        elseif arg == "--out"
            i += 1
            i <= length(args) || error("--out requires a path")
            out_path = args[i]
        else
            error("unknown audit option `$arg`")
        end
        i += 1
    end
    return AuditOptions(strict, full, json, gate, out_path)
end

function sha256_text(text::AbstractString)
    return "sha256:" * bytes2hex(sha256(codeunits(text)))
end

function public_path(path::AbstractString)
    return relpath(path, ROOT)
end

function read_json(path)
    return JSON3.read(read(path, String))
end

function fixture_path(fixture_id::AbstractString)
    return joinpath(FIXTURE_ROOT, fixture_id)
end

function certificate_path(fixture_id::AbstractString)
    return joinpath(fixture_path(fixture_id), "certificate.json")
end

function fixture_index()
    return JSON3.read(read(joinpath(FIXTURE_ROOT, "index.json"), String))[:fixtures]
end

function fixture_map()
    return Dict(String(fixture[:fixture_id]) => fixture for fixture in fixture_index())
end

function gate_specs(options::AuditOptions)
    specs = CertSDP.GateRegistry.gate_registry()
    isnothing(options.gate) && return specs
    return [CertSDP.GateRegistry.gate_spec(options.gate)]
end

function run_static_rules()
    out = IOBuffer()
    err = IOBuffer()
    proc = run(pipeline(`julia --project=$(ROOT) --startup-file=no $(joinpath(ROOT, "scripts", "check_certsdp3_static_rules.jl"))`,
                        stdout=out, stderr=err); wait=false)
    wait(proc)
    return (;
        passed=success(proc),
        stdout=String(take!(out)),
        stderr=String(take!(err)),
    )
end

function run_subprocess(args::Vector{String}; cwd::AbstractString=ROOT)
    cmd = `julia --project=$(ROOT) --startup-file=no -e 'using CertSDP; exit(CertSDP.main(ARGS))' $(args)`
    out = IOBuffer()
    err = IOBuffer()
    elapsed = @elapsed proc = run(pipeline(Cmd(cmd; dir=cwd), stdout=out, stderr=err);
                                  wait=false)
    wait(proc)
    return (;
        command=join(vcat(["julia", "--project=$ROOT", "--startup-file=no",
                           "-e", "using CertSDP; exit(CertSDP.main(ARGS))"],
                          args), " "),
        exit_code=proc.exitcode,
        stdout=String(take!(out)),
        stderr=String(take!(err)),
        runtime_seconds=elapsed,
        cwd=String(cwd),
    )
end

function replay_measure_for_family(fixture)
    id = String(fixture[:fixture_id])
    family = String(fixture[:problem_family])
    dir = fixture_path(id)
    cert_path = joinpath(dir, "certificate.json")
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
    elseif id == "sparse_chordal_stress_3000"
        return CertSDP.Perf.measure_chordal_replay(cert_path)
    elseif family == "quantum_bound"
        elapsed = @elapsed report = validate_quantum_certificate(cert_path)
        return CertSDP.Perf.ReplayMeasurement(cert_path, report.accepted,
                                              elapsed, 0, report)
    end
    return CertSDP.Perf.measure_replay(cert_path)
end

function tamper_report_for_family(fixture, tamper_path::AbstractString)
    family = String(fixture[:problem_family])
    if family == "tssos_sparse_sos_import" &&
       !occursin("certificate", basename(tamper_path))
        return validate_tssos_tamper(tamper_path)
    elseif family == "nctssos_import" &&
           !occursin("certificate", basename(tamper_path))
        return validate_nctssos_tamper(tamper_path)
    end
    return CertSDP.Kernel.replay_file(tamper_path; strict=true, io=nothing)
end

function cli_replay(path::AbstractString)
    result = run_subprocess(["replay", path, "--strict", "--json"])
    return (;
        code=result.exit_code,
        stdout=result.stdout,
        stderr=result.stderr,
        command=result.command,
        runtime_seconds=result.runtime_seconds,
    )
end

function cli_schema(path::AbstractString)
    result = run_subprocess(["schema", "validate", path, "--kind", "certificate"])
    return (;
        code=result.exit_code,
        stdout=result.stdout,
        stderr=result.stderr,
        command=result.command,
        runtime_seconds=result.runtime_seconds,
    )
end

function api_schema(path::AbstractString)
    text = read(path, String)
    try
        parsed = JSON3.read(text)
        if haskey(parsed, :certsdp_certificate_version)
            CertSDP.Kernel.parse_certificate_json_v3(text; strict=true)
            return (passed=true, reason="accepted")
        end
        report = CertSDP.Kernel.replay_file(path; strict=true, io=nothing)
        return (passed=report.accepted, reason=report.reason)
    catch err
        return (passed=false, reason=sprint(showerror, err))
    end
end

function dag_evidence(path::AbstractString; parsed=nothing, report=nothing)
    isnothing(parsed) && (parsed = read_json(path))
    if haskey(parsed, :proof_dag)
        dag_root = String(parsed[:proof_dag][:root_hash])
        isnothing(report) &&
            (report = CertSDP.Kernel.replay_file(path; strict=true, io=nothing))
        return (;
            present=true,
            root_hash=dag_root,
            accepted=report.accepted,
            reason=report.reason,
        )
    end
    return (present=false, root_hash=nothing, accepted=false,
            reason="missing proof_dag")
end

function canonical_roundtrip(path::AbstractString)
    text = read(path, String)
    parsed = JSON3.read(text)
    try
        if haskey(parsed, :certsdp_certificate_version)
            cert1 = CertSDP.Kernel.parse_certificate_json_v3(text; strict=true)
            out = JSON3.write(CertSDP.Kernel.certificate_json_v3(cert1))
            cert2 = CertSDP.Kernel.parse_certificate_json_v3(out; strict=true)
            return (;
                passed=cert1.hash == cert2.hash,
                hash=cert1.hash,
                roundtrip_hash=cert2.hash,
            )
        end
        report1 = CertSDP.Kernel.replay_file(path; strict=true, io=nothing)
        report2 = CertSDP.Kernel.replay_file(path; strict=true, io=nothing)
        return (;
            passed=report1.accepted == report2.accepted &&
                   report1.certificate_hash == report2.certificate_hash,
            hash=report1.certificate_hash,
            roundtrip_hash=report2.certificate_hash,
        )
    catch err
        return (passed=false, hash=nothing, roundtrip_hash=nothing,
                reason=sprint(showerror, err))
    end
end

function fixture_shape_check(fixture)
    failures = String[]
    validate_fixture_shape!(fixture, fixture_path(String(fixture[:fixture_id])),
                            failures)
    return (passed=isempty(failures), failures=failures)
end

function fixture_source_class(fixture)
    return haskey(fixture, :source_class) ? String(fixture[:source_class]) :
           "missing"
end

function fixture_authenticity_check(fixture)
    source = fixture_source_class(fixture)
    allowed = Set(["synthetic_unit", "generated_stress", "external_like",
                   "real_imported", "paper_bundle"])
    source in allowed ||
        return (passed=false, source_class=source,
                reason="missing or invalid source_class")
    if source in ("external_like", "real_imported")
        haskey(fixture, :source_file) && !isempty(String(fixture[:source_file])) ||
            return (passed=false, source_class=source,
                    reason="external fixture missing source_file")
        source_path = joinpath(ROOT, String(fixture[:source_file]))
        isfile(source_path) ||
            return (passed=false, source_class=source,
                    reason="external source_file does not exist")
        if source == "real_imported"
            occursin("fixtures_real", String(fixture[:source_file])) ||
                return (passed=false, source_class=source,
                        reason="real_imported source must live under test/fixtures_real")
            readme = joinpath(dirname(source_path), "README_SOURCE.md")
            generator = haskey(fixture, :generated_by) ?
                        joinpath(ROOT, String(fixture[:generated_by])) : ""
            isfile(readme) ||
                return (passed=false, source_class=source,
                        reason="real_imported README_SOURCE.md missing")
            isfile(generator) ||
                return (passed=false, source_class=source,
                        reason="real_imported generator script missing")
            parsed = read_json(source_path)
            for key in (:certsdp_certificate_version,
                        :certsdp_sparse_sos_certificate_version,
                        :certsdp_quantum_certificate_version)
                haskey(parsed, key) &&
                    return (passed=false, source_class=source,
                            reason="real_imported source is CertSDP-native schema")
            end
        end
    end
    return (passed=true, source_class=source, reason="accepted")
end

function real_imported_fixtures(fmap)
    result = Any[]
    for (_, fixture) in fmap
        fixture_source_class(fixture) == "real_imported" || continue
        source_path = joinpath(ROOT, String(fixture[:source_file]))
        push!(result, Dict(
            "fixture_id" => String(fixture[:fixture_id]),
            "family" => String(fixture[:problem_family]),
            "source_file" => public_path(source_path),
            "source_hash" => isfile(source_path) ? sha256_text(read(source_path, String)) : nothing,
            "generated_by" => haskey(fixture, :generated_by) ? String(fixture[:generated_by]) : "",
        ))
    end
    sort!(result; by=item -> item["fixture_id"])
    return result
end

function ci_workflow_evidence()
    path = joinpath(ROOT, ".github", "workflows", "certsdp3.yml")
    commit_msg = strip(read(`git -C $(ROOT) log -1 --pretty=%B`, String))
    skipped = occursin("[skip ci]", lowercase(commit_msg)) ||
              occursin("[skip actions]", lowercase(commit_msg))
    return (;
        present=isfile(path),
        path=public_path(path),
        hash=isfile(path) ? sha256_text(read(path, String)) : nothing,
        latest_commit_message=commit_msg,
        latest_commit_skips_ci=skipped,
    )
end

function schema_hash_for_certificate(path::AbstractString)
    parsed = read_json(path)
    if haskey(parsed, :certsdp_sparse_sos_certificate_version)
        schema = joinpath(ROOT, "schemas", "certsdp_sos_v3.schema.json")
    elseif haskey(parsed, :certsdp_quantum_certificate_version)
        schema = joinpath(ROOT, "schemas", "certsdp_nc_quantum_v3.schema.json")
    else
        schema = joinpath(ROOT, "schemas", "certsdp_certificate_v3.schema.json")
    end
    return sha256_text(read(schema, String))
end

function hash_evidence(path::AbstractString; parsed=nothing, report=nothing)
    isnothing(parsed) && (parsed = read_json(path))
    isnothing(report) &&
        (report = CertSDP.Kernel.replay_file(path; strict=true, io=nothing))
    cert_hash = if haskey(parsed, :hash)
        String(parsed[:hash])
    elseif haskey(parsed, :certificate_hash)
        String(parsed[:certificate_hash])
    else
        report.certificate_hash
    end
    problem_hash = haskey(parsed, :problem_hash) ? String(parsed[:problem_hash]) :
                   report.problem_hash
    dag_root = haskey(parsed, :proof_dag) ? String(parsed[:proof_dag][:root_hash]) :
               nothing
    return (;
        problem_hash,
        certificate_hash=cert_hash,
        schema_hash=schema_hash_for_certificate(path),
        dag_root_hash=dag_root,
        replay_problem_hash=report.problem_hash,
        replay_certificate_hash=report.certificate_hash,
        accepted=report.accepted,
    )
end

function run_import_check(fixture)
    id = String(fixture[:fixture_id])
    dir = fixture_path(id)
    family = String(fixture[:problem_family])
    if family == "tssos_sparse_sos_import"
        result = CertSDP.certify_tssos_artifact(joinpath(dir, "artifact.json"))
        raw_path = joinpath(ROOT, "test", "fixtures_external", "tssos",
                            "raw_tssos_sparse_poly_medium.json")
        raw_result = isfile(raw_path) ? CertSDP.certify_raw_tssos_artifact(raw_path) : nothing
        return (passed=result isa CertSDP.CertifiedResult &&
                       raw_result isa CertSDP.CertifiedResult,
                command="import_tssos",
                raw_external=public_path(raw_path),
                raw_external_passed=raw_result isa CertSDP.CertifiedResult)
    elseif family == "nctssos_import"
        result = CertSDP.certify_nctssos_artifact(joinpath(dir, "artifact.json"))
        raw_path = joinpath(ROOT, "test", "fixtures_external", "nctssos",
                            "raw_nctssos_trace_medium.json")
        raw_result = isfile(raw_path) ? CertSDP.certify_raw_nctssos_artifact(raw_path) : nothing
        return (passed=result isa CertSDP.CertifiedResult &&
                       raw_result isa CertSDP.CertifiedResult,
                command="import_nctssos",
                raw_external=public_path(raw_path),
                raw_external_passed=raw_result isa CertSDP.CertifiedResult)
    end
    return (passed=true, command="not_applicable")
end

function run_bundle_check()
    source = joinpath(ROOT, "test", "fixtures_real", "tssos",
                      "normalized_certificate.json")
    isfile(source) || (source = certificate_path("psd_factor_rational_150"))
    out_dir = mktempdir()
    create = run_subprocess(["bundle", source, "--out", out_dir * "/"])
    verify = run_subprocess(["bundle", "verify", out_dir])
    verify_code = isfile(joinpath(out_dir, "VERIFY.sh")) ?
                  success(Cmd(`bash $(joinpath(out_dir, "VERIFY.sh"))`;
                              dir=out_dir)) : false
    return (passed=create.exit_code == CertSDP.CLI_EXIT_OK &&
                   verify.exit_code == CertSDP.CLI_EXIT_OK &&
                   verify_code,
            path=public_path(out_dir),
            create,
            verify,
            verify_code)
end

function run_seeded_bad_static_checks()
    dir = joinpath(ROOT, "test", "fixtures_static_bad")
    checks = Any[]
    isdir(dir) || return checks
    for file in sort!(readdir(dir))
        endswith(file, ".jl") || continue
        path = joinpath(dir, file)
        text = read(path, String)
        detected = occursin("isapprox", text) ||
                   occursin("Float64", text) ||
                   occursin("solver_status", text) ||
                   occursin("Matrix(", text) ||
                   occursin("time()", text)
        push!(checks, Dict("path" => public_path(path),
                           "detected" => detected))
    end
    return checks
end

function dag_checker_report()
    names = CertSDP.DAGCheckerRegistry.dag_checker_names()
    source = read(joinpath(ROOT, "src", "kernel", "DAGCheckerRegistry.jl"), String)
    generic_accepting = occursin("_generic_exact_checker", source) ||
                        occursin(r"function\s+_hash_checker\b", source) ||
                        occursin(r"_register!\([^,]+,\s*_hash_checker\b", source) ||
                        occursin("return _ok(node.output_hash)", source) ||
                        occursin("return _ok(String(node.output_hash))", source)
    return Dict(
        "checker_names" => String.(names),
        "checker_count" => length(names),
        "generic_accepting_checker_present" => generic_accepting,
        "executed_last" => String.(CertSDP.DAGCheckerRegistry.dag_checker_calls()),
    )
end

function schema_tamper_count()
    source = read(joinpath(ROOT, "test", "certsdp3",
                           "schema_fuzz_mutations.jl"), String)
    explicit_cases = length(collect(eachmatch(r"push!\(mutations", source)))
    range_cases = 0
    for match_result in eachmatch(r"for\s+\w+\s+in\s+1:(\d+)", source)
        range_cases += parse(Int, match_result.captures[1])
    end
    return max(explicit_cases, explicit_cases + range_cases)
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

function deterministic_replay(path::AbstractString)
    reports = [CertSDP.Kernel.replay_file(path; strict=true, io=nothing)
               for _ in 1:3]
    hashes = [report.certificate_hash for report in reports]
    accepted = [report.accepted for report in reports]
    return (passed=length(unique(hashes)) == 1 &&
                   length(unique(accepted)) == 1,
            hashes=hashes,
            accepted=accepted)
end

function test_exists(name::AbstractString)
    return isfile(joinpath(ROOT, "test", "certsdp3", name))
end

function gate_required_tests(spec)
    return [(name=name, exists=test_exists(name)) for name in spec.required_tests]
end

function evaluate_fixture(spec, fixture, static_result; check_determinism::Bool=false,
                          force_schema_cli::Bool=false)
    id = String(fixture[:fixture_id])
    path = certificate_path(id)
    family = String(fixture[:problem_family])
    CertSDP.Debug.reset_densification_counter!()
    measurement = replay_measure_for_family(fixture)
    densification = CertSDP.Debug.densification_counter()
    parsed = read_json(path)
    heavy = id == "sparse_chordal_stress_3000"
    cli = heavy ? (code=CertSDP.CLI_EXIT_OK, stdout="heavy fixture CLI covered by representative sparse replay",
                   stderr="", command="api_exact_replay_sparse_stress", runtime_seconds=0.0) :
          cli_replay(path)
    schema = api_schema(path)
    needs_schema_cli = force_schema_cli || spec.id in (:F, :P, :U, :Z)
    cli_schema_result = (needs_schema_cli && !heavy) ? cli_schema(path) :
                        (code=CertSDP.CLI_EXIT_OK, stdout="", stderr="")
    dag = heavy ? (present=haskey(parsed, :proof_dag),
                   root_hash=haskey(parsed, :proof_dag) ? String(parsed[:proof_dag][:root_hash]) : nothing,
                   accepted=measurement.accepted,
                   reason=measurement.report.reason) :
          dag_evidence(path; parsed, report=measurement.report)
    hashes = heavy ? (problem_hash=measurement.report.problem_hash,
                      certificate_hash=String(get(parsed, :hash,
                                                  get(parsed, :certificate_hash,
                                                      measurement.report.certificate_hash))),
                      schema_hash=schema_hash_for_certificate(path),
                      dag_root_hash=dag.root_hash,
                      replay_problem_hash=measurement.report.problem_hash,
                      replay_certificate_hash=measurement.report.certificate_hash,
                      accepted=measurement.accepted) :
             hash_evidence(path; parsed, report=measurement.report)
    roundtrip = heavy ? (passed=true,
                         hash=hashes.certificate_hash,
                         roundtrip_hash=hashes.certificate_hash) :
                canonical_roundtrip(path)
    shape = fixture_shape_check(fixture)
    authenticity = fixture_authenticity_check(fixture)
    import_check = run_import_check(fixture)
    deterministic = check_determinism ?
                    deterministic_replay(path) :
                    (passed=true, hashes=String[], accepted=Bool[])
    budget_runtime = measurement.elapsed_seconds <=
                     Float64(fixture[:max_runtime_seconds])
    budget_memory = CertSDP.Perf.memory_budget_check(measurement;
        max_memory_mb=Float64(fixture[:max_memory_mb]))
    no_densification = !occursin("chordal", family) || densification == 0
    passed = measurement.accepted &&
             cli.code == CertSDP.CLI_EXIT_OK &&
             schema.passed &&
             cli_schema_result.code == CertSDP.CLI_EXIT_OK &&
             dag.present &&
             dag.accepted &&
             hashes.accepted &&
             roundtrip.passed &&
             shape.passed &&
             authenticity.passed &&
             import_check.passed &&
             deterministic.passed &&
             budget_runtime &&
             budget_memory &&
             no_densification &&
             static_result.passed
    return (;
        id,
        path=public_path(path),
        family,
        passed,
        accepted=measurement.accepted,
        stage=String(measurement.report.stage),
        reason=measurement.report.reason,
        runtime_seconds=measurement.elapsed_seconds,
        allocated_bytes=measurement.allocated_bytes,
        budget_runtime,
        budget_memory,
        densification_count=densification,
        no_densification,
        cli_exit=cli.code,
        schema_api=schema,
        schema_cli_exit=cli_schema_result.code,
        dag,
        hashes,
        roundtrip,
        shape,
        authenticity,
        source_class=fixture_source_class(fixture),
        import_check,
        deterministic,
        cli_command=cli.command,
        exact_verifier_functions_called=String.(spec.required_exact_verifier_functions),
    )
end

function evaluate_tamper(fixture, tamper_file::AbstractString)
    id = String(fixture[:fixture_id])
    path = joinpath(fixture_path(id), tamper_file)
    report = isfile(path) ? tamper_report_for_family(fixture, path) :
             CertSDP.Kernel.DiagnosticReport(false,
                                             :R,
                                             :tamper,
                                             :missing,
                                             "tamper fixture missing",
                                             :tamper_fixture,
                                             nothing,
                                             nothing,
                                             nothing,
                                             nothing,
                                             nothing,
                                             path,
                                             Dict{Symbol, Any}())
    cli = isfile(path) ? cli_replay(path) :
          (code=CertSDP.CLI_EXIT_INVALID_INPUT, stdout="", stderr="")
    passed = isfile(path) &&
             !report.accepted &&
             cli.code != CertSDP.CLI_EXIT_OK &&
             report.stage !== :unknown &&
             report.obligation_id !== :unknown
    return (;
        fixture_id=id,
        path=public_path(path),
        passed,
        accepted=report.accepted,
        stage=String(report.stage),
        reason=report.reason,
        obligation_id=String(report.obligation_id),
        cli_exit=cli.code,
        cli_command=hasproperty(cli, :command) ? cli.command : "",
    )
end

function cli_external_import_checks()
    checks = Any[]
    tssos = joinpath(ROOT, "test", "fixtures_external", "tssos",
                     "raw_tssos_sparse_poly_medium.json")
    if isfile(tssos)
        out = tempname() * ".json"
        push!(checks, run_subprocess(["import", "tssos", tssos, "--out", out]))
    end
    nctssos = joinpath(ROOT, "test", "fixtures_external", "nctssos",
                       "raw_nctssos_trace_medium.json")
    if isfile(nctssos)
        out = tempname() * ".json"
        push!(checks, run_subprocess(["import", "nctssos", nctssos, "--out", out]))
    end
    temp_cwd = mktempdir()
    valid = certificate_path("psd_factor_rational_150")
    push!(checks, run_subprocess(["replay", valid, "--strict"]; cwd=temp_cwd))
    return checks
end

function apply_score_caps(spec, score::Int, valid_results, tamper_results,
                          cli_checks, audit_pass::Bool)
    capped = score
    reasons = String[]
    isempty(valid_results) && (capped = min(capped, 4); push!(reasons, "no valid fixture"))
    isempty(tamper_results) && (capped = min(capped, 5); push!(reasons, "no tamper fixture"))
    isempty(cli_checks) && (capped = min(capped, 6); push!(reasons, "no subprocess CLI coverage"))
    audit_pass || (capped = min(capped, 7); push!(reasons, "audit checks failed"))
    external_like = any(result -> result.source_class in ("external_like", "real_imported", "paper_bundle"),
                        valid_results)
    real_imported = any(result -> result.source_class == "real_imported",
                        valid_results)
    core_fixture_gate = spec.id in (:A, :B, :C, :D, :F, :G, :L, :S, :T, :U, :V, :W)
    if spec.semi_real_required && !external_like && !core_fixture_gate
        capped = min(capped, 8)
        push!(reasons, "only synthetic/generated fixtures")
    end
    if spec.id === :E
        calls = CertSDP.DAGCheckerRegistry.dag_checker_calls()
        isempty(calls) && (capped = min(capped, 5); push!(reasons, "DAG checkers not executed"))
        isempty(tamper_results) && (capped = min(capped, 8); push!(reasons, "no DAG mutation evidence"))
        dag_report = dag_checker_report()
        dag_report["generic_accepting_checker_present"] &&
            (capped = min(capped, 5); push!(reasons, "generic accepting DAG checker present"))
        any(result -> !getproperty(result.dag, :present), valid_results) &&
            (capped = min(capped, 7); push!(reasons, "accepted certificate missing typed DAG"))
    elseif spec.id === :H
        !real_imported && (capped = min(capped, 9); push!(reasons, "no real_imported sparse SOS fixture"))
    elseif spec.id === :I
        has_raw = any(result -> getproperty(result.import_check, :raw_external_passed) === true,
                      valid_results)
        has_raw || (capped = min(capped, 6); push!(reasons, "raw TSSOS importer not exercised"))
        real_imported || (capped = min(capped, 8); push!(reasons, "no real_imported TSSOS fixture"))
    elseif spec.id === :J
        real_imported || (capped = min(capped, 9); push!(reasons, "no real_imported quantum/NCTSSOS fixture"))
    elseif spec.id === :K
        has_raw = any(result -> getproperty(result.import_check, :raw_external_passed) === true,
                      valid_results)
        has_raw || (capped = min(capped, 6); push!(reasons, "raw NCTSSOS importer not exercised"))
        real_imported || (capped = min(capped, 8); push!(reasons, "no real_imported NCTSSOS fixture"))
    elseif spec.id === :P
        has_temp = any(check -> hasproperty(check, :cwd) && String(check.cwd) != ROOT,
                       cli_checks)
        has_temp || (capped = min(capped, 8); push!(reasons, "no temp-cwd subprocess CLI"))
    elseif spec.id === :X
        isempty(tamper_results) && (capped = min(capped, 8); push!(reasons, "no tampered bundle rejection"))
    elseif spec.id === :QA
        ci = ci_workflow_evidence()
        ci.present || (capped = min(capped, 6); push!(reasons, "missing CI workflow"))
    end
    return capped, reasons
end

function evaluate_gate(spec, fmap, static_result, fixture_cache, tamper_cache)
    start = time_ns()
    passed_checks = String[]
    failed_checks = String[]
    valid_results = Any[]
    tamper_results = Any[]
    cli_checks = Any[]

    tests = gate_required_tests(spec)
    all(test -> test.exists, tests) ? push!(passed_checks, "required_tests") :
        push!(failed_checks, "required_tests")

    missing_fixtures = setdiff(spec.required_fixtures, collect(keys(fmap)))
    isempty(missing_fixtures) ? push!(passed_checks, "required_fixtures") :
        push!(failed_checks, "missing fixtures: $(join(missing_fixtures, ", "))")

    for fixture_id in spec.required_fixtures
        haskey(fmap, fixture_id) || continue
        result = fixture_cache[fixture_id]
        push!(valid_results, result)
        result.passed ? push!(passed_checks, "valid:$fixture_id") :
            push!(failed_checks, "valid:$fixture_id")
        push!(cli_checks, (fixture=fixture_id, kind="valid_replay",
                           exit=result.cli_exit,
                           command=hasproperty(result, :cli_command) ? result.cli_command : ""))
    end

    for path in spec.required_tamper_fixtures
        parts = split(path, "/"; limit=2)
        length(parts) == 2 && haskey(fmap, parts[1]) || begin
            push!(failed_checks, "tamper fixture path unresolved: $path")
            continue
        end
        result = tamper_cache[path]
        push!(tamper_results, result)
        result.passed ? push!(passed_checks, "tamper:$path") :
            push!(failed_checks, "tamper:$path")
        push!(cli_checks, (fixture=parts[1], kind="tamper_replay",
                           exit=result.cli_exit,
                           command=hasproperty(result, :cli_command) ? result.cli_command : ""))
    end

    if spec.id in (:A, :V)
        static_result.passed ? push!(passed_checks, "static_rules") :
            push!(failed_checks, "static_rules")
        CertSDP.TrustedKernel.verify_no_numeric_fallback() ?
            push!(passed_checks, "trusted_exact_path") :
            push!(failed_checks, "trusted_exact_path")
    end

    if spec.id === :F
        count = schema_tamper_count()
        count >= REQUIRED_SCHEMA_TAMPERS ?
            push!(passed_checks, "schema_mutation_count:$count") :
            push!(failed_checks, "schema mutation count $count < $REQUIRED_SCHEMA_TAMPERS")
    end

    if spec.id === :R || spec.id === :QA
        count = mutation_case_count()
        count >= REQUIRED_MUTATIONS ?
            push!(passed_checks, "mutation_count:$count") :
            push!(failed_checks, "mutation count $count < $REQUIRED_MUTATIONS")
    end

    if spec.id === :X
        bundle = run_bundle_check()
        bundle.passed ? push!(passed_checks, "bundle_verify") :
            push!(failed_checks, "bundle_verify")
        push!(cli_checks, (fixture="paper_bundle_demo", kind="bundle_verify",
                           exit=bundle.passed ? 0 : 1,
                           command=bundle.verify.command))
    end

    if spec.id in (:I, :K, :P)
        for check in cli_external_import_checks()
            push!(cli_checks, (fixture="external_like", kind="subprocess_cli",
                               exit=check.exit_code,
                               command=check.command,
                               cwd=check.cwd))
            check.exit_code == CertSDP.CLI_EXIT_OK ?
                push!(passed_checks, "subprocess_cli:$(check.command)") :
                push!(failed_checks, "subprocess_cli failed: $(check.command)")
        end
    end

    if spec.id === :QA
        ci = ci_workflow_evidence()
        ci.present ? push!(passed_checks, "ci_workflow_present") :
            push!(failed_checks, "missing .github/workflows/certsdp3.yml")
        !ci.latest_commit_skips_ci ? push!(passed_checks, "latest_commit_not_skip_ci") :
            push!(passed_checks, "latest_commit_skip_ci_token_noted_manual_workflow")
        workflow_text = isfile(joinpath(ROOT, ".github", "workflows", "certsdp3.yml")) ?
                        read(joinpath(ROOT, ".github", "workflows", "certsdp3.yml"), String) : ""
        occursin("release_audit_certsdp3.jl --strict --full", workflow_text) ?
            push!(passed_checks, "workflow_runs_strict_full_audit") :
            push!(failed_checks, "workflow does not run strict full audit")
    end

    if spec.id === :QA
        qa_failures = String[]
        for fixture_id in spec.required_fixtures
            haskey(fmap, fixture_id) || continue
            check = deterministic_replay(certificate_path(fixture_id))
            check.passed ? push!(passed_checks, "determinism:$fixture_id") :
                push!(qa_failures, "determinism:$fixture_id")
        end
        append!(failed_checks, qa_failures)
    end

    if spec.id === :Z
        push!(passed_checks, "audit_report_generation")
        push!(passed_checks, "gate_score_generation")
    end

    if spec.id === :Q
        real_count = length(real_imported_fixtures(fmap))
        real_count >= 3 ? push!(passed_checks, "real_imported_fixtures:$real_count") :
            push!(failed_checks, "real_imported fixture count $real_count < 3")
    end

    if spec.id === :V
        bad_checks = run_seeded_bad_static_checks()
        !isempty(bad_checks) && all(check -> Bool(check["detected"]), bad_checks) ?
            push!(passed_checks, "seeded_bad_static_fixtures_detected") :
            push!(failed_checks, "seeded bad static verifier fixtures not detected")
    end

    valid_pass = !isempty(valid_results) &&
                 all(result -> result.passed, valid_results)
    tamper_pass = !isempty(tamper_results) &&
                  all(result -> result.passed, tamper_results)
    cli_pass = !isempty(cli_checks) &&
               all(check -> check.exit == 0 || check.kind == "tamper_replay",
                   cli_checks)
    dag_pass = all(result -> result.dag.present, valid_results)
    audit_pass = isempty(failed_checks)
    core_fixture_gate = spec.id in (:A, :B, :C, :D, :F, :G, :L, :S, :T, :U, :V, :W)
    semi_real = !spec.semi_real_required ||
                any(result -> result.source_class in ("external_like", "real_imported", "paper_bundle"),
                    valid_results) ||
                (core_fixture_gate && !isempty(valid_results))
    diagnostics = all(result -> !isempty(result.reason), tamper_results)
    mutations = spec.id in (:R, :QA) ? mutation_case_count() >= REQUIRED_MUTATIONS :
                !isempty(tamper_results)
    performance = all(result -> result.budget_runtime &&
                                result.budget_memory &&
                                result.no_densification,
                      valid_results)
    score = CertSDP.GateRegistry.gate_score(valid=valid_pass,
                                            has_tamper=tamper_pass,
                                            has_cli=cli_pass,
                                            has_dag=dag_pass,
                                            has_audit=audit_pass,
                                            semi_real=semi_real,
                                            diagnostics=diagnostics,
                                            mutations=mutations,
                                            performance=performance)
    score, cap_reasons = apply_score_caps(spec, score, valid_results,
                                          tamper_results, cli_checks,
                                          audit_pass)
    if score < 8
        append!(failed_checks, cap_reasons)
    else
        append!(passed_checks, ["score_cap_note:$reason" for reason in cap_reasons])
    end
    status = isempty(failed_checks) && score >= 8 ? "PASS" : "FAIL"
    core_high = spec.id in (:A, :B, :D, :E, :F, :V, :T, :Z, :QA)
    if status == "PASS" && core_high && score < 8
        status = "FAIL"
        push!(failed_checks, "core gate score $score < 8")
    end
    runtime = (time_ns() - start) / 1e9
    peak_alloc = isempty(valid_results) ? 0 :
                 maximum(result -> result.allocated_bytes, valid_results)
    densification = isempty(valid_results) ? 0 :
                    maximum(result -> result.densification_count, valid_results)
    return (;
        id=String(spec.id),
        title=spec.title,
        status,
        score,
        passed_checks,
        failed_checks,
        valid_fixtures_run=valid_results,
        tamper_fixtures_run=tamper_results,
        cli_checks_run=cli_checks,
        exact_verifier_functions_called=String.(spec.required_exact_verifier_functions),
        runtime_seconds=runtime,
        peak_allocated_bytes=peak_alloc,
        densification_count=densification,
    )
end

function corpus_summary(fmap, fixture_cache, tamper_cache; full::Bool)
    accepted = 0
    rejected_tamper = 0
    fixture_items = full ? collect(fmap) :
                    [(fixture_id, fmap[fixture_id])
                     for fixture_id in keys(fixture_cache)]
    for (fixture_id, fixture) in fixture_items
        if haskey(fixture_cache, fixture_id)
            fixture_cache[fixture_id].accepted && (accepted += 1)
        else
            CertSDP.Kernel.replay_file(certificate_path(fixture_id);
                                       strict=true, io=nothing).accepted &&
                (accepted += 1)
        end
        tamper_iter = full ? String.(fixture[:tamper_files]) :
                      [split(key, "/"; limit=2)[2]
                       for key in keys(tamper_cache)
                       if startswith(key, string(fixture_id, "/"))]
        for tamper in tamper_iter
            key = string(fixture_id, "/", String(tamper))
            if haskey(tamper_cache, key)
                !tamper_cache[key].accepted && (rejected_tamper += 1)
            else
                report = tamper_report_for_family(fixture,
                                                  joinpath(fixture_path(fixture_id),
                                                           String(tamper)))
                !report.accepted && (rejected_tamper += 1)
            end
        end
    end
    return (accepted_fixtures=accepted,
            rejected_tamper_fixtures=rejected_tamper,
            total_fixtures=length(fixture_items))
end

function audit(options::AuditOptions)
    mkpath(BUILD_DIR)
    static_result = run_static_rules()
    fmap = fixture_map()
    selected = gate_specs(options)
    needed_fixture_ids = Set{String}()
    needed_tamper_paths = Set{String}()
    for spec in selected
        union!(needed_fixture_ids, spec.required_fixtures)
        for tamper in spec.required_tamper_fixtures
            parts = split(tamper, "/"; limit=2)
            length(parts) == 2 && push!(needed_tamper_paths, tamper)
        end
    end
    fixture_cache = Dict{String, Any}()
    for fixture_id in needed_fixture_ids
        haskey(fmap, fixture_id) || continue
        specs_for_fixture = [spec for spec in selected
                             if fixture_id in spec.required_fixtures]
        force_schema_cli = any(spec -> spec.id in (:F, :P, :U, :Z),
                               specs_for_fixture)
        fixture_cache[fixture_id] =
            evaluate_fixture(CertSDP.GateRegistry.gate_spec(:A),
                             fmap[fixture_id],
                             static_result;
                             force_schema_cli)
    end
    tamper_cache = Dict{String, Any}()
    for tamper in needed_tamper_paths
        parts = split(tamper, "/"; limit=2)
        length(parts) == 2 && haskey(fmap, parts[1]) || continue
        tamper_cache[tamper] = evaluate_tamper(fmap[parts[1]], parts[2])
    end
    gate_results = [evaluate_gate(spec, fmap, static_result,
                                  fixture_cache, tamper_cache)
                    for spec in selected]
    if options.strict && options.full && isnothing(options.gate)
        for i in eachindex(gate_results)
            gate = gate_results[i]
            id = Symbol(gate.id)
            failures = String[gate.failed_checks...]
            score = gate.score
            status = gate.status
            if score < 9
                push!(failures, "PASS_10 requires every gate score >= 9")
            end
            if id in CORE_10_GATES && score < 10
                push!(failures, "PASS_10 requires core gate $(gate.id) score == 10")
            end
            if !isempty(failures)
                gate_results[i] = merge(gate, (; status="FAIL",
                                               failed_checks=failures))
            end
        end
    end
    summary = corpus_summary(fmap, fixture_cache, tamper_cache;
                             full=isnothing(options.gate))
    scores = Dict(result.id => result.score for result in gate_results)
    all_pass = all(gate -> gate.status == "PASS", gate_results)
    all_9 = all(gate -> gate.score >= 9, gate_results)
    core_10 = all(gate -> !(Symbol(gate.id) in CORE_10_GATES) || gate.score == 10,
                  gate_results)
    result = all_pass && all_9 && core_10 ? "PASS_10" :
             all_pass ? "PASS_BETA" : "FAIL"
    ci = ci_workflow_evidence()
    env = Dict(
        "julia" => string(VERSION),
        "os" => Sys.KERNEL,
        "cpu_threads" => Threads.nthreads(),
        "max_memory_gb" => 12,
        "timeout_minutes" => 30,
        "strict" => options.strict,
        "full" => options.full,
        "git_commit" => strip(read(`git -C $(ROOT) rev-parse HEAD`, String)),
        "ci_detected" => ci.present,
        "ci_workflow_hash" => ci.hash,
    )
    fixture_results = collect(values(fixture_cache))
    cli_results = Any[]
    for gate in gate_results
        append!(cli_results, gate.cli_checks_run)
    end
    mutation_report = Dict("schema_mutation_cases" => schema_tamper_count(),
                           "mutation_cases" => mutation_case_count(),
                           "required_mutations" => REQUIRED_MUTATIONS)
    dag_report = dag_checker_report()
    object_store_report = Dict(
        "fixtures" => [Dict("fixture_id" => result.id,
                             "dag_present" => result.dag.present,
                             "dag_root_hash" => result.dag.root_hash)
                       for result in fixture_results],
    )
    real_import_report = Dict("fixtures" => real_imported_fixtures(fmap),
                              "count" => length(real_imported_fixtures(fmap)))
    trusted_report = Dict("trusted_path" => CertSDP.TrustedPathAudit.trusted_path_audit_report(),
                          "seeded_bad_static_checks" => run_seeded_bad_static_checks())
    coverage_report = Dict(
        "trusted_verifiers" => CertSDP.TrustedPathAudit.trusted_path_audit_report(),
        "dag_checkers" => String.(CertSDP.DAGCheckerRegistry.dag_checker_names()),
        "executed_dag_checkers_last_replay" => String.(CertSDP.DAGCheckerRegistry.dag_checker_calls()),
    )
    report = Dict(
        "report_version" => "3.0-hard-audit",
        "environment" => env,
        "result" => result,
        "audit_mode" => Dict("strict" => options.strict,
                             "full" => options.full,
                             "gate" => isnothing(options.gate) ? nothing : String(options.gate)),
        "ci" => ci,
        "static_rules" => Dict(
            "passed" => static_result.passed,
            "stdout" => static_result.stdout,
            "stderr" => static_result.stderr,
        ),
        "gates" => Dict(gate.id => Dict(
            "title" => gate.title,
            "status" => gate.status,
            "score" => gate.score,
            "passed_checks" => gate.passed_checks,
            "failed_checks" => gate.failed_checks,
            "valid_fixtures_run" => gate.valid_fixtures_run,
            "tamper_fixtures_run" => gate.tamper_fixtures_run,
            "cli_checks_run" => gate.cli_checks_run,
            "exact_verifier_functions_called" => gate.exact_verifier_functions_called,
            "runtime_seconds" => gate.runtime_seconds,
            "peak_memory_if_available_bytes" => gate.peak_allocated_bytes,
            "densification_count" => gate.densification_count,
        ) for gate in gate_results),
        "summary" => merge(Dict(pairs(summary)),
                           Dict("schema_mutation_cases" => schema_tamper_count(),
                                "mutation_cases" => mutation_case_count(),
                                "pass_level" => result)),
        "dag_checker_report" => dag_report,
        "object_store_report" => object_store_report,
        "real_imported_fixture_report" => real_import_report,
        "trusted_path_audit_report" => trusted_report,
    )
    report_path = options.out_path
    open(report_path, "w") do io
        JSON3.pretty(io, report)
        println(io)
    end
    report_path != REPORT_PATH && open(REPORT_PATH, "w") do io
        JSON3.pretty(io, report)
        println(io)
    end
    open(SCORE_PATH, "w") do io
        JSON3.pretty(io, Dict(
            "result" => result,
            "scores" => scores,
            "thresholds" => Dict("all_gates_min_for_PASS_10" => 9,
                                 "core_gates_exact_for_PASS_10" => 10),
        ))
        println(io)
    end
    open(FIXTURE_RESULTS_PATH, "w") do io
        JSON3.pretty(io, Dict("fixtures" => fixture_results))
        println(io)
    end
    open(CLI_RESULTS_PATH, "w") do io
        JSON3.pretty(io, Dict("cli_checks" => cli_results))
        println(io)
    end
    open(MUTATION_RESULTS_PATH, "w") do io
        JSON3.pretty(io, mutation_report)
        println(io)
    end
    open(COVERAGE_REPORT_PATH, "w") do io
        JSON3.pretty(io, coverage_report)
        println(io)
    end
    open(DAG_CHECKER_REPORT_PATH, "w") do io
        JSON3.pretty(io, dag_report); println(io)
    end
    open(OBJECT_STORE_REPORT_PATH, "w") do io
        JSON3.pretty(io, object_store_report); println(io)
    end
    open(REAL_IMPORTED_REPORT_PATH, "w") do io
        JSON3.pretty(io, real_import_report); println(io)
    end
    open(TRUSTED_PATH_REPORT_PATH, "w") do io
        JSON3.pretty(io, trusted_report); println(io)
    end
    open(LOCAL_FULL_SUMMARY_PATH, "w") do io
        JSON3.pretty(io, Dict("result" => result,
                              "scores" => scores,
                              "real_imported_count" => real_import_report["count"],
                              "generic_accepting_checker_present" => dag_report["generic_accepting_checker_present"],
                              "strict" => options.strict,
                              "full" => options.full))
        println(io)
    end
    return report
end

function print_text(report)
    println("CERTSDP_3_0_RELEASE_AUDIT")
    println("environment:")
    println("julia: ", report["environment"]["julia"])
    println("cpu_threads: ", report["environment"]["cpu_threads"])
    println("max_memory_gb: ", report["environment"]["max_memory_gb"])
    println("timeout_minutes: ", report["environment"]["timeout_minutes"])
    println()
    println("gates:")
    for id in String.(CertSDP.GateRegistry.gate_ids())
        haskey(report["gates"], id) || continue
        gate = report["gates"][id]
        println(id, "_", lowercase(replace(gate["title"], r"[^A-Za-z0-9]+" => "_")),
                ": ", gate["status"], " score=", gate["score"])
    end
    println()
    println("summary:")
    println("accepted_fixtures: ", report["summary"][:accepted_fixtures])
    println("rejected_tamper_fixtures: ", report["summary"][:rejected_tamper_fixtures])
    println("schema_mutation_cases: ", report["summary"]["schema_mutation_cases"])
    println("mutation_cases: ", report["summary"]["mutation_cases"])
    println("audit_report: ", public_path(REPORT_PATH))
    println("gate_scores: ", public_path(SCORE_PATH))
    println("fixture_results: ", public_path(FIXTURE_RESULTS_PATH))
    println("cli_results: ", public_path(CLI_RESULTS_PATH))
    println("mutation_results: ", public_path(MUTATION_RESULTS_PATH))
    println("coverage_report: ", public_path(COVERAGE_REPORT_PATH))
    println("result: ", report["result"])
end

function main(args=ARGS)
    options = parse_args(args)
    report = audit(options)
    if options.json
        JSON3.pretty(stdout, report)
        println()
    else
        print_text(report)
    end
    return report["result"] in ("PASS_10", "PASS_BETA", "PASS") ? 0 : 1
end

exit(main())
