const BENCHMARK_EXPECTED_STATUS_CERTIFIED = "certified"
const BENCHMARK_EXPECTED_STATUS_REJECTED = "rejected"
const BENCHMARK_STATUS_ERROR = "error"
const BENCHMARK_STATUS_BACKEND_UNAVAILABLE = "skipped"
const BENCHMARK_STATUS_TIMEOUT = "timeout"
const BENCHMARK_STATUS_SKIPPED = "skipped"
const BENCHMARK_DEFAULT_SUBSET = :validation
const BENCHMARK_PUBLIC_PACK_LEVELS = (:validation,)
const BENCHMARK_DIFFICULTY_CLASSES = ("foundational", "workflow",
                                      "certificate_generation",
                                      "adversarial", "expected_failure")
const MIXED_BLOCK_ALGEBRAIC_WORKFLOW = :mixed_block_algebraic
const ALGEBRAIC_DIRECT_WORKFLOW = :lmi_algebraic_direct
const FAILURE_BOUNDARY_WORKFLOW = :failure_boundary
const JUMP_MOI_EXTRACT_WORKFLOW = :lmi_jump_moi_extract

"""
    run_benchmarks(root; out, subset=:validation, generated_dir=nothing, budget=:validation)

Run the v1.0 benchmark suite rooted at `root` and write a markdown report.
Each benchmark instance is a directory containing `problem.json`,
`approx.json`, `expected.json`, and `README.md`. The runner fails the suite
when the observed status does not match `expected.expected_status`.
The public entry point is `subset=:validation`.
"""
function run_benchmarks(root::AbstractString="benchmarks";
                        out::AbstractString,
                        subset::Union{Symbol, AbstractString}=BENCHMARK_DEFAULT_SUBSET,
                        generated_dir=nothing,
                        profile=DEFAULT_BENCHMARK_RESOURCE_PROFILE,
                        budget=nothing)
    suite_root = normpath(root)
    isdir(suite_root) ||
        throw(ArgumentError("benchmark root `$suite_root` does not exist or is not a directory"))

    selected_subset = Symbol(subset)
    selected_subset in (:validation, :all) ||
        throw(ArgumentError("benchmark subset must be `validation` or `all`; got `$selected_subset`"))
    benchmark_budget = resolve_resource_budget(; profile, budget)
    benchmark_profile = benchmark_budget.profile
    isnothing(benchmark_profile) &&
        throw(ArgumentError("benchmark validation budget must resolve to validation"))

    output_path = normpath(out)
    output_dir = dirname(output_path)
    mkpath(output_dir)
    cert_dir = isnothing(generated_dir) ? joinpath(output_dir, "generated") :
               normpath(String(generated_dir))
    mkpath(cert_dir)

    cases = benchmark_cases(suite_root; subset=selected_subset,
                            profile=benchmark_profile)
    isempty(cases) &&
        throw(ArgumentError("no benchmark instances selected under `$suite_root` for subset `$selected_subset`"))

    rows = NamedTuple[]
    for case in cases
        row = _run_benchmark_case(case, cert_dir, benchmark_budget)
        push!(rows, row)
    end

    mismatches = _benchmark_mismatches(rows)
    _write_benchmark_report(output_path, rows; subset=selected_subset, suite_root)

    return (;
            rows,
            report_path=output_path,
            subset=selected_subset,
            profile=benchmark_profile.name,
            validation_budget=validation_budget_label(benchmark_budget),
            timeout_policy=validation_timeout_policy(benchmark_budget),
            passed=isempty(mismatches),
            mismatches,)
end

"""
    benchmark_cases(root; subset=:validation, profile=:validation)

Discover benchmark instance directories recursively and load their
`expected.json` metadata. `:validation` selects the public validation suite;
`:all` selects every structurally valid instance that fits the validation
budget.
"""
function benchmark_cases(root::AbstractString;
                         subset::Union{Symbol, AbstractString}=BENCHMARK_DEFAULT_SUBSET,
                         profile=DEFAULT_BENCHMARK_RESOURCE_PROFILE)
    suite_root = normpath(root)
    selected_subset = Symbol(subset)
    resolved_profile = normalize_resource_profile(profile)
    entries = _benchmark_instance_dirs(suite_root)
    cases = NamedTuple[]
    for instance_dir in entries
        expected_path = joinpath(instance_dir, "expected.json")
        isfile(expected_path) || continue
        expected = _read_benchmark_expected(expected_path)
        name = _benchmark_case_name(suite_root, instance_dir)
        selected, resource_guarded = _benchmark_selection(expected,
                                                          selected_subset,
                                                          resolved_profile)
        selected || continue
        push!(cases,
              (;
               name,
               dir=instance_dir,
               problem_path=_benchmark_problem_path(instance_dir, expected),
               approx_path=joinpath(instance_dir, "approx.json"),
               expected_path,
               readme_path=joinpath(instance_dir, "README.md"),
               expected,
               resource_guarded,))
    end
    return cases
end

function _benchmark_problem_path(instance_dir::AbstractString, expected)
    if expected.workflow === :lmi_rational_sdpa_import
        return joinpath(instance_dir, "problem.dat-s")
    elseif expected.workflow === JUMP_MOI_EXTRACT_WORKFLOW
        return joinpath(instance_dir, "source.jl")
    end
    return joinpath(instance_dir, "problem.json")
end

function _benchmark_instance_dirs(root::AbstractString)
    suite_root = normpath(root)
    dirs = String[]
    function visit(dir)
        expected_path = joinpath(dir, "expected.json")
        if isfile(expected_path)
            push!(dirs, dir)
            return nothing
        end
        for entry in sort(readdir(dir))
            entry == "generated" && continue
            path = joinpath(dir, entry)
            isdir(path) && visit(path)
        end
        return nothing
    end
    visit(suite_root)
    return sort(dirs; by=dir -> _benchmark_case_name(suite_root, dir))
end

function _benchmark_case_name(root::AbstractString, dir::AbstractString)
    relative = relpath(normpath(dir), normpath(root))
    return replace(relative, '\\' => '/', '/' => "__")
end

function _benchmark_selected(expected, subset::Symbol, profile::ResourceProfile)
    selected, guarded = _benchmark_selection(expected, subset, profile)
    return selected && !guarded
end

function _benchmark_selection(expected, subset::Symbol, profile::ResourceProfile)
    profile_allows = resource_profile_allows(profile, expected.tier;
                                             memory_expectation_mb=expected.memory_expectation_mb)
    subset === :all && return (profile_allows, false)
    subset === :validation &&
        return (expected.pack_level_explicit && expected.pack_level === subset,
                !profile_allows)
    return (false, false)
end

function _read_benchmark_expected(path::AbstractString)
    parsed = _read_json_document(read(path, String), "benchmark expected metadata")
    _require_object(parsed, "expected")

    expected_status = _require_string(parsed, :expected_status, "expected.expected_status")
    expected_status in (BENCHMARK_EXPECTED_STATUS_CERTIFIED,
                        BENCHMARK_EXPECTED_STATUS_REJECTED,
                        BENCHMARK_STATUS_BACKEND_UNAVAILABLE,
                        BENCHMARK_STATUS_TIMEOUT,
                        BENCHMARK_STATUS_SKIPPED,
                        BENCHMARK_STATUS_ERROR) ||
        throw(ArgumentError("expected.expected_status has unsupported value `$expected_status`"))

    workflow = Symbol(_require_string(parsed, :workflow, "expected.workflow"))
    workflow in (:lmi_rational, :lmi_rational_sdpa_import,
                 JUMP_MOI_EXTRACT_WORKFLOW,
                 :lmi_algebraic, :lmi_solve_certify,
                 :sos_rational, :verify_certificate,
                 MIXED_BLOCK_ALGEBRAIC_WORKFLOW,
                 ALGEBRAIC_DIRECT_WORKFLOW,
                 FAILURE_BOUNDARY_WORKFLOW) ||
        throw(ArgumentError("expected.workflow must be `lmi_rational`, `lmi_rational_sdpa_import`, `lmi_jump_moi_extract`, `lmi_algebraic`, `lmi_algebraic_direct`, `lmi_solve_certify`, `sos_rational`, `verify_certificate`, `mixed_block_algebraic`, or `failure_boundary`; got `$workflow`"))

    category = _require_string(parsed, :category, "expected.category")
    strategy = _require_string(parsed, :strategy, "expected.strategy")
    backend = _require_string(parsed, :backend, "expected.backend")
    tier = haskey(parsed, :tier) ?
           normalize_capability_tier(_require_string(parsed, :tier, "expected.tier")) :
           :tier2

    expected_runtime_seconds = Float64(_require_number(parsed,
                                                       :expected_runtime_seconds,
                                                       "expected.expected_runtime_seconds"))
    expected_runtime_seconds > 0 ||
        throw(ArgumentError("expected.expected_runtime_seconds must be positive"))

    memory_expectation_mb = Int(_require_number(parsed, :memory_expectation_mb,
                                                "expected.memory_expectation_mb"))
    memory_expectation_mb >= 0 ||
        throw(ArgumentError("expected.memory_expectation_mb must be nonnegative"))

    backend_requirement = _require_string(parsed, :backend_requirement,
                                          "expected.backend_requirement")
    backend_requirement in ("none", "msolve", "clarabel", "external_optional") ||
        throw(ArgumentError("expected.backend_requirement has unsupported value `$backend_requirement`"))

    groups_value = haskey(parsed, :groups) ? _require_key(parsed, :groups, "expected") :
                   ["ci", "full"]
    _require_array(groups_value, "expected.groups")
    groups = String[]
    for (i, group) in enumerate(groups_value)
        group isa AbstractString ||
            throw(ArgumentError("expected.groups[$i] must be a string"))
        push!(groups, String(group))
    end

    max_time_seconds = if haskey(parsed, :max_time_seconds)
        Float64(_require_number(parsed, :max_time_seconds, "expected.max_time_seconds"))
    else
        nothing
    end

    pack_level_explicit = haskey(parsed, :pack_level)
    pack_level = pack_level_explicit ?
                 Symbol(_require_string(parsed, :pack_level, "expected.pack_level")) :
                 _infer_benchmark_pack_level(tier; groups_value=groups)
    pack_level in BENCHMARK_PUBLIC_PACK_LEVELS ||
        throw(ArgumentError("expected.pack_level must be `validation`; got `$pack_level`"))

    benchmark_family = haskey(parsed, :benchmark_family) ?
                       _require_string(parsed, :benchmark_family,
                                       "expected.benchmark_family") :
                       category
    source = haskey(parsed, :source) ?
             _require_string(parsed, :source, "expected.source") : "manual"
    source_kind = haskey(parsed, :source_kind) ?
                  _require_string(parsed, :source_kind,
                                  "expected.source_kind") :
                  _default_source_kind(source)
    source_kind in ("sdpa_import", "jump_moi_extract", "sumofsquares_extract",
                    "generated", "manual") ||
        throw(ArgumentError("expected.source_kind has unsupported value `$source_kind`"))
    certificate_origin = haskey(parsed, :certificate_origin) ?
                         _require_string(parsed, :certificate_origin,
                                         "expected.certificate_origin") :
                         _default_certificate_origin(workflow, source_kind)
    certificate_origin in ("direct_fixture", "certifier_generated",
                           "imported_certificate") ||
        throw(ArgumentError("expected.certificate_origin has unsupported value `$certificate_origin`"))
    pipeline = haskey(parsed, :pipeline) ?
               _require_string(parsed, :pipeline, "expected.pipeline") :
               _default_pipeline(workflow)
    pipeline in ("verify_only", "certify_from_approx",
                 "solve_diagnose_certify") ||
        throw(ArgumentError("expected.pipeline has unsupported value `$pipeline`"))
    rational_rounding_baseline = haskey(parsed, :rational_rounding_baseline) ?
                                 _require_string(parsed,
                                                 :rational_rounding_baseline,
                                                 "expected.rational_rounding_baseline") :
                                 _default_rounding_baseline(workflow, category)
    rational_rounding_baseline in ("success", "fails", "not_applicable", "unknown") ||
        throw(ArgumentError("expected.rational_rounding_baseline has unsupported value `$rational_rounding_baseline`"))

    expected_rank = haskey(parsed, :expected_rank) ?
                    Int(_require_number(parsed, :expected_rank, "expected.expected_rank")) :
                    nothing
    if !isnothing(expected_rank)
        expected_rank >= 0 ||
            throw(ArgumentError("expected.expected_rank must be nonnegative"))
    end

    algebraic_degree = haskey(parsed, :algebraic_degree) ?
                       Int(_require_number(parsed, :algebraic_degree,
                                           "expected.algebraic_degree")) :
                       nothing
    if !isnothing(algebraic_degree)
        algebraic_degree >= 0 ||
            throw(ArgumentError("expected.algebraic_degree must be nonnegative"))
    end

    timeout_seconds = if haskey(parsed, :timeout_seconds)
        Float64(_require_number(parsed, :timeout_seconds, "expected.timeout_seconds"))
    elseif !isnothing(max_time_seconds)
        Float64(max_time_seconds)
    else
        nothing
    end
    if !isnothing(timeout_seconds)
        timeout_seconds > 0 ||
            throw(ArgumentError("expected.timeout_seconds must be positive"))
    end

    certificate_type = haskey(parsed, :certificate_type) ?
                       _require_string(parsed, :certificate_type,
                                       "expected.certificate_type") : ""
    failure_type = haskey(parsed, :failure_type) ?
                   _require_string(parsed, :failure_type,
                                   "expected.failure_type") : ""
    variable_count = haskey(parsed, :variable_count) ?
                     Int(_require_number(parsed, :variable_count,
                                         "expected.variable_count")) : nothing
    if !isnothing(variable_count)
        variable_count >= 0 ||
            throw(ArgumentError("expected.variable_count must be nonnegative"))
    end
    block_count = haskey(parsed, :block_count) ?
                  Int(_require_number(parsed, :block_count,
                                      "expected.block_count")) : nothing
    if !isnothing(block_count)
        block_count >= 0 ||
            throw(ArgumentError("expected.block_count must be nonnegative"))
    end
    validation_profile = haskey(parsed, :validation_profile) ?
                         _require_string(parsed, :validation_profile,
                                         "expected.validation_profile") : ""
    max_system_variables = haskey(parsed, :max_system_variables) ?
                           Int(_require_number(parsed,
                                               :max_system_variables,
                                               "expected.max_system_variables")) :
                           nothing
    max_system_equations = haskey(parsed, :max_system_equations) ?
                           Int(_require_number(parsed,
                                               :max_system_equations,
                                               "expected.max_system_equations")) :
                           nothing
    max_degree_estimate = haskey(parsed, :max_degree_estimate) ?
                          Int(_require_number(parsed,
                                              :max_degree_estimate,
                                              "expected.max_degree_estimate")) :
                          nothing
    memory_hint_mb = haskey(parsed, :memory_hint_mb) ?
                     Int(_require_number(parsed,
                                         :memory_hint_mb,
                                         "expected.memory_hint_mb")) :
                     nothing
    for (name, value) in ((:max_system_variables, max_system_variables),
                          (:max_system_equations, max_system_equations),
                          (:max_degree_estimate, max_degree_estimate),
                          (:memory_hint_mb, memory_hint_mb))
        if !isnothing(value)
            value >= 0 ||
                throw(ArgumentError("expected.$name must be nonnegative"))
        end
    end
    size_hint = haskey(parsed, :size_hint) ?
                _require_string(parsed, :size_hint, "expected.size_hint") : ""
    psd_method = haskey(parsed, :psd_method) ?
                 Symbol(_require_string(parsed, :psd_method, "expected.psd_method")) :
                 :auto
    pivot_block = haskey(parsed, :pivot_block) ?
                  [Int(value) for value in _require_key(parsed, :pivot_block,
                                                        "expected")] :
                  nothing
    block_pivot_blocks = haskey(parsed, :block_pivot_blocks) ?
                         _parse_expected_block_pivots(_require_key(parsed,
                                                                   :block_pivot_blocks,
                                                                   "expected")) :
                         nothing
    rounding_denominator_bound = haskey(parsed, :rounding_denominator_bound) ?
                                 Int(_require_number(parsed,
                                                     :rounding_denominator_bound,
                                                     "expected.rounding_denominator_bound")) :
                                 1024
    rounding_denominator_bound > 0 ||
        throw(ArgumentError("expected.rounding_denominator_bound must be positive"))
    construction_type = haskey(parsed, :construction_type) ?
                        _require_string(parsed, :construction_type,
                                        "expected.construction_type") :
                        _default_construction_type(workflow, category, source)
    difficulty_class = haskey(parsed, :difficulty_class) ?
                       _require_string(parsed, :difficulty_class,
                                       "expected.difficulty_class") :
                       _default_difficulty_class(pack_level, expected_status,
                                                 category, size_hint,
                                                 workflow)
    difficulty_class in BENCHMARK_DIFFICULTY_CLASSES ||
        throw(ArgumentError("expected.difficulty_class must be one of $(join(BENCHMARK_DIFFICULTY_CLASSES, ", ")); got `$difficulty_class`"))
    scaling_family = haskey(parsed, :scaling_family) ?
                     _require_string(parsed, :scaling_family,
                                     "expected.scaling_family") :
                     benchmark_family
    scale_index = haskey(parsed, :scale_index) ?
                  Int(_require_number(parsed, :scale_index,
                                      "expected.scale_index")) :
                  _default_scale_index(size_hint)
    scale_index >= 0 ||
        throw(ArgumentError("expected.scale_index must be nonnegative"))
    seed = haskey(parsed, :seed) ?
           Int(_require_number(parsed, :seed, "expected.seed")) : nothing
    if !isnothing(seed)
        seed >= 0 || throw(ArgumentError("expected.seed must be nonnegative"))
    end

    return (;
            workflow,
            category,
            strategy,
            backend,
            tier,
            expected_runtime_seconds,
            memory_expectation_mb,
            backend_requirement,
            pack_level,
            pack_level_explicit,
            benchmark_family,
            source,
            source_kind,
            certificate_origin,
            pipeline,
            rational_rounding_baseline,
            expected_rank,
            algebraic_degree,
            timeout_seconds,
            expected_status,
            groups,
            max_time_seconds,
            certificate_type,
            failure_type,
            variable_count,
            block_count,
            validation_profile,
            max_system_variables,
            max_system_equations,
            max_degree_estimate,
            memory_hint_mb,
            size_hint,
            psd_method,
            pivot_block,
            block_pivot_blocks,
            rounding_denominator_bound,
            construction_type,
            difficulty_class,
            scaling_family,
            scale_index,
            seed,)
