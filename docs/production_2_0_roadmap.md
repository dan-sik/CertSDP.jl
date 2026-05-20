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
  internal sparse polynomial ring, block Gram entries, and sparse localizing
  multiplier terms.
- `ExactCertificateArtifact` can carry an `exact_affine_identity` obligation,
  and strict verification recomputes exact field-valued affine residuals.
- Field inference now accepts explicit bounded reconstruction evidence for
  rational, quadratic, multiquadratic, cyclotomic, and low-degree algebraic
  fields before falling back to legacy markers.
- The sparse OPF-like fixture includes a small replayable sparse identity
  with a localizing multiplier instead of relying only on witness hashes.
- Symmetry-reduced and infeasibility fixtures include replayable affine identity
  obligations instead of relying only on residual witness hashes.
- Noncommutative trace fixtures now carry quotient replay examples that verify
  projector, orthogonality, cross-party commutation, and trace-cyclic
  canonicalization exactly.
- External artifact import validates format-specific JSON contracts for
  SumOfSquares-like, TSSOS-like, NCTSSOS-like, and ClusteredLowRank-like
  fixtures before producing compiler IR.
- Gate 7 consumes tracked JSON fixtures from `benchmarks/external/fixtures/`
  rather than symbol-only synthetic adapters.
- Gate 6 compares actual raw/minimized JSON file sizes; the raw side is a real
  unminimized bundle rather than reported padding.
- Canonical hard-gate compilers now bind to saved noisy solver artifact
  manifests under `benchmarks/external/noisy_solver_artifacts/`, while hidden
  seeded variants retain deterministic generation.
- Field discovery accepts bounded numeric-recognition evidence with explicit
  degree and height budgets for rational, quadratic/multiquadratic, and the
  cubic plastic field smoke path.
- Sparse OPF replay now supports full saved localizing multiplier maps rather
  than a single localizing smoke term.
- Noncommutative trace replay now checks coefficient maps after quotient
  canonicalization, not only canonicalization examples.
- External fixture packs carry a redistributability and upstream-publishing
  manifest so real exported fixtures can be added only after license review.
- `compiler_validation_runtime()` measures the actual hard-gate run instead of
  returning a constant.
- `certsdp explain artifact.json` explains CertSDP 2.0 proof artifacts.

## Next Implementation Order

1. Replace locally generated noisy manifests with larger redistributable
   upstream exports after license review.
2. Upgrade numeric field recognition from bounded quadratic/cubic smoke support
   to a general PSLQ/LLL lattice backend with coefficient-height certificates.
3. Bind Gate 1 to full saved OPF-like polynomial coefficient maps, including
   equality multipliers and localizing products across multiple constraints.
4. Extend NC trace identity replay to star-involution SOS terms and quotient
   relation expansion, beyond coefficient maps over canonical words.
5. Add independent third-party replay exports for the new saved artifact
   manifest format.
