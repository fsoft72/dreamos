# dreamos - Debian Live Build - Design

Data: 2026-09-07
Stato: approvato, pronto per il piano di implementazione

## Obiettivo

Creare una distribuzione live avviabile basata su Debian 13 "trixie"
(stable), costruita con il `live-build` ufficiale di Debian, con
ambiente grafico minimale Openbox. Tutta la toolchain di build gira in
un container Docker Debian: l'host Ubuntu 25.10 non viene modificato.

## Scelte fissate

| Ambito | Scelta |
|---|---|
| Toolchain di build | Container Docker `debian:trixie` con `live-build` di Debian |
| Base | Debian 13 "trixie" stable, architettura `amd64` |
| Firmware boot | UEFI + BIOS legacy nella stessa ISO ibrida |
| Login (live) | Autologin su tty1 dell'utente `user`, poi `startx` -> `openbox-session` (nessun display manager attivo nella live) |
| Login (installato) | LightDM (greeter normale, sessione Openbox preselezionata) |
| Desktop | Openbox minimale: `tint2`, `lxterminal`, `pcmanfm`, `feh` |
| Browser | Nessuno |
| Installer su disco | Calamares (`calamares` + `calamares-settings-debian`) |
| Persistenza | Abilitata via `persistence` in `bootappend-live` |
| Nome / hostname / label ISO | `dreamos` per tutti e tre |
| Utente live | `user`, con `sudo` |
| Locale | `it_IT.UTF-8` (default) + `en_US.UTF-8` |
| Tastiera | `XKBLAYOUT="it,us"`, toggle Alt+Shift |
| Timezone | `Europe/Rome` |
| Recommends APT | Disattivati per tenere l'ISO al minimo |

## Struttura del progetto

```
/home/fabio/dreamos/
|-- Dockerfile              # debian:trixie + live-build + xorriso/mtools/squashfs/syslinux/grub
|-- build.sh               # build immagine, run container --privileged, lb build, rinomina ISO
|-- clean.sh               # lb clean --purge + rimozione artefatti
|-- config/
|   |-- auto/
|   |   |-- config         # invocazione unica di `lb config` con tutte le opzioni
|   |   `-- clean          # `lb clean --purge`
|   |-- package-lists/
|   |   |-- desktop.list.chroot     # xorg, openbox, lightdm, tint2, lxterminal, pcmanfm, feh
|   |   |-- network.list.chroot     # network-manager, network-manager-gnome
|   |   |-- installer.list.chroot   # calamares, calamares-settings-debian
|   |   `-- system.list.chroot      # sudo, locales, firmware, live-boot/live-config
|   |-- includes.chroot/            # file copiati nel filesystem live
|   |   `-- etc/
|   |       |-- xdg/openbox/         # rc.xml, menu.xml, autostart (tint2, feh, nm-applet)
|   |       |-- lightdm/lightdm.conf.d/50-dreamos.conf
|   |       `-- skel/.config/tint2/tint2rc
|   `-- hooks/
|       `-- normal/
|           |-- 0100-locale-keyboard-timezone.hook.chroot
|           |-- 0200-calamares-launcher.hook.chroot
|           `-- 0300-cleanup.hook.chroot
|-- cache/                 # (gitignored) cache pacchetti live-build, riusata tra build
|-- docs/superpowers/specs/ # questa spec
|-- CHANGES.md
|-- README.md
`-- .gitignore             # .build/ cache/ chroot/ binary/ *.iso *.log
```

`build.sh` monta `/home/fabio/dreamos` in `/build` nel container:
`cache/` sopravvive tra i run e l'ISO finisce sull'host. Il container
gira `--privileged` (necessario per loop device, mount del chroot,
`mksquashfs`). Output finale: `dreamos-amd64.hybrid.iso` nella root del
progetto.

## Sezione 1 - Dockerfile (host di build)

```dockerfile
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

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
        ca-certificates \
        debian-archive-keyring \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
```

## Sezione 2 - Configurazione live-build (config/auto/config)

Invocazione unica, riproducibile e rigenerabile:

```sh
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
    --bootappend-live "boot=live components username=user hostname=dreamos locales=it_IT.UTF-8 keyboard-layouts=it timezone=Europe/Rome persistence systemd.unit=multi-user.target" \
    "${@}"
```

Motivi delle scelte:

