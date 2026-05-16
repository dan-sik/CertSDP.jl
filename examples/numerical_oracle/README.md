# Numerical Oracle Examples

Run a fresh Clarabel approximation, inspect its max-rank face-search
diagnostics, then try to turn the candidate into an exact certificate:

```bash
bin/certsdp solve examples/numerical_oracle/sqrt2_problem.json \
  --out /tmp/certsdp-sqrt2-approx.json \
  --trace-objective maximize \
  --random-objective-trials 2

bin/certsdp diagnose examples/numerical_oracle/sqrt2_problem.json \
  --solution /tmp/certsdp-sqrt2-approx.json

bin/certsdp certify examples/numerical_oracle/sqrt2_problem.json \
  --solution /tmp/certsdp-sqrt2-approx.json \
  --out /tmp/certsdp-sqrt2-cert.json

bin/certsdp verify --strict /tmp/certsdp-sqrt2-cert.json
```

Clarabel is an optional numerical oracle. Its residuals, eigenvalues, rank
diagnostics, and solver status are never proof. The strict verifier accepts only
after exact replay of the generated certificate. Algebraic certification may
also require an optional `msolve` or Sage/msolve backend; verifier replay does
not.
