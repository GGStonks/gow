#!/bin/bash
# Runs as root before the session starts (sourced by the GoW entrypoint).

gow_log "**** (T)rustyShelf: prepare the session ****"

# KWin's Xwayland needs the X11 socket folder to exist ((T)rustyShelf is an X11 app)
mkdir -p /tmp/.X11-unix /tmp/.ICE-unix
chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix

# Wolf can mount folders inside the profile's home (the Citron folders, the
# shared Songs and Custom themes). Docker creates the missing parents of those
# mount points as root, which would leave ~/.local, ~/.config or ~/TrustyShelf
# unwritable for the user. Give those folders, and only those, back. Not
# recursive, so the mounted folders themselves are never touched.

_uid="${PUID:-1000}"
_gid="${PGID:-1000}"
for _dir in "${HOME}/.local" "${HOME}/.local/share" "${HOME}/.config" "${HOME}/TrustyShelf"; do
    if [ -d "${_dir}" ] && [ ! -L "${_dir}" ] && [ "$(stat -c %u "${_dir}")" != "${_uid}" ]; then
        chown "${_uid}:${_gid}" "${_dir}"
        gow_log "chown ${_uid}:${_gid} ${_dir}"
    fi
done
unset _uid _gid _dir

gow_log "DONE"
