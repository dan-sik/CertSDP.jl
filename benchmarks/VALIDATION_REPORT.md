# CertSDP v1.0 Validation Report

- Suite: `benchmarks`
- Public suite: `validation`
- Instances: 18
- Status: passed
- Machine metadata: CPU=10 threads Apple M5; RAM=24.0 GiB; OS=Darwin; Julia=1.12.6
- Validation budget: validation; max timeout 600.0000s

## Executive Summary

CertSDP.jl is an exact replay layer for SDP/SOS certificate workflows. The validation suite checks exact replay obligations, certificate generation, imported workflows, adversarial rejection, and structured failure reporting.

## Replay Evidence At A Glance

| Reader Question | Current Evidence | Why It Matters |
| --- | --- | --- |
| Did accepted certificates replay exactly? | 15 / 15 certified rows passed strict replay. | Acceptance is by verifier replay, not solver status. |
| Does validation include rejection evidence? | 3 expected rejection/failure rows passed. | Fake certificates and invalid candidates are part of the contract. |
| Does the algebraic path cover rational-rounding failure? | 4 certified rows failed bounded rational rounding first. | This is the motivating degenerate SDP/SOS risk. |
| Is the full numerical-to-exact path exercised? | 1 solve -> diagnose -> certify workflow passed. | The report separates candidate generation from strict verification. |
| What is the strict verifier runtime envelope? | 15 certified timings; total 7.5194s; max 2.5881s; min 0.0013s | Local timing only; useful as an audit baseline, not a solver benchmark. |
| How large are replay artifacts? | 15 certificates; total 2480.93 KiB; max 1314.53 KiB; min 977 B | Certificate size sets expectations for archived JSON artifacts. |

## Evidence By Workflow Family

| Evidence Family | Certified | Rejected | Strict Verified | Rounding Failures Certified | Backend | Representative Case | Notes |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| SOS | 2 | 0 | 2 | 0 | none | validation__sos_x2_plus_1 (basis=2, vars=1, terms=2) | certifier-generated certificate |
| algebraic_incidence | 2 | 0 | 2 | 2 | msolve,none | validation__algebraic_direct_degree6_dim20 (20x20, n=2) | certifier-generated certificate; bounded rational rounding fails but exact certification succeeds; algebraic degree >=4 |
| irrational | 1 | 0 | 1 | 1 | msolve | validation__algebraic_sqrt2_unique (4x4, n=1) | certifier-generated certificate; bounded rational rounding fails but exact certification succeeds |
| mixed_multiblock | 1 | 0 | 1 | 0 | none | validation__mixed_blocks_sqrt2_total22 (blocks=3, dims=12+4+6 (total=22), n=2) | - |
| multi_block | 1 | 0 | 1 | 0 | none | validation__multiblock_sdpa_two_blocks (blocks=2, dims=2+1 (total=3), n=2) | certifier-generated certificate |
| multi_block_sdp | 1 | 0 | 1 | 0 | none | validation__multiblock_dense_dim60_n20 (blocks=4, dims=15+15+15+15 (total=60), n=20) | certifier-generated certificate |
| negative_fake_cert | 0 | 1 | 0 | 0 | none | validation__fake_rational_solution_rejected (2x2, n=2) | expected rejection/failure |
| negative_fake_cert_sos | 0 | 1 | 0 | 0 | none | validation__fake_sos_gram_rejected (basis=2, vars=1, terms=2) | expected rejection/failure |
| numerical_oracle | 0 | 1 | 0 | 0 | msolve | validation__invalid_approximation_rejected (2x2, n=1) | certifier-generated certificate; expected rejection/failure |
| rank_deficient | 1 | 0 | 1 | 0 | none | validation__rank_deficient_kernel_3x3 (3x3, n=0) | certifier-generated certificate |
| rational | 1 | 0 | 1 | 0 | none | validation__rational_pd_2x2 (2x2, n=2) | certifier-generated certificate |
| solve_diagnose_certify | 1 | 0 | 1 | 1 | msolve | validation__workflow_solve_certify_sqrt2_random_objective (4x4, n=1) | certifier-generated certificate; numerical oracle workflow; bounded rational rounding fails but exact certification succeeds |
| weakly_feasible | 1 | 0 | 1 | 0 | none | validation__weakly_feasible_common_kernel_3x3 (3x3, n=1) | certifier-generated certificate |
| workflow_imported | 3 | 0 | 3 | 0 | none | validation__workflow_jump_moi_extract_multiblock_dim48 (blocks=6, dims=8+8+8+8+8+8 (total=48), n=12) | certifier-generated certificate; imported frontend workflow |

