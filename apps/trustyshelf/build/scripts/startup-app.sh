#!/bin/bash
# Runs as the profile's user. Prepares (T)rustyShelf's folder, then starts a nested
# KWin that runs (T)rustyShelf as its only session: when (T)rustyShelf exits (quick menu
# -> Power -> Exit), KWin exits and Wolf closes the stream.
set -e

source /opt/gow/bash-lib/utils.sh

TRUSTYSHELF_APPIMAGE="${TRUSTYSHELF_APPIMAGE:-/opt/trustyshelf/TrustyShelf.AppImage}"
SEED_CONFIG="/opt/trustyshelf/seed/config.json"
# (T)rustyShelf's own choice when there's no data/ folder beside the AppImage
TRUSTYSHELF_ROOT="${HOME}/TrustyShelf"

if [ ! -f "${TRUSTYSHELF_APPIMAGE}" ]; then
    gow_log "[(T)rustyShelf] ERROR: ${TRUSTYSHELF_APPIMAGE} is missing."
    gow_log "[(T)rustyShelf] Mount the host's TrustyShelf.AppImage there (see the app's wolf.config.toml)."
    sleep 20 # keep the message on the logs long enough to be read
    exit 1
fi

# (an account's data from before the rename to (T)rustyShelf: ~/Boxshelf becomes ~/TrustyShelf)
if [ -d "${HOME}/Boxshelf" ] && [ ! -e "${TRUSTYSHELF_ROOT}" ]; then
    mv "${HOME}/Boxshelf" "${TRUSTYSHELF_ROOT}" && gow_log "[(T)rustyShelf] Moved ~/Boxshelf to ~/TrustyShelf"
fi
mkdir -p "${TRUSTYSHELF_ROOT}/data" "${HOME}/Applications"

# ---------- The profile's own copy of (T)rustyShelf, which it can update itself ----------
# Settings -> System -> "Automatically update on startup" replaces the AppImage that's running ($APPIMAGE) with the new
# release. The host's is mounted read-only and shared, so each profile runs its own copy, ~/TrustyShelf/app: an update
# replaces that one, for this profile only. When the host's AppImage changes after the copy was made (the host updated
# or a build of its own), it's copied over this one at the next start, so the host's updates still reach every profile.
# The copy keeps the host file's date (cp -p), so an unchanged host file is never copied again; on btrfs it's a
# reflink, no time and no room.
APP_COPY="${TRUSTYSHELF_ROOT}/app/TrustyShelf.AppImage"
rm -f "${APP_COPY}.update.tmp" # (a download an update didn't finish)
if [ ! -s "${APP_COPY}" ] || [ "${TRUSTYSHELF_APPIMAGE}" -nt "${APP_COPY}" ]; then
    mkdir -p "${APP_COPY%/*}"
    if cp --reflink=auto -p "${TRUSTYSHELF_APPIMAGE}" "${APP_COPY}.tmp" && mv -f "${APP_COPY}.tmp" "${APP_COPY}"; then
        gow_log "[(T)rustyShelf] Copied the host's (T)rustyShelf to ${APP_COPY}"
    else
        rm -f "${APP_COPY}.tmp"
        gow_log "[(T)rustyShelf] Couldn't copy the host's (T)rustyShelf: running it read-only (no updates from here)"
    fi
fi
if [ -x "${APP_COPY}" ]; then
    export TRUSTYSHELF_APPIMAGE="${APP_COPY}"
fi

# ---------- First start: settings from the host, without its accounts ----------
# The seed is a copy the host prepares with its credentials already removed
# (RetroAchievements, ScreenScraper, API keys). Strip them here too, in case a
# raw config is ever mounted, and the host's own PC games folders and per-game
# ways of running (TRUSTYSHELF_PC gives the account's). Only used when this
# profile has no settings yet.
if [ ! -s "${TRUSTYSHELF_ROOT}/data/config.json" ] && [ -s "${SEED_CONFIG}" ]; then
    gow_log "[(T)rustyShelf] First start: copying the shared settings"
    if jq 'del(.keys, .keysEnc, .ra)
           | del(.pc.run, .pc.prefixDir, .pc.homeDir, .pc.userGamesDir)
           | .steam.enabled = false
           | .ui.installs = []' \
          "${SEED_CONFIG}" > "${TRUSTYSHELF_ROOT}/data/config.json.tmp"; then
        mv "${TRUSTYSHELF_ROOT}/data/config.json.tmp" "${TRUSTYSHELF_ROOT}/data/config.json"
    else
        gow_log "[(T)rustyShelf] The seed isn't valid JSON, starting with (T)rustyShelf's own setup"
        rm -f "${TRUSTYSHELF_ROOT}/data/config.json.tmp"
    fi
