#!/usr/bin/env bash
#
# Enter or boot the already-built live root filesystem (chroot/) in a
# systemd-nspawn container, without repacking the ISO. Fast way to check
# the installed package set, the locale / keyboard / timezone config, the
# Openbox dotfiles under /etc/xdg/openbox and the OpusDM binaries
# (ldd /usr/bin/opusdm-hub, ...).
#
# The graphical desktop is not started here: use scripts/test-desktop.sh
# for that. live-config runs only on a real boot, so the auto-login
# 'user' does not exist in the tree yet and this container runs as root.
#
# Usage:
#   sudo ./scripts/test-chroot.sh            # interactive shell in the rootfs
#   sudo ./scripts/test-chroot.sh --boot     # boot systemd inside it (poweroff to exit)
#   sudo ./scripts/test-chroot.sh -- id -a   # run one command and exit
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROOT_DIR="${PROJECT_DIR}/chroot"

MODE="shell"
CMD=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --boot) MODE="boot"; shift ;;
        --) shift; CMD=("$@"); MODE="command"; break ;;
        -h|--help) awk 'NR>1{ if ($0 !~ /^#/) exit; sub(/^#[[:space:]]?/, ""); print }' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "ERROR: unknown argument '$1' (see --help)" >&2; exit 1 ;;
    esac
done

command -v systemd-nspawn >/dev/null || { echo "ERROR: systemd-nspawn not found (install 'systemd-container')" >&2; exit 1; }
test -d "${CHROOT_DIR}" || { echo "ERROR: ${CHROOT_DIR} not found (run ./build.sh at least once)" >&2; exit 1; }
test "$(id -u)" -eq 0 || { echo "ERROR: run with sudo (systemd-nspawn needs root)" >&2; exit 1; }
test "${MODE}" != "command" || [ "${#CMD[@]}" -gt 0 ] || { echo "ERROR: '--' needs a command to run" >&2; exit 1; }

NSPAWN_ARGS=(
    --directory="${CHROOT_DIR}"
    --quiet
)

case "${MODE}" in
    boot)    NSPAWN_ARGS+=(--boot) ;;
    command) NSPAWN_ARGS+=(--as-pid2 "${CMD[@]}") ;;
    shell)   NSPAWN_ARGS+=(--as-pid2 /bin/bash) ;;
esac

echo "==> systemd-nspawn (${MODE}) on ${CHROOT_DIR}"
exec systemd-nspawn "${NSPAWN_ARGS[@]}"
