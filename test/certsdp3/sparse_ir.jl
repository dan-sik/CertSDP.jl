@testset "Gate B sparse exact IR" begin
    A = K3.SparseSymmetricRationalMatrix(5, [(2, 1, 2//4),
                                             (1, 1, 0//1),
                                             (5, 5, 3//1)])
    B = K3.SparseSymmetricRationalMatrix(5, [(1, 2, 1//2),
                                             (5, 5, 3//1)])
    @test A.hash == B.hash
    @test A.entries == B.entries

    @test_throws ArgumentError K3.SparseSymmetricRationalMatrix(5,
        [(1, 2, 1//2), (2, 1, 3//4)])

    P = K3.SparseAffineLMI([:x],
                           K3.SparseSymmetricRationalMatrix(3, [(1, 1, 1//1)]),
                           [K3.SparseSymmetricRationalMatrix(3, [(2, 2, 2//1)])])
    S = K3.substitute(P, [3//1])
    @test S[1, 1] == 1//1
    @test S[2, 2] == 6//1

    C = K3.ChordalPSDStructure(8, [collect(1:4), collect(3:8)],
                               [collect(3:4)])
    @test C.graph_hash == K3.chordal_structure_hash(C)
end
