# CertSDP Documentation

CertSDP.jl is an exact-certificate compiler for SDP/SOS artifacts. It turns
candidate evidence from numerical solvers, sparse SOS workflows,
noncommutative relaxations, symmetry reductions, and algebraic reconstruction
into proof-carrying JSON that can be replayed with exact arithmetic.

```text
candidate evidence in, exact replayable certificate out
```

## Core Claim

CertSDP separates candidate generation from proof acceptance. Solvers and
symbolic tools may help find a candidate. CertSDP accepts only when the
certificate's exact identities, fields, quotient reductions, hashes, and PSD
proof obligations replay from data.

## At A Glance

| Need | Start here |
| --- | --- |
| Fresh checkout | [Installation](installation.md), then [Quickstart](quickstart.md). |
| Replay a certificate | `bin/certsdp verify --strict cert.json`. |
| Replay a proof artifact | `bin/certsdp replay artifact.json --no-network --no-solver`. |
| Minimize an artifact | `bin/certsdp minimize raw.json --out minimized.json`. |
| Certify rational or algebraic LMI data | [LMI tutorial](lmi_tutorial.md) and [Backends](backends.md). |
| Certify Gram/SOS data | [SumOfSquares tutorial](sos_tutorial.md). |
| Connect SDPA, JuMP/MOI, or imported artifacts | [SDPA import](sdpa_import.md), [JuMP/MOI integration](jump_moi_integration.md), and [Workflows](workflows.md). |
| Understand replay and trust | [Trust model](trust_model.md), [Certificate format](certificate_format.md), and [Assurance model](assurance_model.md). |
| Check reproducibility evidence | [Validation](validation.md) and [Benchmarks](benchmarks.md). |

## What Is Trusted

`certify`, `reconstruct`, and import adapters can use numerical diagnostics,
rank guesses, external algebraic backends, exactification strategies, and
provenance. Strict replay does not trust those sources. It recomputes:

- canonical problem, artifact, and semantic hashes;
- exact rational or algebraic field reconstruction;
- exact LMI, SOS, sparse coefficient, affine dual, and quotient identities;
- algebraic root isolation and certified signs;
- PSD proof obligations by exact factorization or exact block replay;
- minimization equivalence when a compressed artifact is claimed equivalent.

The verifier ignores solver success flags, floating residuals, approximate
eigenvalues, backend logs, cached output, session transcripts, and provenance
claims.

## Supported Workflows

| Workflow | What CertSDP checks |
| --- | --- |
| Rational LMI and block LMI replay | Exact substitution, exact affine equality, and PSD proof replay. |
| Algebraic LMI and SOS Gram replay | Field data, embedding/root information, certified signs, coefficient matching, and algebraic PSD replay. |
| Sparse SOS and Putinar-style certificates | Sparse coefficient maps, clique/block structure, localizing multipliers, and block PSD proofs. |
| Symmetry-reduced low-rank SDP | Reduced affine identities, transform metadata, low-rank factors, and original-problem replay metadata. |
| Noncommutative trace certificates | Word canonicalization, star involution, trace cyclic equivalence, quotient relations, and coefficient identities. |
| Infeasibility certificates | Exact Farkas-style contradiction plus PSD slack verification. |
| External ecosystem artifacts | Import, normalize, minimize, export common JSON, and replay without the original tool. |

The public API remains intentionally conservative. Compiler internals are
module-qualified unless promoted in [API stability](API_STABILITY.md).

## Evidence Snapshot

The validation suite is the reproducibility contract for the public claims.

```bash
bin/certsdp doctor
julia --project scripts/run_validation.jl
```

The tracked reader-facing report is `benchmarks/VALIDATION_REPORT.md`.

## Good Fits

Use CertSDP when:

- a numerical SDP/SOS result must become a replayable proof artifact;
- rational rounding may fail and algebraic reconstruction is needed;
- degeneracy or boundary solutions make tolerance-based evidence fragile;
- sparse, symmetry-reduced, or noncommutative structure must survive
  certification;
- a paper, archive, CI job, reviewer, or formal checker needs exact data rather
  than solver logs.

## Boundaries

CertSDP verifies certificates; it does not replace modeling and numerical
solver stacks. A rejection means no supported exact proof artifact was
accepted. A nonexistence claim requires an explicit infeasibility certificate,
not merely failure to certify.

## Platform Scope

Core strict verification targets Julia 1.10+ environments. Linux and macOS run
the full package, docs, and validation matrix in CI-oriented workflows; Windows
has verifier-oriented smoke coverage. Optional candidate-generation tools
remain platform-dependent.

## Release Boundaries

| Boundary | Current contract | Not claimed |
| --- | --- | --- |
| Compiler artifacts | Artifacts carry exact fields, blocks, quotient data, reconstruction logs, verification plans, and hashes. | Trusting raw solver output as proof. |
| Algebraic fields | Rational, quadratic, multiquadratic, cyclotomic, and low-degree algebraic reconstruction paths are covered by reproducibility checks. | Unlimited algebraic-degree reconstruction. |
| PSD replay | Block and low-rank replay are checked with exact arithmetic. | Large dense SDP optimization. |
| Infeasibility | Farkas-style artifacts can certify exact contradiction. | Nonexistence claims without an explicit contradiction certificate. |
| External tools | External artifacts are candidate sources normalized into CertSDP IR. | Treating external logs, residuals, or transcripts as proof. |
