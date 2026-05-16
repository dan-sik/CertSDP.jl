# CertSDP Examples

Run commands from the repository root.

## Rational Certificate Flow

This example has an exact rational feasible point, so `certsdp certify` builds a
Type R certificate directly from `examples/rational_solution.json`.

```bash
bin/certsdp certify examples/rational_problem.json \
  --solution examples/rational_solution.json \
  --out examples/rational_cert.json

bin/certsdp verify --strict examples/rational_cert.json
bin/certsdp inspect examples/rational_cert.json
```

Expected verifier ending:

```text
[OK] PSD verified over QQ
[OK] certificate accepted
```

## Algebraic Certificate Flow

This toy degenerate LMI is feasible at `x = sqrt(2)`. The approximate file only
guides candidate selection; the generated certificate is accepted only after
exact algebraic verification.

Install `msolve` or point `CERTSDP_MSOLVE` at an executable first.

```bash
bin/certsdp certify examples/algebraic_problem.json \
  --solution examples/algebraic_approx.json \
  --out examples/algebraic_cert.json

bin/certsdp verify --strict examples/algebraic_cert.json
bin/certsdp inspect examples/algebraic_cert.json
```

Expected verifier ending:

```text
[OK] Schur-zero PSD verified over QQ(alpha)
[OK] certificate accepted
```

If `msolve` is unavailable, certification exits with code `3` and explains that
the optional backend was not found. Verification failures exit with code `1`;
malformed input or command usage errors exit with code `2`.

## SOS Gram Certificate Flow

The SOS Gram workflow certifies
`x^2 + 1 = [1, x]' * I * [1, x]`; coefficient matching and Gram PSD are both
checked exactly.

```bash
bin/certsdp certify-sos examples/sos/gram_x2_plus_1.json \
  --solution examples/sos/gram_x2_plus_1_solution.json \
  --out examples/sos/gram_x2_plus_1_cert.json

bin/certsdp verify --strict examples/sos/gram_x2_plus_1_cert.json
bin/certsdp inspect examples/sos/gram_x2_plus_1_cert.json
```

Expected verifier ending:

```text
[OK] SOS coefficient matching is exact
[OK] Gram certificate verified over QQ
[OK] SOS Gram certificate accepted
```

There are three ready-to-run SOS examples under `examples/sos/`, including a
non-diagonal Gram example. The SumOfSquares/JuMP dependency remains optional;
when loaded, the extension adds `extract_sos_gram_sdp` and `certify_sos` methods
for exact Gram matrices, constraint references, and simple SOS models.

## Validation Examples

The public validation suite is runnable from the repository root:

```bash
bin/certsdp benchmark benchmarks/ --suite validation
```

This writes `benchmarks/VALIDATION_REPORT.md`. The validation suite includes
rational, algebraic, SOS, SDPA, JuMP/MOI extraction, SumOfSquares-style
extraction, and fake-certificate rejection cases.

## SDPA Sparse Examples

SDPA sparse fixtures live under `examples/sdpa/`:

```julia
using CertSDP

P = read_problem("examples/sdpa/mixed_blocks_decimal.dat-s")
write_problem("examples/sdpa_roundtrip.dat-s", P)
```

The examples cover one PSD block, multiple PSD blocks, diagonal blocks, exact
decimal input, and zero coefficient matrices. SDPA paths read through
`read_problem` return a `BlockLMIProblem`.

## Multi-Block Certificate Flow

CertSDP supports blockwise rational certificates for multi-block SDPA/JuMP
problems:

```bash
bin/certsdp certify examples/sdpa/two_blocks.dat-s \
  --solution examples/multiblock/sdpa_two_blocks_solution.json \
  --out examples/multiblock/two_blocks_cert.json

bin/certsdp verify --strict examples/multiblock/two_blocks_cert.json
bin/certsdp inspect examples/multiblock/two_blocks_cert.json
```

The verifier reports each block independently. If a block fails PSD replay, the
failure includes the block index, proof method, and failed minor or pivot.