fi

# ---------- Every start: this account's own PC games folders ----------
# TRUSTYSHELF_PC (JSON, from the Wolf entry) names the account's folders: the shared
# PC games folder, its own copies, Wine prefixes and the home Linux games get
# (their saves). They're the account's, so they're set at every start; the
# programs it names are defaults a choice made in Settings wins over.
if [ -n "${TRUSTYSHELF_PC:-}" ] && [ -s "${TRUSTYSHELF_ROOT}/data/config.json" ]; then
    if jq --argjson pc "${TRUSTYSHELF_PC}" \
          '.pc = ((.pc // {}) + ($pc | del(.programs, .run)))
           | .pc.programs = (($pc.programs // {}) + (.pc.programs // {}))
           | .pc.run = (($pc.run // {}) + (.pc.run // {}))' \
          "${TRUSTYSHELF_ROOT}/data/config.json" > "${TRUSTYSHELF_ROOT}/data/config.json.tmp"; then
        mv "${TRUSTYSHELF_ROOT}/data/config.json.tmp" "${TRUSTYSHELF_ROOT}/data/config.json"
    else
        gow_log "[(T)rustyShelf] TRUSTYSHELF_PC isn't valid JSON, or the settings aren't: PC games folders left as they are"
        rm -f "${TRUSTYSHELF_ROOT}/data/config.json.tmp"
    fi
fi

# ---------- First start: the box-art database, copied instead of downloaded ----------
# (T)rustyShelf downloads LaunchBox's game database (109 MB) and indexes it (235 MB) on a profile's first start, which
# also froze the shelf for several seconds. A copy made once on the host (/etc/wolf/trustyshelf/boxart-cache, mounted
# read-only) is copied into a profile that has none; on btrfs that's a reflink, so it takes no time and no room.
# Each profile keeps its own copy afterwards: (T)rustyShelf refreshes and rewrites it, so it isn't shared read-write.
BOXART_SEED="/opt/trustyshelf/seed/boxart-cache"
if [ ! -e "${TRUSTYSHELF_ROOT}/data/boxart-cache/launchbox-index.json" ] && [ -e "${BOXART_SEED}/launchbox-index.json" ]; then
    gow_log "[(T)rustyShelf] First start: copying the box-art database"
    mkdir -p "${TRUSTYSHELF_ROOT}/data/boxart-cache"
    cp -a --reflink=auto "${BOXART_SEED}/." "${TRUSTYSHELF_ROOT}/data/boxart-cache/" \
        || gow_log "[(T)rustyShelf] Couldn't copy the box-art database; (T)rustyShelf will download it"
fi

# ---------- Emulators where (T)rustyShelf looks for them ----------
# (T)rustyShelf scans ~/Applications for AppImages by name (dolphin*, cemu*,
# pcsx2*, rpcs3*, citron*, ...). Link the image's emulators there, plus any
# AppImage in the folders listed in TRUSTYSHELF_EMULATOR_DIRS (':'-separated).
shopt -s nullglob
_link_appimages() {
    local dir="$1" f
    [ -d "${dir}" ] || return 0
    for f in "${dir}"/*.AppImage; do
        ln -sfn "${f}" "${HOME}/Applications/$(basename "${f}")"
    done
}
_link_appimages /Applications
IFS=':' read -r -a _emu_dirs <<< "${TRUSTYSHELF_EMULATOR_DIRS:-}"
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
# it once (T)rustyShelf is up (see the script).
/opt/trustyshelf/pointer-lock &

gow_log "[(T)rustyShelf] Starting KWin ${WIDTH}x${HEIGHT} with (T)rustyShelf"
exec dbus-run-session -- kwin_wayland \
    --xwayland \
    --no-lockscreen \
    --no-global-shortcuts \
    --socket wayland-trustyshelf \
    --width "${WIDTH}" --height "${HEIGHT}" \
    --exit-with-session /opt/trustyshelf/trustyshelf
