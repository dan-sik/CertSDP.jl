# Validation Benchmarks

This directory contains the public validation fixture suite. It is an evidence
contract for exact replay, not a solver-speed leaderboard.

The suite covers rational LMIs, algebraic SDP certificates where bounded
rational rounding fails, multi-block SDP replay, SOS Gram certificates,
SDPA/JuMP/MOI/SumOfSquares-style import paths, solve -> diagnose -> certify
workflows, and expected rejection cases.

Run the public entry point from the repository root:

```bash
julia --project scripts/run_validation.jl
```

Generated certificates, failure reports, and extracted frontend artifacts are
written under `benchmarks/generated/` when requested. The tracked report is
`benchmarks/VALIDATION_REPORT.md`.

Strict verification never trusts numerical solver logs, backend artifacts,
approximate eigenvalues, or fixture provenance. Those fields are useful for
diagnostics; acceptance still comes from exact certificate replay.
