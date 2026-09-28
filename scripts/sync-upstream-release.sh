#!/usr/bin/env bash
# Releases the latest upstream tag as a fork tag with the fork patches
# applied, then triggers the image build workflows.
#
# Designed for CI (.github/workflows/fork_sync.yml), but can be run locally:
#
#   DRY_RUN=1 ./scripts/sync-upstream-release.sh   # everything except push
#   FORCE=1   re-release even if the fork already has the tag
#
# Environment:
#   UPSTREAM_URL  upstream remote URL (default: teslamate-org/teslamate)
#   DRY_RUN       set to 1 to stop before pushing and dispatching builds
#   FORCE         set to 1 to delete and re-create an existing fork tag
set -euo pipefail

# Prefer the current directory's repository: the CI workflow runs a copy of
# this script from $RUNNER_TEMP, because the checkout of the upstream tag
# below deletes the in-worktree copy of this very file.
if ! repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	repo_root="$(cd "$script_dir/.." && git rev-parse --show-toplevel)"
fi
cd "$repo_root"

upstream_url="${UPSTREAM_URL:-https://github.com/teslamate-org/teslamate.git}"
dry_run="${DRY_RUN:-0}"
force="${FORCE:-0}"

if ! git remote get-url upstream >/dev/null 2>&1; then
	git remote add upstream "$upstream_url"
fi

# Fetch upstream release tags into a separate namespace so they can never
# collide with the fork's own (already patched) v* tags.
git fetch --no-tags upstream main
git fetch upstream '+refs/tags/v*:refs/tags/upstream/v*'

# Upstream tags belong in refs/tags/upstream/* only. A plain
# `git fetch --tags` leaks them into refs/tags/v*, where they are
# indistinguishable from fork releases. Remove leaked copies (same commit
# as the upstream tag); keep diverging tags (those are fork releases).
while read -r upstream_tag; do
	version="${upstream_tag#upstream/}"
	upstream_commit="$(git rev-list -n1 "refs/tags/$upstream_tag")"
	if local_commit="$(git rev-list -n1 "refs/tags/$version" 2>/dev/null)"; then
		if [ "$local_commit" = "$upstream_commit" ]; then
			echo "removing leaked upstream tag: $version"
			git tag -d "$version" >/dev/null
		fi
	fi
done <<<"$(git tag -l 'upstream/v*')"

latest="$(git tag -l 'upstream/v*' --sort=-v:refname | head -n1)"
if [ -z "$latest" ]; then
	echo "no upstream release tags found"
	exit 0
fi
version="${latest#upstream/}"
echo "latest upstream release: $version"

version_commit="$(git rev-list -n1 "refs/tags/$latest")"
if local_commit="$(git rev-list -n1 "refs/tags/$version" 2>/dev/null)"; then
	if [ "$local_commit" = "$version_commit" ]; then
		# Leaked copy of the upstream tag; the cleanup above removes these, so
		# reaching here means the deletion was refused. Recreate it patched.
		echo "replacing unpatched fork tag: $version"
		git tag -d "$version" >/dev/null
	elif [ "$force" != "1" ]; then
		echo "$version already released by the fork; nothing to do"
		exit 0
	else
		echo "FORCE: re-releasing $version"
		git tag -d "$version" >/dev/null
		git push origin ":refs/tags/$version"
	fi
fi

# The patches live in the fork only, so a checkout of the upstream tag does
# not contain them. Apply them from a temporary copy with both scripts, so
# the checkout does not trip over modified fork-only script files.
patches_tmp="$(mktemp -d)"
trap 'rm -rf "$patches_tmp"' EXIT
git show main:patches/0001-fork-publishing-config.patch >"$patches_tmp/0001-fork-publishing-config.patch"
git show main:patches/0002-configurable-nominatim-host.patch >"$patches_tmp/0002-configurable-nominatim-host.patch"
git show main:scripts/apply-fork-patches.sh >"$patches_tmp/apply-fork-patches.sh"
chmod +x "$patches_tmp/apply-fork-patches.sh"

git checkout --detach "refs/tags/$latest"
(cd "$repo_root" && "$patches_tmp/apply-fork-patches.sh" "$patches_tmp")

if git diff --cached --quiet; then
	echo "error: patches produced no changes for $version" >&2
	exit 1
fi

git commit -m "Apply fork patches to $version"
git tag "$version"

if [ "$dry_run" = "1" ]; then
	echo "DRY_RUN: would push tag $version and trigger the image builds"
	exit 0
fi

git push origin "refs/tags/$version"

# Pushing with GITHUB_TOKEN does not trigger other workflows, so the image
# builds are dispatched explicitly. Both build workflows accept
# workflow_dispatch and derive the semver tags from the tag ref.
if command -v gh >/dev/null 2>&1; then
	gh workflow run buildx.yml --ref "$version"
	gh workflow run ghcr_build.yml --ref "$version"
	echo "triggered image builds for $version"
else
	echo "warning: gh CLI not found; trigger the build workflows manually" >&2
fi
