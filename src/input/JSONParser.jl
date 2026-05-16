using JSON3: JSON3
using SHA: sha256

const LMI_JSON_VERSION = "0.1"
const LMI_PROBLEM_TYPE = "lmi_feasibility"
const LMI_FIELD = "QQ"

"""
    lmi_problem_hash(P::LMIProblem) -> String

Return the stable SHA-256 hash for the canonical JSON representation of `P`.
The digest is independent of JSON whitespace and of any input `hash` field.
"""
function lmi_problem_hash(P::LMIProblem)
    canonical = _canonical_lmi_problem_json(P)
    return "sha256:" * bytes2hex(sha256(JSON3.write(canonical)))
end

"""
    lmi_problem_json(P::LMIProblem) -> NamedTuple

Return the LMI problem JSON object for `P`. Rational entries are exported as
strings such as `"3/5"` and `"-2"`.
"""
function lmi_problem_json(P::LMIProblem)
    problem = _canonical_lmi_problem_json(P)
    problem_with_hash = merge(problem, (; hash=lmi_problem_hash(P)))
    return (;
            certsdp_version=LMI_JSON_VERSION,
            problem=problem_with_hash,)
end

"""
    lmi_problem_json_string(P::LMIProblem) -> String

Return a pretty-printed JSON string for `P`.
"""
function lmi_problem_json_string(P::LMIProblem)
    io = IOBuffer()
    JSON3.pretty(io, lmi_problem_json(P))
    println(io)
    return String(take!(io))
end

"""
    write_lmi_json(path, P::LMIProblem)

Write `P` in CertSDP LMI JSON v0.1 format.
"""
function write_lmi_json(path::AbstractString, P::LMIProblem)
    open(path, "w") do io
        return write(io, lmi_problem_json_string(P))
    end
    return path
end

"""
    read_lmi_json(path) -> LMIProblem

Read a CertSDP LMI JSON v0.1 problem from `path`.
"""
function read_lmi_json(path::AbstractString)
    return parse_lmi_json(read(path, String))
end

"""
    read_approx_solution_json(path; kwargs...) -> ApproxSolution

Read a CertSDP LMI JSON file containing an `approximate_solution.xhat` block.
"""
function read_approx_solution_json(path::AbstractString; kwargs...)
    return parse_approx_solution_json(read(path, String); kwargs...)
end

"""
    parse_lmi_json(json_text) -> LMIProblem

Parse a CertSDP LMI JSON v0.1 problem. If the JSON contains a problem hash, it
must match the canonical hash computed after parsing.
"""
function parse_lmi_json(json_text::AbstractString)
    parsed = try
        JSON3.read(json_text)
    catch err
        throw(ArgumentError("invalid LMI JSON: $(sprint(showerror, err))"))
    end

    _require_object(parsed, "root")
    _require_value(parsed, :certsdp_version, LMI_JSON_VERSION, "root.certsdp_version")
    problem = _require_key(parsed, :problem, "root")
    return _parse_lmi_problem_object(problem)
end

"""
    parse_approx_solution_json(json_text; kwargs...) -> ApproxSolution

Parse a CertSDP LMI JSON v0.1 object with approximate numerical data:

```json
{
  "certsdp_version": "0.1",
  "problem": { "...": "..." },
  "approximate_solution": {
    "type": "xhat",
    "precision_bits": 256,
    "xhat": ["1.0", "0.0"]
  }
}
```

An optional `Xhat` matrix may be supplied; if absent, it is recomputed from
`problem` and `xhat`.
"""
function parse_approx_solution_json(json_text::AbstractString; kwargs...)
    parsed = try
        JSON3.read(json_text)
    catch err
        throw(ArgumentError("invalid approximate solution JSON: $(sprint(showerror, err))"))
    end

    _require_object(parsed, "root")
    _require_value(parsed, :certsdp_version, LMI_JSON_VERSION, "root.certsdp_version")
    problem = _parse_lmi_problem_object(_require_key(parsed, :problem, "root"))
    approx = _require_key(parsed, :approximate_solution, "root")
    return _parse_approx_solution_object(problem, approx; kwargs...)
end

