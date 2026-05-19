# CertSDP Validation Report

- Suite: `benchmarks`
- Public suite: `validation`
- Status: passed
- Trust boundary: exact replay from certificate data
- Solver policy: strict verification does not run an SDP solver
- Artifact policy: JSON export, replay, minimization, diagnostics, and hashes

## Executive Summary

CertSDP validates the path from SDP/SOS certificate evidence to exact
proof-carrying artifacts. The suite checks that accepted artifacts replay with
exact arithmetic, that malformed or mismatched proof data is rejected, and that
compressed artifacts preserve the same mathematical obligations as their source
certificates.

This report is written for readers who need to decide whether a certificate can
be archived, reviewed, or reused in another proof pipeline. The answer is not a
solver residual. The answer is an artifact that replays.

## Evidence At A Glance

| Reader question | Current evidence | Why it matters |
| --- | --- | --- |
| Do accepted certificates replay exactly? | Strict verification recomputes hashes, identities, field arithmetic, quotient reductions, and PSD obligations. | Acceptance is independent of solver status. |
| Are bad artifacts rejected? | Mutations of field data, sparse structure, quotient rules, affine identities, hashes, and adapter formats are rejected. | The suite tests the trust boundary, not only successful examples. |
| Does the compiler preserve structure? | Sparse, block, symmetry-reduced, low-rank, and noncommutative artifacts are checked without dense global expansion. | The certificate remains close to the workflow that produced it. |
| Can certificates be minimized safely? | Minimized artifacts must replay and carry equivalence evidence. | Shorter artifacts are useful only if they keep the proof. |
| Can external workflows be normalized? | SumOfSquares-like, sparse-SOS-like, noncommutative-like, and clustered-low-rank-like artifacts enter through a common IR. | CertSDP acts as a certificate compiler, not a collection of unrelated verifiers. |

## Validated Certificate Families

| Family | Replay obligation |
| --- | --- |
| Rational LMI and block LMI | Exact substitution, exact affine equality, exact PSD proof replay. |
| Algebraic LMI and SOS Gram | Field reconstruction, root/embedding data, exact signs, and algebraic PSD replay. |
| Sparse SOS / Putinar-style identities | Sparse coefficient maps, localizing multipliers, clique labels, and block PSD proofs. |
| Symmetry-reduced low-rank SDP | Reduced affine identity, transform metadata, exact low-rank factorization, and original-problem replay metadata. |
| Noncommutative trace certificates | Word canonicalization, star involution, trace cyclic equivalence, quotient relations, and coefficient identity. |
| Infeasibility certificates | Exact Farkas-style affine contradiction and PSD slack verification. |
| External artifacts | Import, normalization, common JSON export, minimization, and solver-free replay. |

## Rejection Evidence

| Mutation surface | Expected outcome |
| --- | --- |
| Problem or certificate hash | Rejected before mathematical replay. |
| Rational coordinate or affine multiplier | Rejected by exact identity mismatch. |
| Algebraic field declaration | Rejected by field or minimality checks. |
| Sparse clique or localizing constraint label | Rejected by structure or localizing-identity checks. |
| Symmetry transform metadata | Rejected by reconstruction metadata checks. |
| Noncommutative commutation or trace quotient | Rejected by NC/trace identity checks. |
| PSD block factor or rank data | Rejected by exact PSD replay. |
| Unsupported external format | Rejected before entering the trusted proof surface. |

## Reproduction

Run from the repository root:

```bash
bin/certsdp doctor
julia --project scripts/run_validation.jl
```

`doctor` records local runtime and optional tool availability. Validation may
use optional tools to construct candidates, but strict verification accepts
only by exact replay of the resulting certificate.

For ad hoc benchmark output:

```bash
bin/certsdp benchmark benchmarks/ --suite validation --out /tmp/certsdp-validation-report.md
```

Generated certificates and failure reports belong under
`benchmarks/generated/`, which is ignored by git because the artifacts are
reproducible.

## Trust Notes

- Strict replay is data-only.
- Numerical solver logs, residuals, approximate eigenvalues, backend
  transcripts, cache hits, and provenance notes are not proof.
- The verifier accepts exact rational and algebraic arithmetic, exact
  polynomial or affine identities, exact quotient reduction, exact PSD replay,
  and matching semantic hashes.
- Expected failures are part of the validation contract. They demonstrate that
  invalid artifacts are rejected with structured diagnostics.

## Current Scope

The shipped validation suite exercises the certificate compiler, verifier,
import normalization, minimization, and rejection behavior using reproducible
fixtures in this repository and reference-backed artifacts under `references/`.
Future public benchmark packs can add native upstream outputs from additional
solver ecosystems without changing the acceptance rule: external tools may
produce candidates, but exact replay is what accepts a certificate.
