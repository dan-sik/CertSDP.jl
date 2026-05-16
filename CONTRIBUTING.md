# Contributing To CertSDP.jl

CertSDP is an exact replay layer for SDP/SOS certificate workflows. Numerical
solvers, frontend extractors, and optional algebraic backends may help find
candidates, but verifier acceptance must come from data-only certificate replay:
exact hashes, substitution, algebraic signs, PSD proof obligations, and SOS
coefficient matching.

The trust boundary is the most important contribution rule: candidate
generation may be heuristic, but acceptance must be exact and replayable.

## Before You Start

Read:

- `README.md`
- `docs/index.md`
- `docs/trust_model.md`
- `docs/validation.md`
- `docs/platform_support.md`

Keep public writing focused on supported workflows, verifier trust boundaries,
limitations, and reproducible validation evidence.
Internal planning notes should not surface in README, docs navigation,
examples, benchmark names, CLI help, generated reports, or contributor-facing
instructions.

## Development Setup

```bash
julia --project -e 'using Pkg; Pkg.instantiate()'
bin/certsdp doctor
```

Run the fast verify demo before and after user-facing changes:

```bash
bin/certsdp certify examples/rational_problem.json \
  --solution examples/rational_solution.json \
  --out /tmp/certsdp-rational-cert.json
bin/certsdp verify --strict /tmp/certsdp-rational-cert.json
```

## Testing

For most code changes, run:

```bash
julia --project -e 'using Pkg; Pkg.test(; coverage=false)'
```

For public documentation or release-surface changes, also run:

```bash
julia --project=docs docs/make.jl
julia --project scripts/run_validation.jl
```

If an optional backend is unavailable, the change should fail gracefully with a
structured diagnostic. Do not make core verification depend on optional
packages or external executables.

## Pull Request Expectations

- Keep changes scoped to the current task.
- Preserve user work and unrelated local changes.
- Add adversarial rejection tests for verifier, sign-test, PSD, SOS, schema, or
  certificate-format changes.
- Update docs when public behavior, CLI output, certificate schema, or
  validation evidence changes.
- Keep generated outputs such as `docs/build/`, `benchmarks/generated/`, cache
  directories, and platform files out of commits.

## Validation Evidence

The public validation suite is a reproducible evidence contract, not a
performance leaderboard. Reports must distinguish:

- `verify_only`: exact fixture replay;
- `certify_from_approx`: candidate-to-certificate generation;
- `solve_diagnose_certify`: numerical oracle, diagnostics, then exact
  certification.

Do not describe direct fixture replay as if the certifier solved the problem
from numerical data.
