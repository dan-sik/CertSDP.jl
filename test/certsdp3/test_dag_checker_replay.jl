@testset "DAG checker registry executes" begin
    CertSDP.DAGCheckerRegistry.reset_dag_checker_calls!()
    path = joinpath(@__DIR__, "..", "fixtures", "certsdp3",
                    "psd_factor_rational_150", "certificate.json")
    report = CertSDP.Kernel.replay_file(path; strict=true, io=nothing)
    @test report.accepted
    @test :canonical_sparse_matrix_hash in CertSDP.DAGCheckerRegistry.dag_checker_calls()
    @test :verify_low_rank_psd in CertSDP.DAGCheckerRegistry.dag_checker_calls()
end

