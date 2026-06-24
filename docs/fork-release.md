# Fork Release Runbook

This fork keeps upstream TeslaMate history intact and reapplies fork-specific changes as patches.

## Remotes

- `origin`: `https://github.com/flashsoft/teslamate.git`
- `upstream`: `https://github.com/teslamate-org/teslamate.git`
- `upstream` push URL is disabled on purpose.

## Fork patches

Patch files live in `patches/`:

- `0001-fork-publishing-config.patch`
  - publishes Docker Hub images under `babyworld/teslamate`
  - uses `DOCKER_USERNAME` for Docker Hub login
  - publishes GHCR release tags under `ghcr.io/flashsoft/teslamate`
  - lowercases GHCR build-cache refs
  - lets `v*` tag pushes publish even when the tagged commit changes `.github/**`
- `0002-configurable-nominatim-host.patch`
  - adds `NOMINATIM_HOST`
  - updates HTTP pool and geocoder behavior
  - includes tests and docs

Apply patches on top of a clean upstream checkout:

```bash
./scripts/apply-fork-patches.sh
```

The script uses `git apply --3way`. A successful apply leaves changes staged.

## Main branch sync

`main` should track `upstream/main` plus fork patches and release tooling.

```bash
git switch main
git fetch upstream --prune --tags
git merge upstream/main
git diff --binary upstream/main -- .github/actions/build/action.yml .github/workflows/buildx.yml .github/workflows/ghcr_build.yml README.md > patches/0001-fork-publishing-config.patch
git diff --binary upstream/main -- lib/teslamate/http.ex lib/teslamate/locations/geocoder.ex test/teslamate/http_test.exs test/teslamate/locations/geocoder_test.exs website/docs/configuration/environment_variables.md > patches/0002-configurable-nominatim-host.patch
git status --short
```

Verify the patcher against a clean upstream worktree:

```bash
git worktree add --detach /tmp/teslamate-patch-test upstream/main
mkdir -p /tmp/teslamate-patch-test/patches /tmp/teslamate-patch-test/scripts
cp patches/*.patch /tmp/teslamate-patch-test/patches/
cp scripts/apply-fork-patches.sh /tmp/teslamate-patch-test/scripts/
/tmp/teslamate-patch-test/scripts/apply-fork-patches.sh
git -C /tmp/teslamate-patch-test diff --cached --stat
git worktree remove --force /tmp/teslamate-patch-test
```

## Docker Hub release tags

Docker Hub publishing is handled by `.github/workflows/buildx.yml`.

Published repository:

```text
babyworld/teslamate
```

Release tags are created by pushing `v*` Git tags. For example, pushing `v4.0.1` should publish:

```text
babyworld/teslamate:4.0.1
babyworld/teslamate:4.0
```

The workflow intentionally bypasses path filtering for `v*` tag pushes:

```yaml
startsWith(github.ref, 'refs/tags/v')
```

This matters because release commits can include `.github/**` changes. Without the tag bypass, the workflow can appear successful while build jobs are skipped.

Scheduled runs publish `edge`.

## GHCR images

GHCR publishing is handled by `.github/workflows/ghcr_build.yml`.

Published repository:

```text
ghcr.io/flashsoft/teslamate
ghcr.io/flashsoft/teslamate/grafana
```

GHCR publishing is handled separately from Docker Hub, but follows the same version-tag rule:

- `main` pushes publish `main`
- pull requests publish PR tags for internal PRs
- `v*` tag pushes publish semver tags such as `4.0.1` and `4.0`

The workflow bypasses path filtering for `v*` tag pushes for the same reason as Docker Hub releases: release commits can contain `.github/**` changes.

GHCR cache refs used by Docker Hub builds are separate from GHCR release images:

```text
ghcr.io/flashsoft/teslamate:buildcache-...
```

## Releasing an upstream tag with fork patches

Use the same Git tag name as upstream, but point it to the fork-patched commit.

Example for `v4.0.1`:

```bash
git fetch upstream --tags
git tag upstream/v4.0.1 v4.0.1^{}
git switch -c release/v4.0.1-fork v4.0.1^{}
./scripts/apply-fork-patches.sh
git commit -m "Apply fork patches to v4.0.1"
git push -u origin release/v4.0.1-fork
git tag -f v4.0.1 release/v4.0.1-fork
git push origin refs/tags/v4.0.1 --force
```

Preserve the upstream target before moving the local release tag:

```bash
git tag upstream/v4.0.1 v4.0.1^{}
```

If the backup tag already exists, verify it before replacing it.

## Verification

Check GitHub Actions:

```bash
curl -sS "https://api.github.com/repos/flashsoft/teslamate/actions/runs?per_page=10"
```

For a valid Docker Hub tag release, the `Publish Docker images` run for `v*` should have these jobs completed successfully:

- `teslamate_build (linux/amd64, ubuntu-24.04, amd64)`
- `teslamate_build (linux/arm64, ubuntu-24.04-arm, arm64)`
- `teslamate_merge`
- `grafana`

Check Docker Hub:

```bash
curl -sS "https://hub.docker.com/v2/repositories/babyworld/teslamate/tags/4.0.1"
curl -sS "https://hub.docker.com/v2/repositories/babyworld/teslamate/tags/4.0"
```

Do not treat the presence of only `edge` as a release. `edge` comes from scheduled Docker Hub builds.
