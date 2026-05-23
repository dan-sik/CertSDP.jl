#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_HINT=""
PROJECT="$ROOT"
while [ "$PROJECT" != "/" ] && [ ! -f "$PROJECT/Project.toml" ]; do
  PROJECT="$(dirname "$PROJECT")"
done
if [ ! -f "$PROJECT/Project.toml" ]; then
  if [ -n "$PROJECT_HINT" ] && [ -f "$PROJECT_HINT/Project.toml" ]; then
    PROJECT="$PROJECT_HINT"
  elif [ -f "$PWD/Project.toml" ]; then
    PROJECT="$PWD"
  else
    echo "CertSDP Project.toml not found above bundle or current directory" >&2
    exit 3
  fi
fi
julia --project="$PROJECT" --startup-file=no -e 'using CertSDP; exit(CertSDP.Kernel.replay_file(joinpath(ARGS[1], "certificate.json"); strict=true).accepted ? 0 : 1)' "$ROOT"
