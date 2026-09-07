#!/usr/bin/env bash
# Launch the dreamos live ISO in QEMU for interactive testing.
#
# Usage:
#   ./start.sh [--uefi|--bios] [--iso PATH] [--mem MB] [--res WxH] [--fit|--fullscreen] [--] [extra qemu args]
#
#   --uefi        boot via OVMF (UEFI firmware)
#   --bios        boot via SeaBIOS (legacy, default)
#   --iso PATH    ISO to boot (default: dreamos-amd64.hybrid.iso)
#   --mem MB      guest RAM in MB (default: 3072)
#   --res WxH     preferred display resolution (default: 1920x1080)
#   --fit         scale the guest into the window instead of growing the
#                 window to the guest size (for hosts smaller than --res)
#   --fullscreen  open QEMU full screen
#
# By default the QEMU window grows to the guest resolution once X starts.
# Press Enter at the boot menu to start the live system.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_VARS_TEMPLATE="/usr/share/OVMF/OVMF_VARS_4M.fd"

FIRMWARE="bios"
ISO_PATH="${PROJECT_DIR}/dreamos-amd64.hybrid.iso"
MEM_MB="3072"
RESOLUTION="1920x1080"
DISPLAY_MODE="grow"
EXTRA_ARGS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --uefi) FIRMWARE="uefi"; shift ;;
        --bios) FIRMWARE="bios"; shift ;;
        --iso) ISO_PATH="$2"; shift 2 ;;
        --mem) MEM_MB="$2"; shift 2 ;;
        --res) RESOLUTION="$2"; shift 2 ;;
        --fit) DISPLAY_MODE="fit"; shift ;;
        --fullscreen) DISPLAY_MODE="fullscreen"; shift ;;
        --) shift; EXTRA_ARGS+=("$@"); break ;;
        -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^#\s\{0,1\}//'; exit 0 ;;
        *) EXTRA_ARGS+=("$1"); shift ;;
    esac
done

case "${RESOLUTION}" in
    [0-9]*x[0-9]*) XRES="${RESOLUTION%x*}"; YRES="${RESOLUTION#*x}" ;;
    *) echo "ERROR: --res must be WxH, e.g. 1920x1080 (got '${RESOLUTION}')" >&2; exit 1 ;;
esac

command -v qemu-system-x86_64 >/dev/null || {
    echo "ERROR: qemu-system-x86_64 not found (install 'qemu-system-x86')" >&2
    exit 1
}
test -f "${ISO_PATH}" || {
    echo "ERROR: ISO not found: ${ISO_PATH} (run ./build.sh first)" >&2
    exit 1
}

QEMU_ARGS=(
    -m "${MEM_MB}"
    -smp 2
    -cdrom "${ISO_PATH}"
    -boot d
    -device virtio-net,netdev=n0 -netdev user,id=n0
    # virtio-gpu with an EDID advertising the requested mode as preferred,
    # so the guest X server comes up at ${RESOLUTION} instead of 1024x768.
    -device "virtio-vga,edid=on,xres=${XRES},yres=${YRES}"
    -usb -device usb-tablet
)

# Display: by default let the GTK window follow the guest resolution, so it
# grows to ${RESOLUTION} once X starts. --fit scales instead; --fullscreen
# goes full screen. Skipped entirely if the caller passes its own -display.
case " ${EXTRA_ARGS[*]-} " in
    *" -display "*|*" -nographic "*|*" -spice "*) : ;;
    *)
        case "${DISPLAY_MODE}" in
            fit)        QEMU_ARGS+=(-display gtk,zoom-to-fit=on) ;;
            fullscreen) QEMU_ARGS+=(-display gtk,full-screen=on) ;;
            *)          QEMU_ARGS+=(-display gtk,zoom-to-fit=off) ;;
        esac
        ;;
esac

# Use hardware acceleration when the host exposes /dev/kvm.
if [ -w /dev/kvm ]; then
    QEMU_ARGS+=(-enable-kvm -cpu host)
else
    echo "note: /dev/kvm not available, running without acceleration" >&2
fi

if [ "${FIRMWARE}" = "uefi" ]; then
    test -f "${OVMF_CODE}" || {
        echo "ERROR: ${OVMF_CODE} not found (install 'ovmf')" >&2
        exit 1
    }
    # Persistent per-project UEFI NVRAM (gitignored). Reused across runs so
    # boot entries survive; delete it to reset. A fixed path also means the
    # EXIT trap is not needed, so `exec qemu` below stays clean.
    VARS_FILE="${PROJECT_DIR}/.ovmf-vars.fd"
    test -f "${VARS_FILE}" || cp "${OVMF_VARS_TEMPLATE}" "${VARS_FILE}"
    QEMU_ARGS+=(
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}"
        -drive "if=pflash,format=raw,unit=1,file=${VARS_FILE}"
    )
fi

echo "==> Booting ${ISO_PATH##*/} (${FIRMWARE})"
exec qemu-system-x86_64 "${QEMU_ARGS[@]}" "${EXTRA_ARGS[@]}"