function _parse_lmi_problem_object(problem)
    _require_object(problem, "problem")
    _require_value(problem, :type, LMI_PROBLEM_TYPE, "problem.type")
    _require_value(problem, :field, LMI_FIELD, "problem.field")

    matrix_size_value = _require_integer(problem, :matrix_size, "problem.matrix_size")
    matrix_size_value > 0 || throw(ArgumentError("problem.matrix_size must be positive"))

    num_variables_value = _require_integer(problem, :num_variables, "problem.num_variables")
    num_variables_value >= 0 ||
        throw(ArgumentError("problem.num_variables must be nonnegative"))

    vars = _parse_vars(_require_key(problem, :vars, "problem"), num_variables_value)
    A0 = _parse_rational_matrix(_require_key(problem, :A0, "problem"), matrix_size_value,
                                "problem.A0")
    A = _parse_matrix_list(_require_key(problem, :A, "problem"), matrix_size_value,
                           num_variables_value)

    P = try
        LMIProblem(A0, A; vars)
    catch err
        throw(ArgumentError("invalid LMI problem data: $(sprint(showerror, err))"))
    end

    if haskey(problem, :hash)
        expected_hash = _require_string(problem, :hash, "problem.hash")
        actual_hash = lmi_problem_hash(P)
        expected_hash == actual_hash ||
            throw(ArgumentError("problem.hash mismatch: expected $expected_hash, computed $actual_hash"))
    end

    return P
end

function _parse_approx_solution_object(problem::Union{LMIProblem, BlockLMIProblem},
                                       approx;
                                       precision_bits=nothing,
                                       kwargs...)
    _require_object(approx, "approximate_solution")

    if haskey(approx, :type)
        _require_value(approx, :type, "xhat", "approximate_solution.type")
    end

    parsed_precision = if isnothing(precision_bits)
        haskey(approx, :precision_bits) ?
        _require_integer(approx, :precision_bits, "approximate_solution.precision_bits") :
        DEFAULT_APPROX_PRECISION_BITS
    else
        Int(precision_bits)
    end
    parsed_precision > 0 ||
        throw(ArgumentError("approximate_solution.precision_bits must be positive"))

    xhat = _require_key(approx, :xhat, "approximate_solution")
    _require_array(xhat, "approximate_solution.xhat")

    Xhat = if haskey(approx, :Xhat)
        matrix = _require_key(approx, :Xhat, "approximate_solution")
        _require_array(matrix, "approximate_solution.Xhat")
        matrix
    else
        nothing
    end

    slicing_hints = _parse_approx_slicing_hints(approx)
    solver_name = haskey(approx, :solver_name) ?
                  Symbol(_require_string(approx, :solver_name,
                                         "approximate_solution.solver_name")) :
                  :user
    solver_status = haskey(approx, :solver_status) ?
                    Symbol(_require_string(approx, :solver_status,
                                           "approximate_solution.solver_status")) :
                    :user_supplied
    objective_kind = haskey(approx, :objective_kind) ?
                     Symbol(_require_string(approx, :objective_kind,
                                            "approximate_solution.objective_kind")) :
                     :user
    objective_value = haskey(approx, :objective_value) ?
                      _require_key(approx, :objective_value, "approximate_solution") :
                      nothing
    objective_vector = if haskey(approx, :objective_vector)
        vector = _require_key(approx, :objective_vector, "approximate_solution")
        _require_array(vector, "approximate_solution.objective_vector")
        vector
    else
        nothing
    end
    attempt_index = haskey(approx, :attempt_index) ?
                    _require_integer(approx, :attempt_index,
                                     "approximate_solution.attempt_index") : 1
    retry_index = haskey(approx, :retry_index) ?
                  _require_integer(approx, :retry_index,
                                   "approximate_solution.retry_index") : 1
    primal_residual = haskey(approx, :primal_residual) ?
                      _require_key(approx, :primal_residual,
                                   "approximate_solution") : nothing
    dual_residual = haskey(approx, :dual_residual) ?
                    _require_key(approx, :dual_residual,
                                 "approximate_solution") : nothing

    rank_options = Dict{Symbol, Any}()
    if haskey(approx, :rank_detection)
        rank_detection = _require_key(approx, :rank_detection, "approximate_solution")
        _require_object(rank_detection, "approximate_solution.rank_detection")
        if haskey(rank_detection, :relative_tolerance)
            rank_options[:relative_tolerance] = _require_string(rank_detection,
                                                                :relative_tolerance,
                                                                "approximate_solution.rank_detection.relative_tolerance")
        end
        if haskey(rank_detection, :gap_threshold)
            rank_options[:gap_threshold] = _require_string(rank_detection, :gap_threshold,
                                                           "approximate_solution.rank_detection.gap_threshold")
        end
        if haskey(rank_detection, :absolute_tolerance)
            absolute = _require_key(rank_detection, :absolute_tolerance,
                                    "approximate_solution.rank_detection")
            if !isnothing(absolute)
                absolute isa AbstractString ||
                    throw(ArgumentError("approximate_solution.rank_detection.absolute_tolerance must be a string or null"))
                rank_options[:absolute_tolerance] = String(absolute)
            end
        end
    end
    for (key, value) in pairs(kwargs)
        rank_options[Symbol(key)] = value
    end

    oracle_metadata = haskey(approx, :oracle_metadata) ?
                      _json_object_to_symbol_dict(_require_key(approx,
                                                               :oracle_metadata,
                                                               "approximate_solution")) :
                      nothing
    return ApproxSolution(problem, xhat; precision_bits=parsed_precision, Xhat,
                          slicing_hints=slicing_hints,
                          solver_name,
                          solver_status,
                          objective_kind,
                          objective_value,
                          objective_vector,
                          attempt_index,
                          retry_index,
                          solver_primal_residual=primal_residual,
                          solver_dual_residual=dual_residual,
                          oracle_metadata,
                          rank_options...)
