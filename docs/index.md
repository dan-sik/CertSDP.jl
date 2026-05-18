# CertSDP Documentation

CertSDP.jl is a post-solver exact replay layer for SDP/SOS research
workflows. It turns exact problem data plus candidate solutions into data-only
JSON certificates that can be replayed independently with rational or
supported algebraic arithmetic.

CertSDP is not a numerical SDP solver. It is the smaller verification layer
used after modeling, solving, algebraic reconstruction, or SOS extraction.

```text
A solver finds a candidate. CertSDP makes the claim replayable.
```

## Practical Entry Points

## Core Claim

Numerical and symbolic tools are good at finding candidates. CertSDP's job is
to make the accepted claim replayable: exact hashes, exact substitution,
certified signs, coefficient matching, and PSD obligations are recomputed from
certificate data.

## At A Glance

| Need | Start here |
| --- | --- |
| Fresh checkout | [Installation](installation.md), then [Quickstart](quickstart.md). |
| Replay a certificate | `bin/certsdp verify --strict cert.json`. |
| Certify rational or algebraic LMI data | [LMI tutorial](lmi_tutorial.md) and [Backends](backends.md). |
| Certify Gram/SOS data | [SumOfSquares tutorial](sos_tutorial.md). |
| Connect SDPA, JuMP/MOI, or imported artifacts | [SDPA import](sdpa_import.md), [JuMP/MOI integration](jump_moi_integration.md), and [Workflows](workflows.md). |
| Understand the trust boundary | [Trust model](trust_model.md), [Certificate format](certificate_format.md), and [Schema v1](SCHEMA_V1.md). |
| Check release evidence | [Validation](validation.md), [Benchmarks](benchmarks.md), and [Roadmap hard gates](ROADMAP_HARD_GATES.md). |

## What Is Trusted

`certify` can use numerical diagnostics, rank guesses, external algebraic
backends, exactification strategies, and imported workflow metadata.
`verify --strict` does not trust those inputs. It recomputes:

- canonical problem and certificate hashes;
- exact rational or supported `QQ(alpha)` reconstruction;
- exact LMI substitution and SOS coefficient matching;
- algebraic root isolation and certified signs;
- PSD proof obligations by exact replay;
- positive-polynomial, perturbation, compensation, and relation-reduction
  identities when a certificate family requires them.

The verifier ignores solver success flags, floating residuals, approximate
eigenvalues, backend logs, cached output, session transcripts, and provenance
claims.

## Supported Workflows

| Workflow | Status |
| --- | --- |
| Rational LMI and block LMI replay | Public v1 certificate format. |
| One-root algebraic LMI replay | Public v1 certificate format with certified root/sign checks. |
| Exact SOS Gram replay | Public v1 certificate format with embedded rational PSD proof. |
| Approximate SOS Gram exactification | `certify-auto-sos` direct replay plus round-project strategy. |
| Positive-polynomial identities | Rational-function SOS, Positivstellensatz, and perturbation/compensation replay formats. |
| Number-field SOS Gram replay | Algebraic SOS Gram certificate over one explicit `QQ(alpha)` field. |
| Noncommutative and quantum groundwork | Internal hard-gate replay for word identities, trace-cyclic matching, relation reductions, and embedded PSD blocks. |
| External ecosystem bridge | RealCertify, NCTSSOS, ClusteredLowRankSolver.jl, and CertifiedQuantumBounds adapters translate into CertSDP replay artifacts; raw logs are rejected. |
| Reviewer artifacts | Data-only certificate directories with manifest, strict replay text, LaTeX snippet, and redacted provenance. |

The public compatibility surface is intentionally smaller than the internal
hard-gate implementation. See [API stability](API_STABILITY.md) before using
module-qualified internals in downstream code.

## Evidence Snapshot

The validation suite is the release evidence contract. It records accepted
certificates that pass strict replay, expected rejection rows, fake-certificate
controls, rational-rounding failures, and imported SDPA/JuMP/SumOfSquares-style
workflows.

```bash
bin/certsdp doctor
julia --project scripts/run_validation.jl
```

The tracked report is `benchmarks/VALIDATION_REPORT.md`.

## Good Fits

Use CertSDP when:

- the problem data are exact rational data, SDPA sparse data, or exported exact
  SOS/Gram data;
- a numerical candidate looks feasible but needs exact replay;
- rational rounding may fail because the accepted point is algebraic;
- rank deficiency or degeneracy makes tolerance-based evidence fragile;
- a paper, reviewer, CI job, archive, or proof pipeline needs a portable
  certificate.

## Poor Fits

Do not use CertSDP as:

- a replacement for numerical SDP/SOS modeling and solver stacks;
- a large-scale dense SDP engine;
- a general infeasibility prover;
- a verifier for arbitrary floating-point model output without exact
  reconstruction;
- a guarantee that every feasible-looking numerical result can be certified.

When CertSDP accepts a certificate, exact replay passed. When it returns
`not_certified`, no supported exact certificate was accepted; that is diagnostic
evidence, not a mathematical infeasibility proof.

## Platform Scope

Core strict verification targets Julia 1.10+ environments. Linux and macOS run
the full package, docs, and validation matrix in CI; Windows has verifier-only
smoke coverage. Optional candidate-generation tools remain platform-dependent.

## Release Boundaries

| Boundary | Current contract | Not claimed |
| --- | --- | --- |
| Algebraic multi-block workflows | One-root algebraic certificates can be replayed blockwise; certifier generation is conservative. | Arbitrary algebraic SDP solving. |
| PSD scale | Validation-sized exact PSD replay is supported by determinant, Schur, LDL, pivoted-LDL, and blockwise methods. | Large-scale numerical SDP solving or numerical eigenvalue proof. |
| Infeasibility | `FailureResult` means no certificate was accepted. | Mathematical infeasibility unless a future explicit certificate family provides it. |
| Optional tools | Solvers, frontends, and algebraic backends are optional candidate sources. | Trusting optional tool logs, residuals, or backend artifacts as proof. |
