@testset "Gate Y migration to v3" begin
    P = CertSDP.LMIProblem([1//1 0//1; 0//1 1//1],
                           [[0//1 0//1; 0//1 0//1]];
                           vars=[:x])
    cert = CertSDP.certificate(CertSDP.certify(P, [0//1]))
    migrated = CertSDP.migrate_certificate_v1_to_v3(cert)
    @test migrated isa K3.V3Certificate
    @test K3.verify_certificate(migrated).accepted
    @test K3.verify_proof_dag(migrated).accepted
end
