# Changelog

## Unreleased

- Task 1: project scaffold (`.gitignore`, `README.md`, `CHANGES.md`).
- Task 2: `Dockerfile` for the `dreamos-lb` Debian trixie build image.
- Task 3: `auto/config` (full `lb config` option set) and `auto/clean` at
  the project root; `.gitignore` rewritten for the real live-build
  `config/` layout (`auto/` is a sibling of the generated `config/` tree).
- Task 4: chroot package lists (desktop, network, system, installer); all
  packages verified present in the trixie archive.
- Task 5: Openbox autostart/menu, LightDM autologin drop-in, tint2 bottom
  panel in `/etc/skel`, and a 2x2 placeholder wallpaper.
- Task 6: chroot hooks - locale/keyboard/timezone (0100), Openbox 2-desktop
  default (0150), Calamares launcher + `user` in `sudo` (0200), image
  cleanup (0300).
