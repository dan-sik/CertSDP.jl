#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
julia --project="/Users/shani_mac/CertSDP/" --startup-file=no -e 'using CertSDP; exit(CertSDP.Kernel.replay_file(joinpath(ARGS[1], "certificate.json"); strict=true).accepted ? 0 : 1)' "$ROOT"