end

function _default_source_kind(source::AbstractString)
    text = lowercase(String(source))
    occursin("sdpa", text) && return "sdpa_import"
    occursin("jump", text) && return "jump_moi_extract"
    occursin("sumofsquares", text) && return "sumofsquares_extract"
    occursin("generated", text) && return "generated"
    return "manual"
end

function _default_certificate_origin(workflow::Symbol, source_kind::AbstractString)
    workflow in (ALGEBRAIC_DIRECT_WORKFLOW, MIXED_BLOCK_ALGEBRAIC_WORKFLOW,
                 FAILURE_BOUNDARY_WORKFLOW, :verify_certificate) &&
        return "direct_fixture"
    source_kind in ("sdpa_import", "jump_moi_extract", "sumofsquares_extract") &&
        return "certifier_generated"
    return "certifier_generated"
end

function _default_pipeline(workflow::Symbol)
    workflow in (ALGEBRAIC_DIRECT_WORKFLOW, MIXED_BLOCK_ALGEBRAIC_WORKFLOW,
                 FAILURE_BOUNDARY_WORKFLOW, :verify_certificate) &&
        return "verify_only"
    workflow === :lmi_solve_certify && return "solve_diagnose_certify"
    return "certify_from_approx"
end

function _parse_expected_block_pivots(value)
    _require_array(value, "expected.block_pivot_blocks")
    pivots = Vector{Union{Nothing, Vector{Int}}}()
    for (i, entry) in enumerate(value)
        if isnothing(entry)
            push!(pivots, nothing)
            continue
        end
        entry isa AbstractVector ||
            throw(ArgumentError("expected.block_pivot_blocks[$i] must be an array or null"))
        push!(pivots, Int[value for value in entry])
    end
    return pivots
end

function _infer_benchmark_pack_level(tier; groups_value)
    groups = Set{Symbol}()
    if groups_value isa AbstractVector
        for group in groups_value
            group isa AbstractString && push!(groups, Symbol(group))
        end
    end
    :validation in groups && return :validation
    return :validation
end

function _default_rounding_baseline(workflow::Symbol, category::AbstractString)
    workflow === :lmi_algebraic && return "fails"
    workflow in (:lmi_rational, :lmi_rational_sdpa_import,
                 JUMP_MOI_EXTRACT_WORKFLOW) && return "success"
    workflow === :lmi_solve_certify && return "fails"
    workflow === :sos_rational && return "success"
    workflow === :verify_certificate && return "not_applicable"
    return "unknown"
end

function _default_construction_type(workflow::Symbol, category::AbstractString,
                                    source::AbstractString)
    text = lowercase(string(category, " ", source))
    occursin("sdpa", text) && return "sdpa_import"
    occursin("jump", text) && return "jump_moi_extract"
    occursin("sumofsquares", text) && return "sumofsquares_extract"
    workflow === :sos_rational && return "sos_gram_exact"
    workflow === :lmi_rational_sdpa_import && return "sdpa_import"
    workflow === JUMP_MOI_EXTRACT_WORKFLOW && return "jump_moi_extract"
    workflow === :lmi_solve_certify && return "numerical_oracle_workflow"
    workflow === MIXED_BLOCK_ALGEBRAIC_WORKFLOW && return "mixed_exact_report"
    workflow === FAILURE_BOUNDARY_WORKFLOW && return "structured_expected_failure"
    return "generated_exact_fixture"
end

function _default_difficulty_class(pack_level::Symbol, expected_status::AbstractString,
                                   category::AbstractString, size_hint::AbstractString,
                                   workflow::Symbol)
    expected_status == BENCHMARK_EXPECTED_STATUS_CERTIFIED || return "expected_failure"
    text = lowercase(string(category, " ", size_hint))
    if occursin("negative", text) || workflow === :verify_certificate
        return "adversarial"
    elseif occursin("toy", text) || occursin("2x2", text) || occursin("x2_plus_1", text)
        return "foundational"
    elseif workflow in (:lmi_solve_certify, JUMP_MOI_EXTRACT_WORKFLOW)
        return "workflow"
    elseif workflow === :lmi_algebraic
        return "certificate_generation"
    end
    return "workflow"
end

function _default_scale_index(size_hint::AbstractString)
    value = max(_size_hint_number(size_hint, r"total(?:_dim)?[= ](\d+)"),
                _size_hint_number(size_hint, r"basis[= ](\d+)"),
                _size_hint_number(size_hint, r"^(\d+)x\d+"))
    return max(value, 0)
end

function _size_hint_number(text::AbstractString, pattern::Regex)
    found = match(pattern, String(text))
    isnothing(found) && return 0
    return parse(Int, found.captures[1])
end

function _require_number(object, key::Symbol, path::AbstractString)
    haskey(object, key) || throw(ArgumentError("$path is missing required key `$key`"))
    value = object[key]
    value isa Real || throw(ArgumentError("$path must be a number"))
    return value
end

function _run_benchmark_case(case, generated_dir::AbstractString,
                             budget::ResourceBudget)
    if get(case, :resource_guarded, false)
        return _benchmark_resource_guard_row(case, budget)
    end

    missing = _missing_benchmark_files(case)
    if !isempty(missing)
        return _benchmark_error_row(case,
                                    "missing required benchmark files: $(join(missing, ", "))",
                                    budget)
    end

    try
        case_budget = _benchmark_case_budget(case, budget)
        workflow = case.expected.workflow
        if workflow === :lmi_rational
            return _run_lmi_rational_benchmark(case, generated_dir, case_budget)
        elseif workflow === :lmi_rational_sdpa_import
            return _run_lmi_rational_benchmark(case, generated_dir, case_budget)
        elseif workflow === JUMP_MOI_EXTRACT_WORKFLOW
            return _run_lmi_jump_moi_extract_benchmark(case, generated_dir, case_budget)
        elseif workflow === :lmi_algebraic
            return _run_lmi_algebraic_benchmark(case, generated_dir, case_budget)
        elseif workflow === ALGEBRAIC_DIRECT_WORKFLOW
            return _run_lmi_algebraic_direct_benchmark(case, generated_dir, case_budget)
        elseif workflow === :lmi_solve_certify
            return _run_lmi_solve_certify_benchmark(case, generated_dir, case_budget)
        elseif workflow === :sos_rational
            return _run_sos_rational_benchmark(case, generated_dir, case_budget)
        elseif workflow === :verify_certificate
            return _run_verify_certificate_benchmark(case, case_budget)
        elseif workflow === MIXED_BLOCK_ALGEBRAIC_WORKFLOW
            return _run_mixed_block_algebraic_benchmark(case, generated_dir, case_budget)
        elseif workflow === FAILURE_BOUNDARY_WORKFLOW
            return _run_failure_boundary_benchmark(case, case_budget)
        end
    catch err
        return _benchmark_error_row(case, sprint(showerror, err), budget)
    end

    return _benchmark_error_row(case, "unsupported workflow $(case.expected.workflow)",
                                budget)
end

function _benchmark_resource_guard_row(case, budget::ResourceBudget)
    budget_label = validation_budget_label(budget)
    message = string("skipped by validation budget: declared validation level ",
                     case.expected.tier,
                     ", memory expectation ",
                     _benchmark_format_memory(case.expected.memory_expectation_mb))
    return _benchmark_row(case;
                          size=case.expected.size_hint == "" ?
                               _benchmark_problem_size(case) :
                               case.expected.size_hint,
                          status=BENCHMARK_STATUS_SKIPPED,
                          cert_seconds=NaN,
                          verify_seconds=NaN,
                          verify_uncached_seconds=NaN,
                          strict_verify_seconds=NaN,
                          strict_verify_accepted=false,
                          verify_cache_hits=0,
                          verify_cache_misses=0,
                          verify_cache_speedup=NaN,
                          slowest_verify_stage="-",
                          slowest_verify_stage_seconds=NaN,
                          verify_consistent=true,
                          cert_size=0,
                          certificate_type="",
                          failure_type="ResourceGuard",
                          metrics=_benchmark_empty_metrics(; verify_seconds=NaN,
                                                           validation_budget=budget_label,
                                                           timeout_seconds=_benchmark_timeout_seconds(case,
                                                                                                      budget)),
                          rounding_attempt=_rational_rounding_not_applicable("resource guard skipped this scale before certification"),
                          message)
end

function _resource_guard_realism_metrics(case)
    declared = _declared_variables(case)
    return (;
            effective_variables=declared,
            declared_variables=declared,
            affine_matrix_density=0.0,
            coefficient_bit_size_range="-",
            nonzero_affine_matrices=0,
            rank_profile=isnothing(case.expected.expected_rank) ? "-" :
                         string("rank=", case.expected.expected_rank),
            block_variable_coupling="resource_guard",
            gram_offdiagonal_ratio="resource_guard",
            construction_type=case.expected.construction_type,
            difficulty_class="expected_failure",)
end

function _benchmark_case_budget(case, budget::ResourceBudget)
    return resolve_resource_budget(;
                                   profile=budget.profile,
                                   budget,
                                   max_system_variables=case.expected.max_system_variables,
                                   max_system_equations=case.expected.max_system_equations,
                                   max_degree_estimate=case.expected.max_degree_estimate,
                                   timeout_seconds=case.expected.timeout_seconds,
                                   memory_hint_mb=case.expected.memory_hint_mb)
end

function _benchmark_timeout_seconds(case, budget::ResourceBudget)
    candidate = budget.timeout_seconds
    expected = case.expected.timeout_seconds
    if isnothing(candidate)
        return expected
    elseif isnothing(expected)
        return candidate
    end
    return min(Float64(candidate), Float64(expected))
end

function _missing_benchmark_files(case)
    problem_label = case.expected.workflow === :lmi_rational_sdpa_import ?
                    "problem.dat-s" :
                    case.expected.workflow === JUMP_MOI_EXTRACT_WORKFLOW ?
                    "source.jl" : "problem.json"
    required = Pair{String, String}[problem_label => case.problem_path,
                                    "expected.json" => case.expected_path,
                                    "README.md" => case.readme_path]
    case.expected.workflow === JUMP_MOI_EXTRACT_WORKFLOW ||
        push!(required, "approx.json" => case.approx_path)
    return [label for (label, path) in required if !isfile(path)]
end

function _run_lmi_rational_benchmark(case, generated_dir::AbstractString,
                                     budget::ResourceBudget)
    P = read_problem(case.problem_path)
    P isa Union{LMIProblem, BlockLMIProblem} ||
        throw(ArgumentError("problem.json must define an LMI problem"))
    x = _benchmark_read_rational_solution(case.approx_path, P)
    rounding = _rational_rounding_attempt(P, x;
                                          denominator_bound=case.expected.rounding_denominator_bound,
                                          source=:rational_solution)
    cert_path = joinpath(generated_dir, case.name * "_cert.json")
    rm(cert_path; force=true)

    cert_seconds, cert_result = _benchmark_timed() do
        cert = if P isa BlockLMIProblem
            RationalCertificate(P, x;
                                psd_method=case.expected.psd_method,
                                block_pivot_blocks=case.expected.block_pivot_blocks,
                                pivot_block=case.expected.pivot_block)
        else
            RationalCertificate(P, x;
                                psd_method=case.expected.psd_method,
                                pivot_block=case.expected.pivot_block)
        end
        write_certificate(cert_path, cert)
        return cert
    end
    verify = _benchmark_verify_with_cache_modes(read_certificate(cert_path))
    accepted = verify.accepted
    metrics = _benchmark_certificate_metrics(cert_result;
                                             verify_seconds=verify.cache_seconds,
                                             validation_budget=validation_budget_label(budget),
                                             timeout_seconds=_benchmark_timeout_seconds(case,
                                                                                        budget))

    return _benchmark_row(case;
                          size=_benchmark_lmi_size(P),
                          status=accepted ? BENCHMARK_EXPECTED_STATUS_CERTIFIED :
                                 BENCHMARK_EXPECTED_STATUS_REJECTED,
                          cert_seconds,
                          verify_seconds=verify.cache_seconds,
                          verify_uncached_seconds=verify.uncached_seconds,
                          strict_verify_seconds=verify.strict_seconds,
                          strict_verify_accepted=verify.strict_accepted,
                          verify_cache_hits=verify.cache_hits,
                          verify_cache_misses=verify.cache_misses,
                          verify_cache_speedup=_cache_speedup(verify.uncached_seconds,
                                                              verify.cache_seconds),
                          slowest_verify_stage=verify.profiler.slowest_stage,
                          slowest_verify_stage_seconds=verify.profiler.slowest_stage_seconds,
                          verify_consistent=verify.consistent,
                          cert_size=isfile(cert_path) ? filesize(cert_path) : 0,
                          certificate_type=cert_result isa BlockRationalCertificate ?
                                           BLOCK_RATIONAL_CERTIFICATE_TYPE :
                                           cert_result isa RationalCertificate ?
                                           RATIONAL_CERTIFICATE_TYPE : "",
                          metrics,
                          rounding_attempt=rounding,
                          message=accepted ? "certificate verified" :
                                  "generated certificate was rejected")
end

function _run_lmi_jump_moi_extract_benchmark(case, generated_dir::AbstractString,
                                             budget::ResourceBudget)
    extracted_dir = joinpath(generated_dir, case.name * "_extracted")
    rm(extracted_dir; force=true, recursive=true)
    mkpath(extracted_dir)

    extract_seconds, extract = _benchmark_timed() do
        return _run_jump_moi_extraction_script(case.problem_path, extracted_dir)
    end
    if extract.status != BENCHMARK_EXPECTED_STATUS_CERTIFIED
        metrics = _benchmark_empty_metrics(; verify_seconds=NaN,
                                           validation_budget=validation_budget_label(budget),
                                           timeout_seconds=_benchmark_timeout_seconds(case,
                                                                                      budget))
        return _benchmark_row(case;
                              size=case.expected.size_hint == "" ? "-" :
                                   case.expected.size_hint,
                              status=extract.status,
                              cert_seconds=extract_seconds,
                              verify_seconds=NaN,
                              verify_uncached_seconds=NaN,
                              strict_verify_seconds=NaN,
                              strict_verify_accepted=false,
                              verify_cache_hits=0,
                              verify_cache_misses=0,
                              verify_cache_speedup=NaN,
                              slowest_verify_stage="-",
                              slowest_verify_stage_seconds=NaN,
                              verify_consistent=true,
                              cert_size=0,
                              certificate_type="",
                              failure_type=extract.failure_type,
                              metrics,
                              rounding_attempt=_rational_rounding_not_applicable("JuMP/MOI extraction failed before coordinate certification"),
                              message=extract.message)
    end

    extracted_problem = joinpath(extracted_dir, "problem.json")
    extracted_solution = joinpath(extracted_dir, "approx.json")
    P = read_problem(extracted_problem)
    P isa Union{LMIProblem, BlockLMIProblem} ||
        throw(ArgumentError("JuMP/MOI extractor did not emit an LMI problem"))
    x = _benchmark_read_rational_solution(extracted_solution, P)
    rounding = _rational_rounding_attempt(P, x;
                                          denominator_bound=case.expected.rounding_denominator_bound,
                                          source=:rational_solution)
    cert_path = joinpath(generated_dir, case.name * "_cert.json")
    rm(cert_path; force=true)

    cert_seconds, cert_result = _benchmark_timed() do
        cert = if P isa BlockLMIProblem
            RationalCertificate(P, x;
                                psd_method=case.expected.psd_method,
                                block_pivot_blocks=case.expected.block_pivot_blocks,
                                pivot_block=case.expected.pivot_block)
        else
            RationalCertificate(P, x;
                                psd_method=case.expected.psd_method,
                                pivot_block=case.expected.pivot_block)
        end
        write_certificate(cert_path, cert)
        return cert
    end
    verify = _benchmark_verify_with_cache_modes(read_certificate(cert_path))
    accepted = verify.accepted
    metrics = _benchmark_certificate_metrics(cert_result;
                                             verify_seconds=verify.cache_seconds,
                                             validation_budget=validation_budget_label(budget),
                                             timeout_seconds=_benchmark_timeout_seconds(case,
                                                                                        budget))
    message = accepted ?
              string("JuMP/MOI extraction artifact ",
                     basename(extracted_dir),
                     " certified and strict-verified") :
              "generated JuMP/MOI extracted certificate was rejected"

    extracted_case = merge(case,
                           (;
                            problem_path=extracted_problem,
                            approx_path=extracted_solution,))
    return _benchmark_row(extracted_case;
                          size=_benchmark_lmi_size(P),
                          status=accepted ? BENCHMARK_EXPECTED_STATUS_CERTIFIED :
                                 BENCHMARK_EXPECTED_STATUS_REJECTED,
                          cert_seconds=extract_seconds + cert_seconds,
                          verify_seconds=verify.cache_seconds,
                          verify_uncached_seconds=verify.uncached_seconds,
                          strict_verify_seconds=verify.strict_seconds,
                          strict_verify_accepted=verify.strict_accepted,
                          verify_cache_hits=verify.cache_hits,
                          verify_cache_misses=verify.cache_misses,
                          verify_cache_speedup=_cache_speedup(verify.uncached_seconds,
                                                              verify.cache_seconds),
                          slowest_verify_stage=verify.profiler.slowest_stage,
                          slowest_verify_stage_seconds=verify.profiler.slowest_stage_seconds,
                          verify_consistent=verify.consistent,
                          cert_size=isfile(cert_path) ? filesize(cert_path) : 0,
                          certificate_type=cert_result isa BlockRationalCertificate ?
                                           BLOCK_RATIONAL_CERTIFICATE_TYPE :
                                           cert_result isa RationalCertificate ?
                                           RATIONAL_CERTIFICATE_TYPE : "",
                          metrics,
                          rounding_attempt=rounding,
                          message)
