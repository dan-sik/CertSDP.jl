const CLI_EXIT_OK = 0
const CLI_EXIT_VERIFICATION_FAILED = 1
const CLI_EXIT_INVALID_INPUT = 2
const CLI_EXIT_BACKEND_UNAVAILABLE = 3
const CLI_EXIT_TIMEOUT = 4
const CLI_EXIT_NOT_CERTIFIED = 5
const CLI_EXIT_REJECTED = CLI_EXIT_VERIFICATION_FAILED
const CLI_EXIT_USAGE = CLI_EXIT_INVALID_INPUT

"""
    main(args=ARGS; io=stdout, err=stderr) -> Int

Command-line entrypoint for `certsdp`.
"""
function main(args=ARGS; io::IO=stdout, err::IO=stderr)
    isempty(args) && return _cli_usage(err)

    Apps.certsdp3_cli_handles(String.(args)) &&
        return Apps.certsdp3_cli_main(String.(args); io, err)

    command = String(args[1])
    rest = String.(args[2:end])

    if command in ("help", "--help", "-h")
        _print_cli_usage(io)
        return CLI_EXIT_OK
    elseif command in ("version", "--version")
        if "--json" in rest
            JSON3.pretty(io, Dict("name" => "CertSDP",
                                  "certsdp3" => true,
                                  "schema_version" => Kernel.CERTSDP3_SCHEMA_VERSION,
                                  "version" => string(package_version())))
            println(io)
        else
            println(io, "CertSDP.jl ", package_version())
        end
        return CLI_EXIT_OK
    elseif command == "verify"
        return _cli_verify(rest; io, err)
    elseif command == "inspect"
        return _cli_inspect(rest; io, err)
    elseif command == "doctor"
        return _cli_doctor(rest; io, err)
    elseif command == "explain"
        return _cli_explain(rest; io, err)
    elseif command == "minimize"
        return _cli_minimize(rest; io, err)
    elseif command == "bundle"
        return _cli_bundle(rest; io, err)
    elseif command == "replay"
        return _cli_replay(rest; io, err)
    elseif command == "schema"
        return _cli_schema(rest; io, err)
    elseif command == "import"
        return _cli_import(rest; io, err)
    elseif command == "migrate"
        return _cli_schema(vcat(["migrate"], rest); io, err)
    elseif command == "export-sos"
        return _cli_export_sos(rest; io, err)
    elseif command == "convert-sostools"
        return _cli_convert_sostools(rest; io, err)
    elseif command == "certify"
        return _cli_certify(rest; io, err)
    elseif command == "certify-sos"
        return _cli_certify_sos(rest; io, err)
    elseif command == "certify-auto-sos"
        return _cli_certify_auto_sos(rest; io, err)
    elseif command == "solve"
        return _cli_solve(rest; io, err)
    elseif command == "solve-certify"
        return _cli_solve_certify(rest; io, err)
    elseif command == "diagnose"
        return _cli_diagnose(rest; io, err)
    elseif command == "diagnose-approx"
        return _cli_diagnose_approx(rest; io, err)
    elseif command == "benchmark"
        return _cli_benchmark(rest; io, err)
    end

    println(err, "[FAIL] unknown command `$command`")
    return _cli_usage(err)
end

function _cli_certify_auto_sos(args; io::IO, err::IO)
    parsed = try
        _parse_certify_auto_sos_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_certify_auto_sos_usage(err)
        return CLI_EXIT_USAGE
    end

    problem = try
        parse_sos_gram_json(read(parsed.problem_path, String))
    catch parse_error
        println(err,
                "[FAIL] could not read SOS Gram problem `$(parsed.problem_path)`: $(sprint(showerror, parse_error))")
        return CLI_EXIT_USAGE
    end

    gram_candidate = try
        _read_sos_gram_candidate_value(problem, parsed.solution_path)
    catch parse_error
        println(err,
                "[FAIL] could not read SOS Gram candidate `$(parsed.solution_path)`: $(sprint(showerror, parse_error))")
        return CLI_EXIT_USAGE
    end

    result = certify_auto_sos(problem,
                              gram_candidate;
                              strategies=parsed.strategies,
                              tolerance=parsed.tolerance,
                              max_denominator=parsed.max_denominator)
    if result isa FailureResult
        _print_certification_failure(result.failure, err)
        return _cli_exit_for_failure(result.failure)
    end
    cert = certificate(result)

    accepted = verify(cert; io)
    if !accepted
        println(err,
                "[FAIL] internal verifier rejected the exactified SOS Gram certificate")
        return CLI_EXIT_REJECTED
    end

    try
        write_certificate(parsed.out_path, cert)
    catch write_error
        println(err,
                "[FAIL] could not write certificate `$(parsed.out_path)`: $(sprint(showerror, write_error))")
        return CLI_EXIT_USAGE
    end

    report = result.artifacts[:exactification_report]
    println(io, "[OK] exactification strategy: ", report.selected_strategy)
    println(io, "[OK] wrote SOS Gram certificate: $(parsed.out_path)")
    return CLI_EXIT_OK
end

function _cli_convert_sostools(args; io::IO, err::IO)
    parsed = try
        _parse_convert_sostools_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_convert_sostools_usage(err)
        return CLI_EXIT_USAGE
    end

    result = try
        convert_sostools_lite_json(parsed.input_path;
                                   problem_out=parsed.problem_out,
                                   solution_out=parsed.solution_out,
                                   cert_out=parsed.cert_out)
    catch convert_error
        println(err,
                "[FAIL] could not convert SOSTOOLS-lite JSON: $(sprint(showerror, convert_error))")
        return CLI_EXIT_USAGE
    end

    !isnothing(result.problem_out) &&
        println(io, "[OK] wrote SOS Gram problem: ", result.problem_out)
    !isnothing(result.solution_out) &&
        println(io, "[OK] wrote SOS Gram solution: ", result.solution_out)
    !isnothing(result.cert_out) &&
        println(io, "[OK] wrote exact SOS certificate: ", result.cert_out)
    return CLI_EXIT_OK
end

function _cli_benchmark(args; io::IO, err::IO)
    parsed = try
        _parse_benchmark_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_benchmark_usage(err)
        return CLI_EXIT_USAGE
    end

    result = try
        run_benchmarks(parsed.root;
                       out=parsed.out_path,
                       subset=parsed.subset,
                       generated_dir=parsed.generated_dir,
                       profile=parsed.profile,
                       budget=parsed.budget)
    catch run_error
        println(err, "[FAIL] benchmark runner error: $(sprint(showerror, run_error))")
        return CLI_EXIT_USAGE
    end

    println(io, "[OK] wrote benchmark report: ", result.report_path)
    println(io, "[INFO] subset: ", result.subset)
    println(io, "[INFO] validation budget: ", result.validation_budget)
    println(io, "[INFO] instances: ", length(result.rows))
    if result.passed
        println(io, "[OK] benchmark expected statuses matched")
        return CLI_EXIT_OK
    end

    println(err, "[FAIL] benchmark expected status mismatch")
    for mismatch in result.mismatches
        println(err, "[FAIL] ", mismatch)
    end
    return CLI_EXIT_REJECTED
end

function _cli_doctor(args; io::IO, err::IO)
    parsed = try
        _parse_doctor_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_doctor_usage(err)
        return CLI_EXIT_USAGE
    end

    report = doctor_report(; validation_root=parsed.validation_root)
    print_doctor_report(report; io)
    return report.ready ? CLI_EXIT_OK : CLI_EXIT_NOT_CERTIFIED
end

function _cli_explain(args; io::IO, err::IO)
    parsed = try
        _parse_explain_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_explain_usage(err)
        return CLI_EXIT_USAGE
    end

    cert = try
        read_certificate(parsed.failure_path)
    catch
        nothing
    end
    if cert isa ExactCertificateArtifact
        _print_exact_artifact_explanation(cert; io)
        return CLI_EXIT_OK
    end

    failure = try
        read_failure_report(parsed.failure_path)
    catch parse_error
        println(err,
                "[FAIL] could not read failure report `$(parsed.failure_path)`: $(sprint(showerror, parse_error))")
        return CLI_EXIT_USAGE
    end
    print_failure_explanation(failure; io, max_lines=parsed.max_lines)
    return _cli_exit_for_failure(failure)
end

function _print_exact_artifact_explanation(cert::ExactCertificateArtifact; io::IO)
    result = verify(cert; mode=:strict)
    println(io, "CertSDP 2.0 artifact")
    println(io, "- type: ", cert.type)
    println(io, "- strict_status: ", result.status)
    println(io, "- field: ", cert.field, " (degree ", field_degree(cert), ")")
    println(io, "- blocks: ", length(cert.blocks), ", total_dim: ", total_block_dim(cert))
    println(io, "- structure: ",
            join([String(key)
                  for key in keys(cert.structure) if getfield(cert.structure, key)],
                 ", "))
    if haskey(cert.certificate, :exact_sparse_identity)
        identity_result = CertSDP._verify_exact_sparse_identity(cert)
        println(io, "- exact_sparse_identity: ", identity_result.status)
    end
    if result.status !== :valid
        println(io, "- failure_stage: ", result.failure_stage)
        println(io, "- message: ", result.message)
    end
    if !isempty(cert.reconstruction_log)
        println(io, "- reconstruction_log:")
        for entry in cert.reconstruction_log
            println(io, "  * ", entry)
        end
    end
    return nothing
end

function _cli_bundle(args; io::IO, err::IO)
    if !isempty(args) && args[1] == "verify"
        length(args) == 2 || begin
            println(err, "[FAIL] bundle verify expects a bundle directory")
            return CLI_EXIT_USAGE
        end
        result = _certsdp3_verify_paper_bundle(args[2])
        if result.passed
            println(io, "[OK] bundle verified: ", args[2])
            return CLI_EXIT_OK
        end
        println(err, "[FAIL] bundle rejected: ", result.reason)
        return CLI_EXIT_REJECTED
    end

    parsed = try
        _parse_bundle_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_bundle_usage(err)
        return CLI_EXIT_USAGE
    end

    output = try
        if _bundle_out_is_directory(parsed.out_path)
            _certsdp3_paper_bundle(parsed.cert_path, parsed.out_path;
                                   problem_path=parsed.problem_path)
        else
            bundle_certificate(parsed.cert_path;
                               out_path=parsed.out_path,
                               problem_path=parsed.problem_path,
                               approx_path=parsed.approx_path,
                               report_path=parsed.report_path,
                               logs_path=parsed.logs_path,
                               redact=parsed.redact)
        end
    catch bundle_error
        println(err,
                "[FAIL] could not create artifact bundle: $(sprint(showerror, bundle_error))")
        return CLI_EXIT_USAGE
    end
    println(io, "[OK] wrote artifact bundle: ", output)
    println(io, "[INFO] replay with: certsdp replay ", output)
    return CLI_EXIT_OK
end

function _bundle_out_is_directory(out_path::AbstractString)
    return isdir(out_path) ||
           endswith(out_path, "/") ||
           endswith(out_path, Base.Filesystem.path_separator)
end

function _certsdp3_paper_bundle(cert_path::AbstractString,
                                out_dir::AbstractString;
                                problem_path=nothing)
    report = Kernel.replay_file(cert_path; strict=true)
    report.accepted ||
        throw(ArgumentError("certificate did not strict-replay for paper bundle: $(report.reason)"))
    mkpath(out_dir)
    schema_dir = joinpath(out_dir, "schema")
    mkpath(schema_dir)
    cert_text = read(cert_path, String)
    write(joinpath(out_dir, "certificate.json"), cert_text)
    if isnothing(problem_path)
        write(joinpath(out_dir, "problem.json"),
              JSON3.write(Dict("certsdp_problem_version" => Kernel.CERTSDP3_SCHEMA_VERSION,
                               "source" => "embedded_or_not_supplied")))
    else
        write(joinpath(out_dir, "problem.json"), read(problem_path, String))
    end
    cert = Kernel.parse_certificate_json_v3(cert_text; strict=true)
    write(joinpath(out_dir, "proof_dag.json"),
          JSON3.write(Kernel.proof_dag_json(cert)))
    write(joinpath(out_dir, "replay_report.json"),
          JSON3.write(Kernel.diagnostic_report_json(report)))
    write(joinpath(out_dir, "replay_report.html"),
          Kernel.diagnostic_report_html(report))
    for schema_name in ("certsdp_certificate_v3.schema.json",
                        "certsdp_problem_v3.schema.json",
                        "certsdp_report_v3.schema.json")
        source = joinpath(dirname(@__DIR__), "..", "schemas", schema_name)
        isfile(source) && cp(source, joinpath(schema_dir, schema_name);
                             force=true)
    end
    project_root = normpath(joinpath(@__DIR__, "..", ".."))
    rel_out = relpath(abspath(out_dir), project_root)
    project_hint = startswith(rel_out, "..") ? project_root : ""
    verify_script = """
#!/usr/bin/env bash
set -euo pipefail
ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PROJECT_HINT="$project_hint"
PROJECT="\$ROOT"
while [ "\$PROJECT" != "/" ] && [ ! -f "\$PROJECT/Project.toml" ]; do
  PROJECT="\$(dirname "\$PROJECT")"
done
if [ ! -f "\$PROJECT/Project.toml" ]; then
  if [ -n "\$PROJECT_HINT" ] && [ -f "\$PROJECT_HINT/Project.toml" ]; then
    PROJECT="\$PROJECT_HINT"
  elif [ -f "\$PWD/Project.toml" ]; then
    PROJECT="\$PWD"
  else
    echo "CertSDP Project.toml not found above bundle or current directory" >&2
    exit 3
  fi
fi
julia --project="\$PROJECT" --startup-file=no -e 'using CertSDP; exit(CertSDP.Kernel.replay_file(joinpath(ARGS[1], "certificate.json"); strict=true).accepted ? 0 : 1)' "\$ROOT"
"""
    verify_path = joinpath(out_dir, "VERIFY.sh")
    write(verify_path, verify_script)
    chmod(verify_path, 0o755)
    write(joinpath(out_dir, "CITATION.cff"),
          "cff-version: 1.2.0\nmessage: Cite the CertSDP proof-carrying certificate artifact.\ntitle: CertSDP 3.0 Certificate Bundle\n")
    write(joinpath(out_dir, "theorem_statement.txt"),
          "claim_type: $(cert.certificate_type)\ncertificate_id: $(cert.certificate_id)\nproblem_hash: $(cert.problem_hash)\n")
    write(joinpath(out_dir, "README.md"),
          "# CertSDP 3.0 Bundle\n\nRun `bash VERIFY.sh` or `certsdp bundle verify .` offline to replay this certificate.\n")
    schema_hash = isfile(joinpath(schema_dir, "certsdp_certificate_v3.schema.json")) ?
                  "sha256:" * bytes2hex(sha256(read(joinpath(schema_dir, "certsdp_certificate_v3.schema.json")))) :
                  "sha256:" * repeat("0", 64)
    manifest = Dict(
        "certsdp_bundle_version" => Kernel.CERTSDP3_SCHEMA_VERSION,
        "certificate_hash" => cert.certificate_id,
        "problem_hash" => cert.problem_hash,
        "schema_hash" => schema_hash,
        "dag_root_hash" => cert.dag.root_hash,
        "verify_script" => "VERIFY.sh",
    )
    write(joinpath(out_dir, "CERTSDP_BUNDLE.json"), JSON3.write(manifest))
    write(joinpath(out_dir, "schema.json"),
          JSON3.write(Dict("schema_hash" => schema_hash,
                           "certificate_schema" => "schema/certsdp_certificate_v3.schema.json")))
    audit_expected = Dict(
        "accepted" => true,
        "certificate_hash" => cert.certificate_id,
        "problem_hash" => cert.problem_hash,
        "dag_root_hash" => cert.dag.root_hash,
    )
    write(joinpath(out_dir, "audit_expected.json"), JSON3.write(audit_expected))
    hashes = String[]
    for file in ["CERTSDP_BUNDLE.json", "certificate.json", "problem.json",
                 "schema.json", "audit_expected.json", "README.md",
                 "proof_dag.json",
                 "replay_report.json", "replay_report.html",
                 "VERIFY.sh", "CITATION.cff", "theorem_statement.txt"]
        path = joinpath(out_dir, file)
        isfile(path) || continue
        push!(hashes, file * " " * bytes2hex(sha256(read(path))))
    end
    write(joinpath(out_dir, "hashes.txt"), join(hashes, "\n") * "\n")
    return out_dir
