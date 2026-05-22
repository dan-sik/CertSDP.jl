@testset "Gate I TSSOS tamper rejection" begin
    mktempdir() do dir
        source = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                          "tssos_sparse_industry_medium", "artifact.json")
        artifact = certsdp3_mutable_json(JSON3.read(read(source, String)))

        bad = deepcopy(artifact)
        bad[:certificate_valid] = true
        bad[:artifact_hash] = CertSDP.Adapters._artifact_hash(bad)
        path = joinpath(dir, "truth_claim.json")
        certsdp3_write_json(path, bad)
        @test CertSDP.certify_tssos_artifact(path) isa CertSDP.FailureResult

        bad = deepcopy(artifact)
        bad[:coefficient_maps][1][:terms][1][:coefficient] = "2"
        bad[:artifact_hash] = CertSDP.Adapters._artifact_hash(bad)
        path = joinpath(dir, "coefficient.json")
        certsdp3_write_json(path, bad)
        @test CertSDP.certify_tssos_artifact(path) isa CertSDP.FailureResult

        bad = deepcopy(artifact)
        bad[:monomial_bases][1][:exponents][1][1] = 3
        bad[:artifact_hash] = CertSDP.Adapters._artifact_hash(bad)
        path = joinpath(dir, "basis.json")
        certsdp3_write_json(path, bad)
        @test CertSDP.certify_tssos_artifact(path) isa CertSDP.FailureResult
    end
end
