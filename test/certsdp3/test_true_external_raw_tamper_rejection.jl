@testset "true external raw tamper rejection" begin
    raw = joinpath(@__DIR__, "..", "fixtures_real_external", "tampered_raw_artifact.json")
    out = tempname() * ".json"
    cmd = `$(Base.julia_cmd()) --project=$(normpath(joinpath(@__DIR__, "..", ".."))) --startup-file=no $(joinpath(@__DIR__, "..", "fixtures_real_external", "capture_or_converter_script.jl")) $raw $out`
    @test !success(pipeline(cmd, stdout=devnull, stderr=devnull))
    bad_cert = joinpath(@__DIR__, "..", "fixtures_real_external",
                        "tampered_normalized_certificate.json")
    @test_throws ArgumentError K3.parse_certificate_json_v3(read(bad_cert, String); strict=true)
end
