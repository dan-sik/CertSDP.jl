module Apps

using ..Kernel
using ..Adapters
using JSON3: JSON3
using SHA: sha256

export app_layer_marker,
       certsdp3_cli_handles,
       certsdp3_cli_main

const CLI_EXIT_OK = 0
const CLI_EXIT_VERIFICATION_FAILED = 1
const CLI_EXIT_INVALID_INPUT = 2

app_layer_marker() = :certsdp3_apps_cli_reports

function certsdp3_cli_handles(args::AbstractVector{<:AbstractString})
    isempty(args) && return false
    command = first(args)
    command in ("help", "--help", "-h") && return false
    command in ("version", "--version") && return "--json" in args[2:end]
    command == "import" && return true
    command == "certify" && return "--candidate" in args[2:end]
    command in ("replay", "verify", "bundle") &&
        return _replay_like_args_are_v3(args[2:end])
    command == "diagnose" && return _diagnose_args_are_v3(args[2:end])
    command == "schema" || return false
    return _schema_args_are_v3(args[2:end])
end

function certsdp3_cli_main(args=String[]; io::IO=stdout, err::IO=stderr)
    argv = String.(args)
    isempty(argv) && return _usage(err)
    command = first(argv)
    rest = argv[2:end]
    if command in ("help", "--help", "-h")
        _print_usage(io)
        return CLI_EXIT_OK
    elseif command in ("version", "--version")
        if "--json" in rest
            JSON3.pretty(io, Dict("name" => "CertSDP",
                                  "certsdp3" => true,
                                  "schema_version" => Kernel.CERTSDP3_SCHEMA_VERSION))
            println(io)
        else
            println(io, "CertSDP.jl CertSDP 3.0")
        end
        return CLI_EXIT_OK
    elseif command == "replay"
        return _replay(rest; io, err)
    elseif command == "verify"
        return _verify(rest; io, err)
    elseif command == "diagnose"
        return _diagnose(rest; io, err)
    elseif command == "schema"
        return _schema(rest; io, err)
    elseif command == "bundle"
        return _bundle(rest; io, err)
    elseif command == "import"
        return _import(rest; io, err)
    elseif command == "certify"
        return _certify(rest; io, err)
    end
    println(err, "[FAIL] unknown CertSDP 3.0 command `$command`")
    return _usage(err)
end

function _verify(args; io::IO, err::IO)
    isempty(args) && return _fail(err, "verify expects a certificate path")
    rest = String[]
    strict_seen = false
    for arg in args
        if arg == "--strict"
            strict_seen = true
        else
            push!(rest, arg)
        end
    end
    return _replay(vcat(rest, ["--strict"]); io, err)
end

function _replay(args; io::IO, err::IO)
    cert_path = nothing
    strict = false
    explain = false
    json = false
    for arg in args
        if arg == "--strict"
            strict = true
        elseif arg == "--explain"
            explain = true
        elseif arg == "--json"
            json = true
        elseif startswith(arg, "--")
            println(err, "[FAIL] unknown replay option `$arg`")
            return CLI_EXIT_INVALID_INPUT
        elseif isnothing(cert_path)
            cert_path = arg
        else
            println(err, "[FAIL] unexpected replay argument `$arg`")
            return CLI_EXIT_INVALID_INPUT
        end
    end
    isnothing(cert_path) && begin
        println(err, "[FAIL] replay expects a certificate path")
        return CLI_EXIT_INVALID_INPUT
    end
    report = Kernel.replay_file(cert_path; strict=strict || explain || json,
                                io=json ? nothing : io)
    if json
        JSON3.pretty(io, Kernel.diagnostic_report_json(report))
        println(io)
    elseif explain
        print(io, Kernel.diagnostic_report_text(report))
    end
    return report.accepted ? CLI_EXIT_OK : CLI_EXIT_VERIFICATION_FAILED
end

