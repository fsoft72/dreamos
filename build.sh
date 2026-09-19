#!/usr/bin/env bash
# Build the dreamos live ISO inside a Debian trixie container.
# The Ubuntu host is never touched by live-build.
#
# Default: full clean + full lb build (debootstrap, package install, the
# lot). Use --fast to iterate on config/includes.chroot (e.g. new opusdm
# binaries) against an already-built chroot/: it force-recopies the
# includes and only redoes the binary (squashfs+iso) stage, skipping
# debootstrap and package installation entirely. Falls back to a full
# build automatically if chroot/ does not exist yet.
set -euo pipefail

FAST="true"
for _arg in "${@}"; do
    [ "${_arg}" = "--full" ] && FAST="false"
done

IMAGE_TAG="dreamos-lb"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LB_OUTPUT="live-image-amd64.hybrid.iso"
FINAL_ISO="dreamos-amd64.hybrid.iso"
BIN_DIR="config/includes.chroot/usr/bin"
OPUSDM_TARBALL="vendor/opusdm/opusdm-bin.tar.gz"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

cd "${PROJECT_DIR}"

# opusdm-hub / opusdm-lister are the live desktop shell. They are built in
# a separate trixie container (the host toolchain links the wrong glibc),
# so they must be staged before the ISO build runs. On a machine with the
# OpusDM sources that is scripts/build-opusdm.sh; without them (a fresh
# checkout, CI) unpack the tracked tarball it leaves behind.
if [ ! -x "${BIN_DIR}/opusdm-hub" ] || [ ! -x "${BIN_DIR}/opusdm-lister" ]; then
    if [ -f "${OPUSDM_TARBALL}" ]; then
        echo "==> Unpacking ${OPUSDM_TARBALL}"
        mkdir -p "${BIN_DIR}"
        tar -xzf "${OPUSDM_TARBALL}" -C "${BIN_DIR}" opusdm-hub opusdm-lister
        chmod 755 "${BIN_DIR}/opusdm-hub" "${BIN_DIR}/opusdm-lister"
    fi
fi

for _bin in opusdm-hub opusdm-lister; do
    if [ ! -x "${BIN_DIR}/${_bin}" ]; then
        echo "ERROR: ${BIN_DIR}/${_bin} is missing." >&2
        echo "       Run ./scripts/build-opusdm.sh first (it also writes" >&2
        echo "       ${OPUSDM_TARBALL})." >&2
        exit 1
    fi
done

if [ "${FAST}" = "true" ] && [ ! -d "${PROJECT_DIR}/chroot" ]; then
    echo "==> --fast requested but no chroot/ yet; doing a full build first"
    FAST="false"
fi

echo "==> Building Docker image ${IMAGE_TAG}"
docker build -t "${IMAGE_TAG}" "${PROJECT_DIR}"

# live-build needs root inside the container for debootstrap and chroot
# mounts. It writes artifacts into the bind mount as root, so hand
# ownership back to the invoking user before exiting.
if [ "${FAST}" = "true" ]; then
    echo "==> Running fast rebuild: recopy includes + binary stage only (privileged container)"
    docker run --rm --privileged \
        -v "${PROJECT_DIR}:/build" \
        -w /build \
        -e "HOST_UID=${HOST_UID}" \
        -e "HOST_GID=${HOST_GID}" \
        "${IMAGE_TAG}" \
        bash -c '
            set -euo pipefail
            trap "chown -R ${HOST_UID}:${HOST_GID} /build" EXIT
            lb config
            lb chroot_includes_after_packages --force
            lb clean noauto --binary
            lb build
        '
else
    echo "==> Running lb build (privileged container)"
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
fi

test -f "${PROJECT_DIR}/${LB_OUTPUT}" || {
    echo "ERROR: expected ${LB_OUTPUT} was not produced" >&2
    exit 1
}

mv "${PROJECT_DIR}/${LB_OUTPUT}" "${PROJECT_DIR}/${FINAL_ISO}"
echo "==> ISO ready: ${PROJECT_DIR}/${FINAL_ISO}"
