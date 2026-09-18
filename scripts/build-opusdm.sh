#!/usr/bin/env bash
#
# Build every binary defined in the OpusDM cargo workspace inside a Debian
# trixie container and stage them into the live ISO tree at
# config/includes.chroot/usr/bin/. The binary list is discovered from the
# workspace itself (via `cargo metadata`), so a new [[bin]] target added to
# any OpusDM crate is picked up automatically, no edits needed here.
# opusdm-hub is the dreamos desktop shell, so run this once before
# ./build.sh and again whenever the OpusDM sources change.
#
# It also refreshes vendor/opusdm/opusdm-bin.tar.gz, the tracked artifact
# that carries the binaries to environments without the OpusDM sources
# (a fresh checkout, the GitHub Actions ISO build). build.sh unpacks it
# when the loose binaries are absent.
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
TARBALL="${PROJECT_DIR}/vendor/opusdm/opusdm-bin.tar.gz"
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
#
# The set of binaries to build/install is discovered from `cargo metadata`
# (every [[bin]] target across the workspace's own crates), not hardcoded,
# so a new OpusDM binary crate is staged automatically the next time this
# script runs.
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
        cargo build --release --workspace
        bin_names="$(cargo metadata --no-deps --format-version=1 \
            | jq -r ".packages[].targets[] | select(.kind[] == \"bin\") | .name" \
            | sort -u)"
        [ -n "${bin_names}" ] || { echo "no [[bin]] targets found in workspace" >&2; exit 1; }
        for bin_name in ${bin_names}; do
            cp "target/release/${bin_name}" /out/
        done
    '

# Discover the staged binary names from what the container actually wrote,
# so everything below stays in lockstep with the workspace's [[bin]] targets.
bin_names=()
while IFS= read -r -d '' bin_path; do
    bin_names+=("$(basename "${bin_path}")")
done < <(find "${STAGE_DIR}" -maxdepth 1 -type f -not -name MANIFEST -print0)
IFS=$'\n' bin_names=($(sort <<<"${bin_names[*]}")); unset IFS

echo "==> Installing binaries into ${DEST_DIR#"${PROJECT_DIR}"/}"
for bin_name in "${bin_names[@]}"; do
    install -Dm755 "${STAGE_DIR}/${bin_name}" "${DEST_DIR}/${bin_name}"
done

echo "==> Refreshing ${TARBALL#"${PROJECT_DIR}"/}"
# Record which OpusDM revision produced these binaries, when the source
# tree is a git checkout.
_opusdm_ref="unknown"
if git -C "${OPUSDM_SRC}" rev-parse --git-dir >/dev/null 2>&1; then
    _opusdm_ref="$(git -C "${OPUSDM_SRC}" describe --always --dirty --tags 2>/dev/null \
        || git -C "${OPUSDM_SRC}" rev-parse --short HEAD)"
fi
_bin_list="$(printf '%s, ' "${bin_names[@]}")"
_bin_list="${_bin_list%, }"
printf '%s\nopusdm-ref: %s\n' "${_bin_list}" "${_opusdm_ref}" \
    > "${STAGE_DIR}/MANIFEST"
chmod 755 "${bin_names[@]/#/${STAGE_DIR}/}"
mkdir -p "$(dirname "${TARBALL}")"
# Reproducible archive: fixed entry order, owner and mtime, and gzip
# without a name/timestamp header, so an unchanged build produces a
# byte-identical tarball and no noisy git diff.
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='@0' \
    -cf - -C "${STAGE_DIR}" "${bin_names[@]}" MANIFEST \
    | gzip -n -9 > "${TARBALL}"

echo "==> Done:"
ls -la "${bin_names[@]/#/${DEST_DIR}/}" "${TARBALL}"
