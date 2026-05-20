@testset "Exact certificate compiler regression" begin
    @testset "field discovery stays minimal" begin
        @test CertSDP.infer_field(Dict(:field_marker => :QQ)) == CertSDP.QQ
        @test CertSDP.infer_field(Dict(:field_marker => :sqrt2)) ==
              CertSDP.QuadraticField(2)
        @test CertSDP.infer_field(Dict(:field_marker => :sqrt2_sqrt5)) ==
              CertSDP.MultiquadraticField([2, 5])
        evidence = Dict(:kind => "multiquadratic",
                        :radicands => [2, 5],
                        :basis_support => [[], [1], [2], [1, 2]],
                        :degree_bound => 4)
        @test CertSDP.infer_field(Dict(:field_evidence => evidence)) ==
              CertSDP.MultiquadraticField([2, 5])
        numeric = Dict(:kind => "numeric_recognition",
                       :approx_coefficients => ["1.4142135623730950488",
                                                "2.2360679774997896964"],
                       :budget => Dict(:max_degree => 4,
                                       :max_height => 10000))
        @test CertSDP.infer_field(Dict(:field_evidence => numeric)) ==
              CertSDP.MultiquadraticField([2, 5])
        witnesses = CertSDP._field_recognition_witnesses(numeric)
        @test length(witnesses) == 2
        @test all(witness -> witness[:engine] ==
                             "bounded_pslq_integer_relation",
                  witnesses)
        cubic_numeric = Dict(:kind => "numeric_recognition",
                             :approx_coefficients => ["1.324717957244746025960908854"],
                             :budget => Dict(:max_degree => 3,
                                             :max_height => 100))
        @test CertSDP.infer_field(Dict(:field_evidence => cubic_numeric)) ==
              CertSDP.AlgebraicFieldSpec(CertSDP.parse_polynomial("t^3 - t - 1"))

        over_budget = CertSDP.reconstruct(Dict(:field_marker => :cubic_plastic);
                                          max_field_degree=2)
        @test over_budget.status === :failed
        @test over_budget.failure_stage === :field_degree_budget_exceeded
    end

    @testset "import reconstruct minimize replay smoke" begin
        fixtures = CertSDP._external_fixture_paths()
        for (index, fixture) in enumerate(fixtures)
            instance = CertSDP.import_artifact(fixture)
            result = CertSDP.reconstruct(instance)
            @test result.status === :ok
            cert = result.certificate
            @test CertSDP.verify(cert; mode=:strict).status === :valid
            @test haskey(cert.metadata, :source_path)
            @test haskey(cert.metadata, :field_evidence)

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
                                                :field_evidence => Dict(:kind => "rational",
                                                                        :basis_support => [[]]),
                                                :cliques => [[1, 2, 3]],
                                                :localizing_multipliers => [Dict(:constraint => "g_1")],
                                                :sparse_gram_blocks => [Dict(:id => "b1")],
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
        @test_throws ArgumentError CertSDP.import_artifact(Dict(:format => "nctssos_like",
                                                                :words => [["A:0:0"]],
                                                                :relations => [],
                                                                :trace_blocks => [Dict(:id => "b")],
                                                                :seed => 1))
        manifest = CertSDP.external_fixture_pack_manifest()
        @test !isempty(manifest[:packs])
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
        saved = CertSDP.compile_fixture(:sparse_opf_like; seed=0)
        @test haskey(saved.metadata, :saved_noisy_artifact_hash)
        @test length(saved.certificate[:exact_sparse_identity][:rhs_terms]) >= 5
        @test any(term -> term[:kind] == "equality_multiplier",
                  saved.certificate[:exact_sparse_identity][:rhs_terms])
        hidden_saved = CertSDP.compile_fixture(:sparse_opf_like; seed=118260)
        @test haskey(hidden_saved.metadata, :saved_noisy_artifact_hash)
        @test CertSDP.verify(hidden_saved; mode=:strict).status === :valid

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

        identity = deepcopy(cert.certificate[:exact_sparse_identity])
        identity[:rhs_terms][2][:constraint][1][:coefficient] = "2"
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

    @testset "NC trace quotient replay is checked" begin
        cert = CertSDP.compile_fixture(:nc_trace_npa; seed=73)
        @test CertSDP.verify(cert; mode=:strict).status === :valid

        certificate = copy(cert.certificate)
        replay = deepcopy(certificate[:nc_trace_quotient_replay])
        replay[:examples][1][:canonical] = ["B:2:0", "A:0:1"]
        certificate[:nc_trace_quotient_replay] = replay
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
        bad = CertSDP._with_reconstruction_witnesses(bad, :nc_trace_npa, 73)
        result = CertSDP.verify(bad; mode=:strict)
        @test result.status === :invalid
        @test result.failure_stage === :trace_quotient_error

        certificate = copy(cert.certificate)
        identity = deepcopy(certificate[:nc_trace_coefficient_identity])
        identity[:rhs][1][:coefficient] = "7"
        certificate[:nc_trace_coefficient_identity] = identity
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
        bad = CertSDP._with_reconstruction_witnesses(bad, :nc_trace_npa, 73)
        result = CertSDP.verify(bad; mode=:strict)
        @test result.status === :invalid
        @test result.failure_stage === :nc_identity_error

        certificate = copy(cert.certificate)
        identity = deepcopy(certificate[:nc_trace_coefficient_identity])
        identity[:lhs][4][:polynomial][1][:coefficient] = "2"
        certificate[:nc_trace_coefficient_identity] = identity
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
        bad = CertSDP._with_reconstruction_witnesses(bad, :nc_trace_npa, 73)
        result = CertSDP.verify(bad; mode=:strict)
        @test result.status === :invalid
        @test result.failure_stage === :nc_identity_error
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