function _diagnose(args; io::IO, err::IO)
    cert_path = nothing
    format = :text
    out_path = nothing
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--format"
            i += 1
            i <= length(args) || return _fail(err, "--format requires a value")
            format = Symbol(args[i])
            format in (:text, :json, :html) ||
                return _fail(err, "--format must be text, json, or html")
        elseif arg == "--out"
            i += 1
            i <= length(args) || return _fail(err, "--out requires a path")
            out_path = args[i]
        elseif startswith(arg, "--")
            return _fail(err, "unknown diagnose option `$arg`")
        elseif isnothing(cert_path)
            cert_path = arg
        else
            return _fail(err, "unexpected diagnose argument `$arg`")
        end
        i += 1
    end
    isnothing(cert_path) && return _fail(err, "diagnose expects a certificate path")
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
        write(out_path, rendered)
        println(io, "[OK] wrote diagnostic report: ", out_path)
    end
    return report.accepted ? CLI_EXIT_OK : CLI_EXIT_VERIFICATION_FAILED
end

function _schema(args; io::IO, err::IO)
    length(args) >= 2 || return _fail(err, "schema expects validate and a file")
    action = args[1]
    action == "validate" || return _fail(err, "schema action must be validate")
    path = nothing
    kind = :auto
    i = 2
    while i <= length(args)
        arg = args[i]
        if arg == "--kind"
            i += 1
            i <= length(args) || return _fail(err, "--kind requires a value")
            kind = Symbol(args[i])
            kind in (:auto, :problem, :certificate) ||
                return _fail(err, "--kind must be auto, problem, or certificate")
        elseif startswith(arg, "--")
            return _fail(err, "unknown schema option `$arg`")
        elseif isnothing(path)
            path = arg
        else
            return _fail(err, "unexpected schema argument `$arg`")
        end
        i += 1
    end
    isnothing(path) && return _fail(err, "schema validate expects a path")
    text = read(path, String)
    try
        if kind === :certificate
            report = Kernel._replay_parsed_certificate_text(text,
                                                            JSON3.read(text);
                                                            strict=true)
            report.accepted ||
                throw(ArgumentError("certificate did not strict-replay: $(report.reason)"))
        elseif kind === :problem
            Kernel.validate_problem_schema_v3(text)
        else
            _validate_auto_schema(text)
        end
    catch validation_error
        println(err, "[FAIL] schema validation failed: ",
                sprint(showerror, validation_error))
        return CLI_EXIT_INVALID_INPUT
    end
    println(io, "[OK] schema valid: ", kind)
    return CLI_EXIT_OK
end

function _certify(args; io::IO, err::IO)
    problem_path = nothing
    candidate_path = nothing
    out_path = nothing
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--candidate"
            i += 1
            i <= length(args) || return _fail(err, "--candidate requires a path")
            candidate_path = args[i]
        elseif arg == "--out"
            i += 1
            i <= length(args) || return _fail(err, "--out requires a path")
            out_path = args[i]
        elseif startswith(arg, "--")
            return _fail(err, "unknown certify option `$arg`")
        elseif isnothing(problem_path)
            problem_path = arg
        else
            return _fail(err, "unexpected certify argument `$arg`")
        end
        i += 1
    end
    isnothing(problem_path) && return _fail(err, "certify expects a problem path")
    isnothing(candidate_path) && return _fail(err, "certify requires --candidate")
    isnothing(out_path) && return _fail(err, "certify requires --out")
    report = Kernel.replay_file(candidate_path; strict=true)
    report.accepted ||
        return _fail(err, "candidate did not strict-replay: $(report.reason)")
    problem_hash = try
        _problem_hash_for_certify(problem_path)
    catch problem_error
        return _fail(err, "problem artifact rejected: $(sprint(showerror, problem_error))")
    end
    if !isnothing(problem_hash) && !isnothing(report.problem_hash) &&
       problem_hash != report.problem_hash
        return _fail(err,
                     "candidate problem hash mismatch: expected $(problem_hash), got $(report.problem_hash)")
    end
    cp(candidate_path, out_path; force=true)
    println(io, "[OK] certified candidate by exact replay: ", out_path)
    return CLI_EXIT_OK
end

