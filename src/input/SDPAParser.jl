const SDPA_PROBLEM_TYPE = "block_lmi_feasibility"
const SDPA_SOURCE_FORMAT = "sdpa_sparse"

"""
    read_sdpa(path) -> BlockLMIProblem

Read an SDPA sparse `.dat-s` file. SDPA stores problems in the form
`sum_i Fi xi - F0 >= 0`; CertSDP stores each block as
`A0 + sum_i xi Ai >= 0`, so imported blocks use `A0 = -F0` and `Ai = Fi`.
Finite decimal entries are converted exactly to rationals.
"""
read_sdpa(path::AbstractString) = parse_sdpa(read(path, String); source=path)

"""
    parse_sdpa(text; source="<memory>") -> BlockLMIProblem

Parse SDPA sparse text into a block LMI problem.
"""
function parse_sdpa(text::AbstractString; source::AbstractString="<memory>")
    tokens = _sdpa_numeric_tokens(text)
    length(tokens) >= 3 ||
        throw(ArgumentError("malformed SDPA input `$source`: expected mDIM, nBLOCK, block structure, objective vector, and sparse entries"))

    cursor = 1
    m_dim = _parse_sdpa_positive_integer(tokens[cursor], "mDIM")
    cursor += 1
    n_blocks = _parse_sdpa_positive_integer(tokens[cursor], "nBLOCK")
    cursor += 1

    length(tokens) >= cursor + n_blocks - 1 ||
        throw(ArgumentError("malformed SDPA input `$source`: block structure has fewer than $n_blocks entries"))
    block_structure = Int[]
    for j in 1:n_blocks
        value = _parse_sdpa_integer_token(tokens[cursor], "bLOCKsTRUCT[$j]")
        value != 0 ||
            throw(ArgumentError("malformed SDPA input `$source`: bLOCKsTRUCT[$j] must be nonzero"))
        push!(block_structure, value)
        cursor += 1
    end

    length(tokens) >= cursor + m_dim - 1 ||
        throw(ArgumentError("malformed SDPA input `$source`: objective vector has fewer than $m_dim entries"))
    objective = Rational{BigInt}[]
    for i in 1:m_dim
        push!(objective, _parse_sdpa_rational(tokens[cursor], "c[$i]"))
        cursor += 1
    end

    remaining = length(tokens) - cursor + 1
    remaining % 5 == 0 ||
        throw(ArgumentError("malformed SDPA input `$source`: sparse data rows must contain groups of 5 fields, found $remaining trailing numeric fields"))

    block_sizes_value = abs.(block_structure)
    matrices = [[zeros(Rational{BigInt}, block_sizes_value[j], block_sizes_value[j])
                 for j in 1:n_blocks]
                for _ in 0:m_dim]
    seen = [Set{Tuple{Int, Int}}() for _ in 1:(m_dim + 1), _ in 1:n_blocks]

    while cursor <= length(tokens)
        matrix_number = _parse_sdpa_integer_token(tokens[cursor],
                                                  "sparse row matrix number")
        block_number = _parse_sdpa_integer_token(tokens[cursor + 1],
                                                 "sparse row block number")
        row = _parse_sdpa_integer_token(tokens[cursor + 2], "sparse row row index")
        col = _parse_sdpa_integer_token(tokens[cursor + 3], "sparse row column index")
        value = _parse_sdpa_rational(tokens[cursor + 4], "sparse row value")
        cursor += 5

        0 <= matrix_number <= m_dim ||
            throw(ArgumentError("malformed SDPA input `$source`: matrix number $matrix_number is outside 0:$m_dim"))
        1 <= block_number <= n_blocks ||
            throw(ArgumentError("malformed SDPA input `$source`: block number $block_number is outside 1:$n_blocks"))

        block_size = block_sizes_value[block_number]
        1 <= row <= block_size ||
            throw(ArgumentError("malformed SDPA input `$source`: row index $row is outside block $block_number size $block_size"))
        1 <= col <= block_size ||
            throw(ArgumentError("malformed SDPA input `$source`: column index $col is outside block $block_number size $block_size"))

        if block_structure[block_number] < 0 && row != col
            throw(ArgumentError("malformed SDPA input `$source`: diagonal block $block_number cannot contain off-diagonal entry ($row, $col)"))
        end

        matrix_index = matrix_number + 1
        canonical_position = row <= col ? (row, col) : (col, row)
        _set_sdpa_sparse_entry!(matrices[matrix_index][block_number],
                                seen[matrix_index, block_number],
                                canonical_position,
                                value,
                                source,
                                matrix_number,
                                block_number)
    end

    vars = [Symbol("x", i) for i in 1:m_dim]
    block_problems = LMIProblem[]
    for block_number in 1:n_blocks
        F0 = matrices[1][block_number]
        A0 = -F0
        coefficients = [matrices[i + 1][block_number] for i in 1:m_dim]
        push!(block_problems, LMIProblem(A0, coefficients; vars))
    end

    kinds = [size < 0 ? :diagonal : :psd for size in block_structure]
    metadata = Dict{Symbol, Any}(:source_format => SDPA_SOURCE_FORMAT,
                                 :source => source,
                                 :sdpa_standard_form => "sum_i Fi xi - F0 >= 0")
    return BlockLMIProblem(block_problems; objective, block_kinds=kinds, metadata)
