using Dates
using JSON3
using LinearAlgebra
using Pkg
using SHA

using Clarabel
using DynamicPolynomials
using JuMP
using MathOptInterface
using MultivariatePolynomials
using NCTSSOS
using SumOfSquares
using TSSOS

const MOI = MathOptInterface
const MP = MultivariatePolynomials

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))
const UPSTREAM_ROOT = joinpath(REPO_ROOT, "benchmarks", "upstream_artifacts")
const SOLVER_ENV = joinpath(UPSTREAM_ROOT, "real_solver_env")

jsonwrite(path, object) =
    open(path, "w") do io
        JSON3.pretty(io, object)
        return println(io)
    end

function sha256_file(path::AbstractString)
    return "sha256:" * bytes2hex(sha256(read(path)))
end

function package_versions(names)
    wanted = Set(names)
    result = Dict{String, Any}()
    for dep in values(Pkg.dependencies())
        dep.name in wanted || continue
        result[dep.name] = Dict("version" => isnothing(dep.version) ? nothing :
                                             string(dep.version),
                                "source" => _package_source_label(dep.source),
                                "git_revision" => isnothing(dep.git_revision) ? nothing :
                                                  string(dep.git_revision),
                                "is_direct_dep" => dep.is_direct_dep)
    end
    return result
end

function _package_source_label(source)
    isnothing(source) && return nothing
    text = string(source)
    parts = splitpath(text)
    isempty(parts) && return text
    length(parts) >= 2 && return join(parts[(end - 1):end], "/")
    return last(parts)
end

function clip_line(line::AbstractString; limit::Int=1600)
    ncodeunits(line) <= limit && return String(line)
    return first(String(line), limit) * " ... [line clipped]"
end

function write_trimmed_session_log!(dir, full_log, command_text, started_at, finished_at)
    lines = isfile(full_log) ? readlines(full_log) : String[]
    head_count = min(120, length(lines))
    tail_count = min(120, max(length(lines) - head_count, 0))
    selected = String[]
    append!(selected, lines[1:head_count])
    if length(lines) > head_count + tail_count
        push!(selected,
              "... trimmed $(length(lines) - head_count - tail_count) middle lines; see session_full.log.gz ...")
    end
    tail_count > 0 && append!(selected, lines[(end - tail_count + 1):end])

    session_log = joinpath(dir, "session.log")
    open(session_log, "w") do io
        println(io, "CertSDP upstream real solver session")
        println(io, "command: $command_text")
        println(io, "started_at: $started_at")
        println(io, "finished_at: $finished_at")
        println(io, "full_log_sha256: $(sha256_file(full_log))")
        println(io, "full_log_path: session_full.log.gz")
        println(io, "--- transcript head/tail ---")
        for line in selected
            println(io, clip_line(line))
        end
    end
    return session_log
end

function capture_session!(dir, command_text, runner)
    mkpath(dir)
    full_log = joinpath(dir, "session_full.log")
    started_at = string(now(UTC))
    payload = Ref{Any}()
    open(full_log, "w") do io
        redirect_stdout(io) do
            redirect_stderr(io) do
                println("CertSDP upstream real solver session")
                println("command: $command_text")
                println("started_at: $started_at")
                println("julia_version: $(VERSION)")
                println("active_project: $(relpath(Base.active_project(), REPO_ROOT))")
                println("------------------------------------------------------------")
                payload[] = runner()
                println("------------------------------------------------------------")
                return println("session_runner_returned: true")
            end
        end
    end
    finished_at = string(now(UTC))
    session_log = write_trimmed_session_log!(dir, full_log, command_text,
                                             started_at, finished_at)
    full_sha = sha256_file(full_log)
    gzip_ok = false
    try
        run(`gzip -f -9 $full_log`)
        gzip_ok = true
    catch err
        @warn "could not gzip full session log" exception = (err, catch_backtrace())
    end
    compressed_log = gzip_ok ? full_log * ".gz" : full_log
    return payload[],
           Dict("started_at" => started_at,
                "finished_at" => finished_at,
                "session_log_sha256" => sha256_file(session_log),
                "full_log_sha256" => full_sha,
                "compressed_full_log_sha256" => sha256_file(compressed_log),
                "compressed_full_log" => basename(compressed_log))
