#!/bin/bash
# Runs as the profile's user. Prepares Boxshelf's folder, then starts a nested
# KWin that runs Boxshelf as its only session: when Boxshelf exits (quick menu
# -> Power -> Exit), KWin exits and Wolf closes the stream.
set -e

source /opt/gow/bash-lib/utils.sh

BOXSHELF_APPIMAGE="${BOXSHELF_APPIMAGE:-/opt/boxshelf/Boxshelf.AppImage}"
SEED_CONFIG="/opt/boxshelf/seed/config.json"
# Boxshelf's own choice when there's no data/ folder beside the AppImage
BOXSHELF_ROOT="${HOME}/Boxshelf"

if [ ! -f "${BOXSHELF_APPIMAGE}" ]; then
    gow_log "[Boxshelf] ERROR: ${BOXSHELF_APPIMAGE} is missing."
    gow_log "[Boxshelf] Mount the host's Boxshelf.AppImage there (see the app's wolf.config.toml)."
    sleep 20 # keep the message on the logs long enough to be read
    exit 1
fi

mkdir -p "${BOXSHELF_ROOT}/data" "${HOME}/Applications"

# ---------- First start: settings from the host, without its accounts ----------
# The seed is a copy the host prepares with its credentials already removed
# (RetroAchievements, ScreenScraper, API keys). Strip them here too, in case a
# raw config is ever mounted, and the host's own PC games folders and per-game
# ways of running (BOXSHELF_PC gives the account's). Only used when this
# profile has no settings yet.
if [ ! -s "${BOXSHELF_ROOT}/data/config.json" ] && [ -s "${SEED_CONFIG}" ]; then
    gow_log "[Boxshelf] First start: copying the shared settings"
    if jq 'del(.keys, .keysEnc, .ra)
           | del(.pc.run, .pc.prefixDir, .pc.homeDir, .pc.userGamesDir)
           | .steam.enabled = false
           | .ui.installs = []
           | .ui.updateCheck = false' \
          "${SEED_CONFIG}" > "${BOXSHELF_ROOT}/data/config.json.tmp"; then
        mv "${BOXSHELF_ROOT}/data/config.json.tmp" "${BOXSHELF_ROOT}/data/config.json"
    else
        gow_log "[Boxshelf] The seed isn't valid JSON, starting with Boxshelf's own setup"
        rm -f "${BOXSHELF_ROOT}/data/config.json.tmp"
    fi
fi

# ---------- Every start: this account's own PC games folders ----------
# BOXSHELF_PC (JSON, from the Wolf entry) names the account's folders: the shared
# PC games folder, its own copies, Wine prefixes and the home Linux games get
# (their saves). They're the account's, so they're set at every start; the
# programs it names are defaults a choice made in Settings wins over.
if [ -n "${BOXSHELF_PC:-}" ] && [ -s "${BOXSHELF_ROOT}/data/config.json" ]; then
    if jq --argjson pc "${BOXSHELF_PC}" \
          '.pc = ((.pc // {}) + ($pc | del(.programs, .run)))
           | .pc.programs = (($pc.programs // {}) + (.pc.programs // {}))
           | .pc.run = (($pc.run // {}) + (.pc.run // {}))' \
          "${BOXSHELF_ROOT}/data/config.json" > "${BOXSHELF_ROOT}/data/config.json.tmp"; then
        mv "${BOXSHELF_ROOT}/data/config.json.tmp" "${BOXSHELF_ROOT}/data/config.json"
    else
        gow_log "[Boxshelf] BOXSHELF_PC isn't valid JSON, or the settings aren't: PC games folders left as they are"
        rm -f "${BOXSHELF_ROOT}/data/config.json.tmp"
    fi
fi

# ---------- First start: the box-art database, copied instead of downloaded ----------
# Boxshelf downloads LaunchBox's game database (109 MB) and indexes it (235 MB) on a profile's first start, which
# also froze the shelf for several seconds. A copy made once on the host (/etc/wolf/boxshelf/boxart-cache, mounted
# read-only) is copied into a profile that has none; on btrfs that's a reflink, so it takes no time and no room.
# Each profile keeps its own copy afterwards: Boxshelf refreshes and rewrites it, so it isn't shared read-write.
BOXART_SEED="/opt/boxshelf/seed/boxart-cache"
if [ ! -e "${BOXSHELF_ROOT}/data/boxart-cache/launchbox-index.json" ] && [ -e "${BOXART_SEED}/launchbox-index.json" ]; then
    gow_log "[Boxshelf] First start: copying the box-art database"
    mkdir -p "${BOXSHELF_ROOT}/data/boxart-cache"
    cp -a --reflink=auto "${BOXART_SEED}/." "${BOXSHELF_ROOT}/data/boxart-cache/" \
        || gow_log "[Boxshelf] Couldn't copy the box-art database; Boxshelf will download it"
fi

# ---------- Emulators where Boxshelf looks for them ----------
# Boxshelf scans ~/Applications for AppImages by name (dolphin*, cemu*,
# pcsx2*, rpcs3*, citron*, ...). Link the image's emulators there, plus any
# AppImage in the folders listed in BOXSHELF_EMULATOR_DIRS (':'-separated).
shopt -s nullglob
_link_appimages() {
    local dir="$1" f
    [ -d "${dir}" ] || return 0
    for f in "${dir}"/*.AppImage; do
        ln -sfn "${f}" "${HOME}/Applications/$(basename "${f}")"
    done
}
_link_appimages /Applications
IFS=':' read -r -a _emu_dirs <<< "${BOXSHELF_EMULATOR_DIRS:-}"
for _d in "${_emu_dirs[@]}"; do
    _link_appimages "${_d}"
done
# Drop links whose target has gone (an emulator removed or renamed)
find "${HOME}/Applications" -maxdepth 1 -xtype l -delete
shopt -u nullglob

# ---------- Session ----------
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_DESKTOP=KDE
export XDG_SESSION_TYPE=wayland
export KDE_SESSION_VERSION=6
export XCURSOR_THEME=breeze_cursors
export XCURSOR_SIZE=24
# Wolf's output has no hardware cursor plane
export KWIN_FORCE_SW_CURSOR=1

WIDTH="${GAMESCOPE_WIDTH:-1920}"
HEIGHT="${GAMESCOPE_HEIGHT:-1080}"

# Mouse-look in games (Minecraft, any game that captures the mouse): the nested KWin gets the mouse's relative
# movement only once it has locked the cursor in Wolf's compositor, which it does on Right Ctrl. pointer-lock presses
# it once Boxshelf is up (see the script).
/opt/boxshelf/pointer-lock &

gow_log "[Boxshelf] Starting KWin ${WIDTH}x${HEIGHT} with Boxshelf"
exec dbus-run-session -- kwin_wayland \
    --xwayland \
    --no-lockscreen \
    --no-global-shortcuts \
    --socket wayland-boxshelf \
    --width "${WIDTH}" --height "${HEIGHT}" \
    --exit-with-session /opt/boxshelf/boxshelf
