# Certificate Format

CertSDP certificates are JSON documents designed for exact replay. The schema is
data-only; it does not embed executable code.

## Certificate Types

Current certificate types are:

- `rational_psd_certificate`: an LMI feasible point over `QQ`;
- `block_rational_psd_certificate`: a shared rational feasible point for a
  multi-block `BlockLMIProblem`, with one exact PSD proof per block;
- `algebraic_psd_certificate`: an LMI feasible point over one real algebraic
  root representation;
- `block_algebraic_psd_certificate`: a shared algebraic feasible point for a
  multi-block `BlockLMIProblem`, with one exact algebraic PSD proof per block;
- `sos_gram_certificate`: an exact SOS Gram certificate with embedded rational
  PSD proof.

## Top-Level v1 Shape

This is an abridged example that shows the replay boundary. Complete required
fields and certificate-family variants are documented in [Schema v1.0](SCHEMA_V1.md).

```json
{
  "certsdp_certificate_version": "1.0",
  "certificate_type": "rational_psd_certificate",
  "certificate_id": "sha256:...",
  "problem_hash": "sha256:...",
  "problem": {
    "embedded": true,
    "type": "lmi_feasibility",
    "data": { "...": "problem schema v1.0" }
  },
  "solution": {
    "field": "QQ",
    "representation": "coordinates",
    "coordinates": {
      "x": "1/2",
      "y": "1/3"
    }
  },
  "proof": {
    "linear_constraints": {
      "method": "exact_substitution",
      "status": "claimed"
    },
    "psd": {
      "method": "principal_minors",
      "substituted_matrix": [["3/2", "0"], ["0", "4/3"]]
    }
  }
}
```

Proof fields are claims to replay, not trusted facts. The verifier recomputes
the substituted matrix, determinant data, Schur complement data, hashes, and
signs before accepting.

Use `certsdp verify --strict cert.json` for independent replay. Strict mode
accepts only schema v1.0 certificates with embedded problem hashes and complete
exact proof fields; it does not run or require numerical solvers, `msolve`, or
backend artifacts. See [Trust model](trust_model.md).

## Replay Anatomy

| JSON area | Audit question | Exact replay obligation |
| --- | --- | --- |
| Header | Is this a v1 certificate of a supported family? | Schema gate, certificate type gate, required field check. |
| Embedded problem | Is the certified problem the one being claimed? | Canonical problem parse and `problem_hash` recomputation. |
| Solution | Is the candidate exact? | Rational parse or algebraic root isolation plus coordinate reconstruction. |
| Linear/SOS obligations | Does the point satisfy the exact equations? | Exact LMI substitution or exact SOS coefficient matching. |
| PSD obligations | Is every PSD claim replayable? | Recompute minors, Schur complements, LDL pivots, block proofs, and algebraic signs. |
| Provenance | Where did the candidate come from? | Ignored for acceptance; useful only for diagnostics and reproducibility. |

## Rational Certificates

Rational solution coordinates are rational strings:

```json
{
  "field": "QQ",
  "representation": "coordinates",
  "coordinates": {
    "x": "1/2",
    "y": "1/3"
  }
}
```

PSD proof methods include `principal_minors`, `schur_zero`, `ldl`, and
`pivoted_ldl`.

## Blockwise Rational Certificates

Multi-block SDPA/JuMP problems use `block_rational_psd_certificate`. The
solution is a single shared rational coordinate vector, and the PSD proof is:

```json
{
  "method": "blockwise",
  "blocks": [
    {
      "block_index": 1,
      "method": "principal_minors",
      "substituted_matrix": [["1", "0"], ["0", "2"]],
      "data": {
        "principal_minors": []
      }
    }
  ]
}
```

The verifier recomputes each block substitution and each block proof. A failed
PSD proof reports the block index, proof method, and localized minor or pivot,
for example `block 2: principal_minors minor at indices [1, 2]`.

## Algebraic Certificates

Algebraic certificates encode one real algebraic root and coordinates as
rational functions of that root:

```json
{
  "field": "QQbar",
  "representation": "rur",
  "root_symbol": "t",
  "minimal_polynomial": "t^2 - 2",
  "root_interval": ["1", "3/2"],
  "coordinates": {
    "x": "t"
  }
}
```

The verifier checks that the interval isolates a unique real root and evaluates
all signs using certified interval refinement after exact zero tests.

For multi-block algebraic problems, `block_algebraic_psd_certificate` uses the
same solution block and stores a top-level `blockwise` PSD proof. Each block is
re-substituted from the original `BlockLMIProblem`; the verifier does not trust
the aggregate block-diagonal matrix used during candidate generation.

## Schur-Zero Proofs

A Schur-zero proof stores a pivot block, positive-block minors, and a claimed
zero Schur complement. For a decomposition:

```text
[ B  C ]
[ C' D ],
```

the verifier proves `B` is positive definite and recomputes
`D - C' inv(B) C` exactly as zero. This is useful for rank-deficient PSD
matrices where all full determinants vanish.

## SOS Gram Certificates

An SOS Gram certificate contains:

- the exact polynomial and monomial basis;
- a rational Gram matrix;
- coefficient-matching metadata;
- an embedded rational PSD certificate for the Gram matrix;
- optional rational square decomposition data.

`verify_sos` recomputes coefficient matching and Gram PSD. Non-diagonal Gram
matrices may include an exact rational square export when the LDL-based
factorization is safe. If no square decomposition is present, the Gram-only
certificate remains valid and must include a reason.

## Compatibility

`read_certificate` accepts current v1.0 certificates and legacy v0.1
certificates. `write_certificate` emits the public v1.0 schema for supported
certificate types.

For schema-level details, see [Schema v1.0](SCHEMA_V1.md).
