using CertSDP
using JuMP
using LinearAlgebra
import MathOptInterface as MOI

function qstring(x::Rational)
    return denominator(x) == 1 ? string(numerator(x)) :
           string(numerator(x), "/", denominator(x))
end

function write_pretty_json(path, value)
    mkpath(dirname(path))
    open(path, "w") do io
        CertSDP.JSON3.pretty(io, value)
        return println(io)
    end
    return path
end

function symmetric_pattern(d, variable_index, block_index)
    matrix = fill(0 // 1, d, d)
    den = 50 + variable_index + 3block_index
    for i in 1:d, j in i:d
        value = (mod(2i + 3j + variable_index + block_index, 7) - 3) // den
        matrix[i, j] = value
        matrix[j, i] = value
    end
    return matrix
end

function patterned_spd(d; shift=1)
    B = Matrix{Rational{BigInt}}(undef, d, d)
    for i in 1:d, j in 1:d
        B[i, j] = ((i == j ? 5 : 0) + mod(3i + 5j + shift, 9) - 4) // 11
    end
    A = transpose(B) * B
    for i in 1:d
        A[i, i] += 1 // 1
    end
    return A
end

function rational_rotation(d; shift=1)
    R = Matrix{Rational{BigInt}}(I, d, d)
    for i in 1:d, j in 1:d
        i == j && continue
        R[i, j] = (mod(i + 2j + shift, 5) - 2) // (9d)
    end
    return R
end

function diag_matrix(values)
    n = length(values)
    A = fill(0 // 1, n, n)
    for i in 1:n
        A[i, i] = values[i]
    end
    return A
end

function block_matrix(block_index, d)
    if block_index == 1
        return patterned_spd(d; shift=101)
    elseif block_index == 2
        R = rational_rotation(d; shift=17)
        D = diag_matrix(vcat(fill(2 // 1, d - 1), 0 // 1))
        return transpose(R) * D * R
    elseif isodd(block_index)
        return patterned_spd(d; shift=30 + block_index)
    end
    return diag_matrix(vcat(fill((block_index + 2) // 1, d - 2),
                            fill(0 // 1, 2)))
end

function triangle_entries(matrix)
    n = size(matrix, 1)
    return [matrix[i, j] for j in 1:n for i in 1:j]
end

function add_psd_constraint!(model, vars, block_index, A0)
    d = size(A0, 1)
    entries = Any[]
    for (i, j) in [(i, j) for j in 1:d for i in 1:j]
        expr = A0[i, j]
        for (var_index, var) in enumerate(vars)
            expr += symmetric_pattern(d, var_index, block_index)[i, j] * var
        end
        push!(entries, expr)
    end
    return @constraint(model, entries in MOI.PositiveSemidefiniteConeTriangle(d))
end

function build_model()
    dims = fill(8, 6)
    model = GenericModel{Rational{BigInt}}()
    @variable(model, x[1:12])
    for (block_index, d) in enumerate(dims)
        add_psd_constraint!(model, x, block_index, block_matrix(block_index, d))
    end
    return model
end

function main(args)
    length(args) == 1 ||
        error("usage: source.jl <output-dir>")
    outdir = args[1]
    mkpath(outdir)
    model = build_model()
    problem = CertSDP.extract_lmi(model)
    CertSDP.write_problem(joinpath(outdir, "problem.json"), problem)
    write_pretty_json(joinpath(outdir, "approx.json"),
                      (;
                       certsdp_version="0.1",
                       solution=(;
                                 type="rational",
                                 x=[qstring(0 // 1)
                                    for _ in 1:CertSDP.num_variables(problem)],),))
    write_pretty_json(joinpath(outdir, "extraction_manifest.json"),
                      (;
                       source_kind="jump_moi_extract",
                       source_format="JuMP/MOI",
                       block_count=CertSDP.num_blocks(problem),
                       block_sizes=CertSDP.block_sizes(problem),
                       total_psd_dimension=CertSDP.matrix_size(problem),
                       variable_count=CertSDP.num_variables(problem),
                       model_description="JuMP GenericModel with six affine PSD constraints in MOI.PositiveSemidefiniteConeTriangle(8)",
                       certificate_candidate="zero rational point",))
    return println("extracted JuMP/MOI multi-block LMI with total dimension ",
                   CertSDP.matrix_size(problem), " and ",
                   CertSDP.num_variables(problem), " variables")
end

main(ARGS)
