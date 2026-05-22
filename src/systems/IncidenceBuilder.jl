"""
    build_incidence_system(P, approx, rank_profile; kernel_prefix=:Y, gauge_rows=nothing,
                           slicing=:none, slicing_equations=nothing)

Build the kernel-incidence polynomial system for an LMI
`A(x) = A0 + sum(x[i] * A[i])` near a numerical rank profile:

```text
A(x)Y = 0
Y[gauge_rows, :] = I
```

The returned `PolynomialSystem` uses the original LMI variables first, followed
by kernel variables named `Y_i_j` in column-major order. Numerical data is
recorded only as metadata; it is not proof evidence.
"""
function build_incidence_system(P::LMIProblem,
                                approx::ApproxSolution,
                                rank_profile::RankProfile;
                                kernel_prefix::Symbol=:Y,
                                gauge_rows=nothing,
                                slicing=nothing,
                                slicing_equations=nothing,
                                slicing_tolerance="1e-8",
                                slicing_max_denominator::Integer=1024,
                                slicing_max_equations=nothing,
                                slicing_variables=nothing,
                                slicing_seed::Integer=0,)
    _validate_incidence_approximation(P, approx)

    m = matrix_size(P)
    n = num_variables(P)
    r = _validate_incidence_rank_profile(rank_profile, m)
    k = m - r
    k > 0 ||
        throw(ArgumentError("incidence system requires a rank-deficient profile; got rank $r for matrix size $m"))

    selected_gauge_rows, gauge_strategy = _incidence_gauge_rows(rank_profile, m, k,
                                                                gauge_rows)
    variable_names, kernel_variable_names = _incidence_variable_names(P, m, k,
                                                                      kernel_prefix)
    ring = polynomial_ring(variable_names)
    ring_variables = variables(ring)
    x_variables = ring_variables[1:n]
    Y = _kernel_variable_matrix(ring_variables[(n + 1):end], m, k)
    Ax = _lmi_polynomial_matrix(P, ring, x_variables)

    equations = MultivariatePolynomial[]
    sizehint!(equations, m * k + k * k)

    for col in 1:k, row in 1:m
        equation = zero_polynomial(ring)
        for inner in 1:m
            equation += Ax[row, inner] * Y[inner, col]
        end
        push!(equations, equation)
    end

    gauge_specs = NamedTuple[]
    for col in 1:k, local_row in 1:k
        row = selected_gauge_rows[local_row]
        value = local_row == col ? 1 : 0
        push!(equations, Y[row, col] - value)
        push!(gauge_specs,
              (;
               equation_index=length(equations),
               row,
               column=col,
               value=string(value),))
    end

    incidence_count = m * k
    gauge_count = k * k
    slice_equations, slice_specs, slice_strategy = _incidence_slicing_equations(ring,
                                                                                ring_variables,
                                                                                variable_names,
                                                                                P,
                                                                                approx,
                                                                                rank_profile,
                                                                                m,
                                                                                n,
                                                                                k;
                                                                                slicing,
                                                                                slicing_equations,
                                                                                slicing_tolerance,
                                                                                slicing_max_denominator,
                                                                                slicing_max_equations,
                                                                                slicing_variables,
                                                                                slicing_seed)
    append!(equations, slice_equations)
    for i in eachindex(slice_specs)
        spec = slice_specs[i]
        slice_specs[i] = merge(spec, (; equation_index=incidence_count + gauge_count + i))
    end

    metadata = _incidence_metadata(P,
                                   approx,
                                   rank_profile,
                                   m,
                                   n,
                                   r,
                                   k,
                                   selected_gauge_rows,
                                   gauge_strategy,
                                   variable_names,
                                   kernel_variable_names,
                                   gauge_specs,
                                   slice_specs,
                                   slice_strategy)

    return PolynomialSystem(ring, equations; metadata)
end

