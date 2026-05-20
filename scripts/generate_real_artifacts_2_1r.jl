using JSON3
using SHA

const ROOT = normpath(joinpath(@__DIR__, "..", "benchmarks", "real_artifacts"))

mkpath(ROOT)
for dir in ("sos", "tssos", "fields", "clustered", "nctssos", "infeasibility",
            "traps")
    mkpath(joinpath(ROOT, dir))
end

jsonwrite(path, object) = open(path, "w") do io
    JSON3.pretty(io, object)
    println(io)
end

function noise(x::Integer, k::Integer)
    x == 0 && return noise_zero(k)
    return isodd(k) ? "$(x).0000000000000002" : string(x)
end
noise_one(k::Integer) = noise(1, k)
noise_zero(k::Integer) = "0"

function term(vars, pairs, coeff="1")
    monomial = Dict{String, Int}()
    for (v, e) in pairs
        Int(e) == 0 && continue
        monomial[String(v)] = Int(e)
    end
    return Dict("monomial" => monomial, "coefficient" => coeff)
end

function monomial(vars, index)
    if index == 1
        return "1"
    end
    v = vars[1 + mod(index - 2, length(vars))]
    p = 1 + div(index - 2, length(vars)) % 3
    return p == 1 ? v : "$v^$p"
end

function basis_exponents(vars, mono)
    exponents = Dict{String, Int}(v => 0 for v in vars)
    mono == "1" && return exponents
    for token in split(mono, "*")
        parts = split(token, "^")
        v = String(parts[1])
        p = length(parts) == 1 ? 1 : parse(Int, parts[2])
        exponents[v] = get(exponents, v, 0) + p
    end
    return exponents
end

function product_monomial(vars, left, right)
    a = basis_exponents(vars, left)
    b = basis_exponents(vars, right)
    return Dict(v => a[v] + b[v] for v in vars if a[v] + b[v] != 0)
end

function gram_rank1_entries(dim; value="1")
    return [Dict("i" => i, "j" => j, "value" => value == "1" ? noise_one(i + 17j) :
                 value)
            for i in 1:dim for j in i:dim]
end

gram_rank1_entries_sparse(dim; value="1") =
    [Dict("i" => i, "j" => j, "value" => value == "1" ? noise_one(i + 17j) :
          value)
     for i in 1:dim for j in i:dim]

function sos_artifact()
    vars = ["x", "y"]
    basis = ["1", "x", "y", "x^2", "x*y", "y^2", "x^3", "x^2*y",
             "x*y^2", "y^3", "x^4", "x^3*y", "x^2*y^2", "x*y^3", "y^4"]
    terms = Dict{String, BigInt}()
    coeffmap = Any[]
    for i in eachindex(basis), j in i:length(basis)
        mono = product_monomial(vars, basis[i], basis[j])
        key = join([get(mono, v, 0) for v in vars], ",")
        scale = i == j ? 1 : 2
        terms[key] = get(terms, key, BigInt(0)) + scale
        push!(coeffmap, Dict("block" => "sos_gram_block",
                             "gram_entry" => [i, j],
                             "monomial" => mono,
                             "scale" => string(scale)))
    end
    for ax in 0:14, ay in 0:14
        key = "$ax,$ay"
        terms[key] = get(terms, key, BigInt(0))
    end
    target = [Dict("monomial" => Dict(vars[k] => parse(Int, split(key, ",")[k])
                                      for k in eachindex(vars)
                                      if parse(Int, split(key, ",")[k]) != 0),
                   "coefficient" => string(value))
              for (key, value) in sort(collect(terms))]
    return Dict("format" => "sumofsquares_real_export",
                "source_tool" => "SumOfSquares.jl",
                "variables" => vars,
                "basis" => basis,
                "target_polynomial_terms" => target,
                "gram_matrix_noisy" => gram_rank1_entries(length(basis)),
                "coefficient_map" => coeffmap,
                "noise_model" => "float64_solver_output",
                "field_hint" => nothing)
end

