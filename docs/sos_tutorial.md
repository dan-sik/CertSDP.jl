# SumOfSquares Tutorial

CertSDP certifies small exact SOS Gram certificates:

```text
p(x) = v(x)' Q v(x),  Q >= 0.
```

The trusted checks are coefficient matching and Gram PSD verification. Numerical
solver output may suggest a Gram matrix, but it is not proof.

## Exported Gram JSON

The fastest SOS path certifies `x^2 + 1` with basis `[1, x]` and Gram matrix
`I`.

```bash
bin/certsdp certify-sos examples/sos/gram_x2_plus_1.json \
  --solution examples/sos/gram_x2_plus_1_solution.json \
  --out /tmp/certsdp-sos-x2-plus-1-cert.json
bin/certsdp verify --strict /tmp/certsdp-sos-x2-plus-1-cert.json
bin/certsdp inspect /tmp/certsdp-sos-x2-plus-1-cert.json
bin/certsdp export-sos /tmp/certsdp-sos-x2-plus-1-cert.json \
  --out /tmp/certsdp-sos-x2-plus-1-decomposition.json
bin/certsdp export-sos /tmp/certsdp-sos-x2-plus-1-cert.json \
  --out /tmp/certsdp-sos-x2-plus-1-decomposition.txt \
  --format text
bin/certsdp export-sos /tmp/certsdp-sos-x2-plus-1-cert.json \
  --out /tmp/certsdp-sos-x2-plus-1-decomposition.tex \
  --format latex
bin/certsdp export-sos /tmp/certsdp-sos-x2-plus-1-cert.json \
  --out /tmp/certsdp-sos-x2-plus-1-replay.sage \
  --format sage
bin/certsdp export-sos /tmp/certsdp-sos-x2-plus-1-cert.json \
  --out /tmp/certsdp-sos-x2-plus-1-replay.jl \
  --format julia
```

Two additional runnable fixtures are included:

```bash
bin/certsdp certify-sos examples/sos/gram_xy_square.json \
  --solution examples/sos/gram_xy_square_solution.json \
  --out /tmp/certsdp-sos-xy-square-cert.json

bin/certsdp certify-sos examples/sos/gram_x4_plus_1.json \
  --solution examples/sos/gram_x4_plus_1_solution.json \
  --out /tmp/certsdp-sos-x4-plus-1-cert.json
```

Each generated SOS certificate embeds a rational PSD certificate for the Gram
matrix and exact coefficient-matching metadata.

Non-diagonal Gram matrices are first certified as Gram certificates. When exact
rational LDL pivots can be safely expanded into rational squares, CertSDP also
exports a square decomposition such as `(x + y)^2`. If the factorization would
be too large or ambiguous, the certificate falls back to a Gram-only export; the
verifier still checks `p = v'Qv` and `Q >= 0` exactly.

## Julia API

```julia
using CertSDP

result = certify_sos("examples/sos/gram_x2_plus_1.json", [1 0; 0 1])

if verify_sos(result)
    verify_sos(result)
    write_certificate("/tmp/certsdp-sos-cert.json", result)
else
    diagnose(result)
end
```

## SumOfSquares.jl Workflow

The extension loads when `JuMP`, `SumOfSquares`, and
`MultivariatePolynomials` are available. The model must expose exact rational
Gram data or you must provide an exact Gram matrix.

```julia
using CertSDP
using DynamicPolynomials
using SumOfSquares

@polyvar x
model = SOSModel()
constraint_ref = @constraint(model, x^2 + 1 in SOSCone())

result = certify_sos(model;
                     gram_matrices=[[1//1 0//1; 0//1 1//1]],
                     reconstruct_floats=true,
                     tolerance=1e-12)
verify_sos(result)
```

Some SumOfSquares/JuMP model shapes store polynomial coefficients in a
floating-point MOI function even when the supplied Gram matrix is exact. That is
why the example opts into reconstruction with a tolerance. If a solved model
returns a floating-point Gram matrix, reconstruction is also explicit:

```julia
Q = CertSDP.reconstruct_rational_gram_matrix(float_Q; tolerance=1e-12)
result = certify_sos(problem, Q)
```

The SumOfSquares extractor has the same opt-in guard:

```julia
extract_sos_gram_sdp(gram; reconstruct_floats=true, tolerance=1e-12)
```

CertSDP never silently accepts floating-point coefficients as proof; the
reconstructed rational candidate is still checked by exact coefficient matching
and exact PSD verification.

## SOSTOOLS-Lite Replay

The release showcase includes a minimal neutral JSON shape for SOSTOOLS-style
exports: variables, monomial basis, target polynomial, and an exact Gram
matrix. Convert it into ordinary CertSDP SOS Gram artifacts with:

```bash
bin/certsdp convert-sostools showcases/sostools/sostools_lite_xy_square.json \
  --problem-out /tmp/xy_square_sos_gram.json \
  --solution-out /tmp/xy_square_gram_solution.json \
  --cert-out /tmp/xy_square_cert.json
bin/certsdp verify --strict /tmp/xy_square_cert.json
```

The converter is intentionally small. It does not trust SOSTOOLS, MATLAB, or an
SDP solver log; it only translates exact rational Gram data into the existing
SOS Gram verifier path.

## What Is Verified

`verify_sos` recomputes:

- the SOS certificate hash;
- every coefficient equation in `p = v'Qv`;
- the embedded rational PSD certificate for `Q`;
- optional rational square decomposition data when it is safe to export.

When no exact square decomposition is exported, the Gram-only certificate is
still a valid SOS certificate.

## Decomposition Exports

`export_sos_decomposition` and `certsdp export-sos` are public replay paths for
already verified SOS certificates. Supported formats are:

- `json`: structured squares or Gram-only data;
- `text`: compact readable exact decomposition;
- `latex`: display-ready polynomial and square/Gram identity;
- `sage`: a Sage script that reconstructs the exact rational identity;
- `julia`: a Julia script using rational arithmetic for replay.

The export step verifies the certificate before writing. If a rational square
decomposition is unavailable, the Sage and Julia replay scripts reconstruct the
Gram identity `p = v'Qv` exactly instead of inventing square factors.
