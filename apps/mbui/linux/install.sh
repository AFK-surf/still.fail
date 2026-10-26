#!/bin/sh
# still.fail mbui on Linux, installed for the person who runs this (nothing of the system's touched, no root): the
# program, its engine (with the ICU it carries), shell and core.hbc copied to $XDG_DATA_HOME/fail.still.mbui/app (the
# one before replaced), its icon into the icon theme's hicolor, and a desktop entry, so that it is in the desktop's
# applications and its window is known as it (its app id: MBUI_APP_ID, the entry's name; once for its person, put away
# to its icon among the desktop's: mbui's src/host/linux_life.h). Its newer builds come from the test channel's feed
# (MBUI_UPDATE_FEED, MBUI_BETA: as the Mac's), which the app downloads and puts in place by running this script of
# theirs (mbui's src/host/linux_update.h). Run from the unpacked archive:
#   ./still.fail-mbui/install.sh
# It needs GTK 4.12 or later, WebKit not yet: Ubuntu 24.04, Debian 13, Fedora 40 and newer.
set -e
from=$(cd "$(dirname "$0")" && pwd)
data=${XDG_DATA_HOME:-$HOME/.local/share}
id=fail.still.mbui
app=$data/$id/app
mkdir -p "$data/$id" "$data/applications" "$data/icons/hicolor/512x512/apps"
rm -rf "$app.new"
mkdir -p "$app.new"
cp "$from/stillfail" "$from"/lib*.so* "$from/core.hbc" "$from/VERSION" "$app.new/"
rm -rf "$app" && mv "$app.new" "$app"
cp "$from/icon.png" "$data/icons/hicolor/512x512/apps/$id.png"
cat > "$data/applications/$id.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=still.fail mbui
Comment=still.fail, the app written in mbui
Exec=env MBUI_APP_ID=$id "MBUI_APP_NAME=still.fail mbui" MBUI_UPDATE_FEED=linux/mbui MBUI_BETA=1 "$app/stillfail"
Icon=$id
Terminal=false
Categories=Network;Chat;Development;
StartupWMClass=$id
ENTRY
command -v update-desktop-database > /dev/null && update-desktop-database -q "$data/applications" || true
command -v gtk-update-icon-cache > /dev/null && gtk-update-icon-cache -q -t "$data/icons/hicolor" 2> /dev/null || true
echo "still.fail mbui $(cat "$app/VERSION") installed: $app (in your applications as still.fail mbui)"
