using Base: Sys

const REPLAY_BUNDLE_VERSION = "1.0"
const REPLAY_BUNDLE_MANIFEST = "manifest.json"
const REPLAY_BUNDLE_CERTIFICATE = "certificate/cert.json"
const REPLAY_BUNDLE_PROBLEM = "problem/problem.json"
const REPLAY_BUNDLE_APPROX = "approx/approx.json"
const REPLAY_BUNDLE_REPORT = "reports/verification_report.txt"
const REPLAY_BUNDLE_VERSIONS = "versions/versions.json"
const REPLAY_BUNDLE_README = "README.md"

struct ReplayBundleError <: Exception
    message::String
end

Base.showerror(io::IO, err::ReplayBundleError) = print(io, err.message)

struct _ZipEntry
    name::String
    data::Vector{UInt8}
    crc32::UInt32
    offset::UInt32
end

"""
    doctor_report(; validation_root="benchmarks") -> NamedTuple

Collect release-audit readiness checks for the validation contract. The
report is diagnostic: solver and frontend availability affect readiness, but
the exact verifier itself remains independent from those optional tools.
"""
function doctor_report(; validation_root::AbstractString="benchmarks")
    checks = NamedTuple[]
    push!(checks, _doctor_check("Julia",
                                true,
                                string(VERSION),
                                "required runtime"))
    push!(checks,
          _doctor_check("CertSDP",
                        true,
                        string(package_version()),
                        "loaded from current project"))
    push!(checks,
          _doctor_check("RAM/CPU threads",
                        Sys.CPU_THREADS >= 1,
                        string("threads=", Sys.CPU_THREADS,
                               ", ram=", _doctor_memory_label()),
                        "CPU threads detected"))

    clarabel_version = _doctor_package_version("Clarabel")
    push!(checks,
          _doctor_check("Clarabel",
                        !isnothing(clarabel_version),
                        isnothing(clarabel_version) ? "not loadable" :
                        clarabel_version,
                        "needed for solve -> diagnose -> certify validation rows"))

    msolve_path = find_msolve()
    msolve_ver = isnothing(msolve_path) ? nothing :
                 msolve_version(; binary=msolve_path, timeout_seconds=5)
    push!(checks,
          _doctor_check("msolve",
                        !isnothing(msolve_path),
                        isnothing(msolve_path) ? "not found on PATH or CERTSDP_MSOLVE" :
                        string(msolve_path,
                               isnothing(msolve_ver) ? "" :
                               " (" * strip(msolve_ver) * ")"),
                        "needed for algebraic validation rows"))

    sos_version = _doctor_package_version("SumOfSquares")
    push!(checks,
          _doctor_check("SumOfSquares",
                        true,
                        isnothing(sos_version) ?
                        "not loadable in root project; exported Gram fixtures available" :
                        sos_version,
                        "optional frontend; validation uses exact exported Gram data"))

    jump_project = joinpath("examples", "jump")
    jump_version = _doctor_package_version("JuMP"; project_dir=jump_project)
    jump_ready = !isnothing(jump_version)
    push!(checks,
          _doctor_check("JuMP",
                        jump_ready,
                        isnothing(jump_version) ? "not loadable in examples/jump" :
                        jump_version,
                        "needed for JuMP/MOI extraction workflow validation"))

    cache = _doctor_cache_status()
    push!(checks, _doctor_check("cache status",
                                true,
                                cache.summary,
                                cache.detail))

    suite = _doctor_validation_suite_status(validation_root)
    push!(checks,
          _doctor_check("validation suite",
                        suite.ready,
                        suite.summary,
                        suite.detail))

    suite_requirements = suite.requirements
    required = Set(["Julia", "CertSDP", "RAM/CPU threads", "validation suite"])
    "clarabel" in suite_requirements && push!(required, "Clarabel")
    "msolve" in suite_requirements && push!(required, "msolve")
    "jump" in suite_requirements && push!(required, "JuMP")
    ready = all(check -> !(check.name in required) || check.ok, checks)
    return (;
            status=ready ? "ready" : "not_ready",
            ready,
            checks,
            validation_root=String(validation_root),
            validation_budget=validation_budget_label(validation_budget()),)
