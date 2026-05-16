const CAPABILITY_TIERS = (:tier0, :tier1, :tier1_5, :tier2, :tier3)
const DEFAULT_VALIDATION_BUDGET = :validation
const DEFAULT_BENCHMARK_RESOURCE_PROFILE = DEFAULT_VALIDATION_BUDGET

struct ResourceProfile
    name::Symbol
    max_tier::Symbol
    memory_limit_mb::Int
    default_timeout_seconds::Float64
    max_system_variables::Union{Nothing, Int}
    max_system_equations::Union{Nothing, Int}
    description::String
end

struct ResourceBudget
    profile::Union{Nothing, ResourceProfile}
    max_system_variables::Union{Nothing, Int}
    max_system_equations::Union{Nothing, Int}
    max_degree_estimate::Union{Nothing, Int}
    timeout_seconds::Union{Nothing, Float64}
    memory_limit_mb::Union{Nothing, Int}
    memory_hint_mb::Union{Nothing, Int}
end

function ResourceBudget(profile::Union{Nothing, ResourceProfile},
                        max_system_variables::Union{Nothing, Int},
                        max_system_equations::Union{Nothing, Int},
                        timeout_seconds::Union{Nothing, Float64},
                        memory_limit_mb::Union{Nothing, Int})
    return ResourceBudget(profile,
                          max_system_variables,
                          max_system_equations,
                          nothing,
                          timeout_seconds,
                          memory_limit_mb,
                          memory_limit_mb)
end

const RESOURCE_PROFILES = Dict{Symbol, ResourceProfile}(:validation => ResourceProfile(:validation,
                                                                                       :tier2,
                                                                                       64_000,
                                                                                       1_800.0,
                                                                                       80,
                                                                                       160,
                                                                                       "default validation evidence budget"))

function normalize_capability_tier(value)
    value isa Symbol && (value = String(value))
    text = lowercase(strip(String(value)))
    text = replace(text, " " => "", "_" => "", "-" => "")
    if text in ("0", "t0", "tier0")
        return :tier0
    elseif text in ("1", "t1", "tier1")
        return :tier1
    elseif text in ("15", "1.5", "t15", "t1.5", "tier15", "tier1.5")
        return :tier1_5
    elseif text in ("2", "t2", "tier2")
        return :tier2
    elseif text in ("3", "t3", "tier3")
        return :tier3
    end
    throw(ArgumentError("unsupported validation tier `$value`; expected tier0, tier1, tier1.5, tier2, or tier3"))
end

function capability_tier_label(tier)
    normalized = normalize_capability_tier(tier)
    normalized === :tier0 && return "Validation 0"
    normalized === :tier1 && return "Validation 1"
    normalized === :tier1_5 && return "Validation 1.5"
    normalized === :tier2 && return "Validation 2"
    normalized === :tier3 && return "Validation 3"
    throw(ArgumentError("unsupported validation tier `$tier`"))
end

function capability_tier_index(tier)
    normalized = normalize_capability_tier(tier)
    index = findfirst(==(normalized), CAPABILITY_TIERS)
    isnothing(index) && throw(ArgumentError("unsupported validation tier `$tier`"))
    return index - 1
end

function normalize_resource_profile(value)
    value isa ResourceProfile && return value
    value isa Symbol && (value = String(value))
    text = lowercase(strip(String(value)))
    key = Symbol(replace(text, " " => "", "_" => "", "-" => ""))
    haskey(RESOURCE_PROFILES, key) ||
        throw(ArgumentError("unsupported validation budget `$value`; expected validation"))
    return RESOURCE_PROFILES[key]
end

resource_profile(value) = normalize_resource_profile(value)
function validation_budget(value=DEFAULT_VALIDATION_BUDGET; kwargs...)
    return resolve_resource_budget(; profile=value, kwargs...)
end

function validation_budget_label(budget::ResourceBudget)
    return isnothing(budget.profile) ? "custom" : String(budget.profile.name)
end

function validation_timeout_policy(budget::ResourceBudget)
    return (;
            budget=validation_budget_label(budget),
            timeout_seconds=budget.timeout_seconds,
            memory_limit_mb=budget.memory_limit_mb,
            memory_hint_mb=budget.memory_hint_mb,
            max_system_variables=budget.max_system_variables,
            max_system_equations=budget.max_system_equations,
            max_degree_estimate=budget.max_degree_estimate,)
end

