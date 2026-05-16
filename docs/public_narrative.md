# Public Narrative

This page is the release-language guide for README copy, talks, issue
responses, package descriptions, and artifact notes. It keeps CertSDP's public
story attractive without overstating what the verifier or certifier currently
proves.

## One-Sentence Description

CertSDP.jl is an exact replay layer for SDP and SOS certificate workflows: a
solver may find a candidate, but acceptance comes from independent rational or
supported algebraic verification.

## Short Description

Numerical SDP/SOS solvers are excellent candidate generators, but their
residuals are tolerance-based. CertSDP sits after the solver and turns exact
problem data plus candidate solutions into replayable JSON certificates. The
strict verifier recomputes hashes, exact substitution, algebraic root data,
certified signs, PSD proof obligations, and SOS coefficient matching without
trusting solver logs or backend artifacts.

## Audience Fit

| Audience | What to emphasize |
| --- | --- |
| Optimization and SOS users | CertSDP is a post-solver verification layer, not a replacement solver. |
| Computational algebra users | Optional `msolve` or Sage/msolve backends help propose algebraic candidates; strict replay remains inside CertSDP. |
| Paper and artifact reviewers | Certificates are data-only, bundleable, and replayed by `verify --strict` without optional solvers. |
| Package evaluators | The v1.0 line has a frozen public API, a validation suite, negative controls, and explicit platform boundaries. |

## Evidence To Link

- [Quickstart](quickstart.md): first accepted rational certificate from a fresh checkout.
- [Trust model](trust_model.md): the exact boundary between candidate generation
  and proof replay.
- [Validation](validation.md): the tracked public evidence suite, including
  algebraic rational-rounding failures and fake-certificate rejection.
- [Benchmarks](benchmarks.md): how to interpret validation rows and provenance
  fields.
- [Platform support](platform_support.md): Linux/macOS full validation and
  Windows verifier-only coverage.
- [API stability](API_STABILITY.md): the v1.0 compatibility surface.

## Claims That Are Safe

- CertSDP verifies supported SDP/SOS certificates by exact replay.
- Numerical solvers, `msolve`, Sage/msolve, JuMP/MOI, and SumOfSquares.jl are
  optional candidate-generation or extraction aids.
- Strict verification does not trust solver residuals, backend logs, cached
  output, approximate eigenvalues, or certificate proof fields without
  recomputation.
- The validation suite includes positive certificates, algebraic
  rational-rounding failures, imported workflows, solve-diagnose-certify rows,
  and negative controls.
- Core strict verification is intended to run wherever Julia 1.10+ and the
  package dependencies run; full validation CI is currently Linux/macOS, with
  Windows verifier smoke coverage.

## Claims To Avoid

- Do not call CertSDP a general-purpose SDP solver.
- Do not claim arbitrary SDP/SOS models are automatically certifiable.
- Do not call a `FailureResult` an infeasibility proof.
- Do not present `msolve` output, numerical residuals, or backend provenance as
  trusted proof evidence.
- Do not claim Julia General registry availability or a Zenodo DOI until those
  external services have accepted the tagged artifact.
- Do not describe direct-fixture validation rows as evidence that the algebraic
  certifier solved those instances; use the `pipeline` and `certificate_origin`
  fields in the report.

## Preferred Release Language

Use wording like this in external posts or release notes:

```text
CertSDP.jl is a Julia package for exact replay of supported SDP/SOS
certificates. It is designed for reproducible research artifacts: solvers and
algebraic backends may help find candidates, but strict verification accepts
only after exact rational or supported algebraic replay.
```

For release status, use:

```text
The repository is prepared for v1.0 packaging. Registry and DOI claims remain
pending until the tagged artifact is accepted by the Julia General registry and
an archival DOI service.
```

## Copy-Ready Snippets

GitHub repository description:

```text
Exact replay for SDP/SOS certificate workflows in Julia.
```

Release-note paragraph:

```text
CertSDP.jl v1.0 provides a strict exact replay path for supported SDP/SOS
certificates. Numerical solvers and algebraic backends may help find
candidates, but verifier acceptance is independent of solver residuals,
backend logs, and cached artifacts.
```

Paper artifact abstract:

```text
The artifact contains data-only SDP/SOS certificates and a Julia verifier that
replays exact rational or supported algebraic obligations. The validation suite
includes strict replay successes, expected rejection cases, and examples where
bounded rational rounding fails but algebraic certification succeeds.
```

Short demo pitch:

```text
Use a solver to find a candidate; use CertSDP to make the claim replayable.
```
