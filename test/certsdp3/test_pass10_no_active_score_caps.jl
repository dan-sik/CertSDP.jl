@testset "PASS_10 no active score caps" begin
    run(`$(Base.julia_cmd()) --project=$(normpath(joinpath(@__DIR__, "..", ".."))) --startup-file=no $(joinpath(@__DIR__, "..", "..", "scripts", "release_audit_certsdp3.jl")) --gate G`)
    report = JSON3.read(read(joinpath(@__DIR__, "..", "..", "build",
                                      "certsdp3_audit_report.json"), String))
    @test String(report[:result]) == "PASS_10"
    @test isempty(get(report, :active_score_caps, Any[]))
end
