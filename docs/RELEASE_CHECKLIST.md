# Release Checklist

The release gate lives at the repository root: `RELEASE_CHECKLIST.md`.

That file records the v1.0 checklist, required local commands, blocker policy,
and post-tag cautions.

Use it together with the readiness report in
`docs/V1_RELEASE_READINESS.md` and the packaging notes in
`docs/release_path.md`. The checklist is intentionally terse: it is the
operator-facing gate to run before tagging, while the readiness report records
the outcome of the current release-candidate pass. Both documents are part of
the public release evidence because independent readers should be able to see
exactly which commands were used to establish the validation claim.

The checklist is not a substitute for the verifier trust model. A release gate
can only say that the package, documentation, validation suite, and release
audit drill passed on the checked environment. Mathematical acceptance remains the
responsibility of `verify --strict`, which replays certificate obligations
exactly and ignores solver logs or cached backend claims.