end

function _doctor_check(name::AbstractString, ok::Bool, value::AbstractString,
                       detail::AbstractString)
    return (;
            name=String(name),
            ok=Bool(ok),
            value=String(value),
            detail=String(detail),)
end

function _doctor_package_version(name::AbstractString; project_dir=nothing)
    if !isnothing(project_dir)
        version = _doctor_manifest_version(String(name),
                                           joinpath(String(project_dir),
                                                    "Manifest.toml"))
        !isnothing(version) && return version
    end
    symbol = Symbol(name)
    path = Base.find_package(String(name))
    project = isnothing(path) ? "" : normpath(joinpath(dirname(path), "..", "Project.toml"))
    if isfile(project)
        for line in eachline(project)
            stripped = strip(line)
            startswith(stripped, "version") || continue
            parts = split(stripped, "="; limit=2)
            length(parts) == 2 && return strip(strip(parts[2]), ['"', '\''])
        end
    end
    if isdefined(@__MODULE__, symbol)
        module_value = getfield(@__MODULE__, symbol)
        if module_value isa Module && isdefined(module_value, :VERSION)
            return string(getfield(module_value, :VERSION))
        end
    end
    isnothing(path) && return nothing
    return "installed"
end

function _doctor_manifest_version(name::String, manifest_path::AbstractString)
    isfile(manifest_path) || return nothing
    lines = readlines(manifest_path)
    for (i, line) in enumerate(lines)
        occursin("[[deps.$name]]", line) || continue
        for j in (i + 1):min(length(lines), i + 20)
            stripped = strip(lines[j])
            startswith(stripped, "[[deps.") && break
            startswith(stripped, "version") || continue
            parts = split(stripped, "="; limit=2)
            length(parts) == 2 && return strip(strip(parts[2]), ['"', '\''])
        end
    end
    return nothing
end

function _doctor_memory_label()
    total = _doctor_total_memory_bytes()
    isnothing(total) && return "unknown"
    return _replay_format_bytes(total)
end

function _doctor_total_memory_bytes()
    if Sys.isapple()
        try
            output = read(`sysctl -n hw.memsize`, String)
            return parse(Int, strip(output))
        catch
            return nothing
        end
    elseif Sys.islinux()
        try
            for line in eachline("/proc/meminfo")
                if startswith(line, "MemTotal:")
                    parts = split(line)
                    length(parts) >= 2 && return parse(Int, parts[2]) * 1024
                end
            end
        catch
            return nothing
        end
    end
    return nothing
end

function _doctor_cache_status()
    candidates = String[]
    for path in (".certsdp_cache", joinpath("benchmarks", "generated"))
        ispath(path) && push!(candidates, path)
    end
    if isempty(candidates)
        return (;
                summary="empty",
                detail="no .certsdp_cache or benchmarks/generated directory found")
    end
    files = 0
    bytes = 0
    for root in candidates
        for (dir, _, names) in walkdir(root)
            for name in names
                path = joinpath(dir, name)
                isfile(path) || continue
                files += 1
                bytes += filesize(path)
            end
        end
    end
    return (;
            summary=string(files, " files, ", _replay_format_bytes(bytes)),
            detail=join(candidates, ", "))
end

function _doctor_validation_suite_status(root::AbstractString)
    if !isdir(root)
        return (;
                ready=false,
                summary="missing",
                detail="validation root does not exist",
                requirements=String[])
    end
    cases = try
        benchmark_cases(root; subset=:validation)
    catch err
        return (;
                ready=false,
                summary="metadata error",
                detail=sprint(showerror, err),
                requirements=String[])
    end
    isempty(cases) &&
        return (;
                ready=false,
                summary="no validation cases selected",
                detail="expected benchmark metadata under benchmarks/validation",
                requirements=String[])
    backend_requirements = sort(unique(String(case.expected.backend_requirement)
                                       for case in cases))
    workflow_requirements = Set{String}()
    for case in cases
        requirement = String(case.expected.backend_requirement)
        requirement in ("clarabel", "msolve") && push!(workflow_requirements,
                                                       requirement)
        case.expected.workflow === :lmi_solve_certify &&
            push!(workflow_requirements, "clarabel")
        case.expected.workflow === JUMP_MOI_EXTRACT_WORKFLOW &&
            push!(workflow_requirements, "jump")
        source_kind = String(case.expected.source_kind)
        source_kind == "sumofsquares_extract" && push!(workflow_requirements,
                                                       "sumofsquares")
        occursin("sumofsquares", lowercase(String(case.expected.strategy))) &&
            push!(workflow_requirements, "sumofsquares")
    end
    return (;
            ready=true,
            summary=string(length(cases), " validation cases"),
            detail=string("backend requirements: ",
                          join(backend_requirements, ", ")),
            requirements=sort(collect(workflow_requirements)))
