@testset "Gate C block-native algebraic certificate slice" begin
    using LinearAlgebra: I
    using SHA: sha256

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
                                       slicing=:paper,
                                       kernel_prefix=:BN)
    field = K3.AlgebraicFieldCertificate(:Ksqrt2, :alpha,
                                         [-2//1, 0//1, 1//1],
                                         (1//1, 2//1))
    zero = K3.AlgebraicElement(field, [0//1, 0//1])
    one = K3.AlgebraicElement(field, [1//1, 0//1])
    alpha = K3.AlgebraicElement(field, [0//1, 1//1])
    active_proofs = Dict{Int, K3.BlockNativeActiveBlockProof}()
    for block in incidence.blocks[1:4]
        values = Dict(variable => (isodd(i) ? alpha : one)
                      for (i, variable) in enumerate(block.variable_names))
        equations = K3.AlgebraicEquationObligation[]
        for (i, variable) in enumerate(block.variable_names)
            value = values[variable]
            push!(equations,
                  K3.AlgebraicEquationObligation(Symbol("eq_", block.block_index, "_", i),
                                                 [K3.AlgebraicLinearTerm(variable, one)],
                                                 K3.AlgebraicElement(field, -value.coefficients)))
        end
        push!(equations,
              K3.AlgebraicEquationObligation(Symbol("field_", block.block_index),
                                             [K3.AlgebraicLinearTerm(block.variable_names[1],
                                                                    alpha)],
                                             K3.AlgebraicElement(field, [-2//1, 0//1])))
        gauge = [K3.AlgebraicEquationObligation(Symbol("gauge_", block.block_index),
                                                [K3.AlgebraicLinearTerm(block.variable_names[2],
                                                                       one)],
                                                K3.AlgebraicElement(field, [-1//1, 0//1]))]
        active_proofs[block.block_index] =
            K3.BlockNativeActiveBlockProof(block.block_index, block.block_hash,
                                           field, values, equations, gauge)
    end
    inactive_proofs = Dict{Int, K3.BlockNativeInactivePSDProof}()
    for block in incidence.blocks[5:12]
        margin = K3.SparseSymmetricRationalMatrix(20, [(i, i, 1//1) for i in 1:20])
        factor = [[i == j ? 1//1 : 0//1 for j in 1:20] for i in 1:20]
        psd = K3.ExactLowRankPSDProof(margin, factor, fill(1//1, 20))
        inactive_proofs[block.block_index] =
            K3.BlockNativeInactivePSDProof(block.block_index, block.block_hash,
                                           margin, psd)
    end
    cert = K3.make_block_native_algebraic_certificate(incidence;
                                                      active_block_proofs=active_proofs,
                                                      inactive_psd_proofs=inactive_proofs)
    ok = K3.verify_block_native_algebraic_certificate(cert;
                                                      expected_problem_hash=block_lmi_problem_hash(P))
    @test ok.accepted

    bad_solutions = copy(active_proofs)
    delete!(bad_solutions, 3)
    bad_cert = K3.make_block_native_algebraic_certificate(incidence;
                                                          active_block_proofs=bad_solutions,
                                                          inactive_psd_proofs=inactive_proofs)
    bad = K3.verify_block_native_algebraic_certificate(bad_cert)
    @test !bad.accepted
    @test bad.block_id == :block_3
    @test haskey(bad.details, :rank)
    @test haskey(bad.details, :kernel_dimension)
    @test haskey(bad.details, :slicing_strategy)

    bad_inactive = copy(inactive_proofs)
    delete!(bad_inactive, 5)
    inactive_cert = K3.make_block_native_algebraic_certificate(incidence;
                                                               active_block_proofs=active_proofs,
                                                               inactive_psd_proofs=bad_inactive)
    inactive_report = K3.verify_block_native_algebraic_certificate(inactive_cert)
    @test !inactive_report.accepted
    @test inactive_report.stage == :psd_margin
    @test inactive_report.block_id == :block_5

    tampered_values = deepcopy(active_proofs)
    original = tampered_values[3]
    values = copy(original.values)
    values[first(original.incidence_equations).terms[1].variable] = zero
    tampered_values[3] = K3.BlockNativeActiveBlockProof(3, original.block_hash,
                                                       original.field, values,
                                                       original.incidence_equations,
                                                       original.gauge_equations)
    tampered_cert = K3.make_block_native_algebraic_certificate(incidence;
                                                               active_block_proofs=tampered_values,
                                                               inactive_psd_proofs=inactive_proofs)
    tampered_report = K3.verify_block_native_algebraic_certificate(tampered_cert)
    @test !tampered_report.accepted
    @test tampered_report.stage == :candidate_replay
    @test tampered_report.block_id == :block_3

    json = K3.block_native_algebraic_certificate_json(cert)
    parsed = K3.parse_block_native_algebraic_certificate_json(JSON3.write(json))
    @test parsed.certificate_hash == cert.certificate_hash
end
