# Schema v1

CertSDP v1.0 JSON is data-only. It never embeds executable code, and verifier
acceptance comes from exact replay rather than trusting proof claims stored in
the file.

All rational numbers are rational strings such as `"0"`, `"-3"`, `"5/7"`.
Denominators must be positive and nonzero. Matrices are dense row-major arrays
of rational strings unless a frontend format, such as SDPA sparse, explicitly
uses another representation.

## Canonical Hashes

Problem and certificate hashes are SHA-256 identifiers written as
`"sha256:"` followed by 64 lowercase hex characters.

Problem hashes are computed from the canonical exact problem data, excluding
metadata and excluding any input hash field. Certificate hashes are computed
from canonical certificate data, excluding the top-level hash/certificate id
field. Writers emit canonical hashes; readers reject supplied hashes that do not
match recomputation.

External JSON writers do not need to supply a hash. If they do, it must match
CertSDP's canonicalization exactly. The easiest external workflow is to omit
hashes, read the file with `read_problem` or `read_certificate`, then re-emit it
with `write_problem` or `write_certificate`.

## Problem Schema v1.0

Top-level LMI feasibility problem JSON:

```json
{
  "certsdp_problem_version": "1.0",
  "type": "lmi_feasibility",
  "field": "QQ",
  "variables": ["x1", "x2"],
  "matrix_size": 2,
  "A0": [["1", "0"], ["0", "1"]],
  "A": [
    { "var": "x1", "matrix": [["1", "0"], ["0", "0"]] },
    { "var": "x2", "matrix": [["0", "0"], ["0", "1"]] }
  ],
  "metadata": {
    "created_by": "external-tool"
  },
  "hash": "sha256:..."
}
```

Required fields:

- `certsdp_problem_version`: exactly `"1.0"`.
- `type`: exactly `"lmi_feasibility"`.
- `field`: exactly `"QQ"`.
- `variables`: unique nonempty variable names in coefficient order.
- `matrix_size`: positive integer square matrix dimension.
- `A0`: symmetric `matrix_size` by `matrix_size` rational matrix.
- `A`: one object per variable. Each object has `var`, matching the variable at
  the same position, and `matrix`, a symmetric rational matrix.

Optional fields:

- `metadata`: JSON object ignored by exact verification.
- `hash`: canonical problem hash. Omit it unless you already know CertSDP's
  canonical hash.

Semantics:

```text
A(x) = A0 + x1 * A[1] + x2 * A[2] + ...
A(x) must be positive semidefinite for a feasible certificate.
```

## SDPA Sparse Frontend

`read_problem(path)` dispatches to the SDPA sparse frontend for `.dat-s`,
`.dats`, and `.sdpa` files. It returns a `BlockLMIProblem` for one or more PSD
blocks.

Supported SDPA input:

- one or more PSD blocks;
- diagonal blocks, encoded by negative block sizes;
- integers, exact rational tokens, and finite decimals converted exactly to
  rationals;
- sparse symmetric entries, with upper or lower triangular entries accepted.

SDPA stores `sum_i Fi xi - F0 >= 0`. CertSDP stores
`A0 + sum_i xi Ai >= 0`, so import maps `A0 = -F0`. SDPA-specific helper
functions are internal; external code should use `read_problem` and
`write_problem`.

Block problems can also be emitted as JSON schema v1.0 with
`type = "block_lmi_feasibility"`. They store shared variables, objective data,
`block_struct`, and one exact LMI block per PSD or diagonal block.

## Certificate Schema v1.0

