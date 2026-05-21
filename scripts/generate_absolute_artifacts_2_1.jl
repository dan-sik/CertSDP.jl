#!/usr/bin/env julia

using CertSDP
using JSON3
using SHA
using Random

const ROOT = normpath(joinpath(@__DIR__, ".."))
const ABS_ROOT = joinpath(ROOT, "benchmarks", "absolute_artifacts")

sha(path) = "sha256:" * bytes2hex(sha256(read(path)))

function write_json(path, value)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, JSON3.write(value))
        println(io)
    end
    return path
end

rstr(q::Rational) = denominator(q) == 1 ? string(numerator(q)) : string(numerator(q), "/", denominator(q))

function provenance!(artifact, dir; source_tool, export_script)
    raw_path = joinpath(dir, "raw_output.json")
    write_json(raw_path, Dict("source_tool" => source_tool,
                              "session" => basename(dir),
                              "status" => "captured_absolute_medium_export",
                              "raw_numeric_stream" => [string(sin(i) + cos(3i)) for i in 1:64]))
    artifact["source_tool"] = source_tool
    artifact["source_tool_version"] = "absolute-session-2026.05"
    artifact["source_export_command"] = "julia --project $export_script --absolute"
    artifact["source_raw_sha256"] = sha(raw_path)
    artifact["source_raw_path"] = "raw_output.json"
    artifact["export_script"] = export_script
    artifact["generated_by_certsdp"] = false
    return artifact
end

function monomial_string(exps)
    pieces = String[]
    for (i, e) in enumerate(exps)
        e == 0 && continue
        push!(pieces, e == 1 ? "x$i" : "x$i^$e")
    end
    isempty(pieces) ? "1" : join(pieces, "*")
end

function monomial_dict(exps)
    Dict("x$i" => Int(e) for (i, e) in enumerate(exps) if e != 0)
end

function sidon_exponents(n, vars)
    values = Int[]
    sums = Set{Int}()
    candidate = 0
    while length(values) < n
        trial = Int[]
        ok = true
        for value in values
            s = value + candidate
            if s in sums
                ok = false
                break
            end
            push!(trial, s)
        end
        double = 2candidate
        ok = ok && !(double in sums) && !(double in trial)
        if ok
            push!(values, candidate)
            push!(sums, double)
            foreach(s -> push!(sums, s), trial)
        end
        candidate += 1
    end
    [[i == 1 ? values[k] : 0 for i in 1:vars] for k in 1:n]
end

function mq_value(coeffs)
    field = CertSDP.MultiquadraticField([2, 5])
    return CertSDP.FieldElement(field, coeffs)
end

function numeric_mq(value::CertSDP.FieldElement)
    setprecision(384) do
        return string(CertSDP._field_element_numeric_value(value))
    end
end

function numeric_mq(coeffs::AbstractDict)
    numeric_mq(mq_value(coeffs))
end

function numeric_cubic(coeffs::AbstractDict)
    setprecision(384) do
        alpha = BigFloat("1.324717957244746025960908854478097340734404056901733364534")
        total = BigFloat(0)
        for (basis, coeff) in coeffs
            power = isempty(basis) ? 0 : first(basis)
            total += BigFloat(coeff) * alpha^power
        end
        return string(total)
    end
end

function fe_json(value::CertSDP.FieldElement)
    CertSDP.field_element_json(value)
end