function build_incidence_system(P::LMIProblem, approx::ApproxSolution; kwargs...)
    rank_profile = approx.rank_profile
    rank_profile isa RankProfile ||
        throw(ArgumentError("cannot build incidence system from unstable rank profile: $(rank_profile.reason)"))
    return build_incidence_system(P, approx, rank_profile; kwargs...)
end

"""
    build_incidence_system(P::BlockLMIProblem, approx; block_strategy=:active_blocks, ...)

Build a block-native incidence system descriptor. Each rank-deficient active
PSD block receives its own kernel variables and gauge rows while the original
`x` variables remain shared. This path never constructs the dense block
diagonal aggregate; it records per-block hashes and diagnostics for exact
candidate replay.
"""
function build_incidence_system(P::BlockLMIProblem,
                                approx;
                                block_strategy::Symbol=:active_blocks,
                                rank_profiles=nothing,
                                active_blocks=nothing,
                                inactive_blocks=nothing,
                                slicing::Symbol=:none,
                                kernel_prefix::Symbol=:B)
    block_strategy === :active_blocks ||
        throw(ArgumentError("block-native incidence currently supports block_strategy=:active_blocks"))
    profiles = _block_native_rank_profiles(P, rank_profiles)
    active_set, inactive_set = _block_native_active_sets(P, profiles,
                                                        active_blocks,
                                                        inactive_blocks)
    blocks = Kernel.BlockNativeIncidenceBlock[]
    for (block_index, block) in enumerate(P.blocks)
        profile = profiles[block_index]
        rank = profile.rank
        dimension = matrix_size(block)
        kernel_dimension = dimension - rank
        active = block_index in active_set
        if active
            kernel_dimension > 0 ||
                throw(ArgumentError("active block $block_index must be rank-deficient"))
            variable_names = _block_native_variable_names(P, block_index,
                                                          dimension,
                                                          kernel_dimension,
                                                          kernel_prefix)
            gauge_rows = _incidence_complement_indices(dimension,
                                                       profile.pivot_cols)
            system_hash = _block_native_block_system_hash(block,
                                                          block_index,
                                                          rank,
                                                          kernel_dimension,
                                                          variable_names,
                                                          gauge_rows,
                                                          slicing,
                                                          true)
        else
            block_index in inactive_set ||
                throw(ArgumentError("block $block_index is neither active nor inactive"))
            variable_names = Symbol[]
            gauge_rows = Int[]
            system_hash = _block_native_block_system_hash(block,
                                                          block_index,
                                                          rank,
                                                          kernel_dimension,
                                                          variable_names,
                                                          gauge_rows,
                                                          :inactive_psd_margin,
                                                          false)
        end
        push!(blocks,
              Kernel.BlockNativeIncidenceBlock(block_index,
                                               lmi_problem_hash(block),
                                               rank,
                                               kernel_dimension,
                                               variable_names,
                                               gauge_rows,
                                               active ? slicing :
                                               :inactive_psd_margin,
                                               active,
                                               system_hash))
    end
    system_hash = _block_native_system_hash(P, blocks)
    return Kernel.BlockNativeIncidenceSystem(block_lmi_problem_hash(P),
                                             copy(P.vars),
                                             blocks,
                                             system_hash)
end

function build_incidence_system(P::LMIProblem,
                                approx::ApproxSolution,
                                rank_profile::UnstableRankProfile;
                                kwargs...,)
    throw(ArgumentError("cannot build incidence system from unstable rank profile: $(rank_profile.reason)"))
end

