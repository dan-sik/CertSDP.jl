@testset "external-like TSSOS raw import" begin
    root = normpath(joinpath(@__DIR__, "..", "fixtures_external", "tssos"))
    path = joinpath(root, "raw_tssos_sparse_poly_medium.json")
    result = CertSDP.certify_raw_tssos_artifact(path)
    @test result isa CertSDP.CertifiedResult
    @test CertSDP.Kernel.verify_sparse_sos_certificate(result.certificate).accepted
end

