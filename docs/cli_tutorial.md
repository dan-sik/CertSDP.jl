# CLI Tutorial

Run commands from the repository root with the local wrapper `bin/certsdp`.

## Version And Help

```bash
bin/certsdp version
bin/certsdp help
bin/certsdp doctor
```

Exit codes:

- `0`: success, accepted certificate, or matching benchmark expectations;
- `1`: verification rejected a certificate;
- `2`: invalid input, parse error, or usage error;
- `3`: optional backend unavailable;
- `4`: backend timeout;
- `5`: not certified.

`doctor` checks whether the current environment has the pieces needed to rerun
the validation contract: Julia, CertSDP, CPU/RAM diagnostics, Clarabel,
`msolve`, JuMP, SumOfSquares, cache state, and validation metadata.

## Rational LMI Certificate

```bash
bin/certsdp certify examples/rational_problem.json \
  --solution examples/rational_solution.json \
  --out /tmp/certsdp-rational-cert.json

bin/certsdp verify --strict /tmp/certsdp-rational-cert.json
bin/certsdp inspect /tmp/certsdp-rational-cert.json
```

## Algebraic LMI Certificate

Install `msolve` or set:

```bash
export CERTSDP_MSOLVE=/absolute/path/to/msolve
```

Then run:

```bash
bin/certsdp certify examples/algebraic_problem.json \
  --solution examples/algebraic_approx.json \
  --out /tmp/certsdp-algebraic-cert.json \
  --msolve-precision 128 \
  --msolve-threads 1 \
  --timeout 300 \
  --slicing rational_rounding \
  --slice-max-denominator 1024 \
  --max-rank-retries 2 \
  --save-artifacts /tmp/certsdp-msolve-artifacts

bin/certsdp verify --strict /tmp/certsdp-algebraic-cert.json
```

Use `--algebraic-backend sage_msolve --sage /absolute/path/to/sage` to run the
Sage/msolve adapter instead of the direct msolve adapter. Both paths only
generate candidates; `certsdp verify --strict` remains an exact replay with no
external backend.

The approximate solution file is used for candidate selection. The generated
certificate is accepted only after exact verification.

## Solve, Diagnose, Certify

The numerical-oracle path can generate a reusable approximate solution with
Clarabel before exact certification:

```bash
bin/certsdp solve examples/algebraic_problem.json \
  --out /tmp/certsdp-algebraic-approx.json \
  --trace-objective maximize \
  --random-objective-trials 4 \
  --solver-attempts 2

bin/certsdp diagnose examples/algebraic_problem.json \
  --solution /tmp/certsdp-algebraic-approx.json

bin/certsdp certify examples/algebraic_problem.json \
  --solution /tmp/certsdp-algebraic-approx.json \
  --out /tmp/certsdp-algebraic-cert.json
```

The solve command tries feasibility, trace, and random linear objectives, then
selects the candidate using max-rank / face-search scoring. `solve-certify`
combines the same steps:

```bash
bin/certsdp solve-certify examples/algebraic_problem.json \
  --out /tmp/certsdp-algebraic-approx.json \
  --cert-out /tmp/certsdp-algebraic-cert.json \
  --random-objective-trials 4
```

For user-provided exact slices, pass `--slice-file slice.json`. The file may
contain either a top-level object or a `"slicing"` object with `strategy`,
`equations`, `variables`, `gauge_rows`, `max_denominator`, `max_equations`, and
`seed` fields. Slice equations are rational linear equations, for example:

```json
{
  "slicing": {
    "strategy": "user",
    "equations": [
      {
        "coefficients": {"x": "1"},
        "rhs": "0",
        "label": "fix x"
      }
    ]
  }
}
```

## SOS Gram Certificate

```bash
bin/certsdp certify-sos examples/sos/gram_x2_plus_1.json \
  --solution examples/sos/gram_x2_plus_1_solution.json \
  --out /tmp/certsdp-sos-cert.json

bin/certsdp verify --strict /tmp/certsdp-sos-cert.json
bin/certsdp inspect /tmp/certsdp-sos-cert.json
bin/certsdp export-sos /tmp/certsdp-sos-cert.json \
  --out /tmp/certsdp-sos-replay.jl \
  --format julia
```

`export-sos` supports `json`, `text`, `latex`, `sage`, and `julia` formats.

For approximate exported Gram candidates, use the strategy-based exactification
entry point:

```bash
bin/certsdp certify-auto-sos examples/sos/gram_x2_plus_1.json \
  --solution examples/sos/gram_x2_plus_1_solution.json \
  --out /tmp/certsdp-auto-sos-cert.json \
  --strategies direct,sos_round_project \
  --tolerance 1e-12

bin/certsdp verify --strict /tmp/certsdp-auto-sos-cert.json
```

The command reports which strategy was accepted. Strategy diagnostics are
provenance; strict replay of the emitted certificate remains the acceptance
boundary.

## Diagnostics

Diagnose approximate data:

```bash
bin/certsdp diagnose examples/algebraic_problem.json \
  --solution examples/algebraic_approx.json
```

Diagnose a saved failure report:

```bash
bin/certsdp diagnose /tmp/certsdp-failure.json
bin/certsdp explain /tmp/certsdp-failure.json
```

`explain` is the short sharing form. It keeps the output below 30 lines and
focuses on the failure type, stage, key evidence, and next actions.

## Replay Artifact Bundles

Bundle a certificate with replay data:

```bash
bin/certsdp bundle /tmp/certsdp-rational-cert.json \
  --out /tmp/certsdp-artifact.zip \
  --problem examples/rational_problem.json \
  --approx examples/rational_solution.json

bin/certsdp replay /tmp/certsdp-artifact.zip
```

Bundles include the certificate, problem, optional approximation, strict
verification report, version metadata, optional backend logs, a manifest, and a
README. Sidecar metadata and backend logs redact local paths by default; pass
`--no-redact` only for private debugging bundles. Replay runs strict exact
verification on the bundled certificate and ignores sidecar logs.

## Benchmarks

```bash
julia --project scripts/run_validation.jl
```

This writes `benchmarks/VALIDATION_REPORT.md` by default.
