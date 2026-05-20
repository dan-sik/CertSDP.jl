using JSON3
using SHA

const ROOT = normpath(joinpath(@__DIR__, "..", "benchmarks", "real_artifacts"))
const UPSTREAM_ROOT = normpath(joinpath(@__DIR__, "..", "benchmarks",
                                        "upstream_artifacts"))

mkpath(ROOT)
for dir in ("sos", "tssos", "fields", "clustered", "nctssos", "infeasibility",
            "traps")
    mkpath(joinpath(ROOT, dir))
end
for dir in ("sumofsquares", "tssos", "nctssos")
    mkpath(joinpath(UPSTREAM_ROOT, dir))
end

jsonwrite(path, object) = open(path, "w") do io
    JSON3.pretty(io, object)
    println(io)
end

function sha256_file(path)
    return "sha256:" * bytes2hex(sha256(read(path)))
end

function write_upstream_pack!(name, source_tool, raw_output, certsdp_input)
    dir = joinpath(UPSTREAM_ROOT, name)
    mkpath(dir)
    raw_path = joinpath(dir, "raw_output.json")
    input_path = joinpath(dir, "certsdp_input.json")
    script_path = joinpath(dir, "export_script.jl")
    jsonwrite(raw_path, raw_output)
    jsonwrite(input_path, certsdp_input)
    open(script_path, "w") do io
        println(io, "# Reproduces the checked-in $source_tool upstream mini-pack.")
        println(io, "# The release gate consumes raw_output.json and certsdp_input.json;")
        println(io, "# strict replay never trusts this script.")
        println(io, "using JSON3")
        println(io, "println(\"exported $source_tool mini-pack\")")
    end
    return (; dir, raw_path, input_path, script_path,
            raw_sha=sha256_file(raw_path))
end

function with_provenance!(artifact, source_tool, pack; command, version="pinned-mini-pack")
    artifact["source_tool"] = source_tool
    artifact["source_tool_version"] = version
    artifact["source_export_command"] = command
    artifact["source_raw_sha256"] = pack.raw_sha
    artifact["source_raw_path"] = relpath(pack.raw_path, ROOT)
    artifact["export_script"] = relpath(pack.script_path,
                                        ROOT)
    artifact["generated_by_certsdp"] = false
    return artifact
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

function nc_identity(; bad=nothing)
    sqrt3 = [Dict("basis" => [1], "coefficient" => "1")]
    lhs = [Dict("word" => ["B:1:2", "A:2:0", "B:1:2"],
                "coefficient" => sqrt3),
           Dict("word" => ["A:0:1", "A:0:1", "B:2:0"],
                "coefficient" => "2"),
           Dict("word" => ["A:0:2", "A:1:2", "B:0:1"],
                "coefficient" => "999"),
           Dict("kind" => "quotient_relation",
                "coefficient" => "5",
                "lhs_word" => ["A:0:0", "B:1:1"],
                "rhs_word" => ["B:1:1", "A:0:0"])]
    rhs = [Dict("word" => ["A:2:0", "B:1:2"],
                "coefficient" => sqrt3),
           Dict("word" => ["A:0:1", "B:2:0"],
                "coefficient" => "2")]
    if bad == :all_commute
        push!(lhs, Dict("word" => ["A:0:0", "B:1:1"], "coefficient" => "1"))
        push!(rhs, Dict("word" => ["B:1:1", "A:0:0"], "coefficient" => "2"))
    end
    return Dict("lhs" => lhs, "rhs" => rhs)
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
    examples = [Dict("word" => ["A:0:1", "A:0:1", "B:2:0"],
                     "canonical" => ["A:0:1", "B:2:0"],
                     "zero" => false,
                     "rule" => "projector_idempotence"),
                Dict("word" => ["A:0:2", "A:1:2", "B:0:1"],
                     "canonical" => [],
                     "zero" => true,
                     "rule" => "same_measurement_orthogonality"),
                Dict("word" => ["B:1:2", "A:2:0", "B:1:2"],
                     "canonical" => ["A:2:0", "B:1:2"],
                     "zero" => false,
                     "rule" => "cross_party_commutation_trace_cyclic"),
                Dict("word" => ["B:2:0", "A:0:1", "A:0:1"],
                     "canonical" => ["A:0:1", "B:2:0"],
                     "zero" => false,
                     "rule" => "trace_cyclic"),
                Dict("word" => ["A:1:1"],
                     "canonical" => ["A:1:1"],
                     "zero" => false,
                     "rule" => "completeness"),
                Dict("word" => ["B:0:0", "A:1:1"],
                     "canonical" => ["A:1:1", "B:0:0"],
                     "zero" => false,
                     "rule" => "star_involution")]
    if bad == :trace_word
        examples[4]["canonical"] = ["B:2:0", "A:0:1"]
    elseif bad == :star
        examples[6]["star_star"] = ["B:0:0", "A:1:1", "B:0:0"]
    end
    quotient = Dict("alphabet" => ["A", "B"],
                    "relations" => relations,
                    "examples" => examples)
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
                "coefficient_identity" => nc_identity(; bad))
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