end

function _run_lmi_algebraic_benchmark(case, generated_dir::AbstractString,
                                      budget::ResourceBudget)
    P = read_problem(case.problem_path)
    P isa BlockLMIProblem && (P = single_lmi_problem(P))
    P isa LMIProblem || throw(ArgumentError("problem.json must define an LMI problem"))

    if case.expected.backend == "msolve" && !has_msolve() &&
       case.expected.failure_type != "SystemTooLargeFailure"
        return _benchmark_row(case;
                              size=_benchmark_lmi_size(P),
                              status=BENCHMARK_STATUS_BACKEND_UNAVAILABLE,
                              cert_seconds=NaN,
                              verify_seconds=NaN,
                              cert_size=0,
                              certificate_type="",
                              rounding_attempt=_rational_rounding_not_applicable("algebraic benchmark did not run because msolve is unavailable"),
                              message="msolve executable is unavailable")
    end

    approx = _benchmark_read_approx_solution(case.approx_path, P)
    rounding = _rational_rounding_attempt(P, approx;
                                          denominator_bound=case.expected.rounding_denominator_bound,
                                          source=:approximation)
    cert_path = joinpath(generated_dir, case.name * "_cert.json")
    rm(cert_path; force=true)

    cert_seconds, result = _benchmark_timed() do
        return certify(P, approx;
                       algebraic_backend=Symbol(case.expected.backend),
                       psd_method=case.expected.psd_method,
                       pivot_block=case.expected.pivot_block,
                       msolve_precision=128,
                       msolve_threads=1,
                       resource_profile=budget.profile,
                       budget=budget,
                       verify_io=nothing)
    end

    if result isa FailureResult
        failure_path = _write_benchmark_failure_artifact(generated_dir, case, result)
        status = _benchmark_failure_status(result.failure)
        if status == BENCHMARK_STATUS_BACKEND_UNAVAILABLE
            detail = "msolve executable is unavailable"
        elseif status == BENCHMARK_STATUS_TIMEOUT
            detail = "msolve exceeded timeout"
        else
            detail = "not certified: $(result.failure.reason)"
        end
        metrics = _benchmark_empty_metrics(; verify_seconds=NaN,
                                           validation_budget=validation_budget_label(budget),
                                           timeout_seconds=_benchmark_timeout_seconds(case,
                                                                                      budget))
        return _benchmark_row(case;
                              size=_benchmark_lmi_size(P),
                              status,
                              cert_seconds,
                              verify_seconds=NaN,
                              cert_size=isfile(failure_path) ? filesize(failure_path) : 0,
                              certificate_type="",
                              failure_type=_benchmark_failure_type(result.failure),
                              metrics,
                              rounding_attempt=rounding,
                              solve_diagnostics=_benchmark_solve_diagnostics(approx,
                                                                             result),
                              message=string(detail, "; failure artifact: ",
                                             basename(failure_path)))
    end

    write_certificate(cert_path, result)
    verify = _benchmark_verify_with_cache_modes(read_certificate(cert_path))
    accepted = verify.accepted
    metrics = _benchmark_certificate_metrics(result.certificate;
                                             verify_seconds=verify.cache_seconds,
                                             validation_budget=validation_budget_label(budget),
                                             timeout_seconds=_benchmark_timeout_seconds(case,
                                                                                        budget))

    return _benchmark_row(case;
                          size=_benchmark_lmi_size(P),
                          status=accepted ? BENCHMARK_EXPECTED_STATUS_CERTIFIED :
                                 BENCHMARK_EXPECTED_STATUS_REJECTED,
                          cert_seconds,
                          verify_seconds=verify.cache_seconds,
                          verify_uncached_seconds=verify.uncached_seconds,
                          strict_verify_seconds=verify.strict_seconds,
                          strict_verify_accepted=verify.strict_accepted,
                          verify_cache_hits=verify.cache_hits,
                          verify_cache_misses=verify.cache_misses,
                          verify_cache_speedup=_cache_speedup(verify.uncached_seconds,
                                                              verify.cache_seconds),
                          slowest_verify_stage=verify.profiler.slowest_stage,
                          slowest_verify_stage_seconds=verify.profiler.slowest_stage_seconds,
                          verify_consistent=verify.consistent,
                          cert_size=isfile(cert_path) ? filesize(cert_path) : 0,
                          certificate_type=result.certificate isa AlgebraicCertificate ?
                                           ALGEBRAIC_CERTIFICATE_TYPE : "",
                          metrics,
                          rounding_attempt=rounding,
                          message=accepted ? "certificate verified" :
                                  "generated certificate was rejected")
end

function _run_lmi_algebraic_direct_benchmark(case, generated_dir::AbstractString,
                                             budget::ResourceBudget)
    P = read_problem(case.problem_path)
    P isa BlockLMIProblem && (P = single_lmi_problem(P))
    P isa LMIProblem || throw(ArgumentError("problem.json must define an LMI problem"))

    parsed = _read_json_document(read(case.approx_path, String),
                                 "direct algebraic benchmark solution")
    _require_object(parsed, "root")
    solution_object = haskey(parsed, :algebraic_solution) ?
                      _require_key(parsed, :algebraic_solution, "root") :
                      _require_key(parsed, :solution, "root")
    root, solution = _parse_algebraic_solution(solution_object, P)
    _algebraic_root_interval_verified(root) ||
        throw(ArgumentError("direct algebraic root interval is not certified"))

    rounding = if haskey(parsed, :rounding_xhat)
        values = _parse_mixed_rounding_xhat(_require_key(parsed, :rounding_xhat,
                                                         "root"))
        _rational_rounding_attempt(P, values;
                                   denominator_bound=case.expected.rounding_denominator_bound,
                                   source=:approximation)
    else
        _rational_rounding_not_applicable("direct algebraic benchmark did not provide a rounding baseline")
    end

    cert_path = joinpath(generated_dir, case.name * "_cert.json")
    rm(cert_path; force=true)
    cert_seconds, cert = _benchmark_timed() do
        built = AlgebraicCertificate(P, root, solution;
                                     psd_method=case.expected.psd_method,
                                     pivot_block=case.expected.pivot_block)
        write_certificate(cert_path, built)
        return built
    end
    verify = _benchmark_verify_with_cache_modes(read_certificate(cert_path))
    accepted = verify.accepted
    metrics = _benchmark_certificate_metrics(cert;
                                             verify_seconds=verify.cache_seconds,
                                             validation_budget=validation_budget_label(budget),
                                             timeout_seconds=_benchmark_timeout_seconds(case,
                                                                                        budget))

    return _benchmark_row(case;
                          size=_benchmark_lmi_size(P),
                          status=accepted ? BENCHMARK_EXPECTED_STATUS_CERTIFIED :
                                 BENCHMARK_EXPECTED_STATUS_REJECTED,
                          cert_seconds,
                          verify_seconds=verify.cache_seconds,
                          verify_uncached_seconds=verify.uncached_seconds,
                          strict_verify_seconds=verify.strict_seconds,
                          strict_verify_accepted=verify.strict_accepted,
                          verify_cache_hits=verify.cache_hits,
                          verify_cache_misses=verify.cache_misses,
                          verify_cache_speedup=_cache_speedup(verify.uncached_seconds,
                                                              verify.cache_seconds),
                          slowest_verify_stage=verify.profiler.slowest_stage,
                          slowest_verify_stage_seconds=verify.profiler.slowest_stage_seconds,
                          verify_consistent=verify.consistent,
                          cert_size=isfile(cert_path) ? filesize(cert_path) : 0,
                          certificate_type=ALGEBRAIC_CERTIFICATE_TYPE,
                          metrics,
                          rounding_attempt=rounding,
                          message=accepted ? "direct algebraic certificate verified" :
                                  "direct algebraic certificate was rejected")
end

function _run_lmi_solve_certify_benchmark(case, generated_dir::AbstractString,
                                          budget::ResourceBudget)
    P = read_problem(case.problem_path)
    P isa BlockLMIProblem && (P = single_lmi_problem(P))
    P isa LMIProblem || throw(ArgumentError("problem.json must define an LMI problem"))

    if case.expected.backend == "msolve" && !has_msolve()
        return _benchmark_row(case;
                              size=_benchmark_lmi_size(P),
                              status=BENCHMARK_STATUS_BACKEND_UNAVAILABLE,
                              cert_seconds=NaN,
                              verify_seconds=NaN,
                              cert_size=0,
                              certificate_type="",
                              rounding_attempt=_rational_rounding_not_applicable("solve did not run because msolve is unavailable"),
                              message="msolve executable is unavailable")
    end

    solve_options = _benchmark_read_solve_options(case.approx_path)
    cert_path = joinpath(generated_dir, case.name * "_cert.json")
    approx_path = joinpath(generated_dir, case.name * "_solved_approx.json")
    rm(cert_path; force=true)
    rm(approx_path; force=true)

    approx_holder = Ref{Any}(nothing)
    cert_seconds, result = _benchmark_timed() do
        approx = solve_approximately(P;
                                     solvers=solve_options.solvers,
                                     random_objective_trials=solve_options.random_objective_trials,
                                     trace_objective=solve_options.trace_objective,
                                     solver_attempts=solve_options.solver_attempts,
                                     solver_retry_policy=solve_options.solver_retry_policy,
                                     precision=solve_options.precision_bits,
                                     random_seed=solve_options.random_seed,
                                     require_stable_rank=solve_options.require_stable_rank,
                                     clarabel_max_iter=solve_options.clarabel_max_iter)
        approx_holder[] = approx
        approx isa ApproxSolution || return FailureResult(approx)
        write_approx_solution_json(approx_path, approx)
        return certify(P, approx;
                       algebraic_backend=Symbol(case.expected.backend),
                       psd_method=case.expected.psd_method,
                       pivot_block=case.expected.pivot_block,
                       msolve_precision=128,
                       msolve_threads=1,
                       resource_profile=budget.profile,
                       budget=budget,
                       verify_io=nothing)
    end

    rounding = approx_holder[] isa ApproxSolution ?
               _rational_rounding_attempt(P, approx_holder[];
                                          denominator_bound=case.expected.rounding_denominator_bound,
                                          source=:numerical_oracle) :
               _rational_rounding_not_applicable("numerical solve did not produce an approximation")

    if result isa FailureResult
        failure_path = _write_benchmark_failure_artifact(generated_dir, case, result)
        status = _benchmark_failure_status(result.failure)
        detail = status == BENCHMARK_STATUS_BACKEND_UNAVAILABLE ?
                 "msolve executable is unavailable" :
                 status == BENCHMARK_STATUS_TIMEOUT ?
                 "msolve exceeded timeout" :
                 "not certified: $(result.failure.reason)"
        metrics = _benchmark_empty_metrics(; verify_seconds=NaN,
                                           validation_budget=validation_budget_label(budget),
                                           timeout_seconds=_benchmark_timeout_seconds(case,
                                                                                      budget))
        return _benchmark_row(case;
                              size=_benchmark_lmi_size(P),
                              status,
                              cert_seconds,
                              verify_seconds=NaN,
                              cert_size=isfile(failure_path) ? filesize(failure_path) : 0,
                              certificate_type="",
                              failure_type=_benchmark_failure_type(result.failure),
                              metrics,
                              rounding_attempt=rounding,
                              message=string(detail, "; failure artifact: ",
                                             basename(failure_path)))
    end

    write_certificate(cert_path, result)
    verify = _benchmark_verify_with_cache_modes(read_certificate(cert_path))
    accepted = verify.accepted
    metrics = _benchmark_certificate_metrics(result.certificate;
                                             verify_seconds=verify.cache_seconds,
                                             validation_budget=validation_budget_label(budget),
                                             timeout_seconds=_benchmark_timeout_seconds(case,
                                                                                        budget))

    return _benchmark_row(case;
                          size=_benchmark_lmi_size(P),
                          status=accepted ? BENCHMARK_EXPECTED_STATUS_CERTIFIED :
                                 BENCHMARK_EXPECTED_STATUS_REJECTED,
                          cert_seconds,
                          verify_seconds=verify.cache_seconds,
                          verify_uncached_seconds=verify.uncached_seconds,
                          strict_verify_seconds=verify.strict_seconds,
                          strict_verify_accepted=verify.strict_accepted,
                          verify_cache_hits=verify.cache_hits,
                          verify_cache_misses=verify.cache_misses,
                          verify_cache_speedup=_cache_speedup(verify.uncached_seconds,
                                                              verify.cache_seconds),
                          slowest_verify_stage=verify.profiler.slowest_stage,
                          slowest_verify_stage_seconds=verify.profiler.slowest_stage_seconds,
                          verify_consistent=verify.consistent,
                          cert_size=isfile(cert_path) ? filesize(cert_path) : 0,
                          certificate_type=result.certificate isa AlgebraicCertificate ?
                                           ALGEBRAIC_CERTIFICATE_TYPE : "",
                          metrics,
                          rounding_attempt=rounding,
                          solve_diagnostics=_benchmark_solve_diagnostics(approx_holder[],
                                                                         result),
                          message=accepted ? "solve -> diagnose -> certificate verified" :
                                  "generated certificate was rejected")
end

function _run_sos_rational_benchmark(case, generated_dir::AbstractString,
                                     budget::ResourceBudget)
    problem = parse_sos_gram_json(read(case.problem_path, String))
    gram = _benchmark_read_sos_gram_matrix(case.approx_path, problem)
    rounding = _rational_rounding_not_applicable("SOS Gram benchmark uses exact coefficient matching, not LMI coordinate rounding")
    cert_path = joinpath(generated_dir, case.name * "_cert.json")
    rm(cert_path; force=true)

    cert_seconds, result = _benchmark_timed() do
        built = certify_sos(problem, gram)
        write_certificate(cert_path, built)
        return built
    end
    verify = _benchmark_verify_with_cache_modes(read_certificate(cert_path))
    accepted = verify.accepted
    cert_object = result isa CertifiedResult ? result.certificate : result
    metrics = _benchmark_certificate_metrics(cert_object;
                                             verify_seconds=verify.cache_seconds,
                                             validation_budget=validation_budget_label(budget),
                                             timeout_seconds=_benchmark_timeout_seconds(case,
                                                                                        budget))

    return _benchmark_row(case;
                          size=_benchmark_sos_size(problem),
                          status=accepted ? BENCHMARK_EXPECTED_STATUS_CERTIFIED :
                                 BENCHMARK_EXPECTED_STATUS_REJECTED,
                          cert_seconds,
                          verify_seconds=verify.cache_seconds,
                          verify_uncached_seconds=verify.uncached_seconds,
                          strict_verify_seconds=verify.strict_seconds,
                          strict_verify_accepted=verify.strict_accepted,
                          verify_cache_hits=verify.cache_hits,
                          verify_cache_misses=verify.cache_misses,
                          verify_cache_speedup=_cache_speedup(verify.uncached_seconds,
                                                              verify.cache_seconds),
                          slowest_verify_stage=verify.profiler.slowest_stage,
                          slowest_verify_stage_seconds=verify.profiler.slowest_stage_seconds,
                          verify_consistent=verify.consistent,
                          cert_size=isfile(cert_path) ? filesize(cert_path) : 0,
                          certificate_type=result isa CertifiedResult &&
                                           result.certificate isa SOSGramCertificate ?
                                           SOS_GRAM_CERTIFICATE_TYPE : "",
                          metrics,
                          rounding_attempt=rounding,
                          message=accepted ? "SOS Gram certificate verified" :
                                  "SOS Gram certificate was rejected")
end

function _run_mixed_block_algebraic_benchmark(case, generated_dir::AbstractString,
                                              budget::ResourceBudget)
    P = read_problem(case.problem_path)
    P isa BlockLMIProblem ||
        throw(ArgumentError("mixed_block_algebraic benchmark expects a block LMI problem"))

    parsed = _read_json_document(read(case.approx_path, String),
                                 "mixed block algebraic benchmark solution")
    _require_object(parsed, "root")
    root, solution = _parse_mixed_block_algebraic_solution(parsed, P)
    _algebraic_root_interval_verified(root) ||
        throw(ArgumentError("mixed block algebraic root interval is not certified"))

    rounding = if haskey(parsed, :rounding_xhat)
        values = _parse_mixed_rounding_xhat(_require_key(parsed, :rounding_xhat, "root"))
        _rational_rounding_attempt(P, values;
                                   denominator_bound=case.expected.rounding_denominator_bound,
                                   source=:approximation)
    else
        _rational_rounding_not_applicable("mixed block report did not provide a numerical rounding baseline")
    end

    block_specs = _parse_mixed_block_specs(_require_key(parsed, :block_proofs, "root"),
                                           num_blocks(P))
    reports = Vector{NamedTuple}()
    cert_seconds, accepted = _benchmark_timed() do
        for (block_index, (block, spec)) in enumerate(zip(P.blocks, block_specs))
            field = spec.field
            method = spec.method
            if field == "algebraic"
                matrix = substitute(block, solution)
                algebraic_psd_proof(matrix; method=Symbol(method),
                                    pivot_block=spec.pivot_block)
            elseif field in ("rational", "facial")
                _mixed_block_is_solution_independent(block) ||
                    throw(ArgumentError("mixed block $block_index is marked `$field` but depends on the algebraic solution"))
                rational_psd_proof(block.A0; method=Symbol(method),
                                   pivot_block=spec.pivot_block)
            else
                throw(ArgumentError("unsupported mixed block proof field `$field`"))
            end
            push!(reports,
                  (;
                   block=block_index,
                   field,
                   proof_method=method,
                   dimension=matrix_size(block),
                   pivot_block=isnothing(spec.pivot_block) ? Int[] :
                               spec.pivot_block,))
        end
        return true
    end

    report_path = joinpath(generated_dir, case.name * "_mixed_report.json")
    report = (;
              certificate_type=case.expected.certificate_type,
              problem_hash=block_lmi_problem_hash(P),
              solution_field="QQbar",
              minimal_polynomial=string(root.f),
              root_interval=[_rational_string(root.interval.lower),
                             _rational_string(root.interval.upper)],
              block_reports=reports,)
    open(report_path, "w") do io
        JSON3.pretty(io, report)
        return println(io)
    end

    methods = join((string("block ", entry.block, " ", entry.field, " ",
                           entry.proof_method) for entry in reports), "; ")
    return _benchmark_row(case;
                          size=_benchmark_lmi_size(P),
                          status=accepted ? BENCHMARK_EXPECTED_STATUS_CERTIFIED :
                                 BENCHMARK_EXPECTED_STATUS_REJECTED,
                          cert_seconds,
                          verify_seconds=cert_seconds,
                          strict_verify_seconds=cert_seconds,
                          strict_verify_accepted=accepted,
                          verify_uncached_seconds=cert_seconds,
                          verify_cache_hits=0,
                          verify_cache_misses=0,
                          verify_cache_speedup=NaN,
                          slowest_verify_stage="-",
                          slowest_verify_stage_seconds=NaN,
                          verify_consistent=true,
                          cert_size=isfile(report_path) ? filesize(report_path) : 0,
                          certificate_type=case.expected.certificate_type,
                          rounding_attempt=rounding,
                          message=accepted ?
                                  "mixed block exact report verified: $methods" :
                                  "mixed block exact report rejected")