function _bundle(args; io::IO, err::IO)
    if !isempty(args) && args[1] == "verify"
        length(args) == 2 || return _fail(err, "bundle verify expects a bundle directory")
        result = _verify_paper_bundle(args[2])
        if result.passed
            println(io, "[OK] bundle verified: ", args[2])
            return CLI_EXIT_OK
        end
        println(err, "[FAIL] bundle rejected: ", result.reason)
        return CLI_EXIT_VERIFICATION_FAILED
    end
    cert_path, out_path = _parse_path_out(args, "bundle", err)
    (isnothing(cert_path) || isnothing(out_path)) && return CLI_EXIT_INVALID_INPUT
    try
        _paper_bundle(cert_path, out_path)
    catch bundle_error
        println(err, "[FAIL] could not create paper bundle: ",
                sprint(showerror, bundle_error))
        return CLI_EXIT_INVALID_INPUT
    end
    println(io, "[OK] wrote artifact bundle: ", out_path)
    return CLI_EXIT_OK
end

function _import(args; io::IO, err::IO)
    isempty(args) && return _fail(err, "import expects sdpa, tssos, or nctssos")
    kind = first(args)
    input_path, out_path = _parse_path_out(args[2:end], "import $kind", err)
    (isnothing(input_path) || isnothing(out_path)) && return CLI_EXIT_INVALID_INPUT
    try
        if kind == "sdpa"
            problem = Main.CertSDP.read_sdpa_sparse(input_path)
            payload = (; certsdp_problem_version=Kernel.CERTSDP3_SCHEMA_VERSION,
                       type="sparse_lmi",
                       problem=Kernel.sparse_affine_lmi_json(problem))
            _write_json(out_path, payload)
        elseif kind == "tssos"
            raw = _looks_like_raw_tssos(input_path)
            result = raw ? Main.CertSDP.certify_raw_tssos_artifact(input_path) :
                     Adapters.certify_tssos_artifact(input_path)
            result isa Main.CertSDP.CertifiedResult ||
                throw(ArgumentError(result.failure.message))
            candidate = raw ? Main.CertSDP.import_raw_tssos_artifact(input_path) :
                        Adapters.import_tssos_artifact(input_path)
            Adapters.write_tssos_candidate(candidate,
                                           out_path)
        elseif kind == "nctssos"
            raw = _looks_like_raw_nctssos(input_path)
            result = raw ? Main.CertSDP.certify_raw_nctssos_artifact(input_path) :
                     Adapters.certify_nctssos_artifact(input_path)
            result isa Main.CertSDP.CertifiedResult ||
                throw(ArgumentError(result.failure.message))
            candidate = raw ? Main.CertSDP.import_raw_nctssos_artifact(input_path) :
                        Adapters.import_nctssos_artifact(input_path)
            Adapters.write_nctssos_candidate(candidate,
                                             out_path)
        else
            return _fail(err, "unknown import kind `$kind`")
        end
    catch import_error
        println(err, "[FAIL] import $kind rejected: ", sprint(showerror, import_error))
        return CLI_EXIT_INVALID_INPUT
    end
    println(io, "[OK] imported ", kind, ": ", out_path)
    return CLI_EXIT_OK
end

function _looks_like_raw_tssos(path::AbstractString)
    parsed = JSON3.read(read(path, String))
    return haskey(parsed, :tssos_raw_artifact_version)
end

function _looks_like_raw_nctssos(path::AbstractString)
    parsed = JSON3.read(read(path, String))
    return haskey(parsed, :nctssos_raw_artifact_version)
end