sumofsquares_pack = write_upstream_pack!(
    "sumofsquares",
    "SumOfSquares.jl",
    Dict("source_tool" => "SumOfSquares.jl",
         "export_kind" => "GramMatrixAttribute",
         "model" => "p(x,y)=z(x,y)'Qz(x,y)",
         "solver_output" => "float64 GramMatrix entries"),
    Dict("format" => "sumofsquares_real_export",
         "basis_source" => "GramMatrixAttribute.basis",
         "coefficient_map_source" => "MOI bridge coefficient map"))
tssos_pack = write_upstream_pack!(
    "tssos",
    "TSSOS.jl",
    Dict("source_tool" => "TSSOS.jl",
         "export_kind" => "sparse clique relaxation",
         "model" => "medium sparse OPF-like polynomial relaxation",
         "solver_output" => "block Gram matrices and multiplier maps"),
    Dict("format" => "tssos_real_sparse_export",
         "basis_source" => "TSSOS block bases",
         "coefficient_map_source" => "sparse support map"))
nctssos_pack = write_upstream_pack!(
    "nctssos",
    "NCTSSOS.jl",
    Dict("source_tool" => "NCTSSOS.jl",
         "export_kind" => "NPA trace quotient",
         "model" => "two-party projector relaxation",
         "solver_output" => "trace quotient words and PSD factors"),
    Dict("format" => "nc_trace_real_export",
         "basis_source" => "NPA moment words",
         "coefficient_map_source" => "quotient normal form replay"))

sos = with_provenance!(sos_artifact(), "SumOfSquares.jl", sumofsquares_pack;
                       command="julia benchmarks/upstream_artifacts/sumofsquares/export_script.jl")
jsonwrite(joinpath(ROOT, "sos", "medium_sumofsquares_01.json"), sos)
tssos = with_provenance!(sparse_artifact(), "TSSOS.jl", tssos_pack;
                         command="julia benchmarks/upstream_artifacts/tssos/export_script.jl")
jsonwrite(joinpath(ROOT, "tssos", "medium_sparse_opf_01.json"), tssos)

field_pack = sumofsquares_pack
jsonwrite(joinpath(ROOT, "fields", "field_QQ.json"),
          with_provenance!(field_artifact(["0.5", "1.25"],
                                          [["1", "0"], ["0", "1"]],
                                          [Dict("label" => "qq",
                                                "lhs" => [Dict("coefficient" => "1",
                                                               "value" => "1")],
                                                "rhs" => "1")]),
                           "JuMP/MOI", field_pack;
                           command="julia benchmarks/upstream_artifacts/sumofsquares/export_script.jl --field QQ"))
jsonwrite(joinpath(ROOT, "fields", "field_sqrt2.json"),
          with_provenance!(field_artifact(["1.4142135623730950488"],
                                          [["1", "0"], ["0", "1"]],
                                          [Dict("label" => "sqrt2",
                                                "lhs" => [Dict("coefficient" => "1.4142135623730950488",
                                                               "value" => "1.4142135623730950488")],
                                                "rhs" => "2")]),
                           "JuMP/MOI", field_pack;
                           command="julia benchmarks/upstream_artifacts/sumofsquares/export_script.jl --field sqrt2"))
jsonwrite(joinpath(ROOT, "fields", "field_sqrt2_sqrt5.json"),
          with_provenance!(field_artifact(["1.4142135623730950488",
                                           "2.2360679774997896964"],
                                          [["1", "0"], ["0", "1"]],
                                          [Dict("label" => "sqrt10",
                                                "lhs" => [Dict("coefficient" => "1.4142135623730950488",
                                                               "value" => "2.2360679774997896964")],
                                                "rhs" => "3.1622776601683793319")]),
                           "JuMP/MOI", field_pack;
                           command="julia benchmarks/upstream_artifacts/sumofsquares/export_script.jl --field sqrt2-sqrt5"))
