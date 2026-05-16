@testset "PolynomialSystem internal representation" begin
    @testset "small polynomial systems" begin
        ring = polynomial_ring(:x, :y)
        x, y = variables(ring)

        f1 = x^2 + y - 1
        f2 = x * y - 1 // 2
        system = PolynomialSystem(ring,
                                  [f1, f2];
                                  metadata=(source=:toy, rank=1, pivot_cols=[1, 2]),)

        @test system.ring === ring
        @test variable_symbols(system) == [:x, :y]
        @test variables(system) == [x, y]
        @test length(system.equations) == 2
        @test string(system.equations[1]) == "x^2 + y - 1"
        @test string(system.equations[2]) == "x*y - 1/2"
        @test system.metadata[:source] == :toy
        @test system.metadata[:rank] == 1
        @test system.metadata[:pivot_cols] == [1, 2]
    end

    @testset "metadata is preserved and outer dictionary is copied" begin
        ring = polynomial_ring([:x, :lambda])
        x, lambda = variables(ring)
        metadata = Dict("original_lmi_hash" => "sha256:test", :tolerance => "1e-30")
        system = PolynomialSystem(ring, [x + lambda]; metadata)

        metadata["original_lmi_hash"] = "sha256:mutated"

        @test system.metadata[:original_lmi_hash] == "sha256:test"
        @test system.metadata[:tolerance] == "1e-30"
        @test haskey(system.metadata, :original_lmi_hash)
    end

    @testset "variable order is stable in monomials and text export" begin
        ring = polynomial_ring(:z, :x, :y)
        z, x, y = variables(ring)
        f = x * z^2 + y * x - z
        system = PolynomialSystem(ring, [f];
                                  metadata=Dict(:builder => :polynomial_system,
                                                :kind => "order-test"))
        text = polynomial_system_text(system)

        @test variable_symbols(ring) == [:z, :x, :y]
        @test string(f) == "z^2*x + x*y - z"
        @test occursin("ring: QQ[z, x, y]", text)
        @test occursin("  1: z", text)
        @test occursin("  2: x", text)
        @test occursin("  3: y", text)
        @test occursin("  f1 = z^2*x + x*y - z", text)
        @test occursin("  kind = \"order-test\"", text)
        @test occursin("  builder = :polynomial_system", text)
    end

    @testset "construction rejects inconsistent data" begin
        ring = polynomial_ring(:x, :y)
        other = polynomial_ring(:x, :z)
        x, y = variables(ring)
        ox = variables(other)[1]

        @test_throws ArgumentError polynomial_ring(:x, :x)
        @test_throws ArgumentError PolynomialRingAdapter(Symbol[])
        @test_throws ArgumentError monomial(ring, 1, (1,))
        @test_throws ArgumentError monomial(ring, 1, (1, -1))
        @test_throws ArgumentError x + ox
        @test_throws ArgumentError PolynomialSystem(ring, [ox])
        @test_throws ArgumentError PolynomialSystem(ring, [x + y];
                                                    metadata=Dict(1 => "bad"))
    end

    @testset "readable text can be written" begin
        ring = polynomial_ring(:x)
        x = variables(ring)[1]
        system = PolynomialSystem(ring, [x^2 - 2])
        path = tempname()

        @test write_polynomial_system_text(path, system) == path
        @test read(path, String) == polynomial_system_text(system)
    end
end
