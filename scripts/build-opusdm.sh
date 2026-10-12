#!/usr/bin/env bash
#
# Build every binary defined in the OpusDM cargo workspace, plus every
# standalone crate under dreamos-tools, inside a Debian trixie container
# and stage them into the live ISO tree at config/includes.chroot/usr/bin/.
# The OpusDM binary list is discovered from the workspace itself (via
# `cargo metadata`), so a new [[bin]] target added to any OpusDM crate is
# picked up automatically, no edits needed here. dreamos-tools has no
# workspace (each subdirectory with a Cargo.toml is its own crate), so its
# crates are discovered by scanning TOOLS_SRC for Cargo.toml files and
# built one at a time.
# opusdm-hub is the dreamos desktop shell, so run this once before
# ./build.sh and again whenever the OpusDM or dreamos-tools sources change.
#
# It also refreshes vendor/opusdm/opusdm-bin.tar.gz and
# vendor/dreamos-tools/dreamos-tools-bin.tar.gz, the tracked artifacts that
# carry the binaries to environments without the sources (a fresh
# checkout, the GitHub Actions ISO build). build.sh unpacks the OpusDM one
# when the loose binaries are absent.
#
# The Ubuntu host toolchain is never used: its glibc (2.42) is newer than
# trixie's (2.41), so host-built binaries fail to start on the ISO.
#
# It also stages the OpusDM defaults into config/includes.chroot/etc/skel/,
# so the live user gets them from first login (adduser seeds /home/user from
# /etc/skel at boot, see build.sh): the desktop background and the base
# picom.conf are copied from the OpusDM sources. The ~/.config/opusdm files
# in skel (settings.json, desktop.json) are hand-written defaults tracked in
# this repo: they are NEVER copied from the developer's own ~/.config/opusdm
# (that would ship personal menus, hotkeys, startup apps, known hosts and
# paths). Every other config file is created by OpusDM itself on first run.
#
# Cargo builds in the container reuse a persistent target directory
# (cache/opusdm-target, cache/dreamos-tools-target), so a rebuild only
# recompiles what changed. When only the defaults changed, skip compiling
# altogether with --config-only.
#
# Usage:
#   ./scripts/build-opusdm.sh                 compile + stage everything
#   ./scripts/build-opusdm.sh --config-only   only refresh background and picom.conf
#   OPUSDM_SRC=/path/to/opusdm TOOLS_SRC=/path/to/dreamos-tools ./scripts/build-opusdm.sh
set -euo pipefail

CONFIG_ONLY="false"
for _arg in "${@}"; do
    case "${_arg}" in
        --config-only) CONFIG_ONLY="true" ;;
        *) echo "Unknown option: ${_arg} (supported: --config-only)" >&2; exit 1 ;;
    esac
done

