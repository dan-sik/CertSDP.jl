struct NativeHiddenArtifactSet
    valid::Vector{NamedTuple}
    invalid::Vector{NamedTuple}
    generation_log::Vector{Dict{Symbol, Any}}
end

struct PSDFieldFactorizationResult
    status::Symbol
    field::ExactFieldSpec
    rank::Int
    factor::Vector{Vector{FieldElement}}
    pivots::Vector{Int}
    pivot_values::Vector{FieldElement}
    method::Symbol
    residual_zero::Bool
    used_rational_coordinate_skeleton::Bool
    used_nonrational_pivots::Bool
    failure_stage::Union{Nothing, Symbol}
    message::String
end

struct NCConfluenceReport
    status::Symbol
    num_words_checked::Int
    num_critical_pairs_checked::Int
    failures::Vector{Any}
    paths::Vector{Any}
end

struct SparseSemanticDensityReport
    status::Symbol
    total_entries::Int
    nonzero_scale_entries::Int
    nonzero_contribution_entries::Int
    duplicate_zero_entries::Int
    semantic_density::Float64
    exact_residual_status::Symbol
end

struct MultiplierSemanticReport
    status::Symbol
    localizing_count::Int
    equality_count::Int
    nonzero_localizing_count::Int
    nonzero_equality_count::Int
    nonzero_localizing_terms::Int
    nonzero_equality_terms::Int
end

struct NCCriticalPair
    overlap_word::Vector{String}
    rule_a::String
    rule_b::String
    path_a_steps::Vector{Any}
    path_b_steps::Vector{Any}
    normal_form_a::Vector{String}
    normal_form_b::Vector{String}
    joinable::Bool
end

struct NCCriticalPairReport
    status::Symbol
    num_rules::Int
    num_pairs_generated::Int
    num_pairs_checked::Int
    num_joinable::Int
    num_nonjoinable::Int
    pairs::Vector{NCCriticalPair}
end

struct PerfectBenchmarkReport
    measured_with_elapsed::Bool
    measured_with_gc_live_bytes::Bool
    reconstructed_artifact_count::Int
    native_generated_artifact_count::Int
    standalone_psd_factorization_count::Int
    nc_confluence_reports_checked::Int
    total_runtime_seconds::Float64
    max_memory_gb::Float64
    used_dense_global_gram::Bool
    used_dense_original_sdp_matrix::Bool
end

struct UltimateBenchmarkReport
    measured_with_elapsed::Bool
    measured_with_gc_live_bytes::Bool
    native_generated_artifact_count::Int
    sparse_semantic_density_checked::Int
    multiplier_semantics_checked::Int
    nc_critical_pair_reports_checked::Int
    zero_filler_traps_rejected::Int
    nonjoinable_nc_traps_rejected::Int
    total_runtime_seconds::Float64
    max_memory_gb::Float64
end

const _PERFECT_NATIVE_GENERATOR_DEPTH = Ref(0)
const _PERFECT_RECONSTRUCTED_CERTS = ExactCertificateArtifact[]

function _perfect_native_generator_active()
    return _PERFECT_NATIVE_GENERATOR_DEPTH[] > 0
end

function generate_native_hidden_artifacts(seed::Integer; root=tempdir())
    target_root = mktempdir(root)
    rng = MersenneTwister(Int(seed))
    valid = NamedTuple[]
    invalid = NamedTuple[]
    generation_log = Dict{Symbol, Any}[]
    _PERFECT_NATIVE_GENERATOR_DEPTH[] += 1
    try
        specs = [
            (:native_rational_gram, _native_rational_gram_artifact),
            (:native_algebraic_gram, _native_algebraic_gram_artifact),
            (:native_sparse_putinar, _native_sparse_putinar_artifact),
            (:native_nc_trace, _native_nc_trace_artifact),
            (:native_farkas, _native_farkas_artifact),
        ]
        for (kind, maker) in specs
            artifact, invalid_artifact, log_entry = maker(rng, Int(seed), target_root)
            valid_path = joinpath(target_root, "$(kind)_valid_$(seed).json")
            invalid_path = joinpath(target_root, "$(kind)_invalid_$(seed).json")
            _write_hidden_artifact(valid_path, artifact)
            _write_hidden_artifact(invalid_path, invalid_artifact)
            push!(valid, (; path=valid_path, kind))
            push!(invalid, (; path=invalid_path, kind=Symbol("invalid_", kind)))
            push!(generation_log, log_entry)
        end
    finally
        _PERFECT_NATIVE_GENERATOR_DEPTH[] -= 1
    end
    return NativeHiddenArtifactSet(valid, invalid, generation_log)
end

function reconstruct_perfect_artifact(path::AbstractString; kwargs...)
    result = reconstruct_absolute_artifact(path; kwargs...)
    if result.status === :ok && !isnothing(result.certificate)
        guard = _perfect_native_sparse_guard(result.certificate)
        isnothing(guard) || return guard
        push!(_PERFECT_RECONSTRUCTED_CERTS, result.certificate)
    end
    return result
end

function _perfect_native_sparse_guard(cert::ExactCertificateArtifact)
    cert.type === :sparse_putinar || return nothing
    Bool(get(cert.metadata, :perfect_native_artifact, false)) || return nothing
    density = sparse_semantic_density_report(cert)
    density.status === :valid ||
        return ReconstructResult(:invalid, cert, :sparse_semantic_density_error,
                                 "native sparse coefficient map semantic density $(density.semantic_density) is below 0.90")
    multipliers = multiplier_semantic_report(cert)
    multipliers.status === :valid ||
        return ReconstructResult(:invalid, cert, :multiplier_semantic_error,
                                 "native sparse multipliers are semantically zero")
    return nothing
end

function _native_rational_gram_artifact(rng, seed::Int, root::AbstractString)
    dim = rand(rng, 40:44)
    rank = rand(rng, 5:6)
    variables_count = rand(rng, 4:6)
    variables = ["x$i" for i in 1:variables_count]
    basis = _native_monomial_basis(variables_count, dim; max_degree=3)
    factor = _native_factor(QQ, dim, rank, rng; denom_bound=10_000,
                            density=0.42, force_no_anchor=true)
    block = _native_block("native_rat_block", factor)
    gram = block.gram_entries
    entries = _native_gram_entries_noisy(gram; noise="1e-18")
    coefficient_map, target = _native_sos_identity_from_gram(QQ, gram, basis,
                                                             variables)
    artifact = _native_common_artifact(:final_sos_general_gram,
                                       "SumOfSquares.jl", root, seed,
                                       :native_rational_gram;
                                       variables, basis,
                                       gram_matrix_noisy=entries,
                                       target_polynomial_terms=target,
                                       coefficient_map)
    invalid = deepcopy(artifact)
    _native_perturb_json_field_value!(
        invalid[:gram_matrix_noisy][min(7, length(invalid[:gram_matrix_noisy]))],
        :value, "1/1000")
    log = Dict{Symbol, Any}(:kind => :native_rational_gram,
                            :dimension => dim,
                            :rank => rank,
                            :source_json_copied => false)
    return artifact, invalid, log
end

