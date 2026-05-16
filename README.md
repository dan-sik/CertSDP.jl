# CertSDP.jl

[![CI](https://github.com/fang251440/CertSDP.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/fang251440/CertSDP.jl/actions/workflows/ci.yml)
[![Docs](https://github.com/fang251440/CertSDP.jl/actions/workflows/docs.yml/badge.svg)](https://github.com/fang251440/CertSDP.jl/actions/workflows/docs.yml)
[![Validation](https://github.com/fang251440/CertSDP.jl/actions/workflows/validation.yml/badge.svg)](https://github.com/fang251440/CertSDP.jl/actions/workflows/validation.yml)
[![Julia 1.10+](https://img.shields.io/badge/Julia-1.10%2B-9558B2)](Project.toml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

**Exact replay for numerical SDP/SOS certificates.**

CertSDP.jl turns SDP/SOS solver candidates into data-only JSON certificates
that can be independently verified with exact arithmetic.

Numerical solvers are excellent at finding candidates. CertSDP sits after the
solver and asks a narrower question:

```text
Can this SDP/SOS claim be replayed exactly?
```

The strict verifier recomputes the trusted obligations: problem hashes, exact
LMI substitution, rational or algebraic arithmetic, certified sign tests, PSD
proof replay, and SOS coefficient matching. Solver logs, backend artifacts,
floating-point eigenvalues, and approximate equalities are diagnostics, not
proof.

> A solver finds a candidate. CertSDP makes it replayable.

## Why CertSDP Exists

A solver residual is not a proof.

Many SDP/SOS workflows begin numerically: JuMP or SumOfSquares.jl builds a
model, a solver finds a feasible-looking point or Gram matrix, and the result is
then used inside a paper, proof, or reproducibility artifact. Rational rounding
can fail when the true solution is degenerate, rank-deficient, lies on a PSD
face, or has algebraic coordinates such as `sqrt(2)`.

CertSDP is not another large-scale SDP solver. It is the exact verification
layer after one.

## Where CertSDP Fits

| Tool | Role |
| --- | --- |
| JuMP / MathOptInterface | Model optimization problems |
| SumOfSquares.jl | Build SOS and Gram SDP formulations |
| MOSEK / Clarabel / Hypatia / SCS | Find numerical SDP or conic candidates |
| `msolve` / Sage | Optionally propose algebraic candidates |
| CertSDP.jl | Verify exact SDP/SOS certificate artifacts |

Use CertSDP when a numerical or symbolic workflow has produced something worth
making rigorous: a candidate point, a rank profile, a Gram matrix, or an exact
problem export that should become a replayable artifact.

## What It Supports

- Rational LMI certificates over `QQ`.
- Algebraic one-root LMI certificates over `QQ(alpha)`, including multi-block
  SDPA/JuMP-style problems with shared variables.
- Principal-minor, Schur-zero, fraction-free determinant, LDL, pivoted-LDL, and
  blockwise PSD proof replay.
- Exact SOS Gram certificates with coefficient matching and JSON/text/LaTeX/
  Sage/Julia decomposition export.
- Positive-polynomial certificate schemas for rational-function SOS and
  Putinar/Schmüdgen-style SOS multiplier identities.
- SDPA sparse import/export.
- Optional JuMP/MOI and SumOfSquares.jl extraction.
- Optional `msolve` and Sage/msolve algebraic candidate generation.
- Structured failure reports for unsupported, malformed, or not-certified
  cases.
- Strict verifier mode for independent replay.

## Five-Minute Quickstart

Requirements: Julia 1.10 or newer and a checkout of this repository.

```bash
julia --project -e 'using Pkg; Pkg.instantiate()'

bin/certsdp certify examples/rational_problem.json \
  --solution examples/rational_solution.json \
  --out /tmp/certsdp-rational-cert.json

bin/certsdp verify --strict /tmp/certsdp-rational-cert.json
```

The verifier should end with:

```text
[OK] PSD verified over QQ
[OK] certificate accepted
```

This path uses only exact rational data and no optional backend.

## Signature Demo: When Rational Rounding Fails

The sharpest motivating case is an SDP candidate that looks numerically right
but cannot be converted into a valid bounded-denominator rational certificate.

When `msolve` is available:

```bash
bin/certsdp certify examples/algebraic_problem.json \
  --solution examples/algebraic_approx.json \
  --out /tmp/certsdp-algebraic-cert.json \
  --timeout 300

bin/certsdp verify --strict /tmp/certsdp-algebraic-cert.json
```

`msolve` is not trusted as proof. It only helps propose a candidate. Strict
verification accepts the certificate only after root isolation, exact
substitution, certified signs, and PSD proof replay.

## Showcases: Small Mathematical Replays

The validation suite is the evidence contract. The showcases are different:
they are compact, inspectable demos meant to show what exact replay looks like
on recognizable polynomial certificates. They live under `showcases/` and are
not counted in the validation table below.

| Showcase | What to look for |
| --- | --- |
| Motzkin rational-function SOS | A nonnegative polynomial outside plain SOS, accepted through an exact rational-function SOS identity. |
| Hilbert 17-style rational SOS | The same rational-function certificate shape in a tiny one-variable artifact. |
| Putinar/Schmuedgen-style assembly | SOS multipliers attached to named constraints on a box. |
| SOSTOOLS-lite replay | A neutral external Gram shape converted into a CertSDP certificate and then replayed. |

Run the prebuilt showcase certificates:

```bash
bin/certsdp verify --strict showcases/motzkin/motzkin_rational_function_sos.json
bin/certsdp verify --strict showcases/hilbert17/x2_plus_1_rational_function_sos.json
bin/certsdp verify --strict showcases/putinar/box_1_minus_x2y2.json
bin/certsdp verify --strict showcases/sostools/xy_square_cert.json
```

See [showcases/README.md](showcases/README.md) for the identities and the
SOSTOOLS-lite conversion command.

## Current Validation Snapshot

CertSDP ships one public validation suite. It is a reproducible evidence
contract, not a showcase gallery and not a solver-speed leaderboard.
The rows below count fixtures under `benchmarks/validation/`.

Current `v1.0` tracked report:

| Evidence | Current result |
| --- | ---: |
| Public validation instances | 18 |
| Suite status | passed |
| Strict-verified certified rows | 15 |
| Actual rational-rounding failures certified | 4 |
| Solve -> diagnose -> certify workflows passed | 1 |
| Strict verifier timing | total 7.5194s, max 2.5881s, min 0.0013s |
| Certificate sizes | 15 certificates, total 2480.93 KiB, max 1314.53 KiB |

Run the validation contract from the repository root:

```bash
bin/certsdp doctor
julia --project scripts/run_validation.jl
```

The tracked report is
[benchmarks/VALIDATION_REPORT.md](benchmarks/VALIDATION_REPORT.md). Certified
rows must pass strict verification. Strict verification is exact replay only:
it does not use `msolve`, numerical solver output, backend logs, or
solver-specific artifacts.

## Platform Support

| Environment | Current support |
| --- | --- |
| Linux | Full package tests, validation, docs, and formatting in CI. |
| macOS | Full package tests, validation, and docs in CI. |
| Windows | Strict verifier smoke and docs syntax smoke in CI. |
| HPC / other machines | Core verifier should run anywhere Julia 1.10+ runs; optional backends depend on local installation. |

Core verification does not require `msolve`, JuMP, SumOfSquares.jl, Clarabel, or
Sage. See [Platform support](docs/platform_support.md) and
[Installation](docs/installation.md).

Optional components are used only around candidate generation and workflow
integration:

- Optional algebraic backend: `msolve` or Sage/msolve.
- Optional numerical oracle: Clarabel for approximate seeds and diagnostics.

## Common Paths

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

## Replayable Artifacts

Certificates can be packaged for independent replay:

```bash
bin/certsdp bundle /tmp/certsdp-rational-cert.json --out /tmp/certsdp-artifact.zip
bin/certsdp replay /tmp/certsdp-artifact.zip
```

Bundles include certificate data, version metadata, a strict verification
report, and optional problem, approximation, and backend log files. `replay`
ignores sidecar logs and reruns strict exact verification on the bundled
certificate.

## Trust Boundary

`certify` may use numerical diagnostics, rank guesses, external algebraic
backends, caches, and heuristic candidate selection.

`verify --strict` does not trust those claims.

The strict verifier requires schema v1.0 certificate data and rejects
approximate, backend-dependent, stale-hash, malformed, or fake proof fields
before exact acceptance. It recomputes the facts that matter:

- canonical problem hashes;
- certificate hashes;
- exact solution reconstruction;
- exact LMI substitution;
- algebraic root isolation by rational intervals;
- exact arithmetic in `QQ` or `QQ(alpha)`;
- certified algebraic signs;
- PSD proof data by principal minors, Schur-zero, LDL, pivoted LDL, or
  blockwise replay;
- exact SOS coefficient matching.

This is the central design rule:

> The certifier may be complicated. The verifier must remain small, exact, and
> auditable.

## Limitations

CertSDP currently targets exact certification for supported small-to-medium
audit and reproducibility workflows, not arbitrary SDP solving.

CertSDP is not:

- a generic large-scale SDP solver;
- a replacement for MOSEK, Clarabel, Hypatia, SCS, JuMP, or SumOfSquares.jl;
- an infeasibility prover;
- a tool that accepts floating-point eigenvalues as proof;
- an automatic proof engine for every SDP/SOS model.

Current boundaries are documented in [API stability](docs/API_STABILITY.md),
[Certificate format](docs/certificate_format.md), and
[Validation](docs/validation.md). In particular, algebraic certificates use the
supported one-root representation, JuMP/MOI and SumOfSquares paths cover
specific exported workflows, and unsupported systems should return structured
failure reports rather than acceptance.

## Documentation

Start here:

- [Installation](docs/installation.md)
- [Platform support](docs/platform_support.md)
- [Quickstart](docs/quickstart.md)
- [LMI tutorial](docs/lmi_tutorial.md)
- [SOS tutorial](docs/sos_tutorial.md)
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
Ignored local third-party materials under `references/` keep their own terms; see
[NOTICE.md](NOTICE.md).
