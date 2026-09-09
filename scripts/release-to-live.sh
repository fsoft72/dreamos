#!/usr/bin/env bash
#
# Cut a new rolling release. Rebuilds the OpusDM binaries and their
# tracked tarball, commits the tarball if it changed, then fast-forwards
# the `live` branch onto the source branch and pushes it. The push
# triggers .github/workflows/build-iso.yml, which builds the ISO and
# updates the `live-latest` GitHub release.
#
# Usage:
#   ./scripts/release-to-live.sh
#   OPUSDM_SRC=/path/to/opusdm ./scripts/release-to-live.sh
#   SOURCE_BRANCH=some-branch ./scripts/release-to-live.sh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_BRANCH="${SOURCE_BRANCH:-master}"
LIVE_BRANCH="live"
REMOTE="${REMOTE:-origin}"
TARBALL="vendor/opusdm/opusdm-bin.tar.gz"

cd "${PROJECT_DIR}"

# Exit conditions up front
[ -z "$(git status --porcelain)" ] || {
    echo "working tree is dirty, commit or stash first" >&2
    exit 1
}
_current_branch="$(git rev-parse --abbrev-ref HEAD)"
[ "${_current_branch}" = "${SOURCE_BRANCH}" ] || {
    echo "expected to be on '${SOURCE_BRANCH}', currently on '${_current_branch}'" >&2
    exit 1
}

echo "==> Rebuilding OpusDM binaries and ${TARBALL}"
./scripts/build-opusdm.sh

echo "==> Committing ${TARBALL} on ${SOURCE_BRANCH} (if changed)"
git add -f "${TARBALL}"
if git diff --cached --quiet; then
    echo "    tarball unchanged, nothing to commit"
else
    git commit -m "release: refresh OpusDM binaries"
fi

echo "==> Updating ${LIVE_BRANCH}"
git fetch "${REMOTE}"
if git show-ref --verify --quiet "refs/heads/${LIVE_BRANCH}"; then
    git checkout "${LIVE_BRANCH}"
elif git ls-remote --exit-code --heads "${REMOTE}" "${LIVE_BRANCH}" >/dev/null 2>&1; then
    git checkout -b "${LIVE_BRANCH}" "${REMOTE}/${LIVE_BRANCH}"
else
    git checkout -b "${LIVE_BRANCH}"
fi

git merge --no-edit "${SOURCE_BRANCH}"

echo "==> Pushing ${LIVE_BRANCH} to ${REMOTE}"
git push "${REMOTE}" "${LIVE_BRANCH}"

git checkout "${SOURCE_BRANCH}"

echo "==> Done. The ISO build is now running:"
echo "    https://github.com/fsoft72/dreamos/actions"