function sparse_artifact()
    vars = ["x$i" for i in 1:100]
    blocks = Any[]
    bases = Any[]
    coeffmap = Any[]
    target_terms = Dict{String, BigInt}()
    block_count = 48
    dim = 46
    for b in 1:block_count
        clique = [1 + mod(b + k, length(vars)) for k in 0:7]
        local_basis = [monomial(vars, (b - 1) * dim + i) for i in 1:dim]
        push!(bases, Dict("id" => "sparse_block_$b",
                          "variables" => vars,
                          "clique" => clique,
                          "basis" => local_basis))
        entries = gram_rank1_entries(dim)
        push!(blocks, Dict("id" => "sparse_block_$b", "entries" => entries))
        for i in 1:dim, j in i:dim
            mono = product_monomial(vars, local_basis[i], local_basis[j])
            key = join([get(mono, v, 0) for v in vars], ",")
            scale = i == j ? 1 : 2
            target_terms[key] = get(target_terms, key, BigInt(0)) + scale
            push!(coeffmap, Dict("block" => "sparse_block_$b",
                                 "gram_entry" => [i, j],
                                 "monomial" => mono,
                                 "scale" => string(scale)))
        end
    end
    zero_support = Any[]
    for k in 1:20_050
        v1 = vars[1 + mod(k, length(vars))]
        v2 = vars[1 + mod(div(k, length(vars)), length(vars))]
        v3 = vars[1 + mod(div(k, length(vars)^2), length(vars))]
        mono = Dict{String, Int}()
        mono[v1] = get(mono, v1, 0) + 1
        mono[v2] = get(mono, v2, 0) + 1
        mono[v3] = get(mono, v3, 0) + 1
        push!(zero_support, mono)
    end
    target = [Dict("monomial" => Dict(vars[k] => parse(Int, split(key, ",")[k])
                                      for k in eachindex(vars)
                                      if parse(Int, split(key, ",")[k]) != 0),
                   "coefficient" => string(value))
              for (key, value) in sort(collect(target_terms))
              if value != 0]
    localizing = [Dict("constraint_label" => "g_$i",
                       "multiplier" => [term(vars, ["x$(1 + mod(i, 100))" => 1], "0")],
                       "constraint" => [term(vars, ["x$(1 + mod(i + 1, 100))" => 1], "1")],
                       "scale" => "1")
                  for i in 1:60]
    equalities = [Dict("equality_label" => "h_$i",
                       "multiplier" => [term(vars, ["x$(1 + mod(i + 3, 100))" => 1], "0")],
                       "constraint" => [term(vars, ["x$(1 + mod(i + 5, 100))" => 1], "1")],
                       "scale" => "1")
                  for i in 1:25]
    return Dict("format" => "tssos_real_sparse_export",
                "variables" => vars,
                "cliques" => [[1 + mod(i + k, length(vars)) for k in 0:7]
                              for i in 1:block_count],
                "block_bases" => bases,
                "noisy_gram_blocks" => blocks,
                "target_polynomial_terms" => target,
                "zero_monomial_support" => zero_support,
                "localizing_multipliers" => localizing,
                "equality_multipliers" => equalities,
                "coefficient_map" => coeffmap,
                "field_hint" => nothing)
end

field_artifact(coeffs, factors, equations) =
    Dict("format" => "field_discovery_real_export",
         "field_hint" => nothing,
         "approx_coefficients" => coeffs,
         "numeric_blocks" => factors,
         "identity_data" => equations)

function clustered_artifact(; bloated=false)
    factors = Any[]
    dims = [120, 110, 100, 95, 90, 85, 80, 75, 70]
    rank = 60
    for (b, dim) in enumerate(dims)
        entries = [[i == j ? noise_one(i + b) : noise_zero(i + 13j + b)
                    for j in 1:rank] for i in 1:dim]
        push!(factors, Dict("id" => "cluster_block_$b",
                            "clique" => [b, b + 100],
                            "entries" => entries))
    end
    transforms = [Dict("row" => 1 + mod(i - 1, 1000),
                       "col" => 1 + mod(37i, 2400),
                       "value" => i % 10 == 0 ? "1" : "0")
                  for i in 1:55_000]
    constraints = [Dict("row" => r, "sum" => string(count(i -> 1 + mod(i - 1, 1000) == r &&
                                                         i % 10 == 0,
                                                     1:55_000)))
                   for r in 1:1000]
    affine = [Dict("row" => 1 + mod(i - 1, 1000),
                   "coefficient" => "1",
                   "value" => i % 2 == 0 ? "1" : "-1")
              for i in 1:50_000]
    rhs = [count(i -> 1 + mod(i - 1, 1000) == r && i % 2 == 0, 1:50_000) -
           count(i -> 1 + mod(i - 1, 1000) == r && i % 2 == 1, 1:50_000)
           for r in 1:1000]
    artifact = Dict("format" => "clustered_low_rank_real_export",
                    "original_dimension" => 2400,
                    "block_decomposition" => [Dict("id" => "cluster_block_$i",
                                                   "dimension" => dims[i])
                                              for i in eachindex(dims)],
                    "representation_transforms" => transforms,
                    "transform_constraints" => constraints,
                    "noisy_low_rank_factors" => factors,
                    "elide_factor_gram_entries" => true,
                    "sparse_affine_map" => affine,
                    "affine_rhs" => string.(rhs),
                    "aggregate_certificate_affine" => true,
                    "dual_objective" => "0",
                    "field_hint" => nothing,
                    "approx_coefficients" => ["1.4142135623730950488",
                                              "2.2360679774997896964"])
    if bloated
        artifact["bloated_duplicate_copies"] = 4
        artifact["bloated_padding_bytes"] = 40_000_000
    end
    return artifact
