<div align="center">

# CertSDP.jl

[![CI](https://github.com/dan-sik/CertSDP.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/dan-sik/CertSDP.jl/actions/workflows/ci.yml)
[![Docs](https://github.com/dan-sik/CertSDP.jl/actions/workflows/docs.yml/badge.svg)](https://github.com/dan-sik/CertSDP.jl/actions/workflows/docs.yml)
[![Validation](https://github.com/dan-sik/CertSDP.jl/actions/workflows/validation.yml/badge.svg)](https://github.com/dan-sik/CertSDP.jl/actions/workflows/validation.yml)
[![Julia 1.10+](https://img.shields.io/badge/Julia-1.10%2B-9558B2)](Project.toml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

**Exact replay for numerical SDP/SOS certificates.**

</div>

CertSDP.jl is a post-solver Julia certificate layer for SDP/SOS research workflows. It
does not replace JuMP, SumOfSquares.jl, MOSEK, Clarabel, Hypatia, SCS, SDPA,
`msolve`, Sage, RealCertify, NCTSSOS, or ClusteredLowRankSolver.jl. Those tools
can search for candidates; CertSDP turns accepted candidates into data-only
JSON certificates that can be replayed with exact rational or supported
algebraic arithmetic.

It is **not another large-scale SDP solver**. It is the replay boundary after
search.

```text
A solver finds a candidate. CertSDP makes it replayable.
```

Use CertSDP when a numerical SDP/SOS result, Gram matrix, imported SDPA model,
or algebraic candidate needs to survive review, CI, archival, or a downstream
formal-proof pipeline.

## Why CertSDP Exists

A solver residual is not a proof. Rounded Gram matrices and backend logs are
useful search evidence, but they are not portable proof objects. CertSDP
answers the next question: can the SDP/SOS claim be replayed exactly without
trusting the original run?

The practical failure mode is rational rounding. Degenerate or algebraic SDP
points can be numerically clear while no bounded-denominator rational point
exists at the required face. CertSDP can certify supported `QQ(alpha)` data
instead of pretending the rounded rational candidate is proof.

## Where CertSDP Fits

| Tool class | Role |
| --- | --- |
| JuMP, MathOptInterface, SumOfSquares.jl, SOSTOOLS, SDPA | Model or export exact SDP/SOS data. |
| MOSEK, Clarabel, Hypatia, SCS, `msolve`, Sage | Search for numerical or algebraic candidates. |
| RealCertify, NCTSSOS, ClusteredLowRankSolver.jl, CertifiedQuantumBounds | Provide external exact-certificate ecosystems that can be translated. |
| CertSDP.jl | Recompute exact proof obligations and emit replayable v1.0 artifacts. |

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

## Five-Minute Quickstart

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
| Replay an existing certificate | `bin/certsdp verify --strict cert.json` |
| Certify rational LMI data | `certify(problem, rational_vector)` |
| Certify an algebraic LMI candidate | `bin/certsdp certify problem.json --solution approx.json --timeout 300` |
| Certify exact SOS Gram data | `bin/certsdp certify-sos problem.json --solution gram.json --out cert.json` |
| Repair an approximate SOS Gram candidate | `bin/certsdp certify-auto-sos problem.json --solution gram.json --tolerance 1e-12` |
| Import SDPA sparse block SDP data | `read_problem("case.dat-s")` |
| Package a replay artifact | `bin/certsdp bundle cert.json --out artifact.zip` |
| Run the validation contract | `bin/certsdp doctor && julia --project scripts/run_validation.jl` |

Optional tools can help construct candidates. They are not required to replay a
strict certificate.

Optional numerical oracle: Clarabel can provide approximate seeds and
diagnostics for solve-diagnose-certify examples, but it is never part of the
trusted proof.

## What Acceptance Means

`certify` may use numerical diagnostics, rank guesses, optional algebraic
backends, caches, and exactification strategies. `verify --strict` accepts only
after recomputing the trusted obligations from certificate data:

- canonical problem and certificate hashes;
- exact rational or supported `QQ(alpha)` reconstruction;
- exact LMI substitution or SOS coefficient matching;
- algebraic root isolation and certified signs;
- PSD replay by accepted exact proof methods;
- positive-polynomial, perturbation, or relation-reduction identities when the
  certificate family requires them.

Not trusted as proof: solver status, residuals, approximate eigenvalues, rank
guesses, backend logs, session transcripts, cached artifacts, or provenance
claims.

## Certificate Families

Current replay support covers:

- rational and block rational LMI certificates over `QQ`;
- one-root algebraic and block algebraic LMI certificates over supported
  `QQ(alpha)` data;
- exact SOS Gram certificates, including round-and-project exactification for
  approximate Gram candidates;
- algebraic SOS Gram replay over an explicit one-root number field;
- rational-function SOS, Positivstellensatz, and perturbation/compensation SOS
  identity certificates;
- noncommutative SOS word-identity replay and relation-reduction groundwork;
- external replay artifacts for RealCertify, NCTSSOS,
  ClusteredLowRankSolver.jl, and CertifiedQuantumBounds translations.

The public v1 compatibility boundary is intentionally small. See
[API stability](docs/API_STABILITY.md) and
[Certificate format](docs/certificate_format.md) before depending on internal
types.

## Evidence

The tracked validation report is the release evidence contract, not a
performance leaderboard. It includes strict replay rows, rational-rounding
failure rows, SDPA/JuMP/SumOfSquares-style imports, solve-diagnose-certify
coverage, and fake-certificate rejection controls.

```bash
bin/certsdp doctor
julia --project scripts/run_validation.jl
```

See [benchmarks/VALIDATION_REPORT.md](benchmarks/VALIDATION_REPORT.md) and
[docs/validation.md](docs/validation.md).

### Current Validation Snapshot

Current validation covers rational and algebraic LMI replay, multi-block SDPA
data, exact SOS Gram replay, solve-diagnose-certify workflows, fake-certificate
rejection, and hard-gate tests for adapter, artifact, algebraic SOS,
noncommutative, and perturbation paths.

## Signature Demo

The minimal algebraic demo certifies a rational LMI whose accepted point is
`x = sqrt(2)`. Rational rounding fails, but exact algebraic replay succeeds:

```bash
bin/certsdp certify examples/algebraic_problem.json \
  --solution examples/algebraic_approx.json \
  --out /tmp/certsdp-algebraic-cert.json \
  --timeout 300

bin/certsdp verify --strict /tmp/certsdp-algebraic-cert.json
```

## Showcases

The showcase pack contains exact positive-polynomial artifacts for
rational-function SOS, Putinar/Schmuedgen-style identities,
perturbation/compensation replay, and SOSTOOLS-lite Gram conversion:

```bash
julia --project showcases/verify_all.jl
```

## Platform Support

Linux and macOS run the full package, docs, and validation checks in CI.
Windows has verifier-oriented smoke coverage. The core strict verifier should
run anywhere Julia 1.10+ runs; optional candidate-generation tools depend on
local installation.

## Documentation

Start here:

- [Installation](docs/installation.md)
- [Quickstart](docs/quickstart.md)
- [Workflows](docs/workflows.md)
- [Trust model](docs/trust_model.md)
- [Validation](docs/validation.md)
- [Certificate format](docs/certificate_format.md)
- [API reference](docs/api_reference.md)
- [Roadmap hard gates](docs/ROADMAP_HARD_GATES.md)

Build docs locally:

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

## Limitations

CertSDP is not a generic large-scale SDP solver, not an infeasibility prover,
and not a guarantee that every numerical SDP/SOS result can be certified.
Rejection means no supported exact certificate was accepted; it is not
automatically a proof of mathematical infeasibility.

## Citation

```bibtex
@software{CertSDPjl,
  title   = {CertSDP.jl: Exact replay for SDP and SOS certificates},
  author  = {{CertSDP contributors}},
  year    = {2026},
  version = {1.0.0},
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
