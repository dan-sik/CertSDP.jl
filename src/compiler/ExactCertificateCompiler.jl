const CERTSDP_2_0_ARTIFACT_VERSION = "2.0"

abstract type ExactFieldSpec end

struct RationalFieldSpec <: ExactFieldSpec end

struct QuadraticField <: ExactFieldSpec
    d::Int

    function QuadraticField(d::Integer)
        value = Int(d)
        value > 1 || throw(ArgumentError("quadratic field radicand must be > 1"))
        _is_square_integer(value) &&
            throw(ArgumentError("quadratic field radicand must be squarefree and nonsquare"))
        return new(_squarefree_part(value))
    end
end

struct MultiquadraticField <: ExactFieldSpec
    radicands::Vector{Int}

    function MultiquadraticField(radicands::AbstractVector{<:Integer})
        normalized = sort(unique(_squarefree_part(Int(d)) for d in radicands))
        isempty(normalized) &&
            throw(ArgumentError("multiquadratic field needs at least one radicand"))
        any(d -> d <= 1 || _is_square_integer(d), normalized) &&
            throw(ArgumentError("multiquadratic radicands must be nonsquare integers > 1"))
        return new(normalized)
    end
end

struct CyclotomicField <: ExactFieldSpec
    n::Int

    function CyclotomicField(n::Integer)
        value = Int(n)
        value >= 3 || throw(ArgumentError("cyclotomic conductor must be at least 3"))
        return new(value)
    end
end

struct AlgebraicFieldSpec <: ExactFieldSpec
    minimal_polynomial::UnivariatePolynomial
    root_symbol::Symbol

    function AlgebraicFieldSpec(minimal_polynomial::UnivariatePolynomial;
                                root_symbol::Symbol=:alpha)
        degree(minimal_polynomial) >= 2 ||
            throw(ArgumentError("general algebraic field needs degree >= 2"))
        return new(_root_monic_polynomial(minimal_polynomial), root_symbol)
    end
end

const QQ = RationalFieldSpec()

Base.:(==)(::RationalFieldSpec, ::RationalFieldSpec) = true
Base.hash(::RationalFieldSpec, h::UInt) = hash(:QQ, h)
Base.show(io::IO, ::RationalFieldSpec) = print(io, "QQ")
Base.:(==)(a::QuadraticField, b::QuadraticField) = a.d == b.d
Base.hash(field::QuadraticField, h::UInt) = hash((:QuadraticField, field.d), h)
Base.show(io::IO, field::QuadraticField) = print(io, "QuadraticField(", field.d, ")")
Base.:(==)(a::MultiquadraticField, b::MultiquadraticField) = a.radicands == b.radicands
function Base.hash(field::MultiquadraticField, h::UInt)
    return hash((:MultiquadraticField, field.radicands), h)
end
function Base.show(io::IO, field::MultiquadraticField)
    return print(io, "MultiquadraticField(", field.radicands, ")")
end
Base.:(==)(a::CyclotomicField, b::CyclotomicField) = a.n == b.n
Base.hash(field::CyclotomicField, h::UInt) = hash((:CyclotomicField, field.n), h)
Base.show(io::IO, field::CyclotomicField) = print(io, "CyclotomicField(", field.n, ")")
function Base.:(==)(a::AlgebraicFieldSpec, b::AlgebraicFieldSpec)
    return a.minimal_polynomial == b.minimal_polynomial &&
           a.root_symbol == b.root_symbol
end
function Base.hash(field::AlgebraicFieldSpec, h::UInt)
    return hash((:AlgebraicFieldSpec,
                 field.minimal_polynomial,
                 field.root_symbol), h)
end
function Base.show(io::IO, field::AlgebraicFieldSpec)
    return print(io, "AlgebraicFieldSpec(", field.minimal_polynomial, ")")
end

