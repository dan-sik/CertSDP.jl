using JSON3

@testset "positive polynomial showcase pack" begin
    root = normpath(joinpath(@__DIR__, "..", ".."))
    manifest_path = joinpath(root, "showcases", "manifest.json")
    manifest = JSON3.read(read(manifest_path, String))
    artifacts = collect(manifest.artifacts)

    @test length(artifacts) == manifest.total_artifacts
    @test count(artifact -> String(artifact.kind) == "certificate", artifacts) ==
          manifest.certificate_artifacts
    @test count(artifact -> String(artifact.kind) == "sostools_lite_pipeline",
                artifacts) == manifest.sostools_pipeline_artifacts

    for artifact in artifacts
        if String(artifact.kind) == "certificate"
            path = joinpath(root, String(artifact.path))
            cert = read_certificate(path)
            @test verify(cert)
            @test verify_strict(path)
        elseif String(artifact.kind) == "sostools_lite_pipeline"
            prebuilt_path = joinpath(root, String(artifact.certificate_path))
            @test verify_strict(prebuilt_path)

            output_dir = mktempdir()
            result = convert_sostools_lite_json(joinpath(root,
                                                         String(artifact.source_path));
                                                problem_out=joinpath(output_dir,
                                                                     "problem.json"),
                                                solution_out=joinpath(output_dir,
                                                                      "solution.json"),
                                                cert_out=joinpath(output_dir,
                                                                  "cert.json"))
            @test isfile(result.problem_out)
            @test isfile(result.solution_out)
            @test isfile(result.cert_out)
            @test verify_strict(result.cert_out)
        else
            @test false
        end
    end

    motzkin_path = joinpath(root, "showcases", "non_sos_classics",
                            "motzkin_affine_rational_function_sos.json")
    choi_lam_path = joinpath(root, "showcases", "non_sos_classics",
                             "choi_lam_quartic_rational_function_sos.json")
    putinar_path = joinpath(root, "showcases", "putinar",
                            "unit_disk_1_minus_x2y2.json")

    motzkin = read_certificate(motzkin_path)
    @test motzkin isa RationalFunctionSOSCertificate
    @test length(motzkin.numerator_squares) == 4
    @test length(motzkin.denominator_squares) == 1

    choi_lam = read_certificate(choi_lam_path)
    @test choi_lam isa RationalFunctionSOSCertificate
    @test length(choi_lam.numerator_squares) == 15
    @test length(choi_lam.denominator_squares) == 6

    putinar = read_certificate(putinar_path)
    @test putinar isa PositivstellensatzCertificate
    @test length(putinar.constraints) == 1
    @test length(putinar.terms) == 2
end

@testset "SOSTOOLS-lite converter" begin
    root = normpath(joinpath(@__DIR__, "..", ".."))
    input_path = joinpath(root, "showcases", "sostools",
                          "sostools_lite_xy_square.json")
    output_dir = mktempdir()
    problem_out = joinpath(output_dir, "xy_square_sos_gram.json")
    solution_out = joinpath(output_dir, "xy_square_gram_solution.json")
    cert_out = joinpath(output_dir, "xy_square_cert.json")

    result = convert_sostools_lite_json(input_path;
                                        problem_out,
                                        solution_out,
                                        cert_out)
    @test result.problem_out == problem_out
    @test isfile(problem_out)
    @test isfile(solution_out)
    @test isfile(cert_out)
    @test verify_strict(cert_out)
end