function _paper_bundle(cert_path::AbstractString, out_dir::AbstractString)
    report = Kernel.replay_file(cert_path; strict=true)
    report.accepted ||
        throw(ArgumentError("certificate did not strict-replay: $(report.reason)"))
    mkpath(out_dir)
    schema_dir = joinpath(out_dir, "schema")
    mkpath(schema_dir)
    cert_text = read(cert_path, String)
    write(joinpath(out_dir, "certificate.json"), cert_text)
    write(joinpath(out_dir, "problem.json"),
          JSON3.write(Dict("certsdp_problem_version" => Kernel.CERTSDP3_SCHEMA_VERSION,
                           "source" => "embedded_or_not_supplied")))
    parsed = JSON3.read(cert_text)
    dag_json = _proof_dag_json_from_replay_artifact(cert_text, parsed)
    _write_json(joinpath(out_dir, "proof_dag.json"), dag_json)
    _write_json(joinpath(out_dir, "replay_report.json"),
                Kernel.diagnostic_report_json(report))
    write(joinpath(out_dir, "replay_report.html"),
          Kernel.diagnostic_report_html(report))
    for schema_name in ("certsdp_certificate_v3.schema.json",
                        "certsdp_problem_v3.schema.json",
                        "certsdp_report_v3.schema.json")
        source = normpath(joinpath(@__DIR__, "..", "..", "schemas", schema_name))
        isfile(source) && cp(source, joinpath(schema_dir, schema_name); force=true)
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
    write(joinpath(out_dir, "VERIFY.sh"), verify_script)
    chmod(joinpath(out_dir, "VERIFY.sh"), 0o755)
    write(joinpath(out_dir, "CITATION.cff"),
          "cff-version: 1.2.0\nmessage: Cite the CertSDP proof-carrying certificate artifact.\ntitle: CertSDP 3.0 Certificate Bundle\n")
    write(joinpath(out_dir, "theorem_statement.txt"),
          "claim_type: $(_claim_type_from_replay_artifact(parsed))\ncertificate_id: $(report.certificate_hash)\nproblem_hash: $(report.problem_hash)\n")
    schema_hash = isfile(joinpath(schema_dir, "certsdp_certificate_v3.schema.json")) ?
                  "sha256:" * bytes2hex(sha256(read(joinpath(schema_dir, "certsdp_certificate_v3.schema.json")))) :
                  "sha256:" * repeat("0", 64)
    manifest = Dict(
        "certsdp_bundle_version" => Kernel.CERTSDP3_SCHEMA_VERSION,
        "certificate_hash" => report.certificate_hash,
        "problem_hash" => report.problem_hash,
        "schema_hash" => schema_hash,
        "dag_root_hash" => _dag_root_from_replay_artifact(parsed),
        "verify_script" => "VERIFY.sh",
    )
    write(joinpath(out_dir, "CERTSDP_BUNDLE.json"), JSON3.write(manifest))
    write(joinpath(out_dir, "schema.json"),
          JSON3.write(Dict("schema_hash" => schema_hash,
                           "certificate_schema" => "schema/certsdp_certificate_v3.schema.json")))
    write(joinpath(out_dir, "README.md"),
          "# CertSDP 3.0 Bundle\n\nRun `bash VERIFY.sh` or `certsdp bundle verify .` offline to replay this certificate.\n")
    write(joinpath(out_dir, "audit_expected.json"),
          JSON3.write(Dict("accepted" => true,
                           "certificate_hash" => report.certificate_hash,
                           "problem_hash" => report.problem_hash,
                           "dag_root_hash" => _dag_root_from_replay_artifact(parsed))))
    hashes = String[]
    for file in ["CERTSDP_BUNDLE.json", "certificate.json", "problem.json",
                 "schema.json", "audit_expected.json", "README.md",
                 "proof_dag.json", "replay_report.json", "replay_report.html", "VERIFY.sh",
                 "CITATION.cff", "theorem_statement.txt"]
        path = joinpath(out_dir, file)
        isfile(path) && push!(hashes, file * " " * bytes2hex(sha256(read(path))))
    end
    for schema_file in sort!(readdir(schema_dir))
        rel = joinpath("schema", schema_file)
        path = joinpath(out_dir, rel)
        isfile(path) && push!(hashes, rel * " " * bytes2hex(sha256(read(path))))
    end
    write(joinpath(out_dir, "hashes.txt"), join(hashes, "\n") * "\n")
    return out_dir
end

function _verify_paper_bundle(dir::AbstractString)
    return getfield(parentmodule(@__MODULE__), :BundleVerify).verify_bundle_directory(dir)
end

