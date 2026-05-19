# Changelog

All notable changes to CertSDP.jl are documented here.

## v2.1.0 - 2026-05-19

CertSDP is now positioned as an exact-certificate compiler for SDP/SOS
artifacts: candidate evidence enters from numerical, sparse, algebraic,
noncommutative, or external workflows; accepted output is proof-carrying JSON
that can be replayed with exact arithmetic.

### Added

- Proof-carrying artifact path with reconstruction logs, verification plans,
  diagnostics, hashes, minimization metadata, and solver-free replay.
- Field-discovery and field-minimization coverage for rational, quadratic,
  multiquadratic, cyclotomic, and low-degree algebraic examples.
- Structure-preserving compiler paths for sparse SOS, symmetry-reduced
  low-rank SDP, noncommutative trace certificates, and rational
  infeasibility artifacts.
- Artifact minimization and import normalization workflows for
  SumOfSquares-like, sparse-SOS-like, noncommutative-like, and clustered
  low-rank-like certificate data.
- Public documentation and validation report rewritten around the product
  promise: exact replayable certificates from candidate evidence.

### Changed

- Version metadata is now `2.1.0`.
- Validation reporting now emphasizes reproducibility evidence, accepted
  certificate families, structured rejection, and trust boundaries.
- The public README and documentation describe CertSDP as a certificate
  compiler rather than a narrow replay utility.

## v1.0.0 - 2026-05-14

First v1.0 release of the post-solver exact replay layer for numerical SDP/SOS
certificates. CertSDP turns solver candidates into data-only JSON artifacts that
can be checked independently by strict rational or supported algebraic replay.

### Release Significance

- Establishes CertSDP as a certificate protocol and strict verifier for
  replayable SDP/SOS research artifacts, not a numerical SDP solver.
- Records public evidence for strict verifier replay, expected rejection,
  fake-certificate controls, imported workflows, and rational-rounding failure
  cases.
- Freezes the v1.0 API and JSON artifact boundary for reproducible research,
  reviewers, CI checks, and archival replay bundles.

### Added

- Frozen v1.0 public API: `LMIProblem`, `BlockLMIProblem`, `certify`,
  `verify`, `diagnose`, `read_problem`, `write_problem`, `read_certificate`,
  `write_certificate`, `certify_sos`, and `verify_sos`.
- Data-only v1.0 problem, certificate, and failure-report schemas with
  canonical hashes and legacy v0.1 read/migration support.
- Exact rational, blockwise rational, algebraic one-root, and SOS Gram
  certificate families.
- Strict verifier mode for independent replay. It rejects approximate,
  backend-dependent, stale-hash, malformed, and fake proof fields before exact
  acceptance.
- PSD proof planner support for principal minors, Schur-zero, LDL-style, and
  blockwise exact replay with localized failure diagnostics.
- SDPA sparse import/export through the stable `read_problem`/`write_problem`
  boundary, including multi-block and diagonal-block fixtures.
- Optional JuMP/MOI and SumOfSquares integrations through Julia extensions.
- Numerical oracle and diagnostics workflow with Clarabel, random objectives,
  rank/face-quality reports, `certsdp solve`, `diagnose`, and `solve-certify`.
- Optional external `msolve` backend orchestration with timeout handling,
  provenance, artifacts, backend cache, exact candidate replay, and structured
  failure results.
- Reproducible validation suite covering rational, rank-deficient,
  weakly feasible, algebraic, imported, SOS, solve-diagnose-certify,
  adversarial rejection, and structured failure workflows.
- Replay tooling: `certsdp doctor`, `explain`, `bundle`, `replay`, validation
  reporting, and fresh-checkout reproducibility checks.
- Local documentation build with installation, quickstart, LMI/SOS tutorials,
  SDPA/JuMP/MOI guides, backend guide, trust model, validation contract,
  certificate schema, diagnostics, performance notes, and citation guidance.

### Changed

- Version metadata is now `1.0.0` in `VERSION`, `Project.toml`,
  citation metadata, codemeta, CLI output, and generated provenance examples.
- Public benchmark language is consolidated around the single validation
  contract rather than development-only pack names.
- Optional frontends and algebraic backends remain outside the trusted verifier
  boundary; acceptance depends only on exact replay.
- CI now separates full Linux/macOS package tests from Windows verifier-only
  smoke coverage and keeps documentation and validation checks in the main
  release path.

### Compatibility

- v1.0.x patch releases must continue to read and verify valid v1.0 problem and
  certificate JSON.
- Legacy v0.1 LMI and SOS JSON emitted by earlier prototypes remains readable
  through `read_problem`, `read_certificate`, and the public certificate
  writers for migration.
- Internal constructors, backend adapters, schema helpers, proof planners,
  benchmark internals, and cache objects are not part of the compatibility
  contract.

### Limitations

- CertSDP is an exact replay layer, not a generic large-scale SDP solver
  or infeasibility prover.
- Algebraic certificates use the supported one-root representation.
- `msolve`, JuMP/MOI, SumOfSquares, and numerical solvers are optional
  candidate-generation or extraction aids; they are not trusted verifier proof.
- Unsupported or oversized algebraic systems are expected to return structured
  failure reports rather than acceptance.

## v0.1.0 - 2026-05-10

Initial research prototype release.

### Added

- Exact rational LMI core with `LMIProblem`, `SymmetricRationalMatrix`, exact
  substitution, and stable problem hashes.
- JSON v0.1 input/output for LMI problems, rational solutions, approximate
  solutions, and certificates.
- Type R rational PSD certificates with independent verifier replay.
- Small algebraic number layer over one isolated real root.
- Certified algebraic sign tests using exact zero checks, Sturm root counts,
  and rational interval refinement.
- Type A/F algebraic PSD certificates with principal-minor and Schur-zero
  facial-block PSD proofs.
- Numerical `ApproxSolution` diagnostics and rank-profile detection used only
  for candidate selection.
- Internal polynomial-system representation and incidence-system builder.
- Optional external `msolve` adapter plus end-to-end prototype certifier pipeline.
- CLI commands: `certify`, `certify-sos`, `verify`, and `inspect`.
- Exported SOS Gram workflow with exact coefficient matching and embedded
  rational PSD certificate.
- Documentation, examples, reproducible validation benchmarks, CI, license, and
  formatter config.
