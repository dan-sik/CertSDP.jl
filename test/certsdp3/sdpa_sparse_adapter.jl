@testset "Gate N sparse SDPA adapter" begin
    text = """
    2 = mDIM
    2 = nBLOCK
    2 -2 = bLOCKsTRUCT
    0, 0
    0 1 1 1 -1
    1 1 1 2 3/2
    2 2 1 1 5
    """
    problem = CertSDP.parse_sdpa_sparse(text)
    @test problem isa K3.SparseAffineLMI
    @test problem.A0.n == 4
    @test K3.entries_dict(problem.A[1])[(1, 2)] == 3//2
    @test K3.entries_dict(problem.A[2])[(3, 3)] == 5//1

    shuffled = """
    2 = mDIM
    2 = nBLOCK
    2 -2 = bLOCKsTRUCT
    0, 0
    2 2 1 1 5
    1 1 2 1 3/2
    0 1 1 1 -1
    """
    @test CertSDP.parse_sdpa_sparse(shuffled).hash == problem.hash

    bad = """
    1 = mDIM
    1 = nBLOCK
    2 = bLOCKsTRUCT
    0
    0 1 1 1 1
    0 1 1 1 2
    """
    @test_throws ArgumentError CertSDP.parse_sdpa_sparse(bad)
end