end

function print_doctor_report(report; io::IO=stdout)
    println(io, "CertSDP doctor")
    println(io, "Status: ", report.status)
    println(io, "Validation budget: ", report.validation_budget)
    for check in report.checks
        marker = check.ok ? "OK" : "MISSING"
        println(io, "[$marker] ", check.name, ": ", check.value)
        !isempty(check.detail) && println(io, "    ", check.detail)
    end
    if report.ready
        return println(io, "[OK] ready to run validation contract")
    end
    return println(io,
                   "[FAIL] not ready to run full validation contract; install missing optional components or run verifier-only paths")
end

"""
    explain_failure_report(failure; max_lines=30) -> Vector{String}

Return a compact failure explanation suitable for `certsdp explain`.
"""
function explain_failure_report(failure::CertificationFailure; max_lines::Integer=30)
    max_lines >= 8 || throw(ArgumentError("max_lines must be at least 8"))
    report = failure_report_json(failure)
    lines = String["CertSDP failure explanation",
                   "Type: $(report.failure_type)",
                   "Reason: $(report.reason)",
                   "Stage: $(report.stage)",
                   "Summary: $(report.summary)"]
    details = report.details
    key_lines = _explain_key_details(details, Symbol(report.reason))
    if !isempty(key_lines)
        push!(lines, "Key evidence:")
        append!(lines, key_lines)
    end
    push!(lines, "Likely next steps:")
    for suggestion in report.suggestions
        push!(lines, "- " * suggestion)
        length(lines) >= max_lines && break
    end
    return lines[1:min(length(lines), max_lines)]
end

function explain_failure_report(path::AbstractString; max_lines::Integer=30)
    return explain_failure_report(read_failure_report(path); max_lines)
end

function print_failure_explanation(failure::CertificationFailure; io::IO=stdout,
                                   max_lines::Integer=30)
    for line in explain_failure_report(failure; max_lines)
        println(io, line)
    end
    return nothing
end

function _explain_key_details(details, reason::Symbol)
    details isa AbstractDict || return String[]
    preferred = if reason === :rank_profile_unstable
        ("candidate_rank", "candidate_ranks", "gap", "rank_gap", "singular_values")
    elseif reason in (:system_too_large, :incidence_system_too_large)
        ("variables", "equations", "degree_estimate", "max_system_variables",
         "max_system_equations")
    elseif reason in (:msolve_failed, :backend_failed, :unsupported_backend,
                      :backend_timeout, :msolve_timeout, :validation_timeout)
        ("backend_reason", "backend", "timeout_seconds", "elapsed_seconds",
         "command", "stderr", "stdout")
    elseif reason in (:psd_verification_failed, :certificate_build_failed)
        ("block", "block_index", "minor", "minor_indices", "pivot", "pivot_block",
         "method", "exception_type")
    elseif reason in (:sos_matching_failed, :sos_psd_failed, :sos_certificate_failed)
        ("basis_size", "monomial", "coefficient", "expected", "observed", "pivot")
    else
        Tuple(string.(sort(collect(keys(details)))[1:min(length(details), 5)]))
    end
    lines = String[]
    for key in preferred
        haskey(details, key) || haskey(details, Symbol(key)) || continue
        value = haskey(details, key) ? details[key] : details[Symbol(key)]
        push!(lines, "- $(key): $(_replay_short_value(value))")
        length(lines) >= 6 && break
    end
    if isempty(lines)
        for key in sort!(collect(keys(details)); by=string)
            push!(lines, "- $(key): $(_replay_short_value(details[key]))")
            length(lines) >= 5 && break
        end
    end
    return lines