Top-level LMI certificate:

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
      "x1": "1/2",
      "x2": "1/3"
    }
  },
  "rank_profile": {
    "status": "not_recorded",
    "method": "not_recorded",
    "pivot_block": []
  },
  "proof": {
    "linear_constraints": {
      "method": "exact_substitution",
      "status": "claimed"
    },
    "psd": {
      "method": "principal_minors",
      "substituted_matrix": [["3/2", "0"], ["0", "4/3"]],
      "principal_minors": [
        { "indices": [1], "determinant": "3/2" },
        { "indices": [2], "determinant": "4/3" },
        { "indices": [1, 2], "determinant": "2" }
      ]
    }
  },
  "provenance": {
    "certsdp_version": "1.0.0",
    "julia_version": "...",
    "schema_version": "1.0"
  },
  "verification": {
    "verifier_version": "1.0.0",
    "verified_at_creation": null
  }
}
```

Required top-level fields:

- `certsdp_certificate_version`: exactly `"1.0"`.
- `certificate_type`: one of `rational_psd_certificate`,
  `block_rational_psd_certificate`, `algebraic_psd_certificate`, or
  `sos_gram_certificate`.
- `certificate_id`: canonical certificate hash.
- `problem_hash`: canonical hash of the embedded problem.
- `problem`: embedded problem object; v1.0 LMI certificates require
  `"embedded": true`, `"type": "lmi_feasibility"`, and `data`.
- `solution`: exact solution representation.
- `proof`: exact proof data. The verifier recomputes proof facts before
  accepting.
- `provenance`: JSON object describing tools that produced the candidate.
- `verification`: JSON object describing the verifier version at creation time.

### Rational Solutions

Rational LMI solution block:

```json
{
  "field": "QQ",
  "representation": "coordinates",
  "coordinates": {
    "x1": "1/2",
    "x2": "1/3"
  }
}
```

Every problem variable must appear exactly once in `coordinates`.

### Blockwise Rational Certificates

`block_rational_psd_certificate` embeds a `block_lmi_feasibility` problem and a
shared rational coordinate vector. Its PSD proof has `method = "blockwise"` and
a `blocks` array. Each block entry includes `block_index`, `block_kind`,
`matrix_size`, and a complete per-block exact PSD proof using
`principal_minors`, `schur_zero`, or `ldl`.

Strict verify replays every block independently and rejects numerical,
backend-dependent, or approximate proof fields. PSD failures report block
index, method, and the failed minor or pivot.

### Algebraic Solutions

Algebraic LMI solution block:

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

`root_interval` is a rational isolating interval for the selected real root of
`minimal_polynomial`. Coordinates are rational functions in `t`, represented by
the same parser used by the verifier. The verifier checks the root and exact
substitution before checking PSD.

### PSD Proofs

Current PSD proof methods:

- `principal_minors`: all nonempty principal-minor determinants are
  nonnegative.
- `schur_zero`: a pivot block is positive definite and the exact Schur
  complement is zero.
- `ldl`: exact LDL-style pivots, including zero-pivot coupling checks.
- `pivoted_ldl`: exact pivoted LDL proof data. Pivot indices are replayed and
  may be nonsequential; pivots and residual coupling checks are recomputed over
  `QQ` or `QQ(alpha)`.

Older v1-compatible certificates may place method-specific fields directly
under `proof.psd`; current writers also include a `data` block. Readers accept
both shapes. In every case, `verify` recomputes the substituted matrix,
determinants, pivots, Schur complement, and signs.

## SOS Gram Certificate Schema v1.0

Minimal SOS Gram certificate:

```json
{
  "certsdp_certificate_version": "1.0",
  "certificate_type": "sos_gram_certificate",
  "certificate_id": "sha256:...",
  "problem_hash": "sha256:...",
  "sos_problem": {
    "type": "sos_gram_feasibility",
    "field": "QQ",
    "variables": ["x"],
    "basis": [[0], [1]],
    "polynomial": [
      { "exponents": [2], "coefficient": "1" },
      { "exponents": [0], "coefficient": "1" }
    ],
    "hash": "sha256:..."
  },
  "solution": {
    "type": "rational_gram_matrix",
    "gram_matrix": [["1", "0"], ["0", "1"]]
  },
  "coefficient_proof": {
    "method": "exact_coefficient_matching",
    "matches": []
  },
  "decomposition": {
    "status": "squares",
    "method": "diagonal_rational_square_root",
    "squares": []
  },
  "proof": {
    "coefficient_matching": {
      "method": "exact_coefficient_matching",
      "status": "claimed",
      "equations": 0
    },
    "psd": {
      "method": "embedded_rational_psd_certificate",
      "certificate_id": "sha256:..."
    }
  },
  "provenance": {
    "certsdp_version": "1.0.0",
    "julia_version": "...",
    "schema_version": "1.0",
    "source": "sos_gram_workflow"
  },
  "verification": {
    "verifier_version": "1.0.0",
    "verified_at_creation": null
  },
  "lmi_certificate": {
    "...": "embedded rational PSD certificate for the Gram matrix"
  }
}
```

For external writers, the essential data are `sos_problem`, `solution`, exact
coefficient-matching metadata, and an embedded rational PSD certificate for the
Gram matrix. `verify_sos` recomputes the polynomial represented by `v'Qv`,
checks it against the target polynomial, verifies the embedded PSD certificate,
and accepts `decomposition.status = "gram_only"` when no square decomposition is
claimed. Gram-only decomposition records must include a human-readable `reason`;
square decompositions are re-expanded exactly and compared with the target
polynomial.