end

"""
    write_sdpa(problem, path)

Write an `LMIProblem` or `BlockLMIProblem` in canonical SDPA sparse format.
"""
function write_sdpa(P::LMIProblem, path::AbstractString; objective=nothing)
    return write_sdpa(BlockLMIProblem(P; objective), path)
end

function write_sdpa(P::BlockLMIProblem, path::AbstractString)
    open(path, "w") do io
        return write(io, sdpa_string(P))
    end
    return path
end

"""
    sdpa_string(problem) -> String

Return the canonical SDPA sparse text emitted by CertSDP.
"""
function sdpa_string(P::Union{LMIProblem, BlockLMIProblem})
    buffer = IOBuffer()
    write_sdpa(buffer, P)
    return String(take!(buffer))
end

function write_sdpa(io::IO, P::LMIProblem; objective=nothing)
    return write_sdpa(io, BlockLMIProblem(P; objective))
end

function write_sdpa(io::IO, P::BlockLMIProblem)
    println(io, "\"CertSDP SDPA sparse export\"")
    println(io, num_variables(P), " = mDIM")
    println(io, num_blocks(P), " = nBLOCK")
    println(io, join(string.(block_struct(P)), " "), " = bLOCKsTRUCT")
    println(io, join(_rational_string.(P.objective), ", "))

    for matrix_number in 0:num_variables(P)
        for (block_number, block) in enumerate(P.blocks)
            matrix = matrix_number == 0 ? -rational_matrix(block.A0) :
                     rational_matrix(block.A[matrix_number])
            _write_sdpa_matrix_entries(io, matrix_number, block_number, matrix,
                                       P.block_kinds[block_number])
        end
    end
    return nothing
end

"""
    block_lmi_problem_hash(problem) -> String

Return a stable hash for canonical block LMI data. The hash is independent of
SDPA comments, whitespace, sparse entry order, and decimal spelling.
"""
function block_lmi_problem_hash(P::BlockLMIProblem)
    return "sha256:" * bytes2hex(sha256(JSON3.write(block_lmi_problem_json(P))))
end

block_lmi_problem_hash(P::LMIProblem) = block_lmi_problem_hash(BlockLMIProblem(P))

function block_lmi_problem_json(P::BlockLMIProblem)
    return (;
            type=SDPA_PROBLEM_TYPE,
            field=LMI_FIELD,
            variables=String.(P.vars),
            objective=_rational_string.(P.objective),
            num_blocks=num_blocks(P),
            block_struct=block_struct(P),
            blocks=[(;
                     kind=String(kind),
                     matrix_size=matrix_size(block),
                     A0=_json_matrix(block.A0),
                     A=[(;
                         var=String(var),
                         matrix=_json_matrix(matrix),)
                        for (var, matrix) in zip(P.vars, block.A)],)
                    for (kind, block) in zip(P.block_kinds, P.blocks)],)
