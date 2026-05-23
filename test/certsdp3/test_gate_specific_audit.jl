@testset "gate-specific audit subprocesses" begin
    root = normpath(joinpath(@__DIR__, "..", ".."))
    for gate in ["E", "H", "I", "J", "K", "P", "X", "QA"]
        proc = run(pipeline(`$(Base.julia_cmd()) --project=$(root) --startup-file=no $(joinpath(root, "scripts", "release_audit_certsdp3.jl")) --gate $gate`;
                            stdout=IOBuffer(), stderr=IOBuffer()); wait=false)
        wait(proc)
        @test proc.exitcode == 0
    end
end

