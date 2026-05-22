@testset "Gate W symmetry reduction" begin
    variables = [:x1, :x2, :x3]
    group = K3.SymmetryGroupCertificate(variables,
                                        [K3.SymmetryPermutation(:cycle,
                                                               [2, 3, 1])])
    orbit = K3.OrbitBasisCertificate([[2, 0, 0], [0, 2, 0], [0, 0, 2]],
                                     [[1, 2, 3]])
    original = K3.SparseSymmetricRationalMatrix(3, [(i, i, 1//1) for i in 1:3])
    cert = K3.BlockDiagonalizationCertificate(original.hash, group, orbit,
                                              [original], original, original)
    @test K3.verify_block_diagonalization_certificate(cert).accepted

    json = K3.block_diagonalization_certificate_json(cert)
    parsed = K3.parse_block_diagonalization_certificate_json(JSON3.write(json))
    @test parsed.certificate_hash == cert.certificate_hash

    bad_json = certsdp3_mutable_json(json)
    bad_json[:group][:generators][1][:image] = [1, 2, 3]
    @test_throws ArgumentError K3.parse_block_diagonalization_certificate_json(JSON3.write(bad_json))
end