function _block_native_rank_profiles(P::BlockLMIProblem, rank_profiles)
    if isnothing(rank_profiles)
        return [RankProfile(max(0, matrix_size(block) - 1),
                            collect(1:max(0, matrix_size(block) - 1)),
                            collect(1:max(0, matrix_size(block) - 1)),
                            collect(1:matrix_size(block)),
                            BigFloat(0),
                            BigFloat[],
                            BigFloat(0),
                            :fixture)
                for block in P.blocks]
    end
    length(rank_profiles) == num_blocks(P) ||
        throw(ArgumentError("rank_profiles has length $(length(rank_profiles)); expected $(num_blocks(P))"))
    profiles = RankProfile[]
    for (block_index, profile) in enumerate(rank_profiles)
        profile isa RankProfile ||
            throw(ArgumentError("rank_profiles[$block_index] must be a RankProfile"))
        _validate_incidence_rank_profile(profile, matrix_size(P.blocks[block_index]))
        push!(profiles, profile)
    end
    return profiles
end

function _block_native_active_sets(P::BlockLMIProblem,
                                   profiles::Vector{RankProfile},
                                   active_blocks,
                                   inactive_blocks)
    all_blocks = Set(1:num_blocks(P))
    active = if isnothing(active_blocks)
        Set(i for (i, profile) in enumerate(profiles)
            if profile.rank < matrix_size(P.blocks[i]))
    else
        Set(Int.(collect(active_blocks)))
    end
    inactive = if isnothing(inactive_blocks)
        setdiff(all_blocks, active)
    else
        Set(Int.(collect(inactive_blocks)))
    end
    union(active, inactive) == all_blocks ||
        throw(ArgumentError("active/inactive block sets must cover every block"))
    isempty(intersect(active, inactive)) ||
        throw(ArgumentError("active/inactive block sets must be disjoint"))
    for index in union(active, inactive)
        1 <= index <= num_blocks(P) ||
            throw(ArgumentError("block index $index out of range"))
    end
    return active, inactive
end

function _block_native_variable_names(P::BlockLMIProblem,
                                      block_index::Integer,
                                      dimension::Integer,
                                      kernel_dimension::Integer,
                                      kernel_prefix::Symbol)
    prefix = String(kernel_prefix)
    names = Symbol[
        Symbol(prefix, block_index, "_Y_", row, "_", col)
        for col in 1:kernel_dimension
        for row in 1:dimension
    ]
    all_names = vcat(P.vars, names)
    length(unique(all_names)) == length(all_names) ||
        throw(ArgumentError("block $block_index incidence variable names collide with shared variables"))
    return names
end

function _block_native_block_system_hash(block::LMIProblem,
                                         block_index::Integer,
                                         rank::Integer,
                                         kernel_dimension::Integer,
                                         variable_names::Vector{Symbol},
                                         gauge_rows::Vector{Int},
                                         slicing_strategy::Symbol,
                                         active::Bool)
    payload = (;
        block_index=Int(block_index),
        block_hash=lmi_problem_hash(block),
        rank=Int(rank),
        kernel_dimension=Int(kernel_dimension),
        active,
        variable_names=String.(variable_names),
        gauge_rows,
        slicing_strategy=String(slicing_strategy),
    )
    return "sha256:" * bytes2hex(sha256(JSON3.write(payload)))
end

function _block_native_system_hash(P::BlockLMIProblem,
                                   blocks::Vector{Kernel.BlockNativeIncidenceBlock})
    payload = (;
        problem_hash=block_lmi_problem_hash(P),
        shared_variables=String.(P.vars),
        blocks=[Kernel.block_native_incidence_block_json(block)
                for block in blocks],
    )
    return "sha256:" * bytes2hex(sha256(JSON3.write(payload)))
end

function _validate_incidence_approximation(P::LMIProblem, approx::ApproxSolution)
    problem_hash = lmi_problem_hash(P)
    approx.problem_hash == problem_hash ||
        throw(ArgumentError("approximation problem hash $(approx.problem_hash) does not match LMI hash $problem_hash"))
    length(approx.xhat) == num_variables(P) ||
        throw(DimensionMismatch("approximation xhat has length $(length(approx.xhat)); expected $(num_variables(P))"))
    size(approx.Xhat) == (matrix_size(P), matrix_size(P)) ||
        throw(DimensionMismatch("approximation Xhat has size $(size(approx.Xhat)); expected $((matrix_size(P), matrix_size(P)))"))
    return nothing
