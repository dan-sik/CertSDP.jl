@testset "CertSDP3 CI workflow exists" begin
    root = normpath(joinpath(@__DIR__, "..", ".."))
    path = joinpath(root, ".github", "workflows", "certsdp3.yml")
    @test isfile(path)
    text = read(path, String)
    @test occursin("release_audit_certsdp3.jl --strict --full", text)
    @test occursin("Pkg.test()", text)
end

