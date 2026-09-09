#!/usr/bin/env bash
#
# Run the dreamos desktop (Openbox + opusdm-hub) straight from the
# already-built chroot/, inside a nested X server (Xephyr), without
# repacking the ISO. Use it to iterate on the Openbox autostart, on
# rc.xml / menu.xml and on the OpusDM shell.
#
# A throwaway 'user' account (uid 1000, group sudo) is created inside the
# chroot tree if missing, mirroring what live-config does on a real boot.
# It persists in chroot/ and is harmless.
#
# The session is started exactly like /etc/skel/.xinitrc does:
# dbus-run-session -> openbox-session, whose autostart runs opusdm-hub.
#
# Usage:
#   ./scripts/test-desktop.sh                  # 1600x900 nested window
#   ./scripts/test-desktop.sh --res 1920x1080
#   ./scripts/test-desktop.sh --display :7     # nested X server to use
#
# Needs: Xephyr ('xserver-xephyr'), systemd-nspawn ('systemd-container'),
# sudo, and a running graphical session on the host.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROOT_DIR="${PROJECT_DIR}/chroot"

RESOLUTION="1600x900"
NESTED_DISPLAY=":9"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --res) RESOLUTION="$2"; shift 2 ;;
        --display) NESTED_DISPLAY="$2"; shift 2 ;;
        -h|--help) awk 'NR>1{ if ($0 !~ /^#/) exit; sub(/^#[[:space:]]?/, ""); print }' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "ERROR: unknown argument '$1' (see --help)" >&2; exit 1 ;;
    esac
done

case "${RESOLUTION}" in [0-9]*x[0-9]*) : ;; *) echo "ERROR: --res must be WxH, e.g. 1600x900 (got '${RESOLUTION}')" >&2; exit 1 ;; esac
case "${NESTED_DISPLAY}" in :[0-9]*) : ;; *) echo "ERROR: --display must be :N, e.g. :9 (got '${NESTED_DISPLAY}')" >&2; exit 1 ;; esac

command -v Xephyr >/dev/null || { echo "ERROR: Xephyr not found (install 'xserver-xephyr')" >&2; exit 1; }
command -v systemd-nspawn >/dev/null || { echo "ERROR: systemd-nspawn not found (install 'systemd-container')" >&2; exit 1; }
test -d "${CHROOT_DIR}" || { echo "ERROR: ${CHROOT_DIR} not found (run ./build.sh at least once)" >&2; exit 1; }
test -n "${DISPLAY:-}" || { echo "ERROR: no host DISPLAY; run this from a graphical session" >&2; exit 1; }

# Nested X server on the host. Access control is off (-ac) because the
# container connects to it as root: this is a local throwaway test server.
Xephyr "${NESTED_DISPLAY}" -ac -screen "${RESOLUTION}" -resizeable -title "dreamos desktop test" &
XEPHYR_PID="$!"
# Always tear the nested server down when this script exits.
trap 'kill "${XEPHYR_PID}" 2>/dev/null || true' EXIT

# Wait for the Xephyr socket before launching the container.
XSOCK="/tmp/.X11-unix/X${NESTED_DISPLAY#:}"
for _ in $(seq 1 50); do test -S "${XSOCK}" && break; sleep 0.1; done
test -S "${XSOCK}" || { echo "ERROR: Xephyr did not come up on ${NESTED_DISPLAY}" >&2; exit 1; }

# In-container launcher: create the live 'user' if absent, prepare its
# XDG runtime dir, then start the session as that user on the nested
# display. ${NESTED_DISPLAY} is expanded here on the host; everything
# else runs inside the container.
LAUNCH=$(cat <<EOF
set -eu
if ! id user >/dev/null 2>&1; then
    useradd --create-home --uid 1000 --shell /bin/bash --groups sudo user
fi
install -d -o user -g user -m 700 /run/user/1000
exec su - user -c 'export DISPLAY=${NESTED_DISPLAY} XDG_RUNTIME_DIR=/run/user/1000; exec dbus-run-session -- openbox-session'
EOF
)

echo "==> Openbox + opusdm-hub at ${RESOLUTION} (nested ${NESTED_DISPLAY}); close the window to stop"
sudo systemd-nspawn \
    --directory="${CHROOT_DIR}" \
    --quiet \
    --as-pid2 \
    --bind-ro=/tmp/.X11-unix \
    --setenv="DISPLAY=${NESTED_DISPLAY}" \
    /bin/bash -c "${LAUNCH}"
