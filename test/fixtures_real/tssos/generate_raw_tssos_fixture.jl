#!/usr/bin/env julia
# Rebuilds the committed raw TSSOS-shaped snapshots from repository fixtures.
using JSON3
root = normpath(joinpath(@__DIR__, "..", "..", "fixtures_external", "tssos"))
for (src, dst) in [
    ("raw_tssos_sparse_poly_medium.json", "raw_tssos_sparse_poly_medium.json"),
    ("raw_tssos_opf_like_5bus.json", "raw_tssos_opf_or_control.json"),
    ("raw_tssos_control_lyapunov.json", "raw_tssos_control_lyapunov.json"),
]
    data = JSON3.read(read(joinpath(root, src), String))
    open(joinpath(@__DIR__, dst), "w") do io
        JSON3.pretty(io, data); println(io)
    end
end
