#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Prefer the current directory's repository (the release script invokes
# this from the repo root with a copy of this script outside the worktree);
# fall back to the script's own location for direct in-repo use.
if ! repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
	repo_root="$(cd "$script_dir/.." && git rev-parse --show-toplevel)"
fi
cd "$repo_root"

# Optional first argument: directory holding the patch files. Defaults to
# the in-repo patches/ directory; the release script passes a temporary
# copy because the patches are not part of the upstream tag checkouts.
patches_dir="${1:-patches}"

patches=(
	"$patches_dir/0001-fork-publishing-config.patch"
	"$patches_dir/0002-configurable-nominatim-host.patch"
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
