#!/usr/bin/env bash
#
# Build the OpusDM binaries (opusdm-hub, opusdm-lister) inside a Debian
# trixie container and stage them into the live ISO tree at
# config/includes.chroot/usr/bin/. opusdm-hub is the dreamos desktop
# shell, so run this once before ./build.sh and again whenever the
# OpusDM sources change.
#
# The Ubuntu host toolchain is never used: its glibc (2.42) is newer than
# trixie's (2.41), so host-built binaries fail to start on the ISO.
#
# Usage:
#   ./scripts/build-opusdm.sh
#   OPUSDM_SRC=/path/to/opusdm ./scripts/build-opusdm.sh
set -euo pipefail

IMAGE_TAG="dreamos-opusdm"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPUSDM_SRC="${OPUSDM_SRC:-/home/fabio/dev/projects/opusdm}"
DEST_DIR="${PROJECT_DIR}/config/includes.chroot/usr/bin"
STAGE_DIR="${PROJECT_DIR}/.build/opusdm-bin"
REGISTRY_CACHE="${PROJECT_DIR}/cache/opusdm-cargo-registry"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# Exit conditions up front
command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 1; }
test -f "${OPUSDM_SRC}/Cargo.toml" || {
    echo "OpusDM sources not found at ${OPUSDM_SRC} (set OPUSDM_SRC=...)" >&2
    exit 1
}

cd "${PROJECT_DIR}"
mkdir -p "${DEST_DIR}" "${STAGE_DIR}" "${REGISTRY_CACHE}"

echo "==> Building Docker image ${IMAGE_TAG}"
docker build -t "${IMAGE_TAG}" \
    -f "${PROJECT_DIR}/scripts/Dockerfile.opusdm" \
    "${PROJECT_DIR}/scripts"

echo "==> Compiling OpusDM (release) in a trixie container"
# The source is mounted read-only and copied into the container before
# building, so cargo can freely update target/ and Cargo.lock without
# touching the host checkout. Only the finished binaries and the crates.io
# registry cache are written back to the host tree.
docker run --rm \
    -v "${OPUSDM_SRC}:/src:ro" \
    -v "${STAGE_DIR}:/out" \
    -v "${REGISTRY_CACHE}:/opt/cargo/registry" \
    -e "HOST_UID=${HOST_UID}" \
    -e "HOST_GID=${HOST_GID}" \
    "${IMAGE_TAG}" \
    bash -c '
        set -euo pipefail
        trap "chown -R ${HOST_UID}:${HOST_GID} /out /opt/cargo/registry" EXIT
        cp -a /src/. /work/
        cargo build --release --workspace \
            --bin opusdm-hub --bin opusdm-lister
        cp target/release/opusdm-hub target/release/opusdm-lister /out/
    '

echo "==> Installing binaries into ${DEST_DIR#"${PROJECT_DIR}"/}"
install -Dm755 "${STAGE_DIR}/opusdm-hub" "${DEST_DIR}/opusdm-hub"
install -Dm755 "${STAGE_DIR}/opusdm-lister" "${DEST_DIR}/opusdm-lister"

echo "==> Done:"
ls -la "${DEST_DIR}/opusdm-hub" "${DEST_DIR}/opusdm-lister"
