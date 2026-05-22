@testset "Gate E proof DAG tamper diagnostics" begin
    fixture = certsdp3_low_rank_fixture(n=5)
    cert_json = certsdp3_cert_json(fixture.cert)

    removed = certsdp3_mutable_json(cert_json)
    pop!(removed[:proof_dag][:nodes])
    @test_throws ArgumentError K3.parse_certificate_json_v3(JSON3.write(removed))

    changed_hash = certsdp3_mutable_json(cert_json)
    changed_hash[:proof_dag][:nodes][1][:output_hash] = "sha256:" * repeat("8", 64)
    @test_throws ArgumentError K3.parse_certificate_json_v3(JSON3.write(changed_hash))

    changed_checker = certsdp3_mutable_json(cert_json)
    changed_checker[:proof_dag][:nodes][1][:checker] = "metadata_claim"
    @test_throws ArgumentError K3.parse_certificate_json_v3(JSON3.write(changed_checker))

    dag = fixture.cert.dag
    bad_dag = K3.CertificateDAG(dag.claim_type,
                                dag.nodes,
                                "sha256:" * repeat("9", 64),
                                dag.schema_version)
    report = K3.verify_proof_dag(bad_dag)
    @test !report.accepted
    @test report.stage == :proof_dag
    @test report.obligation_id == :root_hash
end