end

function _certsdp3_verify_paper_bundle(dir::AbstractString)
    required = ["CERTSDP_BUNDLE.json", "certificate.json", "problem.json",
                "schema.json", "VERIFY.sh", "audit_expected.json",
                "proof_dag.json", "replay_report.json"]
    for file in required
        isfile(joinpath(dir, file)) ||
            return (passed=false, reason="missing bundle file $file")
    end
    manifest = JSON3.read(read(joinpath(dir, "CERTSDP_BUNDLE.json"), String))
    expected = JSON3.read(read(joinpath(dir, "audit_expected.json"), String))
    cert_path = joinpath(dir, "certificate.json")
    cert = try
        Kernel.parse_certificate_json_v3(read(cert_path, String); strict=true)
    catch err
        return (passed=false, reason="certificate parse failed: $(sprint(showerror, err))")
    end
    report = Kernel.replay_file(cert_path; strict=true, io=nothing)
    report.accepted ||
        return (passed=false, reason="certificate replay rejected: $(report.reason)")
    String(manifest[:certificate_hash]) == cert.certificate_id ||
        return (passed=false, reason="manifest certificate_hash mismatch")
    String(manifest[:problem_hash]) == cert.problem_hash ||
        return (passed=false, reason="manifest problem_hash mismatch")
    String(manifest[:dag_root_hash]) == cert.dag.root_hash ||
        return (passed=false, reason="manifest dag_root_hash mismatch")
    String(expected[:certificate_hash]) == cert.certificate_id ||
        return (passed=false, reason="audit_expected certificate_hash mismatch")
    String(expected[:dag_root_hash]) == cert.dag.root_hash ||
        return (passed=false, reason="audit_expected dag_root_hash mismatch")
    schema_path = joinpath(dir, "schema", "certsdp_certificate_v3.schema.json")
    if isfile(schema_path)
        schema_hash = "sha256:" * bytes2hex(sha256(read(schema_path)))
        String(manifest[:schema_hash]) == schema_hash ||
            return (passed=false, reason="schema_hash mismatch")
    end
    proof_dag = JSON3.read(read(joinpath(dir, "proof_dag.json"), String))
    String(proof_dag[:root_hash]) == cert.dag.root_hash ||
        return (passed=false, reason="proof_dag root hash mismatch")
    return (passed=true, reason="accepted")
end

function _cli_replay(args; io::IO, err::IO)
    if any(arg -> arg == "--strict" || arg == "--explain" || arg == "--json", args)
        cert_path = nothing
        strict = false
        explain = false
        json = false
        i = 1
        while i <= length(args)
            arg = args[i]
            if arg == "--strict"
                strict = true
            elseif arg == "--explain"
                explain = true
            elseif arg == "--json"
                json = true
            elseif startswith(arg, "--")
                println(err, "[FAIL] unknown replay option `$arg`")
                return CLI_EXIT_USAGE
            elseif isnothing(cert_path)
                cert_path = arg
            else
                println(err, "[FAIL] unexpected positional argument `$arg`")
                return CLI_EXIT_USAGE
            end
            i += 1
        end
        isnothing(cert_path) && begin
            println(err, "[FAIL] replay expects a certificate path")
            return CLI_EXIT_USAGE
        end
        report = Kernel.replay_file(cert_path; strict=strict || explain || json,
                                    io=json ? nothing : io)
        if json
            JSON3.pretty(io, Kernel.diagnostic_report_json(report))
            println(io)
        elseif explain
            print(io, Kernel.diagnostic_report_text(report))
        end
        return report.accepted ? CLI_EXIT_OK : CLI_EXIT_REJECTED
    end

    if any(arg -> arg == "--no-network" || arg == "--no-solver", args)
        filtered = [arg for arg in args if arg != "--no-network" && arg != "--no-solver"]
        if length(filtered) == 1
            cert = try
                read_certificate(filtered[1])
            catch parse_error
                println(err,
                        "[FAIL] could not read replay artifact `$(filtered[1])`: $(sprint(showerror, parse_error))")
                return CLI_EXIT_USAGE
            end
            accepted = if cert isa ExactCertificateArtifact
                replay(cert; mode=:strict).status === :valid
            else
                verify(cert; strict=true)
            end
            if accepted
                println(io, "[OK] replay strict verification accepted")
                return CLI_EXIT_OK
            end
            println(err, "[FAIL] replay strict verification rejected")
            return CLI_EXIT_REJECTED
        end
    end

    parsed = try
        _parse_replay_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_replay_usage(err)
        return CLI_EXIT_USAGE
    end

    result = try
        replay_bundle(parsed.bundle_path; io, extract_dir=parsed.extract_dir)
    catch replay_error
        println(err,
                "[FAIL] could not replay artifact bundle: $(sprint(showerror, replay_error))")
        return CLI_EXIT_USAGE
    end
    println(io, "[INFO] bundle entries: ", result.entry_count)
    if !isnothing(result.extracted_to)
        println(io, "[INFO] extracted bundle to: ", result.extracted_to)
    end
    if result.accepted
        println(io, "[OK] replay strict verification accepted")
        return CLI_EXIT_OK
    end
    println(err, "[FAIL] replay strict verification rejected")
    return CLI_EXIT_REJECTED
end

function _cli_import(args; io::IO, err::IO)
    isempty(args) && begin
        _print_import_usage(err)
        return CLI_EXIT_USAGE
    end
    kind = args[1]
    rest = args[2:end]
    if kind == "tssos"
        artifact_path = nothing
        out_path = nothing
        i = 1
        while i <= length(rest)
            arg = rest[i]
            if arg == "--out"
                i == length(rest) && begin
                    println(err, "[FAIL] import tssos --out expects a path")
                    return CLI_EXIT_USAGE
                end
                i += 1
                out_path = rest[i]
            elseif startswith(arg, "--")
                println(err, "[FAIL] unknown import tssos option `$arg`")
                return CLI_EXIT_USAGE
            elseif isnothing(artifact_path)
                artifact_path = arg
            else
                println(err, "[FAIL] unexpected import tssos argument `$arg`")
                return CLI_EXIT_USAGE
            end
            i += 1
        end
        (isnothing(artifact_path) || isnothing(out_path)) && begin
            _print_import_usage(err)
            return CLI_EXIT_USAGE
        end
        result = certify_tssos_artifact(artifact_path)
        result isa CertifiedResult || begin
            println(err, "[FAIL] TSSOS artifact rejected: ", result.failure.message)
            return CLI_EXIT_REJECTED
        end
        candidate = import_tssos_artifact(artifact_path)
        write_tssos_candidate(candidate, out_path)
        println(io, "[OK] imported TSSOS artifact candidate: ", out_path)
        return CLI_EXIT_OK
    elseif kind == "nctssos"
        artifact_path = nothing
        out_path = nothing
        i = 1
        while i <= length(rest)
            arg = rest[i]
            if arg == "--out"
                i == length(rest) && begin
                    println(err, "[FAIL] import nctssos --out expects a path")
                    return CLI_EXIT_USAGE
                end
                i += 1
                out_path = rest[i]
            elseif startswith(arg, "--")
                println(err, "[FAIL] unknown import nctssos option `$arg`")
                return CLI_EXIT_USAGE
            elseif isnothing(artifact_path)
                artifact_path = arg
            else
                println(err, "[FAIL] unexpected import nctssos argument `$arg`")
                return CLI_EXIT_USAGE
            end
            i += 1
        end
        (isnothing(artifact_path) || isnothing(out_path)) && begin
            _print_import_usage(err)
            return CLI_EXIT_USAGE
        end
        result = certify_nctssos_artifact(artifact_path)
        result isa CertifiedResult || begin
            println(err, "[FAIL] NCTSSOS artifact rejected: ", result.failure.message)
            return CLI_EXIT_REJECTED
        end
        candidate = import_nctssos_artifact(artifact_path)
        write_nctssos_candidate(candidate, out_path)
        println(io, "[OK] imported NCTSSOS artifact candidate: ", out_path)
        return CLI_EXIT_OK
    elseif kind == "sdpa"
        input_path = nothing
        out_path = nothing
        i = 1
        while i <= length(rest)
            arg = rest[i]
            if arg == "--out"
                i == length(rest) && begin
                    println(err, "[FAIL] import sdpa --out expects a path")
                    return CLI_EXIT_USAGE
                end
                i += 1
                out_path = rest[i]
            elseif startswith(arg, "--")
                println(err, "[FAIL] unknown import sdpa option `$arg`")
                return CLI_EXIT_USAGE
            elseif isnothing(input_path)
                input_path = arg
            else
                println(err, "[FAIL] unexpected import sdpa argument `$arg`")
                return CLI_EXIT_USAGE
            end
            i += 1
        end
        (isnothing(input_path) || isnothing(out_path)) && begin
            _print_import_usage(err)
            return CLI_EXIT_USAGE
        end
        problem = try
            read_sdpa_sparse(input_path)
        catch parse_error
            println(err, "[FAIL] SDPA sparse import rejected: ",
                    sprint(showerror, parse_error))
            return CLI_EXIT_USAGE
        end
        payload = (;
            certsdp_problem_version=Kernel.CERTSDP3_SCHEMA_VERSION,
            type="sparse_lmi",
            problem=Kernel.sparse_affine_lmi_json(problem),
        )
        open(out_path, "w") do out
            JSON3.pretty(out, payload)
            println(out)
        end
        println(io, "[OK] imported SDPA sparse problem: ", out_path)
        return CLI_EXIT_OK
    end
    println(err, "[FAIL] unknown import kind `$kind`")
    _print_import_usage(err)
    return CLI_EXIT_USAGE
end

function _cli_minimize(args; io::IO, err::IO)
    input_path = nothing
    out_path = nothing
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--out"
            i += 1
            i <= length(args) || begin
                println(err, "[FAIL] --out requires a path")
                return CLI_EXIT_USAGE
            end
            out_path = args[i]
        elseif isnothing(input_path)
            input_path = arg
        else
            println(err, "[FAIL] minimize received unexpected argument `$arg`")
            return CLI_EXIT_USAGE
        end
        i += 1
    end
    isnothing(input_path) && begin
        println(err, "[FAIL] minimize expects an artifact path")
        return CLI_EXIT_USAGE
    end
    isnothing(out_path) && (out_path = input_path * ".min.json")

    cert = try
        read_certificate(input_path)
    catch parse_error
        println(err,
                "[FAIL] could not read certificate `$(input_path)`: $(sprint(showerror, parse_error))")
        return CLI_EXIT_USAGE
    end
    cert isa ExactCertificateArtifact || begin
                                         println(err, "[FAIL] minimize currently expects a CertSDP 2.0 artifact")
                                         return CLI_EXIT_USAGE
                                         end
    minimized = minimize(cert)
    verify(minimized; mode=:strict).status === :valid || begin
                                                         println(err, "[FAIL] minimized artifact failed strict verification")
                                                         return CLI_EXIT_REJECTED
                                                         end
    try
        write_certificate(out_path, minimized)
    catch write_error
        println(err,
                "[FAIL] could not write minimized artifact `$(out_path)`: $(sprint(showerror, write_error))")
        return CLI_EXIT_USAGE
    end
    println(io, "[OK] wrote minimized artifact: ", out_path)
    return CLI_EXIT_OK
end

