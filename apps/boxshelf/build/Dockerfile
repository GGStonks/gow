ARG BASE_APP_IMAGE

# Built on base-emu: Wolf's input/udev/NVIDIA handling from base-app, plus the
# emulators (Dolphin, Cemu, PCSX2, RPCS3, RetroArch, ...) Boxshelf starts.
# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
# AppImages (Boxshelf itself, the emulators) run without FUSE inside Docker
# see: https://github.com/AppImage/AppImageKit/wiki/FUSE#docker
ENV APPIMAGE_EXTRACT_AND_RUN=1

# KWin runs nested inside Wolf's Wayland output. Boxshelf needs a stacking
# window manager: it keeps itself always-on-top, fades its own opacity and
# raises a cover over a closing game. Sway (tiling) and gamescope (one window
# at a time) break that; KWin behaves exactly like a Plasma desktop does.
# The rest are the libraries Electron loads.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        kwin-wayland \
        kwin-style-breeze \
        breeze-cursor-theme \
        dbus \
        dbus-user-session \
        libglib2.0-bin \
        libasound2t64 \
        libatk-bridge2.0-0t64 \
        libatk1.0-0t64 \
        libcups2t64 \
        libdrm2 \
        libgbm1 \
        libnotify4 \
        libnss3 \
        libsecret-1-0 \
        libxkbcommon0 \
        libxkbfile1 \
        libxshmfence1 \
        libxss1 \
        libxtst6 \
        xdg-utils \
        fonts-dejavu-core \
        fonts-noto-color-emoji \
        && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* && \
    # Ubuntu gives kwin_wayland cap_sys_nice (realtime scheduling). Without
    # that capability in the container, exec fails with "Operation not
    # permitted". A compositor nested inside Wolf doesn't need it.
    setcap -r /usr/bin/kwin_wayland

# PC games without Steam (Boxshelf's Linux PC support): legendary for Epic Games
# (sign-in, library, installs, launch info) and umu-run, which runs Proton
# outside Steam with the Steam Linux Runtime and protonfixes. Pinned releases,
# checked against the SHA-256 GitHub publishes for them. The Proton builds
# themselves come from the host (see wolf.config.toml).
ARG LEGENDARY_VERSION=0.21.1
ARG LEGENDARY_SHA256=dbed33bbe96031e65858233e4badf0a1d401bb6cb0cc995d1237cf3a0c826a45
ARG UMU_VERSION=1.4.4
ARG UMU_SHA256=eb590691841f7fad3fc3ad8fd5db4ccb87849fe7948e62b28ece7a4ee48cc851
RUN <<_INSTALL_PC_TOOLS
#!/bin/bash
set -e
cd /tmp
wget --tries=5 --waitretry=2 --timeout=30 -O legendary \
    "https://github.com/derrod/legendary/releases/download/${LEGENDARY_VERSION}/legendary_linux_x64"
echo "${LEGENDARY_SHA256}  legendary" | sha256sum -c -
install -m 755 legendary /usr/local/bin/legendary
wget --tries=5 --waitretry=2 --timeout=30 -O umu.tar \
    "https://github.com/Open-Wine-Components/umu-launcher/releases/download/${UMU_VERSION}/umu-launcher-${UMU_VERSION}-zipapp.tar"
echo "${UMU_SHA256}  umu.tar" | sha256sum -c -
mkdir umu && tar -xf umu.tar -C umu
umu_run=$(find umu -type f -name umu-run | head -n 1)
[ -n "$umu_run" ] || { echo "umu-run not found in the zipapp tarball" >&2; exit 1; }
install -m 755 "$umu_run" /usr/local/bin/umu-run
rm -rf legendary umu umu.tar
_INSTALL_PC_TOOLS

# Wine for the PC games set to run with plain Wine instead of Proton (a game's
# own way of running, Boxshelf's pc.run): the same Ubuntu packages, 32 and 64
# bit, as GoW's Heroic image, so a prefix made there opens unchanged here.
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends wine wine64 wine32:i386 && \
    rm -rf /var/lib/apt/lists/*

# Wolf mounts the host's Boxshelf.AppImage at /opt/boxshelf/Boxshelf.AppImage:
# every profile runs the host's build (a release or one built from source),
# and the host's updates reach every profile without rebuilding the image.
# Nothing else may live beside it: with no data/ folder there, Boxshelf keeps
# its settings in ~/Boxshelf, which is the profile's own home.
RUN mkdir -p /opt/boxshelf/seed

# Qt (KWin, the Qt emulators) and Electron want a UTF-8 locale
ENV LANG=C.UTF-8

COPY configs/kwinrc /etc/xdg/kwinrc
COPY configs/kwinrulesrc /etc/xdg/kwinrulesrc
COPY configs/kdeglobals /etc/xdg/kdeglobals
COPY --chmod=755 scripts/boxshelf /opt/boxshelf/boxshelf
COPY --chmod=755 scripts/init-session.sh /etc/cont-init.d/40-boxshelf.sh
COPY --chmod=755 scripts/startup-app.sh /opt/gow/startup-app.sh

ARG IMAGE_SOURCE
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
