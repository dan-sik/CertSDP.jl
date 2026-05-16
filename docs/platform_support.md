# Platform Support

CertSDP targets Julia 1.10 or newer. The support story is intentionally split
between the trusted verifier and optional candidate-generation tools.

## Support Matrix

| Environment | Current support |
| --- | --- |
| Linux | Full package tests, public validation suite, docs build, and formatter check run in CI. |
| macOS | Full package tests, public validation suite, and docs build run in CI. |
| Windows | Strict verifier smoke and docs syntax smoke run in CI. |
| HPC / other machines | Core verification should run wherever Julia 1.10+ and the package dependencies run. Optional tools depend on local installation. |

This means it is accurate to say that strict exact replay is cross-platform.
It is not accurate to claim that the full optional validation workflow is
equally covered on every platform.

## Core Verifier

The core verifier does not require numerical solvers, `msolve`, Sage, JuMP, or
SumOfSquares.jl. An independent checker can replay a strict certificate in a
minimal Julia environment:

```bash
bin/certsdp verify --strict cert.json
```

This path is the one to use for archived certificates, replay bundles, and
independent reproduction.

## Optional Workflows

Optional workflows add platform-specific requirements:

- `certsdp solve` and `solve_approximately` can use Clarabel as a numerical
  oracle when it is installed in the active Julia environment.
- Algebraic candidate generation can use an external `msolve` executable.
- The Sage/msolve adapter requires Sage and, when configured, an `msolve`
  executable.
- JuMP/MOI and SumOfSquares.jl extraction require their Julia packages and
  supported exact model shapes.

These tools may help construct a certificate, but verifier acceptance never
depends on their logs, residuals, status codes, or installed state.

## Recommended Claims

Use this wording in public release notes:

```text
Core strict verification supports Linux, macOS, Windows, and other Julia 1.10+
machines. Full package validation is tested on Linux/macOS; Windows currently
has verifier-only CI coverage.
```

Avoid claiming full Windows validation coverage until the full validation suite
runs there in CI.

## Claims To Avoid

| Do not say | Safer wording |
| --- | --- |
| Full validation is supported on every platform. | Core strict replay is cross-platform; full validation CI currently covers Linux/macOS. |
| Optional backends are bundled or required. | Optional backends are external candidate-generation tools. |
| Windows has the same validation coverage as Linux/macOS. | Windows currently has verifier-only and docs syntax smoke coverage. |
| Solver availability changes verifier trust. | Verifier acceptance is independent of optional tool installation. |
