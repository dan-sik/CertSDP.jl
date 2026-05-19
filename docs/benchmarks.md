# Benchmarks

CertSDP's benchmark entry point is the reproducibility validation suite:

```bash
julia --project scripts/run_validation.jl
```

The command writes `benchmarks/VALIDATION_REPORT.md` unless `--out` is given.
It exits with code `1` if any expected validation check fails.

The lower-level command remains available for custom runs:

```bash
bin/certsdp benchmark benchmarks/ --suite validation --out /tmp/certsdp-validation-report.md
```

## What Validation Covers

The validation suite is an artifact replay suite, not a solver-speed
leaderboard. It checks:

- exact certificate reconstruction from imported or generated artifact data;
- strict replay over rational and algebraic arithmetic;
- sparse, block, low-rank, symmetry, and noncommutative structure metadata;
- Farkas-style infeasibility artifacts;
- artifact minimization and JSON replay;
- structured rejection for malformed fields, hashes, quotient data, affine
  identities, PSD factors, and unsupported import formats.

## Reading The Report

The tracked report is `benchmarks/VALIDATION_REPORT.md`. It is written for
reviewers and CI readers: what was replayed, what was rejected, and which proof
obligations are exact.

Use benchmark timings as local audit data only. They are not numerical solver
benchmarks and should not be compared across machines as performance claims.

## Generated Artifacts

Generated certificates and failure reports should go under a temporary
directory or `benchmarks/generated/`. That directory is ignored by git.

## Adding A Benchmark

Add a benchmark only when it contributes new proof evidence: a new certificate
family, import shape, rejection mode, minimization behavior, or replay
obligation. Prefer small, exact, deterministic fixtures for regression tests;
put heavier replay evidence behind the explicit validation command.
