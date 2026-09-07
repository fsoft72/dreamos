#!/usr/bin/env bash
# Sanity-check a built dreamos ISO: correct type + both boot paths.
set -euo pipefail

ISO_PATH="${1:-dreamos-amd64.hybrid.iso}"

test -f "${ISO_PATH}" || { echo "ERROR: ${ISO_PATH} not found" >&2; exit 1; }

echo "==> file(1) type"
FILE_OUT="$(file "${ISO_PATH}")"
echo "${FILE_OUT}"
echo "${FILE_OUT}" | grep -qi 'boot sector' || {
    echo "ERROR: not reported as bootable" >&2; exit 1
}

echo "==> El Torito catalog"
ELTORITO="$(xorriso -indev "${ISO_PATH}" -report_el_torito plain 2>/dev/null)"
echo "${ELTORITO}"
echo "${ELTORITO}" | grep -qi 'BIOS'  || { echo "ERROR: no BIOS boot entry" >&2; exit 1; }
echo "${ELTORITO}" | grep -qi 'UEFI\|EFI' || { echo "ERROR: no UEFI boot entry" >&2; exit 1; }

echo "==> OK: ${ISO_PATH} has BIOS + UEFI boot entries"
