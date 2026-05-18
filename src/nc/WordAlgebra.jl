"""
    NCWord

Exact noncommutative word used by the schema-v2 groundwork for NCTSSOS and
quantum-bound adapters. The empty word represents the multiplicative identity.
"""
struct NCWord
    letters::Vector{Symbol}

    function NCWord(letters::AbstractVector)
        return new(Symbol.(letters))
    end
end

nc_word(letters::Symbol...) = NCWord(Symbol[letters...])
nc_identity_word() = NCWord(Symbol[])

Base.:(==)(a::NCWord, b::NCWord) = a.letters == b.letters
function Base.isless(a::NCWord, b::NCWord)
    n = min(length(a.letters), length(b.letters))
    for i in 1:n
        left = String(a.letters[i])
        right = String(b.letters[i])
        left == right && continue
        return isless(left, right)
    end
    return length(a.letters) < length(b.letters)
end
Base.hash(word::NCWord, h::UInt) = hash(word.letters, h)
Base.length(word::NCWord) = length(word.letters)
function Base.show(io::IO, word::NCWord)
    return print(io, isempty(word.letters) ? "1" :
                     join(String.(word.letters), "*"))
end

function nc_multiply(a::NCWord, b::NCWord)
    return NCWord(vcat(a.letters, b.letters))
end

function nc_involution(word::NCWord)
    return NCWord([_nc_star_letter(letter) for letter in reverse(word.letters)])
end

function _nc_star_letter(letter::Symbol)
    text = String(letter)
    if endswith(text, "_star")
        return Symbol(text[1:(end - 5)])
    end
    return Symbol(text, "_star")
end

function nc_trace_canonical(word::NCWord)
    isempty(word.letters) && return word
    rotations = NCWord[]
    n = length(word.letters)
    for shift in 0:(n - 1)
        push!(rotations,
              NCWord([word.letters[((i + shift - 1) % n) + 1] for i in 1:n]))
    end
    return minimum(rotations)
end

struct NCPolynomialTerm
    word::NCWord
    coefficient::Rational{BigInt}

    function NCPolynomialTerm(word::NCWord, coefficient)
        return new(word, _to_big_rational(coefficient; name=:nc_coefficient))
    end
end

struct NCRewriteRule
    lhs::NCWord
    rhs::NCWord

    function NCRewriteRule(lhs::NCWord, rhs::NCWord)
        lhs == rhs &&
            throw(ArgumentError("NC rewrite rule must change the word"))
        isempty(lhs.letters) &&
            throw(ArgumentError("NC rewrite rule lhs must not be the identity word"))
        return new(lhs, rhs)
    end
end

struct NCRelationReduction
    rules::Vector{NCRewriteRule}
    trace_cyclic::Bool
    fingerprint::String

    function NCRelationReduction(rules::AbstractVector{NCRewriteRule};
                                 trace_cyclic::Bool=false)
        normalized = NCRewriteRule[rules...]
        fingerprint = _nc_relation_fingerprint(normalized, Bool(trace_cyclic))
        return new(normalized, Bool(trace_cyclic), fingerprint)
    end
end

function nc_terms_dict(terms::AbstractVector{NCPolynomialTerm};
                       trace_cyclic::Bool=false)
    result = Dict{NCWord, Rational{BigInt}}()
    for term in terms
        word = trace_cyclic ? nc_trace_canonical(term.word) : term.word
        result[word] = get(result, word, 0 // 1) + term.coefficient
        iszero(result[word]) && delete!(result, word)
    end
    return result
end

function nc_coefficient_matching(lhs::AbstractVector{NCPolynomialTerm},
                                 rhs::AbstractVector{NCPolynomialTerm};
                                 trace_cyclic::Bool=false)
    left = nc_terms_dict(lhs; trace_cyclic)
    right = nc_terms_dict(rhs; trace_cyclic)
    words = sort(collect(union(Set(keys(left)), Set(keys(right)))))
    return [(; word,
             lhs=get(left, word, 0 // 1),
             rhs=get(right, word, 0 // 1),
             exact=get(left, word, 0 // 1) == get(right, word, 0 // 1))
            for word in words]
end

function nc_identity_holds(lhs::AbstractVector{NCPolynomialTerm},
                           rhs::AbstractVector{NCPolynomialTerm};
                           trace_cyclic::Bool=false)
    return all(match -> match.exact,
               nc_coefficient_matching(lhs, rhs; trace_cyclic))
end

function nc_reduce_word(word::NCWord,
                        reduction::NCRelationReduction;
                        max_steps::Integer=10_000)
    max_steps > 0 || throw(ArgumentError("max_steps must be positive"))
    current = reduction.trace_cyclic ? nc_trace_canonical(word) : word
    for _ in 1:max_steps
        changed = false
        for rule in reduction.rules
            rewritten = _nc_apply_first_rule(current, rule)
            rewritten == current && continue
            current = reduction.trace_cyclic ? nc_trace_canonical(rewritten) :
                      rewritten
            changed = true
            break
        end
        changed || return current
    end
    throw(ArgumentError("NC relation reduction did not terminate within $max_steps steps"))
end

function nc_reduce_terms(terms::AbstractVector{NCPolynomialTerm},
                         reduction::NCRelationReduction)
    dict = Dict{NCWord, Rational{BigInt}}()
    for term in terms
        word = nc_reduce_word(term.word, reduction)
        dict[word] = get(dict, word, 0 // 1) + term.coefficient
        iszero(dict[word]) && delete!(dict, word)
    end
    return [NCPolynomialTerm(word, dict[word]) for word in sort(collect(keys(dict)))]
end

function nc_relation_reduction_matches(reduction::NCRelationReduction,
                                       fingerprint::AbstractString)
    return reduction.fingerprint == String(fingerprint)
end

function _nc_apply_first_rule(word::NCWord, rule::NCRewriteRule)
    lhs = rule.lhs.letters
    n = length(lhs)
    n == 0 && return word
    length(word.letters) < n && return word
    for start in 1:(length(word.letters) - n + 1)
        if word.letters[start:(start + n - 1)] == lhs
            rewritten = vcat(word.letters[1:(start - 1)],
                             rule.rhs.letters,
                             word.letters[(start + n):end])
            return NCWord(rewritten)
        end
    end
    return word
end

function _nc_relation_fingerprint(rules::Vector{NCRewriteRule},
                                  trace_cyclic::Bool)
    payload = (;
               trace_cyclic,
               rules=[(;
                       lhs=_nc_word_string(rule.lhs),
                       rhs=_nc_word_string(rule.rhs),)
                      for rule in rules],)
    return "sha256:" * bytes2hex(sha256(JSON3.write(payload)))
end