end

function copy_environment_snapshot!(dir)
    for filename in ("Project.toml", "Manifest.toml")
        src = joinpath(SOLVER_ENV, filename)
        isfile(src) && cp(src, joinpath(dir, filename); force=true)
    end
end

function write_export_script!(dir, session_name)
    path = joinpath(dir, "export_script.jl")
    open(path, "w") do io
        println(io,
                "# Re-run this checked-in upstream solver session from the repository root.")
        println(io, "repo = normpath(joinpath(@__DIR__, \"..\", \"..\", \"..\", \"..\"))")
        println(io,
                "env = joinpath(repo, \"benchmarks\", \"upstream_artifacts\", \"real_solver_env\")")
        println(io, "script = joinpath(repo, \"scripts\", \"run_real_solver_sessions.jl\")")
        return println(io, "run(`julia --project=\$env \$script --only $session_name`)")
    end
    return path
end

function run_session!(session_name)
    spec = SESSION_SPECS[session_name]
    dir = joinpath(UPSTREAM_ROOT, spec.dir...)
    command_text = "julia --project=benchmarks/upstream_artifacts/real_solver_env scripts/run_real_solver_sessions.jl --only $session_name"
    payload, log_meta = capture_session!(dir, command_text, spec.runner)
    raw_path = joinpath(dir, "raw_output.json")
    input_path = joinpath(dir, "certsdp_input.json")
    jsonwrite(raw_path, payload["raw_output"])
    jsonwrite(input_path, payload["certsdp_input"])
    copy_environment_snapshot!(dir)
    export_script = write_export_script!(dir, session_name)
    provenance = Dict("session_name" => session_name,
                      "source_tool" => spec.source_tool,
                      "solver" => spec.solver,
                      "source_tool_version" => get(payload["raw_output"]["package_versions"],
                                                   spec.source_tool == "JuMP/MOI" ? "JuMP" :
                                                   replace(spec.source_tool, ".jl" => ""),
                                                   Dict()),
                      "source_export_command" => command_text,
                      "source_raw_sha256" => sha256_file(raw_path),
                      "certsdp_input_sha256" => sha256_file(input_path),
                      "session_log_sha256" => log_meta["session_log_sha256"],
                      "full_log_sha256" => log_meta["full_log_sha256"],
                      "compressed_full_log_sha256" => log_meta["compressed_full_log_sha256"],
                      "compressed_full_log" => log_meta["compressed_full_log"],
                      "export_script" => relpath(export_script, REPO_ROOT),
                      "generated_by_certsdp" => false,
                      "problem_scale" => payload["scale"],
                      "termination_status" => payload["termination_status"])
    jsonwrite(joinpath(dir, "provenance.json"), provenance)
    println("wrote $session_name -> $(relpath(dir, REPO_ROOT))")
    return true
end

function monomial_label(exps, names)
    pieces = String[]
    for (name, exp) in zip(names, exps)
        exp == 0 && continue
        push!(pieces, exp == 1 ? name : "$name^$exp")
    end
    return isempty(pieces) ? "1" : join(pieces, "*")
end

function monomial_dict(exps, names)
    return Dict(name => exp for (name, exp) in zip(names, exps) if exp != 0)
end

function monomial_exponents(mon, variables)
    return [MP.degree(mon, v) for v in variables]
end

function polynomial_terms(poly, variables, names)
    return [Dict("monomial" => monomial_dict(monomial_exponents(MP.monomial(term),
                                                                variables),
                                             names),
                 "coefficient" => string(MP.coefficient(term)))
            for term in MP.terms(poly)]
end

function dense_upper_entries(matrix; block_id=nothing)
    entries = Any[]
    for i in axes(matrix, 1), j in i:size(matrix, 2)
        item = Dict("i" => i, "j" => j, "value" => string(matrix[i, j]))
        block_id === nothing || (item["block"] = block_id)
        push!(entries, item)
    end
    return entries
end

