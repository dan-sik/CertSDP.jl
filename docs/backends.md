# Backends

CertSDP separates candidate generation from verification. Backends may help
find a candidate exact solution, but a certificate is accepted only after exact
verifier replay.

## Trusted Core

The trusted verifier uses CertSDP's own exact routines:

- rational parsing and canonical problem hashing;
- exact LMI substitution;
- algebraic root isolation for one-root certificates;
- exact equality in `QQ` and `QQ(alpha)`;
- certified sign tests;
- Bareiss determinants, Schur complements, and pivoted-LDL PSD proof replay;
- SOS coefficient matching.

## Numerical Oracle Layer

Approximate solvers and user-supplied points are diagnostic data. They can
provide:

- `xhat` values;
- residuals;
- approximate eigenvalues;
- rank estimates;
- pivot guesses;
- solver provenance.

The Clarabel workflow is an optional Julia extension. Loading CertSDP for
exact verification does not load Clarabel; `solve_approximately` will load it
only when `:clarabel` is requested and the package is installed in the active
environment. The workflow includes a maximum-rank search loop. It can try a
plain feasibility objective, trace maximization, random linear objectives, and
multiple retry attempts. Candidates are scored by stable rank, observed rank,
PSD violation, residual, eigengap, and face clarity. This score only chooses a
candidate for the later exact pipeline; it is not proof evidence.

They cannot prove feasibility by themselves.

Pseudo-code for a typical numerical-to-exact workflow:

```text
solve SDP approximately
diagnose residual and rank profile
build incidence system from stable rank data
solve polynomial system with an algebraic backend
select a nearby real candidate
build exact certificate
verify certificate independently
```

## msolve Backend

The `MsolveBackend` calls `msolve` as an external executable. Configure it with:

```bash
export CERTSDP_MSOLVE=/absolute/path/to/msolve
```

or pass a path explicitly:

```bash
bin/certsdp certify examples/algebraic_problem.json \
  --solution examples/algebraic_approx.json \
  --out /tmp/certsdp-algebraic-cert.json \
  --msolve /absolute/path/to/msolve \
  --timeout 300 \
  --save-artifacts /tmp/certsdp-msolve-artifacts
```

Saved artifacts include the generated `.ms` input, backend output, stdout,
stderr, command metadata, version information when available, and provenance
JSON.

## Sage/msolve Backend

`SageMsolveBackend` runs a separate Sage adapter around the same exact
polynomial-system input and parses the resulting msolve-compatible output. It
is useful as an independent orchestration path when an audit or CI job wants
to exercise Sage process setup, artifact capture, and candidate parsing without
changing the trusted verifier.

```bash
bin/certsdp certify examples/algebraic_problem.json \
  --solution examples/algebraic_approx.json \
  --out /tmp/certsdp-algebraic-sage-cert.json \
  --algebraic-backend sage_msolve \
  --sage /absolute/path/to/sage \
  --msolve /absolute/path/to/msolve \
  --timeout 300
```

Julia users can pass either a backend symbol or an explicit backend object:

```julia
result = certify(P, approx; algebraic_backend=:sage_msolve,
                 sage_binary="/absolute/path/to/sage")
```

As with direct `msolve`, Sage/msolve only proposes exact candidates. The
certificate is accepted only after CertSDP replays the incidence equations,
substitution, root isolation, signs, and PSD proof internally.

## Backend Failures

Backend failures are structured. CertSDP distinguishes unavailable executables,
timeouts, unsupported positive-dimensional output, parser failures, and
candidate-selection failures. See [Diagnostics](diagnostics.md) for how to read
failure reports.

For incidence systems, a positive-dimensional `msolve` status is not treated as
proof and is not retried blindly forever. The certifier records the system size,
rank/pivot attempt, slicing strategy, and backend status in the failure report.
When rational slicing is enabled, CertSDP first tries exact small-denominator
slices derived from the approximation or from user input, then falls back to the
unsliced system so the diagnostic still explains the original component.

Candidate roots are exact-replayed against every incidence equation before a
certificate is built. Bad RUR candidates, wrong boxes, point intervals that do
not satisfy the parameter polynomial, and PSD verification failures are
reported as candidate-selection diagnostics rather than accepted from backend
text.

## Optional Frontend Packages

JuMP/MOI and SumOfSquares are frontend extraction paths, not trusted proof
engines. They help move exact model data into CertSDP. Once a problem and
candidate certificate are built, verification is independent of those packages.
