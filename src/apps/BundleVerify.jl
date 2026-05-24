module BundleVerify

using ..Kernel
using JSON3: JSON3
using SHA: sha256

export verify_bundle_directory,
       bundle_file_hashes

const REQUIRED_FILES = [
    "CERTSDP_BUNDLE.json",
    "problem.json",
    "certificate.json",
    "proof_dag.json",
    "object_store.json",
    "schema.json",
    "VERIFY.sh",
    "replay_report.json",
    "hashes.txt",
    "environment.json",
    "theorem_statement.txt",
    "README.md",
    "source_artifacts",
]

function _sha256_file(path)
    return "sha256:" * bytes2hex(sha256(read(path)))
end

function bundle_file_hashes(dir::AbstractString)
    result = Dict{String, String}()
    for rel in REQUIRED_FILES
        path = joinpath(dir, rel)
        isfile(path) && (result[rel] = _sha256_file(path))
    end
    schema_dir = joinpath(dir, "schema")
    if isdir(schema_dir)
        for file in sort!(readdir(schema_dir))
            rel = joinpath("schema", file)
            result[rel] = _sha256_file(joinpath(dir, rel))
        end
    end
    schemas_dir = joinpath(dir, "schemas")
    if isdir(schemas_dir)
        for file in sort!(readdir(schemas_dir))
            rel = joinpath("schemas", file)
            result[rel] = _sha256_file(joinpath(dir, rel))
        end
    end
    source_dir = joinpath(dir, "source_artifacts")
    if isdir(source_dir)
        for file in sort!(readdir(source_dir))
            rel = joinpath("source_artifacts", file)
            result[rel] = _sha256_file(joinpath(dir, rel))
        end
    end
    return result
end

function _parse_hashes_txt(path)
    result = Dict{String, String}()
    for line in eachline(path)
        text = strip(line)
        isempty(text) && continue
        parts = split(text)
        length(parts) >= 2 || throw(ArgumentError("malformed hashes.txt line `$line`"))
        first, last = String(parts[1]), String(parts[end])
        if startswith(first, "sha256:") || occursin(r"^[0-9a-f]{64}$", first)
            result[last] = startswith(first, "sha256:") ? first : "sha256:" * first
        else
            result[first] = startswith(last, "sha256:") ? last : "sha256:" * last
        end
    end
    return result
end

function verify_bundle_directory(dir::AbstractString)
    try
        for file in REQUIRED_FILES
            if file == "source_artifacts"
                isdir(joinpath(dir, file)) ||
                    return (passed=false, reason="missing bundle directory $file")
            else
                isfile(joinpath(dir, file)) ||
                    return (passed=false, reason="missing bundle file $file")
            end
        end
        manifest = JSON3.read(read(joinpath(dir, "CERTSDP_BUNDLE.json"), String))
        for key in (:certificate_hash, :problem_hash)
            haskey(manifest, key) ||
                return (passed=false, reason="bundle manifest missing $(String(key))")
        end
        problem = JSON3.read(read(joinpath(dir, "problem.json"), String))
        if haskey(problem, :source) &&
           String(problem[:source]) in ("embedded_or_not_supplied", "empty_problem_marker")
            return (passed=false, reason="problem.json lacks replayable problem evidence")
        end
        hashes = _parse_hashes_txt(joinpath(dir, "hashes.txt"))
        actual = bundle_file_hashes(dir)
        for (rel, hash) in actual
            rel == "hashes.txt" && continue
            get(hashes, rel, "") == hash ||
                return (passed=false, reason="stale or missing hash for $rel")
        end
        report = Kernel.replay_file(joinpath(dir, "certificate.json");
                                    strict=true,
                                    io=nothing)
        report.accepted ||
            return (passed=false, reason="certificate replay rejected: $(report.reason)")
        certificate = JSON3.read(read(joinpath(dir, "certificate.json"), String))
        dag = JSON3.read(read(joinpath(dir, "proof_dag.json"), String))
        dag_root = haskey(dag, :root_hash) ? String(dag[:root_hash]) : ""
        haskey(certificate, :proof_dag) &&
            String(certificate[:proof_dag][:root_hash]) == dag_root ||
            return (passed=false, reason="proof_dag.json does not match certificate")
        object_store = JSON3.read(read(joinpath(dir, "object_store.json"), String))
        haskey(dag, :object_store) &&
            JSON3.write(object_store) == JSON3.write(dag[:object_store]) ||
            return (passed=false, reason="object_store.json does not match proof DAG")
        String(manifest[:certificate_hash]) == report.certificate_hash ||
            return (passed=false, reason="manifest certificate hash mismatch")
        String(manifest[:problem_hash]) == report.problem_hash ||
            return (passed=false, reason="manifest problem hash mismatch")
        haskey(manifest, :dag_root_hash) && String(manifest[:dag_root_hash]) == dag_root ||
            return (passed=false, reason="manifest DAG root hash mismatch")
        replay_report = JSON3.read(read(joinpath(dir, "replay_report.json"), String))
        haskey(replay_report, :accepted) && Bool(replay_report[:accepted]) ||
            return (passed=false, reason="stale replay_report.json")
        haskey(replay_report, :certificate_hash) &&
            String(replay_report[:certificate_hash]) == report.certificate_hash ||
            return (passed=false, reason="replay_report certificate hash mismatch")
        return (passed=true, reason="accepted")
    catch err
        return (passed=false, reason=sprint(showerror, err))
    end
end

end
