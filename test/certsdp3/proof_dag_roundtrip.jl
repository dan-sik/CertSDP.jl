@testset "Gate E proof DAG roundtrip and tamper" begin
    fixture = certsdp3_low_rank_fixture(n=5)
    cert_json = certsdp3_cert_json(fixture.cert)

    parsed = K3.parse_certificate_json_v3(JSON3.write(cert_json))
    @test K3.verify_proof_dag(parsed).accepted
    @test K3.proof_dag_json(parsed).root_hash == fixture.cert.dag.root_hash

    removed = copy(cert_json)
    removed[:proof_dag][:nodes] = removed[:proof_dag][:nodes][1:1]
    @test_throws ArgumentError K3.parse_certificate_json_v3(JSON3.write(removed))

    changed = copy(cert_json)
    changed[:proof_dag][:nodes][1][:checker] = "trust_me"
    @test_throws ArgumentError K3.parse_certificate_json_v3(JSON3.write(changed))

    dag = fixture.cert.dag
    bad_node = K3.ProofNode(dag.nodes[1].id, dag.nodes[1].kind,
                            dag.nodes[1].inputs,
                            "sha256:" * repeat("1", 64),
                            dag.nodes[1].checker,
                            dag.nodes[1].status)
    bad_dag = K3.CertificateDAG(dag.claim_type,
                                vcat([bad_node], dag.nodes[2:end]),
                                dag.root_hash,
                                dag.schema_version)
    report = K3.verify_proof_dag(bad_dag)
    @test !report.accepted
    @test report.stage == :proof_dag
end
