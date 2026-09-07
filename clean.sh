#!/usr/bin/env bash
# Remove live-build artifacts. With --all, also drop the package cache
# and any built ISO.
set -euo pipefail

IMAGE_TAG="dreamos-lb"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

cd "${PROJECT_DIR}"

docker run --rm --privileged \
    -v "${PROJECT_DIR}:/build" \
    -w /build \
    -e "HOST_UID=${HOST_UID}" \
    -e "HOST_GID=${HOST_GID}" \
    "${IMAGE_TAG}" \
    bash -c '
        set -eu
        trap "chown -R ${HOST_UID}:${HOST_GID} /build" EXIT
        ./auto/clean --purge || lb clean noauto --purge
    '

if [[ "${1:-}" == "--all" ]]; then
    rm -rf "${PROJECT_DIR}/cache"
    rm -f "${PROJECT_DIR}"/*.iso
    echo "==> Removed cache/ and *.iso"
fi

echo "==> Clean complete"
