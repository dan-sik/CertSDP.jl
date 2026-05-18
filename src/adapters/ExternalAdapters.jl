"""
    ExternalAdapterSpec

Registry entry for an external exact-certificate ecosystem. Specs are not
runtime dependencies; they define the translation contract CertSDP expects
before an imported artifact can be considered for strict replay.
"""
struct ExternalAdapterSpec
    name::Symbol
    language::Symbol
    source_url::String
    families::Vector{Symbol}
    trusted_boundary::String
    production_gate::Symbol
end

function external_adapter_specs()
    return ExternalAdapterSpec[ExternalAdapterSpec(:RealCertify,
                                                   :maple,
                                                   "https://gricad-gitlab.univ-grenoble-alpes.fr/magronv/RealCertify",
                                                   [:rational_sos, :perturb_compensate,
                                                    :univariate_sos],
                                                   "translate exact SOS identities; do not trust Maple session logs",
                                                   :external_adapters),
                               ExternalAdapterSpec(:NCTSSOS,
                                                   :julia,
                                                   "https://wangjie212.github.io/NCTSSOS/dev",
                                                   [:commutative_sos, :noncommutative_sos,
                                                    :trace_sos],
                                                   "translate word/coefficient/Gram data; replay symbolic relations in CertSDP",
                                                   :nc_quantum),
                               ExternalAdapterSpec(:ClusteredLowRankSolver,
                                                   :julia,
                                                   "https://github.com/nanleij/ClusteredLowRankSolver.jl",
                                                   [:rational_sos, :number_field_sos,
                                                    :low_rank_sdp],
                                                   "translate number-field Gram data; replay field arithmetic and PSD signs in CertSDP",
                                                   :number_field),
                               ExternalAdapterSpec(:CertifiedQuantumBounds,
                                                   :julia,
                                                   "https://github.com/nininaceur/CertifiedQuantumBounds",
                                                   [:quantum_bounds, :noncommutative_sos],
                                                   "translate projected moment/SOS blocks; replay relations and PSD blocks in CertSDP",
                                                   :nc_quantum)]
end

function external_adapter_spec(name::Symbol)
    for spec in external_adapter_specs()
        spec.name === name && return spec
    end
    throw(ArgumentError("unknown external adapter spec `$name`"))
end

function external_adapter_spec_json(spec::ExternalAdapterSpec)
    return (;
            name=String(spec.name),
            language=String(spec.language),
            source_url=spec.source_url,
            families=String.(spec.families),
            trusted_boundary=spec.trusted_boundary,
            production_gate=String(spec.production_gate),)
end

const EXTERNAL_REPLAY_ARTIFACT_VERSION = "1.0"
const EXTERNAL_TRANSLATED_CERTIFICATE_FORMAT = "certsdp_certificate_v1"

struct ExternalReplayArtifact
    adapter::ExternalAdapterSpec
    source_format::String
    certificate::Any
    artifact_hash::String
    replay_report::String
    metadata::Dict{Symbol, Any}
end

"""
    external_replay_artifact_json(adapter_name, certificate; source_format)

Build a data-only external adapter artifact. External tools may contribute
metadata and translated certificate data, but strict replay accepts only the
embedded CertSDP certificate and ignores solver/session claims.
"""
function external_replay_artifact_json(adapter_name::Symbol,
                                       cert;
                                       source_format::AbstractString=String(adapter_name),
                                       metadata=Dict{Symbol, Any}())
    verify(cert) ||
        throw(ArgumentError("external replay artifacts require a verified translated CertSDP certificate"))
    adapter = external_adapter_spec(adapter_name)
    cert_json = certificate_json_v1(cert)
    report = _external_replay_report(cert_json)
    payload = (;
               certsdp_external_artifact_version=EXTERNAL_REPLAY_ARTIFACT_VERSION,
               adapter=external_adapter_spec_json(adapter),
               source_format=String(source_format),
               translated_certificate_format=EXTERNAL_TRANSLATED_CERTIFICATE_FORMAT,
               translated_certificate=cert_json,
               replay=(;
                       verifier="CertSDP strict replay",
                       accepted=true,
                       report,),
               metadata=_external_adapter_metadata_json(metadata),)
    return merge(payload, (; artifact_hash=_external_artifact_hash(payload),))
end

function parse_external_replay_artifact_json(json_text::AbstractString)
    parsed = _read_json_document(json_text, "external replay artifact")
    _require_object(parsed, "root")
    return parse_external_replay_artifact(parsed)
end