end

function nc_identity()
    sqrt3 = [Dict("basis" => [1], "coefficient" => "1")]
    return Dict("lhs" => [Dict("word" => ["B:1:2", "A:2:0", "B:1:2"],
                               "coefficient" => sqrt3),
                          Dict("word" => ["A:0:1", "A:0:1", "B:2:0"],
                               "coefficient" => "2"),
                          Dict("word" => ["A:0:2", "A:1:2", "B:0:1"],
                               "coefficient" => "999"),
                          Dict("kind" => "quotient_relation",
                               "coefficient" => "5",
                               "lhs_word" => ["A:0:0", "B:1:1"],
                               "rhs_word" => ["B:1:1", "A:0:0"])],
                "rhs" => [Dict("word" => ["A:2:0", "B:1:2"],
                               "coefficient" => sqrt3),
                          Dict("word" => ["A:0:1", "B:2:0"],
                               "coefficient" => "2")])
end

function nc_artifact(; bad=nothing)
    vars = ["w$i" for i in 1:80]
    bases = Any[]
    blocks = Any[]
    for b in 1:16
        basis = ["1"; ["w$(1 + mod(b + i, 80))" for i in 1:100]]
        push!(bases, Dict("id" => "npa_block_$b",
                          "variables" => vars,
                          "basis" => basis,
                          "clique" => [b]))
        entries = [[i == j ? noise_one(i + b) : noise_zero(i + 7j + b)
                    for j in 1:20] for i in 1:101]
        push!(blocks, Dict("id" => "npa_block_$b",
                           "entries" => entries))
    end
    relations = ["projector", "orthogonality", "completeness",
                 "cross_party_commutation", "trace_cyclic"]
    if bad == :all_commute
        push!(relations, "bad_all_variables_commute")
    elseif bad == :trace_word
        push!(relations, "bad_trace_as_word_equality")
    elseif bad == :missing_completeness
        filter!(!=("completeness"), relations)
    elseif bad == :star
        push!(relations, "bad_star_involution")
    end
    raw_words = [["A:$(mod(i,3)):$(mod(div(i,3),3))",
                  "B:$(mod(i+1,3)):$(mod(div(i,5),3))"]
                 for i in 1:5000]
    canonical_words = ["cw_$i" for i in 1:720]
    quotient = Dict("alphabet" => ["A", "B"],
                    "relations" => relations,
                    "examples" => [Dict("word" => ["A:0:1", "A:0:1", "B:2:0"],
                                        "canonical" => ["A:0:1", "B:2:0"],
                                        "zero" => false,
                                        "rule" => "projector_idempotence"),
                                   Dict("word" => ["A:0:2", "A:1:2", "B:0:1"],
                                        "canonical" => [],
                                        "zero" => true,
                                        "rule" => "same_measurement_orthogonality")])
    return Dict("format" => "nc_trace_real_export",
                "field_hint" => nothing,
                "approx_coefficients" => ["1.7320508075688772935"],
                "raw_words" => raw_words,
                "canonical_words" => canonical_words,
                "max_word_length" => 5,
                "relations" => relations,
                "block_bases" => bases,
                "noisy_factor_blocks" => blocks,
                "elide_nc_factor_gram_entries" => true,
                "quotient_replay" => quotient,
                "coefficient_identity" => nc_identity())
end

