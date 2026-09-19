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
# It also stages the OpusDM user config (~/.config/opusdm, theme included)
# and the desktop background into config/includes.chroot/etc/skel/, so the
# live user gets them from first login (adduser seeds /home/user from
# /etc/skel at boot, see build.sh). Absolute paths in settings.json that
# point at the dev machine (e.g. the background image_path) are rewritten
# to the live user's home.
#
# Usage:
#   ./scripts/build-opusdm.sh
#   OPUSDM_SRC=/path/to/opusdm OPUSDM_CONFIG_SRC=/path/to/.config/opusdm ./scripts/build-opusdm.sh
set -euo pipefail

IMAGE_TAG="dreamos-opusdm"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPUSDM_SRC="${OPUSDM_SRC:-/home/fabio/dev/projects/opusdm}"
OPUSDM_CONFIG_SRC="${OPUSDM_CONFIG_SRC:-${HOME}/.config/opusdm}"
BACKGROUND_SRC="${OPUSDM_SRC}/assets/backgrounds/dream01.jpg"
DEST_DIR="${PROJECT_DIR}/config/includes.chroot/usr/bin"
STAGE_DIR="${PROJECT_DIR}/.build/opusdm-bin"
REGISTRY_CACHE="${PROJECT_DIR}/cache/opusdm-cargo-registry"
TARBALL="${PROJECT_DIR}/vendor/opusdm/opusdm-bin.tar.gz"
LIVE_USER="user"
SKEL_DIR="${PROJECT_DIR}/config/includes.chroot/etc/skel"
CONFIG_DEST="${SKEL_DIR}/.config/opusdm"
BG_DEST="${SKEL_DIR}/opusdm/backgrounds/dream01.jpg"
LIVE_BG_PATH="/home/${LIVE_USER}/opusdm/backgrounds/dream01.jpg"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# Exit conditions up front
command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found" >&2; exit 1; }
test -f "${OPUSDM_SRC}/Cargo.toml" || {
    echo "OpusDM sources not found at ${OPUSDM_SRC} (set OPUSDM_SRC=...)" >&2
    exit 1
}
test -d "${OPUSDM_CONFIG_SRC}" || {
    echo "OpusDM config not found at ${OPUSDM_CONFIG_SRC} (set OPUSDM_CONFIG_SRC=...)" >&2
    exit 1
}
test -f "${BACKGROUND_SRC}" || {
    echo "Background image not found at ${BACKGROUND_SRC}" >&2
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

echo "==> Staging OpusDM user config into ${CONFIG_DEST#"${PROJECT_DIR}"/}"
rm -rf "${CONFIG_DEST}"
mkdir -p "$(dirname "${CONFIG_DEST}")"
cp -a "${OPUSDM_CONFIG_SRC}" "${CONFIG_DEST}"

echo "==> Staging desktop background into ${BG_DEST#"${PROJECT_DIR}"/}"
mkdir -p "$(dirname "${BG_DEST}")"
cp "${BACKGROUND_SRC}" "${BG_DEST}"

# The staged settings.json still points at the dev machine's absolute path;
# rewrite it to where the background actually lands on the live system.
_settings_json="${CONFIG_DEST}/settings.json"
if [ -f "${_settings_json}" ]; then
    jq --arg path "${LIVE_BG_PATH}" '.theme.background.image_path = $path' \
        "${_settings_json}" > "${_settings_json}.tmp"
    mv "${_settings_json}.tmp" "${_settings_json}"
fi

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
ls -la "${bin_names[@]/#/${DEST_DIR}/}" "${TARBALL}" "${CONFIG_DEST}" "${BG_DEST}"
