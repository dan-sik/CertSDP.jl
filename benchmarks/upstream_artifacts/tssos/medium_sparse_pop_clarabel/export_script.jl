# Re-run this checked-in upstream solver session from the repository root.
repo = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
env = joinpath(repo, "benchmarks", "upstream_artifacts", "real_solver_env")
script = joinpath(repo, "scripts", "run_real_solver_sessions.jl")
run(`julia --project=$env $script --only tssos_clarabel_medium`)