end

function approximate_solution_json(approx)
    report = approx.quality_report
    metadata = Dict{String, Any}(String(key) => _certification_diagnostics_json(value)
                                 for (key, value) in approx.oracle_metadata)
    return (;
            certsdp_version=LMI_JSON_VERSION,
            approximate_solution=(;
                                  type="xhat",
                                  precision_bits=approx.precision_bits,
                                  xhat=string.(approx.xhat),
                                  solver_name=String(report.solver_name),
                                  solver_status=String(report.solver_status),
                                  objective_kind=String(report.objective_kind),
                                  objective_vector=string.(report.objective_vector),
                                  objective_value=isnothing(report.objective_value) ?
                                                  nothing : string(report.objective_value),
                                  primal_residual=isnothing(report.primal_residual) ?
                                                  nothing : string(report.primal_residual),
                                  dual_residual=isnothing(report.dual_residual) ?
                                                nothing : string(report.dual_residual),
                                  trace=string(report.trace_value),
                                  face_clarity=String(report.face_clarity),
                                  face_clarity_score=string(report.face_clarity_score),
                                  rank_detection=(;
                                                  relative_tolerance=string(get(approx.oracle_metadata,
                                                                                :rank_relative_tolerance,
                                                                                DEFAULT_RANK_RELATIVE_TOLERANCE)),
                                                  gap_threshold=string(get(approx.oracle_metadata,
                                                                           :rank_gap_threshold,
                                                                           DEFAULT_RANK_GAP_THRESHOLD)),
                                                  absolute_tolerance=get(approx.oracle_metadata,
                                                                         :rank_absolute_tolerance,
                                                                         nothing),),
                                  attempt_index=report.attempt_index,
                                  retry_index=report.retry_index,
                                  oracle_metadata=metadata,),)
end

function approximate_solution_json_string(approx)
    io = IOBuffer()
    JSON3.pretty(io, approximate_solution_json(approx))
    println(io)
    return String(take!(io))
end

function write_approx_solution_json(path::AbstractString, approx)
    open(path, "w") do io
        return write(io, approximate_solution_json_string(approx))
    end
    return path
end

function _parse_approx_slicing_hints(approx)
    haskey(approx, :slicing) || return nothing
    slicing = _require_key(approx, :slicing, "approximate_solution")
    _require_object(slicing, "approximate_solution.slicing")

    hints = Dict{Symbol, Any}()
    if haskey(slicing, :strategy)
        hints[:strategy] = _require_string(slicing, :strategy,
                                           "approximate_solution.slicing.strategy")
    end
    if haskey(slicing, :equations)
        equations = _require_key(slicing, :equations, "approximate_solution.slicing")
        _require_array(equations, "approximate_solution.slicing.equations")
        hints[:equations] = [_parse_slicing_equation_object(equation,
                                                            "approximate_solution.slicing.equations[$i]")
                             for (i, equation) in enumerate(equations)]
    end
    if haskey(slicing, :gauge_rows)
        rows = _require_key(slicing, :gauge_rows, "approximate_solution.slicing")
        _require_array(rows, "approximate_solution.slicing.gauge_rows")
        parsed_rows = Int[]
        for (i, row) in enumerate(rows)
            row isa Integer ||
                throw(ArgumentError("approximate_solution.slicing.gauge_rows[$i] must be an integer"))
            push!(parsed_rows, Int(row))
        end
        hints[:gauge_rows] = parsed_rows
    end
    if haskey(slicing, :max_attempts)
        hints[:max_attempts] = _require_integer(slicing, :max_attempts,
                                                "approximate_solution.slicing.max_attempts")
    end
    return hints
end