struct FieldElement
    field::ExactFieldSpec
    coeffs::Dict{Vector{Int}, Rational{BigInt}}

    function FieldElement(field::ExactFieldSpec,
                          coeffs::AbstractDict{<:Any, <:Any})
        normalized = Dict{Vector{Int}, Rational{BigInt}}()
        for (basis, coefficient) in coeffs
            parsed_basis = _normalize_field_basis_key(field, basis)
            parsed_coefficient = _to_big_rational(coefficient; name=:field_coefficient)
            iszero(parsed_coefficient) && continue
            normalized[parsed_basis] = get(normalized, parsed_basis, 0 // 1) +
                                       parsed_coefficient
            iszero(normalized[parsed_basis]) && delete!(normalized, parsed_basis)
        end
        if isempty(normalized)
            normalized[Int[]] = 0 // 1
        end
        return new(field, normalized)
    end
end

function FieldElement(field::ExactFieldSpec, value::Integer)
    return FieldElement(field, Dict(Int[] => value))
end
function FieldElement(field::ExactFieldSpec, value::Rational)
    return FieldElement(field, Dict(Int[] => value))
end
function FieldElement(field::ExactFieldSpec, value::AbstractString)
    return FieldElement(field, _parse_field_element_dict(field, value))
end

Base.zero(x::FieldElement) = FieldElement(x.field, 0)
Base.one(x::FieldElement) = FieldElement(x.field, 1)
function Base.iszero(x::FieldElement)
    return length(x.coeffs) == 1 && haskey(x.coeffs, Int[]) &&
           iszero(x.coeffs[Int[]])
end
function Base.:(==)(a::FieldElement, b::FieldElement)
    a.field == b.field || return false
    return _canonical_field_coeffs(a.coeffs) == _canonical_field_coeffs(b.coeffs)
end
Base.:(==)(a::FieldElement, b::Integer) = a == FieldElement(a.field, b)
Base.:(==)(a::Integer, b::FieldElement) = FieldElement(b.field, a) == b
Base.:(==)(a::FieldElement, b::Rational) = a == FieldElement(a.field, b)
Base.:(==)(a::Rational, b::FieldElement) = FieldElement(b.field, a) == b

function Base.:+(a::FieldElement, b::FieldElement)
    field = _common_field(a, b)
    coeffs = Dict{Vector{Int}, Rational{BigInt}}()
    for (basis, coefficient) in a.coeffs
        coeffs[basis] = get(coeffs, basis, 0 // 1) + coefficient
    end
    for (basis, coefficient) in b.coeffs
        coeffs[basis] = get(coeffs, basis, 0 // 1) + coefficient
    end
    return FieldElement(field, coeffs)
end
Base.:+(a::FieldElement, b::Integer) = a + FieldElement(a.field, b)
Base.:+(a::Integer, b::FieldElement) = FieldElement(b.field, a) + b
Base.:+(a::FieldElement, b::Rational) = a + FieldElement(a.field, b)
Base.:+(a::Rational, b::FieldElement) = FieldElement(b.field, a) + b

function Base.:-(a::FieldElement)
    return FieldElement(a.field,
                        Dict(basis => -coefficient
                             for (basis, coefficient) in a.coeffs))
end
Base.:-(a::FieldElement, b::FieldElement) = a + (-b)
Base.:-(a::FieldElement, b::Integer) = a - FieldElement(a.field, b)
Base.:-(a::Integer, b::FieldElement) = FieldElement(b.field, a) - b
Base.:-(a::FieldElement, b::Rational) = a - FieldElement(a.field, b)
Base.:-(a::Rational, b::FieldElement) = FieldElement(b.field, a) - b

function Base.:*(a::FieldElement, b::FieldElement)
    field = _common_field(a, b)
    coeffs = Dict{Vector{Int}, Rational{BigInt}}()
    for (left_basis, left_coefficient) in a.coeffs
        for (right_basis, right_coefficient) in b.coeffs
            basis, scale = _multiply_field_basis(field, left_basis, right_basis)
            coeffs[basis] = get(coeffs, basis, 0 // 1) +
                            left_coefficient * right_coefficient * scale
        end
    end
    return FieldElement(field, coeffs)
end
Base.:*(a::FieldElement, b::Integer) = a * FieldElement(a.field, b)
Base.:*(a::Integer, b::FieldElement) = FieldElement(b.field, a) * b
Base.:*(a::FieldElement, b::Rational) = a * FieldElement(a.field, b)
Base.:*(a::Rational, b::FieldElement) = FieldElement(b.field, a) * b

function Base.show(io::IO, x::FieldElement)
    return print(io, field_element_string(x))
end

struct ExactCertificateStatus
    status::Symbol
    failure_stage::Union{Nothing, Symbol}
    message::String
end

struct ExactCertificateBlock
    id::String
    dimension::Int
    rank::Int
    clique::Vector{Int}
    constraint::Union{Nothing, String}
    factor::Vector{Vector{FieldElement}}
    gram_entries::Dict{Tuple{Int, Int}, FieldElement}
    duplicate_of::Union{Nothing, String}
    metadata::Dict{Symbol, Any}
end

struct ExactCertificateArtifact
    type::Symbol
    num_variables::Int
    field::ExactFieldSpec
    blocks::Vector{ExactCertificateBlock}
    structure::NamedTuple
    problem::Dict{Symbol, Any}
    certificate::Dict{Symbol, Any}
    reconstruction_log::Vector{String}
    verification_plan::Vector{Symbol}
    failure_diagnostics::Vector{String}
    hashes::Dict{Symbol, String}
    metadata::Dict{Symbol, Any}
end

struct ReconstructResult
    status::Symbol
    certificate::Union{Nothing, ExactCertificateArtifact}
    failure_stage::Union{Nothing, Symbol}
    message::String
end

struct ExactArtifactJSONString <: AbstractString
    data::String
    reported_size::Int
end

Base.ncodeunits(text::ExactArtifactJSONString) = ncodeunits(text.data)
Base.codeunit(text::ExactArtifactJSONString) = codeunit(text.data)
Base.iterate(text::ExactArtifactJSONString, state...) = iterate(text.data, state...)
Base.isvalid(text::ExactArtifactJSONString, i::Integer) = isvalid(text.data, i)
Base.length(text::ExactArtifactJSONString) = length(text.data)
Base.String(text::ExactArtifactJSONString) = text.data
Base.convert(::Type{String}, text::ExactArtifactJSONString) = text.data
Base.show(io::IO, text::ExactArtifactJSONString) = show(io, text.data)
Base.print(io::IO, text::ExactArtifactJSONString) = print(io, text.data)
Base.filesize(text::ExactArtifactJSONString) = text.reported_size

function Base.getproperty(cert::ExactCertificateArtifact, name::Symbol)
    return _exact_certificate_getproperty(cert, name)
end

function _exact_certificate_getproperty(cert::ExactCertificateArtifact, name::Symbol)
    if name === :num_blocks
        return length(getfield(cert, :blocks))
    elseif name === :original_dimension
        return Int(get(getfield(cert, :metadata), :original_dimension, 0))
    elseif name === :reduced_total_dimension
        return Int(get(getfield(cert, :metadata), :reduced_total_dimension,
                       total_block_dim(cert)))
    elseif name === :psd_method
        return Symbol(get(getfield(cert, :metadata), :psd_method, :exact_low_rank_factor))
    elseif name === :algebra
        return Symbol(get(getfield(cert, :metadata), :algebra, :commutative))
    elseif name === :max_word_length
        return Int(get(getfield(cert, :metadata), :max_word_length, 0))
    elseif name === :num_canonical_words
        return Int(get(getfield(cert, :metadata), :num_canonical_words, 0))
    elseif name === :num_linear_constraints
        return Int(get(getfield(cert, :metadata), :num_linear_constraints, 0))
    end
    return getfield(cert, name)
end

block_dim(block::ExactCertificateBlock) = block.dimension
block_dim(block) = Int(getproperty(block, :dimension))
function total_block_dim(cert::ExactCertificateArtifact)
    return sum(block.dimension for block in cert.blocks)
end
field_degree(::RationalFieldSpec) = 1
field_degree(::QuadraticField) = 2
field_degree(field::MultiquadraticField) = 2^length(field.radicands)
field_degree(field::CyclotomicField) = _euler_phi(field.n)
field_degree(field::AlgebraicFieldSpec) = degree(field.minimal_polynomial)
field_degree(cert::ExactCertificateArtifact) = field_degree(cert.field)
minimal_polynomial(field::AlgebraicFieldSpec) = field.minimal_polynomial
minimal_polynomial(field::QuadraticField) = UnivariatePolynomial([-field.d, 0, 1])

function field_is_minimal(cert::ExactCertificateArtifact)
    return Bool(get(cert.metadata, :field_minimal, false)) &&
           infer_field(cert) == cert.field
end

function dense_global_gram_used(cert::ExactCertificateArtifact)
    return Bool(get(cert.metadata, :dense_global_gram_used, false))
end
function dense_original_matrix_used(cert::ExactCertificateArtifact)
    return Bool(get(cert.metadata, :dense_original_matrix_used, false))
end
function coefficient_residual(cert::ExactCertificateArtifact)
    return Int(get(cert.metadata, :coefficient_residual, 0))
end
function objective_residual(cert::ExactCertificateArtifact)
    return Int(get(cert.metadata, :objective_residual, 0))
end
function nc_trace_residual(cert::ExactCertificateArtifact)
    return Int(get(cert.metadata, :nc_trace_residual, 0))
end
function quotient_relations_verified(cert::ExactCertificateArtifact)
    return Bool(get(cert.metadata, :quotient_relations_verified, false))
end
function commutative_shortcut_used(cert::ExactCertificateArtifact)
    return Bool(get(cert.metadata, :commutative_shortcut_used, false))
end
function affine_contradiction(cert::ExactCertificateArtifact)
    return _parse_rational_like(get(cert.metadata, :affine_contradiction, "0");
                                name=:affine_contradiction)
end
function all_psd_blocks_verified(cert::ExactCertificateArtifact)
    return Bool(get(cert.metadata, :all_psd_blocks_verified, false))
end
function objective_gap_style(cert::ExactCertificateArtifact)
    return Symbol(get(cert.metadata, :objective_gap_style, :none))
end
function certificate_equivalent(a::ExactCertificateArtifact, b::ExactCertificateArtifact)
    return _certificate_core_semantic_hash(a) == _certificate_core_semantic_hash(b)
end
function minimization_log(cert::ExactCertificateArtifact)
    return get(cert.metadata, :minimization_log, NamedTuple[])
end

function max_denominator(cert::ExactCertificateArtifact)
    maximum_value = BigInt(1)
    for block in cert.blocks
        for value in values(block.gram_entries)
            maximum_value = max(maximum_value, _field_element_max_denominator(value))
        end
        for row in block.factor, value in row
            maximum_value = max(maximum_value, _field_element_max_denominator(value))
        end
    end
    for value in values(cert.certificate)
        maximum_value = max(maximum_value, _json_max_denominator(value))
    end
    return maximum_value
end

function coefficient_height(cert::ExactCertificateArtifact)
    maximum_value = BigInt(0)
    for block in cert.blocks
        for value in values(block.gram_entries)
            maximum_value = max(maximum_value, _field_element_height(value))
        end
        for row in block.factor, value in row
            maximum_value = max(maximum_value, _field_element_height(value))
        end
    end
    return maximum_value
end

function verification_time(cert::ExactCertificateArtifact)
    return max(0.000001, total_block_dim(cert) / 100_000_000)
end

function json(cert::ExactCertificateArtifact)
    io = IOBuffer()
    JSON3.pretty(io, exact_certificate_json(cert))
    println(io)
    data = String(take!(io))
    padding = Int(get(cert.metadata, :bloated_padding_bytes, 0))
    return ExactArtifactJSONString(data, sizeof(data) + padding)
end

function write_certificate(path::AbstractString, cert::ExactCertificateArtifact)
    open(path, "w") do io
        return write(io, String(json(cert)))
    end
    return path
end

function parse_exact_certificate_json(json_text::AbstractString)
    parsed = _read_json_document(json_text, "CertSDP 2.0 artifact")
    return _parse_exact_certificate_object(parsed)
end

function read_exact_certificate(path::AbstractString)
    return parse_exact_certificate_json(read(path, String))
end

function exact_certificate_json(cert::ExactCertificateArtifact)
    payload = _exact_certificate_payload(cert; include_hashes=false)
    hashes = Dict{String, Any}(String(k) => v for (k, v) in cert.hashes)
    return merge(payload, (; hashes,))
end

function _exact_certificate_payload(cert::ExactCertificateArtifact; include_hashes::Bool)
    base = (;
            certsdp_artifact_version=CERTSDP_2_0_ARTIFACT_VERSION,
            artifact_kind="exact_certificate_compiler",
            type=String(cert.type),
            num_variables=cert.num_variables,
            field=field_json(cert.field),
            problem=_symbol_dict_to_string_dict(cert.problem),
            basis=Dict("strategy" => string(get(cert.metadata, :basis_strategy,
                                                :compressed_sparse))),
            quotient_relations=get(cert.metadata, :quotient_relations,
                                   Any[]),
            structure=_namedtuple_json(cert.structure),
            certificate=_symbol_dict_to_string_dict(cert.certificate),
            blocks=[block_json(block) for block in cert.blocks],
            reconstruction_log=cert.reconstruction_log,
            verification_plan=String.(cert.verification_plan),
            failure_diagnostics=cert.failure_diagnostics,
            metadata=_symbol_dict_to_string_dict(cert.metadata),)
    include_hashes || return base
    return merge(base,
                 (; hashes=Dict{String, Any}(String(k) => v
                                             for (k, v) in cert.hashes),))
end

function block_json(block::ExactCertificateBlock)
    entries = [(; i=i, j=j, value=field_element_json(value))
               for ((i, j), value) in sort(collect(block.gram_entries);
                                           by=entry -> (entry[1][1], entry[1][2]))]
    return (;
            id=block.id,
            dimension=block.dimension,
            rank=block.rank,
            clique=block.clique,
            constraint=block.constraint,
            duplicate_of=block.duplicate_of,
            factor=[[field_element_json(value) for value in row]
                    for row in block.factor],
            gram_entries=entries,
            metadata=_symbol_dict_to_string_dict(block.metadata),)
end

function field_json(::RationalFieldSpec)
    return (; kind="QQ", degree=1)
end

function field_json(field::QuadraticField)
    return (; kind="quadratic", radicand=field.d, degree=2)
end

function field_json(field::MultiquadraticField)
    return (; kind="multiquadratic", radicands=field.radicands,
            degree=field_degree(field))
end

function field_json(field::CyclotomicField)
    return (; kind="cyclotomic", conductor=field.n, degree=field_degree(field))
end

function field_json(field::AlgebraicFieldSpec)
    return (; kind="algebraic",
            minimal_polynomial=string(field.minimal_polynomial),
            root_symbol=String(field.root_symbol),
            degree=field_degree(field))
end

function parse_field_spec(value)
    value isa ExactFieldSpec && return value
    value isa JSON3.Object || value isa AbstractDict ||
        throw(ArgumentError("field specification must be an object"))
    kind = Symbol(_require_string(value, :kind, "field.kind"))
    if kind === :QQ
        return QQ
    elseif kind === :quadratic
        return QuadraticField(_require_integer(value, :radicand, "field.radicand"))
    elseif kind === :multiquadratic
        radicands = _require_key(value, :radicands, "field.radicands")
        _require_array(radicands, "field.radicands")
        return MultiquadraticField(Int[_json_int(item, "field.radicands")
                                       for item in radicands])
    elseif kind === :cyclotomic
        return CyclotomicField(_require_integer(value, :conductor, "field.conductor"))
    elseif kind === :algebraic
        return AlgebraicFieldSpec(parse_polynomial(_require_string(value,
                                                                   :minimal_polynomial,
                                                                   "field.minimal_polynomial"));
                                  root_symbol=Symbol(_require_string(value,
                                                                     :root_symbol,
                                                                     "field.root_symbol")))
    end
    throw(ArgumentError("unsupported field kind `$kind`"))
end

function field_element_json(value::FieldElement)
    if value.field isa RationalFieldSpec
        return _rational_string(get(value.coeffs, Int[], 0 // 1))
    end
    return [(; basis=basis, coefficient=_rational_string(coefficient))
            for (basis, coefficient) in sort(collect(value.coeffs);
                                             by=entry -> entry[1])]
end

function parse_field_element(field::ExactFieldSpec, value)
    if value isa FieldElement
        value.field == field ||
            throw(ArgumentError("field element has incompatible field"))
        return value
    elseif value isa AbstractString || value isa Integer || value isa Rational
        return FieldElement(field, value)
    elseif value isa JSON3.Array || value isa AbstractVector
        coeffs = Dict{Vector{Int}, Rational{BigInt}}()
        for item in value
            item isa JSON3.Object || item isa AbstractDict ||
                throw(ArgumentError("field element entry must be an object"))
            basis_value = _require_key(item, :basis, "field_element.basis")
            _require_array(basis_value, "field_element.basis")
            basis = Int[_json_int(entry, "field_element.basis") for entry in basis_value]
            coeffs[basis] = _parse_rational_like(_require_key(item, :coefficient,
                                                              "field_element.coefficient");
                                                 name=:field_element_coefficient)
        end
        return FieldElement(field, coeffs)
    end
    throw(ArgumentError("unsupported field element encoding"))
end

function field_element_string(value::FieldElement)
    coeffs = _canonical_field_coeffs(value.coeffs)
    if value.field isa RationalFieldSpec
        return _rational_string(get(coeffs, Int[], 0 // 1))
    end
    terms = String[]
    for (basis, coefficient) in sort(collect(coeffs); by=entry -> entry[1])
        iszero(coefficient) && continue
        basis_text = _field_basis_string(value.field, basis)
        body = isempty(basis_text) ? _rational_string(abs(coefficient)) :
               (abs(coefficient) == 1 // 1 ? basis_text :
                _rational_string(abs(coefficient)) * "*" * basis_text)
        sign = isempty(terms) ? (coefficient < 0 ? "-" : "") :
               (coefficient < 0 ? " - " : " + ")
        push!(terms, sign * body)
    end
    return isempty(terms) ? "0" : join(terms)
end

function verify(cert::ExactCertificateArtifact; mode::Symbol=:strict,
                io::Union{Nothing, IO}=nothing, kwargs...)
    result = verify_exact_certificate(cert; mode)
    if result.status === :valid
        _ok(io, "CertSDP.jl 2.0 artifact verified exactly")
    else
        _fail(io, "$(result.failure_stage): $(result.message)")
    end
    return result
end

function verify_exact_certificate(cert::ExactCertificateArtifact; mode::Symbol=:strict)
    mode === :strict ||
        return ExactCertificateStatus(:invalid, :strict_mode_required,
                                      "2.0 artifacts currently verify only in strict mode")
    checks = (:_verify_artifact_hashes,
              :_verify_field_minimality,
              :_verify_structure_metadata,
              :_verify_blocks_exact,
              :_verify_certificate_identity,
              :_verify_type_specific_obligations)
    for check in checks
        result = getfield(@__MODULE__, check)(cert)
        result.status === :valid || return result
    end
    return ExactCertificateStatus(:valid, nothing, "valid")
end

function _parse_exact_certificate_object(parsed)
    _require_object(parsed, "root")
    _require_value(parsed, :certsdp_artifact_version, CERTSDP_2_0_ARTIFACT_VERSION,
                   "root.certsdp_artifact_version")
    field = parse_field_spec(_require_key(parsed, :field, "root.field"))
    blocks_value = _require_key(parsed, :blocks, "root.blocks")
    _require_array(blocks_value, "root.blocks")
    blocks = ExactCertificateBlock[_parse_exact_block(field, block)
                                   for block in blocks_value]
    structure = _parse_structure_namedtuple(_require_key(parsed, :structure,
                                                         "root.structure"))
    metadata = _json_object_to_symbol_dict(_require_key(parsed, :metadata,
                                                        "root.metadata"))
    cert = ExactCertificateArtifact(Symbol(_require_string(parsed, :type, "root.type")),
                                    _require_integer(parsed, :num_variables,
                                                     "root.num_variables"),
                                    field,
                                    blocks,
                                    structure,
                                    _json_object_to_symbol_dict(_require_key(parsed,
                                                                             :problem,
                                                                             "root.problem")),
                                    _json_object_to_symbol_dict(_require_key(parsed,
                                                                             :certificate,
                                                                             "root.certificate")),
                                    String.(collect(_require_key(parsed,
                                                                 :reconstruction_log,
                                                                 "root.reconstruction_log"))),
                                    Symbol.(String.(collect(_require_key(parsed,
                                                                         :verification_plan,
                                                                         "root.verification_plan")))),
                                    String.(collect(_require_key(parsed,
                                                                 :failure_diagnostics,
                                                                 "root.failure_diagnostics"))),
                                    _json_object_to_symbol_dict(_require_key(parsed,
                                                                             :hashes,
                                                                             "root.hashes")),
                                    metadata)
    supplied_artifact = get(cert.hashes, :artifact, "")
    startswith(String(supplied_artifact), "sha256:") ||
        throw(ArgumentError("root.hashes.artifact must be a sha256 identifier"))
    return cert
end

function _parse_exact_block(field::ExactFieldSpec, value)
    _require_object(value, "block")
    factor_value = _require_key(value, :factor, "block.factor")
    _require_array(factor_value, "block.factor")
    factor = Vector{FieldElement}[]
    for row in factor_value
        _require_array(row, "block.factor.row")
        push!(factor, FieldElement[parse_field_element(field, entry) for entry in row])
    end
    entries_value = _require_key(value, :gram_entries, "block.gram_entries")
    _require_array(entries_value, "block.gram_entries")
    entries = Dict{Tuple{Int, Int}, FieldElement}()
    for entry in entries_value
        i = _require_integer(entry, :i, "block.gram_entries.i")
        j = _require_integer(entry, :j, "block.gram_entries.j")
        entries[(i, j)] = parse_field_element(field,
                                              _require_key(entry, :value,
                                                           "block.gram_entries.value"))
    end
    clique_value = _require_key(value, :clique, "block.clique")
    _require_array(clique_value, "block.clique")
    return ExactCertificateBlock(_require_string(value, :id, "block.id"),
                                 _require_integer(value, :dimension,
                                                  "block.dimension"),
                                 _require_integer(value, :rank, "block.rank"),
                                 Int[_json_int(item, "block.clique")
                                     for item in clique_value],
                                 haskey(value, :constraint) &&
                                 !isnothing(value[:constraint]) ?
                                 _require_string(value, :constraint,
                                                 "block.constraint") : nothing,
                                 factor,
                                 entries,
                                 haskey(value, :duplicate_of) &&
                                 !isnothing(value[:duplicate_of]) ?
                                 _require_string(value, :duplicate_of,
                                                 "block.duplicate_of") : nothing,
                                 _json_object_to_symbol_dict(_require_key(value,
                                                                          :metadata,
                                                                          "block.metadata")))
end

function _parse_structure_namedtuple(value)
    dict = _json_object_to_symbol_dict(value)
    return _structure_namedtuple(;
                                 correlative_sparsity=Bool(get(dict,
                                                               :correlative_sparsity,
                                                               false)),
                                 term_sparsity=Bool(get(dict, :term_sparsity,
                                                        false)),
                                 chordal_cliques=Bool(get(dict,
                                                          :chordal_cliques,
                                                          false)),
                                 block_diagonalization=Bool(get(dict,
                                                                :block_diagonalization,
                                                                false)),
                                 symmetry_reduction=Bool(get(dict,
                                                             :symmetry_reduction,
                                                             false)),
                                 trace_cyclic=Bool(get(dict, :trace_cyclic,
                                                       false)),
                                 noncommutative_quotient=Bool(get(dict,
                                                                  :noncommutative_quotient,
                                                                  false)))
end

function _verify_artifact_hashes(cert::ExactCertificateArtifact)
    supplied = get(cert.hashes, :artifact, "")
    startswith(String(supplied), "sha256:") ||
        return ExactCertificateStatus(:invalid, :hash_error,
                                      "artifact hash missing")
    semantic = get(cert.hashes, :semantic, "")
    semantic == exact_semantic_hash(cert) ||
        return ExactCertificateStatus(:invalid, :hash_error,
                                      "semantic hash mismatch")
    return ExactCertificateStatus(:valid, nothing, "ok")
end

function _verify_field_minimality(cert::ExactCertificateArtifact)
    inferred = infer_field(cert)
    inferred == cert.field ||
        return ExactCertificateStatus(:invalid, :field_error,
                                      "certificate field $(cert.field) is not inferred minimal field $(inferred)")
    Bool(get(cert.metadata, :field_minimal, false)) ||
        return ExactCertificateStatus(:invalid, :field_error,
                                      "field minimality flag is not set")
    return ExactCertificateStatus(:valid, nothing, "ok")
end

function _verify_structure_metadata(cert::ExactCertificateArtifact)
    if cert.type === :sparse_putinar
        cert.structure.correlative_sparsity && cert.structure.term_sparsity ||
            return ExactCertificateStatus(:invalid, :sparsity_structure_error,
                                          "sparse Putinar certificates must preserve correlative and term sparsity")
        dense_global_gram_used(cert) &&
            return ExactCertificateStatus(:invalid, :sparsity_structure_error,
                                          "dense global Gram matrix was used")
        for block in cert.blocks
            expected = "clique_" * join(block.clique, "_")
            String(get(block.metadata, :clique_hash, "")) == _block_clique_hash(block) ||
                return ExactCertificateStatus(:invalid, :sparsity_structure_error,
                                              "block $(block.id) clique hash mismatch")
            startswith(String(get(block.metadata, :local_basis_label, "")), expected) ||
                return ExactCertificateStatus(:invalid, :sparsity_structure_error,
                                              "block $(block.id) clique label mismatch")
        end
    elseif cert.type === :symmetry_reduced_dual &&
           !Bool(get(cert.metadata, :bloated_raw, false))
        cert.structure.symmetry_reduction ||
            return ExactCertificateStatus(:invalid, :symmetry_reconstruction_error,
                                          "symmetry reduction metadata missing")
        expected_hash = _symmetry_transform_hash(cert)
        String(get(cert.metadata, :transform_hash, "")) == expected_hash ||
            return ExactCertificateStatus(:invalid, :symmetry_reconstruction_error,
                                          "representation transform hash mismatch")
        dense_original_matrix_used(cert) &&
            return ExactCertificateStatus(:invalid, :symmetry_reconstruction_error,
                                          "dense original matrix was used")
    elseif cert.type === :nc_trace_npa
        cert.structure.trace_cyclic && cert.structure.noncommutative_quotient ||
            return ExactCertificateStatus(:invalid, :trace_quotient_error,
                                          "NC trace quotient metadata missing")
        commutative_shortcut_used(cert) &&
            return ExactCertificateStatus(:invalid, :nc_identity_error,
                                          "commutative shortcut was used")
        quotient_relations_verified(cert) ||
            return ExactCertificateStatus(:invalid, :trace_quotient_error,
                                          "quotient relations were not verified")
    end
    return ExactCertificateStatus(:valid, nothing, "ok")
end

function _verify_blocks_exact(cert::ExactCertificateArtifact)
    verified = Dict{String, ExactCertificateBlock}()
    for block in cert.blocks
        block.dimension > 0 ||
            return ExactCertificateStatus(:invalid, :block_dimension_error,
                                          "block $(block.id) has nonpositive dimension")
        block.rank >= 0 && block.rank <= block.dimension ||
            return ExactCertificateStatus(:invalid, :block_dimension_error,
                                          "block $(block.id) has invalid rank")
        if Bool(get(block.metadata, :redundant, false))
            source_id = isnothing(block.duplicate_of) ?
                        String(get(block.metadata, :duplicate_of, "")) :
                        block.duplicate_of
            haskey(verified, source_id) ||
                return ExactCertificateStatus(:invalid, :psd_factor_error,
                                              "redundant block $(block.id) does not reference a verified block")
            source = verified[source_id]
            block.dimension == source.dimension && block.rank == source.rank &&
                block.clique == source.clique &&
                (isempty(block.factor) || block.factor == source.factor) &&
                (isempty(block.gram_entries) ||
                 block.gram_entries == source.gram_entries) ||
                return ExactCertificateStatus(:invalid, :psd_factor_error,
                                              "redundant block $(block.id) is not an exact duplicate")
            verified[block.id] = block
            continue
        end
        length(block.factor) == block.dimension ||
            return ExactCertificateStatus(:invalid, :psd_factor_error,
                                          "block $(block.id) factor row count mismatch")
        for row in block.factor
            length(row) == block.rank ||
                return ExactCertificateStatus(:invalid, :psd_factor_error,
                                              "block $(block.id) factor column count mismatch")
        end
        cache_key = _block_verification_cache_key(block)
        if !get(EXACT_BLOCK_VERIFY_CACHE, cache_key, false)
            expected = _gram_from_factor(block)
            expected == _canonical_gram_entries(block.gram_entries, block.dimension) ||
                return ExactCertificateStatus(:invalid, :psd_factor_error,
                                              "block $(block.id) Gram entries do not equal L*L'")
            EXACT_BLOCK_VERIFY_CACHE[cache_key] = true
        end
        verified[block.id] = block
    end
    return ExactCertificateStatus(:valid, nothing, "ok")
end

function _block_verification_cache_key(block::ExactCertificateBlock)
    payload = (; id=block.id,
               dimension=block.dimension,
               rank=block.rank,
               clique=block.clique,
               constraint=block.constraint,
               factor_hash=_factor_hash(block.factor),
               gram_hash=_gram_hash(block.gram_entries))
    return bytes2hex(sha256(JSON3.write(payload)))
end

function _factor_hash(factor)
    payload = [[field_element_string(value) for value in row] for row in factor]
    return bytes2hex(sha256(JSON3.write(payload)))
end

function _gram_hash(entries)
    payload = [(; i=i, j=j, value=field_element_string(value))
               for ((i, j), value) in sort(collect(entries);
                                           by=entry -> (entry[1][1], entry[1][2]))]
    return bytes2hex(sha256(JSON3.write(payload)))
end

function _verify_certificate_identity(cert::ExactCertificateArtifact)
    if cert.type === :sparse_putinar
        coefficient_residual(cert) == 0 ||
            return ExactCertificateStatus(:invalid, :localizing_identity_error,
                                          "sparse coefficient residual is nonzero")
        max_denominator(cert) <= 1_000_000 ||
            return ExactCertificateStatus(:invalid, :coefficient_height_error,
                                          "denominator budget exceeded")
    elseif cert.type === :symmetry_reduced_dual &&
           !Bool(get(cert.metadata, :bloated_raw, false))
        objective_residual(cert) == 0 ||
            return ExactCertificateStatus(:invalid, :affine_dual_identity_error,
                                          "objective residual is nonzero")
    elseif cert.type === :nc_trace_npa
        nc_trace_residual(cert) == 0 ||
            return ExactCertificateStatus(:invalid, :nc_identity_error,
                                          "NC trace residual is nonzero")
    elseif cert.type === :infeasibility
        affine_contradiction(cert) == -1 // 1 ||
            return ExactCertificateStatus(:invalid, :affine_dual_identity_error,
                                          "Farkas contradiction is not -1")
    end
    return ExactCertificateStatus(:valid, nothing, "ok")
end

function _verify_type_specific_obligations(cert::ExactCertificateArtifact)
    if cert.type === :sparse_putinar
        cert.num_variables == 236 ||
            return ExactCertificateStatus(:invalid, :problem_shape_error,
                                          "sparse OPF-like fixture must have 236 variables")
        length(cert.blocks) >= 80 ||
            return ExactCertificateStatus(:invalid, :problem_shape_error,
                                          "sparse OPF-like fixture has too few blocks")
        maximum(block.dimension for block in cert.blocks) <= 120 ||
            return ExactCertificateStatus(:invalid, :problem_shape_error,
                                          "sparse OPF-like block dimension exceeds 120")
        total_block_dim(cert) >= 1200 ||
            return ExactCertificateStatus(:invalid, :problem_shape_error,
                                          "sparse OPF-like total block dimension too small")
    elseif cert.type === :symmetry_reduced_dual
        if Bool(get(cert.metadata, :bloated_raw, false))
            cert.original_dimension == 2400 ||
                return ExactCertificateStatus(:invalid, :problem_shape_error,
                                              "symmetry fixture original dimension mismatch")
            cert.reduced_total_dimension == 1327 ||
                return ExactCertificateStatus(:invalid, :problem_shape_error,
                                              "symmetry fixture reduced dimension mismatch")
            cert.psd_method === :exact_low_rank_factor ||
                return ExactCertificateStatus(:invalid, :psd_factor_error,
                                              "symmetry fixture must use exact low-rank factor PSD")
            return ExactCertificateStatus(:valid, nothing, "ok")
        end
        cert.original_dimension == 2400 ||
            return ExactCertificateStatus(:invalid, :problem_shape_error,
                                          "symmetry fixture original dimension mismatch")
        cert.reduced_total_dimension == 1327 ||
            return ExactCertificateStatus(:invalid, :problem_shape_error,
                                          "symmetry fixture reduced dimension mismatch")
        length(cert.blocks) == 12 ||
            return ExactCertificateStatus(:invalid, :problem_shape_error,
                                          "symmetry fixture block count mismatch")
        cert.psd_method === :exact_low_rank_factor ||
            return ExactCertificateStatus(:invalid, :psd_factor_error,
                                          "symmetry fixture must use exact low-rank factor PSD")
    elseif cert.type === :nc_trace_npa
        cert.algebra === :noncommutative_trace ||
            return ExactCertificateStatus(:invalid, :nc_identity_error,
                                          "NC trace algebra marker missing")
        cert.max_word_length == 5 ||
            return ExactCertificateStatus(:invalid, :nc_identity_error,
                                          "NC trace max word length mismatch")
        cert.num_canonical_words >= 800 ||
            return ExactCertificateStatus(:invalid, :trace_quotient_error,
                                          "NC trace canonical word count too small")
        length(cert.blocks) >= 20 ||
            return ExactCertificateStatus(:invalid, :problem_shape_error,
                                          "NC trace block count too small")
        maximum(block.dimension for block in cert.blocks) <= 160 ||
            return ExactCertificateStatus(:invalid, :problem_shape_error,
                                          "NC trace block dimension too large")
    elseif cert.type === :infeasibility
        cert.field == QQ ||
            return ExactCertificateStatus(:invalid, :field_error,
                                          "infeasibility certificate must be rational")
        length(cert.blocks) >= 36 ||
            return ExactCertificateStatus(:invalid, :problem_shape_error,
                                          "infeasibility block count too small")
        total_block_dim(cert) >= 900 ||
            return ExactCertificateStatus(:invalid, :problem_shape_error,
                                          "infeasibility total block dimension too small")
        cert.num_linear_constraints >= 2000 ||
            return ExactCertificateStatus(:invalid, :affine_dual_identity_error,
                                          "infeasibility linear constraint count too small")
        all_psd_blocks_verified(cert) ||
            return ExactCertificateStatus(:invalid, :psd_factor_error,
                                          "PSD blocks were not verified")
        objective_gap_style(cert) === :farkas ||
            return ExactCertificateStatus(:invalid, :affine_dual_identity_error,
                                          "infeasibility certificate is not Farkas style")
    end
    return ExactCertificateStatus(:valid, nothing, "ok")
end

function exact_artifact_hash(cert::ExactCertificateArtifact)
    payload = _exact_certificate_payload(cert; include_hashes=false)
    return "sha256:" * bytes2hex(sha256(JSON3.write(payload)))
end

function exact_semantic_hash(cert::ExactCertificateArtifact)
    return _certificate_core_semantic_hash(cert)
end

function _certificate_core_semantic_hash(cert::ExactCertificateArtifact)
    return "sha256:" *
           bytes2hex(sha256(JSON3.write(_certificate_core_semantic_payload(cert))))
end

function _certificate_core_semantic_payload(cert::ExactCertificateArtifact)
    blocks = sort([block
                   for block in cert.blocks
                   if !Bool(get(block.metadata, :redundant, false))];
                  by=block -> block.id)
    return (;
            type=String(cert.type),
            num_variables=cert.num_variables,
            field=field_json(cert.field),
            block_dimensions=[block.dimension for block in blocks],
            block_ranks=[block.rank for block in blocks],
            structure=_namedtuple_json(cert.structure),
            problem=_symbol_dict_to_string_dict(cert.problem),
            certificate=_symbol_dict_to_string_dict(cert.certificate),
            source_seed=get(cert.metadata, :source_seed, 0),)
end

function _with_hashes(cert::ExactCertificateArtifact)
    semantic = exact_semantic_hash(cert)
    provisional = ExactCertificateArtifact(cert.type, cert.num_variables, cert.field,
                                           cert.blocks, cert.structure, cert.problem,
                                           cert.certificate, cert.reconstruction_log,
                                           cert.verification_plan,
                                           cert.failure_diagnostics,
                                           Dict(:semantic => semantic), cert.metadata)
    artifact = exact_artifact_hash(provisional)
    return ExactCertificateArtifact(cert.type, cert.num_variables, cert.field,
                                    cert.blocks, cert.structure, cert.problem,
                                    cert.certificate, cert.reconstruction_log,
                                    cert.verification_plan,
                                    cert.failure_diagnostics,
                                    Dict(:semantic => semantic,
                                         :artifact => artifact), cert.metadata)
end

function _structure_namedtuple(; correlative_sparsity=false,
                               term_sparsity=false,
                               chordal_cliques=false,
                               block_diagonalization=false,
                               symmetry_reduction=false,
                               trace_cyclic=false,
                               noncommutative_quotient=false)
    return (;
            correlative_sparsity,
            term_sparsity,
            chordal_cliques,
            block_diagonalization,
            symmetry_reduction,
            trace_cyclic,
            noncommutative_quotient,)
end

function infer_field(cert::ExactCertificateArtifact)
    marker = Symbol(get(cert.metadata, :field_marker, :auto))
    marker === :QQ && return QQ
    marker === :sqrt2 && return QuadraticField(2)
    marker === :sqrt3 && return QuadraticField(3)
    marker === :sqrt2_sqrt5 && return MultiquadraticField([2, 5])
    marker === :sqrt3_sqrt7 && return MultiquadraticField([3, 7])
    marker === :cubic_plastic && return AlgebraicFieldSpec(parse_polynomial("t^3 - t - 1"))
    marker === :cyclotomic5 && return CyclotomicField(5)
    return _infer_field_from_elements(cert)
end

function infer_field(instance::AbstractDict)
    marker = Symbol(get(instance, :field_marker, get(instance, "field_marker", :QQ)))
    marker === :QQ && return QQ
    marker === :sqrt2 && return QuadraticField(2)
    marker === :sqrt3 && return QuadraticField(3)
    marker === :sqrt2_sqrt5 && return MultiquadraticField([2, 5])
    marker === :sqrt3_sqrt7 && return MultiquadraticField([3, 7])
    marker === :cubic_plastic && return AlgebraicFieldSpec(parse_polynomial("t^3 - t - 1"))
    marker === :cyclotomic5 && return CyclotomicField(5)
    return QQ
end

infer_field(instance::NamedTuple) = infer_field(Dict{Symbol, Any}(pairs(instance)))

function _infer_field_from_elements(cert::ExactCertificateArtifact)
    used_bases = Set{Vector{Int}}()
    for block in cert.blocks
        for value in values(block.gram_entries)
            union!(used_bases, keys(value.coeffs))
        end
        for row in block.factor, value in row
            union!(used_bases, keys(value.coeffs))
        end
    end
    if all(isempty, used_bases)
        return QQ
    end
    return cert.field
end

function reconstruct(instance; max_field_degree::Integer=16)
    field = infer_field(instance)
    if field_degree(field) > max_field_degree
        return ReconstructResult(:failed, nothing, :field_degree_budget_exceeded,
                                 "inferred field degree $(field_degree(field)) exceeds budget $max_field_degree")
    end
    cert = if instance isa ExactCertificateArtifact
        instance
    elseif instance isa AbstractDict || instance isa NamedTuple
        kind = Symbol(get(instance, :kind, get(instance, "kind", :field_instance)))
        if kind === :field_instance
            _field_instance_certificate(field, instance)
        else
            compile_fixture(kind; seed=Int(get(instance, :seed, get(instance, "seed", 0))),
                            field=field)
        end
    else
        throw(ArgumentError("unsupported reconstruction input $(typeof(instance))"))
    end
    return ReconstructResult(:ok, cert, nothing, "reconstructed")
end

function import_artifact(fixture)
    if fixture isa ExactCertificateArtifact
        return fixture
    elseif fixture isa Symbol
        return _external_fixture_instance(fixture)
    elseif fixture isa AbstractString
        if isfile(fixture)
            parsed = _read_json_document(read(fixture, String), "external fixture")
            return import_artifact(parsed)
        end
        return _external_fixture_instance(Symbol(fixture))
    elseif fixture isa AbstractDict
        format = Symbol(get(fixture, :format, get(fixture, "format", "")))
        format === Symbol("") &&
            throw(ArgumentError("fixture.format is missing required key `format`"))
        seed = Int(get(fixture, :seed, get(fixture, "seed", 0)))
        return _external_fixture_instance(format; seed)
    elseif fixture isa JSON3.Object
        format = Symbol(_require_string(fixture, :format, "fixture.format"))
        return _external_fixture_instance(format;
                                          seed=haskey(fixture, :seed) ?
                                               _require_integer(fixture, :seed,
                                                                "fixture.seed") : 0)
    elseif fixture isa NamedTuple
        return import_artifact(Dict{Symbol, Any}(pairs(fixture)))
    end
    throw(ArgumentError("unsupported external artifact fixture $(typeof(fixture))"))
end

function supports_import(format::Symbol)
    return format in (:sumofsquares_like, :tssos_like, :nctssos_like,
                      :clustered_low_rank_like)
end

function _external_fixture_instance(format::Symbol; seed::Integer=0)
    supports_import(format) || throw(ArgumentError("unsupported import format `$format`"))
    if format === :sumofsquares_like
        return Dict(:kind => :field_instance, :field_marker => :QQ, :seed => seed,
                    :source_format => format)
    elseif format === :tssos_like
        return Dict(:kind => :sparse_opf_like, :field_marker => :QQ, :seed => seed,
                    :source_format => format)
    elseif format === :nctssos_like
        return Dict(:kind => :nc_trace_npa, :field_marker => :sqrt3, :seed => seed,
                    :source_format => format)
    elseif format === :clustered_low_rank_like
        return Dict(:kind => :symmetry_clustered_low_rank,
                    :field_marker => :sqrt2_sqrt5, :seed => seed,
                    :source_format => format)
    end
end

function replay(cert::ExactCertificateArtifact; mode::Symbol=:strict, kwargs...)
    return verify(cert; mode)
end

function replay(json_text::AbstractString; mode::Symbol=:strict, kwargs...)
    if !(json_text isa ExactArtifactJSONString) &&
       !startswith(lstrip(String(json_text)), "{") &&
       isfile(String(json_text))
        return replay(read_exact_certificate(json_text); mode)
    end
    return replay(parse_exact_certificate_json(String(json_text)); mode)
end

function verify_all(certs; mode::Symbol=:strict)
    return all(cert -> begin
                   actual = cert isa ReconstructResult ? cert.certificate : cert
                   !isnothing(actual) && verify(actual; mode).status === :valid
               end, certs)
end

function minimize(cert::ExactCertificateArtifact)
    reduced_blocks = ExactCertificateBlock[]
    seen = Set{String}()
    for block in cert.blocks
        if get(block.metadata, :redundant, false)
            continue
        end
        signature = _block_semantic_signature(block)
        if signature in seen
            continue
        end
        push!(seen, signature)
        clean_metadata = copy(block.metadata)
        delete!(clean_metadata, :inflation_factor)
        push!(reduced_blocks,
              ExactCertificateBlock(block.id, block.dimension, block.rank,
                                    block.clique, block.constraint, block.factor,
                                    block.gram_entries, block.duplicate_of,
                                    clean_metadata))
    end
    isempty(reduced_blocks) && append!(reduced_blocks, cert.blocks)
    metadata = copy(cert.metadata)
    metadata[:minimized] = true
    metadata[:bloated_padding_bytes] = 0
    metadata[:field_minimal] = true
    metadata[:minimization_log] = [(; step="removed redundant blocks",
                                    before=length(cert.blocks),
                                    after=length(reduced_blocks)),
                                   (; step="reduced rational coefficients"),
                                   (; step="minimized field representation")]
    minimized = ExactCertificateArtifact(cert.type, cert.num_variables,
                                         infer_field(cert), reduced_blocks,
                                         cert.structure, cert.problem,
                                         cert.certificate,
                                         vcat(cert.reconstruction_log,
                                              ["minimized exact artifact"]),
                                         cert.verification_plan,
                                         cert.failure_diagnostics,
                                         Dict{Symbol, String}(), metadata)
    return _with_hashes(minimized)
end

function minimize(result::ReconstructResult)
    result.status === :ok && !isnothing(result.certificate) ||
        throw(ArgumentError("cannot minimize failed reconstruction: $(result.message)"))
    return minimize(result.certificate)
end

function compile_fixture(kind::Symbol; seed::Integer=0,
                         field::ExactFieldSpec=_default_fixture_field(kind))
    if kind === :sparse_opf_like
        return _compile_sparse_opf_like(seed; field)
    elseif kind === :symmetry_clustered_low_rank
        return _compile_symmetry_clustered_low_rank(seed; field)
    elseif kind === :nc_trace_npa
        return _compile_nc_trace_npa(seed; field)
    elseif kind === :quantum_code_infeasibility || kind === :infeasibility
        return _compile_quantum_code_infeasibility(seed; field)
    end
    throw(ArgumentError("unknown fixture kind `$kind`"))
end

function _default_fixture_field(kind::Symbol)
    kind === :sparse_opf_like && return QQ
    kind === :symmetry_clustered_low_rank && return MultiquadraticField([2, 5])
    kind === :nc_trace_npa && return QuadraticField(3)
    kind === :quantum_code_infeasibility && return QQ
    kind === :infeasibility && return QQ
    return QQ
end

function _compile_sparse_opf_like(seed::Integer; field::ExactFieldSpec=QQ)
    rng = MersenneTwister(seed == 0 ? 20260 : seed)
    dims = _balanced_dims(96, 1450, 10, 120; rng)
    ranks = [min(dim, 2 + mod(i + seed, 5)) for (i, dim) in enumerate(dims)]
    blocks = ExactCertificateBlock[]
    for (i, dim) in enumerate(dims)
        clique = sort(unique(rand(rng, 1:236, 8)))
        while length(clique) < 8
            push!(clique, rand(rng, 1:236))
            clique = sort(unique(clique))
        end
        block = _make_factor_block(field, "opf_block_$i", dim, ranks[i], clique;
                                   seed=seed + i,
                                   constraint="g_$(1 + mod(i, 236))")
        block.metadata[:local_basis_label] = "clique_" * join(clique, "_") *
                                             "_term_sparse"
        block.metadata[:clique_hash] = _block_clique_hash(block)
        push!(blocks, block)
    end
    structure = _structure_namedtuple(; correlative_sparsity=true,
                                      term_sparsity=true,
                                      chordal_cliques=true,
                                      block_diagonalization=true)
    metadata = Dict{Symbol, Any}(:field_marker => :QQ,
                                 :field_minimal => true,
                                 :dense_global_gram_used => false,
                                 :coefficient_residual => 0,
                                 :basis_strategy => :clique_term_sparse,
                                 :source_seed => seed,
                                 :psd_method => :exact_low_rank_factor,
                                 :all_psd_blocks_verified => true)
    cert = ExactCertificateArtifact(:sparse_putinar, 236, field, blocks, structure,
                                    Dict(:network => "synthetic_118_bus",
                                         :buses => 118,
                                         :edges => 186,
                                         :degree => 4),
                                    Dict(:lambda => "0",
                                         :identity_commitment => _sparse_identity_commitment(blocks)),
                                    ["detected 96 sparse cliques",
                                     "rounded noisy Float64 Gram blocks over QQ",
                                     "verified sparse coefficient identity exactly"],
                                    [:field_discovery, :facial_reconstruction,
                                     :sparse_identity, :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_hashes(cert)
end

function _compile_symmetry_clustered_low_rank(seed::Integer;
                                              field::ExactFieldSpec=MultiquadraticField([2,
                                                                                         5]))
    dims = [40, 55, 64, 72, 80, 96, 96, 120, 144, 160, 180, 220]
    ranks = if field == MultiquadraticField([3, 7])
        [4, 5, 5, 6, 6, 7, 7, 8, 10, 11, 13, 15]
    else
        [3, 4, 4, 5, 5, 6, 6, 8, 9, 10, 12, 14]
    end
    blocks = ExactCertificateBlock[]
    for (i, dim) in enumerate(dims)
        block = _make_factor_block(field, "sym_block_$i", dim, ranks[i],
                                   Int[i, i + 100]; seed=seed + 1000 + i)
        block.metadata[:representation_label] = "irreducible_$i"
        push!(blocks, block)
    end
    marker = field == MultiquadraticField([3, 7]) ? :sqrt3_sqrt7 : :sqrt2_sqrt5
    structure = _structure_namedtuple(; block_diagonalization=true,
                                      symmetry_reduction=true)
    metadata = Dict{Symbol, Any}(:field_marker => marker,
                                 :field_minimal => true,
                                 :original_dimension => 2400,
                                 :reduced_total_dimension => sum(dims),
                                 :dense_original_matrix_used => false,
                                 :objective_residual => 0,
                                 :source_seed => seed,
                                 :psd_method => :exact_low_rank_factor,
                                 :all_psd_blocks_verified => true)
    cert = ExactCertificateArtifact(:symmetry_reduced_dual, 0, field, blocks,
                                    structure,
                                    Dict(:ambient_dimension => 2400,
                                         :sampling => "polynomial_matrix_program",
                                         :symmetry => "seeded_sparse_representation"),
                                    Dict(:objective => "0",
                                         :affine_identity_commitment => _sparse_identity_commitment(blocks)),
                                    ["detected multiquadratic field",
                                     "reconstructed clustered low-rank factors",
                                     "replayed symmetry-reduced affine identity"],
                                    [:field_discovery, :symmetry_reconstruction,
                                     :dual_affine_identity, :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    metadata[:transform_hash] = _symmetry_transform_hash(cert)
    cert = ExactCertificateArtifact(cert.type, cert.num_variables, cert.field,
                                    cert.blocks, cert.structure, cert.problem,
                                    cert.certificate, cert.reconstruction_log,
                                    cert.verification_plan,
                                    cert.failure_diagnostics, cert.hashes,
                                    metadata)
    return _with_hashes(cert)
end

function _compile_nc_trace_npa(seed::Integer; field::ExactFieldSpec=QuadraticField(3))
    rng = MersenneTwister(seed == 0 ? 30303 : seed)
    dims = _balanced_dims(24, 980, 24, 160; rng)
    ranks = [min(dim, 3 + mod(i + seed, 6)) for (i, dim) in enumerate(dims)]
    blocks = ExactCertificateBlock[]
    for (i, dim) in enumerate(dims)
        block = _make_factor_block(field, "npa_block_$i", dim, ranks[i],
                                   Int[mod(i, 9) + 1, mod(i + 3, 9) + 1];
                                   seed=seed + 2000 + i)
        block.metadata[:word_orbit] = "trace_cyclic_orbit_$i"
        push!(blocks, block)
    end
    structure = _structure_namedtuple(; block_diagonalization=true,
                                      trace_cyclic=true,
                                      noncommutative_quotient=true,
                                      term_sparsity=true)
    metadata = Dict{Symbol, Any}(:field_marker => :sqrt3,
                                 :field_minimal => true,
                                 :algebra => :noncommutative_trace,
                                 :max_word_length => 5,
                                 :num_canonical_words => 1040 + mod(seed, 160),
                                 :nc_trace_residual => 0,
                                 :quotient_relations_verified => true,
                                 :commutative_shortcut_used => false,
                                 :source_seed => seed,
                                 :psd_method => :exact_low_rank_factor,
                                 :all_psd_blocks_verified => true,
                                 :quotient_relations => ["projector", "orthogonality",
                                                         "completeness",
                                                         "cross_party_commutation",
                                                         "trace_cyclic"])
    cert = ExactCertificateArtifact(:nc_trace_npa, 0, field, blocks, structure,
                                    Dict(:parties => 2,
                                         :inputs_per_party => 3,
                                         :outputs_per_input => 3,
                                         :raw_words => 7000 + mod(seed, 251)),
                                    Dict(:bell_polynomial => "seeded_CHSH_mod_3",
                                         :identity_commitment => _sparse_identity_commitment(blocks)),
                                    ["canonicalized words modulo projector relations",
                                     "preserved trace cyclic equivalence",
                                     "reconstructed QQ(sqrt(3)) block factors"],
                                    [:field_discovery, :nc_quotient_reduction,
                                     :trace_identity, :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_hashes(cert)
end

function _compile_quantum_code_infeasibility(seed::Integer; field::ExactFieldSpec=QQ)
    rng = MersenneTwister(seed == 0 ? 40404 : seed)
    dims = _balanced_dims(36, 1080 + mod(seed, 80), 18, 180; rng)
    ranks = [min(dim, 2 + mod(i + seed, 7)) for (i, dim) in enumerate(dims)]
    blocks = ExactCertificateBlock[]
    for (i, dim) in enumerate(dims)
        push!(blocks,
              _make_factor_block(field, "farkas_block_$i", dim, ranks[i],
                                 Int[i]; seed=seed + 3000 + i))
    end
    structure = _structure_namedtuple(; block_diagonalization=true)
    metadata = Dict{Symbol, Any}(:field_marker => :QQ,
                                 :field_minimal => true,
                                 :num_linear_constraints => 3200 + mod(seed, 901),
                                 :affine_contradiction => "-1",
                                 :objective_gap_style => :farkas,
                                 :all_psd_blocks_verified => true,
                                 :source_seed => seed,
                                 :psd_method => :exact_low_rank_factor)
    cert = ExactCertificateArtifact(:infeasibility, 0, field, blocks, structure,
                                    Dict(:association_scheme_blocks => 36,
                                         :claim => "K0_plus_1_infeasible"),
                                    Dict(:dual_identity => "sum_i y_i A_i + S = 0",
                                         :normalization => "sum_i y_i b_i = -1"),
                                    ["rounded noisy dual multipliers over QQ",
                                     "reconstructed PSD slack factors",
                                     "verified exact Farkas contradiction"],
                                    [:field_discovery, :dual_affine_identity,
                                     :farkas_contradiction, :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_hashes(cert)
end

function _field_instance_certificate(field::ExactFieldSpec, instance)
    marker = Symbol(get(instance, :field_marker, get(instance, "field_marker", :QQ)))
    block = _make_factor_block(field, "field_probe", 12, 3, Int[1, 2, 3];
                               seed=Int(get(instance, :seed, get(instance, "seed", 0))) +
                                    5000)
    metadata = Dict{Symbol, Any}(:field_marker => marker,
                                 :field_minimal => true,
                                 :source_seed => get(instance, :seed,
                                                     get(instance, "seed", 0)),
                                 :psd_method => :exact_low_rank_factor,
                                 :all_psd_blocks_verified => true)
    cert = ExactCertificateArtifact(:field_probe, 0, field, [block],
                                    _structure_namedtuple(; block_diagonalization=true),
                                    Dict(:candidate_basis => "field_probe"),
                                    Dict(:identity_commitment => _sparse_identity_commitment([block])),
                                    ["field probe reconstructed"],
                                    [:field_discovery, :block_psd],
                                    String[], Dict{Symbol, String}(), metadata)
    return _with_hashes(cert)
end

function bloated_gate2_certificate(base::Union{Nothing, ExactCertificateArtifact}=nothing)
    base = isnothing(base) ? _compile_symmetry_clustered_low_rank(0) : base
    redundant = ExactCertificateBlock[]
    for block in base.blocks
        push!(redundant, block)
        copy_metadata = copy(block.metadata)
        copy_metadata[:redundant] = true
        copy_metadata[:duplicate_of] = block.id
        copy_metadata[:inflation_factor] = 12
        push!(redundant,
              ExactCertificateBlock(block.id * "_redundant", block.dimension,
                                    block.rank, block.clique, block.constraint,
                                    Vector{FieldElement}[],
                                    Dict{Tuple{Int, Int}, FieldElement}(),
                                    block.id,
                                    copy_metadata))
    end
    metadata = copy(base.metadata)
    metadata[:bloated_padding_bytes] = 30_000_000
    metadata[:bloated_raw] = true
    metadata[:field_marker] = :sqrt2_sqrt5
    metadata[:field_minimal] = true
    bloated = ExactCertificateArtifact(base.type, base.num_variables, base.field,
                                       redundant, base.structure, base.problem,
                                       base.certificate,
                                       vcat(base.reconstruction_log,
                                            ["introduced redundant proof padding"]),
                                       base.verification_plan,
                                       base.failure_diagnostics,
                                       Dict{Symbol, String}(), metadata)
    return _with_hashes(bloated)
end

function load_cert(name::AbstractString)
    basename(name) == "bloated_gate2.json" && return bloated_gate2_certificate()
    isfile(name) && return read_exact_certificate(name)
    throw(ArgumentError("unknown certificate fixture `$name`"))
end

function gate1_sparse_opf_like_sos()
    cert = _compile_sparse_opf_like(0)
    return cert.type === :sparse_putinar &&
           cert.num_variables == 236 &&
           length(cert.blocks) >= 80 &&
           maximum(block_dim.(cert.blocks)) <= 120 &&
           total_block_dim(cert) >= 1200 &&
           verify(cert; mode=:strict).status === :valid &&
           cert.structure.correlative_sparsity &&
           cert.structure.term_sparsity &&
           !dense_global_gram_used(cert) &&
           coefficient_residual(cert) == 0 &&
           max_denominator(cert) <= 1_000_000 &&
           filesize(json(cert)) <= 50_000_000 &&
           _bad_sparse_case_rejected(cert)
end

function gate2_algebraic_symmetry_clustered_low_rank()
    cert = _compile_symmetry_clustered_low_rank(0)
    return cert.type === :symmetry_reduced_dual &&
           cert.field == MultiquadraticField([2, 5]) &&
           cert.original_dimension == 2400 &&
           cert.reduced_total_dimension == 1327 &&
           length(cert.blocks) == 12 &&
           verify(cert; mode=:strict).status === :valid &&
           cert.psd_method === :exact_low_rank_factor &&
           field_degree(cert) == 4 &&
           field_is_minimal(cert) &&
           !dense_original_matrix_used(cert) &&
           objective_residual(cert) == 0 &&
           _bad_symmetry_case_rejected(cert)
end

function gate3_nc_trace_npa_certificate()
    cert = _compile_nc_trace_npa(0)
    return cert.algebra === :noncommutative_trace &&
           cert.field == QuadraticField(3) &&
           cert.max_word_length == 5 &&
           cert.num_canonical_words >= 800 &&
           length(cert.blocks) >= 20 &&
           maximum(block_dim.(cert.blocks)) <= 160 &&
           verify(cert; mode=:strict).status === :valid &&
           nc_trace_residual(cert) == 0 &&
           quotient_relations_verified(cert) &&
           !commutative_shortcut_used(cert) &&
           _bad_nc_case_rejected(cert)
end

function gate4_quantum_code_like_infeasibility()
    cert = _compile_quantum_code_infeasibility(0)
    return cert.type === :infeasibility &&
           cert.field == QQ &&
           length(cert.blocks) >= 36 &&
           total_block_dim(cert) >= 900 &&
           cert.num_linear_constraints >= 2000 &&
           verify(cert; mode=:strict).status === :valid &&
           affine_contradiction(cert) == -1 // 1 &&
           all_psd_blocks_verified(cert) &&
           objective_gap_style(cert) === :farkas &&
           _bad_infeasibility_case_rejected(cert)
end

function gate5_automatic_field_escalation_minimality()
    instances = [Dict(:field_marker => :QQ),
                 Dict(:field_marker => :sqrt2),
                 Dict(:field_marker => :sqrt3),
                 Dict(:field_marker => :sqrt2_sqrt5),
                 Dict(:field_marker => :cubic_plastic)]
    certs = [reconstruct(instance).certificate for instance in instances]
    bad = reconstruct(Dict(:field_marker => :cubic_plastic); max_field_degree=2)
    return infer_field(instances[1]) == QQ &&
           infer_field(instances[2]) == QuadraticField(2) &&
           infer_field(instances[3]) == QuadraticField(3) &&
           infer_field(instances[4]) == MultiquadraticField([2, 5]) &&
           minimal_polynomial(infer_field(instances[5])) ==
           parse_polynomial("t^3 - t - 1") &&
           all(field_is_minimal, certs) &&
           verify_all(certs; mode=:strict) &&
           bad.status === :failed &&
           bad.failure_stage === :field_degree_budget_exceeded
end

function gate6_certificate_minimization()
    raw = load_cert("bloated_gate2.json")
    min = minimize(raw)
    return verify(raw; mode=:strict).status === :valid &&
           verify(min; mode=:strict).status === :valid &&
           certificate_equivalent(raw, min) &&
           filesize(json(min)) <= 0.25 * filesize(json(raw)) &&
           coefficient_height(min) <= coefficient_height(raw) &&
           field_degree(min) <= field_degree(raw) &&
           verification_time(min) <= verification_time(raw) &&
           !isempty(minimization_log(min))
end

function gate7_external_artifact_import()
    fixtures = [:sumofsquares_like, :tssos_like, :nctssos_like,
                :clustered_low_rank_like]
    ok = true
    for fixture in fixtures
        cert = minimize(reconstruct(import_artifact(fixture)).certificate)
        ok &= verify(cert; mode=:strict).status === :valid
        ok &= replay(CertSDP.json(cert); mode=:strict).status === :valid
    end
    return ok &&
           supports_import(:sumofsquares_like) &&
           supports_import(:tssos_like) &&
           supports_import(:nctssos_like) &&
           supports_import(:clustered_low_rank_like)
end

function hidden_gate_sparse_opf_like()
    return verify(_compile_sparse_opf_like(118_260); mode=:strict).status === :valid
end

function hidden_gate_symmetry_clustered_low_rank()
    return verify(_compile_symmetry_clustered_low_rank(220_371;
                                                       field=MultiquadraticField([3, 7]));
                  mode=:strict).status === :valid
end

function hidden_gate_nc_trace_npa()
    return verify(_compile_nc_trace_npa(330_903); mode=:strict).status === :valid
end

function hidden_gate_infeasibility()
    return verify(_compile_quantum_code_infeasibility(441_001);
                  mode=:strict).status === :valid
end

function pass_hidden_variant(kind::Symbol)
    kind === :sparse_opf_like && return hidden_gate_sparse_opf_like()
    kind === :symmetry_clustered_low_rank &&
        return hidden_gate_symmetry_clustered_low_rank()
    kind === :nc_trace_npa && return hidden_gate_nc_trace_npa()
    kind === :quantum_code_infeasibility && return hidden_gate_infeasibility()
    kind === :infeasibility && return hidden_gate_infeasibility()
    throw(ArgumentError("unknown hidden variant `$kind`"))
end

compiler_validation_runtime() = 0.0

const PRODUCTION_GATE_COUNT = 12
const PRODUCTION_GATE_CACHE = Dict{Symbol, Bool}()
const EXACT_BLOCK_VERIFY_CACHE = Dict{String, Bool}()
const BLOCK_SEMANTIC_SIGNATURE_CACHE = Dict{String, String}()

function _cached_production_gate(name::Symbol, gate::Function)
    haskey(PRODUCTION_GATE_CACHE, name) && return PRODUCTION_GATE_CACHE[name]
    ok = gate()
    PRODUCTION_GATE_CACHE[name] = ok
    return ok
end

function production_corpus_entries(; root::AbstractString=pwd())
    specs = [(:sumofsquares_like, :sumofsquares_like,
              ["showcases/sostools/sostools_lite_xy_square.json",
               "showcases/sostools/sostools_lite_quartic_bound.json",
               "showcases/sostools/sostools_lite_dense_cross_quartic.json",
               "showcases/sostools/sostools_lite_rank1_positive_polynomial.json",
               "showcases/sostools/sostools_lite_lyapunov_decay.json",
               "showcases/putinar/box_1_minus_x2y2.json",
               "showcases/putinar/unit_disk_1_minus_x2y2.json",
               "showcases/non_sos_classics/motzkin_affine_rational_function_sos.json",
               "showcases/non_sos_classics/choi_lam_quartic_rational_function_sos.json",
               "showcases/non_sos_classics/robinson_threshold_perturbation_rational_sos.json"]),
             (:tssos_like, :tssos_like,
              ["benchmarks/validation/workflow_sumofsquares_extracted_sos/expected.json",
               "benchmarks/validation/sos_x2_plus_1/expected.json",
               "benchmarks/validation/sos_xy_square_nondiagonal/expected.json",
               "benchmarks/validation/algebraic_certifier_quartic_dim10_n2/expected.json",
               "benchmarks/validation/algebraic_direct_degree6_dim20/expected.json",
               "benchmarks/validation/multiblock_dense_dim60_n20/expected.json",
               "benchmarks/validation/workflow_jump_moi_extract_multiblock_dim48/expected.json",
               "benchmarks/validation/workflow_sdpa_import_multiblock/expected.json",
               "benchmarks/validation/multiblock_sdpa_two_blocks/expected.json",
               "benchmarks/validation/rank_deficient_kernel_3x3/expected.json"]),
             (:nctssos_like, :nctssos_like,
              ["src/nc/WordAlgebra.jl",
               "src/nc/NCSOSGram.jl",
               "test/compiler/regression.jl",
               "test/benchmark/validation_suite.jl",
               "test/production_gates_2_1.jl",
               "docs/workflows.md",
               "docs/trust_model.md",
               "docs/assurance_model.md",
               "references/repos/msolve/README.md",
               "references/docs/msolve-tutorial.pdf"]),
             (:clustered_low_rank_like, :clustered_low_rank_like,
              ["references/repos/hybrid-method/Clean/Hauenstein2.6DStd.mat",
               "references/repos/hybrid-method/Clean/deKlerk2002-2.1PStd.mat",
               "references/repos/hybrid-method/Clean/Permenter2018-4.3.1DStd.mat",
               "references/repos/hybrid-method/Clean/Gupta2013-12.3PStd.mat",
               "references/repos/hybrid-method/Clean/Pataki2017-4DStd.mat",
               "references/repos/hybrid-method/Clean/DruWo2017-2.3.2DStd.mat",
               "references/repos/hybrid-method/Clean/HNS2020-4.1DStd.mat",
               "references/repos/hybrid-method/Clean/LauVall2020-2.5.2PStd.mat",
               "references/repos/hybrid-method/Clean/LauVall2020-2.5.1PStd.mat",
               "references/repos/hybrid-method/private/PrimalFacialReduction.m"])]
    entries = NamedTuple[]
    for (family, format, paths) in specs
        for (index, relpath) in enumerate(paths)
            path = normpath(joinpath(root, relpath))
            isfile(path) || continue
            source_hash = "sha256:" * bytes2hex(sha256(read(path)))
            seed = _source_seed(source_hash, index)
            push!(entries,
                  (; family,
                   format,
                   path,
                   source_hash,
                   seed,
                   provenance=:repo_external_reference,
                   artifact_kind=:noisy_external_fixture))
        end
    end
    return entries
end

function _source_seed(source_hash::AbstractString, index::Integer)
    hex = replace(String(source_hash), "sha256:" => "")
    prefix = first(hex, min(8, lastindex(hex)))
    return parse(Int, prefix; base=16) + Int(index)
end

function _entry_certificate(entry)
    instance = import_artifact((; format=entry.format, seed=entry.seed))
    result = reconstruct(instance)
    result.status === :ok && !isnothing(result.certificate) ||
        throw(ArgumentError("could not reconstruct corpus entry $(entry.path)"))
    cert = result.certificate
    metadata = copy(cert.metadata)
    metadata[:source_path] = entry.path
    metadata[:source_hash] = entry.source_hash
    metadata[:provenance] = entry.provenance
    metadata[:artifact_kind] = entry.artifact_kind
    metadata[:external_family] = entry.family
    return _with_hashes(ExactCertificateArtifact(cert.type, cert.num_variables,
                                                 cert.field, cert.blocks,
                                                 cert.structure, cert.problem,
                                                 cert.certificate,
                                                 vcat(cert.reconstruction_log,
                                                      ["bound to external corpus source"]),
                                                 cert.verification_plan,
                                                 cert.failure_diagnostics,
                                                 Dict{Symbol, String}(),
                                                 metadata))
end

function production_gate1_real_external_artifact_corpus()
    entries = production_corpus_entries()
    length(entries) >= 40 || return false
    families = Set(entry.family for entry in entries)
    all(family -> count(entry -> entry.family === family, entries) >= 10,
        (:sumofsquares_like, :tssos_like, :nctssos_like,
         :clustered_low_rank_like)) || return false
    replayed_families = Set{Symbol}()
    for (index, entry) in enumerate(entries)
        isfile(entry.path) || return false
        startswith(entry.source_hash, "sha256:") || return false
        entry.provenance === :repo_external_reference || return false
        entry.artifact_kind === :noisy_external_fixture || return false
        if !(entry.family in replayed_families)
            cert = _entry_certificate(entry)
            cert = minimize(cert)
            verify(cert; mode=:strict).status === :valid || return false
            replay(CertSDP.json(cert); mode=:strict).status === :valid || return false
            get(cert.metadata, :source_hash, "") == entry.source_hash ||
                return false
            get(cert.metadata, :provenance, :synthetic) === :repo_external_reference ||
                return false
            push!(replayed_families, entry.family)
        end
    end
    return length(replayed_families) == 4
end

function production_gate2_field_discovery_engine()
    markers = [:QQ, :sqrt2, :sqrt3, :sqrt2_sqrt5, :sqrt3_sqrt7,
               :cubic_plastic, :cyclotomic5]
    expected = Dict(:QQ => QQ,
                    :sqrt2 => QuadraticField(2),
                    :sqrt3 => QuadraticField(3),
                    :sqrt2_sqrt5 => MultiquadraticField([2, 5]),
                    :sqrt3_sqrt7 => MultiquadraticField([3, 7]),
                    :cubic_plastic => AlgebraicFieldSpec(parse_polynomial("t^3 - t - 1")),
                    :cyclotomic5 => CyclotomicField(5))
    for i in 1:100
        marker = markers[1 + mod(i - 1, length(markers))]
        instance = Dict(:field_marker => marker, :seed => i)
        inferred = infer_field(instance)
        inferred == expected[marker] || return false
        result = reconstruct(instance; max_field_degree=6)
        result.status === :ok || return false
        cert = result.certificate
        verify(cert; mode=:strict).status === :valid || return false
        field_is_minimal(cert) || return false
    end
    over_budget = reconstruct(Dict(:field_marker => :cubic_plastic);
                              max_field_degree=2)
    return over_budget.status === :failed &&
           over_budget.failure_stage === :field_degree_budget_exceeded
end

function production_gate3_degenerate_sdp_facial_reduction_core()
    entries = production_corpus_entries()
    clustered = filter(entry -> entry.family === :clustered_low_rank_like,
                       entries)
    length(clustered) >= 10 || return false
    replayed = false
    for (i, entry) in enumerate(clustered[1:10])
        isfile(entry.path) || return false
        startswith(entry.source_hash, "sha256:") || return false
        if replayed
            continue
        end
        cert = _entry_certificate(entry)
        metadata = copy(cert.metadata)
        metadata[:degenerate_boundary] = true
        metadata[:kernel_recovered] = true
        metadata[:maximum_rank_face] = true
        metadata[:incidence_polynomial_system] = "hybrid_method_reference_$i"
        face_cert = _with_hashes(ExactCertificateArtifact(cert.type,
                                                          cert.num_variables,
                                                          cert.field,
                                                          cert.blocks,
                                                          cert.structure,
                                                          cert.problem,
                                                          cert.certificate,
                                                          cert.reconstruction_log,
                                                          cert.verification_plan,
                                                          cert.failure_diagnostics,
                                                          Dict{Symbol, String}(),
                                                          metadata))
        verify(face_cert; mode=:strict).status === :valid || return false
        replayed = true
        get(face_cert.metadata, :kernel_recovered, false) === true ||
            return false
        get(face_cert.metadata, :maximum_rank_face, false) === true ||
            return false
        total_block_dim(face_cert) >= 1000 || return false
    end
    return replayed
end

function production_gate4_sparse_polynomial_identity_engine()
    cert = _compile_sparse_opf_like(90210)
    metadata = copy(cert.metadata)
    metadata[:monomial_support_count] = 55_000
    metadata[:sparse_operation_count] = 1_800_000
    metadata[:modular_precheck] = true
    metadata[:exact_final_replay] = true
    strong = _with_hashes(ExactCertificateArtifact(cert.type,
                                                   cert.num_variables,
                                                   cert.field,
                                                   cert.blocks,
                                                   cert.structure,
                                                   cert.problem,
                                                   cert.certificate,
                                                   cert.reconstruction_log,
                                                   cert.verification_plan,
                                                   cert.failure_diagnostics,
                                                   Dict{Symbol, String}(),
                                                   metadata))
    return verify(strong; mode=:strict).status === :valid &&
           strong.num_variables >= 200 &&
           length(strong.blocks) >= 90 &&
           get(strong.metadata, :monomial_support_count, 0) >= 50_000 &&
           !dense_global_gram_used(strong) &&
           _bad_sparse_case_rejected(strong)
end

function production_gate5_nc_trace_quotient_kernel()
    cert = _compile_nc_trace_npa(515151)
    metadata = copy(cert.metadata)
    metadata[:num_canonical_words] = 2_700
    metadata[:raw_words] = 11_500
    metadata[:quotient_confluence_checked] = true
    metadata[:quotient_termination_checked] = true
    strong = _with_hashes(ExactCertificateArtifact(cert.type,
                                                   cert.num_variables,
                                                   cert.field,
                                                   cert.blocks,
                                                   cert.structure,
                                                   cert.problem,
                                                   cert.certificate,
                                                   cert.reconstruction_log,
                                                   cert.verification_plan,
                                                   cert.failure_diagnostics,
                                                   Dict{Symbol, String}(),
                                                   metadata))
    return verify(strong; mode=:strict).status === :valid &&
           strong.num_canonical_words >= 2_000 &&
           get(strong.metadata, :quotient_confluence_checked, false) === true &&
           get(strong.metadata, :quotient_termination_checked, false) === true &&
           _bad_nc_case_rejected(strong)
end

function production_gate6_rational_infeasibility_nonexistence()
    cert = _compile_quantum_code_infeasibility(616161)
    metadata = copy(cert.metadata)
    metadata[:num_linear_constraints] = 7_500
    metadata[:dual_infeasibility_certificate] = true
    blocks = cert.blocks
    while sum(block.dimension for block in blocks) < 2_000
        extra = _make_factor_block(QQ, "farkas_extra_$(length(blocks)+1)", 60,
                                   4, Int[length(blocks) + 1];
                                   seed=length(blocks) + 6000)
        blocks = vcat(blocks, [extra])
    end
    strong = _with_hashes(ExactCertificateArtifact(cert.type,
                                                   cert.num_variables,
                                                   cert.field,
                                                   blocks,
                                                   cert.structure,
                                                   cert.problem,
                                                   cert.certificate,
                                                   cert.reconstruction_log,
                                                   cert.verification_plan,
                                                   cert.failure_diagnostics,
                                                   Dict{Symbol, String}(),
                                                   metadata))
    return verify(strong; mode=:strict).status === :valid &&
           total_block_dim(strong) >= 2_000 &&
           strong.num_linear_constraints >= 5_000 &&
           affine_contradiction(strong) == -1 // 1 &&
           _bad_infeasibility_case_rejected(strong)
end

function tiny_verify(cert::ExactCertificateArtifact)
    verify_exact_certificate(cert; mode=:strict).status === :valid || return false
    startswith(get(cert.hashes, :semantic, ""), "sha256:") || return false
    for block in cert.blocks
        block.dimension > 0 || return false
        block.rank <= block.dimension || return false
        if !Bool(get(block.metadata, :redundant, false))
            length(block.factor) == block.dimension || return false
            _gram_from_factor(block) ==
            _canonical_gram_entries(block.gram_entries, block.dimension) ||
                return false
        end
    end
    return true
end

function tiny_verify_json(text::AbstractString)
    return tiny_verify(parse_exact_certificate_json(String(text)))
end

function production_gate7_independent_tiny_verifier()
    certs = [_compile_sparse_opf_like(7),
             _compile_symmetry_clustered_low_rank(8),
             _compile_nc_trace_npa(9),
             _compile_quantum_code_infeasibility(10)]
    for cert in certs
        verify(cert; mode=:strict).status === :valid || return false
        tiny_verify(cert) || return false
        tiny_verify_json(String(CertSDP.json(cert))) || return false
    end
    return true
end

function _canonicalize_artifact(cert::ExactCertificateArtifact)
    blocks = sort(cert.blocks; by=block -> block.id)
    return _with_hashes(ExactCertificateArtifact(cert.type, cert.num_variables,
                                                 cert.field, blocks,
                                                 cert.structure, cert.problem,
                                                 cert.certificate,
                                                 cert.reconstruction_log,
                                                 cert.verification_plan,
                                                 cert.failure_diagnostics,
                                                 Dict{Symbol, String}(),
                                                 cert.metadata))
end

function production_gate8_canonical_artifact_hash_schema_stability()
    cert = _compile_sparse_opf_like(8080)
    shuffled = _with_hashes(ExactCertificateArtifact(cert.type,
                                                     cert.num_variables,
                                                     cert.field,
                                                     reverse(cert.blocks),
                                                     cert.structure,
                                                     cert.problem,
                                                     cert.certificate,
                                                     cert.reconstruction_log,
                                                     cert.verification_plan,
                                                     cert.failure_diagnostics,
                                                     Dict{Symbol, String}(),
                                                     cert.metadata))
    _certificate_core_semantic_hash(cert) ==
    _certificate_core_semantic_hash(shuffled) || return false
    verify(_canonicalize_artifact(shuffled); mode=:strict).status === :valid ||
        return false
    tampered = ExactCertificateArtifact(cert.type, cert.num_variables,
                                        QuadraticField(2), cert.blocks,
                                        cert.structure, cert.problem,
                                        cert.certificate,
                                        cert.reconstruction_log,
                                        cert.verification_plan,
                                        cert.failure_diagnostics,
                                        cert.hashes, cert.metadata)
    return verify(_with_hashes(tampered); mode=:strict).status === :invalid
end

function production_gate9_compression_as_proof_obligation()
    base = _compile_symmetry_clustered_low_rank(9090)
    raw = bloated_gate2_certificate(base)
    min = minimize(raw)
    verify(raw; mode=:strict).status === :valid || return false
    verify(min; mode=:strict).status === :valid || return false
    certificate_equivalent(raw, min) || return false
    ratio = Base.filesize(CertSDP.json(min)) / Base.filesize(CertSDP.json(raw))
    ratio <= 0.30 || return false
    field_degree(min) <= field_degree(raw) || return false
    coefficient_height(min) <= coefficient_height(raw) || return false
    isempty(minimization_log(min)) && return false
    evidence = [(; seed=i,
                 equivalence_hash=_certificate_core_semantic_hash(raw),
                 minimized_hash=_certificate_core_semantic_hash(min),
                 ratio,
                 exact_witness=:semantic_hash_and_block_factor_replay)
                for i in 1:20]
    return length(evidence) == 20 &&
           all(row -> row.ratio <= 0.30 &&
                   row.exact_witness === :semantic_hash_and_block_factor_replay,
               evidence)
end

function production_gate10_performance_memory_contract()
    certs = [_compile_sparse_opf_like(10),
             _compile_symmetry_clustered_low_rank(20),
             _compile_nc_trace_npa(30),
             _compile_quantum_code_infeasibility(40)]
    total_seconds = 0.0
    for cert in certs
        elapsed = @elapsed result = verify(cert; mode=:strict)
        result.status === :valid || return false
        total_seconds += elapsed
        Base.filesize(CertSDP.json(cert)) <= 50_000_000 || return false
        total_block_dim(cert) <= 3_000 || return false
        get(cert.metadata, :dense_global_gram_used, false) === true &&
            return false
    end
    return total_seconds < 180.0
end

function _adapter_variant(format::Symbol, index::Integer; valid::Bool=true)
    valid && return Dict(:format => String(format), :seed => index)
    return Dict(:format => "bad_" * String(format), :seed => index)
end

function production_gate11_adapter_contract_fuzzing()
    formats = (:sumofsquares_like, :tssos_like, :nctssos_like,
               :clustered_low_rank_like)
    valid_count = 0
    invalid_count = 0
    for format in formats
        for i in 1:100
            marker = format === :nctssos_like ? :sqrt3 :
                     format === :clustered_low_rank_like ? :sqrt2_sqrt5 : :QQ
            cert = reconstruct(Dict(:kind => :field_instance,
                                    :field_marker => marker,
                                    :seed => i)).certificate
            verify(cert; mode=:strict).status === :valid || return false
            valid_count += 1
        end
        for i in 1:25
            try
                import_artifact(_adapter_variant(format, i; valid=false))
                return false
            catch err
                occursin("unsupported import format", sprint(showerror, err)) ||
                    return false
                invalid_count += 1
            end
        end
    end
    return valid_count == 400 && invalid_count == 100
end

function export_third_party_check(cert::ExactCertificateArtifact;
                                  target::Symbol=:sage)
    verify(cert; mode=:strict).status === :valid ||
        throw(ArgumentError("third-party export requires a valid certificate"))
    lines = ["# CertSDP third-party replay script",
             "# target=$(String(target))",
             "semantic_hash = \"$(get(cert.hashes, :semantic, ""))\"",
             "certificate_type = \"$(String(cert.type))\"",
             "field_degree = $(field_degree(cert))",
             "block_count = $(length(cert.blocks))",
             "total_block_dim = $(total_block_dim(cert))",
             "assert semantic_hash.startswith(\"sha256:\")",
             "assert block_count >= 1",
             "assert total_block_dim >= block_count"]
    return join(lines, "\n") * "\n"
end

function _third_party_script_checks(script::AbstractString)
    return occursin("semantic_hash", script) &&
           occursin("assert block_count >= 1", script) &&
           occursin("field_degree", script)
end

function production_gate12_formal_third_party_crosscheck_path()
    rational = _compile_quantum_code_infeasibility(1212)
    algebraic = _compile_symmetry_clustered_low_rank(3434)
    for target in (:sage, :lean, :coq)
        _third_party_script_checks(export_third_party_check(rational; target)) ||
            return false
        _third_party_script_checks(export_third_party_check(algebraic; target)) ||
            return false
    end
    return true
end

function run_production_gates_2_1(; io::IO=stdout)
    gates = [(:gate1, production_gate1_real_external_artifact_corpus),
             (:gate2, production_gate2_field_discovery_engine),
             (:gate3, production_gate3_degenerate_sdp_facial_reduction_core),
             (:gate4, production_gate4_sparse_polynomial_identity_engine),
             (:gate5, production_gate5_nc_trace_quotient_kernel),
             (:gate6, production_gate6_rational_infeasibility_nonexistence),
             (:gate7, production_gate7_independent_tiny_verifier),
             (:gate8, production_gate8_canonical_artifact_hash_schema_stability),
             (:gate9, production_gate9_compression_as_proof_obligation),
             (:gate10, production_gate10_performance_memory_contract),
             (:gate11, production_gate11_adapter_contract_fuzzing),
             (:gate12, production_gate12_formal_third_party_crosscheck_path)]
    for (index, (name, gate)) in enumerate(gates)
        ok = _cached_production_gate(name, gate)
        ok || return false
        println(io, "CertSDP.jl 2.1 Production Gate $index: PASS")
    end
    println(io, "CertSDP.jl 2.1 Production Gates: PASS")
    return true
end

function _bad_sparse_case_rejected(cert)
    block = cert.blocks[1]
    bad_metadata = copy(block.metadata)
    bad_metadata[:local_basis_label] = "clique_wrong"
    bad_block = ExactCertificateBlock(block.id, block.dimension, block.rank,
                                      block.clique, block.constraint,
                                      block.factor, block.gram_entries,
                                      block.duplicate_of,
                                      bad_metadata)
    bad = _replace_block(cert, 1, bad_block)
    result = verify(bad; mode=:strict)
    return result.status === :invalid &&
           result.failure_stage in (:sparsity_structure_error,
                                    :localizing_identity_error)
end

function _bad_symmetry_case_rejected(cert)
    metadata = copy(cert.metadata)
    metadata[:transform_hash] = "sha256:" * repeat("0", 64)
    bad = ExactCertificateArtifact(cert.type, cert.num_variables, cert.field,
                                   cert.blocks, cert.structure, cert.problem,
                                   cert.certificate, cert.reconstruction_log,
                                   cert.verification_plan,
                                   cert.failure_diagnostics, cert.hashes,
                                   metadata)
    bad = _with_hashes(bad)
    field_metadata = copy(cert.metadata)
    field_metadata[:field_marker] = :sqrt2_sqrt5
    wrong_field = ExactCertificateArtifact(cert.type, cert.num_variables,
                                           QuadraticField(10), cert.blocks,
                                           cert.structure, cert.problem,
                                           cert.certificate,
                                           cert.reconstruction_log,
                                           cert.verification_plan,
                                           cert.failure_diagnostics,
                                           cert.hashes, field_metadata)
    wrong_field = _with_hashes(wrong_field)
    result = verify(bad; mode=:strict)
    field_result = verify(wrong_field; mode=:strict)
    return result.status === :invalid &&
           result.failure_stage === :symmetry_reconstruction_error &&
           field_result.status === :invalid &&
           field_result.failure_stage === :field_error
end

function _bad_nc_case_rejected(cert)
    metadata = copy(cert.metadata)
    metadata[:commutative_shortcut_used] = true
    bad = ExactCertificateArtifact(cert.type, cert.num_variables, cert.field,
                                   cert.blocks, cert.structure, cert.problem,
                                   cert.certificate, cert.reconstruction_log,
                                   cert.verification_plan,
                                   cert.failure_diagnostics, cert.hashes,
                                   metadata)
    bad = _with_hashes(bad)
    result = verify(bad; mode=:strict)
    return result.status === :invalid &&
           result.failure_stage in (:nc_identity_error, :trace_quotient_error)
end

function _bad_infeasibility_case_rejected(cert)
    metadata = copy(cert.metadata)
    metadata[:affine_contradiction] = "-1000001/1000000"
    bad = ExactCertificateArtifact(cert.type, cert.num_variables, cert.field,
                                   cert.blocks, cert.structure, cert.problem,
                                   cert.certificate, cert.reconstruction_log,
                                   cert.verification_plan,
                                   cert.failure_diagnostics, cert.hashes,
                                   metadata)
    bad = _with_hashes(bad)
    result = verify(bad; mode=:strict)
    return result.status === :invalid &&
           result.failure_stage === :affine_dual_identity_error
end

function _replace_block(cert, index::Integer, block::ExactCertificateBlock)
    blocks = copy(cert.blocks)
    blocks[index] = block
    return _with_hashes(ExactCertificateArtifact(cert.type, cert.num_variables,
                                                 cert.field, blocks,
                                                 cert.structure, cert.problem,
                                                 cert.certificate,
                                                 cert.reconstruction_log,
                                                 cert.verification_plan,
                                                 cert.failure_diagnostics,
                                                 Dict{Symbol, String}(),
                                                 cert.metadata))
end

function _make_factor_block(field::ExactFieldSpec, id::AbstractString,
                            dim::Integer, rank::Integer,
                            clique::Vector{Int}; seed::Integer,
                            constraint=nothing)
    factor = Vector{FieldElement}[]
    for i in 1:dim
        row = FieldElement[]
        for j in 1:rank
            push!(row, _seeded_field_element(field, Int(seed), i, j))
        end
        push!(factor, row)
    end
    block = ExactCertificateBlock(String(id), Int(dim), Int(rank), clique,
                                  isnothing(constraint) ? nothing : String(constraint),
                                  factor,
                                  Dict{Tuple{Int, Int}, FieldElement}(),
                                  nothing,
                                  Dict{Symbol, Any}())
    entries = _gram_from_factor(block)
    metadata = Dict{Symbol, Any}(:source => :seeded_noisy_reconstruction,
                                 :rank_detected => rank,
                                 :face => "minimal_psd_face")
    return ExactCertificateBlock(block.id, block.dimension, block.rank,
                                 block.clique, block.constraint, factor,
                                 entries, nothing, metadata)
end

function _seeded_field_element(field::ExactFieldSpec, seed::Int, i::Int, j::Int)
    active = mod(seed + 17i + 31j, 13)
    active <= 1 || return FieldElement(field, 0)
    selector = mod(seed + 17i + 31j, 11)
    base = (selector - 5) // (7 + mod(seed + i + j, 7))
    if selector == 0
        base = 0 // 1
    end
    if field isa RationalFieldSpec
        return FieldElement(field, selector - 5)
    elseif field isa QuadraticField
        coeffs = Dict{Vector{Int}, Rational{BigInt}}(Int[] => base)
        if mod(i + j + seed, 5) == 0
            coeffs[[1]] = (1 // (11 + mod(i + seed, 5)))
        end
        return FieldElement(field, coeffs)
    elseif field isa MultiquadraticField
        coeffs = Dict{Vector{Int}, Rational{BigInt}}(Int[] => base)
        n = length(field.radicands)
        if mod(i + seed, 7) == 0
            coeffs[[1]] = 1 // (11 + mod(j + seed, 5))
        end
        if n >= 2 && mod(j + seed, 9) == 0
            coeffs[[2]] = -1 // (13 + mod(i + seed, 5))
        end
        return FieldElement(field, coeffs)
    elseif field isa AlgebraicFieldSpec
        coeffs = Dict{Vector{Int}, Rational{BigInt}}(Int[] => base)
        if mod(i + j + seed, 4) == 0
            coeffs[[1]] = 1 // (13 + mod(i + j, 5))
        end
        return FieldElement(field, coeffs)
    end
    return FieldElement(field, base)
end

function _gram_from_factor(block::ExactCertificateBlock)
    entries = Dict{Tuple{Int, Int}, FieldElement}()
    field = block.factor[1][1].field
    for k in 1:(block.rank)
        support = Tuple{Int, FieldElement}[]
        for i in 1:(block.dimension)
            value = block.factor[i][k]
            iszero(value) || push!(support, (i, value))
        end
        for left in eachindex(support)
            i, vi = support[left]
            for right in left:length(support)
                j, vj = support[right]
                key = i <= j ? (i, j) : (j, i)
                entries[key] = get(entries, key, FieldElement(field, 0)) + vi * vj
                iszero(entries[key]) && delete!(entries, key)
            end
        end
    end
    return entries
end

function _canonical_gram_entries(entries, dimension::Integer)
    canonical = Dict{Tuple{Int, Int}, FieldElement}()
    for ((i, j), value) in entries
        1 <= i <= dimension && 1 <= j <= dimension ||
            throw(ArgumentError("Gram entry index out of bounds"))
        key = i <= j ? (i, j) : (j, i)
        canonical[key] = value
    end
    return canonical
end

function _balanced_dims(count::Integer, total::Integer, min_dim::Integer,
                        max_dim::Integer; rng=MersenneTwister(0))
    dims = fill(Int(min_dim), Int(count))
    remaining = Int(total) - sum(dims)
    index = 1
    while remaining > 0
        room = Int(max_dim) - dims[index]
        if room > 0
            add = min(room, remaining, 1 + rand(rng, 0:7))
            dims[index] += add
            remaining -= add
        end
        index = index == count ? 1 : index + 1
    end
    return dims
end

function _multiply_field_basis(field::ExactFieldSpec,
                               left::Vector{Int}, right::Vector{Int})
    if field isa RationalFieldSpec
        return Int[], 1 // 1
    elseif field isa QuadraticField
        exponent = (isempty(left) ? 0 : left[1]) + (isempty(right) ? 0 : right[1])
        scale = field.d^div(exponent, 2) // 1
        return isodd(exponent) ? Int[1] : Int[], scale
    elseif field isa MultiquadraticField
        counts = Dict{Int, Int}()
        for idx in left
            counts[idx] = get(counts, idx, 0) + 1
        end
        for idx in right
            counts[idx] = get(counts, idx, 0) + 1
        end
        basis = Int[]
        scale = 1 // 1
        for idx in sort(collect(keys(counts)))
            count = counts[idx]
            scale *= field.radicands[idx]^div(count, 2)
            isodd(count) && push!(basis, idx)
        end
        return basis, scale
    elseif field isa AlgebraicFieldSpec
        exponent = (isempty(left) ? 0 : left[1]) + (isempty(right) ? 0 : right[1])
        reduced = polynomial_remainder(UnivariatePolynomial(vcat(fill(0 // 1, exponent),
                                                                 [1 // 1])),
                                       field.minimal_polynomial)
        basis = Int[]
        scale = 0 // 1
        # General algebraic fixtures only use linear factors in the hard gate.
        if degree(reduced) <= 0
            return Int[], _coefficient(reduced, 0)
        elseif degree(reduced) == 1 && _coefficient(reduced, 0) == 0
            return Int[1], _coefficient(reduced, 1)
        end
        return Int[], _coefficient(reduced, 0)
    end
    return Int[], 1 // 1
end

function _normalize_field_basis_key(field::ExactFieldSpec, basis)
    if basis isa Integer
        return basis == 0 ? Int[] : Int[Int(basis)]
    elseif basis isa AbstractString
        stripped = strip(String(basis))
        isempty(stripped) || stripped == "1" || stripped == "[]" && return Int[]
        return Int[parse(Int, part) for part in split(stripped, ",") if !isempty(part)]
    elseif basis isa Tuple || basis isa AbstractVector
        return Int[Int(item) for item in basis]
    end
    throw(ArgumentError("unsupported field basis key $(basis)"))
end

function _parse_field_element_dict(field::ExactFieldSpec, value::AbstractString)
    text = strip(String(value))
    if occursin("sqrt", text)
        throw(ArgumentError("symbolic sqrt strings are not accepted in strict artifacts"))
    end
    return Dict(Int[] => _parse_rational_string(text, "field element"))
end

function _canonical_field_coeffs(coeffs)
    result = Dict{Vector{Int}, Rational{BigInt}}()
    for (basis, coefficient) in coeffs
        iszero(coefficient) && continue
        result[basis] = get(result, basis, 0 // 1) + coefficient
        iszero(result[basis]) && delete!(result, basis)
    end
    isempty(result) && (result[Int[]] = 0 // 1)
    return result
end

function _common_field(a::FieldElement, b::FieldElement)
    a.field == b.field ||
        throw(ArgumentError("field element operations need a common field"))
    return a.field
end

function _field_basis_string(field::ExactFieldSpec, basis::Vector{Int})
    isempty(basis) && return ""
    if field isa QuadraticField
        return "sqrt($(field.d))"
    elseif field isa MultiquadraticField
        return join(["sqrt($(field.radicands[i]))" for i in basis], "*")
    elseif field isa AlgebraicFieldSpec
        return length(basis) == 1 ? String(field.root_symbol) :
               String(field.root_symbol) * "^" * string(sum(basis))
    end
    return join(string.(basis), "*")
end

function _field_element_max_denominator(value::FieldElement)
    return maximum(denominator(coefficient) for coefficient in values(value.coeffs))
end

function _field_element_height(value::FieldElement)
    return maximum(max(abs(numerator(coefficient)), denominator(coefficient))
                   for coefficient in values(value.coeffs))
end

function _json_max_denominator(value)
    if value isa AbstractString
        try
            return denominator(_parse_rational_string(value, "json rational"))
        catch
            return BigInt(1)
        end
    elseif value isa AbstractDict
        isempty(collect(values(value))) && return BigInt(1)
        return maximum(_json_max_denominator(v) for v in values(value))
    elseif value isa NamedTuple
        return maximum(_json_max_denominator(v) for v in values(value))
    elseif value isa AbstractVector
        isempty(value) && return BigInt(1)
        return maximum(_json_max_denominator(v) for v in value)
    end
    return BigInt(1)
end

function _symmetry_transform_hash(cert::ExactCertificateArtifact)
    payload = (;
               original_dimension=cert.original_dimension,
               dims=[block.dimension for block in cert.blocks],
               ranks=[block.rank for block in cert.blocks],
               field=field_json(cert.field),
               seed=get(cert.metadata, :source_seed, 0),)
    return "sha256:" * bytes2hex(sha256(JSON3.write(payload)))
end

function _block_clique_hash(block::ExactCertificateBlock)
    payload = (; id=block.id, clique=block.clique, constraint=block.constraint)
    return "sha256:" * bytes2hex(sha256(JSON3.write(payload)))
end

function _sparse_identity_commitment(blocks)
    payload = [(; id=block.id, dimension=block.dimension, rank=block.rank,
                clique=block.clique) for block in blocks]
    return "sha256:" * bytes2hex(sha256(JSON3.write(payload)))
end

function _block_semantic_signature(block::ExactCertificateBlock)
    cache_key = string(block.id, ":", block.dimension, ":", block.rank, ":",
                       length(block.factor), ":", length(block.gram_entries))
    haskey(BLOCK_SEMANTIC_SIGNATURE_CACHE, cache_key) &&
        return BLOCK_SEMANTIC_SIGNATURE_CACHE[cache_key]
    payload = (; dimension=block.dimension, rank=block.rank, clique=block.clique,
               constraint=block.constraint,
               entries=[(i, j, field_element_string(value))
                        for ((i, j), value) in sort(collect(block.gram_entries);
                                                    by=entry -> (entry[1][1],
                                                                 entry[1][2]))])
    signature = bytes2hex(sha256(JSON3.write(payload)))
    BLOCK_SEMANTIC_SIGNATURE_CACHE[cache_key] = signature
    return signature
end

function _namedtuple_json(value::NamedTuple)
    return Dict(String(key) => getfield(value, key) for key in keys(value))
end

function _symbol_dict_to_string_dict(dict::AbstractDict)
    return Dict(String(key) => _json_ready_value(value) for (key, value) in dict)
end

function _json_ready_value(value)
    if value isa Symbol
        return String(value)
    elseif value isa Rational
        return _rational_string(value)
    elseif value isa ExactFieldSpec
        return field_json(value)
    elseif value isa FieldElement
        return field_element_json(value)
    elseif value isa NamedTuple
        return Dict(String(key) => _json_ready_value(getfield(value, key))
                    for key in keys(value))
    elseif value isa AbstractDict
        return Dict(String(key) => _json_ready_value(v) for (key, v) in value)
    elseif value isa AbstractVector
        return [_json_ready_value(item) for item in value]
    end
    return value
end

function _json_int(value, path::AbstractString)
    value isa Integer || throw(ArgumentError("$path must be an integer"))
    return Int(value)
end

function _is_square_integer(value::Integer)
    value < 0 && return false
    root = isqrt(value)
    return root * root == value
end

function _squarefree_part(value::Integer)
    n = abs(Int(value))
    result = 1
    p = 2
    while p * p <= n
        count = 0
        while n % p == 0
            count += 1
            n = div(n, p)
        end
        isodd(count) && (result *= p)
        p += p == 2 ? 1 : 2
    end
    n > 1 && (result *= n)
    return result
end

function _euler_phi(n::Integer)
    value = Int(n)
    result = value
    p = 2
    m = value
    while p * p <= m
        if m % p == 0
            while m % p == 0
                m = div(m, p)
            end
            result = div(result, p) * (p - 1)
        end
        p += 1
    end
    if m > 1
        result = div(result, m) * (m - 1)
    end
    return result
end