| Opzione | Motivo |
|---|---|
| `syslinux,grub-efi` | BIOS legacy (isolinux) e UEFI (grub) nella stessa ISO ibrida |
| `--debian-installer none` | niente d-i; l'installazione su disco la fa Calamares dal desktop |
| `--archive-areas "... non-free-firmware"` + `--firmware-*` | firmware Wi-Fi/GPU inclusi, live usabile su hardware reale |
| `--apt-recommends false` | ISO al minimo indispensabile |
| `--bootappend-live "... persistence"` | `live-config` applica locale/tastiera/timezone al boot; `persistence` abilita il salvataggio |
| `locales=it_IT.UTF-8` + `keyboard-layouts=it` | default italiano; `en_US.UTF-8`/`us` generati via hook e selezionabili |
| `--memtest none` | rimosso, non essenziale |

Persistenza (documentata nel README): l'utente crea sulla chiavetta una
seconda partizione con label `persistence` e un file `persistence.conf`
contenente `/ union`. Al boot con la voce gia presente, le modifiche a
`/home` e `/etc` sopravvivono ai riavvii.

Locale/tastiera doppia: l'hook `0100` mette in `/etc/locale.gen` sia
`it_IT.UTF-8` che `en_US.UTF-8`, esegue `locale-gen`, imposta
`it_IT.UTF-8` di default e configura `/etc/default/keyboard` con
`XKBLAYOUT="it,us"` (toggle con Alt+Shift).

## Sezione 3 - Pacchetti e desktop Openbox

`config/package-lists/desktop.list.chroot`:
```
xserver-xorg
xserver-xorg-core
xserver-xorg-legacy
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
(`xserver-xorg-legacy` fornisce `Xorg.wrap` per `startx` rootless su
tty1; `lightdm` resta installato per il sistema installato)

`config/package-lists/network.list.chroot`:
```
network-manager
network-manager-gnome
```

`config/package-lists/system.list.chroot`:
```
sudo
locales
firmware-linux
firmware-iwlwifi
live-boot
live-config
live-config-systemd
user-setup
live-tools
```
(`user-setup` e `live-tools` sono *Recommends* di `live-config`: con
`--apt-recommends false` vanno messi espliciti, altrimenti l'account
`user` non viene creato al boot e l'autologin fallisce)

`config/package-lists/installer.list.chroot`:
```
calamares
calamares-settings-debian
```

includes.chroot - config statica:

- `etc/xdg/openbox/autostart`:
  ```sh
  tint2 &
  nm-applet &
  feh --bg-fill /usr/share/backgrounds/dreamos.png &
  ```
- `etc/xdg/openbox/menu.xml`: menu ridotto - Terminale, File manager,
  "Installa dreamos" (`calamares` via `pkexec`), Riconfigura Openbox,
  Esci/Riavvia/Spegni
- `etc/xdg/openbox/rc.xml`: default upstream, tema `Clearlooks`, 2
  desktop virtuali
- `etc/skel/.config/tint2/tint2rc`: pannello in basso, taskbar +
  systray + orologio
- `etc/systemd/system/getty@tty1.service.d/autologin.conf`: autologin di
  `user` su tty1 (`agetty --autologin user`); usato solo nella live
- `etc/skel/.bash_profile`: se `tty1` e nessun `DISPLAY`, `exec startx`
- `etc/skel/.xinitrc`: `exec openbox-session`
- `etc/lightdm/lightdm.conf.d/50-dreamos.conf` (sistema installato):
  ```ini
  [Seat:*]
  user-session=openbox
  greeter-session=lightdm-gtk-greeter
  ```
- la live forza `systemd.unit=multi-user.target` in `bootappend-live`
  (override runtime, non persistito): nessun display manager parte nella
  live; il sistema installato mantiene `graphical.target` -> LightDM
- `usr/share/backgrounds/dreamos.png`: sfondo segnaposto tinta unita
  generato in un hook (niente binari nel repo)

Hook (`config/hooks/normal/`):

- `0100-locale-keyboard-timezone.hook.chroot` - genera `it_IT.UTF-8` +
  `en_US.UTF-8`, default `it_IT.UTF-8`, `XKBLAYOUT="it,us"`,
  `ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime`
- `0200-calamares-launcher.hook.chroot` - crea
  `/usr/share/applications/install-dreamos.desktop`, genera lo sfondo
  segnaposto senza dipendenze aggiuntive (PNG minimale o `printf`),
  assicura che `user` sia nel gruppo `sudo`
- `0300-cleanup.hook.chroot` - `apt-get clean`, svuota `/var/log`,
  `/usr/share/doc`, locali non-it/en per ridurre l'ISO

Nota Calamares: `calamares-settings-debian` fornisce gia una config
funzionante per installare un sistema Debian derivato. Se
l'installazione fallisse per branding o partizionamento, si affina
`etc/calamares/` in `includes.chroot` in un secondo giro (fuori scope
del primo build).

## Sezione 4 - Flusso di build, gestione errori, verifica

`build.sh` (eseguito sull'host Ubuntu):
```sh
#!/usr/bin/env bash
# Build the dreamos live ISO inside a Debian trixie container.
set -euo pipefail

