@testset "Gate J NC rewrite witness" begin
    relations = K3.AbstractQuantumRelation[
        K3.ProjectionRelation(:proj_A, :A),
        K3.CommutationRelation(:comm_AB, [:A], [:B]),
    ]
    witness = K3.NCRewriteWitness([:A, :A],
                                  [K3.NCRewriteStep(:proj_A,
                                                    :projection_idempotent,
                                                    [:A, :A],
                                                    [:A])],
                                  [:A],
                                  [:proj_A],
                                  Vector{Symbol}[],
                                  Vector{Symbol}[])
    @test K3.verify_nc_rewrite_witness(witness, relations).accepted

    bad = K3.NCRewriteWitness([:A, :A],
                              [K3.NCRewriteStep(:unknown,
                                                :projection_idempotent,
                                                [:A, :A],
                                                [:A])],
                              [:A],
                              [:unknown],
                              Vector{Symbol}[],
                              Vector{Symbol}[])
    report = K3.verify_nc_rewrite_witness(bad, relations)
    @test !report.accepted
    @test report.stage == :rewrite_witness
end