IMAGE_TAG="dreamos-opusdm"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPUSDM_SRC="${OPUSDM_SRC:-/home/fabio/dev/projects/opusdm}"
TOOLS_SRC="${TOOLS_SRC:-/home/fabio/dev/projects/dreamos-tools}"
PICOM_SRC="${OPUSDM_SRC}/picom.conf"
BACKGROUND_SRC="${OPUSDM_SRC}/assets/backgrounds/dream01.jpg"
DEST_DIR="${PROJECT_DIR}/config/includes.chroot/usr/bin"
STAGE_DIR="${PROJECT_DIR}/.build/opusdm-bin"
TOOLS_STAGE_DIR="${PROJECT_DIR}/.build/dreamos-tools-bin"
REGISTRY_CACHE="${PROJECT_DIR}/cache/opusdm-cargo-registry"
TARGET_CACHE="${PROJECT_DIR}/cache/opusdm-target"
TOOLS_TARGET_CACHE="${PROJECT_DIR}/cache/dreamos-tools-target"
TARBALL="${PROJECT_DIR}/vendor/opusdm/opusdm-bin.tar.gz"
TOOLS_TARBALL="${PROJECT_DIR}/vendor/dreamos-tools/dreamos-tools-bin.tar.gz"
SKEL_DIR="${PROJECT_DIR}/config/includes.chroot/etc/skel"
CONFIG_DEST="${SKEL_DIR}/.config/opusdm"
PICOM_DEST="${CONFIG_DEST}/picom.conf"
BG_DEST="${SKEL_DIR}/opusdm/backgrounds/dream01.jpg"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# Exit conditions up front
test "${CONFIG_ONLY}" = "true" || command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 1; }
test -f "${OPUSDM_SRC}/Cargo.toml" || {
    echo "OpusDM sources not found at ${OPUSDM_SRC} (set OPUSDM_SRC=...)" >&2
    exit 1
}
test -f "${PICOM_SRC}" || {
    echo "picom.conf not found at ${PICOM_SRC}" >&2
    exit 1
}
test -f "${BACKGROUND_SRC}" || {
    echo "Background image not found at ${BACKGROUND_SRC}" >&2
    exit 1
}
test "${CONFIG_ONLY}" = "true" || test -d "${TOOLS_SRC}" || {
    echo "dreamos-tools sources not found at ${TOOLS_SRC} (set TOOLS_SRC=...)" >&2
    exit 1
}

cd "${PROJECT_DIR}"

echo "==> Staging desktop background into ${BG_DEST#"${PROJECT_DIR}"/}"
mkdir -p "$(dirname "${BG_DEST}")"
cp "${BACKGROUND_SRC}" "${BG_DEST}"

echo "==> Staging base picom.conf into ${PICOM_DEST#"${PROJECT_DIR}"/}"
mkdir -p "$(dirname "${PICOM_DEST}")"
cp "${PICOM_SRC}" "${PICOM_DEST}"

if [ "${CONFIG_ONLY}" = "true" ]; then
    echo "==> Done (--config-only): binaries and tarballs left untouched"
    exit 0
fi

mkdir -p "${DEST_DIR}" "${STAGE_DIR}" "${TOOLS_STAGE_DIR}" "${REGISTRY_CACHE}" \
    "${TARGET_CACHE}" "${TOOLS_TARGET_CACHE}"


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
    -v "${TARGET_CACHE}:/cargo-target" \
    -e CARGO_TARGET_DIR=/cargo-target \
    -e "HOST_UID=${HOST_UID}" \
    -e "HOST_GID=${HOST_GID}" \
    "${IMAGE_TAG}" \
    bash -c '
        set -euo pipefail
        trap "chown -R ${HOST_UID}:${HOST_GID} /out /opt/cargo/registry /cargo-target" EXIT
        cp -a /src/. /work/
        rm -rf /work/target
        cargo build --release --workspace
        bin_names="$(cargo metadata --no-deps --format-version=1 \
            | jq -r ".packages[].targets[] | select(.kind[] == \"bin\") | .name" \
            | sort -u)"
        [ -n "${bin_names}" ] || { echo "no [[bin]] targets found in workspace" >&2; exit 1; }
        for bin_name in ${bin_names}; do
            cp "${CARGO_TARGET_DIR}/release/${bin_name}" /out/
        done
    '

# Discover the staged binary names from what the container actually wrote,
# so everything below stays in lockstep with the workspace's [[bin]] targets.
bin_names=()
while IFS= read -r -d '' bin_path; do
    bin_names+=("$(basename "${bin_path}")")
done < <(find "${STAGE_DIR}" -maxdepth 1 -type f -not -name MANIFEST -print0)
IFS=$'\n' bin_names=($(sort <<<"${bin_names[*]}")); unset IFS

echo "==> Installing OpusDM binaries into ${DEST_DIR#"${PROJECT_DIR}"/}"
for bin_name in "${bin_names[@]}"; do
    install -Dm755 "${STAGE_DIR}/${bin_name}" "${DEST_DIR}/${bin_name}"
done