## Paper Artifact Coverage

| Evidence Class | Representative Rows | Evidence Meaning |
| --- | --- | --- |
| Paper-derived degenerate SDP mechanism | `validation__algebraic_direct_degree6_dim20`, `validation__algebraic_certifier_quartic_dim10_n2`, `validation__algebraic_sqrt2_unique` | Exercises incidence-style algebraic certification, exact root replay, and rational rounding failure. |
| SDPA/SDPLIB-style imported SDP | `validation__multiblock_dense_dim60_n20`, `validation__multiblock_sdpa_two_blocks`, `validation__workflow_sdpa_import_multiblock` | Covers sparse block SDP import and blockwise exact PSD replay. |
| SumOfSquares-style SOS workflow | `validation__workflow_sumofsquares_extracted_sos`, `validation__sos_x2_plus_1`, `validation__sos_xy_square_nondiagonal` | Covers exact Gram coefficient matching, non-diagonal Gram replay, and SOS export paths. |
| Full numerical-to-exact workflow | `validation__workflow_solve_certify_sqrt2_random_objective` | Separates numerical solve, diagnosis, certification, and strict exact verification. |
| Negative controls | `validation__fake_rational_solution_rejected`, `validation__fake_sos_gram_rejected`, `validation__invalid_approximation_rejected` | Confirms fake certificates and invalid candidates are rejected with structured diagnostics. |

## Adversarial Mutation Matrix

| Mutation Surface | Visible Validation Row | Deeper Gate |
| --- | --- | --- |
| Problem/certificate hash | `validation__fake_rational_solution_rejected` | Strict verifier recomputes hashes before replay. |
| Rational coordinates, substituted matrix, minors, pivots | `validation__fake_rational_solution_rejected` | Adversarial tests mutate coordinates, matrices, determinants, LDL pivots, and Schur data. |
| Algebraic minimal polynomial, root interval, signs | algebraic validation rows | Adversarial tests mutate root data and exact algebraic proof claims. |
| SOS coefficient matching and Gram PSD proof | `validation__fake_sos_gram_rejected` | SOS tests mutate coefficient tables, Gram entries, and embedded PSD certificates. |
| Invalid approximation / candidate quality | `validation__invalid_approximation_rejected` | Numerical diagnostics reject infeasible approximate candidates before proof acceptance. |

## Raw Artifacts And Archival Status

| Artifact | Location Or Command | Status |
| --- | --- | --- |
| Tracked validation report | benchmarks/VALIDATION_REPORT.md | Generated by `certsdp benchmark`; this file records the current public evidence table. |
| Raw generated certificates and failures | `--generated-dir benchmarks/generated` | 18 reproducible row artifacts in this run; directory is ignored by git. |
| Replay bundle | `bin/certsdp bundle cert.json --out artifact.zip` | Data-only ZIP with strict replay report and redacted sidecar metadata. |
| Archival DOI | CITATION.cff and codemeta.json | Pending until a public tagged archive is deposited and a DOI is minted. |

## Verification Footprint

| Metric | Current Value | Interpretation |
| --- | --- | --- |
| Strict verifier timings | 15 certified timings; total 7.5194s; max 2.5881s; min 0.0013s | Measured for certified rows during exact replay. |
| Cache consistency | acceptance identical: true; cached total 2.8963s; uncached total 3.2537s; cache hits 59767; cache misses 1987; median speedup 1.3139 | Cache-on and cache-off acceptance must agree. |
| Certificate sizes | 15 certificates; total 2480.93 KiB; max 1314.53 KiB; min 977 B | Size of generated or replayed certificate artifacts. |

## Slowest Validation Cases

| Instance | Status | Strict Verify | Verify No Cache | Cache Speedup | Slowest Stage | Certificate Size | Budget |
| --- | --- | ---: | ---: | ---: | --- | ---: | --- |
| validation__algebraic_direct_degree6_dim20 | certified | 2.5881s | 0.1113s | 1.3496 | polynomial_remainder_seconds | 75.78 KiB | validation |
| validation__mixed_blocks_sqrt2_total22 | certified | 2.2764s | 2.2764s | - | - | 977 B | validation |
| validation__algebraic_certifier_quartic_dim10_n2 | certified | 1.1018s | 0.1653s | 2.5917 | determinant_seconds | 51.58 KiB | validation |
| validation__multiblock_dense_dim60_n20 | certified | 0.6871s | 0.2173s | 0.9783 | - | 959.62 KiB | validation |
| validation__algebraic_sqrt2_unique | certified | 0.3241s | 0.0028s | 0.4076 | algebraic_sign_seconds | 8.17 KiB | validation |

