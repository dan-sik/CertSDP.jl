#!/usr/bin/env julia

using JSON3

const ROOT = normpath(joinpath(@__DIR__, ".."))

function mutable_json(value)
    if value isa JSON3.Object || value isa AbstractDict
        result = Dict{Symbol, Any}()
        for key in keys(value)
            result[Symbol(key)] = mutable_json(value[key])
        end
        return result
    elseif value isa AbstractVector
        return Any[mutable_json(entry) for entry in value]
    end
    return value
end

function write_json(path, value)
    mkpath(dirname(path))
    open(path, "w") do io
        JSON3.pretty(io, value)
        println(io)
    end
    return path
end

function mutate_schema_cases(source, out_dir)
    base = mutable_json(JSON3.read(read(source, String)))
    mutations = Pair{String, Function}[
        "unknown_top_level" => obj -> (obj[:unexpected] = "x"; obj),
        "accepted_true" => obj -> (obj[:accepted] = true; obj),
        "wrong_version" => obj -> (obj[:certsdp_certificate_version] = "9.9"; obj),
        "wrong_hash" => obj -> (haskey(obj, :hash) && (obj[:hash] = "sha256:" * repeat("1", 64)); obj),
        "missing_dag" => obj -> (delete!(obj, :proof_dag); obj),
        "dag_root_hash" => obj -> (obj[:proof_dag][:root_hash] = "sha256:" * repeat("2", 64); obj),
        "solver_log" => obj -> (obj[:solver_log] = "optimal"; obj),
        "certificate_valid" => obj -> (obj[:certificate_valid] = true; obj),
        "metadata_verified" => obj -> (obj[:metadata][:verified] = true; obj),
        "problem_hash" => obj -> (haskey(obj, :problem_hash) && (obj[:problem_hash] = "sha256:" * repeat("3", 64)); obj),
        "float_exact_field" => obj -> (obj[:proof][:matrix][:entries][1][:value] = 1.25; obj),
        "malformed_rational" => obj -> (obj[:proof][:matrix][:entries][1][:value] = "1//2"; obj),
        "negative_dimension" => obj -> (obj[:proof][:matrix][:n] = -1; obj),
        "unknown_nested" => obj -> (obj[:proof][:matrix][:entries][1][:unknown] = "x"; obj),
        "missing_certificate_id" => obj -> (delete!(obj, :certificate_id); obj),
        "missing_problem_hash" => obj -> (delete!(obj, :problem_hash); obj),
        "missing_proof" => obj -> (delete!(obj, :proof); obj),
        "wrong_certificate_type" => obj -> (obj[:certificate_type] = "fake"; obj),
        "raw_solver_stdout" => obj -> (obj[:raw_solver_stdout] = "status optimal"; obj),
        "backend_output" => obj -> (obj[:backend_output] = "accepted"; obj),
        "proof_method_mismatch" => obj -> (obj[:proof][:unexpected_method] = "eigen"; obj),
        "duplicate_dag_node" => obj -> (push!(obj[:proof_dag][:nodes], deepcopy(obj[:proof_dag][:nodes][1])); obj),
        "bad_dag_node_status" => obj -> (obj[:proof_dag][:nodes][1][:status] = "claimed"; obj),
        "bad_dag_node_type" => obj -> (obj[:proof_dag][:nodes][1][:kind] = "unknown"; obj),
        "bad_checker" => obj -> (obj[:proof_dag][:nodes][1][:checker] = "trust_me"; obj),
        "bad_output_hash" => obj -> (obj[:proof_dag][:nodes][1][:output_hash] = "sha256:" * repeat("4", 64); obj),
        "float_metadata_nested" => obj -> (obj[:metadata][:residual] = 1.0; obj),
        "raw_residual_as_proof" => obj -> (obj[:proof][:raw_residual] = "1e-12"; obj),
        "wrong_matrix_hash" => obj -> (obj[:proof][:matrix][:hash] = "sha256:" * repeat("5", 64); obj),
        "wrong_identity_hash" => obj -> (obj[:proof][:low_rank_proof][:identity_proof_hash] = "sha256:" * repeat("6", 64); obj),
    ]
    for (name, mutator) in mutations
        obj = deepcopy(base)
        write_json(joinpath(out_dir, string(name, ".json")), mutator(obj))
    end
    return length(mutations)
end

function main(args=ARGS)
    isempty(args) || length(args) == 2 ||
        error("usage: julia scripts/mutate_certsdp3_fixture.jl [source out_dir]")
    source = isempty(args) ?
             joinpath(ROOT, "test", "fixtures", "certsdp3",
                      "psd_factor_rational_150", "certificate.json") :
             args[1]
    out_dir = isempty(args) ?
              joinpath(ROOT, "test", "fixtures", "certsdp3",
                       "tampered", "schema") :
              args[2]
    count = mutate_schema_cases(source, out_dir)
    println("CERTSDP3_MUTATIONS")
    println("schema_cases: ", count)
    println("out_dir: ", out_dir)
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
