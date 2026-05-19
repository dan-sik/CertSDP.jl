# Diagnostics

CertSDP treats non-certification as useful output. A failure means the exact
verifier did not receive enough valid proof data; it is not an infeasibility
certificate.

## CLI Exit Codes

The CLI exit codes are:

- `0`: command succeeded, certificate accepted, or benchmark expectations met;
- `1`: verification rejected a certificate;
- `2`: invalid input, command usage error, or parse error;
- `3`: required optional backend is unavailable;
- `4`: backend timeout;
- `5`: not certified.

## Approximate Solution Diagnosis

```bash
bin/certsdp diagnose examples/algebraic_problem.json \
  --solution examples/algebraic_approx.json
```

This reports residuals, minimum eigenvalue, PSD violation, rank estimate, rank
confidence, rank gap, eigengap, face clarity, objective kind, pivot data when
stable, and a recommendation.

`certsdp solve` writes an approximation JSON that preserves the rank tolerance,
solver status, objective vector, retry index, and max-rank face-search attempt
log:

```bash
bin/certsdp solve examples/algebraic_problem.json \
  --out /tmp/certsdp-approx.json \
  --trace-objective maximize \
  --random-objective-trials 8 \
  --solver-attempts 2
```

If the selected face is unclear, the diagnosis recommends random objective
restarts or a different rank tolerance. Solver failures are reported as
`NumericalFailure` and do not crash the CLI.

## Structured Failure Results

The stable Julia API lets you verify or diagnose the returned result without
depending on concrete internal result types:

```julia
using CertSDP

P = read_problem("examples/algebraic_problem.json")
approx = CertSDP.read_approx_solution_json("examples/algebraic_approx.json")
result = certify(P, approx; algebraic_backend=:msolve)

if verify(result)
    write_certificate("/tmp/certsdp-cert.json", result)
else
    diagnose(result)
end
```

Inspect a saved failure report:

```bash
bin/certsdp diagnose /tmp/certsdp-failure.json
bin/certsdp explain /tmp/certsdp-failure.json
```

Use `explain` when sharing a failure with an auditor, collaborator, or issue tracker. It is a
compact view capped at 30 lines, with the failure type, stage, key evidence,
and the most relevant next steps.

## Failure Types

CertSDP currently reports:

- `NumericalFailure`;
- `RankUnstableFailure`;
- `SystemTooLargeFailure`;
- `BackendFailure`;
- `NoNearbyRealSolutionFailure`;
- `PSDVerificationFailure`;
- `SOSMatchingFailure`;
- `BackendTimeoutFailure`.

These reports include the stage, reason, machine-readable details, provenance,
and suggested next steps.

## What To Try

If the rank profile is unstable, rerun the approximate SDP solve at higher
precision, seek a maximum-rank feasible point, or inspect the singular values in
the diagnosis output.

If `msolve` is missing, install it, set `CERTSDP_MSOLVE`, or pass `--msolve`.

If a backend times out, rerun with `--save-artifacts`, inspect the polynomial
system size, and consider a smaller slice or a different rank/pivot strategy.

If a backend reports a positive-dimensional system, try exact rational slicing
or provide a slice file:

```bash
bin/certsdp certify problem.json \
  --solution approx.json \
  --out cert.json \
  --slicing rational_rounding \
  --slice-max-equations 2
```

Useful failure reports include `attempt_summary`, attempted ranks/pivots,
slicing strategy, system variable/equation counts, degree estimate, and memory
estimate. Too-large systems are stopped before backend launch as
`SystemTooLargeFailure`.

If PSD verification fails, do not treat numerical eigenvalues as proof. Try a
different exact PSD proof method only when it matches the mathematical
structure of the candidate.

## Verifier Output

Successful rational verification ends with:

```text
[OK] PSD verified over QQ
[OK] certificate accepted
```

Successful algebraic Schur-zero verification ends with:

```text
[OK] Schur-zero PSD verified over QQ(alpha)
[OK] certificate accepted
```

A single `[FAIL]` line means the certificate was not accepted.
