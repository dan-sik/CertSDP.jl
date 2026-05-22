using JSON3
using SHA: sha256

const K3 = CertSDP.Kernel

function certsdp3_low_rank_fixture(; n::Int=6)
    factor = [[i == 1 ? 1//1 : 0//1] for i in 1:n]
    entries = Tuple{Int, Int, Rational{BigInt}}[(1, 1, 1//1)]
    matrix = K3.SparseSymmetricRationalMatrix(n, entries)
    proof = K3.ExactLowRankPSDProof(matrix, factor, [1//1])
    cert = K3.make_low_rank_psd_certificate(matrix, proof)
    return (; matrix, proof, cert)
end

function certsdp3_chordal_fixture(; n::Int=24, clique_size::Int=6,
                                  overlap::Int=2, complete_cliques::Bool=true)
    cliques = Vector{Int}[]
    start = 1
    while start <= n
        stop = min(n, start + clique_size - 1)
        push!(cliques, collect(start:stop))
        stop == n && break
        start = stop - overlap + 1
    end
    separators = [intersect(cliques[i], cliques[i + 1])
                  for i in 1:(length(cliques) - 1)]
    structure = K3.ChordalPSDStructure(n, cliques, separators)

    global_entries = Dict{Tuple{Int, Int}, Rational{BigInt}}()
    clique_proofs = K3.CliquePSDProof[]
    for (index, clique) in enumerate(cliques)
        local_entries = Tuple{Int, Int, Rational{BigInt}}[]
        if complete_cliques
            for a in eachindex(clique), b in a:length(clique)
                push!(local_entries, (a, b, 1//1))
                i, j = clique[a], clique[b]
                i <= j || ((i, j) = (j, i))
                global_entries[(i, j)] = 1//1
            end
            local_factor = [[1//1] for _ in clique]
            local_diagonal = [1//1]
        else
            for a in eachindex(clique)
                push!(local_entries, (a, a, 1//1))
                i = clique[a]
                global_entries[(i, i)] = 1//1
            end
            local_factor = [[i == j ? 1//1 : 0//1 for j in eachindex(clique)]
                            for i in eachindex(clique)]
            local_diagonal = fill(1//1, length(clique))
        end
        local_matrix = K3.SparseSymmetricRationalMatrix(length(clique),
                                                        local_entries)
        local_proof = K3.ExactLowRankPSDProof(local_matrix, local_factor,
                                              local_diagonal)
        push!(clique_proofs,
              K3.CliquePSDProof(Symbol("clique_", index), index, clique,
                                local_matrix, local_proof))
    end
    global_matrix = K3.SparseSymmetricRationalMatrix(n,
        [(i, j, value) for ((i, j), value) in global_entries])
    separator_proofs = K3.SeparatorConsistencyProof[]
    for (index, separator) in enumerate(separators)
        left = clique_proofs[index].matrix
        right = clique_proofs[index + 1].matrix
        left_entries = Any[]
        right_entries = Any[]
        for a in eachindex(separator), b in a:length(separator)
            push!(left_entries,
                  (; i=a, j=b, value=K3.rational_string(left[a, b])))
            push!(right_entries,
                  (; i=a, j=b, value=K3.rational_string(right[a, b])))
        end
        payload = (;
            vertices=separator,
            left=left_entries,
            right=right_entries,
        )
        value_hash = "sha256:" * bytes2hex(sha256(JSON3.write(payload)))
        push!(separator_proofs,
              K3.SeparatorConsistencyProof(Symbol("separator_", index),
                                           index, index + 1, separator,
                                           value_hash))
    end
    proof = K3.ChordalPSDProof(global_matrix, structure, clique_proofs,
                               separator_proofs)
    cert = K3.make_chordal_psd_certificate(global_matrix, proof)
    return (; matrix=global_matrix, structure, proof, cert)
end

function certsdp3_write_json(path::AbstractString, object)
    open(path, "w") do io
        JSON3.pretty(io, object)
        println(io)
    end
    return path
end

function certsdp3_cert_json(cert)
    return certsdp3_mutable_json(K3.certificate_json_v3(cert))
end

function certsdp3_mutable_json(value)
    if value isa JSON3.Object || value isa AbstractDict || value isa NamedTuple
        return Dict{Symbol, Any}(Symbol(key) => certsdp3_mutable_json(value[key])
                                 for key in keys(value))
    elseif value isa AbstractVector
        return Any[certsdp3_mutable_json(entry) for entry in value]
    end
    return value
end