## Failure Diagnostics Summary

- `validation__fake_rational_solution_rejected`: rejected - candidate certificate rejected by verifier
- `validation__fake_sos_gram_rejected`: rejected - candidate certificate rejected while parsing: ArgumentError: root.problem_hash mismatch: expected sha256:77cc4b8d239f49bf61f29e1270234cb3be1e3c17937528be803d848dc4fe2ece, computed sha256:e56f2010ece7d8d8281482db2aaf9fe1d2b1735aff8275e40678a54ed2743d5c
- `validation__invalid_approximation_rejected`: NumericalFailure - not certified: approximation_psd_violation_too_large; failure artifact: validation__invalid_approximation_rejected_failure.json

## Cases

| Instance | Suite | Family | Category | Construction | Source | Origin | Pipeline | Size | Declared Vars | Effective Vars | Density | Coeff Bits | Nonzero Affine | Rank Profile | Block Coupling | Gram Offdiag | Status | Certificate Type | Failure Type | Rational Rounding | Denominator Bound | Rounding Failure Reason | Cert Time | Strict Verify | Strict Time | Cert Size | Verify No Cache | Cache Hits | Cache Misses | Cache Speedup | Slowest Stage | Timeout | Backend | Message |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | --- | --- | --- | --- | --- | --- | --- | ---: | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | --- | --- |
| validation__algebraic_certifier_quartic_dim10_n2 | validation | algebraic_certifier_generated | algebraic_incidence_validation | algebraic_incidence_certifier_generated_n2_challenge | generated | certifier_generated | certify_from_approx | 10x10, n=2 | 2 | 2 | 0.1233 | 1-2 | 2 | rank=9 | - | - | certified | algebraic_psd_certificate | - | failed | 64 | ArgumentError: cannot create a rational PSD proof: pivoted_ldl pivot at pivot 4: pivoted LDL diagonal is negative: -1237//7166727 | 39.1637s | pass | 1.1018s | 51.58 KiB | 0.1653s | 21756 | 365 | 2.5917 | determinant_seconds | 600.0000s | msolve | certificate verified |
| validation__algebraic_direct_degree6_dim20 | validation | direct_algebraic | algebraic_sdp_validation | algebraic_direct | generated | direct_fixture | verify_only | 20x20, n=2 | 2 | 2 | 0.0033 | 1-1 | 2 | rank=1 | - | - | certified | algebraic_psd_certificate | - | failed | 1024 | ArgumentError: cannot create a rational PSD proof: pivoted_ldl pivot at pivot 2: pivoted LDL diagonal is negative: -38769//38809000 | 6.7873s | pass | 2.5881s | 75.78 KiB | 0.1113s | 34635 | 12 | 1.3496 | polynomial_remainder_seconds | 180.0000s | none | direct algebraic certificate verified |
| validation__algebraic_sqrt2_unique | validation | irrational | irrational | generated_exact_fixture | manual | certifier_generated | certify_from_approx | 4x4, n=1 | 1 | 1 | 0.25 | 1-2 | 1 | rank=2 | - | - | certified | algebraic_psd_certificate | - | failed | 1024 | ArgumentError: cannot create a rational PSD proof: pivoted_ldl pivot at pivot 2: pivoted LDL diagonal is negative: -1//2744210 | 1.3593s | pass | 0.3241s | 8.17 KiB | 0.0028s | 893 | 23 | 0.4076 | algebraic_sign_seconds | 120.0000s | msolve | certificate verified |
| validation__fake_rational_solution_rejected | validation | negative_fake_cert | negative_fake_cert | generated_exact_fixture | manual | direct_fixture | verify_only | 2x2, n=2 | 2 | 2 | 0.3333 | 1-1 | 2 | rank=2 | - | - | rejected | rational_psd_certificate | - | not_applicable | 0 | certificate replay benchmark | - | - | 0.3047s | 2.41 KiB | 0.1295s | 0 | 0 | 555.0964 | - | 30.0000s | none | candidate certificate rejected by verifier |
| validation__fake_sos_gram_rejected | validation | negative_fake_cert_sos | negative_fake_cert_sos | generated_exact_fixture | manual | direct_fixture | verify_only | basis=2, vars=1, terms=2 | 1 | 1 | 1.0 | 1-1 | 2 | - | - | - | rejected | candidate | - | not_applicable | 0 | candidate certificate rejected before coordinate rounding | - | - | - | 7.96 KiB | - | 0 | 0 | - | - | 30.0000s | none | candidate certificate rejected while parsing: ArgumentError: root.problem_hash mismatch: expected sha256:77cc4b8d239f49bf61f29e1270234cb3be1e3c17937528be803d848dc4fe2ece, computed sha256:e56f2010ece7d8d8281482db2aaf9fe1d2b1735aff8275e40678a54ed2743d5c |
| validation__invalid_approximation_rejected | validation | numerical_oracle | numerical_oracle | generated_exact_fixture | manual | certifier_generated | certify_from_approx | 2x2, n=1 | 1 | 0 | 0.25 | 1-1 | 0 | - | - | - | rejected | - | NumericalFailure | failed | 1024 | ArgumentError: cannot create a rational PSD proof: pivoted_ldl pivot at pivot 1: pivoted LDL diagonal is negative: -1//1 | 0.0048s | - | - | 695 B | - | 0 | 0 | - | - | 30.0000s | msolve | not certified: approximation_psd_violation_too_large; failure artifact: validation__invalid_approximation_rejected_failure.json |
| validation__mixed_blocks_sqrt2_total22 | validation | mixed_multiblock | mixed_multi_block_validation | mixed_multiblock_exact_report | generated | direct_fixture | verify_only | blocks=3, dims=12+4+6 (total=22), n=2 | 2 | 2 | 0.0408 | 1-8 | 2 | rank=9 | 0/2 (0.0%) | - | certified | mixed_block_algebraic_certificate_report | - | success | 1024 | - | 2.2764s | pass | 2.2764s | 977 B | 2.2764s | 0 | 0 | - | - | 120.0000s | none | mixed block exact report verified: block 1 algebraic schur_zero; block 2 rational ldl; block 3 facial schur_zero |
| validation__multiblock_dense_dim60_n20 | validation | multi_block_sdp | multi_block_sdp_validation | generated_dense_multiblock | generated | certifier_generated | certify_from_approx | blocks=4, dims=15+15+15+15 (total=60), n=20 | 20 | 20 | 0.8639 | 4-9 | 80 | rank=60 | 20/20 (100.0%) | - | certified | block_rational_psd_certificate | - | success | 1024 | - | 1.2617s | pass | 0.6871s | 959.62 KiB | 0.2173s | 0 | 0 | 0.9783 | - | 240.0000s | none | certificate verified |
| validation__multiblock_sdpa_two_blocks | validation | multi_block | multi_block | generated_exact_fixture | manual | certifier_generated | certify_from_approx | blocks=2, dims=2+1 (total=3), n=2 | 2 | 2 | 0.6 | 1-2 | 4 | rank=3 | 2/2 (100.0%) | - | certified | block_rational_psd_certificate | - | success | 1024 | - | 0.3841s | pass | 0.0344s | 7.59 KiB | 0.0005s | 4 | 4 | 1.3139 | determinant_seconds | 30.0000s | none | certificate verified |
| validation__rank_deficient_kernel_3x3 | validation | rank_deficient | rank_deficient | generated_exact_fixture | manual | certifier_generated | certify_from_approx | 3x3, n=0 | 0 | 0 | 0.2222 | 1-1 | 0 | rank=2 | - | - | certified | rational_psd_certificate | - | success | 1024 | - | 0.4159s | pass | 0.0289s | 4.98 KiB | 0.0003s | 7 | 7 | 1.6849 | determinant_seconds | 30.0000s | none | certificate verified |
| validation__rational_pd_2x2 | validation | rational | rational | generated_exact_fixture | manual | certifier_generated | certify_from_approx | 2x2, n=2 | 2 | 2 | 0.3333 | 1-1 | 2 | rank=2 | - | - | certified | rational_psd_certificate | - | success | 1024 | - | 0.0232s | pass | 0.0013s | 3.9 KiB | 0.0005s | 3 | 3 | 1.0457 | determinant_seconds | 30.0000s | none | certificate verified |
| validation__sos_x2_plus_1 | validation | SOS | SOS | sos_gram_exact | manual | certifier_generated | certify_from_approx | basis=2, vars=1, terms=2 | 1 | 1 | 1.0 | 1-1 | 2 | rank=2 | - | 0.0% | certified | sos_gram_certificate | - | not_applicable | 0 | SOS Gram benchmark uses exact coefficient matching, not LMI coordinate rounding | 2.1432s | pass | 0.0679s | 8.51 KiB | 0.1964s | 9 | 3 | 6.7211 | determinant_seconds | 30.0000s | none | SOS Gram certificate verified |
| validation__sos_xy_square_nondiagonal | validation | SOS | SOS | sos_gram_exact | manual | certifier_generated | certify_from_approx | basis=2, vars=2, terms=3 | 2 | 2 | 1.0 | 1-2 | 3 | rank=1 | - | 100.0% | certified | sos_gram_certificate | - | not_applicable | 0 | SOS Gram benchmark uses exact coefficient matching, not LMI coordinate rounding | 0.0945s | pass | 0.0024s | 9.38 KiB | 0.0006s | 9 | 3 | 1.7916 | determinant_seconds | 30.0000s | none | SOS Gram certificate verified |
| validation__weakly_feasible_common_kernel_3x3 | validation | weakly_feasible | weakly_feasible | generated_exact_fixture | manual | certifier_generated | certify_from_approx | 3x3, n=1 | 1 | 1 | 0.1111 | 1-1 | 1 | rank=2 | - | - | certified | rational_psd_certificate | - | success | 1024 | - | 0.3044s | pass | 0.0748s | 5.58 KiB | 0.0005s | 7 | 7 | 0.8553 | determinant_seconds | 30.0000s | none | certificate verified |
| validation__workflow_jump_moi_extract_multiblock_dim48 | validation | workflow_imported | imported_workflow_validation | jump_moi_extract | jump_moi_extract | certifier_generated | certify_from_approx | blocks=6, dims=8+8+8+8+8+8 (total=48), n=12 | 12 | 12 | 0.845 | 3-13 | 72 | rank=43 | 12/12 (100.0%) | - | certified | block_rational_psd_certificate | - | success | 1024 | - | 14.8786s | pass | 0.2103s | 1314.53 KiB | 0.1499s | 1530 | 1530 | 0.8298 | determinant_seconds | 180.0000s | none | JuMP/MOI extraction artifact validation__workflow_jump_moi_extract_multiblock_dim48_extracted certified and strict-verified |
| validation__workflow_sdpa_import_multiblock | validation | workflow_imported | imported_workflow_validation | sdpa_import | sdpa_import | certifier_generated | certify_from_approx | blocks=2, dims=2+1 (total=3), n=2 | 2 | 2 | 0.6 | 1-2 | 4 | rank=3 | 2/2 (100.0%) | - | certified | block_rational_psd_certificate | - | success | 1024 | - | 0.1762s | pass | 0.0181s | 6.26 KiB | 0.0002s | 0 | 0 | 1.4467 | - | 60.0000s | none | certificate verified |
| validation__workflow_solve_certify_sqrt2_random_objective | validation | solve_diagnose_certify | solve_diagnose_certify_validation | numerical_oracle_workflow | generated | certifier_generated | solve_diagnose_certify | 4x4, n=1 | 1 | 1 | 0.25 | 1-2 | 1 | rank=2 | - | - | certified | algebraic_psd_certificate | - | failed | 1024 | ArgumentError: cannot create a rational PSD proof: pivoted_ldl pivot at pivot 2: pivoted LDL diagonal is negative: -1//2744210 | 2.6765s | pass | 0.0618s | 8.17 KiB | 0.0017s | 893 | 23 | 0.3444 | algebraic_sign_seconds | 420.0000s | msolve | solve -> diagnose -> certificate verified |
| validation__workflow_sumofsquares_extracted_sos | validation | workflow_imported | imported_workflow_validation | sumofsquares_extract | sumofsquares_extract | certifier_generated | certify_from_approx | basis=3, vars=1, terms=5 | 1 | 1 | 1.0 | 1-2 | 5 | rank=2 | - | 66.67% | certified | sos_gram_certificate | - | not_applicable | 0 | SOS Gram benchmark uses exact coefficient matching, not LMI coordinate rounding | 0.9129s | pass | 0.0420s | 15.92 KiB | 0.0006s | 21 | 7 | 0.0207 | determinant_seconds | 120.0000s | none | SOS Gram certificate verified |

## Notes

The validation suite is a reproducible evidence contract for the supported certificate families, not a numerical SDP benchmark.
A row fails when `expected.json` status differs from the observed status.
Certified rows must pass strict verification. Strict verification is exact replay only: it does not use msolve, numerical solver output, or backend artifacts.
Verifier timing is measured twice per parsed certificate: cache disabled, then scoped exact-operation cache enabled. A row fails if those acceptance results differ.
Numerical solver and algebraic backend outputs are used only to construct candidates; acceptance still comes from exact verification.
Rational rounding is an actual bounded-denominator coordinate rounding attempt. The report records method, denominator bound, status, and exact verifier failure reason when it fails.
