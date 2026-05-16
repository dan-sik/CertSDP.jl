# Installation

CertSDP currently targets Julia 1.10 or newer.

For operating-system coverage, optional backend caveats, and the Windows
verifier-only CI boundary, see [Platform support](platform_support.md).

## Choose A Path

| Goal | Recommended path |
| --- | --- |
| Run the CLI examples in this repository | Use the repository checkout and `bin/certsdp`. |
| Depend on CertSDP from another Julia project before registry release | Use `Pkg.develop(url=...)` or `Pkg.develop(path=...)`. |
| Replay an existing certificate | Install only the core Julia package; optional solvers are not needed. |
| Generate algebraic candidates | Add an external `msolve` or Sage/msolve executable. |
| Run frontend extraction examples | Use the optional JuMP/MOI or SumOfSquares project environments. |

## Repository CLI Path

From a clean checkout:

```bash
julia --project -e 'using Pkg; Pkg.instantiate()'
bin/certsdp version
```

The `bin/certsdp` wrapper runs the package in the repository project. Use it for
all CLI examples in these docs.

## Julia Dependency Path

Until a Julia General registry release exists, downstream Julia environments
should depend on the repository URL or a local checkout:

```bash
julia -e 'using Pkg; Pkg.develop(url="https://github.com/fang251440/CertSDP.jl")'
# or, from a local clone:
julia -e 'using Pkg; Pkg.develop(path="/absolute/path/to/CertSDP")'
```

The local `references/` directory is ignored research context for developers
who keep papers, manuals, or external upstream repositories beside the source
tree. It is not part of the package checkout and is not required for
installation, strict verification, docs, or the validation suite. Fetch papers
or external implementations separately when you need to audit them.

## Verify The Core Environment

Run a verifier-only smoke test:

```bash
bin/certsdp certify examples/rational_problem.json \
  --solution examples/rational_solution.json \
  --out /tmp/certsdp-rational-cert.json
bin/certsdp verify --strict /tmp/certsdp-rational-cert.json
```

This path requires no optional backend.

## Optional Algebraic Backend

Algebraic candidate generation uses `msolve` as an external executable. It is
optional and is never part of the trusted verifier.

On macOS:

```bash
brew install msolve
```

Or point CertSDP to an executable:

```bash
export CERTSDP_MSOLVE=/absolute/path/to/msolve
```

You can also pass `--msolve /absolute/path/to/msolve` to `certsdp certify`.

If Sage is installed, the Sage/msolve adapter can be selected with
`--algebraic-backend sage_msolve --sage /absolute/path/to/sage`. This is an
optional candidate-generation path; verification remains solver-free.

## Optional Julia Frontends

JuMP/MOI and SumOfSquares integration are Julia extension paths. Core CertSDP
verification does not depend on them.

The runnable JuMP examples use their own project:

```bash
julia --project=examples/jump -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=examples/jump examples/jump/affine_square_psd.jl
```

If you only need JSON, SDPA, or exported SOS Gram certificates, you do not need
the optional frontend packages.

## Optional Numerical Solver

`solve_approximately` and `certsdp solve` can use Clarabel as an optional
numerical oracle. Clarabel is a Julia weak dependency, so loading CertSDP for
exact verification does not load or require it. Add it only in environments
that need solve or solve-certify workflows:

```bash
julia --project -e 'using Pkg; Pkg.add("Clarabel")'
```

## Build Documentation

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

The generated HTML is written to `docs/build/`. The build uses Documenter.jl,
including the public API reference and doctest snippets.
