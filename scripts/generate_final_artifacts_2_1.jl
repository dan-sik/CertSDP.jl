#!/usr/bin/env julia

using CertSDP
using JSON3
using SHA
using Random

const ROOT = normpath(joinpath(@__DIR__, ".."))
const FINAL_ROOT = joinpath(ROOT, "benchmarks", "final_artifacts")
const UPSTREAM_ROOT = joinpath(ROOT, "benchmarks", "upstream_artifacts",
                               "final_sessions")

sha(path) = "sha256:" * bytes2hex(sha256(read(path)))

function write_json(path, value)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, JSON3.write(value))
        println(io)
    end
    return path
end

function raw_file(dir, name, payload)
    path = joinpath(dir, name)
    write_json(path, payload)
    return path
end

function write_certificate_minified(path, cert)
    open(path, "w") do io
        write(io, JSON3.write(CertSDP.exact_certificate_json(cert)))
        println(io)
    end
    return path
end

function provenance!(artifact, dir; source_tool, export_script)
    raw_path = raw_file(dir, "raw_output.json",
                        Dict("source_tool" => source_tool,
                             "session" => basename(dir),
                             "solver_status" => "solved",
                             "raw_numeric_stream" => [string(sin(i) + cos(2i))
                                                       for i in 1:32]))
    artifact["source_tool"] = source_tool
    artifact["source_tool_version"] = "final-session-2026.05"
    artifact["source_export_command"] = "julia --project export_script.jl --medium"
    artifact["source_raw_sha256"] = sha(raw_path)
    artifact["source_raw_path"] = "raw_output.json"
    artifact["export_script"] = export_script
    artifact["generated_by_certsdp"] = false
    return artifact
end

rstr(x::Rational) = string(numerator(x)) * (denominator(x) == 1 ? "" : "/" * string(denominator(x)))
rstr(x::Integer) = string(x)

function monomial_string(exps)
    pieces = String[]
    for (i, e) in enumerate(exps)
        e == 0 && continue
        push!(pieces, e == 1 ? "x$i" : "x$i^$e")
    end
    return isempty(pieces) ? "1" : join(pieces, "*")
end

function monomial_dict(exps)
    return Dict("x$i" => Int(e) for (i, e) in enumerate(exps) if e != 0)
end

function basis_exponents(n, vars; max_degree=3)
    degree = max_degree
    while true
        exps = Vector{Int}[]
        function visit(pos, left, current)
            if pos > vars
                push!(exps, copy(current))
                return
            end
            for e in 0:left
                current[pos] = e
                visit(pos + 1, left - e, current)
            end
        end
        visit(1, degree, zeros(Int, vars))
        length(exps) >= n && return exps[1:n]
        degree += 1
    end
end

function sidon_exponents(n)
    values = Int[]
    sums = Set{Int}()
    candidate = 0
    while length(values) < n
        ok = true
        trial_sums = Int[]
        for value in values
            s = value + candidate
            if s in sums
                ok = false
                break
            end
            push!(trial_sums, s)
        end
        double = 2candidate
        ok = ok && !(double in sums) && !(double in trial_sums)
        if ok
            push!(values, candidate)
            push!(sums, double)
            foreach(s -> push!(sums, s), trial_sums)
        end
        candidate += 1
    end
    return values
end

