"""
    paper_artifact_manifest(cert; title="")

Create a data-only reviewer manifest for a verified certificate. The manifest
records hashes, strict replay command text, and proof-obligation metadata. It
does not replace `bundle`/`replay`; it is the lightweight object those tools can
embed in a paper artifact directory.
"""
function paper_artifact_manifest(cert; title::AbstractString="")
    verify(cert) || throw(ArgumentError("paper artifacts require a verified certificate"))
    graph = proof_obligation_graph(cert)
    cert_json = certificate_json_v1(cert)
    certificate_id = _paper_artifact_certificate_id(cert_json)
    return (;
            title=String(title),
            certsdp_version=string(package_version()),
            certificate_type=String(_paper_artifact_certificate_type(cert_json)),
            certificate_id,
            proof_obligations=proof_obligation_graph_json(graph),
            replay_command="bin/certsdp verify --strict certificate.json",
            bundle_command="bin/certsdp bundle certificate.json --out artifact.zip",
            trust_boundary="strict replay ignores numerical solver output, backend logs, and provenance claims",)
end

"""
    write_paper_artifact(dir, cert; title="", label="certsdp-cert")

Write a reviewer-ready, data-only artifact directory:

- `certificate.json`
- `manifest.json`
- `strict_replay.txt`
- `snippet.tex`
- `provenance.json`
- `README.md`

The certificate is accepted only after strict replay succeeds locally.
"""
function write_paper_artifact(dir::AbstractString,
                              cert;
                              title::AbstractString="",
                              label::AbstractString="certsdp-cert")
    verify(cert) || throw(ArgumentError("paper artifacts require a verified certificate"))
    mkpath(dir)
    certificate_path = joinpath(dir, "certificate.json")
    manifest_path = joinpath(dir, "manifest.json")
    replay_path = joinpath(dir, "strict_replay.txt")
    snippet_path = joinpath(dir, "snippet.tex")
    provenance_path = joinpath(dir, "provenance.json")
    readme_path = joinpath(dir, "README.md")

    write_certificate(certificate_path, cert)
    replay_io = IOBuffer()
    accepted = verify_strict(certificate_path; io=replay_io)
    accepted ||
        throw(ArgumentError("paper artifact certificate failed strict replay"))
    replay_text = String(take!(replay_io))
    open(replay_path, "w") do io
        return write(io, replay_text)
    end

    manifest = merge(paper_artifact_manifest(cert; title),
                     (;
                      files=(;
                             certificate="certificate.json",
                             strict_replay="strict_replay.txt",
                             latex_snippet="snippet.tex",
                             provenance="provenance.json",
                             readme="README.md",),
                      replay_accepted=accepted,
                      replay_report_sha256="sha256:" *
                                           bytes2hex(sha256(replay_text)),
                      certificate_sha256="sha256:" *
                                         bytes2hex(sha256(read(certificate_path))),))
    open(manifest_path, "w") do io
        JSON3.pretty(io, manifest)
        return println(io)
    end

    open(snippet_path, "w") do io
        return write(io, paper_artifact_latex_snippet(cert; label) * "\n")
    end
    open(provenance_path, "w") do io
        JSON3.pretty(io, _paper_artifact_redacted_provenance(cert))
        return println(io)
    end
    open(readme_path, "w") do io
        return write(io, _paper_artifact_readme(manifest))
    end
    return (;
            directory=String(dir),
            certificate_path,
            manifest_path,
            replay_path,
            snippet_path,
            provenance_path,
            readme_path,
            accepted,)
end

function _paper_artifact_certificate_type(cert_json)
    return Symbol(_require_string(cert_json, :certificate_type,
                                  "certificate.certificate_type"))
end

function _paper_artifact_certificate_id(cert_json)
    if haskey(cert_json, :certificate_id)
        return _require_string(cert_json, :certificate_id,
                               "certificate.certificate_id")
    elseif haskey(cert_json, :hash)
        return _require_string(cert_json, :hash, "certificate.hash")
    end
    return ""
end

function paper_artifact_latex_snippet(cert; label::AbstractString="certsdp-cert")
    verify(cert) || throw(ArgumentError("paper artifacts require a verified certificate"))
    cert_json = certificate_json_v1(cert)
    certificate_type = String(_paper_artifact_certificate_type(cert_json))
    certificate_id = _paper_artifact_certificate_id(cert_json)
    return "\\paragraph{CertSDP certificate.} The claim is accompanied by a data-only \\texttt{$certificate_type} artifact with identifier \\texttt{$certificate_id}. The artifact was checked by \\texttt{bin/certsdp verify --strict certificate.json}; see \\texttt{$label} for replay files."
end

function _paper_artifact_redacted_provenance(cert)
    cert_json = certificate_json_v1(cert)
    provenance = haskey(cert_json, :provenance) ? cert_json.provenance :
                 (; certsdp_version=string(package_version()),
                  julia_version=string(VERSION),
                  schema_version=SCHEMA_V1_VERSION,)
    return (;
            provenance,
            redaction=(;
                       policy="data-only artifact; backend logs and local paths are excluded",
                       excluded=["solver logs", "backend output", "absolute local paths"],),)
end

function _paper_artifact_readme(manifest)
    title = isempty(manifest.title) ? "CertSDP Reviewer Artifact" : manifest.title
    return """
# $title

This directory is a data-only CertSDP reviewer artifact.

Run:

```sh
$(manifest.replay_command)
```

Expected result: strict replay accepts `certificate.json`.

Trust boundary: $(manifest.trust_boundary)
"""
end
