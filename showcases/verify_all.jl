using CertSDP
using JSON3

const ROOT = normpath(joinpath(@__DIR__, ".."))
const MANIFEST_PATH = joinpath(@__DIR__, "manifest.json")

function verify_certificate(path; label=relpath(path, ROOT))
    io = IOBuffer()
    ok = CertSDP.verify_strict(path; io)
    if ok
        println("[OK] ", label)
    else
        print(String(take!(io)))
        println("[FAIL] ", label)
    end
    return ok
end

function verify_sostools_pipeline(artifact)
    source_path = joinpath(ROOT, String(artifact.source_path))
    output_dir = mktempdir()
    cert_out = joinpath(output_dir, "cert.json")
    problem_out = joinpath(output_dir, "problem.json")
    solution_out = joinpath(output_dir, "solution.json")
    CertSDP.convert_sostools_lite_json(source_path;
                                       problem_out,
                                       solution_out,
                                       cert_out)
    ok = verify_certificate(cert_out;
                            label="converted " * String(artifact.source_path))
    return ok
end

function main()
    manifest = JSON3.read(read(MANIFEST_PATH, String))
    total = 0
    accepted = 0
    for artifact in manifest.artifacts
        total += 1
        kind = String(artifact.kind)
        ok = if kind == "certificate"
            verify_certificate(joinpath(ROOT, String(artifact.path)))
        elseif kind == "sostools_lite_pipeline"
            prebuilt_ok = verify_certificate(joinpath(ROOT,
                                                      String(artifact.certificate_path)))
            converted_ok = verify_sostools_pipeline(artifact)
            prebuilt_ok && converted_ok
        else
            error("unsupported showcase artifact kind: $kind")
        end
        accepted += ok ? 1 : 0
    end
    println("[INFO] showcase artifacts accepted: $accepted / $total")
    accepted == total || error("one or more showcase artifacts failed")
    return nothing
end

main()
