# API Reference

The public API is intentionally small. Numerical solvers and algebraic
backends may help construct candidates, but the replay APIs below remain the
independent verification contract.

```@meta
CurrentModule = CertSDP
DocTestSetup = quote
    using CertSDP
end
```

## Quick Doctest

```jldoctest
julia> using CertSDP

julia> P = LMIProblem([1 0; 0 1],
           [[1 0; 0 0],
            [0 0; 0 1]];
           vars=[:x, :y]);

julia> result = certify(P, [1//2, 1//3]);

julia> verify(result)
true
```

## Result Contract

`certify` and `certify_sos` return a result wrapper. Success behaves like a
certificate for the public replay APIs; failure behaves like structured
diagnostic data:

```julia
result = certify(P, [1//2, 1//3])

if verify(result)
    write_certificate("cert.json", result)
else
    diagnose(result)
end
```

The concrete wrapper types are available as `CertSDP.CertifiedResult` and
`CertSDP.FailureResult`, but they are intentionally not exported. Public code
should branch with `verify(result)`, write accepted results with
`write_certificate`, and inspect failures with `diagnose`.

## Workflow Map

| Task | Public entry point | Replay entry point |
| --- | --- | --- |
| Exact rational LMI | `certify(problem, rational_vector)` | `verify(result)` or `verify(read_certificate(path))` |
| Algebraic LMI from approximate seed | `certify(problem, approx; algebraic_backend=:msolve)` | `verify(result)` |
| SDPA or block LMI | `read_problem(path)` then `certify` | `verify --strict` through CLI or `verify` in Julia |
| SOS Gram data | `certify_sos(problem_or_path, gram)` | `verify_sos(result)` |
| Approximate SOS Gram data | `certify_auto_sos(problem, gram; tolerance=...)` | `verify_sos(result)` or `verify --strict` after writing |
| Failure diagnostics | `diagnose(result_or_failure)` | `bin/certsdp explain failure.json` for saved reports |
| Replayable artifact | `write_certificate(path, result)` | `bin/certsdp bundle` and `bin/certsdp replay` |

For diagrams and CLI/JuMP/SOS comparisons, see [Workflows](workflows.md).

## Core Problems

```@docs
LMIProblem
BlockLMIProblem
read_problem
write_problem
```

## Certification And Replay

```@docs
certify
verify
diagnose
read_certificate
write_certificate
```

## SOS Workflow

```@docs
certify_sos
verify_sos
certify_auto_sos
export_sos_decomposition
sos_decomposition_text
sos_decomposition_latex
sos_decomposition_sage
sos_decomposition_julia
```

`certify_auto_sos` is documented for practical use but remains an experimental
exactification API in the v1 line. The accepted certificate is still ordinary
strictly replayed SOS data.

## Public Index

```@index
Pages = ["api_reference.md"]
```
