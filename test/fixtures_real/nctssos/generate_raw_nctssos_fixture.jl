#!/usr/bin/env julia
# Rebuilds the committed raw NCTSSOS/quantum-shaped snapshots from repository fixtures.
using JSON3
root = normpath(joinpath(@__DIR__, "..", "..", "fixtures_external", "nctssos"))
for (src, dst) in [
    ("raw_nctssos_trace_medium.json", "raw_nctssos_trace_medium.json"),
    ("raw_nctssos_quantum_i3322_medium.json", "raw_quantum_i3322_medium.json"),
]
    data = JSON3.read(read(joinpath(root, src), String))
    open(joinpath(@__DIR__, dst), "w") do io
        JSON3.pretty(io, data); println(io)
    end
end