## Positive-Polynomial Showcase Certificates

Schema v1.0 also accepts two exact replay showcase certificate types:

- `rational_function_sos_certificate`
- `positivstellensatz_certificate`

These are verifier formats, not solver formats. They store explicit rational
polynomial squares and exact coefficient-matching metadata. The strict verifier
re-expands every square and recomputes the identity before accepting.

### Rational-Function SOS

This certificate proves a polynomial claim by checking:

```text
denominator_sos * p == numerator_sos
```

where both sides are represented as sums of explicit rational polynomial
squares. The denominator SOS must not be the zero polynomial.

Minimal shape:

```json
{
  "certsdp_certificate_version": "1.0",
  "certificate_type": "rational_function_sos_certificate",
  "certificate_id": "sha256:...",
  "problem_hash": "sha256:...",
  "problem": {
    "embedded": true,
    "type": "rational_function_sos_claim",
    "data": {
      "certsdp_problem_version": "1.0",
      "type": "rational_function_sos_claim",
      "field": "QQ",
      "variables": ["x", "y"],
      "polynomial": [
        {"exponents": [4, 2], "coefficient": "1"}
      ],
      "hash": "sha256:..."
    }
  },
  "solution": {
    "field": "QQ",
    "representation": "rational_function_sos",
    "numerator_sos": {
      "method": "explicit_rational_squares",
      "squares": [[{"exponents": [1, 0], "coefficient": "1"}]]
    },
    "denominator_sos": {
      "method": "explicit_rational_squares",
      "squares": [[{"exponents": [0, 0], "coefficient": "1"}]]
    }
  },
  "coefficient_proof": {
    "method": "exact_coefficient_matching",
    "identity": "denominator_times_target_equals_numerator",
    "matches": []
  },
  "proof": {
    "identity": {
      "method": "exact_coefficient_matching",
      "status": "claimed",
      "equations": 0
    },
    "sos": {
      "method": "explicit_rational_squares",
      "numerator_squares": 1,
      "denominator_squares": 1
    }
  },
  "provenance": {"schema_version": "1.0"},
  "verification": {"verifier_version": "1.0.0"}
}
```

### Positivstellensatz Assembly

This certificate proves a constrained inequality by checking an exact identity:

```text
f = sum_j sigma_j * product(g_i for i in product_j)
```

Every `sigma_j` is an explicit SOS. Singleton products encode Putinar-style
terms; longer products encode Schmuedgen-style terms.

The public showcase
`showcases/putinar/box_1_minus_x2y2.json` verifies:

```text
1 - x^2 y^2 = y^2(1 - x^2) + 1(1 - y^2).
```

## Failure Report Schema v1.0

Structured non-certification report:

```json
{
  "certsdp_failure_report_version": "1.0",
  "status": "not_certified",
  "failure_type": "RankUnstableFailure",
  "reason": "rank_profile_unstable",
  "summary": "rank gap too small",
  "stage": "rank_profile",
  "details": {
    "candidate_ranks": [2, 3],
    "gap": "1e-3"
  },
  "suggestions": [
    "rerun the numerical solver with higher precision"
  ],
  "provenance": {
    "certsdp_version": "1.0.0",
    "julia_version": "...",
    "schema_version": "1.0"
  }
}
```

Failure reports are diagnostic. They are not proof objects. When a backend
fails, `details.backend_failure` may include stdout, stderr, command,
provenance, timeout status, and artifact paths.

## v0.1 Compatibility

Legacy v0.1 LMI problem JSON is accepted by `read_problem`. Rewriting it with
`write_problem` emits schema v1.0 JSON.

The CLI exposes the same boundary:

```bash
bin/certsdp schema validate problem-v1.json --kind problem
bin/certsdp migrate legacy-problem.json --out problem-v1.json --kind problem
```

Legacy v0.1 rational, algebraic, and SOS Gram certificates are accepted by
`read_certificate` when their exact data are valid. Rewriting them with
`write_certificate` emits schema v1.0 JSON.

```bash
bin/certsdp schema validate cert-v1.json --kind certificate
bin/certsdp schema migrate legacy-cert.json --out cert-v1.json --kind certificate
```

The old v0.1 helper formats remain readable for migration, but new external
tools should write the v1.0 shapes documented above.
