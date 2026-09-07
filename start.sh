#!/usr/bin/env bash
# Launch the dreamos live ISO in QEMU for interactive testing.
#
# Usage:
#   ./start.sh [--uefi|--bios] [--iso PATH] [--mem MB] [--] [extra qemu args]
#
#   --uefi        boot via OVMF (UEFI firmware)
#   --bios        boot via SeaBIOS (legacy, default)
#   --iso PATH    ISO to boot (default: dreamos-amd64.hybrid.iso)
#   --mem MB      guest RAM in MB (default: 3072)
#
# Press Enter at the boot menu to start the live system.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_VARS_TEMPLATE="/usr/share/OVMF/OVMF_VARS_4M.fd"

FIRMWARE="bios"
ISO_PATH="${PROJECT_DIR}/dreamos-amd64.hybrid.iso"
MEM_MB="3072"
EXTRA_ARGS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --uefi) FIRMWARE="uefi"; shift ;;
        --bios) FIRMWARE="bios"; shift ;;
        --iso) ISO_PATH="$2"; shift 2 ;;
        --mem) MEM_MB="$2"; shift 2 ;;
        --) shift; EXTRA_ARGS+=("$@"); break ;;
        -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^#\s\{0,1\}//'; exit 0 ;;
        *) EXTRA_ARGS+=("$1"); shift ;;
    esac
done

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
    -vga virtio
    -usb -device usb-tablet
)

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
