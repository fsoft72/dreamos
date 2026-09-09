# dreamos

A Debian 13 "trixie" live ISO whose desktop is OpusDM (`opusdm-hub` +
`opusdm-lister`) running on Openbox, built with Debian `live-build`
inside a Docker container.

## Requirements (host)

- Docker
- ~15 GB free disk, working internet connection
- The OpusDM sources (default path `/home/fabio/dev/projects/opusdm`,
  override with `OPUSDM_SRC`)
- For boot testing: `qemu-system-x86` and `ovmf`

## Build

```sh
./scripts/build-opusdm.sh   # once, and again whenever OpusDM changes
./build.sh
```

`scripts/build-opusdm.sh` compiles `opusdm-hub` and `opusdm-lister` in a
throwaway `debian:trixie` container and stages them into
`config/includes.chroot/usr/bin/`. It must run before `./build.sh`,
which refuses to start without those binaries. They are built in trixie
(not on the host) because the Ubuntu host glibc is newer than the ISO's
and host builds will not start on the live system.

`./build.sh` builds the `dreamos-lb` Docker image on first run, then runs
`lb build` inside a `--privileged` container. Downloaded packages are
cached under `cache/` and reused by later builds. Output:
`dreamos-amd64.hybrid.iso` in the project root.

## Clean

```sh
./clean.sh          # lb clean --purge inside the container
./clean.sh --all    # also remove cache/ and the ISO
```

## Test without rebuilding the ISO

Once `./build.sh` has produced the `chroot/` tree at least once, most
changes can be checked against it directly, without repacking the ISO:

```sh
sudo ./scripts/test-chroot.sh          # root shell in the live rootfs
sudo ./scripts/test-chroot.sh --boot   # boot systemd inside it (poweroff to exit)
sudo ./scripts/test-chroot.sh -- ldd /usr/bin/opusdm-hub

./scripts/test-desktop.sh              # Openbox + opusdm-hub in a nested Xephyr window
./scripts/test-desktop.sh --res 1920x1080
```

`test-chroot.sh` uses `systemd-nspawn` and is good for the package set,
locale / keyboard / timezone config and the OpusDM binaries; the
auto-login `user` is created only on a real boot, so it runs as root.
`test-desktop.sh` starts the graphical session the same way
`/etc/skel/.xinitrc` does, creating the `user` account in the tree if
missing. Needs `systemd-container` and `xserver-xephyr`.

## Boot test

```sh
./start.sh                 # BIOS legacy (default), 1920x1080
./start.sh --uefi          # UEFI via OVMF
./start.sh --res 1280x800  # pick another resolution
./start.sh --fit           # scale into the window (host smaller than --res)
./start.sh --fullscreen
./start.sh --help          # all options
```

`start.sh` enables KVM when `/dev/kvm` is available and boots the guest at
`--res` (default `1920x1080`, via a `virtio-vga` EDID). By default the
QEMU window grows to the guest resolution once X starts; use `--fit` on a
host screen smaller than the guest. It keeps a per-project UEFI NVRAM
file (`.ovmf-vars.fd`, gitignored).

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

- Auto-login as `user` (group `sudo`) on tty1 -> `startx` ->
  `dbus-run-session openbox-session`.
- Openbox `autostart` launches `opusdm-hub`, the desktop shell: it draws
  the background and desktop icons, shows its toolbar, and opens the
  first Lister window on `$HOME`. There is no separate panel or wallpaper
  setter.
- Right-click the desktop for the Openbox menu (Terminal, OpusDM,
  Install dreamos, session actions).
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
