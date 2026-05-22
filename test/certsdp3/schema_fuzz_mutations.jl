@testset "Gate F schema fuzz mutations" begin
    fixture = certsdp3_low_rank_fixture(n=5)
    base = certsdp3_cert_json(fixture.cert)
    mutations = Function[]
    push!(mutations, obj -> (obj[:unknown_key] = "reject"; obj))
    push!(mutations, obj -> (delete!(obj, :claim); obj))
    push!(mutations, obj -> (obj[:certsdp_certificate_version] = "0"; obj))
    push!(mutations, obj -> (obj[:hash] = "sha256:" * repeat("0", 64); obj))
    push!(mutations, obj -> (obj[:proof][:matrix][:entries][1][:value] = 0.25; obj))
    push!(mutations, obj -> (obj[:proof][:matrix][:entries][1][:value] = "bad"; obj))
    push!(mutations, obj -> (obj[:proof][:matrix][:n] = -1; obj))
    push!(mutations, obj -> (obj[:accepted] = true; obj))
    push!(mutations, obj -> (obj[:metadata][:verified] = true; obj))
    push!(mutations, obj -> (obj[:proof][:raw_solver_stdout] = "optimal"; obj))
    push!(mutations, obj -> (obj[:problem_hash] = "sha256:" * repeat("1", 64); obj))
    push!(mutations, obj -> (obj[:proof][:low_rank_proof][:field] = "QQsqrt2"; obj))
    push!(mutations, obj -> (obj[:proof][:low_rank_proof][:diagonal][1] = "-1"; obj))
    push!(mutations, obj -> (obj[:proof_dag][:nodes][1][:checker] = "trust_me"; obj))
    push!(mutations, obj -> (obj[:proof_dag][:nodes][1][:output_hash] = "sha256:" * repeat("2", 64); obj))
    for i in 1:120
        push!(mutations, obj -> begin
            obj[:claim][Symbol("unknown_", i)] = "reject"
            obj
        end)
    end

    rejected = 0
    for mutate in mutations
        candidate = certsdp3_mutable_json(base)
        mutated = mutate(candidate)
        try
            cert = K3.parse_certificate_json_v3(JSON3.write(mutated))
            report = K3.verify_certificate(cert)
            rejected += report.accepted ? 0 : 1
        catch err
            rejected += 1
        end
    end
    @test rejected >= 100
end
