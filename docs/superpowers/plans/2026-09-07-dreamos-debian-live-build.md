# dreamos Debian Live Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a bootable Debian 13 "trixie" live ISO with a minimal Openbox desktop, produced entirely inside a Debian Docker container so the Ubuntu host stays untouched.

**Architecture:** A `debian:trixie` Docker image carries the real Debian `live-build` toolchain. A versioned `config/` tree drives `lb config` + `lb build`. `build.sh` runs the container `--privileged`, bind-mounts the project so the package cache persists and the ISO lands on the host. The live system auto-logs into Openbox via LightDM; locale/keyboard/timezone are applied at boot by `live-config` and baked as defaults by chroot hooks. Calamares provides on-disk installation; `persistence` is enabled in the kernel command line.

**Tech Stack:** Debian live-build (Debian trixie package), Docker, shell (POSIX sh for live-build scripts, bash for wrappers), Openbox, LightDM, tint2, Calamares, syslinux (BIOS) + grub-efi (UEFI), QEMU/OVMF for boot verification.

**Spec:** `docs/superpowers/specs/2026-09-07-dreamos-debian-live-build-design.md`

## Global Constraints

- Base distribution: Debian 13 "trixie" stable, architecture `amd64` only.
- All `live-build` execution happens inside the `dreamos-lb` Docker image (`FROM debian:trixie`). Never run `lb` on the host.
- ISO must be a hybrid image bootable on both UEFI and BIOS legacy firmware.
- `live-build` config lives in `config/`; build artifacts (`.build/`, `cache/`, `chroot/`, `binary/`, `*.iso`, `*.log`) are never committed.
- `lb config` invocation: exactly the option set in the spec Section 2, kept in `auto/config` as a single call, no drift.
- Archive areas: `main contrib non-free non-free-firmware`. APT recommends disabled (`--apt-recommends false`).
- Kernel command line (`--bootappend-live`): `boot=live components username=user hostname=dreamos locales=it_IT.UTF-8 keyboard-layouts=it timezone=Europe/Rome persistence`
- Names: distro name, hostname, and ISO volume/application label are all the literal string `dreamos`.
- Live user: `user`, member of group `sudo`.
- Locales generated: `it_IT.UTF-8` (system default) and `en_US.UTF-8`. Keyboard: `XKBLAYOUT="it,us"`, `XKBOPTIONS="grp:alt_shift_toggle"`.
- Timezone: `Europe/Rome`.
- No web browser in the package set. Keep the package set minimal: no compositor, no `lxappearance`, no power manager.
- All shell scripts: `set -euo pipefail` for bash wrappers, `set -e` for POSIX `sh` live-build scripts. Exit conditions first, one-liners where possible.
- All code and comments in English. Every script/file ends with a trailing newline.
- Constants in shell scripts: `UPPER_CASE` with `_` separators.
- Update `CHANGES.md` at the end of every task. Commit after every task with a meaningful message; no AI attribution lines; never `--no-verify`; never push.

---

## File Structure

Created by this plan:

| Path | Responsibility |
|---|---|
| `.gitignore` | Exclude build artifacts and caches from git |
| `README.md` | How to build, boot-test, use persistence, install to disk |
| `CHANGES.md` | Progressive changelog, one entry per task |
| `Dockerfile` | `debian:trixie` build host with `live-build` + ISO tooling |
| `build.sh` | Host entrypoint: build image, run container, `lb build`, rename ISO |
| `clean.sh` | Host entrypoint: run `lb clean --purge` in container, drop local artifacts |
| `auto/config` | Single `lb config` call with the full option set (project root, sibling of `config/`) |
| `auto/clean` | Standard `lb clean --purge` wrapper |
| `config/package-lists/desktop.list.chroot` | Xorg + Openbox + LightDM + tint2 + lxterminal + pcmanfm + feh |
| `config/package-lists/network.list.chroot` | NetworkManager + tray applet |
| `config/package-lists/system.list.chroot` | sudo, locales, firmware, live-boot/live-config |
| `config/package-lists/installer.list.chroot` | Calamares + Debian settings |
| `config/includes.chroot/etc/xdg/openbox/autostart` | Start tint2, nm-applet, set wallpaper |
| `config/includes.chroot/etc/xdg/openbox/menu.xml` | Minimal right-click menu incl. "Install dreamos" |
| `config/includes.chroot/etc/lightdm/lightdm.conf.d/50-dreamos.conf` | Autologin `user` into Openbox |
| `config/includes.chroot/etc/skel/.config/tint2/tint2rc` | Bottom panel: taskbar + systray + clock |
| `config/includes.chroot/usr/share/backgrounds/dreamos.png` | Solid-colour placeholder wallpaper (tiny PNG) |
| `config/hooks/normal/0100-locale-keyboard-timezone.hook.chroot` | Generate locales, set defaults, keyboard, timezone |
| `config/hooks/normal/0150-openbox-desktops.hook.chroot` | Set Openbox virtual desktop count to 2 |
| `config/hooks/normal/0200-calamares-launcher.hook.chroot` | Desktop launcher for Calamares, ensure `user` in `sudo` |
| `config/hooks/normal/0300-cleanup.hook.chroot` | Trim docs, logs, unused locales; `apt-get clean` |
| `tests/verify-iso.sh` | Automated ISO checks (file type, dual El Torito) |

