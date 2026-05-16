# Performance

CertSDP uses scoped caches and timing instrumentation for repeated verifier and
validation runs. These caches only memoize exact intermediate values; they do
not make numerical evidence trusted proof.

## Cache Scope

Verifier calls use a short-lived `VerificationCache` by default. It caches:

- exact rational and algebraic determinants used by PSD proofs;
- certified algebraic sign-test results;
- univariate polynomial remainders used by equality and reduction checks.

Disable it when comparing behavior:

```julia
verify(cert; cache=false)
timed = verify_timed(cert; cache=true)
timed.stats
```

The benchmark runner always verifies each parsed certificate twice, first with
cache disabled and then with cache enabled. A benchmark row fails if the two
acceptance results differ.

## Backend Result Cache

`msolve` result caching is optional and off unless a cache directory is passed.
Entries are keyed by the exact `polynomial_system_hash(system)` plus backend
options such as characteristic, parametrization, precision, executable, and
version.

```julia
backend = MsolveBackend(cache_dir=".certsdp_cache/msolve")
solve_system(system, backend)
```

CLI:

```bash
bin/certsdp certify problem.json \
  --solution approx.json \
  --out cert.json \
  --budget validation \
  --timeout 300 \
  --backend-cache .certsdp_cache
```

Cached backend output is still only candidate data. Certificates are accepted
only after exact verification.

## Current Baseline

Baseline command run on this workspace:

```bash
julia --project scripts/run_validation.jl --out /tmp/certsdp-validation-report.md
```

Observed validation baseline on this machine:

```text
instances: 18
status: passed
cache on/off acceptance: identical for all rows
negative fake certificates: rejected with cache on and cache off
validation budget: validation
total cached verifier time: reported in Cache Comparison Summary
total uncached verifier time: reported in Cache Comparison Summary
cache hits/misses: reported in Cache Comparison Summary
slowest validation rows: reported in Slowest Validation Cases
certificate size summary: reported in Certificate Size Summary
```

The report columns `Verify No Cache`, `Cache Hits`, `Cache Misses`,
`Cache Speedup`, `Slowest Stage`, `Timeout`, and `Cert Size` are the
quantitative baseline. Times are local-machine measurements and include Julia
warmup effects when the command is run cold, so compare repeated runs on the
same environment.

## Validation Budget

The public validation contract uses one named budget:

```bash
julia --project scripts/run_validation.jl --timeout 1800
```

`--timeout` is an upper bound for the whole validation row. Algebraic
certification passes the remaining time to `msolve`, and oversized incidence
systems are stopped before backend launch. Infeasible validation rows must
finish as a skipped row or a structured failure report, never by depending on
an unbounded backend run.

## Profiling Notes

The slow verifier path before scoped caches was repeated exact PSD proof replay:
certificate verification recomputed proof determinants, then ran the PSD
verifier over the same matrix again. Algebraic certificates also repeated
polynomial remainders and sign tests while comparing proof data and certifying
nonnegativity.

The cached verifier keeps both proof replay steps, but shares exact
intermediate results inside one verifier call. The trusted behavior is
unchanged: fake certificates with matching hashes are still rejected because
every proof obligation is recomputed and checked.

The slowest-row table is generated from strict verifier timings and scoped
cache timing buckets. `determinant_seconds`, `algebraic_sign_seconds`, and
`polynomial_remainder_seconds` identify which exact operation dominated a row.
