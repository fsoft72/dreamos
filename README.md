# dreamos

A Debian 13 "trixie" live ISO with a minimal Openbox desktop, built with
Debian `live-build` inside a Docker container.

## Requirements (host)

- Docker
- ~15 GB free disk, working internet connection
- For boot testing: `qemu-system-x86` and `ovmf`

## Build

```sh
./build.sh
```

The first run builds the `dreamos-lb` Docker image, then runs `lb build`
inside a `--privileged` container. Downloaded packages are cached under
`cache/` and reused by later builds. Output: `dreamos-amd64.hybrid.iso`
in the project root.

## Clean

```sh
./clean.sh          # lb clean --purge inside the container
./clean.sh --all    # also remove cache/ and the ISO
```

## Boot test

```sh
./start.sh            # BIOS legacy (default)
./start.sh --uefi     # UEFI via OVMF
./start.sh --help     # all options (--iso, --mem, extra qemu args after --)
```

`start.sh` enables KVM when `/dev/kvm` is available and keeps a
per-project UEFI NVRAM file (`.ovmf-vars.fd`, gitignored).

Raw commands, if you prefer:

```sh
# BIOS legacy
qemu-system-x86_64 -m 2048 -cdrom dreamos-amd64.hybrid.iso

# UEFI (Debian/Ubuntu ship OVMF_CODE_4M.fd)
cp /usr/share/OVMF/OVMF_VARS_4M.fd /tmp/ovmf_vars.fd
qemu-system-x86_64 -m 2048 \
    -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
    -drive if=pflash,format=raw,unit=1,file=/tmp/ovmf_vars.fd \
    -cdrom dreamos-amd64.hybrid.iso
```

Both bootloaders (isolinux for BIOS, GRUB for UEFI) wait for a keypress
at the menu (`timeout 0` / `timeout -1`, the Debian live default); press
Enter to boot the live system.

Automated sanity checks:

```sh
./tests/verify-iso.sh dreamos-amd64.hybrid.iso
```

## Live system

- Auto-login as `user` (group `sudo`) into Openbox via LightDM.
- Right-click the desktop for the menu.
- Default locale `it_IT.UTF-8`; `en_US.UTF-8` also available.
- Keyboard `it,us`, switch with Alt+Shift.
- Timezone `Europe/Rome`.

## Persistence (USB)

1. Write the ISO to a USB stick (`dd` or similar).
2. Add a second partition labelled `persistence` (any filesystem, e.g. ext4).
3. In that partition's root create a file `persistence.conf` containing:

   ```
   / union
   ```

4. Boot the stick. Changes to `/home` and `/etc` now survive reboots.

## Install to disk

Use the "Install dreamos" launcher (Openbox menu or
`/usr/share/applications/install-dreamos.desktop`) to run Calamares.
