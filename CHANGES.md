# Changelog

## 0.2.1 - 2026-09-09

- `.github/workflows/build-iso.yml`: GitHub Actions build. On a push to
  the `live` branch (or manual dispatch) it frees runner disk space,
  runs `./build.sh`, and publishes `dreamos-amd64.hybrid.iso` as the
  rolling `live-latest` prerelease. A `concurrency` group serialises
  builds; `cache/` (live-build package downloads) is cached between runs.
- `scripts/build-opusdm.sh`: after staging the binaries it now also
  writes `vendor/opusdm/opusdm-bin.tar.gz` (the two binaries plus a
  `MANIFEST` naming the OpusDM revision). The archive is reproducible
  (fixed entry order, owner, mtime; `gzip -n`) so an unchanged build
  leaves no git diff.
- `build.sh`: when the loose `opusdm-hub` / `opusdm-lister` are absent
  (fresh checkout, CI) it unpacks `vendor/opusdm/opusdm-bin.tar.gz`
  before building, so the ISO build never needs the private OpusDM repo.
- `.gitignore`: track `vendor/opusdm/opusdm-bin.tar.gz` (the loose
  binaries under `config/includes.chroot/` stay ignored).
- `scripts/release-to-live.sh`: rebuild OpusDM, commit the refreshed
  tarball if it changed, merge the source branch into `live` and push,
  triggering the ISO workflow.
- `scripts/test-chroot.sh`: enter or boot the already-built `chroot/` in
  a `systemd-nspawn` container without repacking the ISO. `--boot` boots
  systemd inside it, `-- <cmd>` runs one command; default is a root
  shell. Checks the package set, locale / keyboard / timezone config,
  the Openbox dotfiles and the OpusDM binaries.
- `scripts/test-desktop.sh`: run the desktop (Openbox + `opusdm-hub`)
  from `chroot/` inside a nested `Xephyr` server, again without an ISO
  rebuild. Creates the live `user` in the tree if missing and starts the
  session exactly like `/etc/skel/.xinitrc`. `--res WxH` and
  `--display :N` are configurable.

## 0.2.0 - 2026-09-08

- OpusDM is now the live desktop. Openbox stays the window manager;
  `opusdm-hub` runs as the shell (full-screen keep-below desktop window
  with its own toolbar, spawns `opusdm-lister` from the same directory
  and opens the first window on `$HOME`).
- `scripts/Dockerfile.opusdm` + `scripts/build-opusdm.sh`: compile
  `opusdm-hub` and `opusdm-lister` in a `debian:trixie` container and
  stage them into `config/includes.chroot/usr/bin/`. Built in trixie
  because the Ubuntu host glibc (2.42) is newer than the ISO's (2.41)
  and host binaries will not start on the live system. The source is
  mounted read-only and copied inside the container; only the binaries
  and the crates.io registry cache (`cache/opusdm-cargo-registry/`) are
  written back. rustup provides the toolchain (workspace MSRV 1.91 is
  newer than trixie's packaged rustc).
- `build.sh`: refuses to run until both OpusDM binaries are staged, with
  a hint to run `scripts/build-opusdm.sh` first.
- `.gitignore`: ignore the staged `opusdm-hub` / `opusdm-lister`
  (build artifacts).
- `config/package-lists/desktop.list.chroot`: dropped `tint2`,
  `pcmanfm`, `feh`; added `libgtk-4-1`, `librsvg2-common` (SVG icon
  loader), `adwaita-icon-theme`, `gnome-themes-extra`, and
  `dbus-user-session`. The `Onyx` Openbox theme used by the shipped
  `rc.xml` is already in the base `openbox` package.
- `config/includes.chroot/etc/xdg/openbox/autostart`: launch only
  `opusdm-hub &` (no more `feh` / `tint2` / `nm-applet`).
- `config/includes.chroot/etc/skel/.xinitrc`: wrap the session in
  `dbus-run-session` so GTK4 / OpusDM get a session bus.
- `config/includes.chroot/etc/xdg/openbox/rc.xml`: ship OpusDM's Openbox
  config (Onyx theme, Ctrl+wheel desktop switch, 4 virtual desktops).
- `config/includes.chroot/etc/xdg/openbox/menu.xml`: replaced the
  "File Manager" (`pcmanfm`) entry with "OpusDM" (`opusdm-hub`).
- Removed `config/hooks/normal/0150-openbox-desktops.hook.chroot`: it
  rewrote the packaged `rc.xml`'s desktop count, now moot since we ship
  our own `rc.xml`.

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
- `config/bootloaders/splash.svg`: local copy of the live-build splash
  template with the title line (`@PROJECT@ @VERSION@ (@DISTRIBUTION@)`,
  hard-coded to "Debian GNU/Linux" by `binary_bootloader_splash`) changed
  to "DreamOS". live-build picks up `config/bootloaders/splash.svg`
  automatically and renders it into `isolinux/splash.png` and
  `boot/grub/splash.png`, so both the BIOS (syslinux) and UEFI (grub)
  boot screens now read "DreamOS".
