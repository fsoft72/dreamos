#!/usr/bin/env bash
# Build the dreamos live ISO inside a Debian trixie container.
# The Ubuntu host is never touched by live-build.
set -euo pipefail

IMAGE_TAG="dreamos-lb"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LB_OUTPUT="live-image-amd64.hybrid.iso"
FINAL_ISO="dreamos-amd64.hybrid.iso"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

cd "${PROJECT_DIR}"

echo "==> Building Docker image ${IMAGE_TAG}"
docker build -t "${IMAGE_TAG}" "${PROJECT_DIR}"

echo "==> Running lb build (privileged container)"
# live-build needs root inside the container for debootstrap and chroot
# mounts. It writes artifacts into the bind mount as root, so hand
# ownership back to the invoking user before exiting.
docker run --rm --privileged \
    -v "${PROJECT_DIR}:/build" \
    -w /build \
    -e "HOST_UID=${HOST_UID}" \
    -e "HOST_GID=${HOST_GID}" \
    "${IMAGE_TAG}" \
    bash -c '
        set -euo pipefail
        trap "chown -R ${HOST_UID}:${HOST_GID} /build" EXIT
        ./auto/clean || true
        lb config
        lb build
    '

test -f "${PROJECT_DIR}/${LB_OUTPUT}" || {
    echo "ERROR: expected ${LB_OUTPUT} was not produced" >&2
    exit 1
}

mv "${PROJECT_DIR}/${LB_OUTPUT}" "${PROJECT_DIR}/${FINAL_ISO}"
echo "==> ISO ready: ${PROJECT_DIR}/${FINAL_ISO}"
