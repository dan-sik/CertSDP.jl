# CertSDP.jl 2.0 Production Roadmap

This page tracks the delta between the current deterministic validation harness
and the intended production-grade exact certificate compiler.

## Production Criteria

- Reconstruction consumes saved noisy solver artifacts or external-tool exports,
  not hand-authored certificate objects.
- Field discovery is evidence driven: rational reconstruction, quadratic and
  multiquadratic search, cyclotomic recognition, and bounded low-degree algdep.
- Strict replay recomputes mathematical obligations from exact data, including
  sparse polynomial identities, affine dual identities, PSD factorization, and
  noncommutative trace quotient identities.
- Import adapters parse source artifacts into CertSDP IR and reject malformed
  source data before reconstruction.
- Runtime, size, and minimization gates measure real artifacts rather than
  reported padding or metadata claims.

## Current Hardening Slice

- `ExactCertificateArtifact` can now carry an `exact_sparse_identity` proof
  obligation.
- Strict verification recomputes that sparse identity over `QQ` using the
  internal sparse polynomial ring and block Gram entries.
- `ExactCertificateArtifact` can carry an `exact_affine_identity` obligation,
  and strict verification recomputes exact field-valued affine residuals.
- The sparse OPF-like fixture includes a small replayable sparse identity
  instead of relying only on witness hashes.
- Symmetry-reduced and infeasibility fixtures include replayable affine identity
  obligations instead of relying only on residual witness hashes.
- External artifact import validates source format, source hashes, artifact kind,
  and block-list shape before producing compiler IR.
- `compiler_validation_runtime()` measures the actual hard-gate run instead of
  returning a constant.
- `certsdp explain artifact.json` explains CertSDP 2.0 proof artifacts.

## Next Implementation Order

1. Replace synthetic Gate 7 adapters with real JSON parsers for the four import
   fixture families.
2. Extend `exact_sparse_identity` to sparse localizing terms and constraint
   multipliers, then bind Gate 1 to saved noisy sparse OPF fixtures.
3. Replace marker-based field inference with a bounded reconstruction engine.
4. Add noncommutative word canonicalization replay for trace/NPA certificates.
5. Replace padded compression gates with real raw/minimized artifact files.
