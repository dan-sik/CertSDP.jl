# Assurance Model

CertSDP's public claims are backed by exact replay obligations. A feature is
documented as supported only when accepted artifacts can be checked from data,
or when unsupported inputs fail with structured diagnostics.

## Strategy Boundary

Exactification strategies may use numerical solvers, rank heuristics, algebraic
backends, or external metadata to search for candidate data. Their output is
not proof until strict replay accepts the resulting certificate.

Assurance requirements:

- deterministic strategy names and attempt records;
- bounded diagnostics for failure;
- no dependence on solver logs during verification;
- tests for both acceptance and rejection.

## Strict Replay Boundary

Imported artifacts from RealCertify-style, TSSOS-style, NCTSSOS-style,
ClusteredLowRank-style, quantum-bound, or paper-benchmark workflows are
translation inputs. CertSDP accepts them only after conversion into exact
problem data, certificate data, and replayable proof obligations.

Assurance requirements:

- exact problem and artifact hashes;
- exact solution or field data;
- replayed equality, sign, PSD, coefficient, affine, or quotient obligations;
- adversarial mutation tests.

## SOS Exactification

The rational SOS path reconstructs a rational Gram candidate, projects it onto
exact coefficient-matching equations, and then proves PSD over `QQ`. A projected
Gram matrix without PSD replay is not a certificate.

Assurance requirements:

- exact coefficient matching;
- exact PSD proof replay;
- structured diagnostics when projection or PSD proof fails.

## Perturbation And Compensation

Perturbation-based SOS workflows record the perturbed identity and the
compensation identity as exact polynomial equalities. The final unperturbed
claim is accepted only when both exact identities replay.

Assurance requirements:

- exact perturbation and compensation terms;
- verifier path for the final target;
- examples covering rational-function, Positivstellensatz, and
  perturbation/compensation identities.

## Number Fields

Algebraic and low-rank certificates represent coefficients in explicit number
fields. A field-extension certificate records enough information to replay
field arithmetic, signs, and PSD obligations.

Assurance requirements:

- serialized field data and field elements;
- embedding or isolating information when signs are needed;
- rational-first reconstruction with minimality diagnostics;
- clear rejection when the requested field budget is insufficient.

## Noncommutative And Trace Certificates

Noncommutative workflows replay word identities symbolically before any PSD
block is trusted. Trace, cyclic, involution, projection, orthogonality,
completeness, and quotient-reduction metadata are part of the proof surface.

Assurance requirements:

- canonical word and trace reductions;
- exact coefficient matching over the reduced basis;
- PSD replay after quotient metadata is checked;
- negative tests for stale or overbroad relations.

## External Adapter Matrix

Adapters are untrusted translators. They normalize external candidate evidence
into CertSDP artifacts and reject raw logs, transcripts, floating residuals, or
backend-dependent proof claims.

Assurance requirements:

- one documented adapter contract per external format;
- accepted and rejected sample artifacts;
- strict replay of the translated certificate;
- clear documentation of which external claims are replayed exactly.

## Reviewer Artifacts

A shareable artifact must be useful to a skeptical reader using a fresh
checkout. It should contain data-only certificates, strict replay output,
hashes, provenance, and a short command sequence.

Assurance requirements:

- certificate JSON;
- strict replay report;
- manifest and hashes;
- optional LaTeX/Sage/Julia/third-party snippets;
- redacted provenance sidecar;
- reproducibility evidence for every published artifact row.
