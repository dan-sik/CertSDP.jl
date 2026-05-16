# JuMP / MOI Examples

These examples exercise the optional JuMP/MOI extractor for affine PSD
constraints.

Run them from the repository root:

```bash
julia --project=examples/jump -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=examples/jump examples/jump/affine_square_psd.jl
julia --project=examples/jump examples/jump/multiple_psd_blocks.jl
julia --project=examples/jump examples/jump/psd_variable.jl
julia --project=examples/jump examples/jump/unsupported_bilinear.jl
```

The example project commits a small `Manifest.toml` that develops the repository
root as `CertSDP`, so fresh checkouts and `certsdp doctor` can exercise the
optional JuMP/MOI extractor without relying on the main project to load JuMP.

The first three examples extract JuMP SDP models into `LMIProblem` or
`BlockLMIProblem` objects and then run exact rational PSD verification. The
last example demonstrates the intended failure mode for bilinear PSD entries.

JuMP/MOI extraction is a frontend path, not a trusted proof source. The verifier
trusts only the exact LMI data and certificate obligations replayed after
extraction.