function _cli_schema(args; io::IO, err::IO)
    parsed = try
        _parse_schema_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_schema_usage(err)
        return CLI_EXIT_USAGE
    end

    json_text = try
        read(parsed.path, String)
    catch read_error
        println(err,
                "[FAIL] could not read schema input `$(parsed.path)`: $(sprint(showerror, read_error))")
        return CLI_EXIT_USAGE
    end

    if parsed.action === :validate
        kind = try
            _validate_schema_text(json_text, parsed.kind)
        catch validation_error
            println(err, "[FAIL] schema validation failed: ",
                    sprint(showerror, validation_error))
            return CLI_EXIT_USAGE
        end
        println(io, "[OK] schema valid: ", kind)
        return CLI_EXIT_OK
    end

    kind, migrated = try
        _migrate_schema_text(json_text, parsed.kind)
    catch migration_error
        println(err, "[FAIL] schema migration failed: ",
                sprint(showerror, migration_error))
        return CLI_EXIT_USAGE
    end

    try
        write(parsed.out_path, migrated)
    catch write_error
        println(err,
                "[FAIL] could not write migrated schema `$(parsed.out_path)`: $(sprint(showerror, write_error))")
        return CLI_EXIT_USAGE
    end
    println(io, "[OK] wrote migrated ", kind, " schema: ", parsed.out_path)
    return CLI_EXIT_OK
end

function _cli_export_sos(args; io::IO, err::IO)
    parsed = try
        _parse_export_sos_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_export_sos_usage(err)
        return CLI_EXIT_USAGE
    end

    output = try
        if parsed.format === :json
            export_sos_decomposition(parsed.cert_path)
        elseif parsed.format === :text
            cert = read_certificate(parsed.cert_path)
            sos_decomposition_text(cert)
        elseif parsed.format === :latex
            sos_decomposition_latex(parsed.cert_path)
        elseif parsed.format === :sage
            sos_decomposition_sage(parsed.cert_path)
        elseif parsed.format === :julia
            sos_decomposition_julia(parsed.cert_path)
        else
            throw(ArgumentError("unsupported SOS export format $(parsed.format)"))
        end
    catch export_error
        println(err,
                "[FAIL] could not export SOS decomposition: $(sprint(showerror, export_error))")
        return CLI_EXIT_USAGE
    end

    try
        open(parsed.out_path, "w") do out
            if parsed.format === :json
                JSON3.pretty(out, output)
                println(out)
            else
                println(out, output)
            end
        end
    catch write_error
        println(err,
                "[FAIL] could not write SOS export `$(parsed.out_path)`: $(sprint(showerror, write_error))")
        return CLI_EXIT_USAGE
    end

    println(io, "[OK] wrote SOS ", parsed.format, " export: ", parsed.out_path)
    return CLI_EXIT_OK
end

function _cli_solve(args; io::IO, err::IO)
    parsed = try
        _parse_solve_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_solve_usage(err)
        return CLI_EXIT_USAGE
    end

    problem = try
        read_problem(parsed.problem_path)
    catch parse_error
        println(err,
                "[FAIL] could not read problem `$(parsed.problem_path)`: $(sprint(showerror, parse_error))")
        return CLI_EXIT_USAGE
    end

    problem isa BlockLMIProblem && begin
                                   problem = try
                                             single_lmi_problem(problem)
                                             catch parse_error
                                             println(err,
                                                     "[FAIL] solve currently expects a single PSD block: $(sprint(showerror, parse_error))")
                                             return CLI_EXIT_USAGE
                                             end
                                   end

    result = try
        solve_approximately(problem;
                            solvers=parsed.solvers,
                            random_objective_trials=parsed.random_objective_trials,
                            trace_objective=parsed.trace_objective,
                            solver_attempts=parsed.solver_attempts,
                            solver_retry_policy=parsed.solver_retry_policy,
                            precision=parsed.precision_bits,
                            random_seed=parsed.random_seed,
                            require_stable_rank=parsed.require_stable_rank,
                            clarabel_max_iter=parsed.clarabel_max_iter,
                            relative_tolerance=parsed.rank_relative_tolerance,
                            gap_threshold=parsed.rank_gap_threshold)
    catch solve_error
        println(err,
                "[FAIL] numerical solve error: $(sprint(showerror, solve_error))")
        return CLI_EXIT_INVALID_INPUT
    end

    if result isa CertificationFailure
        _print_certification_failure(result, err)
        return _cli_exit_for_failure(result)
    end

    try
        write_approx_solution_json(parsed.out_path, result)
    catch write_error
        println(err,
                "[FAIL] could not write approximate solution `$(parsed.out_path)`: $(sprint(showerror, write_error))")
        return CLI_EXIT_USAGE
    end

    _print_solve_summary(result; io)
    println(io, "[OK] wrote approximate solution: ", parsed.out_path)
    return CLI_EXIT_OK
end

function _cli_solve_certify(args; io::IO, err::IO)
    parsed = try
        _parse_solve_certify_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_solve_certify_usage(err)
        return CLI_EXIT_USAGE
    end

    solve_path = isnothing(parsed.solution_out_path) ? tempname() * ".json" :
                 parsed.solution_out_path
    solve_args = String[parsed.problem_path,
                        "--out", solve_path,
                        "--solver", join(String.(parsed.solvers), ","),
                        "--random-objective-trials",
                        string(parsed.random_objective_trials),
                        "--trace-objective",
                        String(parsed.trace_objective),
                        "--solver-attempts",
                        string(parsed.solver_attempts),
                        "--solver-retry-policy",
                        String(parsed.solver_retry_policy),
                        "--precision-bits",
                        string(parsed.precision_bits),
                        "--random-seed",
                        string(parsed.random_seed),
                        "--rank-relative-tolerance",
                        parsed.rank_relative_tolerance,
                        "--rank-gap-threshold",
                        parsed.rank_gap_threshold,
                        "--clarabel-max-iter",
                        string(parsed.clarabel_max_iter)]
    parsed.require_stable_rank && push!(solve_args, "--require-stable-rank")

    solve_code = _cli_solve(solve_args; io, err)
    solve_code == CLI_EXIT_OK || return solve_code

    certify_args = String[parsed.problem_path,
                          "--solution", solve_path,
                          "--out", parsed.cert_path,
                          "--psd-method", String(parsed.psd_method),
                          "--msolve-precision", string(parsed.msolve_precision),
                          "--msolve-threads", string(parsed.msolve_threads),
                          "--timeout", string(parsed.msolve_timeout_seconds),
                          "--budget", String(parsed.resource_profile),
                          "--slicing", String(parsed.slicing),
                          "--slice-tolerance", parsed.slicing_tolerance,
                          "--slice-max-denominator",
                          string(parsed.slicing_max_denominator),
                          "--max-rank-retries", string(parsed.max_rank_retries)]
    isnothing(parsed.msolve_binary) ||
        append!(certify_args, ["--msolve", parsed.msolve_binary])
    isnothing(parsed.backend_artifact_dir) ||
        append!(certify_args, ["--save-artifacts", parsed.backend_artifact_dir])
    isnothing(parsed.backend_cache_dir) ||
        append!(certify_args, ["--backend-cache", parsed.backend_cache_dir])
    parsed.rank_retry ? push!(certify_args, "--rank-retry") :
    push!(certify_args, "--no-rank-retry")

    return _cli_certify(certify_args; io, err)
end

function _cli_diagnose(args; io::IO, err::IO)
    if any(arg -> arg == "--format" || arg == "--out", args)
        cert_path = nothing
        format = :text
        out_path = nothing
        i = 1
        while i <= length(args)
            arg = args[i]
            if arg == "--format"
                i += 1
                i <= length(args) || begin
                    println(err, "[FAIL] --format requires text, json, or html")
                    return CLI_EXIT_USAGE
                end
                format = Symbol(args[i])
                format in (:text, :json, :html) || begin
                    println(err, "[FAIL] --format must be text, json, or html")
                    return CLI_EXIT_USAGE
                end
            elseif arg == "--out"
                i += 1
                i <= length(args) || begin
                    println(err, "[FAIL] --out requires a path")
                    return CLI_EXIT_USAGE
                end
                out_path = args[i]
            elseif startswith(arg, "--")
                println(err, "[FAIL] unknown diagnose option `$arg`")
                return CLI_EXIT_USAGE
            elseif isnothing(cert_path)
                cert_path = arg
            else
                println(err, "[FAIL] unexpected positional argument `$arg`")
                return CLI_EXIT_USAGE
            end
            i += 1
        end
        isnothing(cert_path) && begin
            println(err, "[FAIL] diagnose expects a certificate path")
            return CLI_EXIT_USAGE
        end
        report = Kernel.diagnose_file(cert_path; strict=true)
        rendered = if format === :json
            sprint() do buffer
                JSON3.pretty(buffer, Kernel.diagnostic_report_json(report))
                println(buffer)
            end
        elseif format === :html
            Kernel.diagnostic_report_html(report)
        else
            Kernel.diagnostic_report_text(report)
        end
        if isnothing(out_path)
            print(io, rendered)
        else
            try
                write(out_path, rendered)
            catch write_error
                println(err, "[FAIL] could not write diagnostic report `$(out_path)`: ",
                        sprint(showerror, write_error))
                return CLI_EXIT_USAGE
            end
            println(io, "[OK] wrote diagnostic report: ", out_path)
        end
        return report.accepted ? CLI_EXIT_OK : CLI_EXIT_REJECTED
    end

    parsed = try
        _parse_diagnose_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_diagnose_usage(err)
        return CLI_EXIT_USAGE
    end

    if isnothing(parsed.solution_path)
        failure = try
            read_failure_report(parsed.problem_path)
        catch parse_error
            println(err,
                    "[FAIL] could not read failure report `$(parsed.problem_path)`: $(sprint(showerror, parse_error))")
            return CLI_EXIT_USAGE
        end
        _print_failure_diagnosis(failure; io)
        return _cli_exit_for_failure(failure)
    end

    return _cli_diagnose_approx_from_parsed(parsed; io, err)
end

function _cli_diagnose_approx(args; io::IO, err::IO)
    parsed = try
        _parse_diagnose_approx_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_diagnose_approx_usage(err)
        return CLI_EXIT_USAGE
    end

    return _cli_diagnose_approx_from_parsed(parsed; io, err)
end

function _cli_diagnose_approx_from_parsed(parsed; io::IO, err::IO)
    problem = try
        read_problem(parsed.problem_path)
    catch parse_error
        println(err,
                "[FAIL] could not read problem `$(parsed.problem_path)`: $(sprint(showerror, parse_error))")
        return CLI_EXIT_USAGE
    end

    problem isa BlockLMIProblem && begin
                                   problem = try
                                             single_lmi_problem(problem)
                                             catch parse_error
                                             println(err,
                                                     "[FAIL] diagnose currently expects a single PSD block: $(sprint(showerror, parse_error))")
                                             return CLI_EXIT_USAGE
                                             end
                                   end

    approx = try
        _read_cli_solution_file(problem, parsed.solution_path;
                                precision_bits=parsed.precision_bits,
                                relative_tolerance=parsed.rank_relative_tolerance,
                                gap_threshold=parsed.rank_gap_threshold,)
    catch parse_error
        println(err,
                "[FAIL] could not read solution `$(parsed.solution_path)`: $(sprint(showerror, parse_error))")
        return CLI_EXIT_USAGE
    end

    approx isa ApproxSolution ||
        begin
            println(err,
                    "[FAIL] diagnose expects `--solution` to contain `approximate_solution`, not an exact rational certificate solution")
            return CLI_EXIT_USAGE
        end

    _print_approx_diagnosis(approx; io)
    return approx.rank_profile isa RankProfile ? CLI_EXIT_OK : CLI_EXIT_NOT_CERTIFIED
end

function _cli_certify_sos(args; io::IO, err::IO)
    parsed = try
        _parse_certify_sos_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_certify_sos_usage(err)
        return CLI_EXIT_USAGE
    end

    problem = try
        parse_sos_gram_json(read(parsed.problem_path, String))
    catch parse_error
        println(err,
                "[FAIL] could not read SOS Gram problem `$(parsed.problem_path)`: $(sprint(showerror, parse_error))")
        return CLI_EXIT_USAGE
    end

    gram_matrix = try
        _read_sos_gram_matrix_solution(problem, parsed.solution_path;
                                       reconstruct_floats=parsed.reconstruct_floats,
                                       tolerance=parsed.reconstruction_tolerance,
                                       max_denominator=parsed.reconstruction_max_denominator)
    catch parse_error
        println(err,
                "[FAIL] could not read SOS Gram solution `$(parsed.solution_path)`: $(sprint(showerror, parse_error))")
        return CLI_EXIT_USAGE
    end

    result = certify_sos(problem, gram_matrix)
    if result isa FailureResult
        _print_certification_failure(result.failure, err)
        return _cli_exit_for_failure(result.failure)
    end
    cert = certificate(result)

    accepted = verify(cert; io)
    if !accepted
        println(err, "[FAIL] internal verifier rejected the generated SOS Gram certificate")
        return CLI_EXIT_REJECTED
    end

    try
        write_certificate(parsed.out_path, cert)
    catch write_error
        println(err,
                "[FAIL] could not write certificate `$(parsed.out_path)`: $(sprint(showerror, write_error))")
        return CLI_EXIT_USAGE
    end

    println(io, "[OK] wrote SOS Gram certificate: $(parsed.out_path)")
    return CLI_EXIT_OK
end

function _cli_verify(args; io::IO, err::IO)
    parsed = try
        _parse_verify_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_verify_usage(err)
        return CLI_EXIT_USAGE
    end

    cert = try
        read_certificate(parsed.cert_path)
    catch parse_error
        println(err,
                "[FAIL] could not read certificate `$(parsed.cert_path)`: $(sprint(showerror, parse_error))")
        return CLI_EXIT_USAGE
    end

    if parsed.strict
        accepted = cert isa ExactCertificateArtifact ?
                   verify(cert; mode=:strict, io).status === :valid :
                   verify_strict(parsed.cert_path; io)
        return accepted ? CLI_EXIT_OK : CLI_EXIT_REJECTED
    end

    accepted = cert isa ExactCertificateArtifact ?
               verify(cert; mode=:strict, io).status === :valid :
               verify(cert; io)
    return accepted ? CLI_EXIT_OK : CLI_EXIT_REJECTED
end

