@testset "Gate D PSD planner policy" begin
    using LinearAlgebra: I

    small = Matrix{Rational{BigInt}}(I, 4, 4)
    small_plan = choose_psd_proof(small; method=:auto)
    @test small_plan.method === Symbol(RATIONAL_PSD_METHOD)

    large = Matrix{Rational{BigInt}}(I, 13, 13)
    large_plan = choose_psd_proof(large; method=:auto)
    @test large_plan.method !== Symbol(RATIONAL_PSD_METHOD)
    @test large_plan.method === Symbol(PIVOTED_LDL_PSD_METHOD)

    @test_throws ArgumentError choose_psd_proof(large; method=Symbol(RATIONAL_PSD_METHOD),
                                                max_size=8)
end
