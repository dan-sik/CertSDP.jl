<div align="center">

# CertSDP.jl

[![CI](https://github.com/dan-sik/CertSDP.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/dan-sik/CertSDP.jl/actions/workflows/ci.yml)
[![Docs](https://github.com/dan-sik/CertSDP.jl/actions/workflows/docs.yml/badge.svg)](https://github.com/dan-sik/CertSDP.jl/actions/workflows/docs.yml)
[![Validation](https://github.com/dan-sik/CertSDP.jl/actions/workflows/validation.yml/badge.svg)](https://github.com/dan-sik/CertSDP.jl/actions/workflows/validation.yml)
[![Julia 1.10+](https://img.shields.io/badge/Julia-1.10%2B-9558B2)](Project.toml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

**Exact certificates for SDP/SOS results, from numerical evidence to replayable proof artifacts.**

</div>

CertSDP.jl turns semidefinite-programming and sum-of-squares results into
portable proof-carrying artifacts. It is built for the moment after a solver,
sparse SOS hierarchy, noncommutative relaxation, symmetry reduction, or
algebraic reconstruction has produced a promising certificate candidate, and
the result now needs to be checked, minimized, archived, and shared.

The core promise is simple:

```text
candidate evidence in, exact replayable certificate out
```

Accepted certificates are data-only JSON artifacts. They can be verified with
exact rational or algebraic arithmetic, without rerunning the original solver
and without trusting floating-point residuals.

## Why It Exists

Numerical SDP/SOS workflows can produce excellent evidence, but papers,
archives, CI systems, and formal-methods pipelines need something more durable
than a solver log. CertSDP supplies that missing layer: a certificate compiler
that reconstructs exact arithmetic, preserves the structure of the original
problem, and gives reviewers a concrete artifact to replay.

Use it when your result depends on any of these fragile handoff points:

- rational rounding near a degenerate or boundary solution;
- Gram or slack matrices with low numerical rank;
- sparse SOS certificates where dense expansion would destroy the evidence;
- symmetry-reduced or block-diagonal SDP certificates;
- noncommutative, trace, or quotient-polynomial identities;
- primal, dual, objective-gap, or infeasibility certificates that need exact
  affine and PSD replay.

## What CertSDP Produces

A CertSDP artifact contains the ingredients an expert expects to audit:

- exact problem and basis data;
- selected arithmetic field and reconstruction metadata;
- sparsity, block, symmetry, and quotient structure;
- certificate blocks, factors, affine identities, and PSD proof data;
- minimization log, verification plan, diagnostics, and hashes.

Strict verification recomputes the trusted obligations from that data. Solver
status, residuals, approximate eigenvalues, backend logs, and provenance notes
are useful context, not proof.

## Install

From a checkout:

```bash
julia --project -e 'using Pkg; Pkg.instantiate()'
bin/certsdp version
```

From another Julia project before registry release:

```julia
using Pkg
Pkg.develop(url="https://github.com/dan-sik/CertSDP.jl")
```

## Quickstart

Create and replay a small exact rational certificate:

```bash
bin/certsdp certify examples/rational_problem.json \
  --solution examples/rational_solution.json \
  --out /tmp/certsdp-rational-cert.json

bin/certsdp verify --strict /tmp/certsdp-rational-cert.json
```

Expected ending:

```text
[OK] PSD verified over QQ
[OK] certificate accepted
```

The same workflow in Julia:

```julia
using CertSDP

P = read_problem("examples/rational_problem.json")
result = certify(P, [1 // 2, 1 // 3])

verify(result) || error("certificate rejected")
write_certificate("/tmp/certsdp-rational-cert.json", result)
```

## Common Workflows

| Goal | Command or API |
| --- | --- |
| Replay a certificate | `bin/certsdp verify --strict cert.json` |
| Replay a proof artifact | `bin/certsdp replay artifact.json --no-network --no-solver` |
| Explain a certificate or failure | `bin/certsdp explain artifact.json` |
| Minimize a proof artifact | `bin/certsdp minimize raw.json --out minimized.json` |
| Certify rational LMI data | `certify(problem, rational_vector)` |
| Certify an algebraic LMI candidate | `bin/certsdp certify problem.json --solution approx.json --timeout 300` |
| Certify exact SOS Gram data | `bin/certsdp certify-sos problem.json --solution gram.json --out cert.json` |
| Repair an approximate SOS Gram candidate | `bin/certsdp certify-auto-sos problem.json --solution gram.json --tolerance 1e-12` |
| Import SDPA sparse block SDP data | `read_problem("case.dat-s")` |
| Package a replay bundle | `bin/certsdp bundle cert.json --out artifact.zip` |
| Run reproducibility checks | `bin/certsdp doctor && julia --project scripts/run_validation.jl` |

Optional solvers and algebraic backends help construct candidates. They are not
part of strict replay.

## Capabilities

| Area | What is checked |
| --- | --- |
| Field reconstruction | Rational, quadratic, multiquadratic, cyclotomic, and low-degree algebraic fields with minimality diagnostics. |
| Facial structure | Numerical rank, exact kernels, low-rank factors, and PSD replay in the recovered face. |
| Sparse SOS | Clique, block, term-sparsity, localizing, and sparse coefficient-map structure. |
| Symmetry and low rank | Reduced affine identities, block transforms, original-dimension metadata, and exact low-rank PSD factors. |
| Noncommutative trace | Star involution, cyclic trace canonicalization, projector relations, completeness, orthogonality, and commutation quotients. |
| Infeasibility | Exact Farkas-style affine contradictions with PSD slack verification. |
| Minimization | Exact-safe reduction of field degree, rank, redundant blocks, coefficient height, basis size, and JSON size. |
| External artifacts | Normalization paths for SumOfSquares-like, TSSOS-like, NCTSSOS-like, and clustered-low-rank-like outputs. |

## Validation

The validation suite is a reproducibility contract for the public claims above.
It checks exact acceptance, expected rejection, import normalization,
minimization equivalence, and solver-free replay.

```bash
bin/certsdp doctor
julia --project scripts/run_validation.jl
```

See [benchmarks/VALIDATION_REPORT.md](benchmarks/VALIDATION_REPORT.md) and
[docs/validation.md](docs/validation.md).

## Ecosystem Fit

CertSDP complements specialized search and modeling tools:

| Ecosystem | CertSDP role |
| --- | --- |
| JuMP, MathOptInterface, SumOfSquares.jl, SOSTOOLS, SDPA | Read or translate exact problem and Gram data. |
| MOSEK, Clarabel, Hypatia, SCS, Sage, `msolve` | Provide candidate data or algebraic reconstruction support. |
| RealCertify-style rational SOS | Import exact identities and replay them in the common artifact format. |
| TSSOS / CS-TSSOS-style sparse hierarchies | Preserve correlative and term sparsity during certificate replay. |
| NCTSSOS-style noncommutative workflows | Replay word, trace, and quotient identities exactly. |
| Clustered low-rank workflows | Reconstruct low-rank algebraic factors and verify reduced SDP blocks. |

## Documentation

Start here:

- [Installation](docs/installation.md)
- [Quickstart](docs/quickstart.md)
- [Workflows](docs/workflows.md)
- [Trust model](docs/trust_model.md)
- [Validation](docs/validation.md)
- [Certificate format](docs/certificate_format.md)
- [API stability](docs/API_STABILITY.md)
- [Assurance model](docs/assurance_model.md)

Build docs locally:

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

## Platform Support

Core strict replay targets Julia 1.10+ and is exercised on Linux and macOS in
the full validation workflow. Windows support is verifier-oriented. Optional
solver, frontend, and algebraic backend integrations depend on the local
installation of those tools.

## Boundaries

CertSDP verifies certificates; it does not replace numerical solver stacks. A
rejection means the supplied data did not produce a supported exact proof
artifact. A mathematical nonexistence claim requires an explicit infeasibility
certificate, not merely failure to certify.

## Citation

```bibtex
@software{CertSDPjl,
  title   = {CertSDP.jl: Exact certificate compiler for SDP and SOS artifacts},
  author  = {{CertSDP contributors}},
  year    = {2026},
  version = {2.1.0},
  note    = {Software package}
}
```

The degenerate SDP certification workflow is motivated by:

```bibtex
@article{KolmogorovNaldiZapata2025DegenerateSDP,
  author  = {Kolmogorov, Vladimir and Naldi, Simone and Zapata, Jeferson},
  title   = {Certifying Solutions of Degenerate Semidefinite Programs},
  journal = {SIAM Journal on Optimization},
  volume  = {35},
  number  = {3},
  pages   = {1630--1654},
  year    = {2025},
  doi     = {10.1137/24M1664691}
}
```

## License

CertSDP.jl is released under the Apache License 2.0. See [LICENSE](LICENSE).
Ignored local third-party materials under `references/` keep their own terms;
see [NOTICE.md](NOTICE.md).