function run_sumofsquares_session!()
    names = ["x$i" for i in 1:5]
    @polyvar x[1:5]
    basis = collect(monomials(x, 0:3))
    poly = sum((i % 7 + 1) * basis[i]^2 for i in eachindex(basis))
    for i in 1:(length(basis) - 1)
        poly += (1 // 20) * basis[i] * basis[i + 1]
    end
    model = SOSModel(optimizer_with_attributes(Clarabel.Optimizer,
                                               "verbose" => true,
                                               "max_iter" => 100))
    cref = @constraint(model, poly in SOSCone())
    println("SumOfSquares/JuMP/Clarabel medium GramMatrix export")
    println("variables: $(length(x)); basis_degree: 3; basis_size: $(length(basis))")
    optimize!(model)
    status = string(termination_status(model))
    gram = SumOfSquares.gram_matrix(cref)
    q = SumOfSquares.value_matrix(gram)
    gram_basis = collect(gram.basis.monomials)
    basis_exps = [monomial_exponents(m, x) for m in gram_basis]
    coefficient_map = Any[]
    for i in eachindex(gram_basis), j in i:length(gram_basis)
        push!(coefficient_map,
              Dict("gram_entry" => [i, j],
                   "monomial" => monomial_dict(basis_exps[i] .+ basis_exps[j],
                                               names),
                   "scale" => i == j ? "1" : "2"))
    end
    raw = Dict("format" => "sumofsquares_solver_session_raw",
               "source_tool" => "SumOfSquares.jl",
               "modeling_stack" => ["SumOfSquares.jl", "JuMP.jl", "Clarabel.jl"],
               "package_versions" => package_versions(["SumOfSquares", "JuMP",
                                                       "MathOptInterface",
                                                       "Clarabel",
                                                       "DynamicPolynomials",
                                                       "MultivariatePolynomials"]),
               "variables" => names,
               "basis_degree" => 3,
               "basis_size" => length(gram_basis),
               "target_polynomial_terms" => polynomial_terms(poly, x, names),
               "gram_matrix_noisy" => dense_upper_entries(q),
               "coefficient_map" => coefficient_map,
               "termination_status" => status,
               "result_count" => result_count(model),
               "noise_model" => "Clarabel Float64 SDP solution")
    certsdp_input = copy(raw)
    certsdp_input["format"] = "sumofsquares_real_export"
    certsdp_input["basis"] = [monomial_label(exp, names) for exp in basis_exps]
    certsdp_input["field_hint"] = nothing
    return Dict("raw_output" => raw,
                "certsdp_input" => certsdp_input,
                "scale" => Dict("variables" => length(x),
                                "basis_size" => length(gram_basis),
                                "psd_dimension" => size(q, 1),
                                "polynomial_terms" => length(MP.terms(poly)),
                                "gram_entries" => length(raw["gram_matrix_noisy"])),
                "termination_status" => status)
end

function run_jump_moi_session!()
    n = 48
    model = Model(optimizer_with_attributes(Clarabel.Optimizer,
                                            "verbose" => true,
                                            "max_iter" => 120))
    @variable(model, X[1:n, 1:n], Symmetric)
    @constraint(model, X in PSDCone())
    @constraint(model, diag[i=1:n], X[i, i] == 1.0)
    @constraint(model, band[i=1:(n - 1)], X[i, i + 1] == 0.35)
    @constraint(model, band2[i=1:(n - 2)], X[i, i + 2] == 0.12)
    @objective(model, Min,
               sum((mod(i + j, 7) - 3) * X[i, j] / n for i in 1:n for j in i:n))
    println("JuMP/MOI/Clarabel medium correlation-completion SDP export")
    println("psd_dimension: $n")
    optimize!(model)
    status = string(termination_status(model))
    xval = value.(X)
    constraints = Any[]
    append!(constraints,
            [Dict("type" => "diag", "i" => i, "j" => i,
                  "rhs" => "1.0") for i in 1:n])
    append!(constraints,
            [Dict("type" => "band1", "i" => i, "j" => i + 1,
                  "rhs" => "0.35") for i in 1:(n - 1)])
    append!(constraints,
            [Dict("type" => "band2", "i" => i, "j" => i + 2,
                  "rhs" => "0.12") for i in 1:(n - 2)])
    raw = Dict("format" => "jump_moi_clarabel_sdp_raw",
               "source_tool" => "JuMP/MOI",
               "modeling_stack" => ["JuMP.jl", "MathOptInterface.jl", "Clarabel.jl"],
               "package_versions" => package_versions(["JuMP", "MathOptInterface",
                                                       "Clarabel"]),
               "psd_dimension" => n,
               "moi_variable_count" => num_variables(model),
               "moi_constraint_count" => num_constraints(model;
                                                         count_variable_in_set_constraints=true),
               "linear_constraints" => constraints,
               "objective_sense" => "Min",
               "objective_value" => string(objective_value(model)),
               "solution_matrix_upper" => dense_upper_entries(xval),
               "termination_status" => status)
    certsdp_input = Dict("format" => "jump_moi_sdp_real_export",
                         "source_tool" => "JuMP/MOI",
                         "psd_dimension" => n,
                         "linear_constraints" => constraints,
                         "objective_sense" => "Min",
                         "solution_matrix_upper" => raw["solution_matrix_upper"],
                         "termination_status" => status,
                         "field_hint" => nothing)
    return Dict("raw_output" => raw,
                "certsdp_input" => certsdp_input,
                "scale" => Dict("psd_dimension" => n,
                                "moi_variables" => raw["moi_variable_count"],
                                "moi_constraints" => raw["moi_constraint_count"],
                                "matrix_entries" => length(raw["solution_matrix_upper"])),
                "termination_status" => status)
end

function flatten_block_sizes(blocksize)
    sizes = Int[]
    for outer in blocksize, middle in outer, inner in middle
        append!(sizes, Int.(inner))
    end
    return sizes
end

function run_tssos_session!()
    n = 80
    @polyvar x[1:n]
    objective = sum((x[i]^2 - x[i])^2 for i in 1:n) +
                sum((x[i] * x[i + 1] - 1 // 4)^2 for i in 1:(n - 1))
    ineq = [1 - x[i]^2 for i in 1:n]
    pop = [objective; ineq]
    model = Model(optimizer_with_attributes(Clarabel.Optimizer,
                                            "verbose" => true,
                                            "max_iter" => 80))
    println("TSSOS/Clarabel medium sparse POP export")
    println("variables: $n; inequalities: $(length(ineq)); order: 2")
    opt, sol, data = TSSOS.cs_tssos(pop, x, 2; CS="MF", TS="block",
                                    QUIET=false, solve=true, solution=false,
                                    Gram=true, model=model)
    status = string(data.SDP_status)
    block_sizes = flatten_block_sizes(data.blocksize)
    gram_blocks = Any[]
    for (clique_idx, clique_blocks) in enumerate(data.GramMat)
        for (family_idx, family_blocks) in enumerate(clique_blocks)
            for (block_idx, matrix) in enumerate(family_blocks)
                id = "clique$(clique_idx)_family$(family_idx)_block$(block_idx)"
                push!(gram_blocks,
                      Dict("id" => id,
                           "dimension" => size(matrix, 1),
                           "entries" => dense_upper_entries(matrix)))
            end
        end
    end
    raw = Dict("format" => "tssos_solver_session_raw",
               "source_tool" => "TSSOS.jl",
               "modeling_stack" => ["TSSOS.jl", "JuMP.jl", "Clarabel.jl"],
               "package_versions" => package_versions(["TSSOS", "JuMP",
                                                       "MathOptInterface",
                                                       "Clarabel",
                                                       "DynamicPolynomials"]),
               "variables" => ["x$i" for i in 1:n],
               "order" => 2,
               "objective_terms" => length(MP.terms(objective)),
               "num_inequality_constraints" => length(ineq),
               "cliques" => [Int.(clique) for clique in data.cliques],
               "ksupp_count" => length(data.ksupp),
               "block_sizes" => block_sizes,
               "gram_blocks" => gram_blocks,
               "optimum" => string(opt),
               "termination_status" => status)
    certsdp_input = Dict("format" => "tssos_real_sparse_solver_session_export",
                         "source_tool" => "TSSOS.jl",
                         "variables" => raw["variables"],
                         "cliques" => raw["cliques"],
                         "order" => 2,
                         "block_sizes" => block_sizes,
                         "noisy_gram_blocks" => gram_blocks,
                         "ksupp_count" => raw["ksupp_count"],
                         "termination_status" => status,
                         "field_hint" => nothing)
    return Dict("raw_output" => raw,
                "certsdp_input" => certsdp_input,
                "scale" => Dict("variables" => n,
                                "cliques" => length(data.cliques),
                                "affine_constraints" => length(data.ksupp),
                                "psd_blocks" => length(block_sizes),
                                "max_block_dim" => maximum(block_sizes),
                                "total_block_dim" => sum(block_sizes)),
                "termination_status" => status)
end

function medium_trace_projection_case()
    supp = [[[1; 3], [1; 3], [5; 7], [5; 7]],
            [[2; 3], [2; 3], [5; 7], [5; 7]],
            [[1; 3], [1; 3], [5; 8], [5; 8]],
            [[2; 3], [2; 3], [5; 8], [5; 8]],
            [[1; 4], [1; 4], [6; 7], [6; 7]],
            [[2; 4], [2; 4], [6; 7], [6; 7]],
            [[1; 4], [1; 4], [6; 8], [6; 8]],
            [[2; 4], [2; 4], [6; 8], [6; 8]],
            [[1; 3], [2; 3], [5; 7], [5; 7]],
            [[1; 3], [1; 3], [5; 7], [5; 8]],
            [[1; 3], [2; 3], [5; 7], [5; 8]],
            [[1; 3], [1; 4], [5; 7], [6; 7]],
            [[1; 3], [2; 4], [5; 7], [6; 7]],
            [[1; 3], [1; 4], [5; 7], [6; 8]],
            [[1; 3], [2; 4], [5; 7], [6; 8]],
            [[2; 3], [2; 3], [5; 7], [5; 8]],
            [[2; 3], [1; 4], [5; 7], [6; 7]],
            [[2; 3], [2; 4], [5; 7], [6; 7]],
            [[2; 3], [1; 4], [5; 7], [6; 8]],
            [[2; 3], [2; 4], [5; 7], [6; 8]],
            [[1; 3], [2; 3], [5; 8], [5; 8]],
            [[1; 3], [1; 4], [5; 8], [6; 7]],
            [[1; 3], [2; 4], [5; 8], [6; 7]],
            [[1; 3], [1; 4], [5; 8], [6; 8]],
            [[1; 3], [2; 4], [5; 8], [6; 8]],
            [[2; 3], [1; 4], [5; 8], [6; 7]],
            [[2; 3], [2; 4], [5; 8], [6; 7]],
            [[2; 3], [1; 4], [5; 8], [6; 8]],
            [[2; 3], [2; 4], [5; 8], [6; 8]],
            [[1; 4], [2; 4], [6; 7], [6; 7]],
            [[1; 4], [1; 4], [6; 7], [6; 8]],
            [[1; 4], [2; 4], [6; 7], [6; 8]],
            [[2; 4], [2; 4], [6; 7], [6; 8]],
            [[1; 4], [2; 4], [6; 8], [6; 8]],
            [[1; 3], [5; 7]], [[2; 3], [5; 7]],
            [[1; 3], [5; 8]], [[2; 3], [5; 8]],
            [[1; 4], [6; 7]], [[2; 4], [6; 7]],
            [[1; 4], [6; 8]], [[2; 4], [6; 8]]]
    coeff = -[-1 / 8 *
              [1; 1; 1; 1; 1; 1; 1; 1; 2; 2; 4; 2; -2; -2; 2; 2; 2; -2; -2; 2; 2; 2; -2; -2;
               2; 2; -2; -2; 2; -2; -2; 4; -2; -2];
              1; 1; 1; 1; 1; -1; -1; 1]
    return supp, coeff
end

function run_nctssos_session!()
    n = 8
    order = 4
    supp, coeff = medium_trace_projection_case()
    println("NCTSSOS/COSMO medium trace projection export")
    println("variables: $n; order: $order; raw_words: $(length(supp))")
    opt, data = NCTSSOS.ptraceopt_first(supp, coeff, n, order; TS="block",
                                        constraint="projection",
                                        solver="COSMO", QUIET=true,
                                        Gram=false,
                                        cosmo_setting=NCTSSOS.cosmo_para(1e-5,
                                                                         1e-5,
                                                                         1500))
    block_sizes = Int.(vcat(data.blocksize...))
    status = isfinite(opt) ? "SOLVED_OR_APPROXIMATE" : "NONFINITE_OBJECTIVE"
    raw = Dict("format" => "nctssos_solver_session_raw",
               "source_tool" => "NCTSSOS.jl",
               "modeling_stack" => ["NCTSSOS.jl", "JuMP.jl", "COSMO.jl"],
               "package_versions" => package_versions(["NCTSSOS", "JuMP",
                                                       "MathOptInterface",
                                                       "COSMO",
                                                       "DynamicPolynomials"]),
               "algebra" => "noncommutative_trace",
               "variables" => ["x$i" for i in 1:n],
               "order" => order,
               "constraint" => "projection",
               "raw_trace_words" => supp,
               "coefficients" => string.(coeff),
               "ptsupp_count" => length(data.ptsupp),
               "ksupp_count" => length(data.ksupp),
               "block_sizes" => block_sizes,
               "moment_block_sample" => [dense_upper_entries(data.moment[i])
                                         for i in 1:min(length(data.moment), 8)],
               "optimum" => string(opt),
               "termination_status" => status)
    certsdp_input = Dict("format" => "nctssos_trace_solver_session_export",
                         "source_tool" => "NCTSSOS.jl",
                         "algebra" => "noncommutative_trace",
                         "variables" => raw["variables"],
                         "order" => order,
                         "constraint" => "projection",
                         "raw_trace_words" => supp,
                         "coefficients" => raw["coefficients"],
                         "ksupp_count" => raw["ksupp_count"],
                         "block_sizes" => block_sizes,
                         "termination_status" => status,
                         "field_hint" => nothing)
    return Dict("raw_output" => raw,
                "certsdp_input" => certsdp_input,
                "scale" => Dict("variables" => n,
                                "order" => order,
                                "raw_trace_words" => length(supp),
                                "canonical_support_terms" => length(data.ksupp),
                                "psd_blocks" => length(block_sizes),
                                "max_block_dim" => maximum(block_sizes),
                                "total_block_dim" => sum(block_sizes)),
                "termination_status" => status)
end

const SESSION_SPECS = Dict("sumofsquares_jump_clarabel_medium" => (dir=("sumofsquares",
                                                                        "medium_gram_clarabel"),
                                                                   source_tool="SumOfSquares.jl",
                                                                   solver="Clarabel.jl",
                                                                   runner=run_sumofsquares_session!),
                           "jump_moi_clarabel_medium" => (dir=("jump_moi",
                                                               "medium_correlation_sdp_clarabel"),
                                                          source_tool="JuMP/MOI",
                                                          solver="Clarabel.jl",
                                                          runner=run_jump_moi_session!),
                           "tssos_clarabel_medium" => (dir=("tssos",
                                                            "medium_sparse_pop_clarabel"),
                                                       source_tool="TSSOS.jl",
                                                       solver="Clarabel.jl",
                                                       runner=run_tssos_session!),
                           "nctssos_cosmo_medium" => (dir=("nctssos",
                                                           "medium_trace_projection_cosmo"),
                                                      source_tool="NCTSSOS.jl",
                                                      solver="COSMO.jl",
                                                      runner=run_nctssos_session!))

function selected_sessions(args)
    isempty(args) && return sort(collect(keys(SESSION_SPECS)))
    if length(args) == 2 && args[1] == "--only"
        haskey(SESSION_SPECS, args[2]) ||
            error("unknown session `$(args[2])`; known sessions: $(join(sort(collect(keys(SESSION_SPECS))), ", "))")
        return [args[2]]
    end
    return error("usage: julia --project=benchmarks/upstream_artifacts/real_solver_env scripts/run_real_solver_sessions.jl [--only SESSION]")
end

function main(args=ARGS)
    mkpath(UPSTREAM_ROOT)
    for session in selected_sessions(args)
        run_session!(session)
    end
    return true
end

main()
