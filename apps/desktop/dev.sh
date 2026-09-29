#!/bin/sh
# Runs the desktop app from the source on a Mac over ssh (default mini1), with no packing or signing: build.sh DEV=1
# builds build/, which goes to ~/ember-dev/app there next to Electron's own Electron.app (copied once), and that app
# runs it. Electron.app keeps its own signature, so macOS keeps the Local Network grant across updates; it is started
# with `open`, not from ssh, which would make the ssh session the one asking for the network. The app is named still.fail
# (package.json), so it keeps the packed app's data and sign-in. Its pages can be read over DevTools on the Mac's
# localhost:9333 (ssh -L), for looking at what it shows.
#   sh apps/desktop/dev.sh [host]          (HMR=1: the page from a Vite dev server on this machine, live)
set -eu
host=${1:-mini1}
here=$(cd "$(dirname "$0")" && pwd)
DEV=1 sh "$here/build.sh" >/dev/null
[ -d "$here/node_modules/electron/dist/Electron.app" ] || node "$here/node_modules/electron/install.js"
ssh "$host" 'mkdir -p ~/ember-dev/app'
rsync -a "$here/node_modules/electron/dist/Electron.app" "$host:ember-dev/"
rsync -a --delete "$here/build/" "$host:ember-dev/app/build/"
rsync -a "$here/package.json" "$host:ember-dev/app/package.json"
# HMR=1: the page comes from a Vite dev server here (started once, left running), which the Mac reaches on the LAN.
dev=""
if [ -n "${HMR:-}" ]; then
  root=$(cd "$here/../.." && pwd)
  ip=$(ipconfig getifaddr en0 || ipconfig getifaddr en1)
  if ! curl -s -o /dev/null "http://127.0.0.1:5173/"; then
    (cd "$root" && nohup pnpm exec vite --config web/vite.config.ts --mode cloud --host 0.0.0.0 --port 5173 --strictPort > /tmp/ember-vite.log 2>&1 &)
    for _ in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:5173/" && break; sleep 1; done
  fi
  dev="--dev-url=http://$ip:5173"
fi
# The old one must be gone first: a second instance finds its single-instance lock and quits at once.
ssh "$host" "pkill -f 'ember-dev/Electron.app/Contents/MacOS/Electron' || true; for i in \$(seq 1 30); do pgrep -f 'ember-dev/Electron.app/Contents/MacOS/Electron' >/dev/null || break; sleep 0.5; done; open -n -a ~/ember-dev/Electron.app --args ~/ember-dev/app --remote-debugging-port=9333 $dev"
echo "running on $host"
