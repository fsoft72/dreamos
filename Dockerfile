# Debian trixie build host for the dreamos live ISO.
# All live-build execution happens here, never on the Ubuntu host.
# Pinned by digest so the base layer never changes underneath us, which
# would bust the apt-get install layer cache below on every build.
FROM debian:trixie@sha256:9cc080028c43b27d2074d63a5f9caf7166d731494965616c1a6d2827a004585c

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
