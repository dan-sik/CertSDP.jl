@testset "PASS_10 audit report evidence fields" begin
    run(`$(Base.julia_cmd()) --project=$(normpath(joinpath(@__DIR__, "..", ".."))) --startup-file=no $(joinpath(@__DIR__, "..", "..", "scripts", "release_audit_certsdp3.jl")) --gate J`)
    report = JSON3.read(read(joinpath(@__DIR__, "..", "..", "build",
                                      "certsdp3_audit_report.json"), String))
    for key in (:result, :gate_scores, :active_score_caps,
                :proof_relevant_hash_only_count,
                :moment_entry_nodes_executed)
        @test haskey(report, key)
    end
    @test report[:moment_entry_nodes_executed] > 0
end