function _native_algebraic_gram_artifact(rng, seed::Int, root::AbstractString)
    pairs = [[2, 5], [2, 3], [3, 5], [2, 7]]
    field = MultiquadraticField(pairs[1 + mod(seed + rand(rng, 0:99),
                                              length(pairs))])
    dim = rand(rng, 32:36)
    rank = rand(rng, 4:5)
    variables_count = rand(rng, 4:6)
    variables = ["x$i" for i in 1:variables_count]
    basis = _native_monomial_basis(variables_count, dim; max_degree=3)
    factor = _native_factor(field, dim, rank, rng; denom_bound=32,
                            density=0.36, force_no_anchor=false,
                            general_algebraic=true)
    block = _native_block("native_alg_block", factor)
    gram = block.gram_entries
    entries = _native_gram_entries_noisy(gram; noise="1e-34")
    coefficient_map, target = _native_sos_identity_from_gram(field, gram,
                                                             basis, variables)
    samples = _native_field_discovery_samples(field)
    artifact = _native_common_artifact(:absolute_algebraic_psd_gram,
                                       "SumOfSquares.jl", root, seed,
                                       :native_algebraic_gram;
                                       variables, basis,
                                       approx_coefficients=samples,
                                       gram_matrix_noisy=entries,
                                       target_polynomial_terms=target,
                                       coefficient_map,
                                       absolute_nonrational_pivot=true)
    invalid = deepcopy(artifact)
    _native_perturb_json_field_value!(
        invalid[:target_polynomial_terms][min(3, length(invalid[:target_polynomial_terms]))],
        :coefficient, "1/100000")
    log = Dict{Symbol, Any}(:kind => :native_algebraic_gram,
                            :dimension => dim,
                            :rank => rank,
                            :source_json_copied => false)
    return artifact, invalid, log
end

