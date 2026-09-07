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