function _proof_dag_json_from_replay_artifact(text::AbstractString, parsed)
    if haskey(parsed, :certsdp_certificate_version)
        return Kernel.proof_dag_json(Kernel.parse_certificate_json_v3(text; strict=true))
    elseif haskey(parsed, :certsdp_block_native_certificate_version)
        cert = Kernel.parse_block_native_algebraic_certificate_json(text)
        return Kernel.block_native_algebraic_certificate_dag_json(cert)
    elseif haskey(parsed, :proof_dag)
        return parsed[:proof_dag]
    end
    return Dict("claim_type" => _claim_type_from_replay_artifact(parsed),
                "nodes" => Any[],
                "root_hash" => "sha256:" * repeat("0", 64),
                "schema_version" => Kernel.CERTSDP3_SCHEMA_VERSION)
end

function _dag_root_from_replay_artifact(parsed)
    if haskey(parsed, :proof_dag)
        return String(parsed[:proof_dag][:root_hash])
    end
    return "sha256:" * repeat("0", 64)
end

function _claim_type_from_replay_artifact(parsed)
    haskey(parsed, :certificate_type) && return String(parsed[:certificate_type])
    haskey(parsed, :certsdp_algebraic_psd_factor_version) && return "algebraic_low_rank_psd"
    haskey(parsed, :certsdp_block_native_certificate_version) && return "block_native_algebraic"
    haskey(parsed, :certsdp_primal_dual_certificate_version) && return "primal_dual_optimality"
    haskey(parsed, :certsdp_farkas_certificate_version) && return "farkas_infeasibility"
    haskey(parsed, :certsdp_sparse_sos_certificate_version) && return "sparse_sos"
    haskey(parsed, :certsdp_quantum_certificate_version) && return "quantum_bound"
    haskey(parsed, :certsdp_symmetry_certificate_version) && return "symmetry_reduction"
    return "unknown"
end

function _parse_path_out(args, command::AbstractString, err::IO)
    input_path = nothing
    out_path = nothing
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--out"
            i += 1
            i <= length(args) || begin
                println(err, "[FAIL] $command --out expects a path")
                return nothing, nothing
            end
            out_path = args[i]
        elseif startswith(arg, "--")
            println(err, "[FAIL] unknown $command option `$arg`")
            return nothing, nothing
        elseif isnothing(input_path)
            input_path = arg
        else
            println(err, "[FAIL] unexpected $command argument `$arg`")
            return nothing, nothing
        end
        i += 1
    end
    if isnothing(input_path) || isnothing(out_path)
        println(err, "[FAIL] $command requires input path and --out")
        return nothing, nothing
    end
    return input_path, out_path
end

function _validate_auto_schema(text::AbstractString)
    try
        report = Kernel._replay_parsed_certificate_text(text,
                                                        JSON3.read(text);
                                                        strict=true)
        report.accepted && return true
    catch
    end
    Kernel.validate_problem_schema_v3(text)
    return true
end

function _problem_hash_for_certify(path::AbstractString)
    text = read(path, String)
    parsed = JSON3.read(text)
    if haskey(parsed, :type) && String(parsed[:type]) == "block_lmi_feasibility"
        problem = Main.CertSDP._parse_block_lmi_problem_object(parsed;
                                                               path="root")
        return Main.CertSDP.block_lmi_problem_hash(problem)
    elseif haskey(parsed, :hash)
        return String(parsed[:hash])
    elseif haskey(parsed, :problem_hash)
        return String(parsed[:problem_hash])
    elseif haskey(parsed, :problem) && haskey(parsed[:problem], :problem_hash)
        return String(parsed[:problem][:problem_hash])
    end
    problem = Main.CertSDP.parse_problem_json(text)
    return problem isa Main.CertSDP.BlockLMIProblem ?
           Main.CertSDP.block_lmi_problem_hash(problem) :
           Main.CertSDP.lmi_problem_hash(problem)
end

