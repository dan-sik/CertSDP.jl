# Release Showcases

These artifacts are small, data-only exact replay demos. They are intended to
show how CertSDP can verify positive-polynomial certificates after an
untrusted search or external modeling step has produced exact candidate data.

Run all four showcase checks from the repository root:

```bash
bin/certsdp verify --strict showcases/motzkin/motzkin_rational_function_sos.json
bin/certsdp verify --strict showcases/hilbert17/x2_plus_1_rational_function_sos.json
bin/certsdp verify --strict showcases/putinar/box_1_minus_x2y2.json
bin/certsdp verify --strict showcases/sostools/xy_square_cert.json
```

## 1. Motzkin Rational-Function SOS

`showcases/motzkin/motzkin_rational_function_sos.json` proves the dehomogenized
Motzkin polynomial

```text
M(x,y) = x^4 y^2 + x^2 y^4 + 1 - 3 x^2 y^2
```

by exact replay of

```text
(x^2 + y^2)^2 M(x,y) = sum_i q_i(x,y)^2.
```

The denominator is itself an explicit SOS square. The verifier checks only exact
rational polynomial expansion and coefficient equality.

## 2. Hilbert 17-Style Rational SOS

`showcases/hilbert17/x2_plus_1_rational_function_sos.json` is a compact schema
smoke test for the same rational-function SOS format:

```text
(x^2 + 1)^2 (x^2 + 1) = x^6 + 3x^4 + 3x^2 + 1.
```

The numerator is encoded as eight rational squares, avoiding irrational
coefficients.

## 3. Putinar/Schmuedgen-Style Assembly

`showcases/putinar/box_1_minus_x2y2.json` verifies a constrained inequality on
the box `1 - x^2 >= 0`, `1 - y^2 >= 0`:

```text
1 - x^2 y^2 = y^2(1 - x^2) + 1(1 - y^2).
```

The certificate schema supports SOS multipliers attached to products of named
constraints, so singleton products are Putinar-style and larger products are
Schmuedgen-style.

## 4. SOSTOOLS-Lite Exact Replay

`showcases/sostools/sostools_lite_xy_square.json` is a minimal neutral JSON
shape matching what a SOSTOOLS-side exporter can emit: variables, monomial
basis, polynomial, and Gram matrix. Convert and certify it with:

```bash
bin/certsdp convert-sostools showcases/sostools/sostools_lite_xy_square.json \
  --problem-out /tmp/xy_square_sos_gram.json \
  --solution-out /tmp/xy_square_gram_solution.json \
  --cert-out /tmp/xy_square_cert.json
bin/certsdp verify --strict /tmp/xy_square_cert.json
```
