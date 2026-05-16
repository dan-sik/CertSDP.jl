# CertSDP Documentation

CertSDP.jl is the post-solver exact replay layer for numerical SDP/SOS
certificates. It turns rational LMI/SOS data plus solver candidates into
data-only JSON certificates that can be replayed independently with exact
rational or supported algebraic arithmetic.

CertSDP is not a replacement for numerical solvers. It is the certificate
protocol and strict verifier for the point where a feasible-looking SDP/SOS
result becomes a replayable research artifact.

## Core Claim

Numerical solvers are excellent at finding candidates, but a solver residual is
not a proof. CertSDP sits after JuMP, SumOfSquares.jl, numerical solvers, and
optional algebraic backends, then accepts only certificates that survive exact
replay.

The verifier is the trusted core: it replays canonical hashes, exact
substitution, rational arithmetic, algebraic root isolation, certified sign
tests, PSD proof data, and SOS coefficient matching. Numerical solvers and
algebraic backends can help find candidates, but they are not trusted as proof.

The shortest accurate description is:

```text
A solver finds a candidate. CertSDP makes it replayable.
```

## At A Glance

| Question | Answer |
| --- | --- |
| Input | Exact rational LMI/SOS problem data plus a rational, algebraic, or exported Gram candidate. |
| Output | Data-only JSON certificates and replay bundles. |
| Trusted core | `verify --strict`, which recomputes hashes, exact substitution, signs, PSD proofs, and SOS coefficient matching. |
| Optional tools | Numerical solvers, `msolve`, Sage/msolve, JuMP/MOI, and SumOfSquares.jl can help find or extract candidates. |
| Public evidence | The validation report records strict replay, expected rejection rows, fake-certificate controls, rational-rounding failures, and imported workflows. |

## Who Should Use This

| Reader | Use CertSDP to |
| --- | --- |
| SDP/SOS researchers | Turn candidate feasible points, Gram matrices, and algebraic solutions into exact replay artifacts. |
| JuMP, MOI, SumOfSquares.jl, or SOSTOOLS users | Add a strict verification step after numerical or symbolic search. |
| Paper authors | Archive data-only certificates and replay bundles with a reproducible validation path. |
| Reviewers and artifact evaluators | Check accepted claims by exact replay instead of solver logs or floating-point residuals. |
| Tool builders | Depend on the small v1.0 JSON/API boundary for certification, replay, and diagnostics. |

## Why It Matters

| Solver workflow state | Claim risk | CertSDP behavior |
| --- | --- | --- |
| Numerical output | Tolerance-based residuals can hide exact PSD failure. | Candidate data only. |
| Rational rounding | Degenerate or algebraic feasible points may not survive bounded-denominator rounding. | Exact substitution and PSD replay accept or reject the rounded point. |
| Exact certificate | Proof fields can be stale, forged, or backend-derived. | Strict replay recomputes every trusted obligation. |

## Trust Boundary

`certify` may use numerical diagnostics, rank guesses, external algebraic
backends, caches, and heuristic candidate selection. `verify --strict` does not
trust those claims.

| Trusted by strict replay | Not trusted as proof |
| --- | --- |
| v1.0 certificate data and canonical hashes | Solver success flags |
| Exact arithmetic in `QQ` or `QQ(alpha)` | Floating-point eigenvalues or residuals |
| Root isolation by rational intervals | Raw `msolve`, Sage, or solver logs |
| Exact LMI substitution and SOS coefficient matching | Cached backend artifacts |
| PSD proof replay by accepted exact methods | Approximate equalities or rounded diagnostics |

## Reading Path

For first-time use:

1. [Installation](installation.md)
2. [Platform support](platform_support.md)
3. [Quickstart](quickstart.md)

For workflows:

1. [LMI tutorial](lmi_tutorial.md)
2. [SOS tutorial](sos_tutorial.md)
3. [SDPA import/export](sdpa_import.md)
4. [JuMP / MOI integration](jump_moi_integration.md)
5. [Backends](backends.md)
6. [Diagnostics](diagnostics.md)
7. [Workflows](workflows.md)

For trust, evidence, and reference:

1. [Trust model](trust_model.md)
2. [Validation](validation.md)
3. [Benchmarks](benchmarks.md)
4. [Performance](performance.md)
5. [Certificate format](certificate_format.md)
6. [API reference](api_reference.md)
7. [API stability](API_STABILITY.md)
8. [Schema v1.0](SCHEMA_V1.md)

## Evidence Snapshot

The public validation suite is the release evidence contract, not a solver-speed
leaderboard. The current tracked v1.0 report records:

- 18 public validation instances;
- 15 / 15 accepted certificates passing strict replay;
- 3 expected rejection or structured-failure rows;
- 4 actual rational-rounding failures certified by exact algebraic replay;
- imported SDPA, JuMP/MOI, and SumOfSquares-style workflows;
- fake-certificate and invalid-approximation rejection controls.

See [Validation](validation.md) and the tracked report at
`benchmarks/VALIDATION_REPORT.md`.

## Good Fits

Use CertSDP when:

- the input problem has exact rational coefficients;
- a numerical SDP/SOS workflow found a promising candidate but you need an
  exact certificate;
- rational rounding may fail because the correct solution is algebraic;
- the feasible point is degenerate or rank-deficient;
- a JSON certificate should be archived, shared, inspected, and replayed.

## Poor Fits

Do not use CertSDP as:

- a replacement for a numerical SDP solver;
- a large-scale dense SDP engine;
- a general infeasibility certifier;
- a verifier for arbitrary floating-point model output without exact
  reconstruction;
- a fully automated solver for every SumOfSquares hierarchy instance.

## Version Scope

The current release line exposes rational LMI certificates, one-root algebraic
LMI certificates including multi-block blockwise replay, exported SOS Gram
certificates with replay exports, positive-polynomial certificate schemas, SDPA
sparse import/export, JuMP/MOI affine PSD extraction, optional SumOfSquares
extraction, optional `msolve` and Sage/msolve candidate generation, structured
failure reports, replay bundles, and a reproducible validation suite.

Some algorithms are intentionally conservative. When CertSDP accepts a
certificate, the verifier has replayed the proof exactly. When CertSDP returns
`not_certified`, that is a diagnostic result rather than a mathematical
infeasibility proof.

## Platform Scope

Core strict verification is cross-platform for Julia 1.10+ environments. The
full package and validation CI matrix currently covers Linux and macOS, while
Windows has verifier-only smoke coverage. See [Platform support](platform_support.md)
for the exact support statement and optional-backend caveats.

## Release Boundaries

| Boundary | Current contract | Not claimed |
| --- | --- | --- |
| Algebraic multi-block workflows | One-root algebraic certificates can be replayed blockwise; certifier generation is budgeted and conservative. | Arbitrary algebraic SDP solving. |
| PSD scale | Validation-sized exact PSD replay is supported by determinant, Schur, LDL, pivoted-LDL, and blockwise methods. | Large-scale numerical SDP solving or numerical eigenvalue proof. |
| Infeasibility | `FailureResult` means no certificate was accepted. | Mathematical infeasibility unless a future explicit certificate family provides it. |
| Optional tools | Solvers, frontends, and algebraic backends are optional candidate sources. | Trusting optional tool logs, residuals, or backend artifacts as proof. |