end

function _validate_incidence_rank_profile(rank_profile::RankProfile,
                                          matrix_size_value::Integer)
    rank = rank_profile.rank
    0 <= rank <= matrix_size_value ||
        throw(ArgumentError("rank profile rank $rank is out of range for matrix size $matrix_size_value"))
    length(rank_profile.pivot_cols) == rank ||
        throw(ArgumentError("rank profile has $(length(rank_profile.pivot_cols)) pivot columns; expected $rank"))
    length(rank_profile.pivot_rows) == rank ||
        throw(ArgumentError("rank profile has $(length(rank_profile.pivot_rows)) pivot rows; expected $rank"))
    _validate_incidence_index_set(rank_profile.pivot_cols, matrix_size_value,
                                  "rank_profile.pivot_cols")
    _validate_incidence_index_set(rank_profile.pivot_rows, matrix_size_value,
                                  "rank_profile.pivot_rows")
    return rank
end

function _incidence_gauge_rows(rank_profile::RankProfile, m::Integer, k::Integer,
                               gauge_rows)
    if isnothing(gauge_rows)
        rows = _incidence_complement_indices(m, rank_profile.pivot_cols)
        length(rows) == k ||
            throw(ArgumentError("complement of pivot columns has length $(length(rows)); expected kernel dimension $k"))
        return rows, :complement_of_pivot_cols
    end

    rows = Int[value for value in gauge_rows]
    length(rows) == k ||
        throw(ArgumentError("gauge_rows has length $(length(rows)); expected kernel dimension $k"))
    _validate_incidence_index_set(rows, m, "gauge_rows")
    return rows, :user_provided
end

function _validate_incidence_index_set(indices::AbstractVector{Int}, upper::Integer,
                                       name::AbstractString)
    issorted(indices) || throw(ArgumentError("$name must be sorted"))
    length(unique(indices)) == length(indices) ||
        throw(ArgumentError("$name must be unique"))
    for (i, index) in enumerate(indices)
        1 <= index <= upper ||
            throw(ArgumentError("$name[$i] is out of range for size $upper"))
    end
    return indices
end

function _incidence_complement_indices(m::Integer, pivots::AbstractVector{Int})
    pivot_set = Set(pivots)
    return [i for i in 1:m if !(i in pivot_set)]
end

function _incidence_variable_names(P::LMIProblem, m::Integer, k::Integer,
                                   kernel_prefix::Symbol)
    prefix = String(kernel_prefix)
    isempty(prefix) && throw(ArgumentError("kernel_prefix must not be empty"))

    kernel_names = Symbol[
                          Symbol(prefix, "_", row, "_", col)
                          for col in 1:k
                          for row in 1:m
                          ]
    variable_names = vcat(P.vars, kernel_names)
    length(unique(variable_names)) == length(variable_names) ||
        throw(ArgumentError("incidence variable names collide; use LMI variable names that do not overlap with $(prefix)_i_j"))
    return variable_names, kernel_names
end

function _kernel_variable_matrix(kernel_variables::AbstractVector{PolynomialVariable},
                                 m::Integer, k::Integer)
    length(kernel_variables) == m * k ||
        throw(ArgumentError("wrong number of kernel variables"))
    return [kernel_variables[(col - 1) * m + row]
            for row in 1:m, col in 1:k]
end

function _lmi_polynomial_matrix(P::LMIProblem, ring::PolynomialRingAdapter,
                                x_variables::AbstractVector)
    m = matrix_size(P)
    Ax = Matrix{MultivariatePolynomial}(undef, m, m)
    A0 = rational_matrix(P.A0)
    coefficients = [rational_matrix(matrix) for matrix in P.A]

    for row in 1:m, col in 1:m
        entry = constant_polynomial(ring, A0[row, col])
        for (variable, coefficient_matrix) in zip(x_variables, coefficients)
            coefficient = coefficient_matrix[row, col]
            iszero(coefficient) && continue
            entry += coefficient * variable
        end
        Ax[row, col] = entry
    end

    return Ax
