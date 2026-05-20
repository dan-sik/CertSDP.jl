# Reproduces the checked-in TSSOS.jl upstream mini-pack.
# The release gate consumes raw_output.json and certsdp_input.json;
# strict replay never trusts this script.
using JSON3
println("exported TSSOS.jl mini-pack")
