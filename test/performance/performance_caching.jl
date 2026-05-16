@testset "Performance and caching" begin
    @testset "scoped verifier cache preserves algebraic acceptance" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        P = LMIProblem([0 1; 1 0],
                       [[1//1 0//1; 0//1 1//2]];
                       vars=[:x],)
        cert = AlgebraicCertificate(P, root, [alpha])

        uncached = verify_timed(cert; cache=false)
        cached = verify_timed(cert; cache=true)

        @test uncached.accepted
        @test cached.accepted
        @test cached.accepted == uncached.accepted
        @test cached.stats.determinant_entries > 0
        @test cached.stats.algebraic_sign_entries > 0
        @test cached.stats.polynomial_remainder_entries > 0
        @test cached.stats.hits > 0
    end

    @testset "exact operation cache stress stays semantically identical" begin
        root = AlgebraicRoot("t^2 - 2", "1", "3/2")
        alpha = AlgebraicElement(root, "t")
        P = LMIProblem([0 1 0; 1 0 0; 0 0 1],
                       [[1//1 0//1 0//1; 0//1 1//2 0//1; 0//1 0//1 0//1]];
                       vars=[:x],)
        cert = AlgebraicCertificate(P, root, [alpha])

        report = cache_stress_report(; iterations=6) do
            return verify(cert; io=nothing)
        end

        @test report.consistent
        @test report.cached.enabled
        @test !report.uncached.enabled
        @test report.cached.counters[:determinant_hit] > 0
        @test report.cached.counters[:algebraic_sign_hit] > 0
        @test report.cached.counters[:polynomial_remainder_hit] > 0
        @test report.cached.hits > report.cached.misses
        @test report.uncached.hits == 0
    end

    @testset "fake certificates remain rejected with cache on and off" begin
        P = LMIProblem([1 0; 0 1], [[0 2; 2 0]])
        bad_matrix = CertSDP.substitute(P, [1])
        bad_proof = RationalPSDProof(:principal_minors,
                                     bad_matrix,
                                     PrincipalMinorProof[PrincipalMinorProof([1], 1 // 1),
                                                         PrincipalMinorProof([2], 1 // 1),
                                                         PrincipalMinorProof([1, 2],
                                                                             -3 // 1)])
        bad_without_hash = RationalCertificate(P, Rational{BigInt}[1 // 1], bad_proof, "")
        bad = RationalCertificate(P, Rational{BigInt}[1 // 1], bad_proof,
                                  rational_certificate_hash(bad_without_hash))

        @test !verify_timed(bad; cache=false).accepted
        @test !verify_timed(bad; cache=true).accepted
    end

    @testset "benchmark rows compare cache on and off" begin
        repo_root = normpath(joinpath(@__DIR__, "..", ".."))
        temp_root = mktempdir()
        cp(joinpath(repo_root, "benchmarks", "validation", "rational_pd_2x2"),
           joinpath(temp_root, "rational_pd_2x2"))
        result = run_benchmarks(temp_root;
                                out=joinpath(temp_root, "report.md"),
                                subset=:all,
                                generated_dir=joinpath(temp_root, "generated"))

        @test result.passed
        @test length(result.rows) == 1
        row = only(result.rows)
        @test row.verify_consistent
        @test row.verify_seconds isa Real
        @test row.verify_uncached_seconds isa Real
        @test row.verify_cache_hits > 0
    end

    @testset "polynomial system hash and backend cache key are stable" begin
        ring = polynomial_ring(:x, :y)
        x, y = CertSDP.variables(ring)
        system = PolynomialSystem(ring, [x^2 + y - 1, x * y - 1 // 2])
        same = PolynomialSystem(ring, [x^2 + y - 1, x * y - 1 // 2])
        changed = PolynomialSystem(ring, [x^2 + y - 1, x * y - 1 // 3])

        @test polynomial_system_hash(system) == polynomial_system_hash(same)
        @test polynomial_system_hash(system) != polynomial_system_hash(changed)

        cache = BackendResultCache(mktempdir())
        backend = MsolveBackend(; binary="/definitely/not/msolve", result_cache=cache)
        result = solve_system(system, backend)
        @test result.status === :unavailable
        @test result.failure isa AlgebraicBackendFailure
    end

    @testset "optional backend cache reuses output by exact system hash" begin
        if Sys.iswindows()
            @test_skip "temporary shell executable is skipped on Windows"
        else
            script = tempname()
            write(script,
                  "#!/bin/sh\n" *
                  "while [ \"\$#\" -gt 0 ]; do\n" *
                  "  case \"\$1\" in\n" *
                  "    --version)\n" *
                  "      echo fake-msolve-1.0\n" *
                  "      exit 0\n" *
                  "      ;;\n" *
                  "    -o)\n" *
                  "      shift\n" *
                  "      out=\"\$1\"\n" *
                  "      ;;\n" *
                  "  esac\n" *
                  "  shift\n" *
                  "done\n" *
                  "echo \"[0, [1, [[[1, 1]]]]]:\" > \"\$out\"\n" *
                  "echo ran >&2\n")
            chmod(script, 0o755)

            ring = polynomial_ring(:x)
            x = CertSDP.variables(ring)[1]
            system = PolynomialSystem(ring, [x - 1])
            cache_dir = mktempdir()

            first = solve_system(system,
                                 MsolveBackend(; binary=script,
                                               parametrization=0,
                                               cache_dir=cache_dir))
            second = solve_system(system,
                                  MsolveBackend(; binary=script,
                                                parametrization=0,
                                                cache_dir=cache_dir))

            @test first.status === :success
            @test second.status === :success
            @test first.output.status === :finite
            @test second.output.status === :finite
            @test get(second.timings, :cache_hit, false) == true
            @test occursin("cache hit", second.backend_log)
            @test second.provenance.options[:system_hash] == polynomial_system_hash(system)
            @test isdir(joinpath(cache_dir, "msolve"))
        end
    end

    @testset "certificate size report is structured" begin
        P = LMIProblem([1 0; 0 1], [[1 0; 0 0], [0 0; 0 1]];
                       vars=[:x, :y],)
        cert = RationalCertificate(P, [1 // 2, 1 // 3])
        report = certificate_size_report(cert)

        @test report.certificate_type == "rational_psd_certificate"
        @test report.bytes > 0
        @test report.problem_dimension == 2
        @test report.variable_count == 2
        @test report.proof_obligations > 0
    end
end