end

function _replay_short_value(value)
    ready = _certification_diagnostics_json(value)
    text = ready isa AbstractDict || ready isa AbstractVector ? JSON3.write(ready) :
           string(ready)
    length(text) <= 220 && return text
    return first(text, 217) * "..."
end

"""
    bundle_certificate(cert_path; out_path, ... ) -> String

Create a replay artifact bundle. The bundle contains the certificate,
embedded or supplied problem data, optional approximation and backend logs,
strict verification report, environment versions, manifest, and README.
"""
function bundle_certificate(cert_path::AbstractString;
                            out_path::AbstractString,
                            problem_path=nothing,
                            approx_path=nothing,
                            report_path=nothing,
                            logs_path=nothing,
                            redact::Bool=true)
    cert_abs = abspath(cert_path)
    isfile(cert_abs) ||
        throw(ReplayBundleError("certificate `$cert_path` does not exist"))
    cert_text = read(cert_abs, String)
    strict_io = IOBuffer()
    strict_ok = verify_strict_json(cert_text; io=strict_io)
    strict_report = String(take!(strict_io))
    strict_ok ||
        throw(ReplayBundleError("strict verifier rejected certificate before bundling: " *
                                strip(strict_report)))

    entries = Dict{String, Vector{UInt8}}()
    entries[REPLAY_BUNDLE_CERTIFICATE] = Vector{UInt8}(codeunits(cert_text))
    if !isnothing(problem_path)
        entries[REPLAY_BUNDLE_PROBLEM] = _bundle_read_file_for_sharing(abspath(String(problem_path));
                                                                       redact)
    else
        embedded = _bundle_embedded_problem_text(cert_text)
        !isnothing(embedded) &&
            (entries[REPLAY_BUNDLE_PROBLEM] = Vector{UInt8}(codeunits(embedded)))
    end
    if !isnothing(approx_path)
        entries[REPLAY_BUNDLE_APPROX] = _bundle_read_file_for_sharing(abspath(String(approx_path));
                                                                      redact)
    else
        entries["approx/README.md"] = Vector{UInt8}(codeunits("No approximate solution file was supplied when this bundle was created.\n"))
    end
    entries[REPLAY_BUNDLE_REPORT] = Vector{UInt8}(codeunits(strict_report))
    if !isnothing(report_path)
        report_abs = abspath(String(report_path))
        entries["reports/source_report" * _bundle_file_extension(String(report_path))] = _bundle_read_file_for_sharing(report_abs;
                                                                                                                       redact)
    end
    if !isnothing(logs_path)
        _bundle_add_logs!(entries, abspath(String(logs_path)); redact)
    else
        entries["backend_logs/README.md"] = Vector{UInt8}(codeunits("No backend log directory was supplied when this bundle was created.\n"))
    end

    versions = _bundle_versions_json(; redact)
    entries[REPLAY_BUNDLE_VERSIONS] = _json_bytes(versions)
    manifest = _bundle_manifest(redact ? "<redacted>" : cert_abs,
                                entries,
                                strict_ok;
                                redact)
    entries[REPLAY_BUNDLE_MANIFEST] = _json_bytes(manifest)
    entries[REPLAY_BUNDLE_README] = Vector{UInt8}(codeunits(_bundle_readme(manifest)))

    output = abspath(out_path)
    mkpath(dirname(output))
    _zip_write(output, entries)
    return output
end

function replay_bundle(zip_path::AbstractString; io::Union{Nothing, IO}=nothing,
                       extract_dir=nothing)
    zip_abs = abspath(zip_path)
    isfile(zip_abs) || throw(ReplayBundleError("bundle `$zip_path` does not exist"))
    entries = _zip_read(zip_abs)
    haskey(entries, REPLAY_BUNDLE_CERTIFICATE) ||
        throw(ReplayBundleError("bundle is missing $REPLAY_BUNDLE_CERTIFICATE"))
    cert_text = String(entries[REPLAY_BUNDLE_CERTIFICATE])
    if !isnothing(extract_dir)
        _bundle_extract_entries(entries, abspath(String(extract_dir)))
    end
    report_io = isnothing(io) ? IOBuffer() : io
    ok = verify_strict_json(cert_text; io=report_io)
    return (;
            accepted=ok,
            certificate_path=REPLAY_BUNDLE_CERTIFICATE,
            entry_count=length(entries),
            extracted_to=isnothing(extract_dir) ? nothing : abspath(String(extract_dir)),)