function _cli_inspect(args; io::IO, err::IO)
    if length(args) != 1
        println(err, "[FAIL] inspect expects exactly one certificate path")
        println(err, "usage:")
        _print_inspect_usage(err)
        return CLI_EXIT_USAGE
    end

    cert = try
        read_certificate(args[1])
    catch parse_error
        println(err,
                "[FAIL] could not read certificate `$(args[1])`: $(sprint(showerror, parse_error))")
        return CLI_EXIT_USAGE
    end

    inspect_certificate(cert; io)
    return CLI_EXIT_OK
end

function _cli_certify(args; io::IO, err::IO)
    parsed = try
        _parse_certify_args(args)
    catch parse_error
        println(err, "[FAIL] $(sprint(showerror, parse_error))")
        println(err, "usage:")
        _print_certify_usage(err)
        return CLI_EXIT_USAGE
    end

    problem = try
        read_problem(parsed.problem_path)
    catch parse_error
        println(err,
                "[FAIL] could not read problem `$(parsed.problem_path)`: $(sprint(showerror, parse_error))")
        return CLI_EXIT_USAGE
    end

    solution = try
        _read_cli_solution_file(problem, parsed.solution_path;
                                precision_bits=parsed.precision_bits,
                                relative_tolerance=parsed.rank_relative_tolerance,
                                gap_threshold=parsed.rank_gap_threshold,)
    catch parse_error
        println(err,
                "[FAIL] could not read solution `$(parsed.solution_path)`: $(sprint(showerror, parse_error))")
        return CLI_EXIT_USAGE
    end

    cert = if solution isa Vector{Rational{BigInt}}
        result = certify(problem, solution; psd_method=parsed.psd_method)
        if result isa FailureResult
            _print_certification_failure(result.failure, err)
            return _cli_exit_for_failure(result.failure)
        end
        certificate(result)
    elseif solution isa ApproxSolution
        println(io, "[INFO] running algebraic certifier with backend `",
                parsed.algebraic_backend, "`")
        result = certify(problem, solution;
                         algebraic_backend=parsed.algebraic_backend,
                         psd_method=parsed.psd_method,
                         msolve_binary=parsed.msolve_binary,
                         sage_binary=parsed.sage_binary,
                         msolve_precision=parsed.msolve_precision,
                         msolve_threads=parsed.msolve_threads,
                         msolve_timeout_seconds=parsed.msolve_timeout_seconds,
                         backend_artifact_dir=parsed.backend_artifact_dir,
                         backend_cache_dir=parsed.backend_cache_dir,
                         backend_cache=parsed.backend_cache,
                         resource_profile=parsed.resource_profile,
                         max_system_variables=parsed.max_system_variables,
                         max_system_equations=parsed.max_system_equations,
                         max_degree_estimate=parsed.max_degree_estimate,
                         memory_limit_mb=parsed.memory_limit_mb,
                         memory_hint_mb=parsed.memory_hint_mb,
                         gauge_rows=parsed.gauge_rows,
                         slicing=parsed.slicing,
                         slicing_equations=parsed.slicing_equations,
                         slicing_tolerance=parsed.slicing_tolerance,
                         slicing_max_denominator=parsed.slicing_max_denominator,
                         slicing_max_equations=parsed.slicing_max_equations,
                         slicing_variables=parsed.slicing_variables,
                         slicing_seed=parsed.slicing_seed,
                         rank_retry=parsed.rank_retry,
                         max_rank_retries=parsed.max_rank_retries,
                         verify_io=nothing,)
        if result isa FailureResult
            _print_certification_failure(result.failure, err)
            return _cli_exit_for_failure(result.failure)
        end
        certificate(result)
    else
        println(err,
                "[FAIL] unsupported solution object parsed from `$(parsed.solution_path)`")
        return CLI_EXIT_USAGE
    end

    accepted = verify(cert; io)
    if !accepted
        println(err, "[FAIL] internal verifier rejected the generated certificate")
        return CLI_EXIT_REJECTED
    end

    try
        write_certificate(parsed.out_path, cert)
    catch write_error
        println(err,
                "[FAIL] could not write certificate `$(parsed.out_path)`: $(sprint(showerror, write_error))")
        return CLI_EXIT_USAGE
    end

    println(io, "[OK] wrote certificate: $(parsed.out_path)")
    return CLI_EXIT_OK
end

function _parse_certify_args(args::Vector{String})
    isempty(args) && throw(ArgumentError("certify expects a problem path"))

    problem_path = nothing
    solution_path = nothing
    out_path = nothing
    psd_method = :auto
    algebraic_backend = :msolve
    msolve_binary = nothing
    sage_binary = nothing
    msolve_precision = 128
    msolve_threads = 1
    msolve_timeout_seconds = DEFAULT_ALGEBRAIC_BACKEND_TIMEOUT_SECONDS
    backend_artifact_dir = nothing
    backend_cache_dir = nothing
    backend_cache = false
    resource_profile = DEFAULT_VALIDATION_BUDGET
    max_system_variables = nothing
    max_system_equations = nothing
    max_degree_estimate = nothing
    memory_limit_mb = nothing
    memory_hint_mb = nothing
    gauge_rows = nothing
    slicing = nothing
    slicing_equations = nothing
    slicing_tolerance = "1e-8"
    slicing_max_denominator = 1024
    slicing_max_equations = nothing
    slicing_variables = nothing
    slicing_seed = 0
    rank_retry = true
    max_rank_retries = 3
    precision_bits = nothing
    rank_relative_tolerance = DEFAULT_RANK_RELATIVE_TOLERANCE
    rank_gap_threshold = DEFAULT_RANK_GAP_THRESHOLD

    i = 1
    while i <= length(args)
        arg = args[i]

        if arg == "--solution"
            i += 1
            i <= length(args) || throw(ArgumentError("--solution requires a path"))
            solution_path = args[i]
        elseif arg == "--out"
            i += 1
            i <= length(args) || throw(ArgumentError("--out requires a path"))
            out_path = args[i]
        elseif arg == "--psd-method"
            i += 1
            i <= length(args) || throw(ArgumentError("--psd-method requires a value"))
            psd_method = Symbol(args[i])
        elseif arg == "--algebraic-backend"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--algebraic-backend requires msolve or sage_msolve"))
            algebraic_backend = _parse_cli_algebraic_backend(args[i])
        elseif arg == "--msolve"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--msolve requires a path or executable name"))
            msolve_binary = args[i]
        elseif arg == "--sage"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--sage requires a path or executable name"))
            sage_binary = args[i]
        elseif arg == "--msolve-precision"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--msolve-precision requires a positive integer"))
            msolve_precision = _parse_cli_positive_int(args[i], "--msolve-precision")
        elseif arg == "--msolve-threads"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--msolve-threads requires a positive integer"))
            msolve_threads = _parse_cli_positive_int(args[i], "--msolve-threads")
        elseif arg in ("--timeout", "--msolve-timeout")
            i += 1
            i <= length(args) ||
                throw(ArgumentError("$arg requires a positive number of seconds"))
            msolve_timeout_seconds = _parse_cli_positive_float(args[i],
                                                               arg)
        elseif arg == "--save-artifacts"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--save-artifacts requires a directory"))
            backend_artifact_dir = args[i]
        elseif arg == "--backend-cache"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--backend-cache requires a directory"))
            backend_cache_dir = args[i]
            backend_cache = true
        elseif arg in ("--budget", "--profile")
            i += 1
            i <= length(args) ||
                throw(ArgumentError("$arg requires validation"))
            resource_profile = Symbol(args[i])
        elseif arg == "--max-system-variables"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--max-system-variables requires a positive integer"))
            max_system_variables = _parse_cli_nonnegative_int(args[i],
                                                              "--max-system-variables")
        elseif arg == "--max-system-equations"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--max-system-equations requires a positive integer"))
            max_system_equations = _parse_cli_nonnegative_int(args[i],
                                                              "--max-system-equations")
        elseif arg == "--max-degree-estimate"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--max-degree-estimate requires a positive integer"))
            max_degree_estimate = _parse_cli_nonnegative_int(args[i],
                                                             "--max-degree-estimate")
        elseif arg == "--memory-limit-mb"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--memory-limit-mb requires a positive integer"))
            memory_limit_mb = _parse_cli_nonnegative_int(args[i], "--memory-limit-mb")
        elseif arg == "--memory-hint-mb"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--memory-hint-mb requires a positive integer"))
            memory_hint_mb = _parse_cli_nonnegative_int(args[i], "--memory-hint-mb")
        elseif arg == "--slicing"
            i += 1
            i <= length(args) || throw(ArgumentError("--slicing requires a value"))
            slicing = Symbol(args[i])
        elseif arg == "--slice-file"
            i += 1
            i <= length(args) || throw(ArgumentError("--slice-file requires a path"))
            slice_spec = _read_cli_slicing_file(args[i])
            if haskey(slice_spec, :strategy)
                slicing = Symbol(slice_spec[:strategy])
            end
            if haskey(slice_spec, :equations)
                slicing_equations = slice_spec[:equations]
            end
            if haskey(slice_spec, :tolerance)
                slicing_tolerance = slice_spec[:tolerance]
            end
            if haskey(slice_spec, :max_denominator)
                slicing_max_denominator = Int(slice_spec[:max_denominator])
            end
            if haskey(slice_spec, :max_equations)
                slicing_max_equations = Int(slice_spec[:max_equations])
            end
            if haskey(slice_spec, :variables)
                slicing_variables = slice_spec[:variables]
            end
            if haskey(slice_spec, :gauge_rows)
                gauge_rows = Int[value for value in slice_spec[:gauge_rows]]
            end
            if haskey(slice_spec, :seed)
                slicing_seed = Int(slice_spec[:seed])
            end
        elseif arg == "--slice-tolerance"
            i += 1
            i <= length(args) || throw(ArgumentError("--slice-tolerance requires a value"))
            slicing_tolerance = args[i]
        elseif arg == "--slice-max-denominator"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--slice-max-denominator requires a positive integer"))
            slicing_max_denominator = _parse_cli_positive_int(args[i],
                                                              "--slice-max-denominator")
        elseif arg == "--slice-max-equations"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--slice-max-equations requires a nonnegative integer"))
            slicing_max_equations = _parse_cli_nonnegative_int(args[i],
                                                               "--slice-max-equations")
        elseif arg == "--slice-vars"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--slice-vars requires a comma-separated list"))
            slicing_variables = _parse_cli_symbol_list(args[i])
        elseif arg == "--rank-retry"
            rank_retry = true
        elseif arg == "--no-rank-retry"
            rank_retry = false
        elseif arg == "--max-rank-retries"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--max-rank-retries requires a nonnegative integer"))
            max_rank_retries = _parse_cli_nonnegative_int(args[i], "--max-rank-retries")
        elseif arg == "--precision-bits"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--precision-bits requires a positive integer"))
            precision_bits = _parse_cli_positive_int(args[i], "--precision-bits")
        elseif arg == "--rank-relative-tolerance"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--rank-relative-tolerance requires a value"))
            rank_relative_tolerance = args[i]
        elseif arg == "--rank-gap-threshold"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--rank-gap-threshold requires a value"))
            rank_gap_threshold = args[i]
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown certify option `$arg`"))
        elseif isnothing(problem_path)
            problem_path = arg
        else
            throw(ArgumentError("unexpected positional argument `$arg`"))
        end

        i += 1
    end

    isnothing(problem_path) && throw(ArgumentError("certify is missing problem.json"))
    isnothing(solution_path) &&
        throw(ArgumentError("certify is missing --solution approx.json"))
    isnothing(out_path) && throw(ArgumentError("certify is missing --out cert.json"))

    return (;
            problem_path,
            solution_path,
            out_path,
            psd_method,
            algebraic_backend,
            msolve_binary,
            sage_binary,
            msolve_precision,
            msolve_threads,
            msolve_timeout_seconds,
            backend_artifact_dir,
            backend_cache_dir,
            backend_cache,
            resource_profile,
            max_system_variables,
            max_system_equations,
            max_degree_estimate,
            memory_limit_mb,
            memory_hint_mb,
            gauge_rows,
            slicing,
            slicing_equations,
            slicing_tolerance,
            slicing_max_denominator,
            slicing_max_equations,
            slicing_variables,
            slicing_seed,
            rank_retry,
            max_rank_retries,
            precision_bits,
            rank_relative_tolerance,
            rank_gap_threshold,)
end