function resource_profile_allows(profile, tier; memory_expectation_mb=nothing)
    resolved = normalize_resource_profile(profile)
    tier_ok = capability_tier_index(tier) <= capability_tier_index(resolved.max_tier)
    memory_ok = isnothing(memory_expectation_mb) ||
                Int(memory_expectation_mb) <= resolved.memory_limit_mb
    return tier_ok && memory_ok
end

function resolve_resource_budget(; profile=nothing,
                                 budget=nothing,
                                 max_system_variables=nothing,
                                 max_system_equations=nothing,
                                 max_degree_estimate=nothing,
                                 timeout_seconds=nothing,
                                 memory_limit_mb=nothing,
                                 memory_hint_mb=nothing)
    profile_value = isnothing(profile) && _budget_is_profile_like(budget) ? budget : profile
    resolved_profile = isnothing(profile_value) ? nothing :
                       normalize_resource_profile(profile_value)

    variables = isnothing(resolved_profile) ? nothing :
                resolved_profile.max_system_variables
    equations = isnothing(resolved_profile) ? nothing :
                resolved_profile.max_system_equations
    degree = nothing
    timeout = isnothing(resolved_profile) ? nothing :
              resolved_profile.default_timeout_seconds
    memory = isnothing(resolved_profile) ? nothing :
             resolved_profile.memory_limit_mb
    memory_hint = memory

    variables = _combine_budget_limit(variables,
                                      _budget_lookup(budget, :max_system_variables),
                                      :max_system_variables)
    equations = _combine_budget_limit(equations,
                                      _budget_lookup(budget, :max_system_equations),
                                      :max_system_equations)
    degree = _combine_budget_limit(degree,
                                   _budget_lookup(budget, :max_degree_estimate),
                                   :max_degree_estimate)
    degree = _combine_budget_limit(degree,
                                   _budget_lookup(budget, :max_degree),
                                   :max_degree_estimate)
    timeout = _combine_budget_timeout(timeout,
                                      _budget_lookup(budget, :timeout_seconds))
    memory = _combine_budget_limit(memory,
                                   _budget_lookup(budget, :memory_limit_mb),
                                   :memory_limit_mb)
    memory_hint = _combine_budget_limit(memory_hint,
                                        _budget_lookup(budget, :memory_hint_mb),
                                        :memory_hint_mb)
    memory_hint = _combine_budget_limit(memory_hint,
                                        _budget_lookup(budget, :memory_hint),
                                        :memory_hint_mb)

    variables = _combine_budget_limit(variables, max_system_variables,
                                      :max_system_variables)
    equations = _combine_budget_limit(equations, max_system_equations,
                                      :max_system_equations)
    degree = _combine_budget_limit(degree, max_degree_estimate,
                                   :max_degree_estimate)
    timeout = _combine_budget_timeout(timeout, timeout_seconds)
    memory = _combine_budget_limit(memory, memory_limit_mb, :memory_limit_mb)
    memory_hint = _combine_budget_limit(memory_hint, memory_hint_mb,
                                        :memory_hint_mb)
    if !isnothing(memory) && !isnothing(memory_hint)
        memory_hint = min(memory_hint, memory)
    end

    return ResourceBudget(resolved_profile,
                          variables,
                          equations,
                          degree,
                          timeout,
                          memory,
                          memory_hint)
end

function _budget_is_profile_like(value)
    isnothing(value) && return false
    value isa Symbol && return true
    value isa AbstractString && return true
    value isa ResourceProfile && return true
    return false
end

function _budget_lookup(budget, key::Symbol)
    isnothing(budget) && return nothing
    _budget_is_profile_like(budget) && return nothing
    if budget isa ResourceBudget
        key === :max_degree && return budget.max_degree_estimate
        return hasfield(typeof(budget), key) ? getproperty(budget, key) : nothing
    end
    if budget isa NamedTuple
        return haskey(budget, key) ? getproperty(budget, key) : nothing
    elseif budget isa AbstractDict
        haskey(budget, key) && return budget[key]
        string_key = String(key)
        haskey(budget, string_key) && return budget[string_key]
        return nothing
    end
    throw(ArgumentError("budget must be a ResourceBudget, NamedTuple, Dict, validation budget, or nothing"))
end

function _combine_budget_limit(current, value, name::Symbol)
    isnothing(value) && return current
    parsed = Int(value)
    parsed >= 0 || throw(ArgumentError("$name budget must be nonnegative"))
    return isnothing(current) ? parsed : min(current, parsed)
end

function _combine_budget_timeout(current, value)
    isnothing(value) && return current
    parsed = Float64(value)
    parsed > 0 || throw(ArgumentError("timeout_seconds budget must be positive"))
    return isnothing(current) ? parsed : min(current, parsed)
end