end

function _parse_block_lmi_problem_object(object; path::AbstractString="problem")
    _require_object(object, path)
    _require_value(object, :type, SDPA_PROBLEM_TYPE, "$path.type")
    _require_value(object, :field, LMI_FIELD, "$path.field")

    variables_value = _require_key(object, :variables, path)
    _require_array(variables_value, "$path.variables")
    variables = Symbol[]
    for (i, entry) in enumerate(variables_value)
        entry isa AbstractString ||
            throw(ArgumentError("$path.variables[$i] must be a string"))
        isempty(entry) && throw(ArgumentError("$path.variables[$i] must not be empty"))
        push!(variables, Symbol(String(entry)))
    end
    length(unique(variables)) == length(variables) ||
        throw(ArgumentError("$path.variables must be unique"))

    objective_value = _require_key(object, :objective, path)
    _require_array(objective_value, "$path.objective")
    length(objective_value) == length(variables) ||
        throw(ArgumentError("$path.objective has length $(length(objective_value)); expected $(length(variables))"))
    objective = [_parse_rational_string(value, "$path.objective[$i]")
                 for (i, value) in enumerate(objective_value)]

    num_blocks_value = _require_integer(object, :num_blocks, "$path.num_blocks")
    num_blocks_value > 0 || throw(ArgumentError("$path.num_blocks must be positive"))

    block_struct_value = _require_key(object, :block_struct, path)
    _require_array(block_struct_value, "$path.block_struct")
    length(block_struct_value) == num_blocks_value ||
        throw(ArgumentError("$path.block_struct has length $(length(block_struct_value)); expected $num_blocks_value"))
    block_struct = Int[]
    for (i, entry) in enumerate(block_struct_value)
        entry isa Integer ||
            throw(ArgumentError("$path.block_struct[$i] must be an integer"))
        value = Int(entry)
        value != 0 || throw(ArgumentError("$path.block_struct[$i] must be nonzero"))
        push!(block_struct, value)
    end

    blocks_value = _require_key(object, :blocks, path)
    _require_array(blocks_value, "$path.blocks")
    length(blocks_value) == num_blocks_value ||
        throw(ArgumentError("$path.blocks has length $(length(blocks_value)); expected $num_blocks_value"))

    blocks = LMIProblem[]
    block_kinds = Symbol[]
    for (i, block_object) in enumerate(blocks_value)
        block_path = "$path.blocks[$i]"
        _require_object(block_object, block_path)
        kind_text = _require_string(block_object, :kind, "$block_path.kind")
        kind = Symbol(kind_text)
        kind in (:psd, :diagonal) ||
            throw(ArgumentError("$block_path.kind must be `psd` or `diagonal`; got `$kind_text`"))
        expected_kind = block_struct[i] < 0 ? :diagonal : :psd
        kind === expected_kind ||
            throw(ArgumentError("$block_path.kind does not match $path.block_struct[$i]"))
        matrix_size_value = _require_integer(block_object, :matrix_size,
                                             "$block_path.matrix_size")
        matrix_size_value == abs(block_struct[i]) ||
            throw(ArgumentError("$block_path.matrix_size must match abs($path.block_struct[$i])"))
        matrix_size_value > 0 ||
            throw(ArgumentError("$block_path.matrix_size must be positive"))

        A0 = _parse_rational_matrix(_require_key(block_object, :A0, block_path),
                                    matrix_size_value,
                                    "$block_path.A0")
        A_entries = _require_key(block_object, :A, block_path)
        _require_array(A_entries, "$block_path.A")
        length(A_entries) == length(variables) ||
            throw(ArgumentError("$block_path.A has length $(length(A_entries)); expected $(length(variables))"))

        matrices = Matrix{Rational{BigInt}}[]
        for (j, entry) in enumerate(A_entries)
            entry_path = "$block_path.A[$j]"
            _require_object(entry, entry_path)
            var_name = _require_string(entry, :var, "$entry_path.var")
            var_name == String(variables[j]) ||
                throw(ArgumentError("$entry_path.var must be `$(String(variables[j]))`; got `$var_name`"))
            push!(matrices,
                  _parse_rational_matrix(_require_key(entry, :matrix, entry_path),
                                         matrix_size_value,
                                         "$entry_path.matrix"))
        end

        push!(blocks, LMIProblem(A0, matrices; vars=variables))
        push!(block_kinds, kind)
    end

    P = BlockLMIProblem(blocks; objective, block_kinds,
                        metadata=Dict{Symbol, Any}(:source_format => "schema_v1",
                                                   :source => path))
    if haskey(object, :hash)
        expected_hash = _require_string(object, :hash, "$path.hash")
        actual_hash = block_lmi_problem_hash(P)
        expected_hash == actual_hash ||
            throw(ArgumentError("$path.hash mismatch: expected $expected_hash, computed $actual_hash"))
    end
    return P
