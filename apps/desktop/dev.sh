#!/bin/sh
# Runs the desktop app from the source on a Mac over ssh (default mba), with no packing or signing: build.sh DEV=1
# builds build/, which goes to ~/ember-dev/app there next to Electron's own Electron.app (copied once), and that app
# runs it. Electron.app keeps its own signature, so macOS keeps the Local Network grant across updates; it is started
# with `open`, not from ssh, which would make the ssh session the one asking for the network. The app is named ember
# (package.json), so it keeps the packed app's data and sign-in.
#   sh apps/desktop/dev.sh [host]
set -eu
host=${1:-mba}
here=$(cd "$(dirname "$0")" && pwd)
DEV=1 sh "$here/build.sh" >/dev/null
[ -d "$here/node_modules/electron/dist/Electron.app" ] || node "$here/node_modules/electron/install.js"
ssh "$host" 'mkdir -p ~/ember-dev/app'
rsync -a "$here/node_modules/electron/dist/Electron.app" "$host:ember-dev/"
rsync -a --delete "$here/build/" "$host:ember-dev/app/build/"
rsync -a "$here/package.json" "$host:ember-dev/app/package.json"
ssh "$host" 'pkill -f "ember-dev/Electron.app/Contents/MacOS/Electron" || true; sleep 1; open -n -a ~/ember-dev/Electron.app --args ~/ember-dev/app'
echo "running on $host"