end

function _incidence_slicing_equations(ring::PolynomialRingAdapter,
                                      ring_variables::AbstractVector,
                                      variable_names::Vector{Symbol},
                                      P::LMIProblem,
                                      approx::ApproxSolution,
                                      rank_profile::RankProfile,
                                      m::Integer,
                                      n::Integer,
                                      k::Integer;
                                      slicing=nothing,
                                      slicing_equations=nothing,
                                      slicing_tolerance="1e-8",
                                      slicing_max_denominator::Integer=1024,
                                      slicing_max_equations=nothing,
                                      slicing_variables=nothing,
                                      slicing_seed::Integer=0)
    if isnothing(slicing_equations) && haskey(approx.slicing_hints, :equations)
        slicing_equations = approx.slicing_hints[:equations]
    end
    strategy = _resolve_slicing_strategy(slicing, slicing_equations, approx)
    strategy === :none && return MultivariatePolynomial[], NamedTuple[], :none
    if strategy === :user
        return _user_slicing_equations(ring, ring_variables, variable_names,
                                       slicing_equations)
    elseif strategy in (:rational, :rational_rounding, :auto)
        return _rational_rounding_slicing_equations(ring,
                                                    ring_variables,
                                                    variable_names,
                                                    P,
                                                    approx,
                                                    rank_profile,
                                                    m,
                                                    n,
                                                    k;
                                                    slicing_tolerance,
                                                    slicing_max_denominator,
                                                    slicing_max_equations,
                                                    slicing_variables,
                                                    slicing_seed)
    elseif strategy in (:paper, :paper_pivot, :pivot_derived)
        return _rational_rounding_slicing_equations(ring,
                                                    ring_variables,
                                                    variable_names,
                                                    P,
                                                    approx,
                                                    rank_profile,
                                                    m,
                                                    n,
                                                    k;
                                                    slicing_tolerance,
                                                    slicing_max_denominator,
                                                    slicing_max_equations,
                                                    slicing_variables,
                                                    slicing_seed,
                                                    declared_strategy=strategy)
    end
    throw(ArgumentError("unsupported slicing strategy `$strategy`"))
end

function _resolve_slicing_strategy(slicing, slicing_equations, approx::ApproxSolution)
    if isnothing(slicing_equations) && haskey(approx.slicing_hints, :equations)
        slicing_equations = approx.slicing_hints[:equations]
    end
    if !isnothing(slicing_equations)
        return :user
    end
    if isnothing(slicing)
        if haskey(approx.slicing_hints, :strategy)
            return Symbol(approx.slicing_hints[:strategy])
        end
        return :none
    end
    return Symbol(slicing)
end

function _user_slicing_equations(ring::PolynomialRingAdapter,
                                 ring_variables::AbstractVector,
                                 variable_names::Vector{Symbol},
                                 slicing_equations)
    specs = NamedTuple[]
    equations = MultivariatePolynomial[]
    variable_index = Dict(name => i for (i, name) in enumerate(variable_names))
    source = isnothing(slicing_equations) ? [] : slicing_equations
    isempty(source) && return equations, specs, :user

    for (i, raw_equation) in enumerate(source)
        coefficients, rhs, label = _parse_user_slicing_equation(raw_equation,
                                                                variable_index)
        polynomial = zero_polynomial(ring)
        used = Pair{Symbol, Rational{BigInt}}[]
        for (name, coefficient) in sort!(collect(coefficients); by=first)
            iszero(coefficient) && continue
            polynomial += coefficient * ring_variables[variable_index[name]]
            push!(used, name => coefficient)
        end
        polynomial -= rhs
        iszero(polynomial) &&
            throw(ArgumentError("user slicing equation $i is identically zero"))
        push!(equations, polynomial)
        push!(specs,
              (;
               strategy=:user,
               label,
               expression=string(polynomial),
               rhs=_rational_string(rhs),
               coefficients=Dict(String(name) => _rational_string(value)
                                 for (name, value) in used),))
    end

    return equations, specs, :user
