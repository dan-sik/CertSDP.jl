# Quickstart

This page is the fastest complete path from a fresh checkout to an accepted
certificate. It uses only exact rational data, so no optional backend is needed.

## One-Time Setup

```bash
julia --project -e 'using Pkg; Pkg.instantiate()'
```

## Certify And Verify

```bash
bin/certsdp certify examples/rational_problem.json \
  --solution examples/rational_solution.json \
  --out /tmp/certsdp-rational-cert.json

bin/certsdp verify --strict /tmp/certsdp-rational-cert.json
```

Expected verifier ending:

```text
[OK] PSD verified over QQ
[OK] certificate accepted
```

## Inspect The Certificate

```bash
bin/certsdp inspect /tmp/certsdp-rational-cert.json
```

You should see the certificate type, LMI size, variables, PSD proof method,
problem hash, and certificate hash.

## If Something Fails

Run `bin/certsdp doctor` first; it checks the local Julia environment, optional
tool discovery, and validation metadata. Make sure commands are run from the
repository root so `bin/certsdp` can use the project environment. The rational
quickstart does not need optional tools; the algebraic example below needs
`msolve` only for candidate generation.

## What Was Proved?

The example problem is:

```text
A(x, y) = [1 0; 0 1] + x [1 0; 0 0] + y [0 0; 0 1] >= 0.
```

The solution file gives `x = 1/2` and `y = 1/3`. CertSDP builds a rational
certificate and the verifier recomputes:

- exact substitution into the LMI;
- every principal minor over `QQ`;
- the certificate hash.

No floating-point arithmetic is used as proof.

## Next Steps

Try the SOS quick example:

```bash
bin/certsdp certify-sos examples/sos/gram_x2_plus_1.json \
  --solution examples/sos/gram_x2_plus_1_solution.json \
  --out /tmp/certsdp-sos-cert.json
bin/certsdp verify --strict /tmp/certsdp-sos-cert.json
```

Try the algebraic example if `msolve` is installed:

```bash
bin/certsdp certify examples/algebraic_problem.json \
  --solution examples/algebraic_approx.json \
  --out /tmp/certsdp-algebraic-cert.json
bin/certsdp verify --strict /tmp/certsdp-algebraic-cert.json
```
