# v1.0 Release Readiness Report

Status: READY.

This report is updated during the v1.0 release-candidate hardening pass. A
release may be tagged only when the status is `READY` and every hard gate below
has passing evidence.

## Scope Reviewed

- Public API: frozen exports in `docs/API_STABILITY.md` and tests.
- Schemas: v1.0 problem, certificate, SOS Gram, and failure-report schemas.
- Documentation: installation, quickstart, LMI, SOS, SDPA, JuMP/MOI, backends,
  diagnostics, validation, benchmark contract, performance, trust model,
  citation, and release checklist.
- CLI: `certify`, `certify-sos`, `verify --strict`, `inspect`, `solve`,
  `solve-certify`, `diagnose`, `benchmark`, `doctor`, `explain`, `bundle`,
  and `replay`.
- Examples and validation fixtures: rational, algebraic, SOS, SDPA,
  multi-block, numerical oracle, JuMP/MOI, SumOfSquares-style extraction, and
  adversarial rejection cases.
- Release metadata: `VERSION`, `Project.toml`, `CHANGELOG.md`,
  `CITATION.cff`, `codemeta.json`, license, notices, compat bounds, optional
  dependency boundaries, CI matrix, docs/validation badge workflows, TagBot,
  and CompatHelper.

## Gate Evidence

| Gate | Result | Evidence |
| --- | --- | --- |
| `Pkg.test()` | pass | Final worktree passed `julia --project -e 'using Pkg; Pkg.test()'`. |
| Formatter check | pass | JuliaFormatter CI check passed on `src`, `ext`, `test`, and `benchmarks`. |
| Docs build | pass | `julia --project=docs docs/make.jl` built the Documenter.jl documentation site, including public API reference and doctests. |
| Validation suite | pass | `julia --project scripts/run_validation.jl --out benchmarks/VALIDATION_REPORT.md --generated-dir benchmarks/generated` passed 18 instances with expected statuses matched. |
| Strict adversarial rejection | pass | Targeted adversarial test run passed 185 fake/mutated certificate tests plus 75 strict trust-boundary tests; full test suite also passed these tests. |
| Public release path | pass | Registry submission, TagBot, CompatHelper, docs/validation badges, and Zenodo DOI update steps are documented; DOI and registry badges remain pending until external services accept the artifact. |
| Clean clone quickstart | pass | `scripts/fresh_checkout_release_audit.sh --workdir /tmp/certsdp-v1-clean-audit --include-worktree --keep` passed. |
| Release audit drill | pass | `julia --project=. scripts/release_audit.jl --out reports/v1_release_audit` passed, including package registration local dry-run. |

## Current Blocking Issues

None observed in the final v1.0 release-candidate pass.

## Release Decision

CertSDP.jl is ready to tag as `v1.0.0` from this release-candidate state,
subject to the normal Julia package registration process. The local dry-run is
metadata/loadability evidence only; it does not replace Registrator or General
registry review.

## Notes

- The validation report includes exact rejection rows; those are expected
  negative controls, not failures.
- `msolve` was available locally during the release-candidate pass.
- The clean-clone drill used `--include-worktree` so the pre-tag check covered
  the current release changes before a commit/tag existed.
