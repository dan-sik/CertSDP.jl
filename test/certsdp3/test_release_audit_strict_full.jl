@testset "strict full release audit subprocess" begin
    root = normpath(joinpath(@__DIR__, "..", ".."))
    report = joinpath(root, "build", "certsdp3_audit_report.json")
    proc = run(pipeline(`$(Base.julia_cmd()) --project=$(root) --startup-file=no $(joinpath(root, "scripts", "release_audit_certsdp3.jl")) --strict --full --out $report`;
                        stdout=IOBuffer(), stderr=IOBuffer()); wait=false)
    wait(proc)
    @test proc.exitcode == 0
    parsed = JSON3.read(read(report, String))
    @test parsed[:result] == "PASS"
    @test haskey(parsed, :ci)
end

