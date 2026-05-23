module TSSOSRawImporter

using ..Adapters
using JSON3: JSON3
using SHA: sha256

export normalize_raw_tssos_artifact,
       import_raw_tssos_artifact,
       certify_raw_tssos_artifact

function _hash_payload(payload)
    return "sha256:" * bytes2hex(sha256(JSON3.write(payload)))
end

function _write_temp_json(object)
    path = tempname() * ".json"
    open(path, "w") do io
        JSON3.pretty(io, object)
        println(io)
    end
    return path
end

function _require(object, key::Symbol, path::AbstractString)
    haskey(object, key) || throw(ArgumentError("$path is missing $(String(key))"))
    return object[key]
end

function normalize_raw_tssos_artifact(path::AbstractString)
    raw = JSON3.read(read(path, String))
    version = String(_require(raw, :tssos_raw_artifact_version, "root"))
    version == "external-like-1" ||
        throw(ArgumentError("unsupported raw TSSOS artifact version $version"))
    payload = Dict{String, Any}(
        "certsdp_tssos_artifact_version" => "3.0",
        "variables" => raw[:variables],
        "objective_polynomial" => raw[:objective],
        "constraints" => raw[:constraints],
        "cliques" => raw[:correlative_sparsity_cliques],
        "monomial_bases" => raw[:monomial_bases],
        "gram_blocks" => raw[:gram_blocks],
        "localizing_blocks" => raw[:localizing_matrices],
        "coefficient_maps" => raw[:coefficient_maps],
        "bound" => raw[:bound],
        "provenance" => Dict("source" => "external_like_tssos",
                             "raw_file" => basename(path)),
        "frontend_metadata" => haskey(raw, :frontend_metadata) ? raw[:frontend_metadata] : Dict(),
        "solver_metadata" => haskey(raw, :solver_metadata) ? raw[:solver_metadata] : Dict(),
        "source_raw_hash" => _hash_payload(raw),
    )
    payload["artifact_hash"] = Adapters._artifact_hash(payload)
    return payload
end

function import_raw_tssos_artifact(path::AbstractString)
    normalized = normalize_raw_tssos_artifact(path)
    normalized_path = _write_temp_json(normalized)
    try
        return Adapters.import_tssos_artifact(normalized_path)
    finally
        isfile(normalized_path) && rm(normalized_path; force=true)
    end
end

function certify_raw_tssos_artifact(path::AbstractString)
    candidate = try
        import_raw_tssos_artifact(path)
    catch err
        failure = getfield(parentmodule(parentmodule(@__MODULE__)), :BadCandidateRejected)(
            :candidate_rejected,
            sprint(showerror, err),
            :tssos_raw_import,
            Dict{Symbol, Any}(:artifact_path => String(path)))
        return getfield(parentmodule(parentmodule(@__MODULE__)), :FailureResult)(failure)
    end
    report = Adapters.Kernel.verify_sparse_sos_certificate(candidate.certificate)
    if report.accepted
        return getfield(parentmodule(parentmodule(@__MODULE__)), :CertifiedResult)(
            candidate.certificate;
            artifacts=Dict{Symbol, Any}(:source => :raw_tssos,
                                        :artifact_hash => candidate.artifact_hash))
    end
    failure = getfield(parentmodule(parentmodule(@__MODULE__)), :BadCandidateRejected)(
        :candidate_rejected,
        report.reason,
        report.stage,
        Dict{Symbol, Any}(:artifact_path => String(path)))
    return getfield(parentmodule(parentmodule(@__MODULE__)), :FailureResult)(failure)
end

end