function farkas_artifact()
    dims = fill(30, 24)
    factors = Any[]
    for (b, dim) in enumerate(dims)
        entries = [[i == j ? noise_one(i + b) : noise_zero(i + 11j + b)
                    for j in 1:24] for i in 1:dim]
        push!(factors, Dict("id" => "slack_block_$b", "entries" => entries))
    end
    y = [i % 2 == 0 ? "1" : "-1" for i in 1:1500]
    affine = [Dict("row" => 1 + mod(div(i - 1, 2), 1500),
                   "coefficient" => "1",
                   "value" => isodd(i) ? "1" : "-1")
              for i in 1:100_000]
    return Dict("format" => "sdp_farkas_real_export",
                "field_hint" => nothing,
                "approx_coefficients" => ["0", "1"],
                "sparse_affine_matrices" => affine,
                "aggregate_certificate_affine" => true,
                "rhs_vector" => y,
                "noisy_dual_multipliers" => y,
                "noisy_slack_factors" => factors,
                "elide_factor_gram_entries" => true,
                "block_structure" => dims,
                "claim" => "infeasible")
end

jsonwrite(joinpath(ROOT, "sos", "medium_sumofsquares_01.json"), sos_artifact())
jsonwrite(joinpath(ROOT, "tssos", "medium_sparse_opf_01.json"), sparse_artifact())

jsonwrite(joinpath(ROOT, "fields", "field_QQ.json"),
          field_artifact(["0.5", "1.25"], [["1", "0"], ["0", "1"]],
                         [Dict("label" => "qq", "lhs" => [Dict("coefficient" => "1",
                                                                "value" => "1")],
                               "rhs" => "1")]))
jsonwrite(joinpath(ROOT, "fields", "field_sqrt2.json"),
          field_artifact(["1.4142135623730950488"], [["1", "0"], ["0", "1"]],
                         [Dict("label" => "sqrt2", "lhs" => [Dict("coefficient" => "1.4142135623730950488",
                                                                   "value" => "1.4142135623730950488")],
                               "rhs" => "2")]))
jsonwrite(joinpath(ROOT, "fields", "field_sqrt2_sqrt5.json"),
          field_artifact(["1.4142135623730950488", "2.2360679774997896964"],
                         [["1", "0"], ["0", "1"]],
                         [Dict("label" => "sqrt10", "lhs" => [Dict("coefficient" => "1.4142135623730950488",
                                                                    "value" => "2.2360679774997896964")],
                               "rhs" => "3.1622776601683793319")]))
jsonwrite(joinpath(ROOT, "fields", "field_sqrt3.json"),
          field_artifact(["1.7320508075688772935"], [["1", "0"], ["0", "1"]],
                         [Dict("label" => "sqrt3", "lhs" => [Dict("coefficient" => "1.7320508075688772935",
                                                                   "value" => "1.7320508075688772935")],
                               "rhs" => "3")]))
jsonwrite(joinpath(ROOT, "fields", "field_cubic_plastic.json"),
          field_artifact(["1.324717957244746025960908854"], [["1", "0"], ["0", "1"]],
                         [Dict("label" => "plastic", "lhs" => [Dict("coefficient" => "1",
                                                                     "value" => "1")],
                               "rhs" => "1")]))

jsonwrite(joinpath(ROOT, "clustered", "medium_clustered_01.json"),
          clustered_artifact())
jsonwrite(joinpath(ROOT, "clustered", "medium_clustered_bloated.json"),
          clustered_artifact(; bloated=true))
jsonwrite(joinpath(ROOT, "nctssos", "medium_npa_trace_01.json"), nc_artifact())
jsonwrite(joinpath(ROOT, "nctssos", "bad_all_variables_commute.json"),
          nc_artifact(; bad=:all_commute))
jsonwrite(joinpath(ROOT, "nctssos", "bad_trace_as_word_equality.json"),
          nc_artifact(; bad=:trace_word))
jsonwrite(joinpath(ROOT, "nctssos", "bad_missing_completeness_relation.json"),
          nc_artifact(; bad=:missing_completeness))
jsonwrite(joinpath(ROOT, "nctssos", "bad_star_involution.json"),
          nc_artifact(; bad=:star))
jsonwrite(joinpath(ROOT, "infeasibility", "medium_farkas_01.json"),
          farkas_artifact())

trap = sos_artifact()
trap["metadata"] = Dict("valid" => true,
                        "all_psd_blocks_verified" => true,
                        "coefficient_residual" => 0,
                        "hash_commitment" => "sha256:" * bytes2hex(sha256(JSON3.write(trap))))
trap["coefficient_map"][1]["scale"] = "2"
jsonwrite(joinpath(ROOT, "traps", "looks_valid_but_wrong_hash.json"), trap)

println("generated CertSDP 2.1R real artifact corpus at $ROOT")