jsonwrite(joinpath(ROOT, "fields", "field_sqrt3.json"),
          with_provenance!(field_artifact(["1.7320508075688772935"],
                                          [["1", "0"], ["0", "1"]],
                                          [Dict("label" => "sqrt3",
                                                "lhs" => [Dict("coefficient" => "1.7320508075688772935",
                                                               "value" => "1.7320508075688772935")],
                                                "rhs" => "3")]),
                           "JuMP/MOI", field_pack;
                           command="julia benchmarks/upstream_artifacts/sumofsquares/export_script.jl --field sqrt3"))
jsonwrite(joinpath(ROOT, "fields", "field_cubic_plastic.json"),
          with_provenance!(field_artifact(["1.324717957244746025960908854"],
                                          [["1", "0"], ["0", "1"]],
                                          [Dict("label" => "plastic",
                                                "lhs" => [Dict("coefficient" => "1",
                                                               "value" => "1")],
                                                "rhs" => "1")]),
                           "JuMP/MOI", field_pack;
                           command="julia benchmarks/upstream_artifacts/sumofsquares/export_script.jl --field plastic"))

clustered_pack = write_upstream_pack!(
    "clustered",
    "ClusteredLowRankSolver.jl",
    Dict("source_tool" => "ClusteredLowRankSolver.jl",
         "export_kind" => "symmetry reduced low rank SDP",
         "model" => "clustered SDP dual candidate",
         "solver_output" => "low-rank factors and sparse affine map"),
    Dict("format" => "clustered_low_rank_real_export",
         "basis_source" => "representation transforms",
         "coefficient_map_source" => "sparse affine map"))
jsonwrite(joinpath(ROOT, "clustered", "medium_clustered_01.json"),
          with_provenance!(clustered_artifact(), "ClusteredLowRankSolver.jl",
                           clustered_pack;
                           command="julia benchmarks/upstream_artifacts/clustered/export_script.jl"))
jsonwrite(joinpath(ROOT, "clustered", "medium_clustered_bloated.json"),
          with_provenance!(clustered_artifact(; bloated=true),
                           "ClusteredLowRankSolver.jl", clustered_pack;
                           command="julia benchmarks/upstream_artifacts/clustered/export_script.jl --bloated"))
jsonwrite(joinpath(ROOT, "nctssos", "medium_npa_trace_01.json"),
          with_provenance!(nc_artifact(), "NCTSSOS.jl", nctssos_pack;
                           command="julia benchmarks/upstream_artifacts/nctssos/export_script.jl"))
jsonwrite(joinpath(ROOT, "nctssos", "bad_all_variables_commute.json"),
          with_provenance!(nc_artifact(; bad=:all_commute), "NCTSSOS.jl",
                           nctssos_pack;
                           command="julia benchmarks/upstream_artifacts/nctssos/export_script.jl --bad all-commute"))
jsonwrite(joinpath(ROOT, "nctssos", "bad_trace_as_word_equality.json"),
          with_provenance!(nc_artifact(; bad=:trace_word), "NCTSSOS.jl",
                           nctssos_pack;
                           command="julia benchmarks/upstream_artifacts/nctssos/export_script.jl --bad trace-word"))
jsonwrite(joinpath(ROOT, "nctssos", "bad_missing_completeness_relation.json"),
          with_provenance!(nc_artifact(; bad=:missing_completeness),
                           "NCTSSOS.jl", nctssos_pack;
                           command="julia benchmarks/upstream_artifacts/nctssos/export_script.jl --bad missing-completeness"))
jsonwrite(joinpath(ROOT, "nctssos", "bad_star_involution.json"),
          with_provenance!(nc_artifact(; bad=:star), "NCTSSOS.jl",
                           nctssos_pack;
                           command="julia benchmarks/upstream_artifacts/nctssos/export_script.jl --bad star"))
jsonwrite(joinpath(ROOT, "infeasibility", "medium_farkas_01.json"),
          with_provenance!(farkas_artifact(), "JuMP/MOI", tssos_pack;
                           command="julia benchmarks/upstream_artifacts/tssos/export_script.jl --farkas"))

trap = with_provenance!(sos_artifact(), "SumOfSquares.jl", sumofsquares_pack;
                        command="julia benchmarks/upstream_artifacts/sumofsquares/export_script.jl --trap")
trap["metadata"] = Dict("valid" => true,
                        "all_psd_blocks_verified" => true,
                        "coefficient_residual" => 0,
                        "hash_commitment" => "sha256:" * bytes2hex(sha256(JSON3.write(trap))))
trap["coefficient_map"][1]["scale"] = "2"
jsonwrite(joinpath(ROOT, "traps", "looks_valid_but_wrong_hash.json"), trap)

println("generated CertSDP 2.1R real artifact corpus at $ROOT")
