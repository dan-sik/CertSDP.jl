# Showcase Pack

This directory is a research-grade exact replay pack, not a solver benchmark.
The artifacts are data-only JSON certificates or neutral SOSTOOLS-lite exports.
Every accepted certificate is replayed by CertSDP strict mode using exact
arithmetic; solver logs, floating-point residuals, and backend state are not
trusted.

Run the full pack:

```bash
julia --project showcases/verify_all.jl
```

Regenerate all JSON artifacts from CertSDP constructors:

```bash
julia --project scripts/generate_showcase_pack.jl
```

The machine-readable inventory is [manifest.json](manifest.json).

## Track 1: Non-SOS Classics

These artifacts target the cultural entry points of the SOS literature:
nonnegative forms that are not plain polynomial SOS, but become replayable
through denominator/SOS identities or closely related threshold artifacts.

| Artifact | Exact replay |
| --- | --- |
| [motzkin_affine_rational_function_sos.json](non_sos_classics/motzkin_affine_rational_function_sos.json) | `(x^2 + y^2)^2 M(x,y) = sum q_i^2` |
| [motzkin_homogeneous_rational_function_sos.json](non_sos_classics/motzkin_homogeneous_rational_function_sos.json) | Homogenized ternary Motzkin denominator replay |
| [choi_lam_cyclic_sextic_rational_function_sos.json](non_sos_classics/choi_lam_cyclic_sextic_rational_function_sos.json) | `(x^2+y^2+z^2) S(x,y,z) = sum q_i^2` |
| [choi_lam_quartic_rational_function_sos.json](non_sos_classics/choi_lam_quartic_rational_function_sos.json) | Quaternary Choi-Lam quartic with rational denominator SOS |
| [robinson_threshold_perturbation_rational_sos.json](non_sos_classics/robinson_threshold_perturbation_rational_sos.json) | Robinson-family sextic plus the exact `1/8` diagonal perturbation at the SOS threshold |

The Robinson artifact is deliberately named as a threshold perturbation. It is
not presented as a Hilbert-17 denominator certificate for the unperturbed
Robinson form.

## Track 2: Hilbert 17 Rational SOS

The rational-function certificate format is intentionally simple:

```json
{
  "certificate_type": "rational_function_sos_certificate",
  "solution": {
    "representation": "rational_function_sos",
    "numerator_sos": "...",
    "denominator_sos": "..."
  },
  "coefficient_proof": {
    "identity": "denominator_times_target_equals_numerator"
  }
}
```

The strict verifier checks three facts:

1. the denominator block is an explicit SOS and is not zero;
2. the numerator block is an explicit SOS;
3. exact coefficient matching proves `denominator * p == numerator`.

Representative files:

```bash
bin/certsdp verify --strict showcases/hilbert17/x2_plus_1_minimal.json
bin/certsdp verify --strict showcases/hilbert17/dense_denominator_protocol.json
bin/certsdp verify --strict showcases/hilbert17/motzkin_affine_hilbert17.json
bin/certsdp verify --strict showcases/hilbert17/choi_lam_quartic_hilbert17.json
```

## Track 3: Putinar / Schmuedgen Certificates

Constrained inequalities are encoded as:

```text
f = sigma_0 + sigma_1 g_1 + ... + sigma_I * product(g_i : i in I)
```

Each `sigma` is an explicit SOS. Singleton constraint products are
Putinar-style; larger products are Schmuedgen-style.

| Artifact | Claim |
| --- | --- |
| [box_1_minus_x2y2.json](putinar/box_1_minus_x2y2.json) | `-1 <= x,y <= 1 => 1 - x^2 y^2 >= 0` |
| [unit_disk_1_minus_x2y2.json](putinar/unit_disk_1_minus_x2y2.json) | `x^2+y^2 <= 1 => 1 - x^2 y^2 >= 0` |
| [interval_1_minus_x4.json](putinar/interval_1_minus_x4.json) | `-1 <= x <= 1 => 1 - x^4 >= 0` |
| [simplex_edge_product.json](putinar/simplex_edge_product.json) | `x >= 0, y >= 0, x+y <= 1 => x(1-x-y) >= 0` |
| [annulus_product_barrier.json](putinar/annulus_product_barrier.json) | `1 <= x^2+y^2 <= 4 => (x^2+y^2-1)(4-x^2-y^2) >= 0` |

## Track 4: SOSTOOLS Exact Replay Bridge

The SOSTOOLS-lite files model the exchange contract a MATLAB/SOSTOOLS exporter
would provide: variables, monomial basis, target polynomial, and Gram matrix.
CertSDP converts that neutral JSON into its own certificate and then replays it
with exact coefficient matching and exact rational PSD proof replay.

```bash
bin/certsdp convert-sostools showcases/sostools/sostools_lite_quartic_bound.json \
  --problem-out /tmp/quartic_bound_sos_gram.json \
  --solution-out /tmp/quartic_bound_gram_solution.json \
  --cert-out /tmp/quartic_bound_cert.json
bin/certsdp verify --strict /tmp/quartic_bound_cert.json
```

Included SOSTOOLS-lite scenarios:

| Source | Scenario |
| --- | --- |
| [sostools_lite_xy_square.json](sostools/sostools_lite_xy_square.json) | Minimal positive polynomial decomposition |
| [sostools_lite_rank1_positive_polynomial.json](sostools/sostools_lite_rank1_positive_polynomial.json) | Rank-one Gram export |
| [sostools_lite_lyapunov_decay.json](sostools/sostools_lite_lyapunov_decay.json) | Lyapunov decay polynomial |
| [sostools_lite_quartic_bound.json](sostools/sostools_lite_quartic_bound.json) | Polynomial optimization bound replay |
| [sostools_lite_dense_cross_quartic.json](sostools/sostools_lite_dense_cross_quartic.json) | Dense cross-term Gram replay |

The intended positioning is:

```text
SOSTOOLS searches.
CertSDP certifies.
```
