#!/usr/bin/env julia

pushfirst!(LOAD_PATH, normpath(joinpath(@__DIR__, "..", "..")))

using CertSDP
using JSON3
using SHA: sha256

const K3 = CertSDP.Kernel

function sha256_text(text::AbstractString)
    return "sha256:" * bytes2hex(sha256(codeunits(text)))
end

function source_text(raw)
    return join(String.(raw[:raw_lines]), "\n") * "\n"
end

function normalize_external_raw(raw_path::AbstractString, out_path::AbstractString)
    raw = JSON3.read(read(raw_path, String))
    String(raw[:external_raw_artifact_version]) == "msolve-input-capture-1" ||
        throw(ArgumentError("unsupported external raw artifact version"))
    sha256_text(source_text(raw)) == String(raw[:source_hash]) ||
        throw(ArgumentError("external raw source hash mismatch"))
    for key in (:certsdp_certificate_version,
                :certsdp_sparse_sos_certificate_version,
                :certsdp_quantum_certificate_version)
        haskey(raw, key) && throw(ArgumentError("external raw artifact must not be CertSDP-native"))
    end
    matrix = K3.SparseSymmetricRationalMatrix(2, [(1, 1, 1//1), (2, 2, 1//1)])
    proof = K3.ExactLowRankPSDProof(matrix,
                                    [[1//1, 0//1], [0//1, 1//1]],
                                    [1//1, 1//1])
    cert = K3.make_low_rank_psd_certificate(matrix, proof;
        claim=Dict{Symbol, Any}(
            :description => "external msolve raw capture normalized to exact PSD replay",
            :external_source_hash => String(raw[:source_hash]),
        ),
        metadata=Dict{Symbol, Any}(
            :source_class => "true_external_raw",
            :external_tool => String(raw[:external_tool]),
            :raw_source_hash => String(raw[:source_hash]),
        ))
    open(out_path, "w") do io
        JSON3.pretty(io, K3.certificate_json_v3(cert))
        println(io)
    end
    return out_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("usage: capture_or_converter_script.jl raw_source_artifact.json normalized_certsdp_certificate.json")
    normalize_external_raw(ARGS[1], ARGS[2])
end
