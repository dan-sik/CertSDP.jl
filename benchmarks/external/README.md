# External Adapter Benchmarks

This directory is reserved for replay fixtures imported from external exact
certificate ecosystems. The gate is deliberately strict: an imported row is not
accepted because the external tool succeeded; it is accepted only when CertSDP
translates the artifact into exact problem/certificate data and strict replay
passes locally.

Adapter rows:

- RealCertify: rational SOS and perturbation/compensation identities;
- NCTSSOS: noncommutative and trace-SOS coefficient identities;
- ClusteredLowRankSolver: rational and number-field low-rank SOS certificates;
- CertifiedQuantumBounds: projected quantum-bound certificates;
- hybrid-method: degenerate SDP incidence-system benchmarks from the main
  paper workflow.

Every row must include:

- original external artifact or a minimized public fixture;
- translated CertSDP problem/certificate JSON;
- strict replay command and output;
- expected success or expected rejection metadata;
- a note explaining which external claims CertSDP replays exactly.

Raw solver output, session transcripts, floating residuals, and backend logs
are not accepted proof data. The supported handoff shape is a
`certsdp_external_artifact_version = "1.0"` JSON object containing a translated
schema-v1 CertSDP certificate. `parse_external_replay_artifact_json` rejects
raw backend claims and calls `verify_strict_json` on the translated certificate
before returning an accepted adapter artifact.

The smoke fixtures are generated in tests from a minimal SOS Gram certificate;
larger public fixtures should live under `benchmarks/external/fixtures/` with a
paired success/failure expectation row.