end

function _parse_user_slicing_equation(raw_equation, variable_index::Dict{Symbol, Int})
    if raw_equation isa NamedTuple
        return _parse_user_slicing_equation(Dict{Symbol, Any}(Symbol(key) => value
                                                              for (key, value) in
                                                                  pairs(raw_equation)),
                                            variable_index)
    elseif raw_equation isa AbstractDict
        coefficients_value = _dict_lookup(raw_equation, :coefficients)
        isnothing(coefficients_value) &&
            throw(ArgumentError("user slicing equation is missing `coefficients`"))
        coefficients_value isa AbstractDict ||
            throw(ArgumentError("user slicing coefficients must be a dictionary"))
        coefficients = Dict{Symbol, Rational{BigInt}}()
        for (key, value) in coefficients_value
            name = Symbol(String(key))
            haskey(variable_index, name) ||
                throw(ArgumentError("user slicing equation references unknown variable `$name`"))
            coefficients[name] = _slice_rational(value; name=:slicing_coefficient)
        end
        rhs_value = _dict_lookup(raw_equation, :rhs)
        rhs = isnothing(rhs_value) ? 0 // 1 : _slice_rational(rhs_value; name=:slicing_rhs)
        label_value = _dict_lookup(raw_equation, :label)
        label = isnothing(label_value) ? "" : String(label_value)
        return coefficients, rhs, label
    end
    throw(ArgumentError("user slicing equation must be a dictionary or named tuple"))
end

function _rational_rounding_slicing_equations(ring::PolynomialRingAdapter,
                                              ring_variables::AbstractVector,
                                              variable_names::Vector{Symbol},
                                              P::LMIProblem,
                                              approx::ApproxSolution,
                                              rank_profile::RankProfile,
                                              m::Integer,
                                              n::Integer,
                                              k::Integer;
                                              slicing_tolerance="1e-8",
                                              slicing_max_denominator::Integer=1024,
                                              slicing_max_equations=nothing,
                                              slicing_variables=nothing,
                                              slicing_seed::Integer=0,
                                              declared_strategy=:rational_rounding)
    candidates = _rational_slice_coordinate_candidates(P,
                                                       approx,
                                                       rank_profile,
                                                       m,
                                                       n,
                                                       k,
                                                       variable_names;
                                                       slicing_variables,
                                                       slicing_tolerance,
                                                       slicing_max_denominator)
    max_equations = isnothing(slicing_max_equations) ?
                    _default_slice_equation_count(n, m, k) :
                    Int(slicing_max_equations)
    max_equations >= 0 ||
        throw(ArgumentError("slicing_max_equations must be nonnegative"))
    max_equations == 0 && return MultivariatePolynomial[], NamedTuple[], declared_strategy

    order = _deterministic_slice_order(length(candidates), slicing_seed)
    equations = MultivariatePolynomial[]
    specs = NamedTuple[]
    for index in order
        length(equations) >= max_equations && break
        candidate = candidates[index]
        variable_index = findfirst(==(candidate.variable), variable_names)
        isnothing(variable_index) && continue
        equation = ring_variables[variable_index] - candidate.value
        push!(equations, equation)
        push!(specs,
              (;
               strategy=declared_strategy,
               variable=String(candidate.variable),
               expression=string(equation),
               value=_rational_string(candidate.value),
               approximate_value=string(candidate.approximate_value),
               error=string(candidate.error),
               source=candidate.source,))
    end

    return equations, specs, declared_strategy