function _parse_solve_args(args::Vector{String})
    isempty(args) && throw(ArgumentError("solve expects a problem path"))

    problem_path = nothing
    out_path = nothing
    solvers = [:clarabel]
    random_objective_trials = 0
    trace_objective = :maximize
    solver_attempts = 1
    solver_retry_policy = :default
    precision_bits = DEFAULT_APPROX_PRECISION_BITS
    random_seed = 0
    require_stable_rank = false
    clarabel_max_iter = 200
    rank_relative_tolerance = DEFAULT_RANK_RELATIVE_TOLERANCE
    rank_gap_threshold = DEFAULT_RANK_GAP_THRESHOLD

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--out"
            i += 1
            i <= length(args) || throw(ArgumentError("--out requires a path"))
            out_path = args[i]
        elseif arg == "--solver"
            i += 1
            i <= length(args) || throw(ArgumentError("--solver requires a value"))
            solvers = _parse_cli_symbol_list(args[i])
            isempty(solvers) &&
                throw(ArgumentError("--solver must name at least one solver"))
        elseif arg == "--random-objective-trials"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--random-objective-trials requires a nonnegative integer"))
            random_objective_trials = _parse_cli_nonnegative_int(args[i],
                                                                 "--random-objective-trials")
        elseif arg == "--trace-objective"
            i += 1
            i <= length(args) || throw(ArgumentError("--trace-objective requires a value"))
            trace_objective = Symbol(args[i])
        elseif arg == "--no-trace-objective"
            trace_objective = :none
        elseif arg == "--solver-attempts"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--solver-attempts requires a positive integer"))
            solver_attempts = _parse_cli_positive_int(args[i], "--solver-attempts")
        elseif arg == "--solver-retry-policy"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--solver-retry-policy requires default, none, or conservative"))
            solver_retry_policy = Symbol(args[i])
        elseif arg == "--precision-bits"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--precision-bits requires a positive integer"))
            precision_bits = _parse_cli_positive_int(args[i], "--precision-bits")
        elseif arg == "--random-seed"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--random-seed requires an integer"))
            random_seed = try
                parse(Int, args[i])
            catch
                throw(ArgumentError("--random-seed requires an integer"))
            end
        elseif arg == "--require-stable-rank"
            require_stable_rank = true
        elseif arg == "--clarabel-max-iter"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--clarabel-max-iter requires a positive integer"))
            clarabel_max_iter = _parse_cli_positive_int(args[i], "--clarabel-max-iter")
        elseif arg == "--rank-relative-tolerance"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--rank-relative-tolerance requires a value"))
            rank_relative_tolerance = args[i]
        elseif arg == "--rank-gap-threshold"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--rank-gap-threshold requires a value"))
            rank_gap_threshold = args[i]
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown solve option `$arg`"))
        elseif isnothing(problem_path)
            problem_path = arg
        else
            throw(ArgumentError("unexpected positional argument `$arg`"))
        end
        i += 1
    end

    isnothing(problem_path) && throw(ArgumentError("solve is missing problem.json"))
    isnothing(out_path) && throw(ArgumentError("solve is missing --out approx.json"))
    trace_objective === :none && (trace_objective = false)

    return (;
            problem_path,
            out_path,
            solvers,
            random_objective_trials,
            trace_objective,
            solver_attempts,
            solver_retry_policy,
            precision_bits,
            random_seed,
            require_stable_rank,
            clarabel_max_iter,
            rank_relative_tolerance,
            rank_gap_threshold,)
end

function _parse_solve_certify_args(args::Vector{String})
    isempty(args) && throw(ArgumentError("solve-certify expects a problem path"))
    raw_solve_args = _solve_args_subset(args)
    if !("--out" in raw_solve_args)
        append!(raw_solve_args, ["--out", tempname() * ".json"])
    end
    solve = _parse_solve_args(raw_solve_args)
    cert_path = nothing
    solution_out_path = solve.out_path
    psd_method = :auto
    msolve_binary = nothing
    msolve_precision = 128
    msolve_threads = 1
    msolve_timeout_seconds = DEFAULT_ALGEBRAIC_BACKEND_TIMEOUT_SECONDS
    backend_artifact_dir = nothing
    backend_cache_dir = nothing
    resource_profile = DEFAULT_VALIDATION_BUDGET
    slicing = :auto
    slicing_tolerance = "1e-8"
    slicing_max_denominator = 1024
    rank_retry = true
    max_rank_retries = 3

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg in ("--out", "--solver", "--random-objective-trials",
                   "--trace-objective", "--solver-attempts",
                   "--solver-retry-policy", "--precision-bits",
                   "--random-seed", "--clarabel-max-iter",
                   "--rank-relative-tolerance", "--rank-gap-threshold")
            i += 2
            continue
        elseif arg in ("--no-trace-objective", "--require-stable-rank")
            i += 1
            continue
        elseif arg == "--cert-out"
            i += 1
            i <= length(args) || throw(ArgumentError("--cert-out requires a path"))
            cert_path = args[i]
        elseif arg == "--solution-out"
            i += 1
            i <= length(args) || throw(ArgumentError("--solution-out requires a path"))
            solution_out_path = args[i]
        elseif arg == "--psd-method"
            i += 1
            i <= length(args) || throw(ArgumentError("--psd-method requires a value"))
            psd_method = Symbol(args[i])
        elseif arg == "--msolve"
            i += 1
            i <= length(args) || throw(ArgumentError("--msolve requires a path"))
            msolve_binary = args[i]
        elseif arg == "--msolve-precision"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--msolve-precision requires a positive integer"))
            msolve_precision = _parse_cli_positive_int(args[i], "--msolve-precision")
        elseif arg == "--msolve-threads"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--msolve-threads requires a positive integer"))
            msolve_threads = _parse_cli_positive_int(args[i], "--msolve-threads")
        elseif arg in ("--timeout", "--msolve-timeout")
            i += 1
            i <= length(args) ||
                throw(ArgumentError("$arg requires a positive number of seconds"))
            msolve_timeout_seconds = _parse_cli_positive_float(args[i],
                                                               arg)
        elseif arg == "--save-artifacts"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--save-artifacts requires a directory"))
            backend_artifact_dir = args[i]
        elseif arg == "--backend-cache"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--backend-cache requires a directory"))
            backend_cache_dir = args[i]
        elseif arg in ("--budget", "--profile")
            i += 1
            i <= length(args) || throw(ArgumentError("$arg requires a value"))
            resource_profile = Symbol(args[i])
        elseif arg == "--slicing"
            i += 1
            i <= length(args) || throw(ArgumentError("--slicing requires a value"))
            slicing = Symbol(args[i])
        elseif arg == "--slice-tolerance"
            i += 1
            i <= length(args) || throw(ArgumentError("--slice-tolerance requires a value"))
            slicing_tolerance = args[i]
        elseif arg == "--slice-max-denominator"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--slice-max-denominator requires a positive integer"))
            slicing_max_denominator = _parse_cli_positive_int(args[i],
                                                              "--slice-max-denominator")
        elseif arg == "--rank-retry"
            rank_retry = true
        elseif arg == "--no-rank-retry"
            rank_retry = false
        elseif arg == "--max-rank-retries"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--max-rank-retries requires a nonnegative integer"))
            max_rank_retries = _parse_cli_nonnegative_int(args[i],
                                                          "--max-rank-retries")
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown solve-certify option `$arg`"))
        end
        i += 1
    end

    isnothing(cert_path) &&
        throw(ArgumentError("solve-certify is missing --cert-out cert.json"))
    return merge(solve,
                 (;
                  cert_path,
                  solution_out_path,
                  psd_method,
                  msolve_binary,
                  msolve_precision,
                  msolve_threads,
                  msolve_timeout_seconds,
                  backend_artifact_dir,
                  backend_cache_dir,
                  resource_profile,
                  slicing,
                  slicing_tolerance,
                  slicing_max_denominator,
                  rank_retry,
                  max_rank_retries,))
end

function _solve_args_subset(args::Vector{String})
    subset = String[]
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg in ("--cert-out", "--solution-out", "--psd-method", "--msolve",
                   "--msolve-precision", "--msolve-threads", "--msolve-timeout",
                   "--timeout", "--save-artifacts", "--backend-cache", "--budget",
                   "--profile", "--slicing",
                   "--slice-tolerance", "--slice-max-denominator",
                   "--max-rank-retries")
            i += 2
            continue
        elseif arg in ("--rank-retry", "--no-rank-retry")
            i += 1
            continue
        end
        push!(subset, arg)
        i += 1
    end
    return subset
end

function _parse_verify_args(args::Vector{String})
    isempty(args) && throw(ArgumentError("verify expects a certificate path"))

    cert_path = nothing
    strict = false

    for arg in args
        if arg == "--strict"
            strict = true
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown verify option `$arg`"))
        elseif isnothing(cert_path)
            cert_path = arg
        else
            throw(ArgumentError("unexpected positional argument `$arg`"))
        end
    end

    isnothing(cert_path) && throw(ArgumentError("verify expects a certificate path"))
    return (; cert_path, strict)
end

function _parse_doctor_args(args::Vector{String})
    validation_root = "benchmarks"
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg in ("--benchmarks", "--validation-root")
            i += 1
            i <= length(args) || throw(ArgumentError("$arg requires a directory"))
            validation_root = args[i]
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown doctor option `$arg`"))
        else
            throw(ArgumentError("unexpected positional argument `$arg`"))
        end
        i += 1
    end
    return (; validation_root)
end

function _parse_explain_args(args::Vector{String})
    isempty(args) && throw(ArgumentError("explain expects a failure report path"))
    failure_path = nothing
    max_lines = 30
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--max-lines"
            i += 1
            i <= length(args) || throw(ArgumentError("--max-lines requires a count"))
            max_lines = _parse_cli_positive_int(args[i], "--max-lines")
            max_lines <= 30 ||
                throw(ArgumentError("--max-lines cannot exceed 30 for shared output"))
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown explain option `$arg`"))
        elseif isnothing(failure_path)
            failure_path = arg
        else
            throw(ArgumentError("unexpected positional argument `$arg`"))
        end
        i += 1
    end
    isnothing(failure_path) && throw(ArgumentError("explain is missing failure.json"))
    return (; failure_path, max_lines)
end

function _parse_bundle_args(args::Vector{String})
    isempty(args) && throw(ArgumentError("bundle expects a certificate path"))
    cert_path = nothing
    out_path = nothing
    problem_path = nothing
    approx_path = nothing
    report_path = nothing
    logs_path = nothing
    redact = true
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--out"
            i += 1
            i <= length(args) || throw(ArgumentError("--out requires a zip path"))
            out_path = args[i]
        elseif arg == "--problem"
            i += 1
            i <= length(args) || throw(ArgumentError("--problem requires a path"))
            problem_path = args[i]
        elseif arg in ("--approx", "--solution")
            i += 1
            i <= length(args) || throw(ArgumentError("$arg requires a path"))
            approx_path = args[i]
        elseif arg == "--report"
            i += 1
            i <= length(args) || throw(ArgumentError("--report requires a path"))
            report_path = args[i]
        elseif arg in ("--logs", "--backend-logs")
            i += 1
            i <= length(args) || throw(ArgumentError("$arg requires a path"))
            logs_path = args[i]
        elseif arg == "--redact"
            redact = true
        elseif arg == "--no-redact"
            redact = false
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown bundle option `$arg`"))
        elseif isnothing(cert_path)
            cert_path = arg
        else
            throw(ArgumentError("unexpected positional argument `$arg`"))
        end
        i += 1
    end
    isnothing(cert_path) && throw(ArgumentError("bundle is missing cert.json"))
    isnothing(out_path) && throw(ArgumentError("bundle is missing --out artifact.zip"))
    return (; cert_path, out_path, problem_path, approx_path, report_path, logs_path,
            redact)
end

function _parse_replay_args(args::Vector{String})
    isempty(args) && throw(ArgumentError("replay expects an artifact.zip path"))
    bundle_path = nothing
    extract_dir = nothing
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--extract-dir"
            i += 1
            i <= length(args) || throw(ArgumentError("--extract-dir requires a directory"))
            extract_dir = args[i]
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown replay option `$arg`"))
        elseif isnothing(bundle_path)
            bundle_path = arg
        else
            throw(ArgumentError("unexpected positional argument `$arg`"))
        end
        i += 1
    end
    isnothing(bundle_path) && throw(ArgumentError("replay is missing artifact.zip"))
    return (; bundle_path, extract_dir)
end

function _parse_schema_args(args::Vector{String})
    length(args) >= 2 ||
        throw(ArgumentError("schema expects `validate` or `migrate` and an input path"))
    action = Symbol(args[1])
    action in (:validate, :migrate) ||
        throw(ArgumentError("schema action must be `validate` or `migrate`"))

    path = nothing
    out_path = nothing
    kind = :auto
    i = 2
    while i <= length(args)
        arg = args[i]
        if arg == "--kind"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--kind requires problem, certificate, failure, or auto"))
            kind = _parse_schema_kind(args[i])
        elseif arg == "--out"
            i += 1
            i <= length(args) || throw(ArgumentError("--out requires a path"))
            out_path = args[i]
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown schema option `$arg`"))
        elseif isnothing(path)
            path = arg
        else
            throw(ArgumentError("unexpected positional argument `$arg`"))
        end
        i += 1
    end

    isnothing(path) && throw(ArgumentError("schema is missing input.json"))
    action === :migrate && isnothing(out_path) &&
        throw(ArgumentError("schema migrate is missing --out output.json"))
    return (; action, path, kind, out_path)
end

function _parse_export_sos_args(args::Vector{String})
    isempty(args) && throw(ArgumentError("export-sos expects a certificate path"))
    cert_path = nothing
    out_path = nothing
    format = :json
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--out"
            i += 1
            i <= length(args) || throw(ArgumentError("--out requires a path"))
            out_path = args[i]
        elseif arg == "--format"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--format requires json, text, latex, sage, or julia"))
            format = _parse_export_sos_format(args[i])
        elseif arg == "--text"
            format = :text
        elseif arg == "--json"
            format = :json
        elseif arg == "--latex"
            format = :latex
        elseif arg == "--sage"
            format = :sage
        elseif arg == "--julia"
            format = :julia
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown export-sos option `$arg`"))
        elseif isnothing(cert_path)
            cert_path = arg
        else
            throw(ArgumentError("unexpected positional argument `$arg`"))
        end
        i += 1
    end
    isnothing(cert_path) && throw(ArgumentError("export-sos is missing cert.json"))
    isnothing(out_path) && throw(ArgumentError("export-sos is missing --out output"))
    return (; cert_path, out_path, format)
end

function _parse_convert_sostools_args(args::Vector{String})
    isempty(args) &&
        throw(ArgumentError("convert-sostools expects a SOSTOOLS-lite JSON path"))
    input_path = nothing
    problem_out = nothing
    solution_out = nothing
    cert_out = nothing

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--problem-out"
            i += 1
            i <= length(args) || throw(ArgumentError("--problem-out requires a path"))
            problem_out = args[i]
        elseif arg == "--solution-out"
            i += 1
            i <= length(args) || throw(ArgumentError("--solution-out requires a path"))
            solution_out = args[i]
        elseif arg == "--cert-out"
            i += 1
            i <= length(args) || throw(ArgumentError("--cert-out requires a path"))
            cert_out = args[i]
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown convert-sostools option `$arg`"))
        elseif isnothing(input_path)
            input_path = arg
        else
            throw(ArgumentError("unexpected positional argument `$arg`"))
        end
        i += 1
    end

    isnothing(input_path) && throw(ArgumentError("convert-sostools is missing input.json"))
    (isnothing(problem_out) && isnothing(solution_out) && isnothing(cert_out)) &&
        throw(ArgumentError("convert-sostools needs at least one output option"))
    return (; input_path, problem_out, solution_out, cert_out)