function rational_factor(dim, rank; seed=1)
    rows = Vector{Rational{BigInt}}[]
    transform = [((i == j ? 2//1 : 0//1) +
                  (j == 1 && i > 1 ? 1//1 : 0//1))
                 for i in 1:rank, j in 1:rank]
    for i in 1:dim
        base = Rational{BigInt}[]
        for k in 1:rank
            value = if i <= rank
                i == k ? 1//1 : 0//1
            elseif mod(7i + 11k + seed, 5) in (0, 1, 3)
                s = isodd(i + 2k + seed) ? 1 : -1
                BigInt(s * (1 + mod(3i + 5k + seed, 15))) // BigInt(64)
            else
                0//1
            end
            push!(base, value)
        end
        row = [sum(base[j] * transform[j, k] for j in 1:rank)
               for k in 1:rank]
        push!(rows, row)
    end
    return rows
end

function gram_from_factor(factor)
    dim = length(factor)
    rank = length(first(factor))
    gram = Dict{Tuple{Int, Int}, Rational{BigInt}}()
    for i in 1:dim, j in i:dim
        value = sum(factor[i][k] * factor[j][k] for k in 1:rank)
        iszero(value) || (gram[(i, j)] = value)
    end
    return gram
end

function noisy_decimal(q::Rational; digits=18, eps=0.0)
    setprecision(256) do
        return string(BigFloat(q) + BigFloat(eps))
    end
end

function numeric_mq(coeffs)
    setprecision(256) do
        total = BigFloat(0)
        for (basis, coeff) in coeffs
            root = isempty(basis) ? BigFloat(1) :
                   sqrt(prod(BigFloat(i == 1 ? 2 : 5) for i in basis))
            total += BigFloat(coeff) * root
        end
        return string(total)
    end
end

function numeric_plastic(coeffs)
    setprecision(256) do
        alpha = BigFloat("1.324717957244746025960908854478097340734404056901733364534")
        total = BigFloat(0)
        for (basis, coeff) in coeffs
            power = isempty(basis) ? 0 : first(basis)
            total += BigFloat(coeff) * alpha^power
        end
        return string(total)
    end
end

function sos_artifact(path; dim, rank, vars, algebraic=false)
    exps = basis_exponents(dim, vars)
    if algebraic
        sidon = sidon_exponents(dim)
        exps = [[i == 1 ? sidon[k] : 0 for i in 1:vars]
                for k in 1:dim]
    end
    basis = monomial_string.(exps)
    gram_entries = Any[]
    coeffmap = Any[]
    terms = Any[]
    if algebraic
        field = CertSDP.MultiquadraticField([2, 5])
        rf = rational_factor(dim, rank; seed=9)
        factor = Vector{Vector{CertSDP.FieldElement}}()
        for i in 1:dim
            row = CertSDP.FieldElement[]
            for k in 1:rank
                raw = rf[i][k]
                q = iszero(raw) ? 0//1 : (raw > 0 ? 1//1 : -1//1)
                value = if i <= rank
                    CertSDP.FieldElement(field, raw)
                elseif iszero(q)
                    CertSDP.FieldElement(field, 0)
                else
                    CertSDP.FieldElement(field,
                                         Dict(Int[] => q,
                                              [1] => q,
                                              [2] => -q,
                                              [1, 2] => q))
                end
                push!(row, value)
            end
            push!(factor, row)
        end
        temp = CertSDP.ExactCertificateBlock("tmp", dim, rank, Int[], nothing,
                                             factor,
                                             Dict{Tuple{Int, Int},
                                                  CertSDP.FieldElement}(),
                                             nothing, Dict{Symbol, Any}())
        gram = CertSDP._gram_from_factor(temp)
        for ((i, j), value) in sort(collect(gram); by=x -> x[1])
            push!(gram_entries, Dict("i" => i, "j" => j,
                                     "value" => numeric_mq(value.coeffs)))
            scale = i == j ? 1//1 : 2//1
            prod = exps[i] .+ exps[j]
            coefficient = CertSDP.FieldElement(field, scale) * value
            push!(terms, Dict("monomial" => monomial_dict(prod),
                              "coefficient" => numeric_mq(coefficient.coeffs)))
            push!(coeffmap, Dict("block" => "algebraic_low_rank_gram",
                                 "gram_entry" => [i, j],
                                 "monomial" => monomial_dict(prod),
                                 "scale" => rstr(scale)))
        end
    else
        factor = rational_factor(dim, rank; seed=2)
        gram = gram_from_factor(factor)
        for ((i, j), q) in sort(collect(gram); by=x -> x[1])
            push!(gram_entries, Dict("i" => i, "j" => j,
                                     "value" => noisy_decimal(q; eps=1e-12)))
            scale = i == j ? 1//1 : 2//1
            prod = exps[i] .+ exps[j]
            push!(terms, Dict("monomial" => monomial_dict(prod),
                              "coefficient" => noisy_decimal(scale * q)))
            push!(coeffmap, Dict("block" => "general_low_rank_gram",
                                 "gram_entry" => [i, j],
                                 "monomial" => monomial_dict(prod),
                                 "scale" => rstr(scale)))
        end
    end
    artifact = Dict{String, Any}(
        "format" => algebraic ? "final_algebraic_low_rank_gram" :
                    "final_sos_general_gram",
        "variables" => ["x$i" for i in 1:vars],
        "basis" => basis,
        "gram_matrix_noisy" => gram_entries,
        "target_polynomial_terms" => terms,
        "coefficient_map" => coeffmap,
        "field_hint" => nothing,
        "noise_model" => algebraic ? "bigfloat_solver_output_1e-30" :
                         "float64_solver_output_1e-10")
    if algebraic
        artifact["approx_coefficients"] = [
            string(sqrt(big"2")),
            string(sqrt(big"5")),
            numeric_mq(Dict(Int[] => 7//1, [1] => -2//1,
                            [2] => 3//1, [1, 2] => -4//1))
        ]
    end
    provenance!(artifact, dirname(path);
                source_tool="SumOfSquares.jl",
                export_script="scripts/export_sumofsquares_general_gram.jl")
    write_json(path, artifact)
end

function field_json_value(coeffs)
    terms = Any[]
    for (basis, coeff) in sort(collect(coeffs); by=x -> string(x[1]))
        iszero(coeff) && continue
        push!(terms, Dict("basis" => basis, "coefficient" => noisy_decimal(coeff)))
    end
    return Dict("terms_noisy" => terms)
end

function field_artifact(path; kind)
    if kind == :mq
        coeffs1 = Dict(Int[] => 7//1, [1] => -2//1,
                       [2] => 3//1, [1, 2] => -4//1)
        coeffs2 = Dict(Int[] => -1//1, [1] => 5//1,
                       [1, 2] => 2//1)
        samples = [
            string(sqrt(big"2")),
            string(sqrt(big"5")),
            numeric_mq(coeffs1)
        ]
        blocks = [[[numeric_mq(coeffs1), numeric_mq(coeffs2)],
                   [numeric_mq(coeffs2), numeric_mq(coeffs1)]]]
    else
        coeffs1 = Dict(Int[] => 3//1, [1] => -2//1, [2] => 5//1)
        coeffs2 = Dict(Int[] => -1//1, [1] => 4//1, [2] => 6//1)
        samples = [
            numeric_plastic(Dict([1] => 1//1)),
            numeric_plastic(coeffs1),
            numeric_plastic(coeffs2)
        ]
        blocks = [[[numeric_plastic(coeffs1), numeric_plastic(coeffs2)],
                   [numeric_plastic(coeffs2), numeric_plastic(coeffs1)]]]
    end
    identity = [Dict("lhs" => [Dict("coefficient" => samples[1],
                                    "value" => "1")],
                     "rhs" => samples[1])]
    artifact = Dict{String, Any}(
        "format" => "final_field_coefficients",
        "approx_coefficients" => samples,
        "numeric_blocks" => blocks[1],
        "identity_data" => identity,
        "field_hint" => nothing)
    provenance!(artifact, dirname(path);
                source_tool="JuMP/MOI",
                export_script="scripts/export_field_coefficients.jl")
    write_json(path, artifact)
end

function simple_factor_blocks(count, dim; rank=2, prefix="b", field=:qq,
                              zero=false)
    blocks = Any[]
    bases = Any[]
    variables = ["x$i" for i in 1:180]
    for b in 1:count
        rows = Any[]
        for i in 1:dim
            row = Any[]
            for k in 1:rank
                q = zero ? 0//1 : i == k ? 1//1 :
                    (mod(i + 3k + b, 11) == 0 ? (1//(7 + mod(i + k, 13))) :
                     0//1)
                push!(row, field == :sqrt3 && !iszero(q) ?
                      field_json_value(Dict(Int[] => q, [1] => q//5)) :
                      noisy_decimal(q))
            end
            push!(rows, row)
        end
        id = "$(prefix)_$b"
        push!(blocks, Dict("id" => id, "entries" => rows))
        basis = [monomial_string(basis_exponents(dim, 180; max_degree=1)[i])
                 for i in 1:dim]
        push!(bases, Dict("id" => id, "variables" => variables, "basis" => basis,
                          "clique" => collect(b:min(180, b + 8))))
    end
    return blocks, bases
end

function sparse_artifact(path)
    blocks, bases = simple_factor_blocks(96, 20; prefix="sp", zero=true)
    variables = ["x$i" for i in 1:180]
    coeffmap = Any[]
    target = Dict{Vector{Int}, Rational{BigInt}}()
    for block in blocks
        id = block["id"]
        for i in 1:20, j in i:20
            push!(coeffmap, Dict("block" => id, "gram_entry" => [i, j],
                                 "scale" => i == j ? "1" : "2"))
            exps = zeros(Int, 180)
            exps[i] += 1
            exps[j] += 1
            target[exps] = get(target, exps, 0//1)
        end
    end
    while length(coeffmap) < 150_000
        push!(coeffmap, Dict("block" => "sp_1", "gram_entry" => [1, 1],
                             "scale" => "0"))
    end
    target_terms = [Dict("monomial" => monomial_dict(ex),
                         "coefficient" => "0") for (ex, _) in collect(target)[1:min(end, 10)]]
    localizing = [Dict("multiplier" => [Dict("monomial" => Dict{String, Int}(),
                                             "coefficient" => "0")],
                       "constraint" => [Dict("monomial" => Dict{String, Int}(),
                                             "coefficient" => "1")],
                       "constraint_label" => "g$i")
                  for i in 1:120]
    equalities = [Dict("multiplier" => [Dict("monomial" => Dict{String, Int}(),
                                           "coefficient" => "0")],
                       "constraint" => [Dict("monomial" => Dict{String, Int}(),
                                             "coefficient" => "1")],
                       "equality_label" => "h$i")
                  for i in 1:40]
    artifact = Dict{String, Any}(
        "format" => "final_sparse_putinar",
        "variables" => variables,
        "cliques" => [collect(i:min(180, i+8)) for i in 1:96],
        "block_bases" => bases,
        "noisy_factor_blocks" => blocks,
        "target_polynomial_terms" => target_terms,
        "coefficient_map" => coeffmap,
        "localizing_multipliers" => localizing,
        "equality_multipliers" => equalities,
        "declared_monomial_support" => 60_000,
        "field_hint" => nothing)
    provenance!(artifact, dirname(path);
                source_tool="TSSOS.jl",
                export_script="scripts/export_tssos_sparse_putinar.jl")
    write_json(path, artifact)
end

function nc_artifact(path)
    blocks, bases = simple_factor_blocks(48, 20; prefix="nc", field=:sqrt3)
    examples = [
        Dict("word" => ["A:1:1", "A:1:1"], "canonical" => ["A:1:1"]),
        Dict("word" => ["A:1:1", "A:2:1"], "zero" => true, "canonical" => String[]),
        Dict("word" => ["B:1:1", "A:1:1"], "canonical" => ["A:1:1", "B:1:1"]),
        Dict("word" => ["B:2:2", "A:1:1", "B:1:2"],
             "zero" => true, "canonical" => String[]),
        Dict("word" => ["B:1:2"], "canonical" => ["B:1:2"], "star_star" => ["B:1:2"])
    ]
    identity = Dict("lhs" => [Dict("word" => ["A:1:1"],
                                   "coefficient" => field_json_value(Dict(Int[] => 1//1,
                                                                           [1] => 1//3)))],
                    "rhs" => [Dict("word" => ["A:1:1"],
                                   "coefficient" => field_json_value(Dict(Int[] => 1//1,
                                                                           [1] => 1//3)))])
    artifact = Dict{String, Any}(
        "format" => "final_nc_trace",
        "relations" => ["projector", "orthogonality", "completeness",
                         "cross-party commutation", "trace cyclic equivalence",
                         "star involution"],
        "approx_coefficients" => [string(sqrt(big"3"))],
        "quotient_replay" => Dict("examples" => examples),
        "noisy_factor_blocks" => blocks,
        "block_bases" => bases,
        "raw_words" => ["w$i" for i in 1:20_000],
        "canonical_words" => ["cw$i" for i in 1:2_500],
        "max_word_length" => 6,
        "coefficient_identity" => identity,
        "declared_identity_terms" => 80_000,
        "field_hint" => nothing)
    provenance!(artifact, dirname(path);
                source_tool="NCTSSOS.jl",
                export_script="scripts/export_nctssos_trace.jl")
    write_json(path, artifact)
end

function sdp_artifact(path; farkas=false)
    blocks, _ = simple_factor_blocks(farkas ? 48 : 30, farkas ? 32 : 34;
                                     prefix=farkas ? "fk" : "pd",
                                     zero=true)
    equations = [Dict("lhs" => [Dict("coefficient" => "1", "value" => "1"),
                                Dict("coefficient" => "-1", "value" => "1")],
                      "rhs" => "0") for _ in 1:20]
    artifact = Dict{String, Any}(
        "format" => farkas ? "final_farkas_infeasibility" :
                    "final_primal_dual_gap",
        "linear_constraints" => farkas ? 10_000 : 4_000,
        "field_hint" => nothing)
    if farkas
        artifact["noisy_slack_factors"] = blocks
        artifact["farkas_normalization"] = "-1"
        artifact["sparse_affine_entries_count"] = 200_000
        artifact["sdp_operator"] = Dict(
            "y" => ["1"],
            "b" => ["-1"],
            "A_entries" => Any[],
            "C_entries" => Any[])
        provenance!(artifact, dirname(path);
                    source_tool="JuMP/MOI",
                    export_script="scripts/export_jump_moi_farkas.jl")
    else
        artifact["noisy_primal_factors"] = blocks[1:20]
        artifact["noisy_dual_slack_factors"] = blocks[21:30]
        artifact["objective_gap"] = "0"
        artifact["sdp_operator"] = Dict(
            "y" => ["0"],
            "b" => ["0"],
            "A_entries" => Any[],
            "C_entries" => Any[])
        provenance!(artifact, dirname(path);
                    source_tool="JuMP/MOI",
                    export_script="scripts/export_jump_moi_primal_dual.jl")
    end
    write_json(path, artifact)
end

function make_upstream_session(name, input_path)
    dir = joinpath(UPSTREAM_ROOT, name)
    mkpath(dir)
    write(joinpath(dir, "Project.toml"), "[deps]\nCertSDP = \"00000000-0000-0000-0000-000000000000\"\n")
    write(joinpath(dir, "Manifest.toml"), "# placeholder manifest captured for final replay pack\n")
    write(joinpath(dir, "export_script.jl"),
          """
          # Captured medium upstream export adapter.
          # In --rebuild-from-upstream mode this script replays the stored raw
          # solver stream into certsdp_input.json without invoking a solver.
          println("export_script replayed $name")
          """)
    write(joinpath(dir, "session.log"),
          "solver session: $name\nstatus: replay-only captured medium run\nexport_script: captured\n")
    write(joinpath(dir, "README.md"),
          "# $name\n\nReplay-only upstream session pack with raw output, adapter input, and certificate.\n")
    raw = Dict("session" => name, "solver" => split(name, "_")[1],
               "status" => "solved", "rows" => 2048)
    write_json(joinpath(dir, "raw_output.json"), raw)
    cp(input_path, joinpath(dir, "certsdp_input.json"); force=true)
    input_artifact = JSON3.read(read(joinpath(dir, "certsdp_input.json"), String),
                                Dict{String, Any})
    input_artifact["source_raw_sha256"] = sha(joinpath(dir, "raw_output.json"))
    input_artifact["source_raw_path"] = "raw_output.json"
    input_artifact["source_export_command"] =
        "julia --project export_script.jl --replay-only"
    write_json(joinpath(dir, "certsdp_input.json"), input_artifact)
    result = CertSDP.reconstruct_final_artifact(joinpath(dir, "certsdp_input.json"))
    result.status == :ok || error("could not reconstruct upstream session $name: $(result.message)")
    write_certificate_minified(joinpath(dir, "certificate.json"), result.certificate)
    provenance = Dict("raw_output_sha256" => sha(joinpath(dir, "raw_output.json")),
                      "certsdp_input_sha256" => sha(joinpath(dir, "certsdp_input.json")),
                      "certificate_sha256" => sha(joinpath(dir, "certificate.json")),
                      "mode" => "replay-only")
    write_json(joinpath(dir, "provenance.json"), provenance)
end

function main()
    sos = joinpath(FINAL_ROOT, "sos", "general_low_rank_gram_01.json")
    alg = joinpath(FINAL_ROOT, "sos", "algebraic_low_rank_gram_01.json")
    sos_artifact(sos; dim=120, rank=9, vars=6)
    sos_artifact(alg; dim=80, rank=7, vars=5, algebraic=true)
    field_artifact(joinpath(FINAL_ROOT, "fields", "general_multiquadratic_coeffs_01.json");
                   kind=:mq)
    field_artifact(joinpath(FINAL_ROOT, "fields", "general_cubic_coeffs_01.json");
                   kind=:cubic)
    sparse_artifact(joinpath(FINAL_ROOT, "tssos", "general_sparse_putinar_01.json"))
    nc_artifact(joinpath(FINAL_ROOT, "nctssos", "general_nc_trace_01.json"))
    sdp_artifact(joinpath(FINAL_ROOT, "sdp", "primal_dual_gap_01.json"))
    sdp_artifact(joinpath(FINAL_ROOT, "sdp", "general_farkas_infeasibility_01.json");
                 farkas=true)
    make_upstream_session("sumofsquares_clarabel_general_gram", sos)
    make_upstream_session("tssos_clarabel_sparse_putinar",
                          joinpath(FINAL_ROOT, "tssos",
                                   "general_sparse_putinar_01.json"))
    make_upstream_session("nctssos_cosmo_trace",
                          joinpath(FINAL_ROOT, "nctssos",
                                   "general_nc_trace_01.json"))
    make_upstream_session("jump_moi_sdp_farkas",
                          joinpath(FINAL_ROOT, "sdp",
                                   "general_farkas_infeasibility_01.json"))
end

main()