end

function _run_verify_certificate_benchmark(case, budget::ResourceBudget)
    problem_size = _benchmark_problem_size(case)
    verify_seconds, result, uncached_seconds, strict_seconds, strict_accepted, cache_hits, cache_misses, cache_speedup, slowest_stage, slowest_stage_seconds, consistent, metrics, rounding = try
        cert = read_certificate(case.approx_path)
        rounding = _rational_rounding_not_applicable("certificate replay benchmark")
        verify = _benchmark_verify_with_cache_modes(cert)
        verify.cache_seconds,
        (verify.accepted ?
         (status=BENCHMARK_EXPECTED_STATUS_CERTIFIED,
          message="candidate certificate accepted") :
         (status=BENCHMARK_EXPECTED_STATUS_REJECTED,
          message="candidate certificate rejected by verifier")),
        verify.uncached_seconds,
        verify.strict_seconds,
        verify.strict_accepted,
        verify.cache_hits,
        verify.cache_misses,
        _cache_speedup(verify.uncached_seconds, verify.cache_seconds),
        verify.profiler.slowest_stage,
        verify.profiler.slowest_stage_seconds,
        verify.consistent,
        _benchmark_certificate_metrics(cert;
                                       verify_seconds=verify.cache_seconds,
                                       validation_budget=validation_budget_label(budget),
                                       timeout_seconds=_benchmark_timeout_seconds(case,
                                                                                  budget)),
        rounding
    catch err
        seconds, result = _benchmark_timed() do
            return (status=BENCHMARK_EXPECTED_STATUS_REJECTED,
                    message="candidate certificate rejected while parsing: $(sprint(showerror, err))")
        end
        seconds,
        result,
        NaN,
        NaN,
        false,
        0,
        0,
        NaN,
        "-",
        NaN,
        true,
        _benchmark_empty_metrics(; verify_seconds=seconds,
                                 validation_budget=validation_budget_label(budget),
                                 timeout_seconds=_benchmark_timeout_seconds(case, budget)),
        _rational_rounding_not_applicable("candidate certificate rejected before coordinate rounding")
    end

    return _benchmark_row(case;
                          size=problem_size,
                          status=result.status,
                          cert_seconds=NaN,
                          verify_seconds,
                          verify_uncached_seconds=uncached_seconds,
                          strict_verify_seconds=strict_seconds,
                          strict_verify_accepted=strict_accepted,
                          verify_cache_hits=cache_hits,
                          verify_cache_misses=cache_misses,
                          verify_cache_speedup=cache_speedup,
                          slowest_verify_stage=slowest_stage,
                          slowest_verify_stage_seconds=slowest_stage_seconds,
                          verify_consistent=consistent,
                          cert_size=filesize(case.approx_path),
                          certificate_type="candidate",
                          metrics,
                          rounding_attempt=rounding,
                          message=result.message)
end

function _run_failure_boundary_benchmark(case, budget::ResourceBudget)
    problem_size = _benchmark_problem_size(case)
    parsed = _read_json_document(read(case.approx_path, String),
                                 "failure boundary report")
    _require_object(parsed, "root")
    boundary = haskey(parsed, :failure_report) ?
               _require_key(parsed, :failure_report, "root") : parsed
    _require_object(boundary, "failure_report")
    if haskey(boundary, :failure_type)
        observed_failure = _require_string(boundary, :failure_type,
                                           "failure_report.failure_type")
        observed_failure == case.expected.failure_type ||
            throw(ArgumentError("failure boundary expected $(case.expected.failure_type), got $observed_failure"))
    end
    message = haskey(boundary, :summary) ?
              _require_string(boundary, :summary, "failure_report.summary") :
              haskey(boundary, :message) ?
              _require_string(boundary, :message, "failure_report.message") :
              string(case.expected.failure_type, " structured boundary report")
    status = case.expected.failure_type == "BackendTimeoutFailure" ?
             BENCHMARK_STATUS_TIMEOUT : BENCHMARK_EXPECTED_STATUS_REJECTED
    seconds, _ = _benchmark_timed() do
        return true
    end
    return _benchmark_row(case;
                          size=problem_size,
                          status,
                          cert_seconds=seconds,
                          verify_seconds=NaN,
                          verify_uncached_seconds=NaN,
                          strict_verify_seconds=NaN,
                          strict_verify_accepted=false,
                          verify_cache_hits=0,
                          verify_cache_misses=0,
                          verify_cache_speedup=NaN,
                          slowest_verify_stage="-",
                          slowest_verify_stage_seconds=NaN,
                          verify_consistent=true,
                          cert_size=filesize(case.approx_path),
                          certificate_type="",
                          failure_type=case.expected.failure_type,
                          metrics=_benchmark_empty_metrics(; verify_seconds=NaN,
                                                           validation_budget=validation_budget_label(budget),
                                                           timeout_seconds=_benchmark_timeout_seconds(case,
                                                                                                      budget)),
                          rounding_attempt=_rational_rounding_not_applicable("failure-boundary fixture has no certifiable coordinate candidate"),
                          message)
end

function _benchmark_error_row(case, message::AbstractString, budget=nothing)
    budget_label = budget isa ResourceBudget ? validation_budget_label(budget) : "-"
    metrics = _benchmark_empty_metrics(; verify_seconds=NaN,
                                       validation_budget=budget_label,
                                       timeout_seconds=_benchmark_timeout_seconds(case,
                                                                                  budget))
    return _benchmark_row(case;
                          size=case.expected.size_hint == "" ? "-" :
                               case.expected.size_hint,
                          status=BENCHMARK_STATUS_ERROR,
                          cert_seconds=NaN,
                          verify_seconds=NaN,
                          verify_uncached_seconds=NaN,
                          strict_verify_seconds=NaN,
                          strict_verify_accepted=false,
                          verify_cache_hits=0,
                          verify_cache_misses=0,
                          verify_cache_speedup=NaN,
                          slowest_verify_stage="-",
                          slowest_verify_stage_seconds=NaN,
                          verify_consistent=true,
                          cert_size=0,
                          certificate_type="",
                          metrics,
                          rounding_attempt=_rational_rounding_not_applicable("benchmark case did not run"),
                          message)
end

function _benchmark_row(case;
                        size,
                        status,
                        cert_seconds,
                        verify_seconds,
                        verify_uncached_seconds=NaN,
                        strict_verify_seconds=verify_seconds,
                        strict_verify_accepted=false,
                        verify_cache_hits=0,
                        verify_cache_misses=0,
                        verify_cache_speedup=NaN,
                        slowest_verify_stage="-",
                        slowest_verify_stage_seconds=NaN,
                        verify_consistent=true,
                        cert_size,
                        certificate_type,
                        failure_type=case.expected.failure_type,
                        metrics=nothing,
                        rounding_attempt=_rational_rounding_not_applicable("benchmark did not perform coordinate rounding"),
                        solve_diagnostics=_benchmark_empty_solve_diagnostics(),
                        message)
    row_metrics = isnothing(metrics) ?
                  _benchmark_empty_metrics(; verify_seconds,
                                           validation_budget=String(DEFAULT_VALIDATION_BUDGET),
                                           timeout_seconds=case.expected.timeout_seconds) :
                  metrics
    elapsed = _benchmark_elapsed(cert_seconds, verify_seconds)
    max_time = _row_max_time_seconds(case, row_metrics.timeout_seconds)
    time_ok = isnothing(max_time) || isnan(elapsed) || elapsed <= max_time
    status_ok = status == case.expected.expected_status ||
                status == BENCHMARK_STATUS_SKIPPED
    strict_ok = status != BENCHMARK_EXPECTED_STATUS_CERTIFIED ||
                strict_verify_accepted === true
    passed = status_ok && time_ok && verify_consistent && strict_ok
    realism = status == BENCHMARK_STATUS_SKIPPED &&
              failure_type == "ResourceGuard" ?
              _resource_guard_realism_metrics(case) :
              _benchmark_realism_metrics(case;
                                         status,
                                         observed_rank=row_metrics.rank)
    row_message = String(message)
    time_ok || (row_message = string(row_message,
                                     "; exceeded max_time_seconds=", max_time))
    strict_ok || (row_message = string(row_message,
                                       "; strict verifier did not accept"))
    if realism.difficulty_class != case.expected.difficulty_class
        row_message = string(row_message, "; difficulty adjusted to ",
                             realism.difficulty_class, " by realism guard")
    end
    return (;
            instance=case.name,
            workflow=String(case.expected.workflow),
            category=case.expected.category,
            pack_level=String(case.expected.pack_level),
            benchmark_family=case.expected.benchmark_family,
            tier=String(case.expected.tier),
            size,
            variables=isnothing(case.expected.variable_count) ? "-" :
                      case.expected.variable_count,
            blocks=isnothing(case.expected.block_count) ? "-" :
                   case.expected.block_count,
            strategy=case.expected.strategy,
            backend=case.expected.backend,
            backend_requirement=case.expected.backend_requirement,
            certificate_origin=case.expected.certificate_origin,
            pipeline=case.expected.pipeline,
            rational_rounding_baseline=case.expected.rational_rounding_baseline,
            rounding_status=rounding_attempt.status,
            rounding_method=rounding_attempt.method,
            rounding_denominator_bound=rounding_attempt.denominator_bound,
            rounding_failure_reason=rounding_attempt.failure_reason,
            status,
            expected_status=case.expected.expected_status,
            expected_runtime_seconds=case.expected.expected_runtime_seconds,
            memory_expectation_mb=case.expected.memory_expectation_mb,
            cert_seconds,
            verify_seconds,
            verify_uncached_seconds,
            strict_verify_seconds,
            strict_verify_accepted,
            verify_cache_hits,
            verify_cache_misses,
            verify_cache_speedup,
            slowest_verify_stage,
            slowest_verify_stage_seconds,
            verify_consistent,
            cert_size,
            certificate_type,
            failure_type,
            effective_variables=realism.effective_variables,
            declared_variables=realism.declared_variables,
            affine_matrix_density=realism.affine_matrix_density,
            coefficient_bit_size_range=realism.coefficient_bit_size_range,
            nonzero_affine_matrices=realism.nonzero_affine_matrices,
            rank_profile=realism.rank_profile,
            block_variable_coupling=realism.block_variable_coupling,
            gram_offdiagonal_ratio=realism.gram_offdiagonal_ratio,
            construction_type=realism.construction_type,
            difficulty_class=realism.difficulty_class,
            scaling_family=case.expected.scaling_family,
            scale_index=case.expected.scale_index,
            seed=isnothing(case.expected.seed) ? "-" : case.expected.seed,
            solve_residual=solve_diagnostics.residual,
            solve_eigengap=solve_diagnostics.eigengap,
            solve_rank_confidence=solve_diagnostics.rank_confidence,
            selected_candidate=solve_diagnostics.selected_candidate,
            rank=isnothing(row_metrics.rank) ? case.expected.expected_rank :
                 row_metrics.rank,
            algebraic_degree=isnothing(row_metrics.algebraic_degree) ?
                             case.expected.algebraic_degree : row_metrics.algebraic_degree,
            certificate_report_type=row_metrics.certificate_type == "" ?
                                    certificate_type : row_metrics.certificate_type,
            validation_budget=row_metrics.validation_budget,
            timeout_seconds=row_metrics.timeout_seconds,
            source=case.expected.source,
            source_kind=case.expected.source_kind,
            max_time_seconds=max_time,
            passed,
            message=row_message)
end

function _benchmark_elapsed(cert_seconds, verify_seconds)
    total = 0.0
    saw_time = false
    for value in (cert_seconds, verify_seconds)
        if value isa Real && !isnan(value)
            total += Float64(value)
            saw_time = true
        end
    end
    return saw_time ? total : NaN
end

function _row_max_time_seconds(case, timeout_seconds)
    declared = case.expected.max_time_seconds
    timeout_seconds isa Real || return declared
    isnan(timeout_seconds) && return declared
    timeout = Float64(timeout_seconds)
    return isnothing(declared) ? timeout : min(Float64(declared), timeout)
end

function _benchmark_failure_status(failure::CertificationFailure)
    reason = get(failure.diagnostics, :backend_reason, nothing)
    reason === :timeout && return BENCHMARK_STATUS_TIMEOUT
    reason === :unavailable && return BENCHMARK_STATUS_BACKEND_UNAVAILABLE
    failure.reason === :validation_timeout && return BENCHMARK_STATUS_TIMEOUT
    return BENCHMARK_EXPECTED_STATUS_REJECTED
end

function _benchmark_failure_type(failure::CertificationFailure)
    return string(nameof(typeof(failure)))
end

function _benchmark_verify_with_cache_modes(cert)
    uncached = verify_timed(cert; io=nothing, cache=false)
    cached = verify_timed(cert; io=nothing, cache=true)
    strict_cached = verify_timed(cert; io=nothing, cache=true, strict=true)
    profiler = _benchmark_verifier_profile(cached.stats)
    return (;
            accepted=cached.accepted,
            cache_seconds=cached.seconds,
            uncached_seconds=uncached.seconds,
            strict_seconds=strict_cached.seconds,
            strict_accepted=strict_cached.accepted,
            cache_hits=cached.stats.hits,
            cache_misses=cached.stats.misses,
            consistent=cached.accepted == uncached.accepted &&
                       (!cached.accepted || strict_cached.accepted),
            cache_stats=cached.stats,
            profiler,)
end

function _benchmark_verifier_profile(stats)
    timings = stats.timings
    if isempty(timings)
        return (;
                slowest_stage="-",
                slowest_stage_seconds=NaN,
                timings=Dict{Symbol, Float64}(),)
    end
    pairs = collect(timings)
    index = argmax([Float64(value) for (_, value) in pairs])
    key, value = pairs[index]
    return (;
            slowest_stage=String(key),
            slowest_stage_seconds=Float64(value),
            timings=copy(timings),)
end

function _cache_speedup(uncached_seconds, cached_seconds)
    uncached_seconds isa Real || return NaN
    cached_seconds isa Real || return NaN
    isnan(uncached_seconds) && return NaN
    isnan(cached_seconds) && return NaN
    cached_seconds <= 0 && return NaN
    return Float64(uncached_seconds) / Float64(cached_seconds)
end

function _benchmark_empty_metrics(; verify_seconds, validation_budget, timeout_seconds)
    return (;
            certificate_type="",
            rank=nothing,
            algebraic_degree=nothing,
            verify_seconds,
            validation_budget,
            timeout_seconds,)
end

function _benchmark_certificate_metrics(cert; verify_seconds, validation_budget,
                                        timeout_seconds)
    return (;
            certificate_type=_benchmark_certificate_type(cert),
            rank=_benchmark_certificate_rank(cert),
            algebraic_degree=_benchmark_algebraic_degree(cert),
            verify_seconds,
            validation_budget,
            timeout_seconds,)
end

function _benchmark_empty_solve_diagnostics()
    return (;
            residual="-",
            eigengap="-",
            rank_confidence="-",
            selected_candidate="-",)
end

function _write_benchmark_failure_artifact(generated_dir::AbstractString, case,
                                           result::FailureResult)
    path = joinpath(generated_dir, case.name * "_failure.json")
    rm(path; force=true)
    write_failure_report(path, result)
    return path
end

function _benchmark_solve_diagnostics(approx, result)
    approx isa ApproxSolution || return _benchmark_empty_solve_diagnostics()
    report = approx.quality_report
    selected = if result isa CertifiedResult &&
                  result.certificate isa AlgebraicCertificate
        join((algebraic_element_string(value) for value in result.certificate.solution),
             ", ")
    else
        "-"
    end
    return (;
            residual=string(report.residual),
            eigengap=string(report.eigenvalue_gap),
            rank_confidence=String(report.rank_confidence),
            selected_candidate=selected,)
end

_benchmark_certificate_type(cert::RationalCertificate) = RATIONAL_CERTIFICATE_TYPE
function _benchmark_certificate_type(cert::BlockRationalCertificate)
    return BLOCK_RATIONAL_CERTIFICATE_TYPE
