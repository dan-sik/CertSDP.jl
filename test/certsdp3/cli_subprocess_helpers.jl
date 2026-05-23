using JSON3

function certsdp3_subprocess(args::Vector{String}; cwd=nothing)
    root = normpath(joinpath(@__DIR__, "..", ".."))
    cmd = `$(Base.julia_cmd()) --project=$(root) --startup-file=no -e 'using CertSDP; exit(CertSDP.main(ARGS))' $(args)`
    out = IOBuffer()
    err = IOBuffer()
    proc = if isnothing(cwd)
        run(pipeline(cmd, stdout=out, stderr=err); wait=false)
    else
        run(pipeline(Cmd(cmd; dir=cwd), stdout=out, stderr=err); wait=false)
    end
    wait(proc)
    return (; exit_code=proc.exitcode,
            stdout=String(take!(out)),
            stderr=String(take!(err)))
end
