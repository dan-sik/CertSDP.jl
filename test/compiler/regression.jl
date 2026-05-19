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

    @testset "external artifact import validates source contract" begin
        instance = CertSDP.import_artifact(Dict(:format => "tssos_like",
                                                :artifact_kind => "external_tool_export",
                                                :source_hash => "sha256:" * repeat("a", 64),
                                                :blocks => [Dict(:id => "b1")],
                                                :seed => 91))
        @test instance[:kind] === :sparse_opf_like
        @test instance[:source_hash] == "sha256:" * repeat("a", 64)

        @test_throws ArgumentError CertSDP.import_artifact(Dict(:format => "tssos_like",
                                                                :source_hash => "not-a-hash",
                                                                :seed => 1))
        @test_throws ArgumentError CertSDP.import_artifact(Dict(:format => "tssos_like",
                                                                :blocks => [],
                                                                :seed => 1))
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

    @testset "exact sparse identity is replayed, not trusted" begin
        cert = CertSDP.compile_fixture(:sparse_opf_like; seed=31)
        @test CertSDP.verify(cert; mode=:strict).status === :valid
        @test CertSDP._verify_exact_sparse_identity(cert).status === :valid

        identity = deepcopy(cert.certificate[:exact_sparse_identity])
        identity[:rhs_terms][1][:scale] = "2"
        certificate = copy(cert.certificate)
        certificate[:exact_sparse_identity] = identity
        bad = CertSDP.ExactCertificateArtifact(cert.type,
                                               cert.num_variables,
                                               cert.field,
                                               cert.blocks,
                                               cert.structure,
                                               cert.problem,
                                               certificate,
                                               cert.reconstruction_log,
                                               cert.verification_plan,
                                               cert.failure_diagnostics,
                                               cert.hashes,
                                               cert.metadata)
        bad = CertSDP._with_reconstruction_witnesses(bad, :sparse_opf_like, 31)
        result = CertSDP.verify(bad; mode=:strict)
        @test result.status === :invalid
        @test result.failure_stage === :localizing_identity_error
    end

    @testset "exact affine identity is replayed, not trusted" begin
        cert = CertSDP.compile_fixture(:infeasibility; seed=62)
        @test CertSDP.verify(cert; mode=:strict).status === :valid
        @test CertSDP._verify_exact_affine_identity(cert).status === :valid

        affine = deepcopy(cert.certificate[:exact_affine_identity])
        affine[:equations][1][:lhs][1][:coefficient] = "999"
        certificate = copy(cert.certificate)
        certificate[:exact_affine_identity] = affine
        bad = CertSDP.ExactCertificateArtifact(cert.type,
                                               cert.num_variables,
                                               cert.field,
                                               cert.blocks,
                                               cert.structure,
                                               cert.problem,
                                               certificate,
                                               cert.reconstruction_log,
                                               cert.verification_plan,
                                               cert.failure_diagnostics,
                                               cert.hashes,
                                               cert.metadata)
        bad = CertSDP._with_reconstruction_witnesses(bad,
                                                     :quantum_code_infeasibility,
                                                     62)
        result = CertSDP.verify(bad; mode=:strict)
        @test result.status === :invalid
        @test result.failure_stage === :affine_dual_identity_error
    end

    @testset "compiler runtime gate measures work" begin
        elapsed = CertSDP.compiler_validation_runtime(; force=true)
        @test elapsed > 0
        @test elapsed <= 900
    end
end
