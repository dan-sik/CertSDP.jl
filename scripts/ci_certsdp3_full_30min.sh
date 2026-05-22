#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

julia --project=. --startup-file=no scripts/check_certsdp3_static_rules.jl
julia --project=. --startup-file=no scripts/validate_certsdp3.jl --max-memory-gb=12 --timeout-minutes=30
julia --project=. --startup-file=no -e 'using Pkg; Pkg.test(; test_args=["certsdp3","validation"])'
julia --project=. --startup-file=no scripts/release_audit_certsdp3.jl
