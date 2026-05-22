@testset "Gate U hash stability and canonicalization" begin
    fixture = certsdp3_low_rank_fixture(n=6)
    text = JSON3.write(K3.certificate_json_v3(fixture.cert))
    parsed = K3.parse_certificate_json_v3(text)
    text2 = JSON3.write(K3.certificate_json_v3(parsed))
    parsed2 = K3.parse_certificate_json_v3(text2)
    @test parsed.hash == parsed2.hash

    A = K3.SparseSymmetricRationalMatrix(4, [(4, 4, 2//4), (1, 2, 3//1)])
    B = K3.SparseSymmetricRationalMatrix(4, [(2, 1, 3//1), (4, 4, 1//2),
                                             (3, 3, 0//1)])
    @test A.hash == B.hash
    @test K3.rational_string(A[4, 4]) == "1/2"

    with_metadata = K3.make_low_rank_psd_certificate(fixture.matrix,
                                                     fixture.proof;
                                                     metadata=Dict(:a => 1,
                                                                   :b => 2))
    reordered = K3.make_low_rank_psd_certificate(fixture.matrix,
                                                 fixture.proof;
                                                 metadata=Dict(:b => 2,
                                                               :a => 1))
    @test with_metadata.hash == reordered.hash
end