end

function _parse_schema_kind(text::AbstractString)
    kind = Symbol(text)
    kind in (:auto, :problem, :certificate, :failure) ||
        throw(ArgumentError("--kind must be problem, certificate, failure, or auto"))
    return kind
end

function _parse_export_sos_format(text::AbstractString)
    format = Symbol(text)
    format in (:json, :text, :latex, :sage, :julia) ||
        throw(ArgumentError("--format must be json, text, latex, sage, or julia"))
    return format
end

function _schema_candidate_kinds(kind::Symbol; migrate::Bool=false)
    if kind === :auto
        return migrate ? (:problem, :certificate) : (:problem, :certificate, :failure)
    elseif migrate && kind === :failure
        throw(ArgumentError("failure reports are already schema v1.0 and cannot be migrated"))
    end
    return (kind,)
end

function _validate_schema_text(json_text::AbstractString, kind::Symbol)
    errors = String[]
    for candidate in _schema_candidate_kinds(kind)
        try
            if candidate === :certificate
                parsed = JSON3.read(json_text)
                if haskey(parsed, :certsdp_certificate_version) &&
                   String(parsed[:certsdp_certificate_version]) ==
                   Kernel.CERTSDP3_SCHEMA_VERSION
                    Kernel.validate_certificate_schema_v3(json_text)
                    return candidate
                end
            elseif candidate === :problem
                parsed = JSON3.read(json_text)
                if haskey(parsed, :certsdp_problem_version) &&
                   String(parsed[:certsdp_problem_version]) ==
                   Kernel.CERTSDP3_SCHEMA_VERSION
                    Kernel.validate_problem_schema_v3(json_text)
                    return candidate
                end
            end
            candidate === :problem && validate_problem_schema(json_text)
            candidate === :certificate && validate_certificate_schema(json_text)
            candidate === :failure && validate_failure_report_schema(json_text)
            return candidate
        catch err
            push!(errors, "$(candidate): $(sprint(showerror, err))")
        end
    end
    throw(ArgumentError(join(errors, "; ")))
end

function _migrate_schema_text(json_text::AbstractString, kind::Symbol)
    errors = String[]
    for candidate in _schema_candidate_kinds(kind; migrate=true)
        try
            if candidate === :problem
                return candidate, migrate_problem_json(json_text)
            elseif candidate === :certificate
                return candidate, migrate_certificate_json(json_text)
            end
        catch err
            push!(errors, "$(candidate): $(sprint(showerror, err))")
        end
    end
    throw(ArgumentError(join(errors, "; ")))
end

function _parse_certify_sos_args(args::Vector{String})
    isempty(args) &&
        throw(ArgumentError("certify-sos expects an exported SOS Gram problem path"))

    problem_path = nothing
    solution_path = nothing
    out_path = nothing
    reconstruct_floats = false
    reconstruction_tolerance = nothing
    reconstruction_max_denominator = DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR

    i = 1
    while i <= length(args)
        arg = args[i]

        if arg == "--solution"
            i += 1
            i <= length(args) || throw(ArgumentError("--solution requires a path"))
            solution_path = args[i]
        elseif arg == "--out"
            i += 1
            i <= length(args) || throw(ArgumentError("--out requires a path"))
            out_path = args[i]
        elseif arg == "--reconstruct-floats"
            reconstruct_floats = true
        elseif arg == "--reconstruction-tolerance"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--reconstruction-tolerance requires a value"))
            reconstruction_tolerance = _parse_cli_positive_float(args[i],
                                                                 "--reconstruction-tolerance")
        elseif arg == "--reconstruction-max-denominator"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--reconstruction-max-denominator requires a value"))
            reconstruction_max_denominator = _parse_cli_positive_int(args[i],
                                                                     "--reconstruction-max-denominator")
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown certify-sos option `$arg`"))
        elseif isnothing(problem_path)
            problem_path = arg
        else
            throw(ArgumentError("unexpected positional argument `$arg`"))
        end

        i += 1
    end

    isnothing(problem_path) && throw(ArgumentError("certify-sos is missing sos_gram.json"))
    isnothing(solution_path) &&
        throw(ArgumentError("certify-sos is missing --solution gram_solution.json"))
    isnothing(out_path) && throw(ArgumentError("certify-sos is missing --out cert.json"))
    reconstruct_floats && isnothing(reconstruction_tolerance) &&
        throw(ArgumentError("--reconstruct-floats requires --reconstruction-tolerance"))

    return (;
            problem_path,
            solution_path,
            out_path,
            reconstruct_floats,
            reconstruction_tolerance,
            reconstruction_max_denominator,)
end

function _parse_certify_auto_sos_args(args::Vector{String})
    isempty(args) &&
        throw(ArgumentError("certify-auto-sos expects an exported SOS Gram problem path"))

    problem_path = nothing
    solution_path = nothing
    out_path = nothing
    strategies = Symbol[:direct, :sos_round_project]
    tolerance = nothing
    max_denominator = DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR

    i = 1
    while i <= length(args)
        arg = args[i]

        if arg == "--solution"
            i += 1
            i <= length(args) || throw(ArgumentError("--solution requires a path"))
            solution_path = args[i]
        elseif arg == "--out"
            i += 1
            i <= length(args) || throw(ArgumentError("--out requires a path"))
            out_path = args[i]
        elseif arg == "--strategies"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--strategies requires a comma-separated list"))
            strategies = _parse_cli_symbol_list(args[i])
            isempty(strategies) &&
                throw(ArgumentError("--strategies must name at least one exactification strategy"))
        elseif arg in ("--tolerance", "--reconstruction-tolerance")
            i += 1
            i <= length(args) || throw(ArgumentError("$arg requires a value"))
            tolerance = _parse_cli_positive_float(args[i], arg)
        elseif arg in ("--max-denominator", "--reconstruction-max-denominator")
            i += 1
            i <= length(args) || throw(ArgumentError("$arg requires a value"))
            max_denominator = _parse_cli_positive_int(args[i], arg)
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown certify-auto-sos option `$arg`"))
        elseif isnothing(problem_path)
            problem_path = arg
        else
            throw(ArgumentError("unexpected positional argument `$arg`"))
        end

        i += 1
    end

    isnothing(problem_path) &&
        throw(ArgumentError("certify-auto-sos is missing sos_gram.json"))
    isnothing(solution_path) &&
        throw(ArgumentError("certify-auto-sos is missing --solution gram_solution.json"))
    isnothing(out_path) &&
        throw(ArgumentError("certify-auto-sos is missing --out cert.json"))

    return (; problem_path, solution_path, out_path, strategies, tolerance,
            max_denominator)
end

function _parse_diagnose_args(args::Vector{String})
    isempty(args) && throw(ArgumentError("diagnose expects a problem path"))

    problem_path = nothing
    solution_path = nothing
    precision_bits = nothing
    rank_relative_tolerance = DEFAULT_RANK_RELATIVE_TOLERANCE
    rank_gap_threshold = DEFAULT_RANK_GAP_THRESHOLD

    i = 1
    while i <= length(args)
        arg = args[i]

        if arg == "--solution"
            i += 1
            i <= length(args) || throw(ArgumentError("--solution requires a path"))
            solution_path = args[i]
        elseif arg == "--precision-bits"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--precision-bits requires a positive integer"))
            precision_bits = _parse_cli_positive_int(args[i], "--precision-bits")
        elseif arg == "--rank-relative-tolerance"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--rank-relative-tolerance requires a value"))
            rank_relative_tolerance = args[i]
        elseif arg == "--rank-gap-threshold"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--rank-gap-threshold requires a value"))
            rank_gap_threshold = args[i]
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown diagnose option `$arg`"))
        elseif isnothing(problem_path)
            problem_path = arg
        else
            throw(ArgumentError("unexpected positional argument `$arg`"))
        end

        i += 1
    end

    isnothing(problem_path) &&
        throw(ArgumentError("diagnose is missing a failure report or problem path"))

    return (;
            problem_path,
            solution_path,
            precision_bits,
            rank_relative_tolerance,
            rank_gap_threshold,)
end

function _parse_diagnose_approx_args(args::Vector{String})
    parsed = _parse_diagnose_args(args)
    isnothing(parsed.solution_path) &&
        throw(ArgumentError("diagnose-approx is missing --solution approx.json"))
    return parsed
end

function _parse_benchmark_args(args::Vector{String})
    root = nothing
    out_path = nothing
    subset = BENCHMARK_DEFAULT_SUBSET
    generated_dir = nothing
    profile = DEFAULT_VALIDATION_BUDGET
    timeout_seconds = nothing
    max_system_variables = nothing
    max_system_equations = nothing
    max_degree_estimate = nothing
    memory_limit_mb = nothing
    memory_hint_mb = nothing

    i = 1
    while i <= length(args)
        arg = args[i]

        if arg == "--out"
            i += 1
            i <= length(args) || throw(ArgumentError("--out requires a path"))
            out_path = args[i]
        elseif arg == "--suite"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--suite requires validation"))
            subset = _parse_public_benchmark_suite(args[i])
        elseif arg == "--generated-dir"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--generated-dir requires a directory"))
            generated_dir = args[i]
        elseif arg in ("--budget", "--profile")
            i += 1
            i <= length(args) || throw(ArgumentError("$arg requires validation"))
            profile = Symbol(args[i])
        elseif arg == "--timeout"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--timeout requires a positive number of seconds"))
            timeout_seconds = _parse_cli_positive_float(args[i], "--timeout")
        elseif arg == "--max-system-variables"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--max-system-variables requires a nonnegative integer"))
            max_system_variables = _parse_cli_nonnegative_int(args[i],
                                                              "--max-system-variables")
        elseif arg == "--max-system-equations"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--max-system-equations requires a nonnegative integer"))
            max_system_equations = _parse_cli_nonnegative_int(args[i],
                                                              "--max-system-equations")
        elseif arg == "--max-degree-estimate"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--max-degree-estimate requires a nonnegative integer"))
            max_degree_estimate = _parse_cli_nonnegative_int(args[i],
                                                             "--max-degree-estimate")
        elseif arg == "--memory-limit-mb"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--memory-limit-mb requires a nonnegative integer"))
            memory_limit_mb = _parse_cli_nonnegative_int(args[i],
                                                         "--memory-limit-mb")
        elseif arg == "--memory-hint-mb"
            i += 1
            i <= length(args) ||
                throw(ArgumentError("--memory-hint-mb requires a nonnegative integer"))
            memory_hint_mb = _parse_cli_nonnegative_int(args[i],
                                                        "--memory-hint-mb")
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown benchmark option `$arg`"))
        elseif isnothing(root)
            root = arg
        else
            throw(ArgumentError("unexpected positional argument `$arg`"))
        end

        i += 1
    end

    isnothing(root) && (root = "benchmarks")
    if isnothing(out_path)
        if subset === :validation
            out_path = joinpath(normpath(root), "VALIDATION_REPORT.md")
        else
            throw(ArgumentError("benchmark is missing --out report.md"))
        end
    end

    budget = (;
              timeout_seconds,
              max_system_variables,
              max_system_equations,
              max_degree_estimate,
              memory_limit_mb,
              memory_hint_mb,)
    return (; root, out_path, subset, generated_dir, profile, budget)
end

function _parse_public_benchmark_suite(value::AbstractString)
    suite = Symbol(lowercase(strip(String(value))))
    suite === :validation && return suite
    throw(ArgumentError("--suite requires validation; got `$value`"))
end

function _parse_cli_positive_int(value::AbstractString, option::AbstractString)
    parsed = try
        parse(Int, value)
    catch
        throw(ArgumentError("$option must be a positive integer; got `$value`"))
    end
    parsed > 0 || throw(ArgumentError("$option must be positive; got `$value`"))
    return parsed
end

function _parse_cli_nonnegative_int(value::AbstractString, option::AbstractString)
    parsed = try
        parse(Int, value)
    catch
        throw(ArgumentError("$option must be a nonnegative integer; got `$value`"))
    end
    parsed >= 0 || throw(ArgumentError("$option must be nonnegative; got `$value`"))
    return parsed
end

function _parse_cli_symbol_list(value::AbstractString)
    items = split(String(value), ",")
    symbols = Symbol[]
    for item in items
        text = strip(item)
        isempty(text) && continue
        push!(symbols, Symbol(text))
    end
    return symbols
end

function _parse_cli_algebraic_backend(value::AbstractString)
    backend = Symbol(value)
    backend in (:msolve, :sage_msolve, :sage) ||
        throw(ArgumentError("algebraic backend must be msolve or sage_msolve"))
    return backend === :sage ? :sage_msolve : backend
end

function _read_cli_slicing_file(path::AbstractString)
    parsed = try
        JSON3.read(read(path, String))
    catch err
        throw(ArgumentError("invalid slicing JSON: $(sprint(showerror, err))"))
    end

    _require_object(parsed, "root")
    if haskey(parsed, :slicing)
        slicing = _require_key(parsed, :slicing, "root")
        _require_object(slicing, "root.slicing")
        return _json_object_to_symbol_dict(slicing)
    end
    return _json_object_to_symbol_dict(parsed)
end

function _parse_cli_positive_float(value::AbstractString, option::AbstractString)
    parsed = try
        parse(Float64, value)
    catch
        throw(ArgumentError("$option must be a positive number; got `$value`"))
    end
    parsed > 0 || throw(ArgumentError("$option must be positive; got `$value`"))
    return parsed
end