end
_benchmark_certificate_type(cert::AlgebraicCertificate) = ALGEBRAIC_CERTIFICATE_TYPE
_benchmark_certificate_type(cert::SOSGramCertificate) = SOS_GRAM_CERTIFICATE_TYPE
_benchmark_certificate_type(cert) = ""

function _benchmark_realism_metrics(case; status::AbstractString,
                                    observed_rank=nothing)
    defaults = _empty_realism_metrics(case;
                                      observed_rank,
                                      declared_variables=_declared_variables(case))
    try
        if case.expected.workflow === :sos_rational ||
           (case.expected.workflow === :verify_certificate &&
            occursin("sos", lowercase(case.expected.category)))
            problem = parse_sos_gram_json(read(case.problem_path, String))
            gram = isfile(case.approx_path) &&
                   case.expected.workflow === :sos_rational ?
                   _benchmark_read_sos_gram_matrix(case.approx_path, problem) :
                   nothing
            return _finalize_realism(case,
                                     _sos_realism_metrics(case, problem, gram;
                                                          observed_rank),
                                     status)
        end

        P = read_problem(case.problem_path)
        if P isa BlockLMIProblem
            return _finalize_realism(case,
                                     _block_lmi_realism_metrics(case, P;
                                                                observed_rank),
                                     status)
        elseif P isa LMIProblem
            return _finalize_realism(case,
                                     _lmi_realism_metrics(case, P;
                                                          observed_rank),
                                     status)
        end
    catch
        return _finalize_realism(case, defaults, status)
    end
    return _finalize_realism(case, defaults, status)
end

function _empty_realism_metrics(case; observed_rank=nothing,
                                declared_variables::Integer=0)
    return (;
            effective_variables=0,
            declared_variables,
            affine_matrix_density=0.0,
            coefficient_bit_size_range="-",
            nonzero_affine_matrices=0,
            rank_profile=isnothing(observed_rank) ? "-" : string(observed_rank),
            block_variable_coupling="-",
            gram_offdiagonal_ratio="-",
            construction_type=case.expected.construction_type,
            difficulty_class=case.expected.difficulty_class,)
end

function _lmi_realism_metrics(case, P::LMIProblem; observed_rank=nothing)
    matrices = vcat([P.A0], P.A)
    coeff_matrices = P.A
    return (;
            effective_variables=_effective_lmi_variables(coeff_matrices),
            declared_variables=num_variables(P),
            affine_matrix_density=_affine_matrix_density(matrices),
            coefficient_bit_size_range=_coefficient_bit_size_range(matrices),
            nonzero_affine_matrices=count(_matrix_has_nonzero, coeff_matrices),
            rank_profile=_rank_profile_label(case, observed_rank),
            block_variable_coupling="-",
            gram_offdiagonal_ratio="-",
            construction_type=case.expected.construction_type,
            difficulty_class=case.expected.difficulty_class,)
end

function _block_lmi_realism_metrics(case, P::BlockLMIProblem; observed_rank=nothing)
    matrices = SymmetricRationalMatrix[]
    coeff_matrices = SymmetricRationalMatrix[]
    for block in P.blocks
        push!(matrices, block.A0)
        append!(matrices, block.A)
        append!(coeff_matrices, block.A)
    end
    variable_block_counts = Int[]
    for var_index in 1:num_variables(P)
        push!(variable_block_counts,
              count(block -> _matrix_has_nonzero(block.A[var_index]), P.blocks))
    end
    coupled = count(>=(2), variable_block_counts)
    block_variable_coupling = num_variables(P) == 0 ? "0/0" :
                              string(coupled, "/", num_variables(P),
                                     " (", _percent(coupled,
                                                    num_variables(P)), ")")
    return (;
            effective_variables=count(>(0), variable_block_counts),
            declared_variables=num_variables(P),
            affine_matrix_density=_affine_matrix_density(matrices),
            coefficient_bit_size_range=_coefficient_bit_size_range(matrices),
            nonzero_affine_matrices=count(_matrix_has_nonzero, coeff_matrices),
            rank_profile=_rank_profile_label(case, observed_rank),
            block_variable_coupling,
            gram_offdiagonal_ratio="-",
            construction_type=case.expected.construction_type,
            difficulty_class=case.expected.difficulty_class,)
end

function _sos_realism_metrics(case, problem::SOSGramProblem, gram;
                              observed_rank=nothing)
    ratio = isnothing(gram) ? "-" : _gram_offdiagonal_ratio(gram)
    nonzero_terms = length(problem.polynomial)
    density = _sos_coefficient_density(problem)
    return (;
            effective_variables=_effective_sos_variables(problem),
            declared_variables=length(problem.variables),
            affine_matrix_density=density,
            coefficient_bit_size_range=_sos_coefficient_bit_size_range(problem),
            nonzero_affine_matrices=nonzero_terms,
            rank_profile=_rank_profile_label(case, observed_rank),
            block_variable_coupling="-",
            gram_offdiagonal_ratio=ratio,
            construction_type=case.expected.construction_type,
            difficulty_class=case.expected.difficulty_class,)
end

function _finalize_realism(case, metrics, status::AbstractString)
    difficulty = case.expected.difficulty_class
    if status != BENCHMARK_EXPECTED_STATUS_CERTIFIED
        difficulty = "expected_failure"
    end
    return merge(metrics, (; difficulty_class=difficulty))
end

function _declared_variables(case)
    isnothing(case.expected.variable_count) || return case.expected.variable_count
    return 0
end

function _effective_lmi_variables(coeff_matrices)
    return count(_matrix_has_nonzero, coeff_matrices)
end

function _effective_sos_variables(problem::SOSGramProblem)
    used = falses(length(problem.variables))
    for term in problem.polynomial
        for (i, exponent) in enumerate(term.exponents)
            exponent != 0 && (used[i] = true)
        end
    end
    return count(identity, used)
end

function _affine_matrix_density(matrices)
    total = 0
    nonzero = 0
    for matrix in matrices
        entries = rational_matrix(matrix)
        total += length(entries)
        nonzero += count(!iszero, entries)
    end
    total == 0 && return 0.0
    return nonzero / total
end

function _matrix_has_nonzero(matrix::SymmetricRationalMatrix)
    return any(!iszero, rational_matrix(matrix))
end

function _coefficient_bit_size_range(matrices)
    bits = Int[]
    for matrix in matrices
        for value in rational_matrix(matrix)
            iszero(value) && continue
            push!(bits, _rational_bit_size(value))
        end
    end
    isempty(bits) && return "0-0"
    return string(minimum(bits), "-", maximum(bits))
end

function _sos_coefficient_bit_size_range(problem::SOSGramProblem)
    bits = [_rational_bit_size(term.coefficient)
            for term in problem.polynomial
            if !iszero(term.coefficient)]
    isempty(bits) && return "0-0"
    return string(minimum(bits), "-", maximum(bits))
end

function _rational_bit_size(value::Rational)
    numerator_bits = ndigits(abs(BigInt(numerator(value))); base=2)
    denominator_bits = ndigits(abs(BigInt(denominator(value))); base=2)
    return max(numerator_bits, denominator_bits)
end

function _rank_profile_label(case, observed_rank)
    rank = isnothing(observed_rank) ? case.expected.expected_rank : observed_rank
    isnothing(rank) && return "-"
    return string("rank=", rank)
end

function _gram_offdiagonal_ratio(gram::SymmetricRationalMatrix)
    matrix = rational_matrix(gram)
    n = size(matrix, 1)
    total = 0
    nonzero = 0
    for i in 1:n, j in 1:n
        i == j && continue
        total += 1
        !iszero(matrix[i, j]) && (nonzero += 1)
    end
    total == 0 && return "0.00%"
    return _percent(nonzero, total)
end

function _sos_coefficient_density(problem::SOSGramProblem)
    isempty(problem.polynomial) && return 0.0
    return count(term -> !iszero(term.coefficient), problem.polynomial) /
           length(problem.polynomial)
end

function _effective_variable_rule_passes(effective::Integer, declared::Integer)
    declared <= 0 && return true
    threshold = declared <= 20 ? 0.60 : 0.40
    return effective >= ceil(Int, threshold * declared)
end

function _validation_shape_guard_passes(case, metrics)
    category = lowercase(case.expected.category)
    if occursin("multi", category) && occursin("block", category)
        coupled = _parse_coupled_variables(metrics.block_variable_coupling)
        construction = lowercase(metrics.construction_type)
        return case.expected.block_count >= 4 &&
               coupled >= ceil(Int, 0.50 * max(metrics.declared_variables, 1)) &&
               occursin("coupled", construction) &&
               (occursin("dense", construction) || occursin("rotated", construction)) &&
               (occursin("facial", construction) || occursin("rank", construction))
    elseif occursin("sos", category)
        ratio = _parse_percent(metrics.gram_offdiagonal_ratio)
        return ratio >= 15.0
    elseif occursin("algebraic", category)
        return metrics.effective_variables >= 1 &&
               case.expected.algebraic_degree >= 2
    end
    return true
end

function _parse_coupled_variables(text)
    found = match(r"^(\d+)/", string(text))
    isnothing(found) && return 0
    return parse(Int, found.captures[1])
end

function _parse_percent(text)
    found = match(r"([0-9]+(?:\.[0-9]+)?)%", string(text))
    isnothing(found) && return 0.0
    return parse(Float64, found.captures[1])
end

function _percent(numerator_value::Integer, denominator_value::Integer)
    denominator_value == 0 && return "0.00%"
    return string(round(100 * numerator_value / denominator_value; digits=2),
                  "%")
end

function _benchmark_certificate_rank(cert::RationalCertificate)
    return _benchmark_rational_matrix_rank(rational_matrix(cert.psd_proof.matrix))
end

function _benchmark_certificate_rank(cert::BlockRationalCertificate)
    return sum(_benchmark_rational_matrix_rank(rational_matrix(proof.matrix))
               for proof in cert.psd_proof.block_proofs)
end

function _benchmark_certificate_rank(cert::AlgebraicCertificate)
    if cert.psd_proof.method === Symbol(SCHUR_ZERO_PSD_METHOD) &&
       !isnothing(cert.psd_proof.schur_zero)
        return length(cert.psd_proof.schur_zero.pivot_block)
    elseif cert.psd_proof.method === Symbol(LDL_PSD_METHOD) &&
           !isnothing(cert.psd_proof.ldl)
        return count(pivot -> pivot.sign === :positive, cert.psd_proof.ldl.pivots)
    end
    return _benchmark_algebraic_matrix_rank(cert.psd_proof.matrix)
end

function _benchmark_certificate_rank(cert::SOSGramCertificate)
    return _benchmark_certificate_rank(cert.lmi_certificate)
end

_benchmark_certificate_rank(cert) = nothing

_benchmark_algebraic_degree(cert::AlgebraicCertificate) = degree(cert.root.f)
function _benchmark_algebraic_degree(cert::SOSGramCertificate)
    return _benchmark_algebraic_degree(cert.lmi_certificate)
end
_benchmark_algebraic_degree(cert) = 1

function _benchmark_rational_matrix_rank(matrix::AbstractMatrix{<:Rational})
    work = Rational{BigInt}[_to_big_rational(matrix[i, j]; name=:rank_entry)
                            for i in axes(matrix, 1), j in axes(matrix, 2)]
    rows, cols = size(work)
    rank = 0
    pivot_row = 1
    for col in 1:cols
        pivot = findfirst(row -> !iszero(work[row, col]), pivot_row:rows)
        isnothing(pivot) && continue
        pivot += pivot_row - 1
        if pivot != pivot_row
            work[[pivot_row, pivot], :] = work[[pivot, pivot_row], :]
        end
        pivot_value = work[pivot_row, col]
        for row in (pivot_row + 1):rows
            iszero(work[row, col]) && continue
            factor = work[row, col] / pivot_value
            for j in col:cols
                work[row, j] -= factor * work[pivot_row, j]
            end
        end
        rank += 1
        pivot_row += 1
        pivot_row > rows && break
    end
    return rank
end

function _benchmark_algebraic_matrix_rank(matrix::AbstractMatrix{AlgebraicElement})
    work = [matrix[i, j] for i in axes(matrix, 1), j in axes(matrix, 2)]
    rows, cols = size(work)
    rank = 0
    pivot_row = 1
    for col in 1:cols
        pivot = findfirst(row -> !iszero(work[row, col]), pivot_row:rows)
        isnothing(pivot) && continue
        pivot += pivot_row - 1
        if pivot != pivot_row
            work[[pivot_row, pivot], :] = work[[pivot, pivot_row], :]
        end
        pivot_value = work[pivot_row, col]
        for row in (pivot_row + 1):rows
            iszero(work[row, col]) && continue
            factor = work[row, col] / pivot_value
            for j in col:cols
                work[row, j] -= factor * work[pivot_row, j]
            end
        end
        rank += 1
        pivot_row += 1
        pivot_row > rows && break
    end
    return rank
end

function _benchmark_mismatches(rows)
    messages = String[]
    for row in rows
        row.status == BENCHMARK_STATUS_SKIPPED && continue
        row.status == row.expected_status ||
            push!(messages,
                  "$(row.instance): expected status $(row.expected_status), got $(row.status)")
        row.verify_consistent || push!(messages,
                                       "$(row.instance): cached and uncached verifier results differed")
        row.status == BENCHMARK_EXPECTED_STATUS_CERTIFIED &&
            row.strict_verify_accepted !== true &&
            push!(messages,
                  "$(row.instance): certified row did not pass strict verification")
        if !isnothing(row.max_time_seconds)
            elapsed = _benchmark_elapsed(row.cert_seconds, row.verify_seconds)
            if !isnan(elapsed) && elapsed > row.max_time_seconds
                push!(messages,
                      "$(row.instance): elapsed $(round(elapsed; digits=4))s exceeded max_time_seconds $(row.max_time_seconds)")
            end
        end
    end
    return messages
end

function _benchmark_read_rational_solution(path::AbstractString, P::LMIProblem)
    parsed = _read_json_document(read(path, String), "benchmark approximation")
    _require_object(parsed, "root")
    solution = _require_key(parsed, :solution, "root")
    return _parse_rational_solution(solution, num_variables(P))
end

function _benchmark_read_rational_solution(path::AbstractString, P::BlockLMIProblem)
    parsed = _read_json_document(read(path, String), "benchmark approximation")
    _require_object(parsed, "root")
    solution = _require_key(parsed, :solution, "root")
    return _parse_rational_solution(solution, num_variables(P))
end

function _benchmark_read_approx_solution(path::AbstractString, P::LMIProblem)
    parsed = _read_json_document(read(path, String), "benchmark approximation")
    _require_object(parsed, "root")
    approx = _require_key(parsed, :approximate_solution, "root")
    return _parse_approx_solution_object(P, approx;
                                         relative_tolerance=DEFAULT_RANK_RELATIVE_TOLERANCE,
                                         gap_threshold=DEFAULT_RANK_GAP_THRESHOLD)
end

function _benchmark_read_sos_gram_matrix(path::AbstractString, problem::SOSGramProblem)
    parsed = _read_json_document(read(path, String), "benchmark SOS approximation")
    _require_object(parsed, "root")
    solution = _require_key(parsed, :solution, "root")
    _require_object(solution, "solution")
    _require_value(solution, :type, SOS_GRAM_SOLUTION_TYPE, "solution.type")
    gram = _require_key(solution, :gram_matrix, "solution")
    return SymmetricRationalMatrix(_parse_rational_matrix(gram, length(problem.basis),
                                                          "solution.gram_matrix");
                                   name=:gram_matrix)
end

function _benchmark_read_solve_options(path::AbstractString)
    parsed = _read_json_document(read(path, String), "benchmark solve options")
    _require_object(parsed, "root")
    options = haskey(parsed, :solve_options) ?
              _require_key(parsed, :solve_options, "root") : parsed
    _require_object(options, "solve_options")

    solvers = if haskey(options, :solvers)
        raw = _require_key(options, :solvers, "solve_options")
        _require_array(raw, "solve_options.solvers")
        [Symbol(_json_string_value(solver, "solve_options.solvers[$i]"))
         for (i, solver) in enumerate(raw)]
    else
        [:clarabel]
    end
    random_objective_trials = haskey(options, :random_objective_trials) ?
                              Int(_require_number(options,
                                                  :random_objective_trials,
                                                  "solve_options.random_objective_trials")) :
                              0
    random_objective_trials >= 0 ||
        throw(ArgumentError("solve_options.random_objective_trials must be nonnegative"))
    trace_objective = haskey(options, :trace_objective) ?
                      _parse_trace_objective(_require_key(options,
                                                          :trace_objective,
                                                          "solve_options")) :
                      true
    solver_attempts = haskey(options, :solver_attempts) ?
                      Int(_require_number(options, :solver_attempts,
                                          "solve_options.solver_attempts")) :
                      1
    solver_attempts > 0 ||
        throw(ArgumentError("solve_options.solver_attempts must be positive"))
    solver_retry_policy = haskey(options, :solver_retry_policy) ?
                          Symbol(_require_string(options,
                                                 :solver_retry_policy,
                                                 "solve_options.solver_retry_policy")) :
                          :default
    precision_bits = haskey(options, :precision_bits) ?
                     Int(_require_number(options, :precision_bits,
                                         "solve_options.precision_bits")) :
                     DEFAULT_APPROX_PRECISION_BITS
    precision_bits > 0 ||
        throw(ArgumentError("solve_options.precision_bits must be positive"))
    random_seed = haskey(options, :random_seed) ?
                  Int(_require_number(options, :random_seed,
                                      "solve_options.random_seed")) :
                  0
    require_stable_rank = haskey(options, :require_stable_rank) ?
                          _parse_json_bool(_require_key(options,
                                                        :require_stable_rank,
                                                        "solve_options"),
                                           "solve_options.require_stable_rank") :
                          false
    clarabel_max_iter = haskey(options, :clarabel_max_iter) ?
                        Int(_require_number(options, :clarabel_max_iter,
                                            "solve_options.clarabel_max_iter")) :
                        200
    clarabel_max_iter > 0 ||
        throw(ArgumentError("solve_options.clarabel_max_iter must be positive"))

    return (;
            solvers,
            random_objective_trials,
            trace_objective,
            solver_attempts,
            solver_retry_policy,
            precision_bits,
            random_seed,
            require_stable_rank,
            clarabel_max_iter,)
