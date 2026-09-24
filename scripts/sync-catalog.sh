#!/usr/bin/env bash
# Copies the canonical nutrition catalog into the server and client packages.
# go:embed and Flutter assets cannot reference files outside their own module,
# so each side keeps a byte-identical copy. Tests on both sides fail on drift.
#
# Usage: scripts/sync-catalog.sh [--check]
#   --check  only verify that the copies are identical; exit 1 otherwise.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
canonical="$root/protocol/nutrition/catalog.json"
targets=(
  "$root/server/internal/nutrition/catalog.json"
  "$root/apps/client/assets/catalog/foods.json"
)

if [[ ! -f "$canonical" ]]; then
  echo "canonical catalog not found: $canonical" >&2
  exit 1
fi

status=0
for target in "${targets[@]}"; do
  if [[ "${1:-}" == "--check" ]]; then
    if ! cmp -s "$canonical" "$target"; then
      echo "out of sync: $target" >&2
      status=1
    fi
  else
    mkdir -p "$(dirname "$target")"
    cp "$canonical" "$target"
    echo "synced: $target"
  fi
done
exit $status