end

function _rational_slice_coordinate_candidates(P::LMIProblem,
                                               approx::ApproxSolution,
                                               rank_profile::RankProfile,
                                               m::Integer,
                                               n::Integer,
                                               k::Integer,
                                               variable_names::Vector{Symbol};
                                               slicing_variables,
                                               slicing_tolerance,
                                               slicing_max_denominator)
    tolerance = _bigfloat_scalar(slicing_tolerance; name=:slicing_tolerance)
    tolerance >= 0 || throw(ArgumentError("slicing_tolerance must be nonnegative"))
    slicing_max_denominator >= 1 ||
        throw(ArgumentError("slicing_max_denominator must be positive"))
    allowed = _slicing_variable_set(slicing_variables, P.vars)
    candidates = NamedTuple[]

    for i in 1:n
        variable = P.vars[i]
        _slice_variable_allowed(variable, allowed) || continue
        rounded = _rationalize_bigfloat(approx.xhat[i], tolerance)
        denominator(rounded) <= slicing_max_denominator || continue
        error = abs(_bigfloat_rational(rounded) - approx.xhat[i])
        error <= tolerance || continue
        push!(candidates,
              (;
               variable,
               value=rounded,
               approximate_value=approx.xhat[i],
               error,
               source=:xhat))
    end

    kernel_variables = variable_names[(n + 1):end]
    gauge_rows = _incidence_complement_indices(m, rank_profile.pivot_cols)
    gauge_set = Set(gauge_rows)
    for col in 1:k, row in 1:m
        row in gauge_set && continue
        name = kernel_variables[(col - 1) * m + row]
        _slice_variable_allowed(name, allowed) || continue
        approximate_value = _approx_kernel_entry(approx, rank_profile, row, col,
                                                 gauge_rows)
        isnothing(approximate_value) && continue
        rounded = _rationalize_bigfloat(approximate_value, tolerance)
        denominator(rounded) <= slicing_max_denominator || continue
        error = abs(_bigfloat_rational(rounded) - approximate_value)
        error <= tolerance || continue
        push!(candidates,
              (;
               variable=name,
               value=rounded,
               approximate_value,
               error,
               source=:kernel_approximation))
    end

    return candidates
end

function _slicing_variable_set(slicing_variables, default_variables::Vector{Symbol})
    if isnothing(slicing_variables)
        return Set{Symbol}(default_variables)
    end
    values = Set{Symbol}()
    for variable in slicing_variables
        push!(values, Symbol(variable))
    end
    return values
end

_slice_variable_allowed(_variable::Symbol, allowed::Nothing) = true
_slice_variable_allowed(variable::Symbol, allowed::Set{Symbol}) = variable in allowed

function _default_slice_equation_count(n::Integer, m::Integer, k::Integer)
    return max(0, min(n + m * k, max(1, n)))
end

function _deterministic_slice_order(count::Integer, seed::Integer)
    order = collect(1:count)
    count <= 1 && return order
    shift = mod(seed, count)
    shift == 0 && return order
    return vcat(order[(shift + 1):end], order[1:shift])
end

function _approx_kernel_entry(approx::ApproxSolution,
                              rank_profile::RankProfile,
                              row::Integer,
                              col::Integer,
                              gauge_rows::Vector{Int})
    pivot_rows = rank_profile.pivot_cols
    r = length(pivot_rows)
    r == 0 && return row == gauge_rows[col] ? BigFloat(1) : BigFloat(0)
    length(gauge_rows) >= col || return nothing
    gauge_row = gauge_rows[col]
    try
        S = approx.Xhat[pivot_rows, pivot_rows]
        R = approx.Xhat[gauge_row, pivot_rows]
        y = -(S \ R)
        index = findfirst(==(row), pivot_rows)
        isnothing(index) && return row == gauge_row ? BigFloat(1) : BigFloat(0)
        return BigFloat(y[index])
    catch
        return nothing
    end
