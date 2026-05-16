@testset "msolve backend adapter" begin
    @testset "PolynomialSystem serializes to msolve input" begin
        ring = polynomial_ring(:x, :y)
        x, y = variables(ring)
        system = PolynomialSystem(ring,
                                  [x^2 + y - 1, x * y - 1 // 2, zero_polynomial(ring)])

        @test msolve_input(system) == "x,y\n0\nx^2+y-1,\nx*y-1/2\n"

        path = tempname()
        @test write_msolve_input(path, system) == path
        @test read(path, String) == msolve_input(system)
    end

    @testset "msolve writer rejects unsupported input" begin
        ring = polynomial_ring([Symbol("bad-name")])
        bad = variables(ring)[1]
        @test_throws ArgumentError msolve_input(PolynomialSystem(ring, [bad]))

        empty_ring = polynomial_ring(:x)
        @test_throws ArgumentError msolve_input(PolynomialSystem(empty_ring,
                                                                 [zero_polynomial(empty_ring)]))
        @test_throws ArgumentError msolve_input(PolynomialSystem(empty_ring,
                                                                 [variables(empty_ring)[1]]);
                                                characteristic=-1)
    end

    @testset "basic msolve output parser" begin
        real_output = "[0, [1,\n[[[1, 1]]]\n]]:"
        parsed_real = parse_msolve_output(real_output; variables=[:x])

        @test parsed_real.status === :finite
        @test parsed_real.rur === nothing
        @test parsed_real.variable_order == [:x]
        @test length(parsed_real.real_solution_boxes) == 1
        @test parsed_real.real_solution_boxes[1][1] == MsolveInterval(1, 1)

        rur_output = """
        [0, [0,
        1,
        2,
        ['x'],
        [1],
        [1,
        [[2, [-2, 0, 1]],
        [1, [0, 2]],
        [
        ]]]]]:
        """
        parsed_rur = parse_msolve_output(rur_output)

        @test parsed_rur.status === :finite
        @test parsed_rur.characteristic == 0
        @test parsed_rur.degree == 2
        @test parsed_rur.variable_order == [:x]
        @test parsed_rur.rur isa RURSolution
        @test parsed_rur.rur.minimal_polynomial == parse_polynomial("t^2 - 2")
        @test parsed_rur.rur.denominator == parse_polynomial("2*t")
        @test isempty(parsed_rur.rur.numerators)
        @test isempty(parsed_rur.real_solution_boxes)

        @test parse_msolve_output("[-1]:").status === :empty
        @test parse_msolve_output("[1, 1, -1, []]:").status === :positive_dimensional
    end

    @testset "missing msolve binary remains optional" begin
        ring = polynomial_ring(:x)
        x = variables(ring)[1]
        system = PolynomialSystem(ring, [x - 1])

        @test find_msolve(; binary="/definitely/not/msolve") === nothing
        @test has_msolve(; binary="/definitely/not/msolve") == false
        result = solve_system(system, MsolveBackend(; binary="/definitely/not/msolve"))
        @test result.status === :unavailable
        @test result.failure isa AlgebraicBackendFailure
        @test result.failure.reason === :unavailable
        @test algebraic_backend_failure_json(result.failure).failure_type ==
              "AlgebraicBackendFailure"
        @test_throws MsolveNotFoundError solve_with_msolve(system;
                                                           binary="/definitely/not/msolve")
    end

    @testset "backend failure parser captures process stderr" begin
        ring = polynomial_ring(:x)
        x = variables(ring)[1]
        system = PolynomialSystem(ring, [x - 1])

        if Sys.iswindows()
            @test_skip "temporary executable shell script is skipped on Windows"
        else
            script = tempname()
            write(script, "#!/bin/sh\necho backend exploded >&2\nexit 7\n")
            chmod(script, 0o755)

            result = solve_system(system, MsolveBackend(; binary=script, timeout_seconds=5))

            @test result.failure isa AlgebraicBackendFailure
            @test result.failure.reason === :process_failed
            @test occursin("backend exploded", result.stderr)
            @test result.provenance.exit_code == 7
        end
    end

    @testset "backend timeout is structured failure" begin
        ring = polynomial_ring(:x)
        x = variables(ring)[1]
        system = PolynomialSystem(ring, [x - 1])

        if Sys.iswindows()
            @test_skip "temporary executable shell script is skipped on Windows"
        else
            script = tempname()
            write(script, "#!/bin/sh\nsleep 5\n")
            chmod(script, 0o755)

            result = solve_system(system,
                                  MsolveBackend(; binary=script, timeout_seconds=0.2))

            @test result.failure isa AlgebraicBackendFailure
            @test result.failure.reason === :timeout
            @test result.provenance.timed_out
        end
    end

    @testset "Sage/msolve adapter parses candidate output" begin
        ring = polynomial_ring(:x)
        x = variables(ring)[1]
        system = PolynomialSystem(ring, [x - 1])

        if Sys.iswindows()
            @test_skip "temporary executable shell script is skipped on Windows"
        else
            sage = tempname()
            write(sage,
                  "#!/bin/sh\nprintf '[0, [1, [[[1, 1]]]]]:\\n' > \"\$3\"\necho sage-msolve shim\n")
            chmod(sage, 0o755)

            result = solve_system(system,
                                  SageMsolveBackend(; binary=sage,
                                                    msolve_binary="unused-msolve",
                                                    timeout_seconds=5))

            @test result.status === :success
            @test result.output isa MsolveOutput
            @test result.output.status === :finite
            @test result.provenance.backend === :sage_msolve
            @test occursin("sage-msolve shim", result.stdout)
        end
    end

    @testset "small polynomial system integration" begin
        if !has_msolve()
            @test_skip "msolve binary is not installed"
        else
            ring = polynomial_ring(:x, :y)
            x, y = variables(ring)
            system = PolynomialSystem(ring, [x^2 - 2, y - 1]; metadata=(kind=:msolve_toy,))

            output = solve_with_msolve(system; precision=128, parametrization=1, threads=1)

            @test output.status === :finite
            @test output.rur isa RURSolution
            @test output.degree == 2
            @test Set(output.variable_order) == Set([:x, :y])
            @test length(output.real_solution_boxes) == 2
            @test all(length(box) == 2 for box in output.real_solution_boxes)

            y_index = findfirst(==(:y), output.variable_order)
            @test y_index !== nothing
            @test all(box[y_index] == MsolveInterval(1, 1)
                      for box in output.real_solution_boxes)
        end
    end

    @testset "algebraic backend interface saves msolve artifacts" begin
        if !has_msolve()
            @test_skip "msolve binary is not installed"
        else
            ring = polynomial_ring(:x)
            x = variables(ring)[1]
            system = PolynomialSystem(ring, [x^2 - 2];
                                      metadata=(kind=:msolve_artifact_toy,))
            artifact_dir = mktempdir()

            result = solve_system(system,
                                  MsolveBackend(; precision=128,
                                                parametrization=1,
                                                threads=1,
                                                artifact_dir=artifact_dir))

            @test result.status === :success
            @test result.output isa MsolveOutput
            @test result.output.status === :finite
            @test result.provenance.backend === :msolve
            @test result.provenance.version !== nothing
            @test isfile(result.artifacts[:input])
            @test isfile(result.artifacts[:output])
            @test isfile(result.artifacts[:stdout])
            @test isfile(result.artifacts[:stderr])
            @test isfile(result.artifacts[:provenance])
            @test isfile(result.artifacts[:backend_log])
            @test occursin("command:", read(result.artifacts[:backend_log], String))
        end
    end
end