function parse_external_replay_artifact(parsed)
    _require_value(parsed, :certsdp_external_artifact_version,
                   EXTERNAL_REPLAY_ARTIFACT_VERSION,
                   "root.certsdp_external_artifact_version")
    adapter_object = _require_key(parsed, :adapter, "root")
    _require_object(adapter_object, "root.adapter")
    adapter_name = Symbol(_require_string(adapter_object, :name,
                                          "root.adapter.name"))
    adapter = external_adapter_spec(adapter_name)
    _require_value(parsed, :translated_certificate_format,
                   EXTERNAL_TRANSLATED_CERTIFICATE_FORMAT,
                   "root.translated_certificate_format")
    forbidden_keys = (:raw_solver_output, :solver_log, :backend_log,
                      :backend_output, :session_transcript, :floating_residuals)
    for key in forbidden_keys
        haskey(parsed, key) &&
            throw(ArgumentError("root.$(String(key)) is forbidden in external replay artifacts"))
    end
    cert_object = _require_key(parsed, :translated_certificate, "root")
    cert_text = JSON3.write(cert_object)
    verify_strict_json(cert_text) ||
        throw(ArgumentError("translated certificate did not pass CertSDP strict replay"))
    cert = parse_certificate_json(cert_text)

    supplied_hash = _require_string(parsed, :artifact_hash, "root.artifact_hash")
    payload = _external_artifact_payload_without_hash(parsed)
    computed_hash = _external_artifact_hash(payload)
    supplied_hash == computed_hash ||
        throw(ArgumentError("root.artifact_hash mismatch: expected $supplied_hash, computed $computed_hash"))
    replay = _require_key(parsed, :replay, "root")
    _require_object(replay, "root.replay")
    _require_value(replay, :accepted, true, "root.replay.accepted")
    report = _require_string(replay, :report, "root.replay.report")
    return ExternalReplayArtifact(adapter,
                                  _require_string(parsed, :source_format,
                                                  "root.source_format"),
                                  cert,
                                  supplied_hash,
                                  report,
                                  haskey(parsed, :metadata) ?
                                  _json_object_to_symbol_dict(_require_key(parsed,
                                                                           :metadata,
                                                                           "root")) :
                                  Dict{Symbol, Any}())
end

function read_external_replay_artifact(path::AbstractString)
    return parse_external_replay_artifact_json(read(path, String))
end

function write_external_replay_artifact(path::AbstractString,
                                        adapter_name::Symbol,
                                        cert;
                                        kwargs...)
    artifact = external_replay_artifact_json(adapter_name, cert; kwargs...)
    open(path, "w") do io
        JSON3.pretty(io, artifact)
        return println(io)
    end
    return path
end

function verify(artifact::ExternalReplayArtifact; io::Union{Nothing, IO}=nothing,
                kwargs...)
    try
        _check_or_report(io,
                         artifact.artifact_hash ==
                         _external_artifact_hash(_external_artifact_payload(artifact)),
                         "external replay artifact hash matches") ||
            return false
        _check_or_report(io,
                         verify(artifact.certificate; strict=true, kwargs...),
                         "translated certificate passes CertSDP strict replay") ||
            return false
        _ok(io,
            "external adapter artifact accepted for $(String(artifact.adapter.name))")
        return true
    catch err
        _fail(io,
              "external adapter artifact verification error: $(sprint(showerror, err))")
        return false
    end
end

function _external_adapter_metadata_json(metadata)
    if metadata isa AbstractDict
        return Dict(String(key) => _provenance_json_value(value)
                    for (key, value) in metadata)
    elseif metadata isa NamedTuple
        return Dict(String(key) => _provenance_json_value(value)
                    for (key, value) in pairs(metadata))
    elseif isnothing(metadata)
        return Dict{String, Any}()
    end
    throw(ArgumentError("external adapter metadata must be a dictionary, NamedTuple, or nothing"))
end

function _external_replay_report(cert_json)
    io = IOBuffer()
    ok = verify_strict_json(JSON3.write(cert_json); io)
    ok || throw(ArgumentError("translated certificate failed strict replay"))
    return String(take!(io))
end

function _external_artifact_hash(payload)
    return "sha256:" * bytes2hex(sha256(JSON3.write(payload)))
end

function _external_artifact_payload(artifact::ExternalReplayArtifact)
    cert_json = certificate_json_v1(artifact.certificate)
    return (;
            certsdp_external_artifact_version=EXTERNAL_REPLAY_ARTIFACT_VERSION,
            adapter=external_adapter_spec_json(artifact.adapter),
            source_format=artifact.source_format,
            translated_certificate_format=EXTERNAL_TRANSLATED_CERTIFICATE_FORMAT,
            translated_certificate=cert_json,
            replay=(;
                    verifier="CertSDP strict replay",
                    accepted=true,
                    report=artifact.replay_report,),
            metadata=_external_adapter_metadata_json(artifact.metadata),)
end

function _external_artifact_payload_without_hash(parsed)
    return (;
            certsdp_external_artifact_version=_require_string(parsed,
                                                              :certsdp_external_artifact_version,
                                                              "root.certsdp_external_artifact_version"),
            adapter=_require_key(parsed, :adapter, "root"),
            source_format=_require_string(parsed, :source_format,
                                          "root.source_format"),
            translated_certificate_format=_require_string(parsed,
                                                          :translated_certificate_format,
                                                          "root.translated_certificate_format"),
            translated_certificate=_require_key(parsed,
                                                :translated_certificate,
                                                "root"),
            replay=_require_key(parsed, :replay, "root"),
            metadata=haskey(parsed, :metadata) ? _require_key(parsed, :metadata,
                                  "root") :
                     Dict{String, Any}(),)
end
