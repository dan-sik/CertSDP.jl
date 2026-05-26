@testset "gate-specific audit subprocesses" begin
    root = normpath(joinpath(@__DIR__, "..", ".."))
    expected_blocked = Set(["G"])
    for gate in ["E", "G", "QA"]
        out = IOBuffer()
        err = IOBuffer()
        proc = run(pipeline(`$(Base.julia_cmd()) --project=$(root) --startup-file=no $(joinpath(root, "scripts", "release_audit_certsdp3.jl")) --gate $gate`;
                            stdout=out, stderr=err); wait=false)
        wait(proc)
        text = String(take!(out)) * String(take!(err))
        if gate in expected_blocked
            @test proc.exitcode != 0
            @test occursin("result: FAIL", text)
        else
            @test proc.exitcode == 0
        end
    end
end
