# SDPA Import And Export

CertSDP can import and export SDPA sparse files so external SDP workflows can
feed exact rational LMI data into the verifier and certificate pipeline.

## Basic Use

```julia
using CertSDP

B = read_problem("examples/sdpa/two_blocks.dat-s")
write_problem("/tmp/certsdp-two-blocks-roundtrip.dat-s", B)
read_problem("/tmp/certsdp-two-blocks-roundtrip.dat-s") isa BlockLMIProblem
```

`read_problem(path)` dispatches to the SDPA frontend for `.dat-s`, `.dats`, and
`.sdpa` paths.

## Supported SDPA Sparse Form

CertSDP supports:

- one or more PSD blocks;
- SDPA diagonal blocks, encoded by negative block sizes;
- exact integers and rational strings;
- finite decimal or scientific tokens converted exactly to rationals;
- sparse upper or lower triangular input.

SDPA uses:

```text
sum_i F_i x_i - F_0 >= 0.
```

CertSDP stores:

```text
A0 + sum_i x_i Ai >= 0.
```

Import therefore maps `A0 = -F0` and `Ai = Fi`.

## Single-Block Certification

The historical certifier path expects one PSD block:

```julia
using CertSDP

B = read_problem("examples/sdpa/single_block.dat-s")
B isa BlockLMIProblem
```

For multi-block files, keep the `BlockLMIProblem` for import/export,
diagnostics, and blockwise proof planning.

## Exact Number Parsing

Examples:

```text
0.125  ->  1/8
1e-3   ->  1/1000
2D+4   ->  20000
```

Malformed numeric text, zero denominators, invalid block indices, conflicting
duplicate entries, and off-diagonal entries in diagonal blocks raise
`ArgumentError`.

## Roundtrip Contract

`write_problem(path, problem)` emits a canonical sparse form when `path` has an
SDPA extension:

- matrices appear in order `F0, F1, ...`;
- blocks appear in block order;
- PSD blocks use upper-triangular entries;
- diagonal blocks write only diagonal entries;
- rationals are normalized as integers or `p/q` strings.

The fixture directory `examples/sdpa/` covers single PSD blocks, multiple PSD
blocks, diagonal blocks, exact decimal input, and zero coefficient matrices.
