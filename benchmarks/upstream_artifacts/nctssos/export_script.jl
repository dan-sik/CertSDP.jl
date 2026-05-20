# Reproduces the checked-in NCTSSOS.jl upstream mini-pack.
# The release gate consumes raw_output.json and certsdp_input.json;
# strict replay never trusts this script.
using JSON3
println("exported NCTSSOS.jl mini-pack")