echo "==> Compiling dreamos-tools (release) in the same trixie container"
# dreamos-tools has no workspace: each subdirectory with its own Cargo.toml
# is an independent crate. Discover them by scanning for Cargo.toml files
# (one level deep) rather than hardcoding the list, so a new tool crate is
# picked up automatically the next time this script runs.
docker run --rm \
    -v "${TOOLS_SRC}:/src:ro" \
    -v "${TOOLS_STAGE_DIR}:/out" \
    -v "${REGISTRY_CACHE}:/opt/cargo/registry" \
    -v "${TOOLS_TARGET_CACHE}:/cargo-target" \
    -e CARGO_TARGET_DIR=/cargo-target \
    -e "HOST_UID=${HOST_UID}" \
    -e "HOST_GID=${HOST_GID}" \
    "${IMAGE_TAG}" \
    bash -c '
        set -euo pipefail
        trap "chown -R ${HOST_UID}:${HOST_GID} /out /opt/cargo/registry /cargo-target" EXIT
        cp -a /src/. /work/
        rm -rf /work/*/target
        for manifest in /work/*/Cargo.toml; do
            crate_dir="$(dirname "${manifest}")"
            cargo build --release --manifest-path "${manifest}"
            bin_names="$(cargo metadata --no-deps --format-version=1 --manifest-path "${manifest}" \
                | jq -r ".packages[].targets[] | select(.kind[] == \"bin\") | .name" \
                | sort -u)"
            [ -n "${bin_names}" ] || { echo "no [[bin]] targets found in ${crate_dir}" >&2; exit 1; }
            for bin_name in ${bin_names}; do
                cp "${CARGO_TARGET_DIR}/release/${bin_name}" /out/
            done
        done
    '

# Discover the staged tool binary names from what the container actually
# wrote, so everything below stays in lockstep with dreamos-tools crates.
tool_bin_names=()
while IFS= read -r -d '' bin_path; do
    tool_bin_names+=("$(basename "${bin_path}")")
done < <(find "${TOOLS_STAGE_DIR}" -maxdepth 1 -type f -not -name MANIFEST -print0)
IFS=$'\n' tool_bin_names=($(sort <<<"${tool_bin_names[*]}")); unset IFS

echo "==> Installing dreamos-tools binaries into ${DEST_DIR#"${PROJECT_DIR}"/}"
for bin_name in "${tool_bin_names[@]}"; do
    install -Dm755 "${TOOLS_STAGE_DIR}/${bin_name}" "${DEST_DIR}/${bin_name}"
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

echo "==> Refreshing ${TOOLS_TARBALL#"${PROJECT_DIR}"/}"
# Record which dreamos-tools revision produced these binaries, when the
# source tree is a git checkout.
_tools_ref="unknown"
if git -C "${TOOLS_SRC}" rev-parse --git-dir >/dev/null 2>&1; then
    _tools_ref="$(git -C "${TOOLS_SRC}" describe --always --dirty --tags 2>/dev/null \
        || git -C "${TOOLS_SRC}" rev-parse --short HEAD)"
fi
_tool_bin_list="$(printf '%s, ' "${tool_bin_names[@]}")"
_tool_bin_list="${_tool_bin_list%, }"
printf '%s\ndreamos-tools-ref: %s\n' "${_tool_bin_list}" "${_tools_ref}" \
    > "${TOOLS_STAGE_DIR}/MANIFEST"
chmod 755 "${tool_bin_names[@]/#/${TOOLS_STAGE_DIR}/}"
mkdir -p "$(dirname "${TOOLS_TARBALL}")"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='@0' \
    -cf - -C "${TOOLS_STAGE_DIR}" "${tool_bin_names[@]}" MANIFEST \
    | gzip -n -9 > "${TOOLS_TARBALL}"

echo "==> Done:"
ls -la "${bin_names[@]/#/${DEST_DIR}/}" "${tool_bin_names[@]/#/${DEST_DIR}/}" \
    "${TARBALL}" "${TOOLS_TARBALL}" "${PICOM_DEST}" "${BG_DEST}"
