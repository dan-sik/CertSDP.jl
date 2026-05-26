@testset "true external raw fixture policy" begin
    raw_path = joinpath(@__DIR__, "..", "fixtures_real_external",
                        "raw_source_artifact.json")
    raw = JSON3.read(read(raw_path, String))
    @test !haskey(raw, :certsdp_certificate_version)
    @test String(raw[:source_hash]) == "sha256:86d5da99c363731730a147b57c22ad9e6455c799d8656a3d030d992808e45e6b"
end