end

function _rationalize_bigfloat(value::BigFloat, tolerance::BigFloat)
    tol = tolerance == 0 ? eps(value) : tolerance
    rounded = rationalize(value; tol=tol)
    return Rational{BigInt}(numerator(rounded), denominator(rounded))
end

function _slice_rational(value; name::Symbol)
    if value isa Rational{BigInt}
        return value
    elseif value isa Rational
        return Rational{BigInt}(numerator(value), denominator(value))
    elseif value isa Integer
        return Rational{BigInt}(value, 1)
    elseif value isa AbstractString
        text = strip(String(value))
        m = match(r"^([+-]?\d+)(?:/(\d+))?$", text)
        isnothing(m) && throw(ArgumentError("$name is not a valid rational string: $value"))
        denominator_value = isnothing(m.captures[2]) ? BigInt(1) :
                            parse(BigInt, m.captures[2])
        denominator_value != 0 || throw(ArgumentError("$name has zero denominator"))
        return Rational{BigInt}(parse(BigInt, m.captures[1]), denominator_value)
    end
    throw(ArgumentError("$name must be an integer, rational, or rational string"))
end

function _dict_lookup(dict::AbstractDict, key::Symbol)
    haskey(dict, key) && return dict[key]
    string_key = String(key)
    haskey(dict, string_key) && return dict[string_key]
    return nothing
end

function _incidence_metadata(P::LMIProblem,
                             approx::ApproxSolution,
                             rank_profile::RankProfile,
                             m::Integer,
                             n::Integer,
                             r::Integer,
                             k::Integer,
                             gauge_rows::Vector{Int},
                             gauge_strategy::Symbol,
                             variable_names::Vector{Symbol},
                             kernel_variable_names::Vector{Symbol},
                             gauge_specs::Vector,
                             slicing_specs::Vector,
                             slicing_strategy::Symbol)
    incidence_count = m * k
    gauge_count = k * k
    slicing_count = length(slicing_specs)
    return Dict{Symbol, Any}(:kind => :incidence_system,
                             :builder => :kernel_incidence,
                             :certifier_context => :validation_algebraic_robustness,
                             :original_lmi_hash => lmi_problem_hash(P),
                             :approx_problem_hash => approx.problem_hash,
                             :matrix_size => m,
                             :num_lmi_variables => n,
                             :rank => r,
                             :kernel_dimension => k,
                             :pivot_cols => copy(rank_profile.pivot_cols),
                             :pivot_rows => copy(rank_profile.pivot_rows),
                             :gauge_rows => copy(gauge_rows),
                             :gauge_strategy => gauge_strategy,
                             :gauge_equations => gauge_specs,
                             :slicing_strategy => slicing_strategy,
                             :slicing_equations => String[
                                                          spec.expression
                                                          for spec in slicing_specs],
                             :slicing_equation_specs => slicing_specs,
                             :equation_blocks => (;
                                                  incidence=(start=1, stop=incidence_count,
                                                             count=incidence_count),
                                                  gauge=(start=incidence_count + 1,
                                                         stop=incidence_count + gauge_count,
                                                         count=gauge_count),
                                                  slicing=(start=incidence_count +
                                                                 gauge_count + 1,
                                                           stop=incidence_count +
                                                                gauge_count + slicing_count,
                                                           count=slicing_count),),
                             :variable_order => String.(variable_names),
                             :x_variables => String.(P.vars),
                             :kernel_variables => String.(kernel_variable_names),
                             :approx_xhat => string.(approx.xhat),
                             :approx_precision_bits => approx.precision_bits,
                             :rank_method => rank_profile.method,
                             :rank_tolerance => string(rank_profile.tolerance),
                             :rank_singular_values => string.(rank_profile.singular_values),
                             :rank_gap => string(rank_profile.gap))
end
