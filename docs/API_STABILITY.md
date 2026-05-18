# API Stability

CertSDP.jl keeps a deliberately small public surface for the v1.0 line.
External code should depend on stable entry points, while exact arithmetic,
backend orchestration, proof planning, parsers, caches, and test fixtures can
evolve behind that boundary.

## Surface Map

| Surface | v1.0 status | Use for |
| --- | --- | --- |
| Julia API | Stable names listed below. | Applications that construct, certify, verify, diagnose, or write artifacts. |
| JSON problem/certificate data | Stable v1.0 read/write compatibility through public entry points. | Archived certificates, replay bundles, and paper artifacts. |
| CLI replay path | Public release workflow for `verify --strict`, `bundle`, and `replay`. | Independent reproduction and artifact checks. |
| Hard-gate experimental layer | Internal unless promoted below. | Exactification, external-adapter, number-field SOS, NC, and reviewer-artifact development. |
| Internals | Not stable unless promoted here. | CertSDP implementation and tests only. |

## Stable Public API

Only these names are covered by the v1.0 compatibility contract:

- `LMIProblem`: exact rational one-block LMI data for
  `A(x) = A0 + sum(xi * Ai)`.
- `BlockLMIProblem`: exact rational block LMI data for SDPA-style multiple PSD
  blocks with shared variables.
- `certify(problem, exact_solution_or_approx; kwargs...)`: build an exact
  rational certificate from a rational vector, or run the algebraic LMI
  certifier from an approximate candidate. It returns a result accepted by
  `verify` on success, or accepted by `diagnose` on failure.
- `verify(certificate_or_result; io=nothing, kwargs...)`: independently replay
  exact checks for LMI or SOS certificates/results.
- `diagnose(failure_or_result_or_certificate)`: produce a structured diagnostic
  report for failures, approximations, and verification status.
- `read_problem(path)`: read v1.0 problem JSON, legacy v0.1 LMI JSON, or SDPA
  sparse files with `.dat-s`, `.dats`, or `.sdpa` extensions.
- `write_problem(path, problem)`: write canonical v1.0 problem JSON, or SDPA
  sparse when the path has an SDPA extension.
- `read_certificate(path)`: read v1.0 LMI/SOS certificates and legacy v0.1
  LMI/SOS certificates.
- `write_certificate(path, certificate_or_result)`: write canonical v1.0
  certificate JSON.
- `certify_sos(model_or_problem; kwargs...)`: build an exact SOS Gram
  certificate from supported exported data or optional frontend integrations.
- `verify_sos(certificate_or_result; io=nothing, kwargs...)`: independently
  replay exact SOS coefficient matching and Gram PSD checks.
- `export_sos_decomposition(certificate_or_path)`: export verified SOS square
  data, or a verified Gram-only fallback when square export is unsafe.
- `sos_decomposition_text`, `sos_decomposition_latex`,
  `sos_decomposition_sage`, and `sos_decomposition_julia`: produce exact
  human-readable or replay-oriented SOS decomposition text from a verified SOS
  certificate.

Patch releases in the v1.0.x line may add keyword arguments and accept more
input variants, but they must not remove these names, change their core
meaning, or stop accepting valid v1.0 JSON written by this release.

## Documented Experimental API

These names are documented for early expert use, but they are not yet part of
the stable v1 compatibility promise and may require the `CertSDP.` namespace:

- `certify_auto_sos(problem, gram; kwargs...)`: exactification entry point for
  exported SOS Gram data. It tries named strategies such as direct replay and
  `:sos_round_project`, returning the same result contract as `certify_sos`.
- `round_project_sos_gram(problem, gram; kwargs...)`: helper that reconstructs
  and projects an SOS Gram candidate before a separate exact verifier accepts
  or rejects it.

## Compatibility Policy

`read_problem` and `read_certificate` are the compatibility entry points. They
accept the frozen v1.0 schema and the v0.1 JSON emitted by earlier prototype
releases.
Use `write_problem` and `write_certificate` to re-emit canonical v1.0 JSON.

`read_problem` is also the stable SDPA import boundary. Direct helper functions
such as `read_sdpa`, `write_sdpa`, `single_lmi_problem`, `parse_*`,
`validate_*`, and `migrate_*` remain available as module-qualified internals for
CertSDP's own tools and tests, but they are not part of the compatibility
contract. External applications should prefer the public entry points above.

Likewise, concrete certificate/result/failure types, backend types, polynomial
system objects, numerical diagnostic structs, PSD proof planners, cache objects,
and optional JuMP/SumOfSquares extraction helpers are implementation details
unless a future stability document explicitly promotes them.

These internal names are not part of the compatibility contract.

## Internal API

Everything not listed under Stable Public API is internal. This includes:

- rational/algebraic matrix helpers and sign-test internals;
- certificate constructors, hash helpers, and schema parser helpers;
- msolve/Sage backend adapters and backend cache controls;
- incidence-system builders, polynomial-system IR, and root selectors;
- numerical oracle/rank-profile heuristics;
- PSD proof planners and low-level verifier methods;
- benchmark runners, CLI subcommand internals, and names beginning with `_`.
- exactification strategy objects, proof-obligation graph helpers,
  noncommutative word-algebra groundwork, external adapter specs, and reviewer
  artifact helpers until they are promoted in a future stability document.
- `AlgebraicSOSGramProblem`, `AlgebraicSOSGramCertificate`,
  `NCSOSGramProblem`, `NCSOSGramCertificate`, `ExternalReplayArtifact`, and
  paper-artifact helper structs/functions. They are production hard-gate
  implementations, but not yet a stable downstream extension API.

Internal APIs may change within the v1.0 development series without a migration
promise. They should not be used as persistent file formats, downstream package
extension points, or long-term compatibility boundaries.

## Trust Boundary

The verifier is the trusted core. It replays exact rational substitution,
algebraic root checks, exact equality checks, certified sign tests, coefficient
matching, and PSD proof checks. Numerical solvers, rank diagnostics, msolve
output, backend logs, cached data, and certificate proof fields are candidate
data only; `verify` recomputes what matters before accepting a certificate.
