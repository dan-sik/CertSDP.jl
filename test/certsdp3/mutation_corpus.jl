@testset "Gate R/QA mutation corpus" begin
    fixture = certsdp3_low_rank_fixture(n=5)
    base = certsdp3_cert_json(fixture.cert)

    mutations = Pair{String, Function}[
        "unknown top-level key" => obj -> (obj[:unknown] = "x"; obj),
        "missing hash" => obj -> (delete!(obj, :hash); obj),
        "wrong schema version" => obj -> (obj[:certsdp_certificate_version] = "9.9"; obj),
        "wrong problem hash" => obj -> (obj[:problem_hash] = "sha256:" * repeat("f", 64); obj),
        "floating exact coefficient" => obj -> (obj[:proof][:matrix][:entries][1][:value] = 1.25; obj),
        "malformed rational" => obj -> (obj[:proof][:matrix][:entries][1][:value] = "1/0"; obj),
        "metadata truth claim" => obj -> (obj[:accepted] = true; obj),
        "raw solver log" => obj -> (obj[:proof][:solver_log] = "optimal"; obj),
        "field mismatch" => obj -> (obj[:proof][:low_rank_proof][:field] = "QQsqrt2"; obj),
        "dag output tamper" => obj -> (obj[:proof_dag][:nodes][1][:output_hash] = "sha256:" * repeat("a", 64); obj),
    ]
    for i in 1:90
        push!(mutations,
              "unknown claim key $i" => obj -> begin
                  obj[:claim][Symbol("unknown_claim_$i")] = "reject"
                  obj
              end)
        push!(mutations,
              "unknown proof key $i" => obj -> begin
                  obj[:proof][Symbol("unknown_proof_$i")] = "reject"
                  obj
              end)
        push!(mutations,
              "unknown dag key $i" => obj -> begin
                  obj[:proof_dag][Symbol("unknown_dag_$i")] = "reject"
                  obj
              end)
    end
    for i in 1:30
        push!(mutations,
              "tamper diagonal $i" => obj -> begin
                  obj[:proof][:low_rank_proof][:diagonal][1] = string(-i)
                  obj
              end)
    end

    rejected = 0
    for (label, mutate) in mutations
        candidate = certsdp3_mutable_json(base)
        mutated = mutate(candidate)
        rejected += try
            cert = K3.parse_certificate_json_v3(JSON3.write(mutated))
            report = K3.verify_certificate(cert)
            report.accepted ? 0 : 1
        catch err
            1
        end
    end
    @test length(mutations) >= 300
    @test rejected == length(mutations)
end
