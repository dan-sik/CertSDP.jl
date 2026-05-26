# True External Raw Fixture

This fixture captures `references/repos/msolve/input_files/linear1-qq.ms`, an msolve repository input file, as raw external data.

- External source: msolve input format from `references/repos/msolve/input_files/linear1-qq.ms`
- Source hash: `sha256:86d5da99c363731730a147b57c22ad9e6455c799d8656a3d030d992808e45e6b`
- Captured date: 2026-05-26
- Capture procedure: read the file bytes from the msolve checkout in `references/repos/msolve`, store the exact lines and source hash in `raw_source_artifact.json`
- Raw format: variable line, characteristic line, and polynomial equations; it is not a CertSDP certificate schema
- Untrusted fields: external equations are provenance only; no solver status or claimed PSD result is trusted
- Normalization path: `capture_or_converter_script.jl` verifies the raw source hash and emits a CertSDP low-rank PSD certificate that is replayed offline
- Offline replay: `julia --project=. test/fixtures_real_external/capture_or_converter_script.jl test/fixtures_real_external/raw_source_artifact.json /tmp/certsdp_external.json`
