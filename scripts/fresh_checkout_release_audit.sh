#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: scripts/fresh_checkout_release_audit.sh [options]

Clone the current repository into a temporary clean checkout and run the
release audit drill against that checkout.

Options:
  --repo DIR       source repository (default: git root or pwd)
  --workdir DIR    parent directory for the clean clone (default: mktemp -d)
  --seed N         release audit drill seed (default: 2912)
  --include-worktree
                   overlay current tracked and untracked worktree changes
                   after cloning; use this for pre-tag local release checks
  --keep           keep the clone after the run
  -h, --help       show this help
USAGE
}

repo=""
workdir=""
seed="2912"
keep="false"
include_worktree="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="$2"
      shift 2
      ;;
    --workdir)
      workdir="$2"
      shift 2
      ;;
    --seed)
      seed="$2"
      shift 2
      ;;
    --include-worktree)
      include_worktree="true"
      shift
      ;;
    --keep)
      keep="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$repo" ]]; then
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    repo="$(git rev-parse --show-toplevel)"
  else
    repo="$(pwd)"
  fi
fi

repo="$(cd "$repo" && pwd)"
script_source="$repo/scripts/release_audit.jl"
if [[ ! -f "$script_source" ]]; then
  echo "missing release audit script: $script_source" >&2
  exit 2
fi

if [[ -z "$workdir" ]]; then
  workdir="$(mktemp -d "${TMPDIR:-/tmp}/certsdp-audit-XXXXXX")"
fi
mkdir -p "$workdir"
workdir="$(cd "$workdir" && pwd)"

clone="$workdir/CertSDP-clean"
rm -rf "$clone"
git clone --quiet "$repo" "$clone"

if [[ "$include_worktree" == "true" ]]; then
  patch_file="$workdir/worktree.patch"
  git -C "$repo" diff --binary HEAD > "$patch_file"
  if [[ -s "$patch_file" ]]; then
    git -C "$clone" apply "$patch_file"
  fi
  while IFS= read -r -d '' relpath; do
    mkdir -p "$clone/$(dirname "$relpath")"
    cp -p "$repo/$relpath" "$clone/$relpath"
  done < <(git -C "$repo" ls-files --others --exclude-standard -z)
fi

if [[ "$keep" != "true" ]]; then
  cleanup() {
    rm -rf "$workdir"
  }
  trap cleanup EXIT
fi

echo "[INFO] clean clone: $clone"
echo "[INFO] source release audit script: $script_source"
if [[ "$include_worktree" == "true" ]]; then
  echo "[INFO] included current worktree changes"
fi
echo "[INFO] references/ is ignored local research context and is not cloned"

julia --project="$clone" -e 'using Pkg; Pkg.instantiate()'

clone_script="$clone/scripts/release_audit.jl"
if [[ -f "$clone_script" ]]; then
  drill_script="$clone_script"
else
  drill_script="$script_source"
fi

julia --project="$clone" "$drill_script" \
  --repo "$clone" \
  --out "$clone/reports/fresh_checkout_release_audit" \
  --mode sampled-clean \
  --seed "$seed" \
  --skip-package-dry-run

echo "[OK] fresh checkout release audit completed"
echo "[INFO] report: $clone/reports/fresh_checkout_release_audit/release_audit_report.md"
