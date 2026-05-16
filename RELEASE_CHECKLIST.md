# CertSDP v1.0 Release Checklist

Release candidate: `v1.0.0`
Date: 2026-05-14

This checklist is the public release gate for CertSDP.jl v1.0. It records what
must be true before tagging. Do not mark a gate complete without the matching
command output or review evidence.

## Required Gates

| Gate | Status | Evidence |
| --- | --- | --- |
| Version metadata | pass | `VERSION`, `Project.toml`, root `Manifest.toml`, CLI version, `CITATION.cff`, `codemeta.json`, and `examples/jump/Manifest.toml` report `1.0.0`. |
| Public API review | pass | `docs/API_STABILITY.md` lists the frozen v1.0 API; `Pkg.test()` confirms no extra exports. |
| Schema review | pass | `docs/SCHEMA_V1.md` documents v1.0 problem, certificate, SOS, and failure-report schemas; schema tests pass. |
| Docs/examples/CLI review | pass | Public docs, examples, CLI help, validation report, and README were scanned for stale development terms; only negative regression assertions remain. |
| License and notices | pass | Apache-2.0 `LICENSE`; `NOTICE.md` separates optional backend/frontends and `references/` materials. |
| Compat bounds | pass | `[compat]` covers deps, weakdeps, and test extras; `julia = "1.10"`. |
| Optional dependencies | pass | JuMP/MOI/SumOfSquares remain weakdeps/extensions; `examples/jump` has a reproducible optional frontend Manifest; msolve remains external optional. |
| CI matrix | pass | Linux/macOS full tests, Windows verifier-only smoke, docs, validation, coverage, and formatting are configured. |
| Release automation path | pass | Docs/validation badge workflows, TagBot, and CompatHelper workflow files are present; registry/DOI claims remain pending until external services accept the release. |
| Dead/debug artifact scan | pass | No public stale generated artifacts, debug prints, roadmap phase language, or obsolete examples found in release-facing files. |
| Full package tests | pass | `julia --project -e 'using Pkg; Pkg.test()'` passed on the final worktree. |
| Formatter check | pass | CI formatter command with JuliaFormatter passed after applying repository formatting. |
| Documentation build | pass | `julia --project=docs docs/make.jl` built the Documenter.jl site, including API reference and doctests. |
| Validation suite | pass | `julia --project scripts/run_validation.jl --out benchmarks/VALIDATION_REPORT.md --generated-dir benchmarks/generated` passed 18 instances. |
| Strict verifier adversarial tests | pass | Targeted `Pkg.test(; test_args=["adversarial"])` passed 185 adversarial mutation tests and 75 trust-boundary tests; full `Pkg.test()` also passed. |
| Clean clone quickstart | pass | `scripts/fresh_checkout_release_audit.sh --workdir /tmp/certsdp-v1-clean-audit --include-worktree --keep` passed with doctor ready and fake certificates rejected. |
| Release audit drill | pass | `julia --project=. scripts/release_audit.jl --out reports/v1_release_audit` passed, including package registration local dry-run. |

## Release Blocker Policy

The release is not ready if any of the following are observed:

- `Pkg.test()` fails.
- Documentation build fails.
- Validation suite has an unexpected mismatch.
- Any fake certificate is accepted by strict verification.
- Clean clone quickstart or release audit drill fails for a reason within CertSDP.
- Public docs, examples, CLI help, or validation reports expose internal
  roadmap/phase language as release claims.
- Optional backend absence causes verifier-only workflows to fail.

## Pre-Tag Commands

```bash
julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
julia --project=docs docs/make.jl
bin/certsdp doctor
julia --project scripts/run_validation.jl \
  --out benchmarks/VALIDATION_REPORT.md --generated-dir benchmarks/generated
julia --project=. scripts/release_audit.jl --out reports/v1_release_audit
scripts/fresh_checkout_release_audit.sh --workdir /tmp/certsdp-v1-clean-audit --include-worktree --keep
```

## Post-Tag Notes

- Do not tag until the release readiness report says `READY`.
- Do not include `benchmarks/generated/`, `docs/build/`, `reports/`, or other
  local generated artifacts in the tag.
- General registry submission still requires the normal Julia Registrator and
  registry review flow; the local dry-run is not a registry substitute.
- Do not add a registry badge or Zenodo DOI badge until the registry entry or
  DOI exists; update `CITATION.cff`, `codemeta.json`, README, and release notes
  after the DOI is minted.
