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
# BIOS legacy
qemu-system-x86_64 -m 2048 -cdrom dreamos-amd64.hybrid.iso

# UEFI
qemu-system-x86_64 -m 2048 -bios /usr/share/OVMF/OVMF_CODE.fd \
    -cdrom dreamos-amd64.hybrid.iso
```

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