end

function _parse_mixed_block_algebraic_solution(parsed, P::BlockLMIProblem)
    solution = haskey(parsed, :algebraic_solution) ?
               _require_key(parsed, :algebraic_solution, "root") :
               _require_key(parsed, :solution, "root")
    _require_object(solution, "algebraic_solution")
    if haskey(solution, :type)
        _require_value(solution, :type, ALGEBRAIC_SOLUTION_TYPE,
                       "algebraic_solution.type")
    end

    f = parse_polynomial(_require_string(solution, :minimal_polynomial,
                                         "algebraic_solution.minimal_polynomial"))
    interval_value = _require_key(solution, :root_interval, "algebraic_solution")
    _require_array(interval_value, "algebraic_solution.root_interval")
    length(interval_value) == 2 ||
        throw(ArgumentError("algebraic_solution.root_interval must contain two endpoints"))
    root = AlgebraicRoot(f,
                         RationalInterval(_parse_rational_string(interval_value[1],
                                                                 "algebraic_solution.root_interval[1]"),
                                          _parse_rational_string(interval_value[2],
                                                                 "algebraic_solution.root_interval[2]")))

    coordinates = _require_key(solution, :coordinates, "algebraic_solution")
    _require_object(coordinates, "algebraic_solution.coordinates")
    values = AlgebraicElement[]
    for var in P.vars
        key = Symbol(String(var))
        haskey(coordinates, key) ||
            throw(ArgumentError("algebraic_solution.coordinates is missing variable `$(String(var))`"))
        push!(values,
              AlgebraicElement(root,
                               _require_string(coordinates, key,
                                               "algebraic_solution.coordinates.$(String(var))")))
    end
    return root, values
end

function _parse_mixed_rounding_xhat(value)
    _require_array(value, "root.rounding_xhat")
    result = BigFloat[]
    for (i, entry) in enumerate(value)
        entry isa AbstractString ||
            throw(ArgumentError("root.rounding_xhat[$i] must be a decimal string"))
        push!(result, parse(BigFloat, String(entry)))
    end
    return result
end

function _parse_mixed_block_specs(value, expected_blocks::Integer)
    _require_array(value, "root.block_proofs")
    length(value) == expected_blocks ||
        throw(ArgumentError("root.block_proofs has length $(length(value)); expected $expected_blocks"))
    specs = NamedTuple[]
    for (i, entry) in enumerate(value)
        _require_object(entry, "root.block_proofs[$i]")
        field = _require_string(entry, :field, "root.block_proofs[$i].field")
        method = _require_string(entry, :method, "root.block_proofs[$i].method")
        pivot_block = if haskey(entry, :pivot_block)
            pivot_value = _require_key(entry, :pivot_block, "root.block_proofs[$i]")
            if isnothing(pivot_value)
                nothing
            else
                _require_array(pivot_value, "root.block_proofs[$i].pivot_block")
                Int[Int(index) for index in pivot_value]
            end
        else
            nothing
        end
        push!(specs, (; field, method, pivot_block))
    end
    return specs
end

function _mixed_block_is_solution_independent(block::LMIProblem)
    return all(matrix -> all(iszero, rational_matrix(matrix)), block.A)
end

function _benchmark_problem_size(case)
    workflow = case.expected.workflow
    if workflow === :sos_rational ||
       (workflow === :verify_certificate &&
        case.expected.category == "negative_fake_cert_sos")
        problem = parse_sos_gram_json(read(case.problem_path, String))
        return _benchmark_sos_size(problem)
    end

    P = read_problem(case.problem_path)
    P isa BlockLMIProblem && return _benchmark_block_lmi_size(P)
    P isa LMIProblem && return _benchmark_lmi_size(P)
    return case.expected.size_hint == "" ? "-" : case.expected.size_hint
end

function _benchmark_lmi_size(P::LMIProblem)
    return string(matrix_size(P), "x", matrix_size(P), ", n=", num_variables(P))
end

function _benchmark_lmi_size(P::BlockLMIProblem)
    return _benchmark_block_lmi_size(P)
end

function _benchmark_block_lmi_size(P::BlockLMIProblem)
    return string("blocks=", num_blocks(P),
                  ", dims=", join(block_sizes(P), "+"),
                  " (total=", matrix_size(P), "), n=", num_variables(P))
end

function _benchmark_sos_size(problem::SOSGramProblem)
    return string("basis=", length(problem.basis),
                  ", vars=", length(problem.variables),
                  ", terms=", length(problem.polynomial))
end

function _benchmark_timed(f::Function)
    start = time_ns()
    result = f()
    return (time_ns() - start) / 1.0e9, result
end

function _run_jump_moi_extraction_script(source_path::AbstractString,
                                         output_dir::AbstractString)
    repo_root = normpath(joinpath(@__DIR__, "..", ".."))
    source_abs = abspath(source_path)
    source_rel = relpath(source_abs, repo_root)
    (source_rel == "." ||
     !(source_rel == ".." ||
       startswith(source_rel, string("..", Base.Filesystem.path_separator)))) ||
        return (;
                status=BENCHMARK_STATUS_BACKEND_UNAVAILABLE,
                failure_type="BackendFailure",
                message="refusing to execute benchmark source outside this repository; source fixtures are trusted repo-local code, not a sandboxed external benchmark interface")
    project_dir = joinpath(repo_root, "examples", "jump")
    if !isfile(joinpath(project_dir, "Project.toml"))
        return (;
                status=BENCHMARK_STATUS_BACKEND_UNAVAILABLE,
                failure_type="BackendFailure",
                message="examples/jump Project.toml is unavailable for JuMP/MOI extraction")
    end

    project_workdir = mktempdir()
    cp(joinpath(project_dir, "Project.toml"),
       joinpath(project_workdir, "Project.toml"))
    setup = """
    using Pkg
    Pkg.develop(Pkg.PackageSpec(path=$(repr(repo_root))))
    Pkg.instantiate()
    include($(repr(source_path)))
    main(ARGS)
    """
    command = Cmd(`$(Base.julia_cmd()) --project=$project_workdir -e $setup $output_dir`;
                  dir=repo_root)
    output = IOBuffer()
    process = try
        run(pipeline(command; stdout=output, stderr=output); wait=false)
    catch err
        return (;
                status=BENCHMARK_STATUS_BACKEND_UNAVAILABLE,
                failure_type="BackendFailure",
                message="could not start JuMP/MOI extraction: $(sprint(showerror, err))")
    end

    timed_out = false
    timeout = 300.0
    start = time()
    while process_running(process)
        if time() - start > timeout
            timed_out = true
            try
                kill(process)
            catch
            end
            break
        end
        sleep(0.1)
    end
    process_ok = !timed_out && success(process)
    text = String(take!(output))
    if timed_out
        return (;
                status=BENCHMARK_STATUS_TIMEOUT,
                failure_type="BackendTimeoutFailure",
                message="JuMP/MOI extraction exceeded $(timeout)s; output: $(strip(text))")
    elseif !process_ok
        return (;
                status=BENCHMARK_STATUS_BACKEND_UNAVAILABLE,
                failure_type="BackendFailure",
                message="JuMP/MOI extraction failed; output: $(strip(text))")
    end

    problem_path = joinpath(output_dir, "problem.json")
    approx_path = joinpath(output_dir, "approx.json")
    manifest_path = joinpath(output_dir, "extraction_manifest.json")
    missing = [path for path in (problem_path, approx_path, manifest_path)
               if !isfile(path)]
    if !isempty(missing)
        return (;
                status=BENCHMARK_STATUS_ERROR,
                failure_type="ExtractionArtifactMissing",
                message="JuMP/MOI extraction did not emit required artifacts: $(join(basename.(missing), ", "))")
    end
    return (;
            status=BENCHMARK_EXPECTED_STATUS_CERTIFIED,
            failure_type="",
            message=strip(text) == "" ? "JuMP/MOI extraction completed" :
                    strip(text))
end

function _rational_rounding_not_applicable(reason::AbstractString)
    return (;
            status="not_applicable",
            method="not_applicable",
            denominator_bound=0,
            candidate="",
            failure_reason=String(reason),)
end

function _rational_rounding_attempt(P,
                                    candidate;
                                    denominator_bound::Integer,
                                    source::Symbol)
    method = "bounded_denominator_coordinate_rounding"
    denominator_bound > 0 ||
        return (;
                status="failed",
                method,
                denominator_bound,
                candidate="",
                failure_reason="denominator bound must be positive",)

    rounded = try
        _rounding_candidate_vector(candidate, denominator_bound)
    catch err
        return (;
                status="failed",
                method,
                denominator_bound,
                candidate="",
                failure_reason=sprint(showerror, err),)
    end

    certificate = try
        RationalCertificate(P, rounded; psd_method=:auto)
    catch err
        return (;
                status="failed",
                method,
                denominator_bound,
                candidate=_rounding_candidate_string(rounded),
                failure_reason=sprint(showerror, err),)
    end

    accepted = try
        verify(certificate; io=nothing)
    catch err
        return (;
                status="failed",
                method,
                denominator_bound,
                candidate=_rounding_candidate_string(rounded),
                failure_reason="rounded candidate exact replay errored: $(sprint(showerror, err))",)
    end

    return (;
            status=accepted ? "success" : "failed",
            method,
            denominator_bound,
            candidate=_rounding_candidate_string(rounded),
            failure_reason=accepted ? "" :
                           "rounded candidate did not pass exact certificate verification",)
end

function _rounding_candidate_vector(x::AbstractVector, denominator_bound::Integer)
    return Rational{BigInt}[_bounded_denominator_rational(value,
                                                          denominator_bound)
                            for value in x]
end

function _rounding_candidate_vector(approx::ApproxSolution, denominator_bound::Integer)
    return _rounding_candidate_vector(approx.xhat, denominator_bound)
end

function _bounded_denominator_rational(value::Integer, denominator_bound::Integer)
    return Rational{BigInt}(BigInt(value), BigInt(1))
end

function _bounded_denominator_rational(value::Rational, denominator_bound::Integer)
    q = Rational{BigInt}(BigInt(numerator(value)), BigInt(denominator(value)))
    denominator(q) <= denominator_bound ||
        throw(ArgumentError("exact rational denominator $(denominator(q)) exceeds bound $denominator_bound"))
    return q
end

function _bounded_denominator_rational(value, denominator_bound::Integer)
    x = BigFloat(value)
    best = Rational{BigInt}(round(BigInt, x), BigInt(1))
    best_error = abs(x - BigFloat(numerator(best)) / BigFloat(denominator(best)))
    for q in 1:denominator_bound
        q_big = BigInt(q)
        p = round(BigInt, x * BigFloat(q_big))
        candidate = Rational{BigInt}(p, q_big)
        error = abs(x - BigFloat(numerator(candidate)) / BigFloat(denominator(candidate)))
        if error < best_error ||
           (error == best_error && denominator(candidate) < denominator(best))
            best = candidate
            best_error = error
        end
    end
    return best
end

function _rounding_candidate_string(values::AbstractVector{<:Rational})
    return join((_rational_string(value) for value in values), ", ")
end

function _json_string_value(value, path::AbstractString)
    value isa AbstractString || throw(ArgumentError("$path must be a string"))
    return String(value)
end

function _parse_json_bool(value, path::AbstractString)
    value isa Bool && return Bool(value)
    throw(ArgumentError("$path must be a boolean"))
end

function _parse_trace_objective(value)
    value isa Bool && return Bool(value)
    value isa AbstractString && return Symbol(value)
    throw(ArgumentError("solve_options.trace_objective must be a boolean or string"))
end

function _write_benchmark_report(path::AbstractString, rows; subset::Symbol,
                                 suite_root::AbstractString)
    suite_level = _public_suite_level(subset, suite_root, rows)
    open(path, "w") do io
        println(io, "# CertSDP v1.0 ", _suite_title(suite_level), " Report")
        println(io)
        println(io, "- Suite: `", suite_root, "`")
        println(io, "- Public suite: `", suite_level, "`")
        println(io, "- Instances: ", length(rows))
        println(io, "- Status: ", all(row.passed for row in rows) ? "passed" : "failed")
        println(io, "- Machine metadata: CPU=", _benchmark_cpu_label(),
                "; RAM=", _benchmark_memory_label(), "; OS=", Sys.KERNEL,
                "; Julia=", VERSION)
        println(io, "- Validation budget: ", _validation_budget_summary(rows))
        println(io)
        _write_validation_report_summary(io, rows)

        println(io)
        println(io, "## Cases")
        println(io)
        _write_public_benchmark_table(io, rows)
        println(io)
        println(io, "## Notes")
        println(io)
        println(io,
                "The validation suite is a reproducible evidence contract for the supported certificate families, not a numerical SDP benchmark.")
        println(io,
                "A row fails when `expected.json` status differs from the observed status.")
        println(io,
                "Certified rows must pass strict verification. Strict verification is exact replay only: it does not use msolve, numerical solver output, or backend artifacts.")
        println(io,
                "Verifier timing is measured twice per parsed certificate: cache disabled, then scoped exact-operation cache enabled. A row fails if those acceptance results differ.")
        println(io,
                "Numerical solver and algebraic backend outputs are used only to construct candidates; acceptance still comes from exact verification.")
        println(io,
                "Rational rounding is an actual bounded-denominator coordinate rounding attempt. The report records method, denominator bound, status, and exact verifier failure reason when it fails.")
        failures = filter(row -> !row.passed, rows)
        if !isempty(failures)
            println(io)
            println(io, "## Mismatches")
            println(io)
            for row in failures
                println(io, "- `", row.instance, "` expected `", row.expected_status,
                        "` but observed `", row.status, "`: ", row.message)
            end
        end
    end
    return path
end

function _public_suite_level(subset::Symbol, suite_root::AbstractString, rows)
    return :validation
end

_suite_title(level::Symbol) = "Validation"

function _write_validation_report_summary(io::IO, rows)
    println(io, "## Executive Summary")
    println(io)
    println(io,
            "CertSDP.jl is an exact replay layer for SDP/SOS certificate workflows. The validation suite checks exact replay obligations, certificate generation, imported workflows, adversarial rejection, and structured failure reporting.")
    println(io)
    println(io, "## Replay Evidence At A Glance")
    println(io)
    _write_replay_evidence_at_a_glance(io, rows)
    println(io)
    println(io, "## Evidence By Workflow Family")
    println(io)
    _write_evidence_summary_table(io, rows)
    println(io)
    println(io, "## Paper Artifact Coverage")
    println(io)
    _write_paper_artifact_coverage(io, rows)
    println(io)
    println(io, "## Adversarial Mutation Matrix")
    println(io)
    _write_adversarial_mutation_matrix(io, rows)
    println(io)
    println(io, "## Raw Artifacts And Archival Status")
    println(io)
    _write_raw_artifact_status(io, rows)
    println(io)
    println(io, "## Verification Footprint")
    println(io)
    _write_verification_footprint(io, rows)
    println(io)
    println(io, "## Slowest Validation Cases")
    println(io)
    _write_slowest_validation_cases(io, rows)
    println(io)
    println(io, "## Failure Diagnostics Summary")
    println(io)
    _write_failure_diagnostics_summary(io, rows)
    return nothing
end

function _write_extended_validation_summary(io::IO, rows)
    println(io, "## Extended Validation Summary")
    println(io)
    println(io,
            "- Certified rows are counted only after strict exact replay accepts them.")
    println(io)
    _write_boundary_summary_table(io, rows)
    println(io)
    println(io, "## Certified")
    println(io)
    _write_status_instances(io, rows, BENCHMARK_EXPECTED_STATUS_CERTIFIED)
    println(io)
    println(io, "## Rejected")
    println(io)
    _write_status_instances(io, rows, BENCHMARK_EXPECTED_STATUS_REJECTED)
    println(io)
    println(io, "## Timeouts")
    println(io)
    _write_status_instances(io, rows, BENCHMARK_STATUS_TIMEOUT)
    println(io)
    println(io, "## Skipped Cases")
    println(io)
    _write_status_instances(io, rows, BENCHMARK_STATUS_SKIPPED)
    println(io)
    println(io, "## Foundational Cases")
    println(io)
    _write_difficulty_instances(io, rows, "foundational")
    println(io)
    println(io, "## Memory Expectation")
    println(io)
    println(io, _memory_expectation_summary(rows))
    println(io)
    println(io, "## Backend Bottleneck")
    println(io)
    _write_backend_bottleneck_summary(io, rows)
    println(io)
    println(io, "## Structured Failure Summary")
    println(io)
    _write_failure_diagnostics_summary(io, rows)
    println(io)
    println(io, "## Algebraic Pipeline Highlights")
    println(io)
    _write_algebraic_pipeline_boundaries(io, rows)
    println(io)
    println(io, "## Algebraic Certifier-Generated Success Boundary")
    println(io)
    _write_algebraic_certifier_success_boundary(io, rows)
    println(io)
    println(io, "## Imported Workflow Highlights")
    println(io)
    _write_imported_workflow_highlights(io, rows)
    println(io)
    println(io, "## Non-SDPA Imported Workflow Highlight")
    println(io)
    _write_non_sdpa_imported_workflow_highlight(io, rows)
    return nothing
end

function _status_count(rows, status::AbstractString)
    return count(row -> row.status == status, rows)
end

function _rounding_failures_certified(rows)
    return count(row -> row.rounding_status == "failed" &&
                     row.status == BENCHMARK_EXPECTED_STATUS_CERTIFIED, rows)
end

function _solve_diagnose_certify_passed(rows)
    return count(row -> row.workflow == "lmi_solve_certify" &&
                            row.status == BENCHMARK_EXPECTED_STATUS_CERTIFIED &&
                            row.passed, rows)
