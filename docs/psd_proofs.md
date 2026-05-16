# PSD Proof Planner

`choose_psd_proof(A, rank_profile; options...)` selects an exact PSD proof for a
substituted matrix. Rank profiles and pivot hints are only used to choose a
candidate method; acceptance still comes from exact replay.

Supported methods:

- `principal_minors`: checks every nonempty principal minor exactly, using
  Bareiss fraction-free determinants rather than recursive expansion.
- `schur_zero`: proves a pivot block is positive definite and the exact Schur
  complement is zero.
- `blockwise`: verifies each PSD block independently and reports the failing
  block.
- `ldl`: exact LDL-style fallback with nonnegative pivots and strict checks for
  zero pivots.
- `pivoted_ldl`: fraction-free pivoted LDL replay. This is the large-matrix
  fallback used by `method=:auto` when principal minors would be too expensive
  or too sensitive to variable ordering.

Pseudo-code for method selection inside a caller:

```text
plan = choose_psd_proof(A, rank_profile; method=:auto)
plan.status === :accepted || error(plan.failure.message)
```

Pseudo-code for multiple PSD blocks:

```text
blocks = substitute(block_problem, x)
plan = choose_psd_proof(blocks; method=:blockwise, block_method=:auto)
```

Failures are localized. A rejected plan carries `plan.failure.block_index`,
`location`, `indices`, and `pivot_index`, so callers can say things like
“block 2, minor [1, 3] failed” or “pivot 4 failed”. No method uses numerical
eigenvalues inside `verify(cert)`.

For algebraic matrices, determinant and pivot signs are decided by the
certified algebraic sign layer. The verifier first performs exact zero tests in
`QQ(alpha)`, then uses root isolation/refinement only to decide signs; backend
logs, approximate eigenvalues, and the proof method stored in a certificate are
not trusted facts.
