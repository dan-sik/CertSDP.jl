@testset "Gate I TSSOS importer" begin
    dir = mktempdir()
    artifact_path = joinpath(dir, "artifact.json")
    variables = ["x$i" for i in 1:12]
    matrix = K3.SparseSymmetricRationalMatrix(2, [(1, 1, 1//1), (2, 2, 1//1)])
    proof = K3.ExactLowRankPSDProof(matrix, [[1//1, 0//1], [0//1, 1//1]],
                                    [1//1, 1//1])
    artifact = Dict(
        "certsdp_tssos_artifact_version" => "3.0",
        "variables" => variables,
        "objective_polynomial" => Any[
            Dict("exponents" => [i == 1 ? 2 : 0 for i in 1:12],
                 "coefficient" => "1"),
            Dict("exponents" => [i == 2 ? 2 : 0 for i in 1:12],
                 "coefficient" => "1"),
        ],
        "constraints" => Any[],
        "cliques" => Any[variables[1:4], variables[5:8], variables[9:12],
                          variables[3:6], variables[7:10]],
        "monomial_bases" => Any[
            Dict("id" => "basis_1",
                 "exponents" => Any[
                     [i == 1 ? 1 : 0 for i in 1:12],
                     [i == 2 ? 1 : 0 for i in 1:12],
                 ]),
        ],
        "gram_blocks" => Any[
            Dict("id" => "gram_1",
                 "clique_id" => "clique_1",
                 "basis_id" => "basis_1",
                 "gram_matrix" => K3.sparse_matrix_json(matrix),
                 "psd_proof" => K3.low_rank_proof_json(proof)),
        ],
        "localizing_blocks" => Any[],
        "coefficient_maps" => Any[
            Dict("block_id" => "gram_1",
                 "terms" => Any[
                     Dict("exponents" => [i == 1 ? 2 : 0 for i in 1:12],
                          "coefficient" => "1"),
                     Dict("exponents" => [i == 2 ? 2 : 0 for i in 1:12],
                          "coefficient" => "1"),
                 ]),
        ],
        "bound" => "0",
        "provenance" => Dict("frontend" => "TSSOS",
                             "status" => "must_not_be_trusted"),
        "frontend_metadata" => Dict("package" => "TSSOS-test"),
        "solver_metadata" => Dict("solver_status" => "ignored"),
        "source_raw_hash" => "sha256:" * repeat("a", 64),
    )
    artifact["artifact_hash"] = "sha256:" * repeat("0", 64)
    artifact["artifact_hash"] = CertSDP.tssos_artifact_hash(certsdp3_write_json(artifact_path,
                                                                                 artifact))
    certsdp3_write_json(artifact_path, artifact)

    candidate = CertSDP.import_tssos_artifact(artifact_path)
    @test candidate.source === :tssos
    @test CertSDP.verify_tssos_certificate(candidate)
    @test CertSDP.certify_tssos_artifact(artifact_path) isa CertSDP.CertifiedResult
end