end

function _benchmark_cpu_label()
    try
        info = Sys.cpu_info()
        isempty(info) && return "unknown"
        return string(length(info), " threads ", info[1].model)
    catch
        return "unknown"
    end
end

function _benchmark_memory_label()
    try
        bytes = Sys.total_memory()
        return string(round(bytes / 1024^3; digits=2), " GiB")
    catch
        return "unknown"
    end
end

function _write_largest_row(io::IO, rows, predicate::Function, size_function::Function)
    candidates = filter(predicate, rows)
    if isempty(candidates)
        println(io, "None")
        return nothing
    end
    row = candidates[argmax([size_function(candidate) for candidate in candidates])]
    println(io, "- Instance: `", row.instance, "`")
    println(io, "- Size: ", row.size)
    println(io, "- Certificate: ", row.certificate_report_type)
    println(io, "- Strict verify time: ",
            _benchmark_format_seconds(row.strict_verify_seconds))
    println(io, "- Certificate size: ", _benchmark_format_bytes(row.cert_size))
    return nothing
end

function _write_largest_by_category(io::IO, rows)
    isempty(rows) && begin
        println(io, "None")
        return nothing
    end
    for category in sort(unique(row.category for row in rows))
        category_rows = filter(row -> row.category == category, rows)
        row = category_rows[argmax([_row_general_size(candidate)
                                    for candidate in category_rows])]
        println(io, "- ", category, ": `", row.instance, "` (", row.size,
                ", status=", row.status,
                row.failure_type == "" ? "" : string(", failure=", row.failure_type),
                ")")
    end
    return nothing
end

function _write_evidence_summary_table(io::IO, rows)
    println(io,
            "| Evidence Family | Certified | Rejected | Strict Verified | Rounding Failures Certified | Backend | Representative Case | Notes |")
    println(io,
            "| --- | ---: | ---: | ---: | ---: | --- | --- | --- |")
    families = sort(unique(row.scaling_family for row in rows))
    for family in families
        family_rows = filter(row -> row.scaling_family == family, rows)
        certified = filter(row -> row.status == BENCHMARK_EXPECTED_STATUS_CERTIFIED &&
                               row.passed, family_rows)
        rejected = filter(row -> row.status != BENCHMARK_EXPECTED_STATUS_CERTIFIED &&
                              row.passed, family_rows)
        strict_verified = count(row -> row.strict_verify_accepted === true,
                                certified)
        rounding_failures = count(row -> row.rounding_status == "failed",
                                  certified)
        representative = isempty(certified) ? first(family_rows) :
                         certified[argmax([_row_general_size(row)
                                           for row in certified])]
        backends = sort(unique(row.backend for row in family_rows))
        notes = _evidence_family_notes(family_rows, representative)
        println(io, "| ",
                join([_markdown_cell(family),
                      string(length(certified)),
                      string(length(rejected)),
                      string(strict_verified),
                      string(rounding_failures),
                      _markdown_cell(join(backends, ",")),
                      _markdown_cell(string(representative.instance, " (",
                                            representative.size, ")")),
                      _markdown_cell(notes)], " | "),
                " |")
    end
    return nothing
end

function _write_paper_artifact_coverage(io::IO, rows)
    println(io,
            "| Evidence Class | Representative Rows | Evidence Meaning |")
    println(io,
            "| --- | --- | --- |")
    entries = [("Paper-derived degenerate SDP mechanism",
                row -> occursin("algebraic", lowercase(row.scaling_family)) ||
                    row.category == "irrational",
                "Exercises incidence-style algebraic certification, exact root replay, and rational rounding failure."),
               ("SDPA/SDPLIB-style imported SDP",
                row -> row.source_kind == "sdpa_import" ||
                    row.scaling_family in ("multi_block", "multi_block_sdp"),
                "Covers sparse block SDP import and blockwise exact PSD replay."),
               ("SumOfSquares-style SOS workflow",
                row -> row.scaling_family == "SOS" ||
                    row.source_kind == "sumofsquares_extract",
                "Covers exact Gram coefficient matching, non-diagonal Gram replay, and SOS export paths."),
               ("Full numerical-to-exact workflow",
                row -> row.pipeline == "solve_diagnose_certify",
                "Separates numerical solve, diagnosis, certification, and strict exact verification."),
               ("Negative controls",
                row -> row.status != BENCHMARK_EXPECTED_STATUS_CERTIFIED,
                "Confirms fake certificates and invalid candidates are rejected with structured diagnostics.")]
    for (label, predicate, meaning) in entries
        representatives = _representative_instances(rows, predicate; limit=3)
        println(io, "| ",
                join([_markdown_cell(label),
                      _markdown_cell(representatives),
                      _markdown_cell(meaning)], " | "),
                " |")
    end
    return nothing
end

function _write_adversarial_mutation_matrix(io::IO, rows)
    rational = _representative_instances(rows,
                                         row -> row.scaling_family ==
                                                "negative_fake_cert";
                                         limit=1)
    sos = _representative_instances(rows,
                                    row -> row.scaling_family ==
                                           "negative_fake_cert_sos";
                                    limit=1)
    invalid = _representative_instances(rows,
                                        row -> row.scaling_family ==
                                               "numerical_oracle" &&
                                            row.status !=
                                            BENCHMARK_EXPECTED_STATUS_CERTIFIED;
                                        limit=1)
    println(io,
            "| Mutation Surface | Visible Validation Row | Deeper Gate |")
    println(io,
            "| --- | --- | --- |")
    matrix = [("Problem/certificate hash",
               rational,
               "Strict verifier recomputes hashes before replay."),
              ("Rational coordinates, substituted matrix, minors, pivots",
               rational,
               "Adversarial tests mutate coordinates, matrices, determinants, LDL pivots, and Schur data."),
              ("Algebraic minimal polynomial, root interval, signs",
               "algebraic validation rows",
               "Adversarial tests mutate root data and exact algebraic proof claims."),
              ("SOS coefficient matching and Gram PSD proof",
               sos,
               "SOS tests mutate coefficient tables, Gram entries, and embedded PSD certificates."),
              ("Invalid approximation / candidate quality",
               invalid,
               "Numerical diagnostics reject infeasible approximate candidates before proof acceptance.")]
    for (surface, visible, gate) in matrix
        println(io, "| ",
                join([_markdown_cell(surface),
                      _markdown_cell(visible),
                      _markdown_cell(gate)], " | "),
                " |")
    end
    return nothing
end

function _write_raw_artifact_status(io::IO, rows)
    generated = count(row -> row.cert_size isa Integer && row.cert_size > 0,
                      rows)
    println(io,
            "| Artifact | Location Or Command | Status |")
    println(io,
            "| --- | --- | --- |")
    artifacts = [("Tracked validation report",
                  "benchmarks/VALIDATION_REPORT.md",
                  "Generated by `certsdp benchmark`; this file records the current public evidence table."),
                 ("Raw generated certificates and failures",
                  "`--generated-dir benchmarks/generated`",
                  string(generated,
                         " reproducible row artifacts in this run; directory is ignored by git.")),
                 ("Replay bundle",
                  "`bin/certsdp bundle cert.json --out artifact.zip`",
                  "Data-only ZIP with strict replay report and redacted sidecar metadata."),
                 ("Archival DOI",
                  "CITATION.cff and codemeta.json",
                  "Pending until a public tagged archive is deposited and a DOI is minted.")]
    for (artifact, location, status) in artifacts
        println(io, "| ",
                join([_markdown_cell(artifact),
                      _markdown_cell(location),
                      _markdown_cell(status)], " | "),
                " |")
    end
    return nothing
end

function _write_replay_evidence_at_a_glance(io::IO, rows)
    certified = count(row -> row.status == BENCHMARK_EXPECTED_STATUS_CERTIFIED &&
                          row.passed, rows)
    rejected = count(row -> row.status != BENCHMARK_EXPECTED_STATUS_CERTIFIED &&
                         row.passed, rows)
    strict_verified = count(row -> row.strict_verify_accepted === true &&
                                row.status == BENCHMARK_EXPECTED_STATUS_CERTIFIED,
                            rows)
    rounding_failures = _rounding_failures_certified(rows)
    solve_pipelines = _solve_diagnose_certify_passed(rows)
    timing = _strict_timing_summary(rows)
    sizes = _certificate_size_summary(rows)

    println(io,
            "| Reader Question | Current Evidence | Why It Matters |")
    println(io,
            "| --- | --- | --- |")
    entries = [("Did accepted certificates replay exactly?",
                string(strict_verified, " / ", certified,
                       " certified rows passed strict replay."),
                "Acceptance is by verifier replay, not solver status."),
               ("Does validation include rejection evidence?",
                string(rejected, " expected rejection/failure rows passed."),
                "Fake certificates and invalid candidates are part of the contract."),
               ("Does the algebraic path cover rational-rounding failure?",
                string(rounding_failures,
                       " certified rows failed bounded rational rounding first."),
                "This is the motivating degenerate SDP/SOS risk."),
               ("Is the full numerical-to-exact path exercised?",
                string(solve_pipelines,
                       " solve -> diagnose -> certify workflow passed."),
                "The report separates candidate generation from strict verification."),
               ("What is the strict verifier runtime envelope?",
                timing,
                "Local timing only; useful as an audit baseline, not a solver benchmark."),
               ("How large are replay artifacts?",
                sizes,
                "Certificate size sets expectations for archived JSON artifacts.")]
    for (question, evidence, meaning) in entries
        println(io, "| ",
                join([_markdown_cell(question),
                      _markdown_cell(evidence),
                      _markdown_cell(meaning)], " | "),
                " |")
    end
    return nothing
end

function _write_verification_footprint(io::IO, rows)
    println(io,
            "| Metric | Current Value | Interpretation |")
    println(io,
            "| --- | --- | --- |")
    entries = [("Strict verifier timings",
                _strict_timing_summary(rows),
                "Measured for certified rows during exact replay."),
               ("Cache consistency",
                _cache_comparison_summary(rows),
                "Cache-on and cache-off acceptance must agree."),
               ("Certificate sizes",
                _certificate_size_summary(rows),
                "Size of generated or replayed certificate artifacts.")]
    for (metric, value, interpretation) in entries
        println(io, "| ",
                join([_markdown_cell(metric),
                      _markdown_cell(value),
                      _markdown_cell(interpretation)], " | "),
                " |")
    end
    return nothing
end

function _representative_instances(rows, predicate::Function; limit::Integer=3)
    selected = filter(predicate, rows)
    isempty(selected) && return "not present"
    ordered = sort(selected; by=row -> _row_general_size(row), rev=true)
    names = [string("`", row.instance, "`")
             for row in Iterators.take(ordered, limit)]
    return join(names, ", ")
end

function _write_boundary_summary_table(io::IO, rows)
    return _write_evidence_summary_table(io, rows)
end

function _write_boundary_override_results(io::IO, rows)
    forced = filter(row -> row.forced_boundary_attempt, rows)
    isempty(forced) && begin
        println(io, "No forced boundary attempts in this run.")
        return nothing
    end
    println(io,
            "| Case | Previous Status | Forced Attempt Result | Failure Type If Any | Cert Time | Strict Verify Time | Cert Size | Memory Expectation | Notes |")
    println(io,
            "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- |")
    for row in forced
        println(io, "| ",
                join([_markdown_cell(row.instance),
                      _markdown_cell(row.previous_status),
                      _markdown_cell(row.status),
                      _markdown_cell(row.failure_type == "" ? "-" : row.failure_type),
                      _benchmark_format_seconds(row.cert_seconds),
                      _benchmark_format_seconds(row.strict_verify_seconds),
                      _benchmark_format_bytes(row.cert_size),
                      _benchmark_format_memory(row.memory_expectation_mb),
                      _markdown_cell(row.message)], " | "),
                " |")
    end
    return nothing
end

function _write_algebraic_pipeline_boundaries(io::IO, rows)
    algebraic = filter(row -> occursin("algebraic", lowercase(row.category)) &&
                           row.status == BENCHMARK_EXPECTED_STATUS_CERTIFIED,
                       rows)
    println(io,
            "| Highlight | Instance | Size | Degree | Certificate Origin | Pipeline | Rational Rounding | Cert Time | Strict Verify Time | Cert Size | Notes |")
    println(io,
            "| --- | --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: | --- |")
    specs = [("Largest verified algebraic certificate",
              row -> row.certificate_origin == "direct_fixture" &&
                  row.pipeline == "verify_only"),
             ("Largest certifier-generated algebraic certificate",
              row -> row.certificate_origin == "certifier_generated" &&
                  row.pipeline == "certify_from_approx"),
             ("Largest solve->diagnose->certify algebraic workflow",
              row -> row.certificate_origin == "certifier_generated" &&
                  row.pipeline == "solve_diagnose_certify")]
    for (label, predicate) in specs
        candidates = filter(predicate, algebraic)
        if isempty(candidates)
            println(io, "| ",
                    join([_markdown_cell(label), "None", "-", "-", "-", "-",
                          "-", "-", "-", "-", "-"], " | "), " |")
            continue
        end
        row = candidates[argmax([_row_general_size(candidate)
                                 for candidate in candidates])]
        notes = row.pipeline == "verify_only" ?
                "direct fixture replay; not a full certifier solve" :
                row.pipeline == "certify_from_approx" ?
                "certifier generated from approximate candidate" :
                "numerical solve, diagnose, certify, strict verify"
        row.algebraic_degree isa Integer && row.algebraic_degree >= 4 &&
            (notes = string(notes, "; degree >=4"))
        println(io, "| ",
                join([_markdown_cell(label),
                      _markdown_cell(row.instance),
                      _markdown_cell(row.size),
                      _benchmark_format_optional_int(row.algebraic_degree),
                      _markdown_cell(row.certificate_origin),
                      _markdown_cell(row.pipeline),
                      _markdown_cell(row.rounding_status),
                      _benchmark_format_seconds(row.cert_seconds),
                      _benchmark_format_seconds(row.strict_verify_seconds),
                      _benchmark_format_bytes(row.cert_size),
                      _markdown_cell(notes)], " | "),
                " |")
    end
    return nothing
end

function _write_algebraic_certifier_success_boundary(io::IO, rows)
    candidates = filter(row -> occursin("algebraic", lowercase(row.category)) &&
                                   row.status == BENCHMARK_EXPECTED_STATUS_CERTIFIED &&
                                   row.certificate_origin == "certifier_generated" &&
                                   row.pipeline in ("certify_from_approx",
                                                    "solve_diagnose_certify"),
                        rows)
    if isempty(candidates)
        println(io, "No certifier-generated algebraic success in this run.")
        return nothing
    end
    row = candidates[argmax([_row_general_size(candidate)
                             for candidate in candidates])]
    println(io,
            "| Instance | Size | Degree | Effective Variables | Pipeline | Rational Rounding | Cert Time | Strict Verify Time | Cert Size | Notes |")
    println(io,
            "| --- | ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | --- |")
    notes = "certifier-generated algebraic certificate, strict verified"
    row.algebraic_degree isa Integer && row.algebraic_degree >= 4 &&
        (notes = string(notes, "; degree >=4"))
    row.effective_variables isa Integer && row.effective_variables >= 2 &&
        (notes = string(notes, "; effective variables >=2"))
    println(io, "| ",
            join([_markdown_cell(row.instance),
                  _markdown_cell(row.size),
                  _benchmark_format_optional_int(row.algebraic_degree),
                  _markdown_cell(row.effective_variables),
                  _markdown_cell(row.pipeline),
                  _markdown_cell(row.rounding_status),
                  _benchmark_format_seconds(row.cert_seconds),
                  _benchmark_format_seconds(row.strict_verify_seconds),
                  _benchmark_format_bytes(row.cert_size),
                  _markdown_cell(notes)], " | "),
            " |")
    return nothing
end

function _write_imported_workflow_highlights(io::IO, rows)
    imported = filter(row -> row.status == BENCHMARK_EXPECTED_STATUS_CERTIFIED &&
                          row.source_kind in ("sdpa_import", "jump_moi_extract",
                                              "sumofsquares_extract"),
                      rows)
    isempty(imported) && begin
                         println(io, "No imported/extracted workflow highlight certified in this run.")
                         return nothing
                         end
    println(io,
            "| Case | Source | Pipeline | Size | Certificate Type | Cert Time | Strict Verify Time | Cert Size | Notes |")
    println(io,
            "| --- | --- | --- | ---: | --- | ---: | ---: | ---: | --- |")
    for row in sort(imported; by=row -> (row.source_kind, row.instance))
        println(io, "| ",
                join([_markdown_cell(row.instance),
                      _markdown_cell(row.source_kind),
                      _markdown_cell(row.pipeline),
                      _markdown_cell(row.size),
                      _markdown_cell(row.certificate_report_type),
                      _benchmark_format_seconds(row.cert_seconds),
                      _benchmark_format_seconds(row.strict_verify_seconds),
                      _benchmark_format_bytes(row.cert_size),
                      _markdown_cell(row.message)], " | "),
                " |")
    end
    return nothing
end

function _write_non_sdpa_imported_workflow_highlight(io::IO, rows)
    candidates = filter(row -> row.status == BENCHMARK_EXPECTED_STATUS_CERTIFIED &&
                            row.source_kind in ("jump_moi_extract",
                                                "sumofsquares_extract"),
                        rows)
    if isempty(candidates)
        println(io, "No JuMP/MOI or SumOfSquares extracted workflow certified in this run.")
        return nothing
    end
    row = candidates[argmax([_row_general_size(candidate)
                             for candidate in candidates])]
    println(io,
            "| Case | Source | Pipeline | Size | Effective Variables | Certificate Type | Cert Time | Strict Verify Time | Cert Size | Notes |")
    println(io,
            "| --- | --- | --- | ---: | ---: | --- | ---: | ---: | ---: | --- |")
    notes = row.source_kind == "jump_moi_extract" ?
            "JuMP/MOI extracted workflow; not SDPA import" :
            "SumOfSquares extracted workflow; not SDPA import"
    println(io, "| ",
            join([_markdown_cell(row.instance),
                  _markdown_cell(row.source_kind),
                  _markdown_cell(row.pipeline),
                  _markdown_cell(row.size),
                  _markdown_cell(row.effective_variables),
                  _markdown_cell(row.certificate_report_type),
                  _benchmark_format_seconds(row.cert_seconds),
                  _benchmark_format_seconds(row.strict_verify_seconds),
                  _benchmark_format_bytes(row.cert_size),
                  _markdown_cell(notes)], " | "),
            " |")
    return nothing