end

function _write_sdpa_matrix_entries(io::IO, matrix_number::Integer,
                                    block_number::Integer,
                                    matrix::AbstractMatrix{<:Rational},
                                    kind::Symbol)
    if kind === :diagonal
        for i in axes(matrix, 1)
            value = matrix[i, i]
            value == 0 && continue
            println(io, matrix_number, " ", block_number, " ", i, " ", i, " ",
                    _rational_string(value))
        end
        return nothing
    end

    for col in axes(matrix, 2), row in 1:col
        value = matrix[row, col]
        value == 0 && continue
        println(io, matrix_number, " ", block_number, " ", row, " ", col, " ",
                _rational_string(value))
    end
    return nothing
end

function _set_sdpa_sparse_entry!(matrix::Matrix{Rational{BigInt}},
                                 seen::Set{Tuple{Int, Int}},
                                 position::Tuple{Int, Int},
                                 value::Rational{BigInt},
                                 source::AbstractString,
                                 matrix_number::Integer,
                                 block_number::Integer)
    row, col = position
    if position in seen
        matrix[row, col] == value ||
            throw(ArgumentError("malformed SDPA input `$source`: duplicate entry for matrix $matrix_number block $block_number position ($row, $col) has conflicting values $(matrix[row, col]) and $value"))
        return matrix
    end

    push!(seen, position)
    matrix[row, col] = value
    matrix[col, row] = value
    return matrix
end

function _sdpa_numeric_tokens(text::AbstractString)
    tokens = String[]
    for (line_number, raw_line) in enumerate(split(text, '\n'))
        line = _strip_sdpa_comment(raw_line)
        isempty(strip(line)) && continue

        cleaned = replace(line,
                          '{' => ' ',
                          '}' => ' ',
                          '[' => ' ',
                          ']' => ' ',
                          '(' => ' ',
                          ')' => ' ',
                          ',' => ' ',
                          ';' => ' ')
        for token in split(cleaned)
            token == "=" && continue
            if _is_sdpa_numeric_token(token)
                push!(tokens, token)
            elseif _looks_like_broken_number(token)
                throw(ArgumentError("malformed SDPA input at line $line_number: invalid numeric token `$token`"))
            end
        end
    end
    return tokens
end

function _strip_sdpa_comment(line::AbstractString)
    stripped = strip(line)
    (isempty(stripped) || startswith(stripped, "\"") || startswith(stripped, "*") ||
     startswith(stripped, "#") || startswith(stripped, "%")) &&
        return ""

    cut = lastindex(line) + 1
    for marker in ('#', '%')
        index = findfirst(==(marker), line)
        isnothing(index) || (cut = min(cut, index))
    end
    quote_index = findfirst(==('"'), line)
    isnothing(quote_index) || (cut = min(cut, quote_index))
    cut <= firstindex(line) && return ""
    return cut <= lastindex(line) ? line[firstindex(line):prevind(line, cut)] : line