end

function _bundle_embedded_problem_text(cert_text::AbstractString)
    parsed = try
        JSON3.read(cert_text)
    catch
        return nothing
    end
    try
        if haskey(parsed, :problem)
            problem = _require_key(parsed, :problem, "root")
            data = _require_key(problem, :data, "root.problem")
            return _pretty_json_string(data)
        elseif haskey(parsed, :sos_problem)
            return _pretty_json_string(_require_key(parsed, :sos_problem, "root"))
        end
    catch
        return nothing
    end
    return nothing
end

function _bundle_add_logs!(entries::Dict{String, Vector{UInt8}},
                           path::AbstractString;
                           redact::Bool)
    ispath(path) || throw(ReplayBundleError("logs path `$path` does not exist"))
    if isfile(path)
        entries["backend_logs/" * basename(path)] = _bundle_read_file_for_sharing(path;
                                                                                  redact)
        return entries
    end
    for (dir, _, files) in walkdir(path)
        for file in sort(files)
            source = joinpath(dir, file)
            rel = relpath(source, path)
            entries["backend_logs/" * replace(rel, '\\' => '/')] = _bundle_read_file_for_sharing(source;
                                                                                                 redact)
        end
    end
    return entries
end

function _bundle_versions_json(; redact::Bool=true)
    msolve_path = find_msolve()
    return (;
            certsdp_version=string(package_version()),
            julia_version=string(VERSION),
            os=Sys.KERNEL,
            arch=Sys.ARCH,
            cpu_threads=Sys.CPU_THREADS,
            clarabel=_doctor_package_version("Clarabel"),
            jump=_doctor_package_version("JuMP"),
            sumofsquares=_doctor_package_version("SumOfSquares"),
            msolve_path=redact ? _redact_path_for_bundle(msolve_path) :
                        msolve_path,
            msolve_version=msolve_version(; timeout_seconds=5),)
end

function _bundle_manifest(certificate_source::AbstractString,
                          entries::Dict{String, Vector{UInt8}},
                          strict_ok::Bool;
                          redact::Bool=true)
    file_entries = sort([(;
                          path=name,
                          bytes=length(data),
                          sha256=_sha256_bytes(data),)
                         for (name, data) in entries if name != REPLAY_BUNDLE_MANIFEST];
                        by=item -> item.path)
    return (;
            certsdp_artifact_bundle_version=REPLAY_BUNDLE_VERSION,
            created_by="CertSDP.jl",
            redacted=redact,
            certificate_source,
            strict_verify_at_bundle_time=strict_ok,
            files=file_entries,
            replay_command="certsdp replay artifact.zip",)
end

function _bundle_readme(manifest)
    io = IOBuffer()
    println(io, "# CertSDP Replay Artifact Bundle")
    println(io)
    println(io, "This bundle is data-only. Replay uses `certsdp replay artifact.zip`,")
    println(io,
            "which extracts the embedded certificate in memory and runs strict exact verification.")
    println(io)
    println(io, "- Bundle version: ", manifest.certsdp_artifact_bundle_version)
    println(io, "- Redacted sidecar metadata: ", manifest.redacted)
    println(io, "- Strict verify at bundle time: ", manifest.strict_verify_at_bundle_time)
    println(io, "- Certificate: ", REPLAY_BUNDLE_CERTIFICATE)
    println(io, "- Problem: ",
            any(file -> file.path == REPLAY_BUNDLE_PROBLEM,
                manifest.files) ? REPLAY_BUNDLE_PROBLEM : "embedded in certificate only")
    println(io, "- Approximation: ",
            any(file -> file.path == REPLAY_BUNDLE_APPROX,
                manifest.files) ? REPLAY_BUNDLE_APPROX : "not supplied")
    println(io, "- Verification report: ", REPLAY_BUNDLE_REPORT)
    println(io, "- Versions: ", REPLAY_BUNDLE_VERSIONS)
    println(io, "- Backend logs: backend_logs/ when supplied")
    return String(take!(io))
