@testset "positive polynomial showcase certificates" begin
    root = normpath(joinpath(@__DIR__, "..", ".."))
    motzkin_path = joinpath(root, "showcases", "motzkin",
                            "motzkin_rational_function_sos.json")
    hilbert_path = joinpath(root, "showcases", "hilbert17",
                            "x2_plus_1_rational_function_sos.json")
    putinar_path = joinpath(root, "showcases", "putinar", "box_1_minus_x2y2.json")

    motzkin = read_certificate(motzkin_path)
    @test motzkin isa RationalFunctionSOSCertificate
    @test verify(motzkin)
    @test verify_strict(motzkin_path)
    @test length(motzkin.numerator_squares) == 4
    @test length(motzkin.denominator_squares) == 1

    hilbert = read_certificate(hilbert_path)
    @test hilbert isa RationalFunctionSOSCertificate
    @test verify(hilbert)
    @test verify_strict(hilbert_path)

    putinar = read_certificate(putinar_path)
    @test putinar isa PositivstellensatzCertificate
    @test verify(putinar)
    @test verify_strict(putinar_path)
    @test length(putinar.constraints) == 2
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