end

const SDPA_INTEGER_TOKEN_RE = r"^[+-]?\d+$"
const SDPA_RATIONAL_TOKEN_RE = r"^[+-]?\d+/\d+$"
const SDPA_DECIMAL_TOKEN_RE = r"^[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eEdD][+-]?\d+)?$"

function _is_sdpa_numeric_token(token::AbstractString)
    return occursin(SDPA_INTEGER_TOKEN_RE, token) ||
           occursin(SDPA_RATIONAL_TOKEN_RE, token) ||
           occursin(SDPA_DECIMAL_TOKEN_RE, token)
end

function _looks_like_broken_number(token::AbstractString)
    occursin(r"\d", token) || return false
    occursin(r"[A-Za-z_]", token) && return false
    return true
end

function _parse_sdpa_positive_integer(token::AbstractString, path::AbstractString)
    value = _parse_sdpa_integer_token(token, path)
    value > 0 ||
        throw(ArgumentError("malformed SDPA input: $path must be positive; got $value"))
    return value
end

function _parse_sdpa_integer_token(token::AbstractString, path::AbstractString)
    occursin(SDPA_INTEGER_TOKEN_RE, token) ||
        throw(ArgumentError("malformed SDPA input: $path must be an integer; got `$token`"))
    return parse(Int, token)
end

function _parse_sdpa_rational(token::AbstractString, path::AbstractString)
    if occursin(SDPA_RATIONAL_TOKEN_RE, token)
        parts = split(token, '/')
        denominator_value = parse(BigInt, parts[2])
        denominator_value != 0 ||
            throw(ArgumentError("malformed SDPA input: $path has zero denominator"))
        return Rational{BigInt}(parse(BigInt, parts[1]), denominator_value)
    elseif occursin(SDPA_INTEGER_TOKEN_RE, token)
        return Rational{BigInt}(parse(BigInt, token), BigInt(1))
    elseif occursin(SDPA_DECIMAL_TOKEN_RE, token)
        return _parse_sdpa_decimal_exact(token, path)
    end

    throw(ArgumentError("malformed SDPA input: $path is not an exact rational or finite decimal: `$token`"))
end

function _parse_sdpa_decimal_exact(token::AbstractString, path::AbstractString)
    normalized = replace(String(token), 'D' => 'e', 'd' => 'e')
    m = match(r"^([+-]?)(?:(\d+)(?:\.(\d*))?|(?:\.(\d+)))(?:[eE]([+-]?\d+))?$",
              normalized)
    isnothing(m) &&
        throw(ArgumentError("malformed SDPA input: $path is not a finite decimal: `$token`"))

    sign_text = m.captures[1]
    integer_part = isnothing(m.captures[2]) ? "" : m.captures[2]
    fractional_part = if !isnothing(m.captures[3])
        m.captures[3]
    elseif !isnothing(m.captures[4])
        m.captures[4]
    else
        ""
    end
    exponent = isnothing(m.captures[5]) ? 0 : parse(Int, m.captures[5])

    digits = integer_part * fractional_part
    isempty(digits) &&
        throw(ArgumentError("malformed SDPA input: $path is not a finite decimal: `$token`"))
    numerator_value = parse(BigInt, digits)
    sign_text == "-" && (numerator_value = -numerator_value)

    scale = length(fractional_part) - exponent
    if scale >= 0
        return Rational{BigInt}(numerator_value, BigInt(10)^scale)
    end
    return Rational{BigInt}(numerator_value * BigInt(10)^(-scale), BigInt(1))
end

function _is_sdpa_path(path::AbstractString)
    lower = lowercase(path)
    return endswith(lower, ".dat-s") || endswith(lower, ".dats") ||
           endswith(lower, ".sdpa")
end
