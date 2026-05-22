@testset "Gate O diagnostics report" begin
    fixture = certsdp3_low_rank_fixture(n=4)
    report = K3.verify_certificate(fixture.cert)
    @test report.accepted
    @test occursin("accepted", K3.diagnostic_report_text(report))
    @test K3.diagnostic_report_json(report).accepted
    @test occursin("<html", K3.diagnostic_report_html(report))

    bad_matrix = K3.SparseSymmetricRationalMatrix(4, [(1, 1, 2//1)])
    bad = K3.verify_low_rank_psd(bad_matrix, fixture.proof)
    @test !bad.accepted
    @test bad.stage != :unknown
    @test bad.reason != ""
    @test bad.obligation_id != :unknown
    @test occursin("rejected", K3.diagnostic_report_text(bad))
end