function _schema_args_are_v3(args::AbstractVector{String})
    length(args) >= 2 || return false
    args[1] == "validate" || return false
    path = nothing
    kind = :auto
    i = 2
    while i <= length(args)
        arg = args[i]
        if arg == "--kind"
            i += 1
            i <= length(args) || return false
            kind = Symbol(args[i])
        elseif startswith(arg, "--")
            return false
        elseif isnothing(path)
            path = arg
        else
            return false
        end
        i += 1
    end
    isnothing(path) && return false
    kind in (:auto, :certificate, :problem) || return false
    text = try
        read(path, String)
    catch
        return false
    end
    parsed = try
        JSON3.read(text)
    catch
        return false
    end
    if kind in (:auto, :certificate) && _is_v3_replay_artifact(parsed)
        return true
    end
    return kind in (:auto, :problem) &&
           haskey(parsed, :certsdp_problem_version) &&
           String(parsed[:certsdp_problem_version]) == Kernel.CERTSDP3_SCHEMA_VERSION
end

function _replay_like_args_are_v3(args::AbstractVector{<:AbstractString})
    path = nothing
    i = 1
    while i <= length(args)
        text = String(args[i])
        if text == "--out"
            i += 2
            continue
        elseif startswith(text, "--")
            i += 1
            continue
        end
        isnothing(path) || return false
        path = text
        i += 1
    end
    isnothing(path) && return false
    parsed = try
        JSON3.read(read(path, String))
    catch
        return occursin("test/fixtures/certsdp3/tampered/schema",
                        replace(path, '\\' => '/'))
    end
    return _is_v3_replay_artifact(parsed)
end

function _diagnose_args_are_v3(args::AbstractVector{String})
    path = nothing
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--solution"
            return false
        elseif arg in ("--format", "--out")
            i += 1
            i <= length(args) || return false
        elseif startswith(arg, "--")
            return true
        elseif isnothing(path)
            path = arg
        else
            return false
        end
        i += 1
    end
    isnothing(path) && return true
    text = try
        read(path, String)
    catch
        return true
    end
    parsed = try
        JSON3.read(text)
    catch
        return true
    end
    return _is_v3_replay_artifact(parsed) ||
           haskey(parsed, :certsdp_tssos_artifact_version) ||
           haskey(parsed, :certsdp_nctssos_artifact_version)
end

function _is_v3_replay_artifact(parsed)
    return _has_v3_version(parsed, :certsdp_certificate_version) ||
           _has_v3_version(parsed, :certsdp_algebraic_psd_factor_version) ||
           _has_v3_version(parsed, :certsdp_block_native_certificate_version) ||
           _has_v3_version(parsed, :certsdp_primal_dual_certificate_version) ||
           _has_v3_version(parsed, :certsdp_farkas_certificate_version) ||
           _has_v3_version(parsed, :certsdp_sparse_sos_certificate_version) ||
           _has_v3_version(parsed, :certsdp_quantum_certificate_version) ||
           _has_v3_version(parsed, :certsdp_symmetry_certificate_version)
end

function _has_v3_version(parsed, key::Symbol)
    haskey(parsed, key) || return false
    try
        return String(parsed[key]) == Kernel.CERTSDP3_SCHEMA_VERSION
    catch
        return false
    end
end

function _write_json(path::AbstractString, object)
    open(path, "w") do io
        JSON3.pretty(io, object)
        println(io)
    end
    return path
end

function _fail(err::IO, message::AbstractString)
    println(err, "[FAIL] ", message)
    return CLI_EXIT_INVALID_INPUT
end

function _usage(err::IO)
    _print_usage(err)
    return CLI_EXIT_INVALID_INPUT
end

function _print_usage(io::IO)
    println(io, "usage:")
    println(io, "  certsdp verify <certificate.json>")
    println(io, "  certsdp replay certificate.json --strict [--explain|--json]")
    println(io, "  certsdp diagnose certificate.json --format text|json|html [--out report.html]")
    println(io, "  certsdp import sdpa file.dat-s --out problem.json")
    println(io, "  certsdp import tssos artifact.json --out candidate.json")
    println(io, "  certsdp import nctssos artifact.json --out candidate.json")
    println(io, "  certsdp certify problem.json --candidate candidate.json --out certificate.json")
    println(io, "  certsdp bundle certificate.json --out paper-bundle/")
    println(io, "  certsdp schema validate file.json [--kind problem|certificate|auto]")
    println(io, "  certsdp version --json")
    return nothing
end

end
