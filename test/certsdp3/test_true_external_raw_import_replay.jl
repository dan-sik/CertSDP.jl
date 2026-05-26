@testset "true external raw import replay" begin
    raw = joinpath(@__DIR__, "..", "fixtures_real_external", "raw_source_artifact.json")
    out = tempname() * ".json"
    run(`$(Base.julia_cmd()) --project=$(normpath(joinpath(@__DIR__, "..", ".."))) --startup-file=no $(joinpath(@__DIR__, "..", "fixtures_real_external", "capture_or_converter_script.jl")) $raw $out`)
    @test K3.replay_file(out; strict=true, io=nothing).accepted
end