end

function _evidence_family_notes(family_rows, representative)
    parts = String[]
    any(row -> row.certificate_origin == "certifier_generated", family_rows) &&
        push!(parts, "certifier-generated certificate")
    any(row -> row.pipeline == "solve_diagnose_certify", family_rows) &&
        push!(parts, "numerical oracle workflow")
    any(row -> row.source_kind in ("sdpa_import", "jump_moi_extract",
                                   "sumofsquares_extract"), family_rows) &&
        push!(parts, "imported frontend workflow")
    any(row -> row.rounding_status == "failed" &&
            row.status == BENCHMARK_EXPECTED_STATUS_CERTIFIED,
        family_rows) &&
        push!(parts, "bounded rational rounding fails but exact certification succeeds")
    any(row -> row.status != BENCHMARK_EXPECTED_STATUS_CERTIFIED,
        family_rows) &&
        push!(parts, "expected rejection/failure")
    representative.algebraic_degree isa Integer &&
        representative.algebraic_degree >= 4 &&
        push!(parts, "algebraic degree >=4")
    return isempty(parts) ? "-" : join(parts, "; ")
end

function _family_notes(family_rows, largest, first_failure)
    representative = isnothing(largest) ? first(family_rows) : largest
    return _evidence_family_notes(family_rows, representative)
end

function _write_status_instances(io::IO, rows, status::AbstractString)
    selected = filter(row -> row.status == status, rows)
    isempty(selected) && begin
        println(io, "None")
        return nothing
    end
    for row in selected
        println(io, "- `", row.instance, "`: ", row.message)
    end
    return nothing
end

function _write_difficulty_instances(io::IO, rows, difficulty::AbstractString)
    selected = filter(row -> row.difficulty_class == difficulty, rows)
    isempty(selected) && begin
        println(io, "None")
        return nothing
    end
    for row in selected
        println(io, "- `", row.instance, "`: ", row.size,
                ", effective_variables=", row.effective_variables, "/",
                row.declared_variables, ", status=", row.status)
    end
    return nothing
end

function _write_failure_diagnostics_summary(io::IO, rows)
    failures = filter(row -> row.status != BENCHMARK_EXPECTED_STATUS_CERTIFIED,
                      rows)
    isempty(failures) && begin
        println(io, "None")
        return nothing
    end
    for row in failures
        label = row.failure_type == "" ? row.status : row.failure_type
        println(io, "- `", row.instance, "`: ", label, " - ", row.message)
    end
    return nothing
end

function _write_backend_bottleneck_summary(io::IO, rows)
    backend_rows = filter(row -> row.backend != "none" &&
                              row.status != BENCHMARK_EXPECTED_STATUS_CERTIFIED,
                          rows)
    isempty(backend_rows) && begin
        println(io, "No backend bottleneck observed in this run.")
        return nothing
    end
    for row in backend_rows
        println(io, "- `", row.instance, "`: backend=", row.backend,
                ", status=", row.status, ", failure=",
                row.failure_type == "" ? "-" : row.failure_type)
    end
    return nothing
end

function _strict_timing_summary(rows)
    certified = filter(row -> row.status == BENCHMARK_EXPECTED_STATUS_CERTIFIED,
                       rows)
    times = [Float64(row.strict_verify_seconds)
             for row in certified
             if row.strict_verify_seconds isa Real &&
                !isnan(row.strict_verify_seconds)]
    isempty(times) && return "No certified strict verifier timings."
    return string(length(times), " certified timings; total ",
                  _benchmark_format_seconds(sum(times)), "; max ",
                  _benchmark_format_seconds(maximum(times)), "; min ",
                  _benchmark_format_seconds(minimum(times)))
end

function _validation_budget_summary(rows)
    isempty(rows) && return "-"
    budgets = sort(unique(String(row.validation_budget) for row in rows))
    timeouts = [Float64(row.timeout_seconds)
                for row in rows
                if row.timeout_seconds isa Real && !isnan(row.timeout_seconds)]
    timeout_text = isempty(timeouts) ? "-" :
                   string("max timeout ", _benchmark_format_seconds(maximum(timeouts)))
    return string(join(budgets, ","), "; ", timeout_text)
end

function _write_slowest_validation_cases(io::IO, rows; limit::Integer=5)
    timed = filter(row -> row.strict_verify_seconds isa Real &&
                       !isnan(row.strict_verify_seconds), rows)
    isempty(timed) && begin
        println(io, "No verifier timings recorded.")
        return nothing
    end
    ordered = sort(timed; by=row -> Float64(row.strict_verify_seconds), rev=true)
    println(io,
            "| Instance | Status | Strict Verify | Verify No Cache | Cache Speedup | Slowest Stage | Certificate Size | Budget |")
    println(io,
            "| --- | --- | ---: | ---: | ---: | --- | ---: | --- |")
    for row in Iterators.take(ordered, limit)
        println(io, "| ",
                join([_markdown_cell(row.instance),
                      _markdown_cell(row.status),
                      _benchmark_format_seconds(row.strict_verify_seconds),
                      _benchmark_format_seconds(row.verify_uncached_seconds),
                      _benchmark_format_float(row.verify_cache_speedup),
                      _markdown_cell(row.slowest_verify_stage),
                      _benchmark_format_bytes(row.cert_size),
                      _markdown_cell(row.validation_budget)], " | "),
                " |")
    end
    return nothing
end

function _cache_comparison_summary(rows)
    cached = [Float64(row.verify_seconds)
              for row in rows
              if row.verify_seconds isa Real && !isnan(row.verify_seconds)]
    uncached = [Float64(row.verify_uncached_seconds)
                for row in rows
                if row.verify_uncached_seconds isa Real &&
                   !isnan(row.verify_uncached_seconds)]
    (isempty(cached) || isempty(uncached)) &&
        return "No cache comparison timings recorded."
    speedups = [Float64(row.verify_cache_speedup)
                for row in rows
                if row.verify_cache_speedup isa Real &&
                   !isnan(row.verify_cache_speedup)]
    return string("acceptance identical: ",
                  all(row.verify_consistent for row in rows),
                  "; cached total ", _benchmark_format_seconds(sum(cached)),
                  "; uncached total ", _benchmark_format_seconds(sum(uncached)),
                  "; cache hits ", sum(row.verify_cache_hits for row in rows),
                  "; cache misses ", sum(row.verify_cache_misses for row in rows),
                  isempty(speedups) ? "" :
                  string("; median speedup ",
                         _benchmark_format_float(_median_float(speedups))))
end

function _certificate_size_summary(rows)
    certified = filter(row -> row.status == BENCHMARK_EXPECTED_STATUS_CERTIFIED,
                       rows)
    sizes = [Int(row.cert_size) for row in certified if row.cert_size isa Integer]
    isempty(sizes) && return "No certified certificate sizes."
    return string(length(sizes), " certificates; total ",
                  _benchmark_format_bytes(sum(sizes)), "; max ",
                  _benchmark_format_bytes(maximum(sizes)), "; min ",
                  _benchmark_format_bytes(minimum(sizes)))
end

function _median_float(values::Vector{Float64})
    isempty(values) && return NaN
    sorted = sort(values)
    n = length(sorted)
    isodd(n) && return sorted[div(n + 1, 2)]
    return (sorted[div(n, 2)] + sorted[div(n, 2) + 1]) / 2
end

function _memory_expectation_summary(rows)
    values = [Int(row.memory_expectation_mb)
              for row in rows
              if row.memory_expectation_mb isa Integer]
    isempty(values) && return "No memory expectation metadata."
    return string("max=", _benchmark_format_memory(maximum(values)),
                  ", total declared across rows=",
                  _benchmark_format_memory(sum(values)))
end

function _row_general_size(row)
    return max(_row_total_dimension(row), _row_sos_basis(row),
               _row_lmi_dimension(row))
end

function _row_total_dimension(row)
    text = string(row.size)
    found = match(r"total=(\d+)", text)
    !isnothing(found) && return parse(Int, found.captures[1])
    return _row_lmi_dimension(row)
end

function _row_lmi_dimension(row)
    text = string(row.size)
    found = match(r"^(\d+)x\1", text)
    !isnothing(found) && return parse(Int, found.captures[1])
    return 0
end

function _row_sos_basis(row)
    text = string(row.size)
    found = match(r"basis=(\d+)", text)
    !isnothing(found) && return parse(Int, found.captures[1])
    return 0
end

function _write_public_benchmark_table(io::IO, rows)
    println(io,
            "| Instance | Suite | Family | Category | Construction | Source | Origin | Pipeline | Size | Declared Vars | Effective Vars | Density | Coeff Bits | Nonzero Affine | Rank Profile | Block Coupling | Gram Offdiag | Status | Certificate Type | Failure Type | Rational Rounding | Denominator Bound | Rounding Failure Reason | Cert Time | Strict Verify | Strict Time | Cert Size | Verify No Cache | Cache Hits | Cache Misses | Cache Speedup | Slowest Stage | Timeout | Backend | Message |")
    println(io,
            "| --- | --- | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | --- | --- | --- | --- | --- | --- | --- | ---: | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | --- | --- |")
    for row in rows
        println(io, "| ",
                join([_markdown_cell(row.instance),
                      _markdown_cell(row.pack_level),
                      _markdown_cell(row.benchmark_family),
                      _markdown_cell(row.category),
                      _markdown_cell(row.construction_type),
                      _markdown_cell(row.source_kind),
                      _markdown_cell(row.certificate_origin),
                      _markdown_cell(row.pipeline),
                      _markdown_cell(row.size),
                      _markdown_cell(row.declared_variables),
                      _markdown_cell(row.effective_variables),
                      _benchmark_format_float(row.affine_matrix_density),
                      _markdown_cell(row.coefficient_bit_size_range),
                      _markdown_cell(row.nonzero_affine_matrices),
                      _markdown_cell(row.rank_profile),
                      _markdown_cell(row.block_variable_coupling),
                      _markdown_cell(row.gram_offdiagonal_ratio),
                      _markdown_cell(row.status),
                      _markdown_cell(row.certificate_report_type == "" ? "-" :
                                     row.certificate_report_type),
                      _markdown_cell(row.failure_type == "" ? "-" : row.failure_type),
                      _markdown_cell(row.rounding_status),
                      string(row.rounding_denominator_bound),
                      _markdown_cell(row.rounding_failure_reason == "" ? "-" :
                                     row.rounding_failure_reason),
                      _benchmark_format_seconds(row.cert_seconds),
                      row.strict_verify_accepted === true ? "pass" :
                      row.status == BENCHMARK_EXPECTED_STATUS_CERTIFIED ? "fail" : "-",
                      _benchmark_format_seconds(row.strict_verify_seconds),
                      _benchmark_format_bytes(row.cert_size),
                      _benchmark_format_seconds(row.verify_uncached_seconds),
                      string(row.verify_cache_hits),
                      string(row.verify_cache_misses),
                      _benchmark_format_float(row.verify_cache_speedup),
                      _markdown_cell(row.slowest_verify_stage),
                      _benchmark_format_seconds(row.timeout_seconds),
                      _markdown_cell(row.backend),
                      _markdown_cell(row.message)], " | "),
                " |")
    end
    return nothing
end

function _write_extended_benchmark_table(io::IO, rows)
    println(io,
            "| Instance | Budget | Difficulty | Construction | Size | Variables | Effective Variables | Blocks | Algebraic Degree | Rational Rounding Observed | CertSDP Result | Certificate Type | Failure Type | Cert Time | Strict Verify Time | Memory Expectation | Timeout | Cert Size | Backend | Cache Hits | Result |")
    println(io,
            "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- | ---: | --- |")
    for row in rows
        println(io, "| ",
                join([_markdown_cell(row.instance),
                      _markdown_cell(row.validation_budget),
                      _markdown_cell(row.difficulty_class),
                      _markdown_cell(row.construction_type),
                      _markdown_cell(row.size),
                      _markdown_cell(row.variables),
                      _markdown_cell(row.effective_variables),
                      _markdown_cell(row.blocks),
                      _benchmark_format_optional_int(row.algebraic_degree),
                      _markdown_cell(row.rounding_status),
                      _markdown_cell(row.status),
                      _markdown_cell(row.certificate_report_type),
                      _markdown_cell(row.failure_type == "" ? "-" : row.failure_type),
                      _benchmark_format_seconds(row.cert_seconds),
                      _benchmark_format_seconds(row.strict_verify_seconds),
                      _benchmark_format_memory(row.memory_expectation_mb),
                      _benchmark_format_seconds(row.timeout_seconds),
                      _benchmark_format_bytes(row.cert_size),
                      _markdown_cell(row.backend),
                      string(row.verify_cache_hits),
                      row.passed ? "pass" : "fail"], " | "),
                " |")
    end
    return nothing
end

function _write_benchmark_table(io::IO, rows)
    println(io,
            "| Instance | Pack | Family | Category | Difficulty | Construction | Source | Origin | Pipeline | Validation Level | Size | Variables | Effective Variables | Blocks | Density | Coeff Bits | Block Coupling | Gram Offdiag | Rational Baseline | Rounding Attempt | Rounding Method | Denominator Bound | Rounding Failure Reason | CertSDP Result | Certificate Type | Failure Type | Rank | Algebraic Degree | Strategy | Backend | Backend Requirement | Expected Runtime | Memory | Cert Time | Verify Time | Strict Verify Time | Verify No Cache | Cache Hits | Validation Budget | Timeout | Cert Size | Expected | Result |")
    println(io,
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | --- | --- |")
    for row in rows
        println(io, "| ",
                join([_markdown_cell(row.instance),
                      _markdown_cell(row.pack_level),
                      _markdown_cell(row.benchmark_family),
                      _markdown_cell(row.category),
                      _markdown_cell(row.difficulty_class),
                      _markdown_cell(row.construction_type),
                      _markdown_cell(row.source_kind),
                      _markdown_cell(row.certificate_origin),
                      _markdown_cell(row.pipeline),
                      _markdown_cell(capability_tier_label(row.tier)),
                      _markdown_cell(row.size),
                      _markdown_cell(row.variables),
                      _markdown_cell(row.effective_variables),
                      _markdown_cell(row.blocks),
                      _benchmark_format_float(row.affine_matrix_density),
                      _markdown_cell(row.coefficient_bit_size_range),
                      _markdown_cell(row.block_variable_coupling),
                      _markdown_cell(row.gram_offdiagonal_ratio),
                      _markdown_cell(row.rational_rounding_baseline),
                      _markdown_cell(row.rounding_status),
                      _markdown_cell(row.rounding_method),
                      string(row.rounding_denominator_bound),
                      _markdown_cell(row.rounding_failure_reason == "" ? "-" :
                                     row.rounding_failure_reason),
                      _markdown_cell(row.status),
                      _markdown_cell(row.certificate_report_type),
                      _markdown_cell(row.failure_type == "" ? "-" : row.failure_type),
                      _benchmark_format_optional_int(row.rank),
                      _benchmark_format_optional_int(row.algebraic_degree),
                      _markdown_cell(row.strategy),
                      _markdown_cell(row.backend),
                      _markdown_cell(row.backend_requirement),
                      _benchmark_format_seconds(row.expected_runtime_seconds),
                      _benchmark_format_memory(row.memory_expectation_mb),
                      _benchmark_format_seconds(row.cert_seconds),
                      _benchmark_format_seconds(row.verify_seconds),
                      _benchmark_format_seconds(row.strict_verify_seconds),
                      _benchmark_format_seconds(row.verify_uncached_seconds),
                      string(row.verify_cache_hits),
                      _markdown_cell(row.validation_budget),
                      _benchmark_format_seconds(row.timeout_seconds),
                      _benchmark_format_bytes(row.cert_size),
                      _markdown_cell(row.expected_status),
                      row.passed ? "pass" : "fail"], " | "),
                " |")
    end
    return nothing
end

function _markdown_cell(value)
    text = string(value)
    return replace(text, "|" => "\\|", "\n" => " ")
end

function _benchmark_format_seconds(value)
    value isa Real || return "-"
    isnan(value) && return "-"
    scaled = round(Int, Float64(value) * 10_000)
    whole = div(scaled, 10_000)
    fractional = mod(scaled, 10_000)
    return string(whole, ".", lpad(string(fractional), 4, '0'), "s")
end

function _benchmark_format_float(value)
    value isa Real || return "-"
    isnan(value) && return "-"
    return string(round(Float64(value); digits=4))
end

function _benchmark_format_bytes(value::Integer)
    value == 0 && return "-"
    value < 1024 && return string(value, " B")
    return string(round(value / 1024; digits=2), " KiB")
end

function _benchmark_format_optional_int(value)
    isnothing(value) && return "-"
    value isa Integer && return string(value)
    return string(value)
end

function _benchmark_format_memory(value::Integer)
    value == 0 && return "-"
    value < 1024 && return string(value, " MB")
    return string(round(value / 1024; digits=2), " GiB")
end

function _benchmark_pack_level_summary(rows)
    isempty(rows) && return "-"
    counts = Dict{String, Int}()
    for row in rows
        counts[row.pack_level] = get(counts, row.pack_level, 0) + 1
    end
    parts = String[]
    for level in ("validation",)
        haskey(counts, level) && push!(parts, string(level, "=", counts[level]))
    end
    return isempty(parts) ? "-" : join(parts, ", ")
end
