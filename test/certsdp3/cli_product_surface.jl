@testset "Gate P CLI v3 product surface" begin
    fixture = certsdp3_low_rank_fixture(n=4)
    dir = mktempdir()
    cert_path = joinpath(dir, "certificate.json")
    certsdp3_write_json(cert_path, K3.certificate_json_v3(fixture.cert))

    out = IOBuffer()
    err = IOBuffer()
    @test CertSDP.main(["replay", cert_path, "--strict", "--explain"];
                       io=out, err=err) == CertSDP.CLI_EXIT_OK
    @test occursin("accepted", String(take!(out)))

    out = IOBuffer()
    err = IOBuffer()
    @test CertSDP.main(["schema", "validate", cert_path, "--kind",
                        "certificate"]; io=out, err=err) == CertSDP.CLI_EXIT_OK
    @test CertSDP.main(["schema", "validate", cert_path];
                       io=IOBuffer(), err=IOBuffer()) == CertSDP.CLI_EXIT_OK

    version_out = IOBuffer()
    @test CertSDP.main(["version", "--json"]; io=version_out,
                       err=IOBuffer()) == CertSDP.CLI_EXIT_OK
    @test JSON3.read(String(take!(version_out)))[:certsdp3] == true

    help_out = IOBuffer()
    @test CertSDP.Apps.certsdp3_cli_main(["help"]; io=help_out,
                                         err=IOBuffer()) == CertSDP.CLI_EXIT_OK
    @test occursin("certsdp replay", String(take!(help_out)))

    report_path = joinpath(dir, "report.html")
    out = IOBuffer()
    err = IOBuffer()
    @test CertSDP.main(["diagnose", cert_path, "--format", "html", "--out",
                        report_path]; io=out, err=err) == CertSDP.CLI_EXIT_OK
    @test isfile(report_path)
    @test filesize(report_path) > 0
    diagnose_json = IOBuffer()
    @test CertSDP.main(["diagnose", cert_path, "--format", "json"];
                       io=diagnose_json, err=IOBuffer()) == CertSDP.CLI_EXIT_OK
    @test JSON3.read(String(take!(diagnose_json)))[:accepted] == true

    bad = certsdp3_cert_json(fixture.cert)
    bad[:proof][:matrix][:entries][1][:value] = "2"
    bad[:proof][:matrix][:hash] = "sha256:" * repeat("0", 64)
    bad_path = joinpath(dir, "tampered.json")
    certsdp3_write_json(bad_path, bad)
    @test CertSDP.main(["replay", bad_path, "--strict"]; io=IOBuffer(),
                       err=IOBuffer()) != CertSDP.CLI_EXIT_OK

    sdpa_path = joinpath(dir, "small.dat-s")
    write(sdpa_path, """
    1 = mDIM
    1 = nBLOCK
    2 = bLOCKsTRUCT
    0
    0 1 1 1 -1
    1 1 2 2 2
    """)
    problem_out = joinpath(dir, "problem.json")
    @test CertSDP.main(["import", "sdpa", sdpa_path, "--out", problem_out];
                       io=IOBuffer(), err=IOBuffer()) == CertSDP.CLI_EXIT_OK
    @test K3.validate_problem_schema_v3(read(problem_out, String))
    @test CertSDP.main(["schema", "validate", problem_out, "--kind",
                        "problem"]; io=IOBuffer(),
                       err=IOBuffer()) == CertSDP.CLI_EXIT_OK

    tssos_matrix = K3.SparseSymmetricRationalMatrix(2,
        [(1, 1, 1//1), (2, 2, 1//1)])
    tssos_proof = K3.ExactLowRankPSDProof(tssos_matrix,
                                          [[1//1, 0//1], [0//1, 1//1]],
                                          [1//1, 1//1])
    tssos_artifact = Dict(
        "certsdp_tssos_artifact_version" => "3.0",
        "variables" => ["x$i" for i in 1:12],
        "objective_polynomial" => Any[
            Dict("exponents" => [i == 1 ? 2 : 0 for i in 1:12],
                 "coefficient" => "1"),
            Dict("exponents" => [i == 2 ? 2 : 0 for i in 1:12],
                 "coefficient" => "1"),
        ],
        "constraints" => Any[],
        "cliques" => Any[[ "x1", "x2", "x3", "x4" ],
                          [ "x5", "x6", "x7", "x8" ]],
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
                 "gram_matrix" => K3.sparse_matrix_json(tssos_matrix),
                 "psd_proof" => K3.low_rank_proof_json(tssos_proof)),
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
        "provenance" => Dict("status" => "ignored"),
        "frontend_metadata" => Dict("package" => "TSSOS-test"),
        "solver_metadata" => Dict("solver_status" => "ignored"),
        "source_raw_hash" => "sha256:" * repeat("a", 64),
    )
    tssos_path = joinpath(dir, "tssos.json")
    tssos_artifact["artifact_hash"] = "sha256:" * repeat("0", 64)
    tssos_artifact["artifact_hash"] =
        CertSDP.tssos_artifact_hash(certsdp3_write_json(tssos_path,
                                                         tssos_artifact))
    certsdp3_write_json(tssos_path, tssos_artifact)
    @test CertSDP.main(["import", "tssos", tssos_path, "--out",
                        joinpath(dir, "tssos_candidate.json")];
                       io=IOBuffer(), err=IOBuffer()) == CertSDP.CLI_EXIT_OK

    nctssos_artifact = Dict(
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
        "block_bases" => Any[Dict("id" => "basis_1",
                                  "words" => Any[Any[], Any["A1"], Any["B1"]])],
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
        "source_hash" => "sha256:" * repeat("4", 64),
    )
    moment = K3.SparseSymmetricRationalMatrix(3, [(i, i, 1//1) for i in 1:3])
    factor = [[i == j ? 1//1 : 0//1 for j in 1:3] for i in 1:3]
    psd = K3.ExactLowRankPSDProof(moment, factor, fill(1//1, 3))
    push!(nctssos_artifact["gram_blocks"],
          Dict("id" => "moment_1",
               "basis_id" => "basis_1",
               "moment_matrix" => K3.sparse_matrix_json(moment),
               "psd_proof" => K3.low_rank_proof_json(psd)))
    nctssos_artifact["rewrite_witnesses"] = Any[
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
    nctssos_artifact["artifact_hash"] =
        CertSDP.Adapters._artifact_hash(nctssos_artifact)
    nctssos_path = joinpath(dir, "nctssos.json")
    certsdp3_write_json(nctssos_path, nctssos_artifact)
    nctssos_out = joinpath(dir, "nctssos_candidate.json")
    @test CertSDP.main(["import", "nctssos", nctssos_path, "--out", nctssos_out];
                       io=IOBuffer(), err=IOBuffer()) == CertSDP.CLI_EXIT_OK
    @test isfile(nctssos_out)

    @test CertSDP.main(["replay", cert_path, "--bad-option"];
                       io=IOBuffer(), err=IOBuffer()) != CertSDP.CLI_EXIT_OK
    @test CertSDP.main(["diagnose", cert_path, "--format", "xml"];
                       io=IOBuffer(), err=IOBuffer()) != CertSDP.CLI_EXIT_OK
    @test CertSDP.main(["import", "unknown", cert_path, "--out",
                        joinpath(dir, "nope.json")];
                       io=IOBuffer(), err=IOBuffer()) != CertSDP.CLI_EXIT_OK
end