end

function _bundle_read_file_for_sharing(path::AbstractString; redact::Bool)
    data = read(path)
    redact || return data
    text = try
        String(data)
    catch
        return data
    end
    return Vector{UInt8}(codeunits(_redact_bundle_text(text)))
end

function _redact_bundle_text(text::AbstractString)
    redacted = replace(text,
                       homedir() => "\$HOME",
                       pwd() => "\$PWD")
    redacted = replace(redacted,
                       r"(/Users|/home|/private/tmp|/tmp|/var/folders)/[^\s\"'`,;)]+" => s"<redacted-path>",
                       r"[A-Za-z]:\\[^\s\"'`,;)]+" => s"<redacted-path>")
    return redacted
end

function _redact_path_for_bundle(path)
    isnothing(path) && return nothing
    return "<redacted-path>/" * basename(String(path))
end

function _bundle_extract_entries(entries, dir::AbstractString)
    mkpath(dir)
    for (name, data) in entries
        target = normpath(joinpath(dir, split(name, '/')...))
        rel = relpath(target, normpath(dir))
        (rel == "." || rel == ".." ||
         startswith(rel, ".." * Base.Filesystem.path_separator)) &&
            throw(ReplayBundleError("unsafe bundle path `$name`"))
        mkpath(dirname(target))
        write(target, data)
    end
    return dir
end

function _bundle_file_extension(path::AbstractString)
    ext = splitext(path)[2]
    isempty(ext) && return ".txt"
    return ext
end

function _pretty_json_string(value)
    io = IOBuffer()
    JSON3.pretty(io, value)
    println(io)
    return String(take!(io))
end

function _json_bytes(value)
    return Vector{UInt8}(codeunits(_pretty_json_string(value)))
end

function _sha256_bytes(data::Vector{UInt8})
    return "sha256:" * bytes2hex(sha256(data))
end

function _replay_format_bytes(bytes::Integer)
    value = Float64(bytes)
    units = ("B", "KiB", "MiB", "GiB", "TiB")
    index = 1
    while value >= 1024 && index < length(units)
        value /= 1024
        index += 1
    end
    index == 1 && return string(Int(bytes), " B")
    return string(round(value; digits=2), " ", units[index])
end

function _zip_write(path::AbstractString, raw_entries::Dict{String, Vector{UInt8}})
    names = sort(collect(keys(raw_entries)))
    entries = _ZipEntry[]
    open(path, "w") do io
        for name in names
            data = raw_entries[name]
            offset = UInt32(position(io))
            crc = _crc32(data)
            name_bytes = Vector{UInt8}(codeunits(name))
            _zip_write_u32(io, 0x04034b50)
            _zip_write_u16(io, 20)
            _zip_write_u16(io, 0)
            _zip_write_u16(io, 0)
            _zip_write_u16(io, 0)
            _zip_write_u16(io, 0)
            _zip_write_u32(io, crc)
            _zip_write_u32(io, UInt32(length(data)))
            _zip_write_u32(io, UInt32(length(data)))
            _zip_write_u16(io, UInt16(length(name_bytes)))
            _zip_write_u16(io, 0)
            write(io, name_bytes)
            write(io, data)
            push!(entries, _ZipEntry(name, data, crc, offset))
        end
        central_offset = UInt32(position(io))
        for entry in entries
            name_bytes = Vector{UInt8}(codeunits(entry.name))
            _zip_write_u32(io, 0x02014b50)
            _zip_write_u16(io, 20)
            _zip_write_u16(io, 20)
            _zip_write_u16(io, 0)
            _zip_write_u16(io, 0)
            _zip_write_u16(io, 0)
            _zip_write_u16(io, 0)
            _zip_write_u32(io, entry.crc32)
            _zip_write_u32(io, UInt32(length(entry.data)))
            _zip_write_u32(io, UInt32(length(entry.data)))
            _zip_write_u16(io, UInt16(length(name_bytes)))
            _zip_write_u16(io, 0)
            _zip_write_u16(io, 0)
            _zip_write_u16(io, 0)
            _zip_write_u16(io, 0)
            _zip_write_u32(io, 0)
            _zip_write_u32(io, entry.offset)
            write(io, name_bytes)
        end
        central_size = UInt32(position(io) - central_offset)
        _zip_write_u32(io, 0x06054b50)
        _zip_write_u16(io, 0)
        _zip_write_u16(io, 0)
        _zip_write_u16(io, UInt16(length(entries)))
        _zip_write_u16(io, UInt16(length(entries)))
        _zip_write_u32(io, central_size)
        _zip_write_u32(io, central_offset)
        return _zip_write_u16(io, 0)
    end
    return path
