# LMI Tutorial

CertSDP works with feasibility problems of the form:

```text
A(x) = A0 + x1 A1 + ... + xn An >= 0,
```

where every matrix entry is exact rational data.

## Rational LMI JSON

The quickstart problem is stored in `examples/rational_problem.json`. Its legacy
v0.1 wrapper is still accepted by `read_problem`:

```json
{
  "certsdp_version": "0.1",
  "problem": {
    "type": "lmi_feasibility",
    "field": "QQ",
    "matrix_size": 2,
    "num_variables": 2,
    "vars": ["x", "y"],
    "A0": [["1", "0"], ["0", "1"]],
    "A": [
      [["1", "0"], ["0", "0"]],
      [["0", "0"], ["0", "1"]]
    ]
  }
}
```

The matching exact solution file is:

```json
{
  "certsdp_version": "0.1",
  "solution": {
    "type": "rational",
    "x": ["1/2", "1/3"]
  }
}
```

Run:

```bash
bin/certsdp certify examples/rational_problem.json \
  --solution examples/rational_solution.json \
  --out /tmp/certsdp-rational-cert.json
bin/certsdp verify --strict /tmp/certsdp-rational-cert.json
bin/certsdp inspect /tmp/certsdp-rational-cert.json
```

The verifier recomputes the substituted matrix and PSD proof over `QQ`.

## Problem JSON

New integrations should write problem JSON through the public API:

```julia
using CertSDP

P = read_problem("examples/rational_problem.json")
write_problem("/tmp/certsdp-rational-problem.json", P)
Q = read_problem("/tmp/certsdp-rational-problem.json")
Q isa LMIProblem
```

## Julia API

```julia
using CertSDP

P = read_problem("examples/rational_problem.json")
result = certify(P, [1//2, 1//3])
verify(result)
write_certificate("/tmp/certsdp-rational-cert.json", result)
verify(read_certificate("/tmp/certsdp-rational-cert.json"))
```

## Algebraic LMI

The algebraic example is feasible at `x = sqrt(2)`:

```text
A(x) = [x 1; 1 x/2] >= 0.
```

The approximate solution file guides candidate selection only. Install `msolve`
or set `CERTSDP_MSOLVE`, then run:

```bash
bin/certsdp certify examples/algebraic_problem.json \
  --solution examples/algebraic_approx.json \
  --out /tmp/certsdp-algebraic-cert.json \
  --timeout 300
bin/certsdp verify --strict /tmp/certsdp-algebraic-cert.json
```

Typical accepted verifier output ends with:

```text
[OK] Schur-zero PSD verified over QQ(alpha)
[OK] certificate accepted
```

The backend output is candidate data. The final certificate is accepted only
after exact root isolation, substitution, equality checks, and PSD verification.

For multi-block SDPA/JuMP-style problems, `certify` accepts the same shared
approximate solution vector. Algebraic candidate generation may internally use
the aggregate block-diagonal LMI, but the certificate stores the original block
problem and the verifier replays one exact PSD proof per block.

## Choosing A PSD Proof

`--psd-method auto` is the default. You can request a method explicitly:

```bash
bin/certsdp certify examples/algebraic_problem.json \
  --solution examples/algebraic_approx.json \
  --psd-method schur_zero \
  --out /tmp/certsdp-algebraic-schur-cert.json
```

Use `principal_minors` for very small full-rank examples. Use `schur_zero` when
the solution is rank-deficient and a positive pivot block with exact zero Schur
complement is expected. Use `pivoted_ldl` when exact pivoting is preferable to
all principal minors. The verifier rejects proof data that does not replay.
