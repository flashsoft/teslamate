#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && git rev-parse --show-toplevel)"
cd "$repo_root"

patches=(
  "patches/0001-fork-publishing-config.patch"
  "patches/0002-configurable-nominatim-host.patch"
)

for patch in "${patches[@]}"; do
  echo "applying: $patch"
  if git apply --3way "$patch"; then
    continue
  fi

  if git apply --reverse --check "$patch" >/dev/null 2>&1; then
    echo "already applied: $patch"
    continue
  fi

  echo "failed to apply: $patch" >&2
  exit 1
done