function _read_cli_solution_file(P::LMIProblem, path::AbstractString; kwargs...)
    parsed = try
        JSON3.read(read(path, String))
    catch err
        throw(ArgumentError("invalid solution JSON: $(sprint(showerror, err))"))
    end

    _require_object(parsed, "root")
    if haskey(parsed, :certsdp_version)
        _require_value(parsed, :certsdp_version, LMI_JSON_VERSION, "root.certsdp_version")
    elseif haskey(parsed, :certsdp_problem_version)
        _require_value(parsed, :certsdp_problem_version, SCHEMA_V1_VERSION,
                       "root.certsdp_problem_version")
    end

    if haskey(parsed, :problem)
        embedded = _parse_lmi_problem_object(_require_key(parsed, :problem, "root"))
        embedded_hash = lmi_problem_hash(embedded)
        problem_hash = lmi_problem_hash(P)
        embedded_hash == problem_hash ||
            throw(ArgumentError("embedded problem hash $embedded_hash does not match problem.json hash $problem_hash"))
    end

    if haskey(parsed, :solution)
        solution = _require_key(parsed, :solution, "root")
        _require_object(solution, "solution")
        solution_type = _require_string(solution, :type, "solution.type")
        solution_type == RATIONAL_SOLUTION_TYPE ||
            throw(ArgumentError("solution.type must be `$RATIONAL_SOLUTION_TYPE` for exact rational certification; got `$solution_type`"))
        return _parse_rational_solution(solution, num_variables(P))
    elseif haskey(parsed, :approximate_solution)
        approx = _require_key(parsed, :approximate_solution, "root")
        return _parse_approx_solution_object(P, approx; kwargs...)
    end

    throw(ArgumentError("solution JSON must contain `solution` or `approximate_solution`"))
end

function _read_cli_solution_file(P::BlockLMIProblem, path::AbstractString; kwargs...)
    parsed = try
        JSON3.read(read(path, String))
    catch err
        throw(ArgumentError("invalid solution JSON: $(sprint(showerror, err))"))
    end

    _require_object(parsed, "root")
    if haskey(parsed, :certsdp_version)
        _require_value(parsed, :certsdp_version, LMI_JSON_VERSION, "root.certsdp_version")
    elseif haskey(parsed, :certsdp_problem_version)
        _require_value(parsed, :certsdp_problem_version, SCHEMA_V1_VERSION,
                       "root.certsdp_problem_version")
    end

    if haskey(parsed, :problem)
        embedded_value = _require_key(parsed, :problem, "root")
        embedded = if embedded_value isa JSON3.Object &&
                      haskey(embedded_value, :type) &&
                      getproperty(embedded_value, :type) == SDPA_PROBLEM_TYPE
            _parse_block_lmi_problem_object(embedded_value)
        else
            _parse_lmi_problem_object(embedded_value)
        end
        embedded_hash = embedded isa BlockLMIProblem ?
                        block_lmi_problem_hash(embedded) :
                        lmi_problem_hash(embedded)
        problem_hash = block_lmi_problem_hash(P)
        embedded_hash == problem_hash ||
            throw(ArgumentError("embedded problem hash $embedded_hash does not match problem hash $problem_hash"))
    end

    if haskey(parsed, :solution)
        solution = _require_key(parsed, :solution, "root")
        _require_object(solution, "solution")
        solution_type = _require_string(solution, :type, "solution.type")
        solution_type == RATIONAL_SOLUTION_TYPE ||
            throw(ArgumentError("solution.type must be `$RATIONAL_SOLUTION_TYPE` for exact rational certification; got `$solution_type`"))
        return _parse_rational_solution(solution, num_variables(P))
    elseif haskey(parsed, :approximate_solution)
        approx = _require_key(parsed, :approximate_solution, "root")
        return _parse_approx_solution_object(P, approx; kwargs...)
    end

    throw(ArgumentError("solution JSON must contain `solution` or `approximate_solution`"))
end

function _read_sos_gram_matrix_solution(problem::SOSGramProblem, path::AbstractString;
                                        reconstruct_floats::Bool=false,
                                        tolerance=nothing,
                                        max_denominator::Integer=DEFAULT_SOS_RATIONAL_RECONSTRUCTION_MAX_DENOMINATOR)
    parsed = try
        JSON3.read(read(path, String))
    catch err
        throw(ArgumentError("invalid SOS Gram solution JSON: $(sprint(showerror, err))"))
    end

    _require_object(parsed, "root")
    if haskey(parsed, :certsdp_version)
        _require_value(parsed, :certsdp_version, LMI_JSON_VERSION, "root.certsdp_version")
    end

    if haskey(parsed, :sos_problem)
        embedded = _parse_sos_gram_problem_object(_require_key(parsed, :sos_problem,
                                                               "root"))
        embedded_hash = sos_gram_problem_hash(embedded)
        problem_hash = sos_gram_problem_hash(problem)
        embedded_hash == problem_hash ||
            throw(ArgumentError("embedded SOS problem hash $embedded_hash does not match problem hash $problem_hash"))
    end

    solution = _require_key(parsed, :solution, "root")
    _require_object(solution, "solution")
    _require_value(solution, :type, SOS_GRAM_SOLUTION_TYPE, "solution.type")
    if haskey(solution, :gram_matrix)
        matrix_value = _require_key(solution, :gram_matrix, "solution")
        if reconstruct_floats
            return _parse_reconstructed_sos_gram_matrix(matrix_value,
                                                        length(problem.basis);
                                                        tolerance,
                                                        max_denominator)
        end
        return SymmetricRationalMatrix(_parse_rational_matrix(matrix_value,
                                                              length(problem.basis),
                                                              "solution.gram_matrix");
                                       name=:gram_matrix,)
    elseif haskey(solution, :x)
        return gram_matrix_from_solution(problem,
                                         _parse_rational_solution(solution,
                                                                  num_variables(problem.lmi)))
    end
    throw(ArgumentError("solution must contain `gram_matrix` or triangular coordinate vector `x`"))
end

function _read_sos_gram_candidate_value(problem::SOSGramProblem, path::AbstractString)
    parsed = try
        JSON3.read(read(path, String))
    catch err
        throw(ArgumentError("invalid SOS Gram solution JSON: $(sprint(showerror, err))"))
    end

    _require_object(parsed, "root")
    if haskey(parsed, :certsdp_version)
        _require_value(parsed, :certsdp_version, LMI_JSON_VERSION, "root.certsdp_version")
    end

    if haskey(parsed, :sos_problem)
        embedded = _parse_sos_gram_problem_object(_require_key(parsed, :sos_problem,
                                                               "root"))
        embedded_hash = sos_gram_problem_hash(embedded)
        problem_hash = sos_gram_problem_hash(problem)
        embedded_hash == problem_hash ||
            throw(ArgumentError("embedded SOS problem hash $embedded_hash does not match problem hash $problem_hash"))
    end

    solution = _require_key(parsed, :solution, "root")
    _require_object(solution, "solution")
    _require_value(solution, :type, SOS_GRAM_SOLUTION_TYPE, "solution.type")
    if haskey(solution, :gram_matrix)
        return _require_key(solution, :gram_matrix, "solution")
    elseif haskey(solution, :x)
        return gram_matrix_from_solution(problem,
                                         _parse_rational_solution(solution,
                                                                  num_variables(problem.lmi)))
    end
    throw(ArgumentError("solution must contain `gram_matrix` or triangular coordinate vector `x`"))
end

function _parse_reconstructed_sos_gram_matrix(value, expected_size::Integer;
                                              tolerance,
                                              max_denominator::Integer)
    _require_array(value, "solution.gram_matrix")
    length(value) == expected_size ||
        throw(ArgumentError("solution.gram_matrix has $(length(value)) rows; expected $expected_size"))
    matrix = Matrix{Rational{BigInt}}(undef, expected_size, expected_size)
    for (i, row) in enumerate(value)
        row_path = "solution.gram_matrix[$i]"
        _require_array(row, row_path)
        length(row) == expected_size ||
            throw(ArgumentError("$row_path has $(length(row)) entries; expected $expected_size"))
        for (j, entry) in enumerate(row)
            matrix[i, j] = reconstruct_rational_value(entry;
                                                      tolerance,
                                                      max_denominator,
                                                      path="$row_path[$j]")
        end
    end
    return SymmetricRationalMatrix(matrix; name=:gram_matrix)
end

"""
    inspect_certificate(cert; io=stdout)

Print a concise, non-verifying summary of a parsed certificate.
"""
function inspect_certificate(cert::RationalCertificate; io::IO=stdout)
    println(io, "Certificate: $RATIONAL_CERTIFICATE_TYPE")
    _inspect_problem(cert.problem; io)
    println(io, "Solution: rational")
    if cert.psd_proof.method === Symbol(SCHUR_ZERO_PSD_METHOD)
        pivots = isnothing(cert.psd_proof.schur_zero) ? Int[] :
                 cert.psd_proof.schur_zero.pivot_block
        println(io, "PSD proof: $SCHUR_ZERO_PSD_METHOD (pivot block ", pivots, ")")
    elseif cert.psd_proof.method === Symbol(LDL_PSD_METHOD) ||
           cert.psd_proof.method === Symbol(PIVOTED_LDL_PSD_METHOD)
        pivot_count = isnothing(cert.psd_proof.ldl) ? 0 : length(cert.psd_proof.ldl.pivots)
        println(io, "PSD proof: $(cert.psd_proof.method) ($pivot_count pivots)")
    else
        println(io,
                "PSD proof: $(cert.psd_proof.method) ($(length(cert.psd_proof.principal_minors)) principal minors)")
    end
    println(io, "Problem hash: ", lmi_problem_hash(cert.problem))
    return println(io, "Certificate hash: ", cert.hash)
end

function inspect_certificate(cert::BlockRationalCertificate; io::IO=stdout)
    println(io, "Certificate: $BLOCK_RATIONAL_CERTIFICATE_TYPE")
    println(io, "Problem: $SDPA_PROBLEM_TYPE over $LMI_FIELD")
    println(io, "Blocks: ", num_blocks(cert.problem), " (sizes ",
            join(string.(block_sizes(cert.problem)), ", "), ")")
    println(io, "Variables: ", num_variables(cert.problem), " (",
            join(String.(cert.problem.vars), ", "), ")")
    for (i, proof) in enumerate(cert.psd_proof.block_proofs)
        if proof.method === Symbol(SCHUR_ZERO_PSD_METHOD)
            pivots = isnothing(proof.schur_zero) ? Int[] : proof.schur_zero.pivot_block
            println(io, "Block $i PSD proof: $SCHUR_ZERO_PSD_METHOD (pivot block ",
                    pivots, ")")
        elseif proof.method === Symbol(LDL_PSD_METHOD) ||
               proof.method === Symbol(PIVOTED_LDL_PSD_METHOD)
            pivot_count = isnothing(proof.ldl) ? 0 : length(proof.ldl.pivots)
            println(io, "Block $i PSD proof: $(proof.method) ($pivot_count pivots)")
        else
            println(io, "Block $i PSD proof: $(proof.method) (",
                    length(proof.principal_minors), " principal minors)")
        end
    end
    println(io, "Problem hash: ", block_lmi_problem_hash(cert.problem))
    return println(io, "Certificate hash: ", cert.hash)
end

function inspect_certificate(cert::AlgebraicCertificate; io::IO=stdout)
    println(io, "Certificate: $ALGEBRAIC_CERTIFICATE_TYPE")
    _inspect_problem(cert.problem; io)
    println(io, "Solution: algebraic RUR over root t")
    println(io, "Minimal polynomial: ", cert.root.f)
    println(io, "Root interval: [", _rational_string(cert.root.interval.lower), ", ",
            _rational_string(cert.root.interval.upper), "]")
    println(io, "Coordinates: ", _inspect_coordinates(cert.problem, cert.solution))

    if cert.psd_proof.method === Symbol(SCHUR_ZERO_PSD_METHOD)
        pivots = isnothing(cert.psd_proof.schur_zero) ? Int[] :
                 cert.psd_proof.schur_zero.pivot_block
        println(io, "PSD proof: $SCHUR_ZERO_PSD_METHOD (pivot block ", pivots, ")")
    elseif cert.psd_proof.method === Symbol(LDL_PSD_METHOD) ||
           cert.psd_proof.method === Symbol(PIVOTED_LDL_PSD_METHOD)
        pivot_count = isnothing(cert.psd_proof.ldl) ? 0 : length(cert.psd_proof.ldl.pivots)
        println(io, "PSD proof: $(cert.psd_proof.method) ($pivot_count pivots)")
    else
        println(io,
                "PSD proof: $(cert.psd_proof.method) ($(length(cert.psd_proof.principal_minors)) principal minors)")
    end

    println(io, "Problem hash: ", lmi_problem_hash(cert.problem))
    return println(io, "Certificate hash: ", cert.hash)
end

function inspect_certificate(cert::BlockAlgebraicCertificate; io::IO=stdout)
    println(io, "Certificate: $BLOCK_ALGEBRAIC_CERTIFICATE_TYPE")
    println(io, "Problem: $SDPA_PROBLEM_TYPE over $LMI_FIELD")
    println(io, "Blocks: ", num_blocks(cert.problem), " (sizes ",
            join(string.(block_sizes(cert.problem)), ", "), ")")
    println(io, "Variables: ", num_variables(cert.problem), " (",
            join(String.(cert.problem.vars), ", "), ")")
    println(io, "Solution: algebraic RUR over root t")
    println(io, "Minimal polynomial: ", cert.root.f)
    println(io, "Root interval: [", _rational_string(cert.root.interval.lower), ", ",
            _rational_string(cert.root.interval.upper), "]")
    println(io, "Coordinates: ", _inspect_coordinates(cert.problem, cert.solution))
    for (i, proof) in enumerate(cert.psd_proof.block_proofs)
        if proof.method === Symbol(SCHUR_ZERO_PSD_METHOD)
            pivots = isnothing(proof.schur_zero) ? Int[] : proof.schur_zero.pivot_block
            println(io, "Block $i PSD proof: $SCHUR_ZERO_PSD_METHOD (pivot block ",
                    pivots, ")")
        elseif proof.method === Symbol(LDL_PSD_METHOD) ||
               proof.method === Symbol(PIVOTED_LDL_PSD_METHOD)
            pivot_count = isnothing(proof.ldl) ? 0 : length(proof.ldl.pivots)
            println(io, "Block $i PSD proof: $(proof.method) ($pivot_count pivots)")
        else
            println(io, "Block $i PSD proof: $(proof.method) (",
                    length(proof.principal_minors), " principal minors)")
        end
    end
    println(io, "Problem hash: ", block_lmi_problem_hash(cert.problem))
    return println(io, "Certificate hash: ", cert.hash)
