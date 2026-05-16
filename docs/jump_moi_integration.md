# JuMP / MathOptInterface Integration

CertSDP can extract exact affine PSD constraints from JuMP and MOI models when
the optional extension packages are loaded.

## Minimal JuMP Example

```julia
using CertSDP
using JuMP

model = GenericModel{Rational{BigInt}}()
@variable(model, x)
@variable(model, y)
@constraint(model, [1 + x y; y 2 - x] in PSDCone())

problem = CertSDP.extract_lmi(model)
cert = CertSDP.RationalCertificate(problem, [0//1, 0//1])
verify(cert)
```

The optional extraction helpers and concrete certificate constructors are
module-qualified because they are outside the stable public API contract. They
remain available for the extension workflow, while the stable entry points are
listed in [API_STABILITY.md](API_STABILITY.md).

Use `GenericModel{Rational{BigInt}}()` for exact research workflows. Finite
floating-point coefficients are converted to their exact binary rational values;
they are not interpreted as decimal approximations.

## Supported Constraints

The extractor supports affine PSD cone constraints:

- `Vector{AffExpr}` in `MOI.PositiveSemidefiniteConeSquare`;
- `Vector{AffExpr}` in `MOI.PositiveSemidefiniteConeTriangle`;
- PSD matrix-variable constraints represented as `Vector{VariableRef}`;
- MOI `VectorAffineFunction` and `VectorOfVariables` PSD constraints.

One PSD constraint returns an `LMIProblem`. Multiple PSD constraints return a
`BlockLMIProblem` with shared CertSDP variables.

## Provenance

Extraction metadata records variable mapping, constraint mapping, cone shape,
and bridge provenance when available. This is useful for debugging and
reproducibility, but the verifier still trusts only the extracted exact LMI and
the exact certificate replay.

## Unsupported Models

Unsupported input raises `ArgumentError` rather than being silently skipped:

- nonlinear constraints or objectives;
- bilinear or quadratic PSD entries such as `x * y`;
- non-PSD constraints mixed into the model;
- asymmetric square PSD matrices.

Certifying a silently truncated model would certify the wrong mathematical
problem, so the extractor fails loudly.

## Runnable Examples

The examples use their own project:

```bash
julia --project=examples/jump -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=examples/jump examples/jump/affine_square_psd.jl
julia --project=examples/jump examples/jump/multiple_psd_blocks.jl
julia --project=examples/jump examples/jump/psd_variable.jl
```

`examples/jump/unsupported_bilinear.jl` demonstrates an expected extraction
failure for unsupported bilinear input.
