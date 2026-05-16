# Why Rational Rounding Fails

Classical SDP certificate workflows often take a floating-point solution,
round every entry to a nearby rational number, and then check the exact rational
matrix. This works when the feasible set has rational points near the numerical
solution and the matrix is not too close to the boundary of the PSD cone.

Degenerate SDP examples violate both assumptions.

## A Minimal Failure Pattern

Consider a rational LMI whose feasible set forces a coordinate to be
`sqrt(2)`. CertSDP's algebraic examples encode this pattern with two PSD
blocks:

```text
[ x   1 ] >= 0        forces x >= sqrt(2)
[ 1  x/2]

[ 2   x ] >= 0        forces |x| <= sqrt(2)
[ x   1 ]
```

Together they imply `x = sqrt(2)`. No rational value of `x` is feasible.
Rounding the approximate value `1.414213562...` to any rational nearby still
breaks at least one of the two blocks.

## Why Floating-Point Evidence Is Not Enough

Floating-point eigenvalues can say a candidate matrix is nearly PSD, but they
cannot prove exact PSD at a boundary point. Near a zero eigenvalue, a tiny
rounding or modeling error can change feasibility. CertSDP therefore treats
floating-point data only as:

- a way to choose a rank profile,
- a way to select a nearby algebraic root,
- a diagnostic to explain failures.

It never treats numerical eigenvalues as proof.

## What CertSDP Does Instead

For algebraic examples, CertSDP represents the solution as:

```text
alpha^2 - 2 = 0, alpha in [1, 3/2]
x = alpha
```

Then it verifies:

- the LMI substitution exactly in `QQ(alpha)`,
- all required equalities by polynomial remainders modulo the root polynomial,
- PSD either by all principal minors or by a Schur-zero facial block proof,
- algebraic signs using isolating intervals and certified refinement.

Rational rounding is still useful when it succeeds. It is just not the
foundation of the verifier.
