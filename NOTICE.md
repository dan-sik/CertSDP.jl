# Third-Party Notices

Copyright 2026 CertSDP contributors

The CertSDP.jl source code under `src/`, `ext/`, `test/`, `docs/`,
`examples/`, `benchmarks/`, and `bin/` is released under the Apache License,
Version 2.0 in `LICENSE`, unless a file states otherwise.

The trusted core package consists of CertSDP's Julia source, schemas,
certificates, verifier, examples, documentation, and validation fixtures. It
does not vendor or link optional algebraic or numerical backends into the exact
verifier.

Optional backends and frontends are outside the Apache-2.0 core package
boundary:

- `msolve` is used, when installed, as an optional external executable for
  algebraic candidate generation. CertSDP records backend provenance, but
  verifier acceptance never depends on `msolve` output or logs. If developers
  keep an upstream msolve checkout under the ignored local `references/`
  directory, that checkout retains its own license.
- JuMP, MathOptInterface, SumOfSquares.jl, MultivariatePolynomials.jl, and
  related Julia packages are optional extension dependencies. Their own
  licenses apply when users install them.
- Numerical solvers such as Clarabel, Mosek, Hypatia, or SCS may provide
  candidates or diagnostics in user workflows. Their outputs are not trusted
  verifier proof data.

The ignored local `references/` directory is research context used during
development. It may contain papers, external repositories, solver source code,
benchmark data, and manuals with their own licenses and copyright terms.

These reference materials are not part of the CertSDP.jl Apache-2.0 package
surface, are not required for core verification, and should not be redistributed
as if they were CertSDP source files.
