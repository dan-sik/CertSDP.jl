@testset "Exact certificate compiler regression" begin
    @testset "field discovery stays minimal" begin
        @test CertSDP.infer_field(Dict(:field_marker => :QQ)) == CertSDP.QQ
        @test CertSDP.infer_field(Dict(:field_marker => :sqrt2)) ==
              CertSDP.QuadraticField(2)
        @test CertSDP.infer_field(Dict(:field_marker => :sqrt2_sqrt5)) ==
              CertSDP.MultiquadraticField([2, 5])

        over_budget = CertSDP.reconstruct(Dict(:field_marker => :cubic_plastic);
                                          max_field_degree=2)
        @test over_budget.status === :failed
        @test over_budget.failure_stage === :field_degree_budget_exceeded
    end

    @testset "import reconstruct minimize replay smoke" begin
        for (index, (format, seed)) in enumerate(((:sumofsquares_like, 11),
                                                  (:tssos_like, 12),
                                                  (:nctssos_like, 13),
                                                  (:clustered_low_rank_like, 14)))
            instance = CertSDP.import_artifact(Dict(:format => String(format),
                                                    :seed => seed))
            result = CertSDP.reconstruct(instance)
            @test result.status === :ok
            cert = result.certificate
            @test CertSDP.verify(cert; mode=:strict).status === :valid

            if index == 1
                minimized = CertSDP.minimize(cert)
                @test CertSDP.verify(minimized; mode=:strict).status === :valid
                @test CertSDP.replay(String(CertSDP.json(minimized));
                                     mode=:strict).status === :valid
            end
        end
    end

    @testset "tampering is rejected at strict replay" begin
        result = CertSDP.reconstruct(Dict(:field_marker => :sqrt2_sqrt5,
                                          :seed => 21))
        @test result.status === :ok
        cert = result.certificate
        bad = CertSDP.ExactCertificateArtifact(cert.type,
                                               cert.num_variables,
                                               CertSDP.QuadraticField(10),
                                               cert.blocks,
                                               cert.structure,
                                               cert.problem,
                                               cert.certificate,
                                               cert.reconstruction_log,
                                               cert.verification_plan,
                                               cert.failure_diagnostics,
                                               cert.hashes,
                                               cert.metadata)
        @test CertSDP.verify(bad; mode=:strict).status === :invalid
    end
end
