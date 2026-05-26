@testset "Gate K NCTSSOS importer" begin
    artifact = Dict(
        "certsdp_nctssos_artifact_version" => "3.0",
        "variables" => ["A1", "B1"],
        "words" => Any[Any[], Any["A1"], Any["B1"], Any["A1", "A1"],
                       Any["A1", "B1"]],
        "involution_convention" => "star_suffix",
        "trace_cyclic" => true,
        "quotient_relations" => Any[
            Dict("kind" => "ProjectionRelation", "id" => "proj_A1",
                 "data" => Dict("symbol" => "A1")),
            Dict("kind" => "CommutationRelation", "id" => "comm_AB",
                 "data" => Dict("left_symbols" => ["A1"],
                                "right_symbols" => ["B1"])),
            Dict("kind" => "NormalizationRelation", "id" => "trace_one",
                 "data" => Dict("value" => "1")),
        ],
        "block_bases" => Any[
            Dict("id" => "basis_1",
                 "words" => Any[Any[], Any["A1"], Any["B1"]])
        ],
        "gram_blocks" => Any[],
        "coefficient_maps" => Any[
            Dict("block_id" => "moment_1",
                "terms" => Any[
                    Dict("word" => Any[], "coefficient" => "1"),
                    Dict("word" => ["A1_star", "A1"], "coefficient" => "1"),
                    Dict("word" => ["B1_star", "B1"], "coefficient" => "1"),
                 ])
        ],
        "objective_bound" => "3",
        "provenance" => Dict("status" => "ignored"),
        "frontend_metadata" => Dict("package" => "NCTSSOS-test"),
        "solver_metadata" => Dict("solver_status" => "ignored"),
        "source_hash" => "sha256:" * repeat("3", 64),
    )
    matrix = K3.SparseSymmetricRationalMatrix(3, [(i, i, 1//1) for i in 1:3])
    factor = [[i == j ? 1//1 : 0//1 for j in 1:3] for i in 1:3]
    proof = K3.ExactLowRankPSDProof(matrix, factor, fill(1//1, 3))
    push!(artifact["gram_blocks"],
          Dict("id" => "moment_1",
               "basis_id" => "basis_1",
               "moment_matrix" => K3.sparse_matrix_json(matrix),
               "psd_proof" => K3.low_rank_proof_json(proof)))
    artifact["rewrite_witnesses"] = Any[
        Dict("input_word" => Any[],
             "steps" => Any[],
             "final_word" => Any[],
             "relation_ids_used" => Any[],
             "trace_rotations" => Any[],
             "star_steps" => Any[]),
        Dict("input_word" => Any["A1_star", "A1"],
             "steps" => Any[],
             "final_word" => Any["A1_star", "A1"],
             "relation_ids_used" => Any[],
             "trace_rotations" => Any[],
             "star_steps" => Any[]),
        Dict("input_word" => Any["B1_star", "B1"],
             "steps" => Any[],
             "final_word" => Any["B1_star", "B1"],
             "relation_ids_used" => Any[],
             "trace_rotations" => Any[],
             "star_steps" => Any[]),
    ]
    artifact["artifact_hash"] = CertSDP.Adapters._artifact_hash(artifact)
    dir = mktempdir()
    path = joinpath(dir, "artifact.json")
    certsdp3_write_json(path, artifact)
    candidate = CertSDP.import_nctssos_artifact(path)
    @test candidate.source === :nctssos
    @test K3.verify_quantum_bound_certificate(candidate.certificate).accepted

    bad = deepcopy(artifact)
    bad["quotient_relations"][1]["data"]["symbol"] = "BAD"
    bad["artifact_hash"] = CertSDP.Adapters._artifact_hash(bad)
    bad_path = joinpath(dir, "tampered.json")
    certsdp3_write_json(bad_path, bad)
    @test CertSDP.certify_nctssos_artifact(bad_path) isa CertSDP.FailureResult
end