IMAGE="dreamos-lb"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

docker build -t "$IMAGE" "$PROJECT_DIR"

docker run --rm --privileged \
    -v "$PROJECT_DIR:/build" \
    -w /build \
    "$IMAGE" \
    bash -c 'lb clean --purge && lb config && lb build'

# Rename the live-build output to the project artifact name.
mv "$PROJECT_DIR"/live-image-amd64.hybrid.iso "$PROJECT_DIR/dreamos-amd64.hybrid.iso"
echo "ISO pronta: $PROJECT_DIR/dreamos-amd64.hybrid.iso"
```

Gestione errori (fail fast):

- `set -euo pipefail` in tutti gli script: la build si ferma al primo
  errore
- `lb config` e in `auto/config`; `build.sh` chiama `lb config` senza
  argomenti, che rilegge `auto/config`
- se manca `--privileged` il chroot fallisce subito con messaggio
  chiaro su mount/loop
- `cache/` montata dall'host: una build interrotta riusa i `.deb` gia
  scaricati
- log completo di `lb build` su stdout del container; in caso di
  fallita, `config/.build/` resta per ispezione

Verifica (dopo il primo build riuscito):

1. `file dreamos-amd64.hybrid.iso` deve dire
   `DOS/MBR boot sector ... (bootable)`
2. `xorriso -indev dreamos-amd64.hybrid.iso -report_el_torito plain`
   deve mostrare due entry El Torito (BIOS + UEFI/EFI)
3. Boot di prova BIOS:
   `qemu-system-x86_64 -m 2048 -cdrom dreamos-amd64.hybrid.iso`
4. Boot di prova UEFI: stesso comando con
   `-bios /usr/share/OVMF/OVMF_CODE.fd` (pacchetto `ovmf` sull'host)
5. Dentro la live: autologin -> Openbox + tint2, `localectl` =
   `it_IT.UTF-8`, tastiera `it,us`, `timedatectl` = `Europe/Rome`,
   `nmcli` funzionante, lanciatore "Installa dreamos" apre Calamares
6. Test persistenza: seconda partizione USB con label `persistence` +
   `persistence.conf` con `/ union`, creare un file in `/home/user`,
   riavviare, verificare che resti

Criteri di completamento del primo milestone: punti 1-2 automatici
verdi + boot QEMU BIOS e UEFI che arrivano al desktop Openbox con
autologin. Persistenza e Calamares end-to-end sono verifica manuale
documentata nel README.

## Rischi noti

- `live-build` in Docker richiede `--privileged`; su host con policy
  restrittive potrebbe servire anche `--cap-add` mirato o
  `-v /dev:/dev`
- `firmware-iwlwifi` e altri pacchetti firmware richiedono l'area
  `non-free-firmware` gia inclusa in `--archive-areas`
- la config Calamares di `calamares-settings-debian` potrebbe
  richiedere ritocchi di branding: gestito in un secondo giro
- `syslinux` per BIOS + `grub-efi` per UEFI e la combinazione standard
  di Debian live; se l'ISO ibrida non risultasse avviabile in BIOS si
  valuta `--bootloaders "grub-pc,grub-efi"`

## Fuori scope (primo milestone)

- Branding grafico completo (loghi, tema GTK custom, splash Plymouth)
- Config Calamares personalizzata oltre il default Debian
- Repository APT custom o pacchetti `.deb` propri
- CI per build automatica dell'ISO
- Architetture diverse da `amd64`
