# Release Path

This page records the public packaging path for a v1.0 release. It is not a
claim that the package is already registered or archived; it is the checklist
for turning the release-candidate repository into a citable public artifact.

## Julia Registry

Before submitting to General:

- confirm `VERSION`, `Project.toml`, `Manifest.toml`, `CITATION.cff`, and
  `codemeta.json` agree on the release version;
- run `Pkg.test()`, the Documenter build, the validation suite, release audit drill,
  and the fresh-checkout drill listed in [Release Checklist](RELEASE_CHECKLIST.md);
- submit the tagged release through the standard Julia Registrator flow;
- wait for General registry review before claiming registry availability.

The local registration dry-run in the release audit drill checks metadata and
loadability. It does not replace Registrator or General registry review.

## Automation

The repository includes two post-release maintenance workflows:

| Workflow | File | Purpose |
| --- | --- | --- |
| TagBot | `.github/workflows/tagbot.yml` | Create GitHub tags/releases after Julia registry merge events. |
| CompatHelper | `.github/workflows/compathelper.yml` | Open dependency compatibility PRs on a schedule or manual trigger. |

Both workflows rely on standard GitHub Actions tokens. They are inert until the
repository is public enough for GitHub Actions and, for TagBot, the package is
registered.

## Badges

The README exposes separate release evidence signals:

- CI: package tests, validation, docs build, Windows verifier smoke, formatter;
- Docs: standalone Documenter build;
- Validation: standalone validation report generation;
- Julia version and Apache-2.0 license.

Do not add a registry or DOI badge until the registry entry or Zenodo DOI
exists.

## Archival Artifact

For a citable release:

1. Tag the release after all gates pass.
2. Archive the GitHub release on Zenodo or an equivalent DOI service.
3. Add the minted DOI to `CITATION.cff`, `codemeta.json`, release notes, and
   the README citation section.
4. Attach or link the validation report and, when useful, replay bundles
   produced by `certsdp bundle`.

The raw artifacts are data-only. An independent checker should be able to run:

```bash
bin/certsdp replay artifact.zip
```

and get acceptance from strict exact replay without trusting backend logs,
solver output, or local artifact paths.
