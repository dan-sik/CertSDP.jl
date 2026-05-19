# Validation

CertSDP validation is a reproducibility contract for exact certificate replay.
It answers a practical question:

```text
Can this checkout turn certificate evidence into exact proof-carrying artifacts and reject malformed proof data?
```

Run it from the repository root:

```bash
bin/certsdp doctor
julia --project scripts/run_validation.jl
```

`doctor` checks Julia, CertSDP, CPU/RAM diagnostics, optional packages, backend
paths, cache state, and validation metadata. Candidate construction may use
optional tools; strict replay of accepted certificates is solver-free.

The tracked report is written to:

```text
benchmarks/VALIDATION_REPORT.md
```

## Local Test Profiles

The default package test is intentionally fast:

```bash
julia --project test/runtests.jl
```

It runs command smoke tests, core exact replay regressions, and a compact
compiler regression suite. Focused profiles are available when you only need
one surface:

```bash
julia --project test/runtests.jl cli
julia --project test/runtests.jl regression
julia --project test/runtests.jl docs
```

Heavier checks are explicit:

```bash
julia --project test/runtests.jl validation
julia --project test/runtests.jl release_smoke
julia --project test/runtests.jl all
```

Use `validation` for replay evidence, `release_smoke` before packaging, and
`all` for the complete current test suite. The `all` profile is deliberately
limited to active validation, command, regression, release, and documentation
checks; retired compatibility specimens are not part of it.

## Current Evidence

The validation suite covers:

- rational LMI and block LMI certificates;
- algebraic LMI and SOS Gram certificates where rational rounding is
  insufficient;
- sparse SOS and Putinar-style identities with preserved block structure;
- symmetry-reduced and low-rank SDP certificate replay;
- noncommutative and trace-polynomial certificate replay;
- Farkas-style infeasibility certificates;
- external artifact import, normalization, JSON export, and replay;
- artifact minimization with equivalence checks;
- structured rejection of malformed hashes, fields, quotient data, affine
  identities, PSD factors, and adapter formats.

## Reader-Facing Snapshot

| Reader question | Validation evidence |
| --- | --- |
| Did accepted artifacts replay exactly? | Strict replay recomputes exact identities, field arithmetic, quotient reductions, hashes, and PSD obligations. |
| Are invalid artifacts rejected? | The suite mutates certificate coordinates, fields, structure labels, quotient rules, multipliers, hashes, and import formats. |
| Does structure survive certification? | Sparse, block, symmetry-reduced, low-rank, and noncommutative metadata are part of the replay surface. |
| Is minimization safe? | Minimized artifacts must verify and remain semantically equivalent to their source artifact. |
| Is external output treated carefully? | External formats are normalized into CertSDP IR before strict replay can accept them. |

## Paper-Artifact Coverage

The suite is organized around the kinds of evidence a mathematical software
artifact should provide:

| Evidence class | What is demonstrated |
| --- | --- |
| Exact replay | Accepted artifacts pass by exact arithmetic, not numerical tolerance. |
| Algebraic reconstruction | Certificates can carry field data when rational coordinates are not enough. |
| Structure preservation | Sparse, block, quotient, and symmetry metadata are replay obligations, not decoration. |
| Negative controls | Known-invalid artifacts fail with localized diagnostics. |
| Reproducibility | Generated artifacts can be exported, minimized, and replayed from JSON. |

## Mutation Matrix

| Mutation surface | Expected rejection |
| --- | --- |
| Problem or certificate hash | Rejected before mathematical replay. |
| Rational coordinate or affine multiplier | Rejected by exact identity mismatch. |
| Algebraic field declaration | Rejected by field or minimality checks. |
| Sparse clique or localizing constraint label | Rejected by structure or localizing-identity checks. |
| Symmetry transform metadata | Rejected by reconstruction metadata checks. |
| Noncommutative commutation or trace quotient | Rejected by NC/trace identity checks. |
| PSD block factor or rank data | Rejected by exact PSD replay. |
| Unsupported external format | Rejected before entering the trusted proof surface. |

## Raw Artifacts And DOI

`benchmarks/VALIDATION_REPORT.md` is the tracked reader-facing report.
Re-running the benchmark command can emit a compact table to a temporary path:

```bash
bin/certsdp benchmark benchmarks/ --suite validation --out /tmp/certsdp-validation-report.md
```

Generated certificates, failure reports, and extracted intermediates should go
under `benchmarks/generated/`, which is intentionally ignored by git.

The repository includes `CITATION.cff` and `codemeta.json`. A DOI should be
minted from a tagged public archive after tests, docs, and validation pass.

## Trust Boundary

Candidate sources may include numerical solvers, algebraic backends, external
tools, reference fixtures, or user-supplied artifacts. Acceptance comes only
from strict exact replay of certificate data.

Fields treated as provenance only:

- solver status and residuals;
- approximate eigenvalues and ranks;
- backend logs and transcripts;
- cache hits;
- source paths and human-readable claims.

Fields replayed exactly:

- problem, artifact, and semantic hashes;
- field arithmetic and minimality evidence;
- sparse coefficient and affine identities;
- quotient reductions;
- low-rank PSD factors;
- minimization equivalence witnesses.

## Interpreting Failures

A rejected row is not automatically a bug. Several rows are designed to fail in
structured ways. A validation failure is serious when the observed status
differs from the expected status, when an invalid artifact is accepted, or when
an exact proof obligation is silently skipped.

For a saved failure report:

```bash
bin/certsdp explain failure.json
```

The explanation is capped and intended for audit notes, issue reports, and
reviewer communication.

## Scope

The shipped validation suite exercises the compiler, verifier, import
normalization, minimization, and rejection behavior using reproducible fixtures
in this repository and reference-backed artifacts under `references/`. Future
public benchmark packs can add native upstream outputs from additional solver
ecosystems without changing the acceptance rule: external tools may produce
candidates, but exact replay accepts certificates.