end

function _zip_read(path::AbstractString)
    bytes = read(path)
    entries = Dict{String, Vector{UInt8}}()
    i = 1
    while i + 30 <= length(bytes)
        sig = _zip_read_u32(bytes, i)
        sig == 0x04034b50 || break
        flags = _zip_read_u16(bytes, i + 6)
        method = _zip_read_u16(bytes, i + 8)
        flags == 0 || throw(ReplayBundleError("unsupported ZIP flags in bundle"))
        method == 0 || throw(ReplayBundleError("unsupported compressed ZIP entry"))
        crc = _zip_read_u32(bytes, i + 14)
        compressed_size = Int(_zip_read_u32(bytes, i + 18))
        uncompressed_size = Int(_zip_read_u32(bytes, i + 22))
        name_length = Int(_zip_read_u16(bytes, i + 26))
        extra_length = Int(_zip_read_u16(bytes, i + 28))
        data_start = i + 30 + name_length + extra_length
        data_end = data_start + compressed_size - 1
        data_end <= length(bytes) ||
            throw(ReplayBundleError("truncated ZIP entry"))
        name = String(bytes[(i + 30):(i + 29 + name_length)])
        data = bytes[data_start:data_end]
        length(data) == uncompressed_size ||
            throw(ReplayBundleError("ZIP entry size mismatch for `$name`"))
        _crc32(data) == crc ||
            throw(ReplayBundleError("ZIP entry checksum mismatch for `$name`"))
        _zip_safe_name(name)
        entries[name] = data
        i = data_end + 1
    end
    isempty(entries) &&
        throw(ReplayBundleError("bundle contains no readable ZIP entries"))
    return entries
end

function _zip_safe_name(name::AbstractString)
    isempty(name) && throw(ReplayBundleError("empty ZIP entry name"))
    startswith(name, "/") && throw(ReplayBundleError("absolute ZIP entry path forbidden"))
    ".." in split(name, '/') &&
        throw(ReplayBundleError("parent-directory ZIP entry path forbidden"))
    return true
end

function _zip_write_u16(io::IO, value)
    v = UInt16(value)
    write(io, UInt8(v & 0xff))
    return write(io, UInt8((v >> 8) & 0xff))
end

function _zip_write_u32(io::IO, value)
    v = UInt32(value)
    write(io, UInt8(v & 0xff))
    write(io, UInt8((v >> 8) & 0xff))
    write(io, UInt8((v >> 16) & 0xff))
    return write(io, UInt8((v >> 24) & 0xff))
end

function _zip_read_u16(bytes::Vector{UInt8}, i::Integer)
    return UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8)
end

function _zip_read_u32(bytes::Vector{UInt8}, i::Integer)
    return UInt32(bytes[i]) |
           (UInt32(bytes[i + 1]) << 8) |
           (UInt32(bytes[i + 2]) << 16) |
           (UInt32(bytes[i + 3]) << 24)
end

function _crc32(data::Vector{UInt8})
    crc = UInt32(0xffffffff)
    for byte in data
        crc = crc ⊻ UInt32(byte)
        for _ in 1:8
            mask = -(crc & UInt32(1))
            crc = (crc >> 1) ⊻ (UInt32(0xedb88320) & mask)
        end
    end
    return crc ⊻ UInt32(0xffffffff)
end
