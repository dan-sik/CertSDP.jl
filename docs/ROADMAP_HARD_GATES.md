# Roadmap Hard Gates

CertSDP's next phase is not measured by feature labels. A feature is considered
landed only when it crosses the verifier boundary with exact replay evidence,
or when it is explicitly marked unsupported and fails loudly.

## Gate 1: Exactification Strategy Boundary

Every new algorithm must be implemented as a named exactification strategy with
deterministic inputs, bounded diagnostics, and a clear handoff into an exact
certificate family. A strategy may use numerical solvers or external tools to
search, but its output is candidate data until strict replay accepts it.

Production status requires:

- a stable strategy name;
- structured attempt diagnostics;
- tests for success and failure;
- no hidden dependence on solver logs during verification.

Implementation evidence:

- `certify_auto_sos` exposes named exactification strategies and structured
  attempt records;
- unsupported experimental strategies fail loudly with diagnostics;
- CLI and exactification tests cover accepted and rejected attempts.

## Gate 2: Strict Replay Boundary

No strategy is allowed to extend the trusted base by trusting RealCertify,
NCTSSOS, ClusteredLowRankSolver, msolve, Sage, quantum-bound logs, or any
floating-point residual. Imported artifacts must be translated into CertSDP
problem data and proof obligations, then checked by CertSDP's exact verifier.

Production status requires:

- exact problem hashes;
- exact solution or field data;
- replayed equality, sign, PSD, or coefficient obligations;
- adversarial mutation tests.

Implementation evidence:

- schema-v1 strict replay rejects backend logs, approximate equality, and
  numerical trust claims before parsing;
- every accepted family embeds exact problem hashes and proof obligations;
- adversarial suites mutate coordinates, matrices, hashes, signs, pivots, SOS
  identities, and trust-boundary fields.

## Gate 3: Parrilo-Peyrl Round-And-Project SOS

The rational SOS path must reconstruct a rational Gram candidate, project it
onto exact coefficient-matching equations, and then prove PSD over `QQ`. A
projected Gram matrix without PSD replay is not a certificate.

Current implementation status:

- `:sos_round_project` is implemented for exported SOS Gram problems;
- direct exact replay is attempted first when requested;
- projected candidates are accepted only after exact coefficient matching and
  embedded rational PSD replay.

## Gate 4: Perturbation And Compensation

Perturbation-based SOS workflows must record the perturbed identity and the
compensation identity as exact polynomial equalities. Univariate special cases
must expose the chosen basis, perturbation size, compensation squares, and exact
coefficient replay.

Production status requires:

- exact perturbation and compensation terms;
- a verifier path for the final unperturbed target;
- benchmarks covering Reznick/Hilbert-Artin/Putinar-style examples.

Implementation evidence:

- `PerturbationCompensationSOSCertificate` stores perturbed and compensation
  SOS blocks separately;
- strict replay checks both exact identities:
  `target + perturbation = perturbed_sos` and
  `target = perturbed_sos - compensation_sos`;
- showcase and positive-certificate tests cover rational-function,
  Putinar-style, and perturbation/compensation paths.

## Gate 5: Number-Field Certificates

Algebraic and low-rank strategies must represent coefficients in explicit
number fields. A field-extension certificate must include the defining
polynomial, isolating data or embedding choices, exact arithmetic rules, and
sign obligations sufficient for replay.

Production status requires:

- `QQ(alpha)` and multi-generator extension metadata;
- exact field element serialization;
- embedding-aware PSD/sign replay;
- tests where rational rounding fails but the field certificate passes.

Implementation evidence:

- Type A/F LMI certificates and algebraic SOS Gram certificates serialize
  minimal polynomials, isolating intervals, and field elements;
- algebraic PSD replay uses certified sign tests over the selected embedding;
- validation rows include rational-rounding failure followed by algebraic
  certification, and `AlgebraicSOSGramCertificate` covers `QQ(alpha)` Gram
  replay.

## Gate 6: Noncommutative And Quantum Certificates

Noncommutative workflows must replay word identities symbolically before any
PSD block is trusted. Quantum-bound certificates must also replay projection,
trace-cyclic, involution, and relation-reduction obligations.

Production status requires:

- word algebra and canonicalization tests;
- exact coefficient matching for noncommutative or trace polynomial bases;
- block PSD replay after symmetry/projection metadata is checked;
- negative tests for stale relation reductions.

Implementation evidence:

- `NCSOSGramCertificate` replays word identities, trace-cyclic canonicalization,
  and embedded rational PSD;
- `NCRelationReduction` records rewrite rules with a stable fingerprint and
  reduces target/Gram words before coefficient matching;
- tests reject stale relation reductions and nonmatching NC Gram data.

## Gate 7: External Adapter Matrix

Adapters for RealCertify, NCTSSOS, ClusteredLowRankSolver, CertifiedQuantumBounds,
and paper benchmark code are translation layers only. They must not become
trusted proof engines.

Production status requires:

- one adapter spec per external tool;
- sample imported artifact fixtures;
- success/failure rows in `benchmarks/external/`;
- docs explaining which external claims CertSDP replays.

Implementation evidence:

- adapter specs cover RealCertify, NCTSSOS, ClusteredLowRankSolver, and
  CertifiedQuantumBounds;
- `ExternalReplayArtifact` accepts only translated CertSDP schema-v1
  certificates that pass strict replay;
- raw solver output, backend logs, and session transcripts are rejected.

## Gate 8: Reviewer Artifact

A paper artifact must be useful to a skeptical reviewer using a fresh checkout.
It must contain data-only certificates, strict replay output, hashes, and a
short command sequence that reproduces the acceptance result.

Production status requires:

- certificate JSON;
- strict replay report;
- LaTeX/Sage/Julia export when relevant;
- redacted provenance sidecar;
- CI or validation evidence for every shipped artifact row.

Implementation evidence:

- `write_paper_artifact` writes `certificate.json`, `manifest.json`,
  `strict_replay.txt`, `snippet.tex`, `provenance.json`, and `README.md`;
- artifact generation fails unless strict replay accepts the certificate;
- validation and roadmap tests exercise the generated reviewer directory.