function _parse_slicing_equation_object(equation, path::AbstractString)
    _require_object(equation, path)
    coefficients = _require_key(equation, :coefficients, path)
    _require_object(coefficients, "$path.coefficients")
    parsed_coefficients = Dict{Symbol, Rational{BigInt}}()
    for key in keys(coefficients)
        parsed_coefficients[Symbol(String(key))] = _parse_rational_string(coefficients[key],
                                                                          "$path.coefficients.$(String(key))")
    end
    rhs = haskey(equation, :rhs) ?
          _parse_rational_string(_require_key(equation, :rhs, path), "$path.rhs") :
          0 // 1
    label = haskey(equation, :label) ?
            _require_string(equation, :label, "$path.label") : ""
    return Dict{Symbol, Any}(:coefficients => parsed_coefficients,
                             :rhs => rhs,
                             :label => label)
end

function _canonical_lmi_problem_json(P::LMIProblem)
    return (;
            type=LMI_PROBLEM_TYPE,
            field=LMI_FIELD,
            matrix_size=matrix_size(P),
            num_variables=num_variables(P),
            vars=String.(P.vars),
            A0=_json_matrix(P.A0),
            A=[_json_matrix(matrix) for matrix in P.A],)
end

function _json_matrix(M::SymmetricRationalMatrix)
    entries = rational_matrix(M)
    return [[_rational_string(entries[i, j]) for j in axes(entries, 2)]
            for i in axes(entries, 1)]
end

function _rational_string(q::Rational)
    return denominator(q) == 1 ? string(numerator(q)) :
           string(numerator(q), "/", denominator(q))
end

function _parse_vars(value, expected_length::Integer)
    _require_array(value, "problem.vars")
    length(value) == expected_length ||
        throw(ArgumentError("problem.vars has length $(length(value)); expected $expected_length"))

    vars = Symbol[]
    for (i, entry) in enumerate(value)
        entry isa AbstractString ||
            throw(ArgumentError("problem.vars[$i] must be a string"))
        isempty(entry) && throw(ArgumentError("problem.vars[$i] must not be empty"))
        push!(vars, Symbol(String(entry)))
    end
    return vars
end

function _parse_matrix_list(value, matrix_size_value::Integer, expected_length::Integer)
    _require_array(value, "problem.A")
    length(value) == expected_length ||
        throw(ArgumentError("problem.A has length $(length(value)); expected $expected_length"))

    return [_parse_rational_matrix(matrix, matrix_size_value, "problem.A[$i]")
            for (i, matrix) in enumerate(value)]
end

function _parse_rational_matrix(value, expected_size::Integer, path::AbstractString)
    _require_array(value, path)
    length(value) == expected_size ||
        throw(ArgumentError("$path has $(length(value)) rows; expected $expected_size"))

    rows = Vector{Vector{Rational{BigInt}}}(undef, expected_size)
    for (i, row) in enumerate(value)
        row_path = "$path[$i]"
        _require_array(row, row_path)
        length(row) == expected_size ||
            throw(ArgumentError("$row_path has $(length(row)) entries; expected $expected_size"))
        rows[i] = [_parse_rational_string(entry, "$row_path[$j]")
                   for (j, entry) in enumerate(row)]
    end

    return [rows[i][j] for i in 1:expected_size, j in 1:expected_size]
end

function _parse_rational_string(value, path::AbstractString)
    value isa AbstractString || throw(ArgumentError("$path must be a rational string"))
    text = strip(String(value))
    m = match(r"^([+-]?\d+)(?:/(\d+))?$", text)
    isnothing(m) && throw(ArgumentError("$path is not a valid rational string: $value"))

    numerator_value = parse(BigInt, m.captures[1])
    denominator_value = isnothing(m.captures[2]) ? BigInt(1) : parse(BigInt, m.captures[2])
    denominator_value != 0 || throw(ArgumentError("$path has zero denominator"))
    return Rational{BigInt}(numerator_value, denominator_value)
end

function _require_key(object, key::Symbol, path::AbstractString)
    haskey(object, key) || throw(ArgumentError("$path is missing required key `$key`"))
    return getproperty(object, key)
end

function _require_value(object, key::Symbol, expected, path::AbstractString)
    actual = _require_key(object, key, split(path, ".")[1])
    actual == expected || throw(ArgumentError("$path must be `$expected`; got `$actual`"))
    return actual
end

function _require_string(object, key::Symbol, path::AbstractString)
    value = _require_key(object, key, split(path, ".")[1])
    value isa AbstractString || throw(ArgumentError("$path must be a string"))
    return String(value)
end

function _require_integer(object, key::Symbol, path::AbstractString)
    value = _require_key(object, key, split(path, ".")[1])
    value isa Integer || throw(ArgumentError("$path must be an integer"))
    return Int(value)
end

function _require_object(value, path::AbstractString)
    return value isa JSON3.Object || throw(ArgumentError("$path must be a JSON object"))
end

function _require_array(value, path::AbstractString)
    return value isa JSON3.Array || throw(ArgumentError("$path must be a JSON array"))
end
