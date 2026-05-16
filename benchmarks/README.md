# CertSDP Validation Fixtures

This directory contains exact fixtures used by the public validation suite.

Run:

```bash
bin/certsdp benchmark benchmarks/ --suite validation --budget validation
```

The default report path is:

```text
benchmarks/VALIDATION_REPORT.md
```

The validation suite covers rational LMIs, rank-deficient and weakly feasible
examples, algebraic certificates, certifier-generated algebraic pipelines, SOS
Gram certificates, SDPA import, JuMP/MOI extraction, SumOfSquares-style
extraction, numerical solve -> diagnose -> certify workflows, fake-certificate
rejection, and structured failure reports.

Each fixture directory contains `expected.json` plus the exact source data
needed by its workflow. Most cases use `problem.json` and `approx.json`; some
imported workflows intentionally use `problem.dat-s` or `source.jl`.

Generated certificates and extracted intermediates belong in
`benchmarks/generated/`, which is ignored by git.
