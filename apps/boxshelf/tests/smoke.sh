#!/usr/bin/env bash
# Boxshelf itself is mounted from the host at run time, so this checks what the
# image provides: the nested compositor, the launch scripts and the emulators.

source /smoke-common/lib.sh

assert_path /opt/gow/startup-app.sh /etc/cont-init.d/40-boxshelf.sh
assert_path /opt/boxshelf/boxshelf /opt/boxshelf/seed /etc/xdg/kwinrc

for bin in kwin_wayland Xwayland dbus-run-session jq retroarch legendary umu-run bwrap; do
  if command -v "$bin" >/dev/null 2>&1; then ok "$bin is installed"; else bad "$bin is installed"; fi
done

# Nothing may sit beside the mounted AppImage, or Boxshelf would keep its
# settings there instead of in the profile's home.
if [[ ! -e /opt/boxshelf/data ]]; then ok "no data/ beside the AppImage"; else bad "no data/ beside the AppImage"; fi

smoke_report
