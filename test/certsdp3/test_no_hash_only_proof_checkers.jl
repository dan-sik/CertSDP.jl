@testset "DAG checker semantic classification is explicit" begin
    report = CertSDP.DAGCheckerRegistry.dag_checker_semantics_report()
    names = Set(String.(CertSDP.DAGCheckerRegistry.dag_checker_names()))

    @test report["proof_relevant_hash_only_count"] == 0
    @test isempty(report["proof_relevant_hash_only"])
    @test report["checkers"]["check_algebraic_sign"]["mathematical_replay"] == true
    @test report["checkers"]["check_tssos_import_normalization"]["mathematical_replay"] == true
    @test report["checkers"]["check_bundle_manifest"]["mathematical_replay"] == true
    @test "hash" in names
    @test report["checkers"]["hash"]["diagnostic_only"] == true
end

@testset "known theorem-semantic blockers cap audit gates" begin
    root = normpath(joinpath(@__DIR__, "..", ".."))
    audit_source = read(joinpath(root, "scripts", "release_audit_certsdp3.jl"),
                        String)
    @test occursin("primal-dual/Farkas replay uses supplied affine lhs/rhs payloads",
                   audit_source)
    @test occursin("NPA replay does not reconstruct every moment entry",
                   audit_source)
    @test occursin("NCTSSOS replay lacks complete moment-entry reconstruction",
                   audit_source)
    @test occursin("symmetry replay lacks projector idempotence/orthogonality semantics",
                   audit_source)
    @test occursin("bundle problem.json is a placeholder", audit_source)

    out = joinpath(root, "build", "fast_blocker_gate_E.json")
    proc = run(pipeline(`$(Base.julia_cmd()) --project=$(root) --startup-file=no $(joinpath(root, "scripts", "release_audit_certsdp3.jl")) --gate E --json --out $out`;
                        stdout=IOBuffer(), stderr=IOBuffer());
               wait=false)
    wait(proc)
    @test proc.exitcode == 0
    report = JSON3.read(read(out, String))
    gate_report = report[:gates][:E]
    @test gate_report[:status] == "PASS"
    @test gate_report[:score] == 10
    @test !any(check -> occursin("proof-relevant hash-only DAG checker present",
                                 String(check)),
               gate_report[:failed_checks])
end