end

function inspect_certificate(cert::SOSGramCertificate; io::IO=stdout)
    println(io, "Certificate: $SOS_GRAM_CERTIFICATE_TYPE")
    println(io, "SOS problem: Gram SDP over $LMI_FIELD")
    println(io, "Polynomial variables: ", length(cert.problem.variables), " (",
            join(String.(cert.problem.variables), ", "), ")")
    println(io, "Gram basis size: ", length(cert.problem.basis))
    println(io, "Polynomial terms: ", length(cert.problem.polynomial))
    println(io, "Coefficient equations: ", length(cert.coefficient_proof))
    println(io, "Decomposition: ", cert.decomposition.status)
    println(io, "PSD proof: embedded $RATIONAL_CERTIFICATE_TYPE")
    println(io, "SOS problem hash: ", sos_gram_problem_hash(cert.problem))
    return println(io, "Certificate hash: ", cert.hash)
end

function inspect_certificate(cert::RationalFunctionSOSCertificate; io::IO=stdout)
    println(io, "Certificate: $RATIONAL_FUNCTION_SOS_CERTIFICATE_TYPE")
    println(io, "Polynomial variables: ", length(cert.variables), " (",
            join(String.(cert.variables), ", "), ")")
    println(io, "Target polynomial terms: ", length(cert.target))
    println(io, "Numerator SOS squares: ", length(cert.numerator_squares))
    println(io, "Denominator SOS squares: ", length(cert.denominator_squares))
    println(io, "Coefficient equations: ", length(cert.coefficient_proof))
    println(io, "Problem hash: ", rational_function_sos_problem_hash(cert))
    return println(io, "Certificate hash: ", cert.hash)
end

function inspect_certificate(cert::PositivstellensatzCertificate; io::IO=stdout)
    println(io, "Certificate: $POSITIVSTELLENSATZ_CERTIFICATE_TYPE")
    println(io, "Polynomial variables: ", length(cert.variables), " (",
            join(String.(cert.variables), ", "), ")")
    println(io, "Target polynomial terms: ", length(cert.target))
    println(io, "Constraints: ", length(cert.constraints))
    println(io, "SOS multiplier terms: ", length(cert.terms))
    println(io, "Coefficient equations: ", length(cert.coefficient_proof))
    println(io, "Problem hash: ", positivstellensatz_problem_hash(cert))
    return println(io, "Certificate hash: ", cert.hash)
end

function _inspect_problem(P::LMIProblem; io::IO)
    println(io, "Problem: $LMI_PROBLEM_TYPE over $LMI_FIELD")
    println(io, "Matrix size: ", matrix_size(P))
    return println(io, "Variables: ", num_variables(P), " (", join(String.(P.vars), ", "),
                   ")")
end

function _inspect_coordinates(P::LMIProblem, solution::Vector{AlgebraicElement})
    parts = String[]
    for (var, value) in zip(P.vars, solution)
        push!(parts, string(var, "=", algebraic_element_string(value)))
    end
    return join(parts, ", ")
end

function _inspect_coordinates(P::BlockLMIProblem, solution::Vector{AlgebraicElement})
    parts = String[]
    for (var, value) in zip(P.vars, solution)
        push!(parts, string(var, "=", algebraic_element_string(value)))
    end
    return join(parts, ", ")
end

function _print_certification_failure(failure::CertificationFailure, io::IO)
    println(io, "[FAIL] certification failed at $(failure.stage): $(failure.message)")
    println(io, "[FAIL] failure type: $(failure_type(failure))")
    println(io, "[FAIL] reason: $(failure.reason)")
    for (key, value) in sort!(collect(failure.diagnostics); by=first)
        println(io, "[INFO] $(key): $(_cli_diagnostic_string(value))")
    end
end

function _print_failure_diagnosis(failure::CertificationFailure; io::IO=stdout)
    report = failure_report_json(failure)
    println(io, "CertSDP failure diagnosis")
    println(io, "Status: ", report.status)
    println(io, "Failure type: ", report.failure_type)
    println(io, "Reason: ", report.reason)
    println(io, "Stage: ", report.stage)
    println(io, "Summary: ", report.summary)
    println(io, "Key data:")
    details = report.details
    if isempty(details)
        println(io, "  (none)")
    else
        for key in sort!(collect(keys(details)))
            println(io, "  ", key, ": ", _cli_diagnostic_string(details[key]))
        end
    end
    println(io, "Suggested next steps:")
    for suggestion in report.suggestions
        println(io, "  - ", suggestion)
    end
end

function _cli_exit_for_failure(failure::CertificationFailure)
    if failure isa BackendTimeoutFailure
        return CLI_EXIT_TIMEOUT
    elseif failure isa BackendFailure
        backend_reason = get(failure.diagnostics, :backend_reason, nothing)
        backend_reason in (:timeout, "timeout") && return CLI_EXIT_TIMEOUT
        backend_failure = get(failure.diagnostics, :backend_failure, nothing)
        if backend_failure isa AlgebraicBackendFailure
            backend_failure.reason === :timeout && return CLI_EXIT_TIMEOUT
            backend_failure.reason === :unavailable && return CLI_EXIT_BACKEND_UNAVAILABLE
        end
        backend_reason in (:unavailable, "unavailable") &&
            return CLI_EXIT_BACKEND_UNAVAILABLE
        return CLI_EXIT_BACKEND_UNAVAILABLE
    elseif failure isa NumericalFailure
        return CLI_EXIT_INVALID_INPUT
    end
    return CLI_EXIT_NOT_CERTIFIED
end

function _cli_diagnostic_string(value)
    json_ready = _certification_diagnostics_json(value)
    if json_ready isa AbstractDict || json_ready isa AbstractVector
        return JSON3.write(json_ready)
    end
    return string(json_ready)
end

function _print_approx_diagnosis(approx::ApproxSolution; io::IO)
    report = approx.quality_report
    println(io, "CertSDP approximate solution diagnosis")
    println(io, "Problem hash: ", report.problem_hash)
    println(io, "Solver: ", report.solver_name, " (status: ", report.solver_status, ")")
    println(io, "Precision bits: ", report.precision_bits)
    println(io, "Residual: ", report.residual)
    println(io, "Linear residual: ", report.linear_residual)
    println(io, "Symmetry residual: ", report.symmetry_residual)
    println(io, "Minimum eigenvalue: ", report.min_eigenvalue)
    println(io, "PSD violation: ", report.psd_violation)
    println(io, "Trace: ", report.trace_value)
    println(io, "Rank estimate: ", report.rank_estimate)
    println(io, "Rank confidence: ", report.rank_confidence)
    println(io, "Rank gap: ", report.rank_gap)
    println(io, "Eigenvalue gap: ", report.eigenvalue_gap)
    println(io, "Face clarity: ", report.face_clarity)
    println(io, "Face clarity score: ", report.face_clarity_score)
    println(io, "Objective kind: ", report.objective_kind)
    if approx.rank_profile isa RankProfile
        println(io, "Pivot columns: ", approx.rank_profile.pivot_cols)
        println(io, "Pivot rows: ", approx.rank_profile.pivot_rows)
    else
        profile = approx.rank_profile
        println(io, "Rank instability reason: ", profile.reason)
        println(io, "Candidate rank: ", profile.candidate_rank)
        println(io, "Singular values: ", join(string.(profile.singular_values), ", "))
    end
    !isnothing(report.primal_residual) &&
        println(io, "Solver primal residual: ", report.primal_residual)
    !isnothing(report.dual_residual) &&
        println(io, "Solver dual residual: ", report.dual_residual)
    !isnothing(report.objective_value) &&
        println(io, "Objective value: ", report.objective_value)
    if haskey(approx.oracle_metadata, :attempts)
        println(io, "Solver attempts: ", length(approx.oracle_metadata[:attempts]))
        println(io, "Selected attempt: ", report.attempt_index)
    end
    println(io, "Recommendation: ", approx_quality_report_json(report).recommendation)
    if approx.rank_profile isa RankProfile
        return println(io, "[OK] approximate rank profile is stable")
    end
    return println(io, "[FAIL] approximate rank profile is unstable")
end

function _print_solve_summary(approx::ApproxSolution; io::IO)
    report = approx.quality_report
    summary = max_rank_workflow_summary(approx)
    println(io, "CertSDP numerical solve summary")
    println(io, "Solver: ", report.solver_name, " (status: ", report.solver_status, ")")
    println(io, "Objective kind: ", report.objective_kind)
    println(io, "Selected attempt: ", summary.selected_attempt, " of ",
            summary.attempt_count)
    println(io, "Rank estimate: ", report.rank_estimate)
    println(io, "Rank confidence: ", report.rank_confidence)
    println(io, "Face clarity: ", report.face_clarity)
    println(io, "Residual: ", report.residual)
    println(io, "PSD violation: ", report.psd_violation)
    println(io, "Trace: ", report.trace_value)
    return println(io, "Recommendation: ",
                   approx_quality_report_json(report).recommendation)
end

function _cli_usage(io::IO)
    _print_cli_usage(io)
    return CLI_EXIT_USAGE
end

function _print_cli_usage(io::IO)
    println(io, "usage:")
    _print_doctor_usage(io)
    _print_solve_usage(io)
    _print_solve_certify_usage(io)
    _print_certify_usage(io)
    _print_certify_sos_usage(io)
    _print_certify_auto_sos_usage(io)
    _print_explain_usage(io)
    _print_bundle_usage(io)
    _print_replay_usage(io)
    _print_import_usage(io)
    _print_schema_usage(io)
    _print_migrate_usage(io)
    _print_export_sos_usage(io)
    _print_convert_sostools_usage(io)
    _print_diagnose_usage(io)
    _print_benchmark_usage(io)
    _print_verify_usage(io)
    return _print_inspect_usage(io)
end

function _print_import_usage(io::IO)
    return println(io,
                   "  certsdp import tssos artifact.json --out candidate.json\n  certsdp import sdpa file.dat-s --out problem.json\n  certsdp import nctssos artifact.json --out candidate.json")
end

function _print_doctor_usage(io::IO)
    return println(io,
                   "  certsdp doctor [--benchmarks benchmarks/]")
end

function _print_solve_usage(io::IO)
    return println(io,
                   "  certsdp solve problem.json --out approx.json [--solver clarabel] [--trace-objective maximize|false|both] [--random-objective-trials n] [--solver-attempts n] [--require-stable-rank]")
end

function _print_solve_certify_usage(io::IO)
    return println(io,
                   "  certsdp solve-certify problem.json --out approx.json --cert-out cert.json [solve options] [certify options]")
end

function _print_certify_usage(io::IO)
    return println(io,
                   "  certsdp certify problem.json --solution approx.json --out cert.json [--budget validation] [--timeout seconds] [--algebraic-backend msolve|sage_msolve] [--psd-method auto|principal_minors|schur_zero|ldl|pivoted_ldl] [--save-artifacts dir] [--backend-cache dir] [--slicing auto|none|user] [--slice-file file]")
end

function _print_certify_sos_usage(io::IO)
    return println(io,
                   "  certsdp certify-sos sos_gram.json --solution gram_solution.json --out cert.json [--reconstruct-floats --reconstruction-tolerance tol]")
end

function _print_certify_auto_sos_usage(io::IO)
    return println(io,
                   "  certsdp certify-auto-sos sos_gram.json --solution gram_solution.json --out cert.json [--strategies direct,sos_round_project] [--tolerance tol] [--max-denominator n]")
end

function _print_explain_usage(io::IO)
    return println(io,
                   "  certsdp explain failure.json [--max-lines 30]\n  certsdp explain artifact.json")
end

function _print_bundle_usage(io::IO)
    return println(io,
                   "  certsdp bundle cert.json --out artifact.zip [--problem problem.json] [--approx approx.json] [--report report.txt] [--logs backend_artifacts/] [--redact|--no-redact]\n  certsdp bundle verify bundle/")
end

function _print_replay_usage(io::IO)
    return println(io,
                   "  certsdp replay certificate.json --strict [--explain|--json]\n  certsdp replay artifact.zip [--extract-dir dir]")
end

function _print_schema_usage(io::IO)
    return println(io,
                   "  certsdp schema validate input.json [--kind problem|certificate|failure|auto]\n  certsdp schema migrate input.json --out output.json [--kind problem|certificate|auto]")
end

function _print_migrate_usage(io::IO)
    return println(io,
                   "  certsdp migrate input.json --out output.json [--kind problem|certificate|auto]")
end

function _print_export_sos_usage(io::IO)
    return println(io,
                   "  certsdp export-sos cert.json --out decomposition.json [--format json|text|latex|sage|julia]")
end

function _print_convert_sostools_usage(io::IO)
    return println(io,
                   "  certsdp convert-sostools sostools_lite.json [--problem-out sos_gram.json] [--solution-out gram_solution.json] [--cert-out cert.json]")
end

function _print_diagnose_usage(io::IO)
    return println(io,
                   "  certsdp diagnose certificate.json --format text|json|html [--out report.html]\n  certsdp diagnose failure.json\n  certsdp diagnose problem.json --solution approx.json [--rank-relative-tolerance tol] [--rank-gap-threshold gap]")
end

function _print_diagnose_approx_usage(io::IO)
    return println(io,
                   "  certsdp diagnose-approx problem.json --solution approx.json [--rank-relative-tolerance tol] [--rank-gap-threshold gap]")
end

function _print_benchmark_usage(io::IO)
    return println(io,
                   "  certsdp benchmark [benchmarks/] --suite validation [--budget validation] [--timeout seconds] [--out report.md] [--generated-dir dir]")
end

function _print_verify_usage(io::IO)
    return println(io, "  certsdp verify [--strict] cert.json")
end

function _print_inspect_usage(io::IO)
    println(io, "  certsdp inspect cert.json")
    return println(io, "  certsdp version --json")
end
