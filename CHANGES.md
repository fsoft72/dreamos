# Changelog

## 0.1.0 - 2026-09-07

- Task 1: project scaffold (`.gitignore`, `README.md`, `CHANGES.md`).
- Task 2: `Dockerfile` for the `dreamos-lb` Debian trixie build image.
- Task 3: `auto/config` (full `lb config` option set) and `auto/clean` at
  the project root; `.gitignore` rewritten for the real live-build
  `config/` layout (`auto/` is a sibling of the generated `config/` tree).
- Task 4: chroot package lists (desktop, network, system, installer); all
  packages verified present in the trixie archive.
- Task 5: Openbox autostart/menu, tint2 (default config), placeholder
  wallpaper; `/etc/skel/.bash_profile` + `.xinitrc` for the live session.
- Task 6: chroot hooks - locale/keyboard/timezone (0100), Openbox 2-desktop
  default (0150), Calamares launcher + `user` in `sudo` (0200), image
  cleanup (0300).
- Task 7: host wrappers `build.sh` and `clean.sh` (privileged container,
  chown artifacts back to the caller on exit) and `tests/verify-iso.sh`
  (checks ISO type + BIOS/UEFI El Torito entries).
- Task 8: first full ISO build (`dreamos-amd64.hybrid.iso`, ~1 GB).
  Login flow revised per request:
  - **Live**: tty1 autologin of `user` (`getty@tty1` drop-in) ->
    `~/.bash_profile` runs `startx` -> `~/.xinitrc` -> `openbox-session`.
    `bootappend-live` forces `systemd.unit=multi-user.target` so no
    display manager runs in the live session.
  - **Installed**: LightDM (unchanged squashfs default target), Openbox
    session preselected via `lightdm.conf.d/50-dreamos.conf`.
  - Added `user-setup` + `live-tools` (live-config Recommends): without
    `user-setup` the `user` account is never created and autologin fails
    with "Authentication failure".
  - Added `xserver-xorg-core` + `xserver-xorg-legacy` (rootless `startx`).
  - Dropped the hand-written `tint2rc` (tint2 17.x rejected it); the
    packaged default renders a working taskbar + systray + clock.
  - Hook 0100 now writes `/etc/locale.conf` directly (trixie symlinks
    `/etc/default/locale` -> `/etc/locale.conf`).
  Verified in QEMU (BIOS + UEFI): dual El Torito, boot to Openbox via
  tty autologin, tint2 panel, nm-applet in the systray, `feh` wallpaper,
  `it_IT.UTF-8` locale live (clock reads "lunedi 07 settembre"),
  `it,us` keyboard config, `Europe/Rome` timezone, 2 virtual desktops.
  Manual verification still pending: Openbox right-click menu popping
  (QEMU synthetic right-click does not register), Calamares install,
  keyboard toggle, USB persistence.
- `config/includes.chroot/etc/X11/xorg.conf.d/20-resolution.conf`: force
  the `modesetting` driver with a 1920x1080 modeline (+ `AllowNonEdidModes`
  and 1600x900 / 1366x768 / 1280x800 fallbacks). Without it Xorg came up
  at the 720x400 VGA console size under QEMU/GTK (headless was fine).
  Verified: guest scanout is now 1920x1080 with `-display gtk`.
- `start.sh`: interactive QEMU launcher (`--bios`/`--uefi`, `--iso`,
  `--mem`, `--res`, `--fit`, `--fullscreen`, KVM auto-detect, persistent
  per-project UEFI NVRAM). Default guest resolution 1920x1080 via a
  `virtio-vga` EDID; the GTK window follows the guest resolution
  (`zoom-to-fit=off`) so it grows to full size once X starts, `--fit`
  scales instead for smaller host screens.