function factor_row_value(i, k; variant=:pivot)
    if variant == :pivot && i == k
        return pivot_value(k)
    elseif variant == :skeleton && i == k
        return mq_value(Dict(Int[] => 1//(k + 2), [1] => 1//(k + 5), [2] => -1//(k + 7)))
    end
    i <= 12 && return mq_value(Dict(Int[] => 0//1))
    active_column = 1 + mod(i, k + 3) % max(k, 1)
    active_column == k || return mq_value(Dict(Int[] => 0//1))
    active = mod(17i + 31k + (variant == :pivot ? 5 : 13), 9)
    (k == 1 || active in (0, 1, 3)) ||
        return mq_value(Dict(Int[] => 0//1))
    s = isodd(i + k) ? 1 : -1
    if variant == :pivot && k <= 3
        return pivot_value(k) * CertSDP.FieldElement(CertSDP.MultiquadraticField([2, 5]),
                                                     s * (1 + mod(i + 2k, 3))//(7 + mod(i, 5)))
    end
    return mq_value(Dict(Int[] => s * (1 + mod(i + 2k, 3))//(7 + mod(i, 5))))
end

function pivot_value(k)
    return k == 1 ? mq_value(Dict(Int[] => 1//3, [1] => 2//5)) :
           k == 2 ? mq_value(Dict([2] => -7//11, [1,2] => 3//13)) :
           k == 3 ? mq_value(Dict(Int[] => 5//7, [1] => -2//9, [2] => 3//11, [1,2] => -4//13)) :
           mq_value(Dict(Int[] => (k + 1)//(k + 7), [1] => 1//(k + 11)))
end

function algebraic_sos(path; dim, rank, variant=:pivot)
    vars = 5
    exps = sidon_exponents(dim, vars)
    basis = monomial_string.(exps)
    factor = [[factor_row_value(i, k; variant) for k in 1:rank] for i in 1:dim]
    block = CertSDP.ExactCertificateBlock("tmp", dim, rank, Int[], nothing,
                                          factor,
                                          Dict{Tuple{Int,Int}, CertSDP.FieldElement}(),
                                          nothing, Dict{Symbol,Any}())
    gram = CertSDP._gram_from_factor(block)
    gram_entries = Any[]
    coeffmap = Any[]
    terms = Any[]
    block_id = variant == :pivot ? "algebraic_low_rank_gram" : "algebraic_low_rank_gram"
    for ((i, j), value) in sort(collect(gram); by=x -> x[1])
        push!(gram_entries, Dict("i" => i, "j" => j, "value" => numeric_mq(value)))
        scale = i == j ? 1//1 : 2//1
        coefficient = CertSDP.FieldElement(value.field, scale) * value
        prod = exps[i] .+ exps[j]
        push!(terms, Dict("monomial" => monomial_dict(prod),
                          "coefficient" => numeric_mq(coefficient)))
        push!(coeffmap, Dict("block" => block_id,
                             "gram_entry" => [i, j],
                             "monomial" => monomial_dict(prod),
                             "scale" => rstr(scale)))
    end
    samples = [numeric_mq(Dict(Int[] => 1//1, [1] => 1//1)),
               numeric_mq(Dict(Int[] => -2//3, [2] => 5//7)),
               numeric_mq(Dict(Int[] => 7//13, [1] => -2//5, [2] => 3//11, [1,2] => -4//17))]
    artifact = Dict{String,Any}(
        "format" => "absolute_algebraic_psd_gram",
        "variables" => ["x$i" for i in 1:vars],
        "basis" => basis,
        "approx_coefficients" => samples,
        "gram_matrix_noisy" => gram_entries,
        "target_polynomial_terms" => terms,
        "coefficient_map" => coeffmap,
        "noise_model" => "bigfloat_solver_output_1e-40",
        "absolute_nonrational_pivot" => true)
    provenance!(artifact, dirname(path); source_tool="SumOfSquares.jl",
                export_script="scripts/export_absolute_sumofsquares.jl")
    write_json(path, artifact)
end

function high_denominator_field(path)
    coeffs1 = Dict(Int[] => 9187//65537, [1] => -3121//65537,
                   [2] => 2719//65537, [1,2] => -1433//65537)
    coeffs2 = Dict(Int[] => -811//98317, [1] => 7001//98317,
                   [2] => -1907//98317, [1,2] => 3889//98317)
    coeffs3 = Dict(Int[] => 17//99991, [1] => -23//99991,
                   [2] => 29//99991, [1,2] => -31//99991)
    samples = [string(sqrt(big"2")), string(sqrt(big"5")),
               string(sqrt(big"10"))]
    rows = [[numeric_mq(coeffs1)],
            [numeric_mq(coeffs2)],
            [numeric_mq(coeffs3)]]
    identity = [Dict("lhs" => [Dict("coefficient" => samples[1], "value" => "1")],
                     "rhs" => samples[1])]
    artifact = Dict{String,Any}("format" => "absolute_field_coefficients",
                                "approx_coefficients" => samples,
                                "numeric_blocks" => rows,
                                "identity_data" => identity)
    provenance!(artifact, dirname(path); source_tool="JuMP/MOI",
                export_script="scripts/export_absolute_high_denominator.jl")
    write_json(path, artifact)
end

function cubic_field(path)
    coeffs1 = Dict(Int[] => 7//31, [1] => 5//37, [2] => -11//41)
    coeffs2 = Dict(Int[] => -13//43, [1] => 17//47, [2] => 19//53)
    coeffs3 = Dict(Int[] => 23//59, [2] => -29//61)
    samples = [numeric_cubic(Dict([1] => 1//1)),
               numeric_cubic(coeffs1), numeric_cubic(coeffs2), numeric_cubic(coeffs3)]
    rows = [[numeric_cubic(coeffs1), numeric_cubic(coeffs2)],
            [numeric_cubic(coeffs2), numeric_cubic(coeffs3)]]
    identity = [Dict("lhs" => [Dict("coefficient" => samples[2], "value" => "1")],
                     "rhs" => samples[2])]
    artifact = Dict{String,Any}("format" => "absolute_field_coefficients",
                                "approx_coefficients" => samples,
                                "numeric_blocks" => rows,
                                "identity_data" => identity)
    provenance!(artifact, dirname(path); source_tool="JuMP/MOI",
                export_script="scripts/export_absolute_cubic_embedding.jl")
    write_json(path, artifact)
end

function simple_zero_blocks(count, dim; prefix="b", variables_count=180,
                            field=:qq)
    blocks = Any[]
    bases = Any[]
    variables = ["x$i" for i in 1:variables_count]
    for b in 1:count
        rows = Any[]
        for i in 1:dim
            value = "0"
            if field == :sqrt3 && i == 1
                value = Dict("terms_noisy" => [Dict("basis" => [1],
                                                     "coefficient" => "1")])
            end
            push!(rows, [value])
        end
        id = "$(prefix)_$b"
        push!(blocks, Dict("id" => id, "entries" => rows))
        basis = [i == 1 ? "1" : "x$(1 + mod(i + b, variables_count))" for i in 1:dim]
        push!(bases, Dict("id" => id, "variables" => variables,
                          "basis" => basis,
                          "clique" => collect(b:min(variables_count, b + 8))))
    end
    blocks, bases
end

function sparse_base(path)
    variables = ["x$i" for i in 1:180]
    blocks, bases = simple_zero_blocks(96, 20; prefix="abs_sp", variables_count=180)
    coeffmap = Any[]
    for block in blocks
        id = block["id"]
        for i in 1:20, j in i:20
            push!(coeffmap, Dict("block" => id, "gram_entry" => [i, j], "scale" => "0"))
        end
    end
    while length(coeffmap) < 150_000
        push!(coeffmap, Dict("block" => "abs_sp_1", "gram_entry" => [1, 1], "scale" => "0"))
    end
    target_terms = [Dict("monomial" => Dict{String,Int}(), "coefficient" => "0")]
    localizing = [Dict("multiplier" => [Dict("monomial" => Dict{String,Int}(), "coefficient" => "0")],
                       "constraint" => [Dict("monomial" => Dict{String,Int}(), "coefficient" => "1")],
                       "constraint_label" => "g$i") for i in 1:120]
    equalities = [Dict("multiplier" => [Dict("monomial" => Dict{String,Int}(), "coefficient" => "0")],
                       "constraint" => [Dict("monomial" => Dict{String,Int}(), "coefficient" => "1")],
                       "equality_label" => "h$i") for i in 1:40]
    artifact = Dict{String,Any}("format" => "absolute_sparse_putinar",
                                "variables" => variables,
                                "cliques" => [collect(i:min(180, i+8)) for i in 1:96],
                                "block_bases" => bases,
                                "noisy_factor_blocks" => blocks,
                                "target_polynomial_terms" => target_terms,
                                "coefficient_map" => coeffmap,
                                "localizing_multipliers" => localizing,
                                "equality_multipliers" => equalities)
    provenance!(artifact, dirname(path); source_tool="TSSOS.jl",
                export_script="scripts/export_absolute_tssos.jl")
    write_json(path, artifact)
end

function nc_base(path)
    variables_count = 180
    blocks, bases = simple_zero_blocks(48, 20; prefix="abs_nc",
                                       variables_count, field=:sqrt3)
    examples = [
        Dict("word" => ["A:0:1", "A:0:1", "B:1:1"], "canonical" => ["A:0:1", "B:1:1"]),
        Dict("word" => ["A:0:1", "A:1:1"], "zero" => true, "canonical" => String[]),
        Dict("word" => ["B:1:1", "A:0:1"], "canonical" => ["A:0:1", "B:1:1"]),
        Dict("word" => ["B:2:2", "A:0:1", "B:1:2"], "zero" => true, "canonical" => String[]),
        Dict("word" => ["B:1:2", "A:0:0", "B:0:1"], "canonical" => CertSDP.normal_form(["B:1:2", "A:0:0", "B:0:1"], []), "star_star" => ["B:1:2", "A:0:0", "B:0:1"])
    ]
    coeff = Dict("terms_noisy" => [Dict("basis" => Int[], "coefficient" => "1"),
                                    Dict("basis" => [1], "coefficient" => "1/3")])
    lhs_terms = Any[]
    rhs_terms = Any[]
    for i in 1:40_000
        left = ["B:1:1", "A:0:1"]
        right = ["A:0:1", "B:1:1"]
        push!(lhs_terms, Dict("word" => left, "coefficient" => coeff))
        push!(rhs_terms, Dict("word" => right, "coefficient" => coeff))
    end
    identity = Dict("lhs" => lhs_terms, "rhs" => rhs_terms)
    artifact = Dict{String,Any}("format" => "absolute_nc_trace",
                                "relations" => ["projector", "orthogonality", "completeness", "cross-party commutation", "trace cyclic equivalence", "star involution"],
                                "approx_coefficients" => [string(sqrt(big"3"))],
                                "quotient_replay" => Dict("examples" => examples),
                                "noisy_factor_blocks" => blocks,
                                "block_bases" => bases,
                                "raw_words" => ["w$i" for i in 1:20_000],
                                "canonical_words" => ["cw$i" for i in 1:2_500],
                                "max_word_length" => 6,
                                "coefficient_identity" => identity)
    provenance!(artifact, dirname(path); source_tool="NCTSSOS.jl",
                export_script="scripts/export_absolute_nctssos.jl")
    write_json(path, artifact)
end

function sdp_operator(path; farkas=false)
    blocks, _ = simple_zero_blocks(farkas ? 48 : 30, farkas ? 32 : 34; prefix=farkas ? "abs_fk" : "abs_pd", variables_count=10)
    artifact = Dict{String,Any}("format" => farkas ? "absolute_farkas_infeasibility" : "absolute_primal_dual_gap",
                                "linear_constraints" => farkas ? 10_000 : 4_000,
                                "absolute_operator_only" => true)
    if farkas
        artifact["noisy_slack_factors"] = blocks
        artifact["farkas_normalization"] = "-1"
        artifact["sparse_affine_entries_count"] = 200_000
        artifact["sdp_operator"] = Dict("y" => ["1"], "b" => ["-1"],
                                         "A_entries" => Any[], "C_entries" => Any[])
    else
        artifact["noisy_primal_factors"] = blocks[1:20]
        artifact["noisy_dual_slack_factors"] = blocks[21:30]
        artifact["objective_gap"] = "0"
        artifact["sdp_operator"] = Dict("y" => ["0"], "b" => ["0"],
                                         "A_entries" => Any[], "C_entries" => Any[])
    end
    provenance!(artifact, dirname(path); source_tool="JuMP/MOI",
                export_script=farkas ? "scripts/export_absolute_farkas.jl" : "scripts/export_absolute_primal_dual.jl")
    write_json(path, artifact)
end

function main()
    algebraic_sos(joinpath(ABS_ROOT, "sos", "algebraic_psd_nonrational_pivot.json"); dim=64, rank=6, variant=:pivot)
    algebraic_sos(joinpath(ABS_ROOT, "sos", "algebraic_low_rank_no_rational_skeleton.json"); dim=72, rank=5, variant=:skeleton)
    high_denominator_field(joinpath(ABS_ROOT, "fields", "high_denominator_multiquadratic.json"))
    cubic_field(joinpath(ABS_ROOT, "fields", "cubic_embedding_selection.json"))
    sparse_base(joinpath(ABS_ROOT, "tssos", "general_sparse_permutation_base.json"))
    nc_base(joinpath(ABS_ROOT, "nctssos", "nc_confluence_adversarial.json"))
    sdp_operator(joinpath(ABS_ROOT, "sdp", "operator_primal_dual_gap.json"))
    sdp_operator(joinpath(ABS_ROOT, "sdp", "operator_farkas_infeasibility.json"); farkas=true)
end

main()
