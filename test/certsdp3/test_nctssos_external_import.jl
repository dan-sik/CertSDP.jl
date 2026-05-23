@testset "external-like NCTSSOS raw import requires witnesses" begin
    root = normpath(joinpath(@__DIR__, "..", "fixtures_external", "nctssos"))
    path = joinpath(root, "raw_nctssos_trace_medium.json")
    result = CertSDP.certify_raw_nctssos_artifact(path)
    @test result isa CertSDP.CertifiedResult
    raw = certsdp3_mutable_json(JSON3.read(read(path, String)))
    empty!(raw[:rewrite_witnesses])
    bad_path = tempname() * ".json"
    certsdp3_write_json(bad_path, raw)
    @test !(CertSDP.certify_raw_nctssos_artifact(bad_path) isa CertSDP.CertifiedResult)
end

