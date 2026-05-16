# CertSDP.jl

[![CI](https://github.com/fang251440/CertSDP.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/fang251440/CertSDP.jl/actions/workflows/ci.yml)
[![Docs](https://github.com/fang251440/CertSDP.jl/actions/workflows/docs.yml/badge.svg)](https://github.com/fang251440/CertSDP.jl/actions/workflows/docs.yml)
[![Validation](https://github.com/fang251440/CertSDP.jl/actions/workflows/validation.yml/badge.svg)](https://github.com/fang251440/CertSDP.jl/actions/workflows/validation.yml)
[![Julia 1.10+](https://img.shields.io/badge/Julia-1.10%2B-9558B2)](Project.toml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

**Exact replay for SDP and SOS certificates.**

CertSDP.jl is a research-grade verification layer for semidefinite programming
and sum-of-squares workflows. It turns solver candidates, Gram matrices, and
supported algebraic solutions into data-only JSON certificates that can be
replayed independently with exact rational or algebraic arithmetic.

```text
A solver finds a candidate. CertSDP makes it replayable.
```

CertSDP is not another large-scale SDP solver and not a replacement for MOSEK,
Clarabel, Hypatia, SCS, JuMP, or SumOfSquares.jl. It is the smaller trusted
layer after search: a certificate protocol plus a strict verifier for artifacts
that should survive review, archival, CI, and downstream proof pipelines.

## Why CertSDP Exists

A solver residual is not a proof, and a rounded Gram matrix is not a portable
certificate.

Numerical SDP/SOS workflows are powerful, but solver residuals and rounded Gram
matrices are not portable proofs. They can fail on exactly the cases that matter
for rigorous research: degenerate feasible points, rank-deficient PSD faces,
weak feasibility, and algebraic coordinates such as `sqrt(2)`.

CertSDP focuses on the transition from "the solver found something plausible"
to "this claim can be replayed exactly":

| Workflow state | Risk | CertSDP response |
| --- | --- | --- |
| Numerical output | Tolerance-based residuals can hide exact failure. | Treat as candidate data, not proof. |
| Rational rounding | Degenerate or algebraic solutions may not round to a valid rational point. | Certify over `QQ` or supported `QQ(alpha)` data. |
| Backend artifact | Logs, caches, and proof fields can be stale or solver-specific. | Recompute trusted obligations in strict replay. |

## At A Glance

| Question | Answer |
| --- | --- |
| Input | Exact rational LMI/SOS problem data plus rational, algebraic, SDPA, JuMP/MOI, or SOS Gram candidates. |
| Output | JSON certificates, structured failure reports, and replay bundles. |
| Trusted core | `verify --strict`, which recomputes hashes, exact substitution, signs, PSD proofs, and SOS coefficient matching. |
| Optional tools | `msolve`, Sage/msolve, Clarabel, JuMP/MOI, and SumOfSquares.jl can help find or extract candidates. |
| Evidence | A tracked validation report with accepted rows, rejection controls, rational-rounding failures, and imported workflows. |

## Where CertSDP Fits

| Tool class | Role |
| --- | --- |
| JuMP / MathOptInterface / SumOfSquares.jl / SOSTOOLS | Model or export SDP/SOS problems. |
| MOSEK / Clarabel / Hypatia / SCS | Find numerical candidates. |
| `msolve` / Sage | Optionally propose algebraic candidates. |
| CertSDP.jl | Verify exact replayable certificate artifacts. |

## Five-Minute Quickstart

Requirements: Julia 1.10 or newer and a checkout of this repository.

```bash
julia --project -e 'using Pkg; Pkg.instantiate()'

bin/certsdp certify examples/rational_problem.json \
  --solution examples/rational_solution.json \
  --out /tmp/certsdp-rational-cert.json

bin/certsdp verify --strict /tmp/certsdp-rational-cert.json
```

Expected verifier result:

```text
[OK] PSD verified over QQ
[OK] certificate accepted
```

The same path through the Julia API:

```julia
using CertSDP

P = read_problem("examples/rational_problem.json")
result = certify(P, [1 // 2, 1 // 3])

verify(result) || error("certificate rejected")
write_certificate("/tmp/certsdp-rational-cert.json", result)

replay = read_certificate("/tmp/certsdp-rational-cert.json")
verify(replay) || error("replay rejected")
```

The public API is intentionally small and versioned. See
[API stability](docs/API_STABILITY.md) before depending on internals.

## Strict Replay

`certify` may use numerical diagnostics, rank guesses, optional algebraic
backends, caches, and heuristic candidate selection. `verify --strict` does not
trust those inputs as proof.

Strict replay recomputes the accepted obligations from certificate data:

- canonical problem and certificate hashes;
- exact rational or supported algebraic reconstruction;
- exact LMI substitution and SOS coefficient matching;
- algebraic root isolation by rational intervals;
- certified signs and exact PSD proof replay.

| Trusted by strict replay | Not trusted as proof |
| --- | --- |
| v1.0 certificate data and canonical hashes | Solver success flags |
| Exact arithmetic in `QQ` or supported `QQ(alpha)` | Floating-point eigenvalues or residuals |
| Root isolation by rational intervals | Raw `msolve`, Sage, or solver logs |
| Exact substitution and coefficient matching | Cached backend artifacts |
| PSD proof replay by accepted exact methods | Approximate equalities or rounded diagnostics |

Design rule:

```text
The certifier may be complicated. The verifier must remain small, exact, and auditable.
```

## Supported Paths

CertSDP currently covers rational LMI certificates over `QQ`, supported
one-root algebraic certificates over `QQ(alpha)`, multi-block SDPA/JuMP-style
problems, exact SOS Gram certificates, rational-function SOS certificates, and
Putinar/Schmuedgen-style multiplier identities. Unsupported, malformed, or
not-certified cases return structured failures rather than acceptance.

Workflow support includes JSON schemas, SDPA import/export, replay bundles,
optional JuMP/MOI and SumOfSquares.jl extraction, and optional `msolve` or
Sage/msolve candidate generation. Optional numerical oracle: Clarabel can
provide approximate seeds and diagnostics.

| Path | Command |
| --- | --- |
| Rational LMI | `bin/certsdp certify examples/rational_problem.json --solution examples/rational_solution.json --out /tmp/certsdp-rational-cert.json` |
| Algebraic LMI | `bin/certsdp certify examples/algebraic_problem.json --solution examples/algebraic_approx.json --out /tmp/certsdp-algebraic-cert.json --timeout 300` |
| SOS Gram | `bin/certsdp certify-sos examples/sos/gram_x2_plus_1.json --solution examples/sos/gram_x2_plus_1_solution.json --out /tmp/certsdp-sos-cert.json` |
| Multi-block SDPA | `bin/certsdp certify examples/sdpa/two_blocks.dat-s --solution examples/multiblock/sdpa_two_blocks_solution.json --out /tmp/certsdp-two-blocks-cert.json` |

Verify any generated certificate with:

```bash
bin/certsdp verify --strict <certificate.json>
```

## Signature Demo: Rational Rounding Fails

The motivating failure mode is a numerically convincing SDP point that cannot be
turned into a valid bounded-denominator rational certificate.

For example, a rational LMI can force `x = sqrt(2)`. No rational value of `x` is
feasible, so rational rounding fails even when the floating-point approximation
is excellent. CertSDP can represent the accepted solution algebraically and then
replay the certificate exactly.

```bash
bin/certsdp certify examples/algebraic_problem.json \
  --solution examples/algebraic_approx.json \
  --out /tmp/certsdp-algebraic-cert.json \
  --timeout 300

bin/certsdp verify --strict /tmp/certsdp-algebraic-cert.json
```

`msolve` may help propose the algebraic candidate, but it is not part of the
trusted proof. Strict replay accepts only after root isolation, exact
substitution, certified signs, and PSD proof replay. See
[Why rational rounding fails](docs/why_rational_rounding_fails.md).

## Validation Evidence

CertSDP ships a public validation suite that is meant to be an evidence
contract, not a solver-speed leaderboard. The tracked v1.0 report records:

- 18 public validation instances;
- 15 / 15 accepted certificates passing strict replay;
- 3 expected rejection or structured-failure rows;
- 4 rational-rounding failures certified by exact algebraic replay;
- imported SDPA, JuMP/MOI, and SumOfSquares-style workflows;
- fake-certificate and invalid-approximation rejection controls.

Run the validation contract from the repository root:

```bash
bin/certsdp doctor
julia --project scripts/run_validation.jl
```

See [benchmarks/VALIDATION_REPORT.md](benchmarks/VALIDATION_REPORT.md) and
[docs/validation.md](docs/validation.md). Certified rows must pass strict
verification. Strict replay does not use `msolve`, numerical solver output,
backend logs, or solver-specific artifacts as proof.

## Showcases

The showcase pack contains data artifacts for recognizable positive-polynomial
certificate families. It is intended as a mathematical demo of the replay
protocol, not as a benchmark.

| Track | Examples |
| --- | --- |
| Non-SOS classics | Motzkin affine/homogeneous forms, Choi-Lam forms, and a Robinson-family SOS-threshold perturbation. |
| Hilbert 17 rational SOS | Explicit denominator SOS, numerator SOS, and exact `denominator * p == numerator` replay. |
| Putinar / Schmuedgen | Compact-domain inequalities on boxes, disks, intervals, simplex faces, and annuli. |
| SOSTOOLS bridge | Neutral SOSTOOLS-lite Gram exports converted into exact CertSDP certificates. |

Run or regenerate the pack:

```bash
julia --project showcases/verify_all.jl
julia --project scripts/generate_showcase_pack.jl
```

See [showcases/README.md](showcases/README.md) and
[showcases/manifest.json](showcases/manifest.json).

## Platform Support

Linux and macOS run the full package, docs, and validation checks in CI.
Windows runs strict verifier smoke and docs syntax smoke. The core verifier
should run anywhere Julia 1.10+ runs; optional backends depend on local
installation.

## Limits

CertSDP targets exact certification for supported small-to-medium audit and
reproducibility workflows. It is not:

- a generic large-scale SDP solver;
- a replacement for numerical SDP/SOS modeling and solver stacks;
- an infeasibility prover;
- a verifier for arbitrary floating-point model output without exact
  reconstruction;
- an automatic proof engine for every SDP/SOS hierarchy instance.

Current boundaries are documented in [API stability](docs/API_STABILITY.md),
[Certificate format](docs/certificate_format.md), and
[Validation](docs/validation.md). Core verification does not require `msolve`,
JuMP, SumOfSquares.jl, Clarabel, or Sage; optional backends are used around
candidate generation and workflow integration.

## Documentation

Start with:

- [Installation](docs/installation.md)
- [Platform support](docs/platform_support.md)
- [Quickstart](docs/quickstart.md)
- [LMI tutorial](docs/lmi_tutorial.md)
- [SOS tutorial](docs/sos_tutorial.md)
- [SDPA import/export](docs/sdpa_import.md)
- [JuMP / MOI integration](docs/jump_moi_integration.md)
- [Workflows](docs/workflows.md)
- [Trust model](docs/trust_model.md)
- [Validation](docs/validation.md)
- [Certificate format](docs/certificate_format.md)
- [API reference](docs/api_reference.md)

Build the local documentation site:

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

## Citation

The repository includes software citation metadata in `CITATION.cff` and
`codemeta.json`. It should not claim a registry entry or archived DOI until
those external services accept the artifact.

If CertSDP helps your research, cite this software and the paper that motivates
the degenerate SDP certification workflow:

```bibtex
@software{CertSDPjl,
  title   = {CertSDP.jl: Exact replay for SDP and SOS certificates},
  author  = {{CertSDP contributors}},
  year    = {2026},
  version = {1.0.0},
  note    = {Software package}
}
```

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
