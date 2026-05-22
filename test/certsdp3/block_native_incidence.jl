@testset "Gate C block-native incidence" begin
    using LinearAlgebra: I

    blocks = LMIProblem[]
    vars = [Symbol("x", i) for i in 1:20]
    for block_index in 1:12
        n = 20
        A0 = Matrix{Rational{BigInt}}(I, n, n)
        A = [zeros(Rational{BigInt}, n, n) for _ in vars]
        push!(blocks, LMIProblem(A0, A; vars))
    end
    P = BlockLMIProblem(blocks; objective=zeros(Rational{BigInt}, length(vars)))
    profiles = RankProfile[]
    for i in 1:12
        n = matrix_size(P.blocks[i])
        rank = i <= 4 ? n - 2 : n
        pivots = collect(1:rank)
        push!(profiles,
              RankProfile(rank, pivots, pivots, collect(1:n), BigFloat(0),
                          BigFloat[], BigFloat(0), :fixture))
    end
    incidence = build_incidence_system(P, nothing;
                                       rank_profiles=profiles,
                                       active_blocks=1:4,
                                       inactive_blocks=5:12,
                                       slicing=:user,
                                       kernel_prefix=:BN)

    @test incidence.problem_hash == block_lmi_problem_hash(P)
    @test length(incidence.blocks) == 12
    active_names = Symbol[]
    for block in incidence.blocks
        append!(active_names, block.variable_names)
        if block.active
            @test block.kernel_dimension == 2
            @test length(block.gauge_rows) == 2
            @test block.slicing_strategy == :user
        else
            @test isempty(block.variable_names)
            @test block.slicing_strategy == :inactive_psd_margin
        end
    end
    @test length(unique(active_names)) == length(active_names)
    @test !occursin("block_diagonal", JSON3.write(K3.block_native_incidence_system_json(incidence)))
end