---

## Task 1: Project scaffold

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: `CHANGES.md`

**Interfaces:**
- Consumes: nothing.
- Produces: repository skeleton. Later tasks assume `.gitignore` already excludes `cache/`, `.build/`, `chroot/`, `binary/`, `*.iso`, `*.log`.

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# live-build working directories
.build/
config/.build/
chroot/
chroot.packages.live
chroot.packages.install
binary/
binary.modified/
cache/

# build artifacts
*.iso
*.img
*.log
*.buildlog

# The whole config/ tree is regenerated by `lb config` from auto/config.
# Track only the hand-authored files below; ignore everything else.
/config/*
!/config/hooks/
!/config/includes.chroot/
!/config/package-lists/

# hooks/: live-build symlinks its own hooks here on every `lb config`.
# Keep only our 0xxx-prefixed custom hooks.
/config/hooks/*
!/config/hooks/normal/
/config/hooks/normal/*
!/config/hooks/normal/0*.hook.chroot

# package-lists/: live.list.chroot is generated. Keep only our lists.
/config/package-lists/*
!/config/package-lists/desktop.list.chroot
!/config/package-lists/network.list.chroot
!/config/package-lists/system.list.chroot
!/config/package-lists/installer.list.chroot

# editor noise
*~
.DS_Store
```

> **Layout note (discovered during execution):** in Debian live-build the
> `auto/` directory lives at the *project root*, as a sibling of `config/`,
> not inside it. `config/` is almost entirely generated by `lb config`;
> only `config/package-lists/*.list.chroot`, `config/hooks/normal/0*.hook.chroot`
> and `config/includes.chroot/**` are hand-authored. A bare `lb config`
> (what `build.sh` runs) only executes `./auto/config`.

- [ ] **Step 2: Create `README.md`**

```markdown
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
```

- [ ] **Step 3: Create `CHANGES.md`**

```markdown
# Changelog

## Unreleased

- Task 1: project scaffold (`.gitignore`, `README.md`, `CHANGES.md`).
```

- [ ] **Step 4: Verify files exist and git sees them**

Run: `ls -1 .gitignore README.md CHANGES.md && git status --porcelain`
Expected: the three filenames listed, and `git status` shows them as untracked (`?? .gitignore` etc.).

- [ ] **Step 5: Commit**

```bash
git add .gitignore README.md CHANGES.md
git commit -m "Add project scaffold for dreamos live-build"
```

---

## Task 2: Docker build image

**Files:**
- Create: `Dockerfile`

**Interfaces:**
- Consumes: nothing.
- Produces: Docker image tag `dreamos-lb` (referenced literally by `build.sh` and `clean.sh` in later tasks). Image has `lb` (Debian live-build), `debootstrap`, `xorriso`, `mksquashfs`, `syslinux`/`isolinux`, `grub-efi-amd64-bin`, `grub-pc-bin`, `libxml2-utils` (for `xmllint`), working dir `/build`.

- [ ] **Step 1: Create `Dockerfile`**

```dockerfile
# Debian trixie build host for the dreamos live ISO.
# All live-build execution happens here, never on the Ubuntu host.
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

RUN apt-get update && apt-get install --no-install-recommends -y \
        live-build \
        debootstrap \
        squashfs-tools \
        xorriso \
        mtools \
        dosfstools \
        syslinux \
        syslinux-common \
        isolinux \
        grub-efi-amd64-bin \
        grub-pc-bin \
        grub-common \
        libxml2-utils \
        ca-certificates \
        debian-archive-keyring \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
```

- [ ] **Step 2: Build the image**

Run: `docker build -t dreamos-lb .`
Expected: build completes, final line `naming to docker.io/library/dreamos-lb` or `writing image sha256:...`.

- [ ] **Step 3: Verify the toolchain is Debian live-build**

Run: `docker run --rm dreamos-lb sh -c 'lb --version && dpkg -s live-build | grep -E "^Version|^Maintainer"'`
Expected: `lb --version` prints a version string; `dpkg -s` shows a Debian maintainer (an `@debian.org` address), NOT an Ubuntu one. If it shows Ubuntu, the base image is wrong.

- [ ] **Step 4: Verify ISO tooling present**

Run: `docker run --rm dreamos-lb sh -c 'command -v xorriso mksquashfs debootstrap xmllint && ls /usr/lib/grub/x86_64-efi >/dev/null && echo grub-efi-ok'`
Expected: four paths printed followed by `grub-efi-ok`.

- [ ] **Step 5: Update `CHANGES.md`**

Add under `## Unreleased`:

```markdown
- Task 2: `Dockerfile` for the `dreamos-lb` Debian trixie build image.
```

- [ ] **Step 6: Commit**

```bash
git add Dockerfile CHANGES.md
git commit -m "Add Debian trixie Docker build image"
```

---

## Task 3: live-build configuration

**Files:**
- Create: `auto/config` (project root, NOT `config/auto/`)
- Create: `auto/clean` (project root)

**Interfaces:**
- Consumes: the `dreamos-lb` image from Task 2.
- Produces: `auto/config` (executable, POSIX `sh`) that runs one `lb config` call with the full spec option set. After it runs, `lb build` (Task 8) knows how to assemble the ISO. `auto/clean` (executable) wraps `lb clean --purge`. `auto/` sits at the project root as a sibling of the generated `config/` tree; a bare `lb config` only picks up `./auto/config`.

- [ ] **Step 1: Create `auto/config`**

```sh
#!/bin/sh
# Single source of truth for `lb config`. Regenerate config/ with:
#   lb config        (which re-runs this script)
set -e

lb config noauto \
    --mode debian \
    --distribution trixie \
    --archive-areas "main contrib non-free non-free-firmware" \
    --architectures amd64 \
    --linux-flavours amd64 \
    --binary-images iso-hybrid \
    --bootloaders "syslinux,grub-efi" \
    --debian-installer none \
    --apt-recommends false \
    --apt-indices false \
    --firmware-chroot true \
    --firmware-binary true \
    --iso-application "dreamos" \
    --iso-volume "dreamos" \
    --iso-publisher "dreamos" \
    --memtest none \
    --bootappend-live "boot=live components username=user hostname=dreamos locales=it_IT.UTF-8 keyboard-layouts=it timezone=Europe/Rome persistence" \
    "${@}"
```

- [ ] **Step 2: Create `auto/clean`**

`noauto` is REQUIRED here. `lb clean` (like `lb config`) re-executes
`auto/clean`; without `noauto` it recurses into itself and forks forever.

```sh
#!/bin/sh
# `lb clean` wrapper. `noauto` is REQUIRED: without it `lb clean` would
# re-execute this script, which calls `lb clean` again, forking forever.
set -e

lb clean noauto "${@}"
```

- [ ] **Step 3: Make both scripts executable**

Run: `chmod +x auto/config auto/clean && ls -l auto`
Expected: both files show the `x` bit for the owner.

- [ ] **Step 4: Run `lb config` inside the container and check it succeeds**

Run:
```bash
docker run --rm -v "$PWD:/build" -w /build dreamos-lb lb config
```
Expected: output includes `P: Executing auto/config script.` then
`P: Updating config tree for a debian/trixie/amd64 system`, no `E:` lines,
exit code 0. It populates `config/binary`, `config/bootstrap`,
`config/common`, etc. plus many empty subdirs (all gitignored).

- [ ] **Step 5: Verify the resulting config captured the key options**

Run:
```bash
grep -hE 'LB_DISTRIBUTION=|LB_ARCHITECTURE=|LB_BOOTLOADERS=|LB_IMAGE_TYPE=|LB_DEBIAN_INSTALLER=|LB_ARCHIVE_AREAS=|LB_APT_RECOMMENDS=' config/binary config/bootstrap config/common 2>/dev/null | sort -u
grep -h 'LB_BOOTAPPEND_LIVE=' config/binary
```
Expected: `LB_DISTRIBUTION="trixie"`, `LB_ARCHITECTURE="amd64"`,
`LB_BOOTLOADERS="syslinux grub-efi"` (live-build stores it space-separated),
`LB_IMAGE_TYPE="iso-hybrid"`, `LB_DEBIAN_INSTALLER="none"`,
`LB_ARCHIVE_AREAS="main contrib non-free non-free-firmware"`,
`LB_APT_RECOMMENDS="false"`, and `LB_BOOTAPPEND_LIVE` contains
`persistence` and `locales=it_IT.UTF-8`.

- [ ] **Step 6: Reset generated config**

Run: `docker run --rm -v "$PWD:/build" -w /build dreamos-lb ./auto/clean; git status --porcelain`
Expected: only `auto/config`, `auto/clean` and the modified `.gitignore`
show; nothing under `config/` is listed (all generated content is
gitignored).

- [ ] **Step 7: Update `CHANGES.md`**

```markdown
- Task 3: `auto/config` (full `lb config` option set) and `auto/clean`; `.gitignore` rewritten for the real live-build `config/` layout.
```

- [ ] **Step 8: Commit**

```bash
git add auto/config auto/clean .gitignore CHANGES.md
git commit -m "Add live-build auto/config and auto/clean"
```

---

## Task 4: Package lists

**Files:**
- Create: `config/package-lists/desktop.list.chroot`
- Create: `config/package-lists/network.list.chroot`
- Create: `config/package-lists/system.list.chroot`
- Create: `config/package-lists/installer.list.chroot`

**Interfaces:**
- Consumes: `auto/config` from Task 3.
- Produces: the chroot package set. Task 5 hooks assume these binaries exist in the chroot: `openbox`, `lightdm`, `tint2`, `nm-applet` (from `network-manager-gnome`), `calamares`, `locale-gen` (from `locales`), `sudo`.

- [ ] **Step 1: Create `config/package-lists/desktop.list.chroot`**

```
xserver-xorg
xserver-xorg-input-libinput
xinit
x11-xserver-utils
openbox
lightdm
lightdm-gtk-greeter
tint2
lxterminal
pcmanfm
feh
```

- [ ] **Step 2: Create `config/package-lists/network.list.chroot`**

```
network-manager
network-manager-gnome
```

- [ ] **Step 3: Create `config/package-lists/system.list.chroot`**

```
sudo
locales
firmware-linux
firmware-iwlwifi
live-boot
live-config
live-config-systemd
```

- [ ] **Step 4: Create `config/package-lists/installer.list.chroot`**

```
calamares
calamares-settings-debian
```

- [ ] **Step 5: Verify every listed package exists in the trixie archive**

The base `debian:trixie` image only has `main`, so the check must enable
all four archive areas first (matching `--archive-areas` in `auto/config`).
Save this as `scripts/check-packages.sh` on the host is not needed; run it
inline via a heredoc into the container:

```bash
docker run --rm -v "$PWD:/build" -w /build dreamos-lb bash -s <<'EOF'
set -e
cat > /etc/apt/sources.list.d/areas.sources <<'SRC'
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SRC
apt-get update >/dev/null 2>&1
for p in $(cat config/package-lists/*.list.chroot); do
  apt-cache show "$p" >/dev/null 2>&1 && echo "ok      $p" || echo "MISSING $p"
done
EOF
```

Expected: every line starts with `ok` (a generated `live.list.chroot`
from a prior `lb config` may also be globbed in - that is fine).
`firmware-linux` and `firmware-iwlwifi` live in `non-free-firmware` and
resolve once the areas are enabled. If any real `MISSING` appears, fix
the name before continuing.

- [ ] **Step 6: Update `CHANGES.md`**

```markdown
- Task 4: chroot package lists (desktop, network, system, installer).
```

- [ ] **Step 7: Commit**

```bash
git add config/package-lists CHANGES.md
git commit -m "Add chroot package lists"
```

---

## Task 5: Openbox / LightDM / tint2 static config

**Files:**
- Create: `config/includes.chroot/etc/xdg/openbox/autostart`
- Create: `config/includes.chroot/etc/xdg/openbox/menu.xml`
- Create: `config/includes.chroot/etc/lightdm/lightdm.conf.d/50-dreamos.conf`
- Create: `config/includes.chroot/etc/skel/.config/tint2/tint2rc`
- Create: `config/includes.chroot/usr/share/backgrounds/dreamos.png`

**Interfaces:**
- Consumes: package binaries from Task 4 (`tint2`, `nm-applet`, `feh`, `openbox`).
- Produces: a working Openbox session on autologin. Task 6's `0200` hook adds `/usr/share/applications/install-dreamos.desktop`, which the menu entry in this task points at (`pcmanfm` and `lxterminal` commands are referenced by literal name).

- [ ] **Step 1: Create `config/includes.chroot/etc/xdg/openbox/autostart`**

```sh
# dreamos Openbox session autostart
feh --bg-fill /usr/share/backgrounds/dreamos.png &
tint2 &
nm-applet &
```

- [ ] **Step 2: Create `config/includes.chroot/etc/xdg/openbox/menu.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="dreamos">
    <item label="Terminal">
      <action name="Execute"><command>lxterminal</command></action>
    </item>
    <item label="File Manager">
      <action name="Execute"><command>pcmanfm</command></action>
    </item>
    <separator/>
    <item label="Install dreamos">
      <action name="Execute"><command>pkexec calamares</command></action>
    </item>
    <separator/>
    <item label="Reconfigure Openbox">
      <action name="Reconfigure"/>
    </item>
    <item label="Log Out">
      <action name="Exit"><prompt>yes</prompt></action>
    </item>
    <item label="Reboot">
      <action name="Execute"><command>systemctl reboot</command></action>
    </item>
    <item label="Shut Down">
      <action name="Execute"><command>systemctl poweroff</command></action>
    </item>
  </menu>
</openbox_menu>
```

- [ ] **Step 3: Create `config/includes.chroot/etc/lightdm/lightdm.conf.d/50-dreamos.conf`**

```ini
[Seat:*]
autologin-user=user
autologin-user-timeout=0
autologin-session=openbox
user-session=openbox
greeter-session=lightdm-gtk-greeter
```

- [ ] **Step 4: Create `config/includes.chroot/etc/skel/.config/tint2/tint2rc`**

```ini
# dreamos minimal bottom panel
panel_items = TSC
panel_size = 100% 30
panel_position = bottom center horizontal
panel_background_id = 1
taskbar_mode = single_desktop
task_text = 1
task_maximum_size = 200 30
time1_format = %H:%M
time2_format = %a %d %b
systray_padding = 4 2 4
systray_icon_size = 20

rounded = 0
border_width = 0
background_color = #1e2430 100
```

- [ ] **Step 5: Create the placeholder wallpaper**

Run:
```bash
mkdir -p config/includes.chroot/usr/share/backgrounds
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR42mOQUzEAIgYIBQAMPgHJ0U8atQAAAABJRU5ErkJggg==' \
  | base64 -d > config/includes.chroot/usr/share/backgrounds/dreamos.png
```

- [ ] **Step 6: Verify PNG and XML validity**

Run:
```bash
file config/includes.chroot/usr/share/backgrounds/dreamos.png
docker run --rm -v "$PWD:/build" -w /build dreamos-lb \
  xmllint --noout config/includes.chroot/etc/xdg/openbox/menu.xml && echo "menu.xml ok"
```
Expected: `file` reports `PNG image data, 2 x 2`; `xmllint` prints nothing then `menu.xml ok`.

- [ ] **Step 7: Update `CHANGES.md`**

```markdown
- Task 5: Openbox autostart/menu, LightDM autologin, tint2 panel, placeholder wallpaper.
```

- [ ] **Step 8: Commit**

```bash
git add config/includes.chroot CHANGES.md
git commit -m "Add Openbox, LightDM and tint2 static config"
```

---

## Task 6: Chroot hooks

**Files:**
- Create: `config/hooks/normal/0100-locale-keyboard-timezone.hook.chroot`
- Create: `config/hooks/normal/0150-openbox-desktops.hook.chroot`
- Create: `config/hooks/normal/0200-calamares-launcher.hook.chroot`
- Create: `config/hooks/normal/0300-cleanup.hook.chroot`

**Interfaces:**
- Consumes: `locales`, `openbox`, `calamares`, `sudo` from Task 4; `/etc/xdg/openbox/rc.xml` shipped by the `openbox` package.
- Produces: baked-in locale/keyboard/timezone defaults, a 2-desktop Openbox default, `/usr/share/applications/install-dreamos.desktop`, and a slimmed chroot. No later task depends on these outputs; they only affect the final image.

- [ ] **Step 1: Create `config/hooks/normal/0100-locale-keyboard-timezone.hook.chroot`**

```sh
#!/bin/sh
# Bake locale, keyboard and timezone defaults into the installed system.
# live-config also applies these at boot from the kernel command line;
# this makes an on-disk install (via Calamares) match without relying on it.
set -e

LOCALE_DEFAULT="it_IT.UTF-8"
TIMEZONE="Europe/Rome"

# Locales: generate both, default to Italian.
sed -i 's/^# *\(it_IT.UTF-8 UTF-8\)/\1/' /etc/locale.gen
sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
cat > /etc/default/locale <<EOF
LANG=${LOCALE_DEFAULT}
EOF

# Keyboard: Italian first, US second, toggle with Alt+Shift.
cat > /etc/default/keyboard <<EOF
XKBMODEL="pc105"
XKBLAYOUT="it,us"
XKBVARIANT=","
XKBOPTIONS="grp:alt_shift_toggle"
BACKSPACE="guess"
EOF

# Timezone.
echo "${TIMEZONE}" > /etc/timezone
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
```

- [ ] **Step 2: Create `config/hooks/normal/0150-openbox-desktops.hook.chroot`**

```sh
#!/bin/sh
# Reduce Openbox virtual desktops from the packaged default (4) to 2.
set -e

RC_FILE="/etc/xdg/openbox/rc.xml"

test -f "${RC_FILE}" || exit 0
sed -i 's|<number>4</number>|<number>2</number>|' "${RC_FILE}"
```

- [ ] **Step 3: Create `config/hooks/normal/0200-calamares-launcher.hook.chroot`**

```sh
#!/bin/sh
# Provide a desktop launcher for the Calamares installer and make sure
# the live user can authenticate for it.
set -e

install -d /usr/share/applications
cat > /usr/share/applications/install-dreamos.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Install dreamos
Comment=Install dreamos to a hard disk
Exec=pkexec calamares
Icon=calamares
Terminal=false
Categories=System;
EOF

# Ensure the 'user' account (created by live-config) is in group sudo.
# live-config already does this for the default user, but be explicit
# so an on-disk install inherits the setting.
if ! grep -q '^sudo:.*\buser\b' /etc/group 2>/dev/null; then
    adduser user sudo 2>/dev/null || true
fi
```

- [ ] **Step 4: Create `config/hooks/normal/0300-cleanup.hook.chroot`**

```sh
#!/bin/sh
# Trim the chroot to keep the ISO small.
set -e

apt-get clean
rm -rf /usr/share/doc/*
rm -rf /var/log/*
find /var/cache/apt/archives -type f -name '*.deb' -delete

# Drop locale data except Italian and English.
if [ -d /usr/share/locale ]; then
    find /usr/share/locale -mindepth 1 -maxdepth 1 -type d \
        ! -name 'it*' ! -name 'en*' ! -name 'C*' ! -name 'locale.alias' \
        -exec rm -rf {} +
fi
```

- [ ] **Step 5: Make all hooks executable and syntax-check them**

Run (target our `0*` hooks only - a prior `lb config` leaves live-build's
own `1000+`/`5000+`/`8000+` hook symlinks in this directory, which dangle
on the host and would break a bare `chmod`/`sh -n` glob):
```bash
chmod +x config/hooks/normal/0*.hook.chroot
for f in config/hooks/normal/0*.hook.chroot; do sh -n "$f" && echo "syntax ok: $f"; done
```
Expected: one `syntax ok:` line per custom hook, no errors.

- [ ] **Step 6: Update `CHANGES.md`**

```markdown
- Task 6: chroot hooks - locale/keyboard/timezone, Openbox desktops, Calamares launcher, cleanup.
```

- [ ] **Step 7: Commit**

```bash
git add config/hooks CHANGES.md
git commit -m "Add chroot hooks for locale, Openbox, Calamares and cleanup"
```

---

## Task 7: Host wrapper scripts

**Files:**
- Create: `build.sh`
- Create: `clean.sh`
- Create: `tests/verify-iso.sh`

**Interfaces:**
- Consumes: the `dreamos-lb` image (Task 2), `config/` tree (Tasks 3-6).
- Produces: `./build.sh` -> `dreamos-amd64.hybrid.iso` in the project root. `./clean.sh [--all]`. `./tests/verify-iso.sh <iso>` exits non-zero if the ISO is missing a BIOS or a UEFI boot path.

- [ ] **Step 1: Create `build.sh`**

```bash
#!/usr/bin/env bash
# Build the dreamos live ISO inside a Debian trixie container.
# The Ubuntu host is never touched by live-build.
set -euo pipefail

IMAGE_TAG="dreamos-lb"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LB_OUTPUT="live-image-amd64.hybrid.iso"
FINAL_ISO="dreamos-amd64.hybrid.iso"

cd "${PROJECT_DIR}"

echo "==> Building Docker image ${IMAGE_TAG}"
docker build -t "${IMAGE_TAG}" "${PROJECT_DIR}"

echo "==> Running lb build (privileged container)"
docker run --rm --privileged \
    -v "${PROJECT_DIR}:/build" \
    -w /build \
    "${IMAGE_TAG}" \
    bash -c 'set -euo pipefail; ./auto/clean || true; lb config; lb build'

test -f "${PROJECT_DIR}/${LB_OUTPUT}" || {
    echo "ERROR: expected ${LB_OUTPUT} was not produced" >&2
    exit 1
}

mv "${PROJECT_DIR}/${LB_OUTPUT}" "${PROJECT_DIR}/${FINAL_ISO}"
echo "==> ISO ready: ${PROJECT_DIR}/${FINAL_ISO}"
```

- [ ] **Step 2: Create `clean.sh`**

```bash
#!/usr/bin/env bash
# Remove live-build artifacts. With --all, also drop the package cache
# and any built ISO.
set -euo pipefail

IMAGE_TAG="dreamos-lb"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "${PROJECT_DIR}"

docker run --rm --privileged \
    -v "${PROJECT_DIR}:/build" \
    -w /build \
    "${IMAGE_TAG}" \
    bash -c './auto/clean || lb clean --purge'

if [[ "${1:-}" == "--all" ]]; then
    rm -rf "${PROJECT_DIR}/cache"
    rm -f "${PROJECT_DIR}"/*.iso
    echo "==> Removed cache/ and *.iso"
fi

echo "==> Clean complete"
```

- [ ] **Step 3: Create `tests/verify-iso.sh`**

```bash
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
```

- [ ] **Step 4: Make scripts executable and lint**

Run:
```bash
chmod +x build.sh clean.sh tests/verify-iso.sh
bash -n build.sh && bash -n clean.sh && bash -n tests/verify-iso.sh && echo "syntax ok"
command -v shellcheck >/dev/null && shellcheck build.sh clean.sh tests/verify-iso.sh || echo "shellcheck not installed, skipped"
```
Expected: `syntax ok`. If shellcheck runs, no errors (warnings acceptable).

- [ ] **Step 5: Update `CHANGES.md`**

```markdown
- Task 7: host wrapper scripts `build.sh`, `clean.sh`, and `tests/verify-iso.sh`.
```

- [ ] **Step 6: Commit**

```bash
git add build.sh clean.sh tests/verify-iso.sh CHANGES.md
git commit -m "Add build, clean and ISO verification scripts"
```

---

## Task 8: Full build and boot verification

**Files:**
- Modify: `CHANGES.md`
- Modify: `README.md:1` (only if build reveals a needed correction; otherwise leave)

**Interfaces:**
- Consumes: everything from Tasks 1-7.
- Produces: `dreamos-amd64.hybrid.iso` at the project root, verified to boot in BIOS and UEFI QEMU.

- [ ] **Step 1: Run the full build**

Run: `./build.sh 2>&1 | tee build.log`
Expected: finishes with `==> ISO ready: .../dreamos-amd64.hybrid.iso`, exit code 0. This takes tens of minutes on the first run. If it fails, read `build.log`; the chroot stage log is the usual culprit (missing package, hook error). Fix the offending task's file, re-run.

- [ ] **Step 2: Confirm the artifact exists and has a sane size**

Run: `ls -lh dreamos-amd64.hybrid.iso`
Expected: file present, size roughly 700 MB - 1.3 GB (minimal Openbox + Calamares + firmware). A sub-400 MB image means package lists did not apply.

- [ ] **Step 3: Run automated ISO checks**

Run: `./tests/verify-iso.sh dreamos-amd64.hybrid.iso`
Expected: ends with `==> OK: ... has BIOS + UEFI boot entries`.

- [ ] **Step 4: BIOS boot smoke test**

Run: `timeout 120 qemu-system-x86_64 -m 2048 -cdrom dreamos-amd64.hybrid.iso -display none -serial stdio || true`
Expected: kernel/live-boot messages appear on serial; no immediate `Boot failed` from SeaBIOS. (Full desktop needs a graphical display; see Step 6.)

- [ ] **Step 5: UEFI boot smoke test**

Run:
```bash
test -f /usr/share/OVMF/OVMF_CODE.fd || echo "install 'ovmf' on the host first"
timeout 120 qemu-system-x86_64 -m 2048 -bios /usr/share/OVMF/OVMF_CODE.fd \
    -cdrom dreamos-amd64.hybrid.iso -display none -serial stdio || true
```
Expected: GRUB loads, kernel boots, live-boot messages on serial; no `BdsDxe: failed to load Boot0001`.

- [ ] **Step 6: Manual graphical check (document result in commit message)**

Run: `qemu-system-x86_64 -m 2048 -enable-kvm -cdrom dreamos-amd64.hybrid.iso`
Verify by eye, then close QEMU:
- LightDM auto-logs into Openbox (no password prompt).
- tint2 panel visible at the bottom; nm-applet icon in the systray.
- Right-click desktop shows the menu; "Terminal" opens `lxterminal`.
- In the terminal: `localectl status` shows `System Locale: LANG=it_IT.UTF-8` and `X11 Layout: it,us`; `timedatectl` shows `Time zone: Europe/Rome`.
- `locale -a` lists both `it_IT.utf8` and `en_US.utf8`.
- `id user` shows group `sudo`.
- "Install dreamos" launches Calamares (cancel before partitioning).

- [ ] **Step 7: Update `CHANGES.md`**

```markdown
- Task 8: first full ISO build; verified BIOS + UEFI boot and Openbox autologin. Release 0.1.0.
```

Change the `## Unreleased` heading to `## 0.1.0 - 2026-09-07`.

- [ ] **Step 8: Commit and tag**

```bash
git add CHANGES.md README.md
git commit -m "Build and verify dreamos 0.1.0 live ISO"
git tag -a v0.1.0 -m "dreamos 0.1.0 - first bootable live ISO"
```

Do not push.

---

## Self-Review

**1. Spec coverage**

| Spec item | Task |
|---|---|
| Docker `debian:trixie` toolchain, host untouched | Task 2, Task 7 (`build.sh` runs everything in container) |
| Debian live-build (not Ubuntu fork) | Task 2 Step 3 verifies maintainer |
| trixie stable, amd64 | Task 3 `auto/config` |
| UEFI + BIOS hybrid ISO | Task 3 (`--bootloaders syslinux,grub-efi`, `iso-hybrid`), Task 8 Steps 3-5 |
| LightDM autologin into Openbox | Task 5 Step 3, Task 8 Step 6 |
| Minimal Openbox (tint2, lxterminal, pcmanfm, feh), no browser | Task 4 Step 1, Task 5 |
| Calamares installer | Task 4 Step 4, Task 6 Step 3, Task 8 Step 6 |
| Persistence enabled | Task 3 (`persistence` in bootappend), README Task 1 documents usage |
| name/hostname/label all `dreamos` | Task 3 (`--iso-*`, `hostname=` in bootappend) |
| user `user` in group `sudo` | Task 3 (`username=user`), Task 6 Step 3 |
| Locales it_IT.UTF-8 default + en_US.UTF-8 | Task 6 Step 1 |
| Keyboard it,us Alt+Shift | Task 6 Step 1 |
| Timezone Europe/Rome | Task 3 bootappend, Task 6 Step 1 |
| APT recommends off, minimal set | Task 3 (`--apt-recommends false`), Task 6 Step 4 cleanup |
| firmware non-free included | Task 3 (`non-free-firmware` area, `--firmware-*`), Task 4 Step 3 |
| Artifact `dreamos-amd64.hybrid.iso` at root | Task 7 `build.sh`, Task 8 |
| Build artifacts gitignored | Task 1 |
| CHANGES.md progressive | every task, final step |
| Verification: file, xorriso dual El Torito, QEMU BIOS+UEFI | Task 7 `tests/verify-iso.sh`, Task 8 Steps 3-6 |

No uncovered spec requirements.

**2. Placeholder scan**

No `TBD`/`TODO`/"handle edge cases"/"similar to Task N" present. Every code step contains the full file content. Task 8 Step 1's "fix the offending task's file" is a debugging instruction, not a deferred implementation.

**3. Type / name consistency**

- Image tag `dreamos-lb` - identical in Tasks 2, 3, 4, 5, 6, 7.
- `lb` output filename `live-image-amd64.hybrid.iso` -> renamed to `dreamos-amd64.hybrid.iso` - consistent in Task 7 `build.sh` and Task 8.
- `auto/clean` invoked as `./auto/clean` in Tasks 3, 7 - consistent, and it is created executable in Task 3 Step 3.
- Wallpaper path `/usr/share/backgrounds/dreamos.png` - identical in Task 5 Step 1 (autostart), Step 5 (creation).
- Launcher `pkexec calamares` - identical in Task 5 menu.xml and Task 6 `.desktop`.
- Live user `user` - consistent across bootappend (Task 3), hooks (Task 6), verification (Task 8).

No inconsistencies found.

**4. Known deviations from spec (intentional, minor)**

- Spec Section 3 lists a single `0200` hook that both creates the launcher and generates the wallpaper. This plan creates the wallpaper directly as a committed 2x2 PNG in Task 5 (43 bytes, effectively not a "binary blob") and keeps hook `0200` for the launcher only, plus a dedicated `0150` hook for the Openbox desktop count. Same end result, simpler hooks.
- `x11-xserver-utils` added to the desktop list (provides `xset`/`xrandr`); tiny, standard for a bare X session.