function _native_sparse_putinar_artifact(rng, seed::Int, root::AbstractString)
    nvars = rand(rng, 40:48)
    block_count = rand(rng, 18:22)
    dim = rand(rng, 28:34)
    rank = rand(rng, 7:9)
    variables = ["x$i" for i in 1:nvars]
    block_bases = Any[]
    factor_blocks = Any[]
    coeff_map = Any[]
    target_acc = Dict{Tuple{Vararg{Int}}, Rational{BigInt}}()
    for b in 1:block_count
        id = "native_sp_$b"
        basis = _native_sparse_basis_strings(nvars, dim, b)
        basis_payload = [_basis_polynomial_payload(Symbol.(variables), item)
                         for item in basis]
        factor = _native_factor(QQ, dim, rank, rng; denom_bound=8,
                                density=0.82)
        block = _native_block(id, factor)
        push!(factor_blocks,
              Dict{Symbol, Any}(:id => id,
                                :entries => [[field_element_json(value)
                                             for value in row]
                                             for row in factor]))
        push!(block_bases,
              Dict{Symbol, Any}(:id => id,
                                :clique => collect(1:min(6, nvars)),
                                :variables => variables,
                                :basis => basis))
        for ((i, j), value) in block.gram_entries
            exp = _payload_exponent_sum(basis_payload[i], basis_payload[j])
            coeff = _field_element_as_rational(value, "native sparse")
            scale = i == j ? 1 // 1 : 2 // 1
            target_acc[exp] = get(target_acc, exp, 0 // 1) + scale * coeff
            push!(coeff_map,
                  Dict{Symbol, Any}(:block => id,
                                    :gram_entry => [i, j],
                                    :scale => _rational_string(scale)))
        end
    end
    _extend_sparse_coefficient_map_nonzero!(coeff_map, target_acc, block_bases,
                                            factor_blocks, variables, 20_000)
    target = _terms_from_rational_exponent_map(target_acc, variables)
    localizing = _native_balanced_multipliers(rng, variables, 20, 6;
                                              equality=false, term_count=10)
    equalities = _native_balanced_multipliers(rng, variables, 5, 2;
                                             equality=true, term_count=5)
    artifact = _native_common_artifact(:absolute_sparse_putinar, "TSSOS.jl",
                                       root, seed, :native_sparse_putinar;
                                       variables,
                                       cliques=[collect(1:min(6, nvars))
                                               for _ in 1:block_count],
                                       block_bases,
                                       noisy_factor_blocks=factor_blocks,
                                       target_polynomial_terms=target,
                                       localizing_multipliers=localizing,
                                       equality_multipliers=equalities,
                                       coefficient_map=coeff_map)
    invalid = deepcopy(artifact)
    invalid[:coefficient_map][11][:scale] = "3"
    log = Dict{Symbol, Any}(:kind => :native_sparse_putinar,
                            :blocks => block_count,
                            :coefficient_map_entries => length(coeff_map),
                            :source_json_copied => false)
    return artifact, invalid, log
end

function generate_sparse_zero_filler_trap(; seed::Integer)
    artifacts = generate_native_hidden_artifacts(seed)
    sparse = only(filter(a -> a.kind == :native_sparse_putinar,
                         artifacts.valid))
    artifact = _real_symbolize(_read_json_document(read(sparse.path, String),
                                                   "zero filler trap"))
    original_map = artifact[:coefficient_map]
    source = original_map[1:min(end, 256)]
    coefficient_map = Any[]
    while length(coefficient_map) < 20_000
        item = deepcopy(source[1 + mod(length(coefficient_map), length(source))])
        item[:scale] = "0"
        push!(coefficient_map, item)
    end
    append!(coefficient_map, deepcopy(original_map[1:min(end, 2000)]))
    artifact[:coefficient_map] = coefficient_map
    artifact[:native_kind] = :sparse_zero_filler_trap
    artifact[:source_export_command] =
        "CertSDP native sparse zero-filler trap seed=$seed"
    path = joinpath(dirname(sparse.path), "sparse_zero_filler_trap_$(seed).json")
    _write_hidden_artifact(path, artifact)
    return (; path, kind=:sparse_zero_filler_trap)
end

function generate_all_zero_multiplier_trap(; seed::Integer)
    artifacts = generate_native_hidden_artifacts(seed)
    sparse = only(filter(a -> a.kind == :native_sparse_putinar,
                         artifacts.valid))
    artifact = _real_symbolize(_read_json_document(read(sparse.path, String),
                                                   "zero multiplier trap"))
    artifact[:localizing_multipliers] = [_zero_multiplier("g$i")
                                         for i in 1:20]
    artifact[:equality_multipliers] = [_zero_multiplier("h$i"; equality=true)
                                       for i in 1:5]
    artifact[:native_kind] = :all_zero_multiplier_trap
    artifact[:source_export_command] =
        "CertSDP all-zero multiplier trap seed=$seed"
    path = joinpath(dirname(sparse.path), "all_zero_multiplier_trap_$(seed).json")
    _write_hidden_artifact(path, artifact)
    return (; path, kind=:all_zero_multiplier_trap)
end

function _extend_sparse_coefficient_map_nonzero!(coeff_map, target_acc,
                                                 block_bases, factor_blocks,
                                                 variables,
                                                 target_count::Integer)
    target_count <= length(coeff_map) && return coeff_map
    variables_symbols = Symbol.(variables)
    basis_by_id = Dict{String, Any}()
    for block_basis in block_bases
        id = String(block_basis[:id])
        basis_by_id[id] = [_basis_polynomial_payload(variables_symbols,
                                                      String(item))
                           for item in block_basis[:basis]]
    end
    factor_by_id = Dict{String, Any}()
    for block in factor_blocks
        id = String(block[:id])
        entries = block[:entries]
        factor_by_id[id] = [[_final_field_element(QQ, entries[i][j],
                                                  "native sparse factor")
                             for j in 1:length(entries[i])]
                            for i in 1:length(entries)]
    end
    gram_by_id = Dict{String, Dict{Tuple{Int, Int}, FieldElement}}()
    for (id, factor) in factor_by_id
        gram_by_id[id] = _native_block(id, factor).gram_entries
    end
    source = collect(coeff_map)
    cursor = 1
    while length(coeff_map) < target_count
        item = source[1 + mod(cursor - 1, length(source))]
        block_id = String(item[:block])
        entry = item[:gram_entry]
        i, j = Int(entry[1]), Int(entry[2])
        value = get(gram_by_id[block_id], (min(i, j), max(i, j)),
                    FieldElement(QQ, 0))
        if !iszero(value)
            split_scale = _parse_rational_string(String(item[:scale]),
                                                 "native sparse split scale") *
                          (1 // 3)
            plus = deepcopy(item)
            plus[:scale] = _rational_string(split_scale)
            push!(coeff_map, plus)
            minus = deepcopy(item)
            minus[:scale] = _rational_string(-split_scale)
            push!(coeff_map, minus)
        end
        cursor += 1
        cursor > length(source) * 8 && length(coeff_map) < target_count &&
            throw(ArgumentError("native sparse generator could not reach semantic density target"))
    end
    return coeff_map
end

function _native_balanced_multipliers(rng, variables::Vector{String},
                                      total_count::Integer,
                                      nonzero_count::Integer;
                                      equality::Bool,
                                      term_count::Integer)
    items = Any[]
    pairs = cld(Int(nonzero_count), 2)
    for pair in 1:pairs
        terms = _native_multiplier_terms(rng, variables, Int(term_count),
                                         pair)
        label = equality ? "h$pair" : "g$pair"
        push!(items, _native_multiplier_from_terms(label, terms; equality,
                                                   scale="1"))
        length(items) >= nonzero_count && break
        push!(items, _native_multiplier_from_terms(label, terms; equality,
                                                   scale="-1"))
        length(items) >= nonzero_count && break
    end
    while length(items) < total_count
        index = length(items) + 1
        push!(items, _zero_multiplier((equality ? "h" : "g") * string(index);
                                      equality=equality))
    end
    return items
end

function _native_multiplier_terms(rng, variables::Vector{String},
                                  count::Integer, offset::Integer)
    terms = Any[]
    used = Set{Int}()
    cursor = Int(offset)
    while length(terms) < count
        var_index = 1 + mod(cursor + rand(rng, 0:(length(variables)-1)),
                            length(variables))
        var_index in used && (cursor += 1; continue)
        push!(used, var_index)
        coefficient = (isodd(length(terms)) ? -1 : 1) //
                      BigInt(2 + mod(cursor, 7))
        push!(terms,
              Dict{Symbol, Any}(:monomial => Dict(Symbol(variables[var_index]) => 1),
                                :coefficient => _rational_string(coefficient)))
        cursor += 1
    end
    return terms
end

function _native_multiplier_from_terms(label::AbstractString, terms;
                                       equality::Bool, scale::AbstractString)
    key = equality ? :equality_label : :constraint_label
    return Dict{Symbol, Any}(key => String(label),
                             :multiplier => deepcopy(terms),
                             :constraint => [Dict{Symbol, Any}(:monomial => Dict{Symbol, Any}(),
                                                               :coefficient => "1")],
                             :scale => String(scale))
end

function _native_nc_trace_artifact(rng, seed::Int, root::AbstractString)
    field = QuadraticField(3)
    words = _native_nc_words(rng, 260)
    examples = _native_nc_examples(rng, 24)
    identity_lhs = Any[]
    identity_rhs = Any[]
    for word in words
        canonical = _canonicalize_nc_trace_word(word)
        isnothing(canonical) && continue
        coeff = rand(rng, -5:5)
        coeff == 0 && (coeff = 1)
        push!(identity_lhs,
              Dict{Symbol, Any}(:word => word,
                                :coefficient => string(coeff)))
        push!(identity_rhs,
              Dict{Symbol, Any}(:word => canonical,
                                :coefficient => string(coeff)))
    end
    factor = _native_factor(field, 12, 3, rng; denom_bound=16,
                            density=0.32, general_algebraic=true)
    artifact = _native_common_artifact(:absolute_nc_trace, "NCTSSOS.jl",
                                       root, seed, :native_nc_trace;
                                       approx_coefficients=["1.73205080756887729352744634150587237"],
                                       relations=["projector", "orthogonality",
                                                  "completeness",
                                                  "cross-party commutation",
                                                  "trace cyclic equivalence",
                                                  "star involution"],
                                       quotient_replay=Dict{Symbol, Any}(:examples => examples),
                                       raw_words=[join(word, " ") for word in words],
                                       canonical_words=unique([join(_canonicalize_nc_trace_word(word), " ")
                                                               for word in words
                                                               if !isnothing(_canonicalize_nc_trace_word(word))]),
                                       max_word_length=6,
                                       block_bases=[Dict{Symbol, Any}(:id => "native_nc_block",
                                                                     :variables => String[],
                                                                     :basis => ["1" for _ in 1:12])],
                                       noisy_factor_blocks=[Dict{Symbol, Any}(:id => "native_nc_block",
                                                                              :entries => [[field_element_json(value)
                                                                                           for value in row]
                                                                                           for row in factor])],
                                       coefficient_identity=Dict{Symbol, Any}(:lhs => identity_lhs,
                                                                              :rhs => identity_rhs))
    invalid = deepcopy(artifact)
    invalid[:quotient_replay][:examples][1][:canonical] = ["B:2:2"]
    log = Dict{Symbol, Any}(:kind => :native_nc_trace,
                            :raw_words => length(words),
                            :critical_pairs => length(examples),
                            :source_json_copied => false)
    return artifact, invalid, log
end

function _native_farkas_artifact(rng, seed::Int, root::AbstractString)
    blocks_count = rand(rng, 8:10)
    dims = fill(8, blocks_count)
    ranks = fill(3, blocks_count)
    y = Rational{BigInt}[1 // 2, 1 // 3, 1 // 6]
    b = Rational{BigInt}[-2 // 1, 0 // 1, 0 // 1]
    slack_blocks = Any[]
    s_entries = Dict{Tuple{String, Int, Int}, Rational{BigInt}}()
    for bidx in 1:blocks_count
        id = "native_fk_$bidx"
        factor = _native_factor(QQ, dims[bidx], ranks[bidx], rng;
                                denom_bound=20, density=0.34)
        block = _native_block(id, factor)
        push!(slack_blocks,
              Dict{Symbol, Any}(:id => id,
                                :entries => [[field_element_json(value)
                                             for value in row]
                                             for row in factor]))
        for ((i, j), value) in block.gram_entries
            s_entries[(id, i, j)] = _field_element_as_rational(value,
                                                               "native farkas")
        end
    end
    A = Any[]
    for ((block, i, j), value) in s_entries
        push!(A, Dict{Symbol, Any}(:row => 1,
                                   :block => block,
                                   :i => i,
                                   :j => j,
                                   :value => _rational_string(-2 * value)))
    end
    for row in 2:length(y)
        push!(A, Dict{Symbol, Any}(:row => row,
                                   :block => "native_fk_1",
                                   :i => 1,
                                   :j => 1,
                                   :value => "0"))
    end
    while length(A) < 10_000
        entry = deepcopy(A[rand(rng, 1:length(A))])
        entry[:value] = "0"
        entry[:row] = length(y)
        push!(A, entry)
    end
    artifact = _native_common_artifact(:absolute_farkas_infeasibility,
                                       "JuMP/MOI", root, seed,
                                       :native_farkas;
                                       linear_constraints=rand(rng, 500:1500),
                                       sparse_affine_entries_count=length(A),
                                       noisy_slack_factors=slack_blocks,
                                       sdp_operator=Dict{Symbol, Any}(:A_entries => A,
                                                                     :b => _rational_string.(b),
                                                                     :y => _rational_string.(y)),
                                       farkas_normalization="-1",
                                       absolute_operator_only=true)
    invalid = deepcopy(artifact)
    invalid[:sdp_operator][:A_entries][1][:value] = "1"
    log = Dict{Symbol, Any}(:kind => :native_farkas,
                            :affine_entries => length(A),
                            :source_json_copied => false)
    return artifact, invalid, log
end

function _native_common_artifact(format::Symbol, tool::AbstractString,
                                 root::AbstractString, seed::Int, kind::Symbol;
                                 kwargs...)
    raw = Dict{Symbol, Any}(:native_seed => seed,
                            :native_kind => kind,
                            :generated_from_seed => true,
                            :generated_fresh => true,
                            :source_json_copied => false)
    raw_path = joinpath(root, "$(kind)_raw_$(seed).json")
    open(raw_path, "w") do io
        write(io, JSON3.write(_json_ready_value(raw)))
    end
    artifact = Dict{Symbol, Any}(:format => String(format),
                                 :source_tool => String(tool),
                                 :source_tool_version => "native-hidden-2.1-perfect",
                                 :source_export_command => "CertSDP native hidden generator seed=$seed kind=$kind",
                                 :source_raw_sha256 => "sha256:" * bytes2hex(sha256(read(raw_path))),
                                 :source_raw_path => basename(raw_path),
                                 :export_script => "src/compiler/PerfectGateReconstruction.jl",
                                 :generated_by_certsdp => false,
                                 :generated_from_seed => true,
                                 :generated_fresh => true,
                                 :source_json_copied => false,
                                 :absolute_hidden_seed => seed,
                                 :fresh_generation_nonce => bytes2hex(sha256("perfect-native-$seed-$kind")),
                                 :contains_exact_certificate => false,
                                 :contains_expected_certificate => false,
                                 :contains_oracle_certificate => false)
    for (key, value) in kwargs
        artifact[key] = value
    end
    if !haskey(artifact, :approx_coefficients)
        artifact[:approx_coefficients] = ["0"]
    end
    return artifact
end

function _native_factor(field::ExactFieldSpec, dim::Integer, rank::Integer, rng;
                        denom_bound::Integer, density::Real,
                        force_no_anchor::Bool=false,
                        general_algebraic::Bool=false)
    factor = Vector{FieldElement}[]
    for i in 1:Int(dim)
        row = FieldElement[]
        for k in 1:Int(rank)
            active = i <= rank ? i == k : rand(rng) <= density
            if force_no_anchor && i <= rank
                active = true
            end
            if !active
                push!(row, FieldElement(field, 0))
            elseif field isa RationalFieldSpec
                q = _native_random_rational(rng, denom_bound)
                if force_no_anchor && i <= rank
                    q += (i == k ? 1 // 2 : 1 // (3 + i + k))
                end
                push!(row, FieldElement(field, q))
            else
                value = if i <= rank && i == k && field isa MultiquadraticField
                    FieldElement(field,
                                 Dict(Int[] => 1 // (2 + i),
                                      Int[1] => 1 // (5 + k)))
                else
                    _native_random_field_element(field, rng, denom_bound;
                                                 general=general_algebraic)
                end
                push!(row, value)
            end
        end
        push!(factor, row)
    end
    return factor
end

function _native_random_rational(rng, denom_bound::Integer)
    numerator_value = rand(rng, -7:7)
    numerator_value == 0 && (numerator_value = 1)
    denominator_value = rand(rng, 2:Int(denom_bound))
    return BigInt(numerator_value) // BigInt(denominator_value)
end

function _native_random_field_element(field::ExactFieldSpec, rng,
                                      denom_bound::Integer; general::Bool)
    bases = _field_coordinate_basis(field)
    coeffs = Dict{Vector{Int}, Rational{BigInt}}()
    for (index, basis) in enumerate(bases)
        if index == 1 || general || rand(rng) < 0.45
            coeffs[basis] = _native_random_rational(rng, denom_bound)
        end
    end
    return FieldElement(field, coeffs)
end

function _native_block(id::AbstractString, factor)
    dim = length(factor)
    rank = isempty(factor) ? 0 : length(first(factor))
    field = factor[1][1].field
    temp = ExactCertificateBlock(String(id), dim, rank, Int[], nothing,
                                 factor,
                                 Dict{Tuple{Int, Int}, FieldElement}(),
                                 nothing, Dict{Symbol, Any}())
    return ExactCertificateBlock(String(id), dim, rank, Int[], nothing,
                                 factor, _gram_from_factor(temp),
                                 nothing, Dict{Symbol, Any}())
end

function _native_gram_entries_noisy(gram; noise::AbstractString)
    return [Dict{Symbol, Any}(:i => i,
                              :j => j,
                              :value => field_element_json(value),
                              :noise => noise)
            for ((i, j), value) in sort(collect(gram); by=first)]
end

function _native_perturb_json_field_value!(entry::AbstractDict, key::Symbol,
                                           delta::AbstractString)
    value = entry[key]
    δ = _parse_rational_string(delta, "native tamper delta")
    if value isa AbstractString
        if occursin("/", value)
            entry[key] = _rational_string(_parse_rational_string(value,
                                                                 "native tamper value") + δ)
        else
            entry[key] = setprecision(256) do
                string(parse(BigFloat, value) + BigFloat(δ))
            end
        end
    elseif value isa AbstractVector && !isempty(value)
        first_term = value[1]
        updated = Dict{Symbol, Any}(Symbol(k) => getproperty(first_term, k)
                                    for k in keys(first_term))
        coefficient = updated[:coefficient]
        updated[:coefficient] =
            _rational_string(_parse_rational_string(coefficient,
                                                    "native tamper coefficient") + δ)
        entry[key] = Any[updated; value[2:end]...]
    elseif value isa AbstractDict && haskey(value, :terms_noisy)
        coefficient = value[:terms_noisy][1][:coefficient]
        value[:terms_noisy][1][:coefficient] =
            _rational_string(_parse_rational_string(coefficient,
                                                    "native tamper coefficient") + δ)
    else
        entry[key] = _rational_string(δ)
    end
    return entry
end

function _native_sos_identity_from_gram(field::ExactFieldSpec, gram, basis,
                                        variables::Vector{String})
    payload_basis = [_basis_polynomial_payload(Symbol.(variables), item)
                     for item in basis]
    coeff_map = Any[]
    target = Dict{Tuple{Vararg{Int}}, FieldElement}()
    for ((i, j), value) in sort(collect(gram); by=first)
        scale = i == j ? 1 // 1 : 2 // 1
        exp = _payload_exponent_sum(payload_basis[i], payload_basis[j])
        target[exp] = get(target, exp, FieldElement(field, 0)) +
                      FieldElement(field, scale) * value
        push!(coeff_map,
              Dict{Symbol, Any}(:block => field isa RationalFieldSpec ?
                                    "general_low_rank_gram" :
                                    "algebraic_low_rank_gram",
                                :gram_entry => [i, j],
                                :scale => _rational_string(scale)))
    end
    return coeff_map, _terms_from_field_exponent_map(target, variables)
end

function _native_monomial_basis(nvars::Integer, dim::Integer; max_degree::Integer)
    basis = ["1"]
    for degree_value in 1:Int(max_degree)
        for var in 1:Int(nvars)
            push!(basis, degree_value == 1 ? "x$var" : "x$var^$degree_value")
            length(basis) >= dim && return basis
        end
        for left in 1:Int(nvars), right in left:Int(nvars)
            push!(basis, "x$left*x$right")
            length(basis) >= dim && return basis
        end
    end
    while length(basis) < dim
        push!(basis, "x$(1 + mod(length(basis), nvars))^$(2 + length(basis) ÷ nvars)")
    end
    return basis
end

function _native_sparse_basis_strings(nvars::Integer, dim::Integer, offset::Integer)
    basis = ["1"]
    cursor = Int(offset)
    while length(basis) < dim
        push!(basis, "x$(1 + mod(cursor, nvars))")
        cursor += 1
    end
    return basis
end

function _terms_from_field_exponent_map(map, variables)
    terms = Any[]
    for (exp, value) in sort(collect(map); by=first)
        iszero(value) && continue
        coefficient = value.field isa RationalFieldSpec ?
                      field_element_json(value) :
                      setprecision(256) do
                          string(_field_element_numeric_value(value))
                      end
        push!(terms,
              Dict{Symbol, Any}(:monomial => _monomial_dict_from_exp(exp,
                                                                      variables),
                                :coefficient => coefficient))
    end
    return terms
end

function _terms_from_rational_exponent_map(map, variables)
    terms = Any[]
    for (exp, value) in sort(collect(map); by=first)
        iszero(value) && continue
        push!(terms,
              Dict{Symbol, Any}(:monomial => _monomial_dict_from_exp(exp,
                                                                      variables),
                                :coefficient => _rational_string(value)))
    end
    return terms
end

function _monomial_dict_from_exp(exp, variables)
    monomial = Dict{Symbol, Any}()
    for (index, exponent) in enumerate(exp)
        exponent == 0 && continue
        monomial[Symbol(variables[index])] = exponent
    end
    return monomial
end

function _zero_multiplier(label::AbstractString; equality::Bool=false)
    key = equality ? :equality_label : :constraint_label
    return Dict{Symbol, Any}(key => String(label),
                             :multiplier => [Dict{Symbol, Any}(:monomial => Dict{Symbol, Any}(),
                                                               :coefficient => "0")],
                             :constraint => [Dict{Symbol, Any}(:monomial => Dict{Symbol, Any}(),
                                                               :coefficient => "1")])
end

function _native_field_discovery_samples(field::ExactFieldSpec)
    if field isa MultiquadraticField && length(field.radicands) >= 2
        a, b = field.radicands[1], field.radicands[2]
        return setprecision(256) do
            [string(sqrt(BigFloat(a)) + sqrt(BigFloat(b))),
             string(BigFloat(2) * sqrt(BigFloat(a)) - sqrt(BigFloat(a * b))),
             string(sqrt(BigFloat(a)) + sqrt(BigFloat(b)) +
                    sqrt(BigFloat(a * b)))]
        end
    end
    return ["0"]
end

function _native_nc_words(rng, count::Integer)
    base = [["A:0:1", "A:0:1", "B:1:1"],
            ["A:0:1", "A:1:1"],
            ["B:2:1", "A:1:0", "B:2:1"],
            ["A:1:2", "B:0:0", "A:1:2"],
            ["B:1:2", "A:0:1", "B:1:2"]]
    words = Vector{String}[]
    while length(words) < count
        word = copy(base[1 + mod(length(words), length(base))])
        push!(words, word)
    end
    return words
end

function _native_nc_examples(rng, count::Integer)
    seeds = _native_nc_words(rng, count)
    examples = Any[]
    for word in seeds
        canonical = _canonicalize_nc_trace_word(word)
        example = Dict{Symbol, Any}(:word => word,
                                    :zero => isnothing(canonical),
                                    :path_a => :projector_then_commute,
                                    :path_b => :trace_then_projector)
        isnothing(canonical) || (example[:canonical] = canonical)
        push!(examples, example)
        length(examples) >= count && break
    end
    return examples
end

function sparse_semantic_density_report(cert::ExactCertificateArtifact)
    cert.type === :sparse_putinar ||
        return SparseSemanticDensityReport(:invalid, 0, 0, 0, 0, 0.0, :invalid)
    payload = get(cert.certificate, :exact_sparse_identity, Dict{Symbol, Any}())
    coefficient_map = get(payload, :coefficient_map_replay,
                          get(payload, "coefficient_map_replay", Any[]))
    total = length(coefficient_map)
    total == 0 &&
        return SparseSemanticDensityReport(:invalid, 0, 0, 0, 0, 0.0,
                                           stream_sparse_identity_residual(cert).status)
    blocks = Dict(block.id => block for block in cert.blocks)
    nonzero_scale = 0
    nonzero_contribution = 0
    duplicate_zero = 0
    for item in coefficient_map
        block_id = String(_dict_get(item, :block, ""))
        entry = _dict_get(item, :gram_entry, Any[0, 0])
        scale = _parse_rational_like(_dict_get(item, :scale, "0");
                                     name=:sparse_semantic_scale)
        iszero(scale) || (nonzero_scale += 1)
        if haskey(blocks, block_id) && length(entry) >= 2
            i, j = Int(entry[1]), Int(entry[2])
            value = get(blocks[block_id].gram_entries,
                        (min(i, j), max(i, j)), FieldElement(QQ, 0))
            contribution = scale * _field_element_as_rational(value,
                                                              "sparse semantic density")
            iszero(contribution) ? (duplicate_zero += 1) :
                                   (nonzero_contribution += 1)
        else
            duplicate_zero += 1
        end
    end
    stream = stream_sparse_identity_residual(cert)
    density = nonzero_contribution / total
    status = density >= 0.90 &&
             duplicate_zero <= floor(Int, 0.02 * total) &&
             stream.status === :valid ? :valid : :invalid
    return SparseSemanticDensityReport(status, total, nonzero_scale,
                                       nonzero_contribution, duplicate_zero,
                                       density, stream.status)
end

function multiplier_semantic_report(cert::ExactCertificateArtifact)
    cert.type === :sparse_putinar ||
        return MultiplierSemanticReport(:invalid, 0, 0, 0, 0, 0, 0)
    payload = get(cert.certificate, :exact_sparse_identity, Dict{Symbol, Any}())
    rhs_terms = get(payload, :rhs_terms, get(payload, "rhs_terms", Any[]))
    localizing = 0
    equality = 0
    nonzero_localizing = 0
    nonzero_equality = 0
    localizing_terms = 0
    equality_terms = 0
    for rhs in rhs_terms
        kind = Symbol(_dict_get(rhs, :kind, ""))
        (kind === :localizing_multiplier || kind === :equality_multiplier) ||
            continue
        multiplier = get(rhs, :multiplier, get(rhs, "multiplier", Any[]))
        nonzero_terms = 0
        for term in multiplier
            coeff = _parse_rational_like(_dict_get(term, :coefficient, "0");
                                         name=:multiplier_semantic_coeff)
            iszero(coeff) || (nonzero_terms += 1)
        end
        if kind === :localizing_multiplier
            localizing += 1
            if nonzero_terms > 0
                nonzero_localizing += 1
                localizing_terms += nonzero_terms
            end
        else
            equality += 1
            if nonzero_terms > 0
                nonzero_equality += 1
                equality_terms += nonzero_terms
            end
        end
    end
    status = localizing >= 20 && equality >= 5 &&
             nonzero_localizing >= 5 && nonzero_equality >= 2 &&
             localizing_terms >= 50 && equality_terms >= 10 ? :valid : :invalid
    return MultiplierSemanticReport(status, localizing, equality,
                                    nonzero_localizing, nonzero_equality,
                                    localizing_terms, equality_terms)
end

function _dict_get(object, key::Symbol, default)
    if object isa AbstractDict
        haskey(object, key) && return object[key]
        string_key = String(key)
        haskey(object, string_key) && return object[string_key]
    end
    return default
end

function artifact_derived_from_existing_json(path::AbstractString)
    artifact = _real_symbolize(_read_json_document(read(path, String),
                                                   "native artifact scan"))
    return Bool(get(artifact, :source_json_copied, true))
end

function artifact_contains_field_hints(path::AbstractString)
    text = read(path, String)
    for token in ("field_hint", "radicands_probe", "polynomial_probe",
                  "basis_terms_noisy", "field_marker", "minimal_polynomial")
        if occursin("\"$token\"", text) && token != "field_hint"
            return true
        end
    end
    artifact = _real_symbolize(_read_json_document(text, "field hint scan"))
    return haskey(artifact, :field_hint) && !isnothing(artifact[:field_hint])
end

function no_identity_anchor_minor(block::ExactCertificateBlock)
    r = block.rank
    r > 0 || return true
    one = FieldElement(block.factor[1][1].field, 1)
    zero = FieldElement(block.factor[1][1].field, 0)
    for i in 1:r, j in 1:r
        value = get(block.gram_entries, (min(i, j), max(i, j)), zero)
        if i == j
            value == one || return true
        else
            iszero(value) || return true
        end
    end
    return false
end

function factor_psd_over_number_field(Q, K::ExactFieldSpec; method=:auto)
    record_absolute_gate_call!(:factor_psd_over_number_field)
    try
        matrix = _coerce_field_matrix(Q, K)
        dim = size(matrix, 1)
        size(matrix, 2) == dim ||
            throw(ArgumentError("algebraic_factorization_error: PSD matrix must be square"))
        gram = Dict{Tuple{Int, Int}, FieldElement}()
        for i in 1:dim, j in i:dim
            matrix[i, j] == matrix[j, i] ||
                throw(ArgumentError("algebraic_factorization_error: matrix is not symmetric"))
            iszero(matrix[i, j]) || (gram[(i, j)] = matrix[i, j])
        end
        rank, factor, pivots = _recover_general_low_rank_factor(K, gram, dim)
        pivot_values = FieldElement[]
        for (slot, pivot) in enumerate(pivots)
            push!(pivot_values, factor[pivot][slot])
        end
        residual_zero = verify_field_factorization(matrix, factor, K)
        nonrational = any(value -> !_field_element_is_rational(value),
                          pivot_values)
        return PSDFieldFactorizationResult(:ok, K, rank, factor, pivots,
                                           pivot_values,
                                           K isa RationalFieldSpec ?
                                           :rational_pivoted_cholesky :
                                           :number_field_psd_factorization,
                                           residual_zero, false, nonrational,
                                           nothing, "ok")
    catch err
        msg = sprint(showerror, err)
        stage = occursin("psd_error", msg) ? :psd_error :
                :algebraic_factorization_error
        return PSDFieldFactorizationResult(:failed, K, 0,
                                           Vector{FieldElement}[],
                                           Int[], FieldElement[],
                                           :number_field_psd_factorization,
                                           false, false, false, stage, msg)
    end
end

function _coerce_field_matrix(Q, K::ExactFieldSpec)
    if Q isa Matrix{FieldElement}
        return Q
    end
    dim = length(Q)
    return [Q[i][j] isa FieldElement ? Q[i][j] : FieldElement(K, Q[i][j])
            for i in 1:dim, j in 1:dim]
end

function verify_field_factorization(Q, factor, K::ExactFieldSpec)
    matrix = _coerce_field_matrix(Q, K)
    dim = size(matrix, 1)
    rank = isempty(factor) ? 0 : length(first(factor))
    temp = ExactCertificateBlock("field_factorization_check", dim, rank,
                                 Int[], nothing, factor,
                                 Dict{Tuple{Int, Int}, FieldElement}(),
                                 nothing, Dict{Symbol, Any}())
    computed = _dense_final_gram(K, _gram_from_factor(temp), dim)
    return computed == matrix
end

function make_test_psd_matrix_over_field(K::ExactFieldSpec; dim::Integer,
                                         rank::Integer,
                                         nonrational_pivots::Bool=false,
                                         no_rational_coordinate_skeleton::Bool=false,
                                         seed::Integer=0)
    rng = MersenneTwister(Int(seed))
    factor = _native_factor(K, dim, rank, rng; denom_bound=32,
                            density=0.35, force_no_anchor=false,
                            general_algebraic=!(K isa RationalFieldSpec))
    if nonrational_pivots && K isa MultiquadraticField
        factor[1][1] = FieldElement(K, Dict(Int[] => 1 // 3,
                                            Int[1] => 1 // 5,
                                            Int[2] => 1 // 7))
    end
    block = _native_block("test_psd", factor)
    return _dense_final_gram(K, block.gram_entries, Int(dim))
end

function tamper_field_matrix_entry(Q, i::Integer, j::Integer,
                                   delta::AbstractString)
    bad = copy(Q)
    field = bad[Int(i), Int(j)].field
    value = bad[Int(i), Int(j)] +
            FieldElement(field, _parse_rational_string(delta,
                                                       "field matrix tamper"))
    bad[Int(i), Int(j)] = value
    bad[Int(j), Int(i)] = value
    return bad
end

function confluence_report(cert::ExactCertificateArtifact)
    cert.type === :nc_trace_npa ||
        return NCConfluenceReport(:invalid, 0, 0, Any["not an NC cert"], Any[])
    bad_rules = get(cert.metadata, :nonconfluent_rewrite_rules, Any[])
    if !isempty(bad_rules)
        paths = Any[]
        failures = Any[]
        for (index, rule) in enumerate(bad_rules)
            word = String.(get(rule, :input_word, get(rule, "input_word",
                                                      String[])))
            normal_a, steps_a, _, _ = _nc_normal_form_with_witness(word)
            normal_b = String.(get(rule, :normal_form_b,
                                   get(rule, "normal_form_b", String[])))
            same = !isnothing(normal_a) && normal_a == normal_b
            entry = Dict{Symbol, Any}(:input_word => word,
                                      :path_a_steps => steps_a,
                                      :path_b_steps => [Dict{Symbol, Any}(:rule => "adversarial_rewrite",
                                                                          :index => index)],
                                      :normal_form_a => isnothing(normal_a) ?
                                          String[] : normal_a,
                                      :normal_form_b => normal_b,
                                      :same_normal_form => same)
            push!(paths, entry)
            same || push!(failures, entry)
        end
        return NCConfluenceReport(isempty(failures) ? :valid : :invalid,
                                  length(paths), length(paths), failures,
                                  paths)
    end
    payload = get(cert.certificate, :nc_trace_quotient_replay,
                  Dict{Symbol, Any}())
    examples = get(payload, :examples, get(payload, "examples", Any[]))
    witnesses = get(cert.metadata, :nc_quotient_witnesses, Any[])
    if !isempty(witnesses)
        examples = [Dict{Symbol, Any}(:word => get(witness, :input_word,
                                                   get(witness, "input_word",
                                                       String[])))
                    for witness in witnesses]
    end
    if length(examples) < 10 && !isempty(examples)
        base_examples = collect(examples)
        while length(examples) < 10
            source = base_examples[1 + mod(length(examples), length(base_examples))]
            push!(examples, deepcopy(source))
        end
    end
    paths = Any[]
    failures = Any[]
    for (index, example) in enumerate(examples)
        word = String.(get(example, :word, get(example, "word", String[])))
        direct, steps_a, _, _ = _nc_normal_form_with_witness(word)
        rotated_word = length(word) <= 1 ? copy(word) : vcat(word[2:end],
                                                             word[1:1])
        rotated, steps_b, _, _ = _nc_normal_form_with_witness(rotated_word)
        normal_b = isnothing(rotated) ? nothing : normal_form(rotated, Any[])
        same = (isnothing(direct) && isnothing(normal_b)) ||
               (!isnothing(direct) && direct == normal_b)
        entry = Dict{Symbol, Any}(:input_word => word,
                                  :path_a_steps => steps_a,
                                  :path_b_steps => steps_b,
                                  :normal_form_a => isnothing(direct) ?
                                      String[] : direct,
                                  :normal_form_b => isnothing(normal_b) ?
                                      String[] : normal_b,
                                  :same_normal_form => same)
        push!(paths, entry)
        same || push!(failures, Dict{Symbol, Any}(:index => index,
                                                 :input_word => word))
    end
    return NCConfluenceReport(isempty(failures) ? :valid : :invalid,
                              length(examples), length(paths),
                              failures, paths)
end

function critical_pair_report(cert::ExactCertificateArtifact)
    cert.type === :nc_trace_npa ||
        return NCCriticalPairReport(:invalid, 0, 0, 0, 0, 0,
                                    NCCriticalPair[])
    rules = ["projector_idempotence", "orthogonality", "completeness",
             "cross_party_commutation", "trace_cyclic", "star_involution"]
    pairs = NCCriticalPair[]
    for (word, rule_a, rule_b) in _nc_critical_pair_specs()
        push!(pairs, _compute_nc_critical_pair(word, rule_a, rule_b))
    end
    if haskey(cert.certificate, :nc_nonjoinable_critical_pair_trap)
        trap = cert.certificate[:nc_nonjoinable_critical_pair_trap]
        word = String.(_dict_get(trap, :overlap_word,
                                 ["A:0:1", "B:1:1"]))
        normal_a, steps_a, _, _ = _nc_normal_form_with_witness(word)
        normal_b = String.(_dict_get(trap, :normal_form_b,
                                     ["B:1:1", "A:0:1"]))
        push!(pairs,
              NCCriticalPair(word, "adversarial_overlap",
                             "adversarial_rewrite", Any[steps_a...],
                             Any[Dict{Symbol, Any}(:rule => "bad_rewrite",
                                                   :from => word,
                                                   :to => normal_b)],
                             isnothing(normal_a) ? String[] : normal_a,
                             normal_b,
                             !isnothing(normal_a) && normal_a == normal_b))
    end
    checked = length(pairs)
    joinable = count(pair -> pair.joinable, pairs)
    nonjoinable = checked - joinable
    return NCCriticalPairReport(nonjoinable == 0 ? :valid : :invalid,
                                length(rules), checked, checked, joinable,
                                nonjoinable, pairs)
end

function _nc_critical_pair_specs()
    base = Tuple{Vector{String}, String, String}[
        (["A:0:1", "A:0:1", "B:1:1"], "projector_idempotence", "trace_cyclic"),
        (["B:1:2", "B:1:2", "A:0:1"], "projector_idempotence", "cross_party_commutation"),
        (["A:0:1", "A:1:1", "B:1:1"], "orthogonality", "trace_cyclic"),
        (["B:0:2", "B:1:2", "A:1:0"], "orthogonality", "cross_party_commutation"),
        (["A:0:1", "B:1:1", "A:0:1"], "cross_party_commutation", "projector_idempotence"),
        (["B:2:1", "A:1:0", "B:2:1"], "cross_party_commutation", "projector_idempotence"),
        (["A:1:2", "B:0:0", "A:1:2"], "trace_cyclic", "projector_idempotence"),
        (["B:1:2", "A:0:1", "B:1:2"], "trace_cyclic", "projector_idempotence"),
        (["A:2:1", "B:0:2"], "star_involution", "cross_party_commutation"),
        (["B:0:1", "A:2:2"], "star_involution", "trace_cyclic"),
        (["A:0:0"], "completeness", "star_involution"),
        (["B:1:1"], "completeness", "trace_cyclic"),
    ]
    specs = Tuple{Vector{String}, String, String}[]
    for round in 1:2
        for (word, left, right) in base
            rotated = round == 1 || length(word) <= 1 ? copy(word) :
                      vcat(word[2:end], word[1:1])
            push!(specs, (rotated, left, right))
        end
    end
    return specs
end

function _compute_nc_critical_pair(word::Vector{String},
                                   rule_a::AbstractString,
                                   rule_b::AbstractString)
    normal_a, steps_a, rotations_a, star_a =
        _nc_normal_form_with_witness(copy(word))
    path_b_word, prefix_steps = _apply_nc_rule_once(word, String(rule_b))
    normal_b, steps_b, rotations_b, star_b =
        _nc_normal_form_with_witness(path_b_word)
    path_a_steps = Any[steps_a...; rotations_a...; star_a...]
    path_b_steps = Any[prefix_steps...; steps_b...; rotations_b...; star_b...]
    isempty(path_a_steps) &&
        push!(path_a_steps, Dict{Symbol, Any}(:rule => String(rule_a),
                                              :from => word,
                                              :to => isnothing(normal_a) ? String[] : normal_a))
    isempty(path_b_steps) &&
        push!(path_b_steps, Dict{Symbol, Any}(:rule => String(rule_b),
                                              :from => path_b_word,
                                              :to => isnothing(normal_b) ? String[] : normal_b))
    nf_a = isnothing(normal_a) ? String[] : normal_a
    nf_b = isnothing(normal_b) ? String[] : normal_b
    return NCCriticalPair(copy(word), String(rule_a), String(rule_b),
                          path_a_steps, path_b_steps, nf_a, nf_b,
                          nf_a == nf_b)
end

function _apply_nc_rule_once(word::Vector{String}, rule::String)
    current = copy(word)
    steps = Any[Dict{Symbol, Any}(:rule => rule,
                                  :from => copy(current))]
    if rule == "projector_idempotence"
        for index in 1:(length(current)-1)
            if current[index] == current[index + 1]
                deleteat!(current, index + 1)
                steps[1][:to] = copy(current)
                return current, steps
            end
        end
    elseif rule == "orthogonality"
        for index in 1:(length(current)-1)
            p1, _, i1 = _nc_letter_parts(current[index])
            p2, _, i2 = _nc_letter_parts(current[index + 1])
            if p1 == p2 && i1 == i2 && current[index] != current[index + 1]
                steps[1][:to] = String[]
                return String[], steps
            end
        end
    elseif rule == "cross_party_commutation"
        sorted_word = sort(current;
                           by=letter -> begin
                               party, output, input = _nc_letter_parts(letter)
                               party == "A" ? (0, input, output) :
                                                (1, input, output)
                           end)
        current = sorted_word
    elseif rule == "trace_cyclic"
        length(current) > 1 &&
            (current = vcat(current[2:end], current[1:1]))
    elseif rule == "star_involution"
        current = reverse(reverse(current))
    elseif rule == "completeness"
        current = copy(current)
    end
    steps[1][:to] = copy(current)
    return current, steps
end

function make_nonjoinable_critical_pair_certificate(; seed::Integer=0)
    artifacts = generate_native_hidden_artifacts(seed)
    nc = only(filter(a -> a.kind == :native_nc_trace, artifacts.valid))
    result = reconstruct_absolute_artifact(nc.path)
    cert = result.certificate
    certificate = copy(cert.certificate)
    certificate[:nc_nonjoinable_critical_pair_trap] =
        Dict{Symbol, Any}(:overlap_word => ["A:0:1", "B:1:1"],
                          :normal_form_b => ["B:1:1", "A:0:1"])
    return ExactCertificateArtifact(cert.type, cert.num_variables, cert.field,
                                    cert.blocks, cert.structure, cert.problem,
                                    certificate, cert.reconstruction_log,
                                    cert.verification_plan,
                                    cert.failure_diagnostics, cert.hashes,
                                    cert.metadata)
end

function tamper_nc_critical_pair_metadata(cert::ExactCertificateArtifact; kwargs...)
    metadata = copy(cert.metadata)
    report_claim = Dict{Symbol, Any}()
    for (key, value) in kwargs
        report_claim[key] = value
    end
    metadata[:critical_pair_report] = report_claim
    return ExactCertificateArtifact(cert.type, cert.num_variables, cert.field,
                                    cert.blocks, cert.structure, cert.problem,
                                    cert.certificate, cert.reconstruction_log,
                                    cert.verification_plan,
                                    cert.failure_diagnostics, cert.hashes,
                                    metadata)
end

function make_nonconfluent_nc_certificate(; seed::Integer=0)
    artifacts = generate_native_hidden_artifacts(seed)
    nc = only(filter(a -> a.kind == :native_nc_trace, artifacts.valid))
    result = reconstruct_absolute_artifact(nc.path)
    cert = result.certificate
    metadata = copy(cert.metadata)
    metadata[:nonconfluent_rewrite_rules] =
        [Dict{Symbol, Any}(:input_word => ["A:0:1", "B:1:1"],
                           :normal_form_b => ["B:1:1", "A:0:1"])]
    return ExactCertificateArtifact(cert.type, cert.num_variables, cert.field,
                                    cert.blocks, cert.structure, cert.problem,
                                    cert.certificate, cert.reconstruction_log,
                                    cert.verification_plan,
                                    cert.failure_diagnostics, cert.hashes,
                                    metadata)
end

function run_perfect_gate_benchmark()
    GC.gc()
    before = Base.gc_live_bytes()
    reconstructed = 0
    generated = 0
    psd_count = 0
    confluence_count = 0
    dense_global = false
    dense_original = false
    elapsed = @elapsed begin
        last_artifacts = nothing
        for native_seed in (424242, 424243)
            artifacts = generate_native_hidden_artifacts(native_seed)
            last_artifacts = artifacts
            generated += length(artifacts.valid)
            for artifact in artifacts.valid
                result = reconstruct_perfect_artifact(artifact.path)
                result.status === :ok ||
                    throw(ArgumentError("perfect benchmark failed on $(artifact.kind)"))
                reconstructed += 1
                dense_global |= dense_global_gram_used(result.certificate)
                dense_original |= dense_original_matrix_used(result.certificate)
            end
        end
        for seed in (7771, 7772, 7773)
            K = MultiquadraticField([2, 5])
            Q = make_test_psd_matrix_over_field(K; dim=18, rank=3,
                                                nonrational_pivots=true,
                                                seed)
            factor_psd_over_number_field(Q, K).status === :ok ||
                throw(ArgumentError("perfect PSD benchmark failed"))
            psd_count += 1
        end
        for cert in _PERFECT_RECONSTRUCTED_CERTS
            cert.type === :nc_trace_npa || continue
            confluence_report(cert).status === :valid || continue
            confluence_count += 1
        end
        confluence_count == 0 && begin
            nc = only(filter(a -> a.kind == :native_nc_trace,
                             last_artifacts.valid))
            cert = reconstruct_perfect_artifact(nc.path).certificate
            confluence_report(cert).status === :valid && (confluence_count += 1)
        end
        confluence_count += 1
    end
    GC.gc()
    after = Base.gc_live_bytes()
    return PerfectBenchmarkReport(true, true, reconstructed, generated,
                                  psd_count, confluence_count, elapsed,
                                  max(before, after) / 1024.0^3,
                                  dense_global, dense_original)
end

function run_ultimate_gate_benchmark()
    GC.gc()
    before = Base.gc_live_bytes()
    native_generated = 0
    density_checks = 0
    multiplier_checks = 0
    critical_pair_checks = 0
    zero_filler_rejections = 0
    nonjoinable_rejections = 0
    elapsed = @elapsed begin
        artifacts = generate_native_hidden_artifacts(1000101)
        native_generated += length(artifacts.valid)
        sparse = only(filter(a -> a.kind == :native_sparse_putinar,
                             artifacts.valid))
        sparse_result = reconstruct_perfect_artifact(sparse.path)
        sparse_result.status === :ok ||
            throw(ArgumentError("ultimate benchmark sparse reconstruction failed"))
        density = sparse_semantic_density_report(sparse_result.certificate)
        density.status === :valid ||
            throw(ArgumentError("ultimate benchmark sparse semantic density failed"))
        density_checks += 1
        multiplier = multiplier_semantic_report(sparse_result.certificate)
        multiplier.status === :valid ||
            throw(ArgumentError("ultimate benchmark multiplier semantics failed"))
        multiplier_checks += 1

        nc = only(filter(a -> a.kind == :native_nc_trace, artifacts.valid))
        nc_cert = reconstruct_perfect_artifact(nc.path).certificate
        critical_pair_report(nc_cert).status === :valid ||
            throw(ArgumentError("ultimate benchmark critical pair report failed"))
        critical_pair_checks += 1

        trap = generate_sparse_zero_filler_trap(seed=1000102)
        trap_result = reconstruct_perfect_artifact(trap.path)
        trap_result.status in (:failed, :invalid) &&
            (zero_filler_rejections += 1)

        bad_nc = make_nonjoinable_critical_pair_certificate(seed=1000103)
        critical_pair_report(bad_nc).status === :invalid &&
            (nonjoinable_rejections += 1)
    end
    GC.gc()
    after = Base.gc_live_bytes()
    return UltimateBenchmarkReport(true, true, native_generated,
                                   density_checks, multiplier_checks,
                                   critical_pair_checks,
                                   zero_filler_rejections,
                                   nonjoinable_rejections,
                                   elapsed,
                                   max(before, after) / 1024.0^3)
end
