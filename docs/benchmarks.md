# Benchmarks

CertSDP's benchmark fixtures live under `benchmarks/`. The public entry point
is the validation suite:

```bash
julia --project scripts/run_validation.jl
```

The command writes `benchmarks/VALIDATION_REPORT.md` unless `--out` is given.
It exits with code `1` if any observed status differs from the corresponding
`expected.json` contract.

The script prepares the optional numerical oracle environment required by the
solve -> diagnose -> certify validation row. The lower-level
`bin/certsdp benchmark` command remains available for custom fixture runs, but
the script is the public release artifact path.

The report opens with `Replay Evidence At A Glance`, which is the reader-facing
summary: strict replay count, expected rejection evidence, rational-rounding
failure evidence, solve -> diagnose -> certify coverage, verifier timing, and
certificate size. The family and case tables that follow are the audit trail
behind that snapshot.

## What Validation Covers

The validation suite is a reproducibility fixture suite, not a performance
leaderboard. It covers:

- rational LMI certification;
- rank-deficient and weakly feasible SDP examples;
- algebraic certificates where bounded rational rounding fails;
- msolve-backed certifier-generated algebraic certificates;
- multi-block blockwise PSD certificates;
- exact SOS Gram coefficient matching;
- SDPA sparse import;
- JuMP/MOI and SumOfSquares-style extraction workflows;
- numerical solve -> diagnose -> certify workflows;
- negative fake-certificate rejection;
- structured failure reports.

The report also includes a paper-artifact capsule: paper-derived degenerate SDP
mechanisms, SDPA/SDPLIB-style imported block SDP cases, SumOfSquares-style SOS
workflows, fake-certificate mutation surfaces, and the raw artifact/DOI status.

## Report Contract

The markdown report includes:

```text
instance, family, category, construction type, source, certificate origin,
pipeline, size, declared variables, effective variables, affine density,
coefficient bit-size range, rank profile, status, certificate/failure type,
rational rounding result, certify time, strict verify time, certificate size,
cache-on/cache-off verifier comparison, cache hits/misses, slowest exact
verifier stage, timeout budget, backend, and message
```

Important provenance fields:

- `certificate_origin = direct_fixture` means the fixture provided an exact
  certificate and CertSDP replayed it.
- `certificate_origin = certifier_generated` means the benchmark ran the
  CertSDP certifier to generate the certificate.
- `pipeline = verify_only` means exact replay only.
- `pipeline = certify_from_approx` means the runner started from an approximate
  candidate and ran certification.
- `pipeline = solve_diagnose_certify` also includes the numerical oracle step.

Do not describe a `direct_fixture` / `verify_only` row as evidence that the
algebraic certifier solved the instance. The report separates replay evidence
from certifier-generated evidence.

## How To Read One Row

For a row with `certificate_origin = certifier_generated` and
`pipeline = certify_from_approx`, the benchmark started from an approximate or
exact candidate file, asked CertSDP to build a certificate, then required strict
verification to accept the generated certificate. For a row with
`certificate_origin = direct_fixture` and `pipeline = verify_only`, the row is
replay evidence: it shows the verifier can check the supplied exact artifact,
but it should not be described as a certifier solve.

## Paper-Artifact Lens

Validation reports should be read along three axes:

| Axis | What to inspect |
| --- | --- |
| Mathematical mechanism | Degenerate/incidence-style algebraic cases, rational rounding failures, exact PSD replay method. |
| Workflow realism | SDPA sparse import, JuMP/MOI source extraction, SumOfSquares-style Gram extraction, solve -> diagnose -> certify. |
| Negative evidence | Fake certificate rows, invalid approximation rows, adversarial mutation tests, structured failure artifacts. |

## Instance Layout

Each benchmark instance directory contains:

- `problem.json` or another exact source file such as `problem.dat-s`;
- `approx.json`, unless the workflow generates extracted artifacts from source;
- `expected.json`, with workflow, strategy, backend, expected status,
  runtime/memory metadata, certificate type, and provenance fields;
- `README.md`, with the mathematical point and reproducibility notes.

Some imported workflows intentionally ship a source script instead of a
hand-written `problem.json`. For example, the JuMP/MOI extraction validation
case executes `source.jl`, extracts an affine PSD model, then certifies the
extracted block LMI.

## Source Execution Trust Model

Validation `source.jl` files are trusted repository fixtures. The harness runs
them in a temporary Julia project so that imported-workflow examples exercise
the same extraction path an independent checker would use, but this is not a sandbox for
untrusted third-party code. Do not point the validation runner at external
benchmark trees that contain executable source unless you have reviewed the
scripts or are willing to run them with your normal Julia permissions.

The verifier boundary is different: certificates and problems are data-only,
and `certsdp verify --strict` never executes benchmark source files.

## Generated Artifacts

Generated certificates and extracted intermediate files should go under a
temporary directory or `benchmarks/generated/`. That directory is ignored by
git.

## Adding A Benchmark

Use the smallest exact instance that demonstrates the behavior. Include a
README explaining the mathematical point, the expected status, and any optional
backend requirement. Prefer adding to the validation suite only when the case
adds new evidence: a new frontend, a new certificate type, a new failure mode,
or a materially stronger exact-certification example.
