// The still.fail station's installer, served at /install.sh: `curl -fsSL <origin>/install.sh | sh -s -- <token>` on the
// machine that is to be a station. It gets the release for the machine (scripts/release.sh put it in the releases
// bucket, served at /releases/<file>), puts it in ~/.stillfail/app (the data around it stays), links `stillfail` (and
// `ember`, its name before the rename) into ~/.local/bin, joins the workspace the token is for, and runs the station as
// a service of the user (launchd), started at login and again if it stops. Claude Code and Codex are the machine's own:
// it says how to get them when they are missing.
// On Linux the service is a systemd user service (lingering, so it runs with no one logged in); with no user systemd
// (a container, another init) the station is started in the background, and said not to come back after a reboot.
// Without a token, on a station already in a workspace, it updates the station (`stillfail update` runs it so). An update
// does not stop the agents when it can help it: with the service's definition unchanged, the running station hands
// over to the new release in its own process (SIGUSR2, the Rust station's main.rs), turns, runtimes and jobs going on;
// else, or if that fails, the station is first drained (SIGUSR1: no new turns, and it says once none runs), then
// restarted. A station older than these says neither (no run/station.json): it is restarted as before.
// The service's PATH is the caller's (the agents are found on it), so it is not what makes a definition "changed": an
// update from another shell (an agent's, the station's own) would never hand over. Started from inside the station (an
// agent's turn, a job), a restart goes on in the background, apart from the caller: the drain waits for the caller's
// own turn to end, which does not end while it waits. A station already on this release is left as it is.
// A station installed before the rename (docs/rename-still-fail.md: ~/.ember, the service org.3720.ember.station or
// ember-station.service, `ember` in ~/.local/bin) is moved, not installed beside: its service is drained and stopped
// (its definition differs, so it is never handed over), ~/.ember moved to ~/.stillfail with a link left at the old
// place, the old service's definition removed and the new one started; `ember` is linked to the new command.

import { tr, type Lang } from "./i18n.ts";

/**
 * The installer for a still.fail cloud at `origin`, getting the release of `channel` by default: the stable one, or the
 * test channel's (beta/, scripts/release.sh --beta). STILLFAIL_CHANNEL where it runs says otherwise.
 */
export function installScript(origin: string, channel: "stable" | "beta" = "stable", lang: Lang = "zh"): string {
  return script((key, args) => tr(lang, key, args)).replaceAll("__ORIGIN__", origin).replaceAll("__CHANNEL__", channel);
}

/**
 * A release's file, as the bucket keeps it: stillfail-station-<platform>.tar.gz; ember-station-<platform>.tar.gz is the
 * last release from before the rename, which installers from before it still get. Windows' is a zip (install-windows.ts).
 */
export const RELEASE_FILE = /^((stillfail|ember)-station-(darwin-arm64|linux-x64|linux-arm64)\.tar\.gz|stillfail-station-win32-x64\.zip)$/;

/** The test channel's release (scripts/release.sh --beta), until promoted to the stable name. */
export const BETA_RELEASE_FILE = /^beta\/stillfail-station-((darwin-arm64|linux-x64|linux-arm64)\.tar\.gz|win32-x64\.zip)$/;

/**
 * The Node a release runs on (its NODE_VERSION file says the version), kept apart from it, once per version (scripts/node-dist.sh):
 * the installer gets it when the machine has none of that version yet, with its sha256 to check it by.
 */
export const NODE_FILE = /^node\/node-v[0-9]+\.[0-9]+\.[0-9]+-((darwin-arm64|linux-x64|linux-arm64)\.tar\.gz|win-x64\.zip)(\.sha256)?$/;

/**
 * The apps' builds, as scripts/release.sh puts them beside the station's: what each app's updater reads for the
 * latest (the desktop app's electron-updater, the Android app's Updates.kt), and the files it names.
 */
const APP_FILES: [RegExp, string][] = [
  // The station's latest release, for stations to say a newer one is out (the Rust station's updates.rs).
  [/^station\.json$/, "application/json"],
  // The test channel's (scripts/release.sh --beta): the station's latest, and the beta apps' (fail.still.desktop.beta,
  // fail.still.android.beta, apps of their own beside the released ones): the desktop one's feed (electron-updater's
  // channel stillfail-beta) and the Android one's, with the builds they name (stillfail-beta-…).
  [/^station-beta\.json$/, "application/json"],
  [/^desktop\/stillfail-beta-mac\.yml$/, "text/yaml; charset=utf-8"],
  [/^desktop\/stillfail-beta\.yml$/, "text/yaml; charset=utf-8"],
  [/^android\/beta\/latest\.json$/, "application/json"],
  [/^desktop\/stillfail-mac\.yml$/, "text/yaml; charset=utf-8"],
  [/^desktop\/stillfail-(beta-)?[0-9.]+-arm64-mac\.zip$/, "application/zip"],
  // Its blockmap, for the updater to download only what changed since the zip it has (releases.ts).
  [/^desktop\/stillfail-(beta-)?[0-9.]+-arm64-mac\.zip\.blockmap$/, "application/octet-stream"],
  // The Windows app's (apps/desktop/build.sh --win): its feed (electron-updater's, named by the channel alone), its NSIS
  // installer and that one's blockmap.
  [/^desktop\/stillfail\.yml$/, "text/yaml; charset=utf-8"],
  [/^desktop\/stillfail-(beta-)?[0-9.]+-x64-win\.exe$/, "application/vnd.microsoft.portable-executable"],
  [/^desktop\/stillfail-(beta-)?[0-9.]+-x64-win\.exe\.blockmap$/, "application/octet-stream"],
  [/^android\/latest\.json$/, "application/json"],
  // Builds from before the rename were android/ember-<n>.apk: the latest.json of then and the apps it updated name them.
  [/^android\/(stillfail|ember|stillfail-beta)-[0-9]+\.apk$/, "application/vnd.android.package-archive"],
];

/** The content type a file of the releases bucket is served with; null for a name that is not one of its files. */
export function releaseType(file: string): string | null {
  const archive = file.endsWith(".zip") ? "application/zip" : "application/gzip";
  if (RELEASE_FILE.test(file) || BETA_RELEASE_FILE.test(file)) return archive;
  if (NODE_FILE.test(file)) return file.endsWith(".sha256") ? "text/plain; charset=utf-8" : archive;
  return APP_FILES.find(([name]) => name.test(file))?.[1] ?? null;
}

// A variable is always braced where words follow it ("\${app}（…）"): sh may take the first byte of a non-ASCII
// character for part of its name, and set -u stops the script there.
// What it says is in the language it was asked for (?lang=, Accept-Language); `say` gives it, with what the shell puts
// in ($names, $(commands)) given as arguments.
const script = (say: (key: string, args?: Record<string, string>) => string) => `#!/bin/sh
# Installs the still.fail station on this machine and joins it to a workspace in still.fail cloud:
#   curl -fsSL __ORIGIN__/install.sh | sh -s -- <token>
# STILLFAIL_CHANNEL=beta gets the test channel's release (stable: the usual one); this copy defaults to __CHANNEL__.
# The token comes from 「添加 station」 in still.fail. Running it again updates it and keeps its data (~/.stillfail;
# a station from before the rename has it in ~/.ember, which is moved there).
set -eu
origin="__ORIGIN__"
token="\${1:-}"
# The data: $STILLFAIL_DATA, else $EMBER_DATA (a shell or service from before the rename), else ~/.stillfail. ~/.ember,
# the default before the rename, is the default now too: it is moved to ~/.stillfail.
old_data="$HOME/.ember"
data="\${STILLFAIL_DATA:-\${EMBER_DATA:-$HOME/.stillfail}}"
[ "$data" = "$old_data" ] && data="$HOME/.stillfail"
# Moved from ~/.ember: only there (or ~/.stillfail an empty directory), not already moved (a link to ~/.stillfail).
# Until then what runs now is found there.
migrate=""
if [ "$data" = "$HOME/.stillfail" ] && { [ -e "$old_data" ] || [ -L "$old_data" ]; } && [ "$(readlink "$old_data" 2>/dev/null)" != "$data" ]; then
  if { [ ! -e "$data" ] && [ ! -L "$data" ]; } || { [ -d "$data" ] && [ ! -L "$data" ] && [ -z "$(ls -A "$data")" ]; }; then
    migrate=yes
  fi
fi
cur="$data"
[ -n "$migrate" ] && cur="$old_data"
# Where the update is, for the station to show on its pages (the Rust station's updates.rs): download, handoff, drain,
# restart. Only for a station that is there to read it.
step() { [ -d "$cur/run" ] && printf '%s\n' "$1" > "$cur/run/update.step" 2>/dev/null || true; }
# A station already in a workspace is only updated: no token, and it stays the same station.
if [ -z "$token" ] && [ ! -f "$cur/mesh/cloud.json" ]; then
  echo "${say("cloud.install.usage", { origin: "$origin" })}" >&2
  echo "${say("cloud.install.updateNoToken")}" >&2
  exit 2
fi
os=$(uname -s)
case "$os-$(uname -m)" in
  Darwin-arm64) platform=darwin-arm64 ;;
  Linux-x86_64) platform=linux-x64 ;;
  Linux-aarch64|Linux-arm64) platform=linux-arm64 ;;
  *) echo "${say("cloud.install.unsupported", { machine: "$(uname -s) $(uname -m)" })}" >&2; exit 1 ;;
esac
app="$data/app"
label="fail.still.station"
plist="$HOME/Library/LaunchAgents/$label.plist"
unit_dir="\${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
unit="stillfail-station.service"
# The service as it was named before the rename: stopped and removed, the new one in its place.
old_label="org.3720.ember.station"
old_plist="$HOME/Library/LaunchAgents/$old_label.plist"
old_unit="ember-station.service"
# Whether this Linux has a systemd for the user to run services in (not a container's, not another init).
user_systemd() { command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

channel="\${STILLFAIL_CHANNEL:-__CHANNEL__}"
case "$channel" in
  beta) release="beta/stillfail-station-$platform.tar.gz"; echo "${say("cloud.install.downloadBeta")}" ;;
  *) channel=stable; release="stillfail-station-$platform.tar.gz"; echo "${say("cloud.install.download")}" ;;
esac
step download
curl -fL --progress-bar "$origin/releases/$release" -o "$tmp/stillfail.tar.gz"
tar -xzf "$tmp/stillfail.tar.gz" -C "$tmp"
# Which channel the release came from, for the station (the Rust station's updates.rs: where it goes back from the beta).
printf '%s\n' "$channel" > "$tmp/stillfail/CHANNEL"

# The Node it runs on (NODE_VERSION: its version) is not in the release: kept apart in node/v<version> beside the data, once per
# version, and linked at <app>/node, where the launcher finds it (and a launcher of an older release handing over to
# this one: it looks there too). The machine's own Node does when it is that very version (another one is not what the
# station was tested on); else it is downloaded and checked. A release from before (Node in it, no NODE_VERSION) needs none.
node_dir=""
if [ -f "$tmp/stillfail/NODE_VERSION" ]; then
  node_version=$(cat "$tmp/stillfail/NODE_VERSION")
  node_dir="$cur/node/v$node_version"
  if [ ! -x "$node_dir/bin/node" ]; then
    rm -rf "$node_dir.part"
    mkdir -p "$node_dir.part/bin"
    own=$(command -v node 2>/dev/null || true)
    if [ -n "$own" ] && [ "$("$own" -v 2>/dev/null)" = "v$node_version" ]; then
      cp "$own" "$node_dir.part/bin/node"
    else
      node_file="node-v$node_version-$platform.tar.gz"
      echo "${say("cloud.install.node.download", { version: "${node_version}" })}"
      if ! curl -fL --progress-bar "$origin/releases/node/$node_file" -o "$tmp/$node_file" || ! curl -fsSL "$origin/releases/node/$node_file.sha256" -o "$tmp/$node_file.sha256"; then
        echo "${say("cloud.install.node.failed", { version: "${node_version}", origin: "${origin}" })}" >&2
        exit 1
      fi
      want=$(cut -d' ' -f1 < "$tmp/$node_file.sha256")
      got=$({ shasum -a 256 "$tmp/$node_file" 2>/dev/null || sha256sum "$tmp/$node_file"; } | cut -d' ' -f1)
      if [ -z "$want" ] || [ "$want" != "$got" ]; then
        echo "${say("cloud.install.node.mismatch", { version: "${node_version}" })}" >&2
        exit 1
      fi
      tar -xzf "$tmp/$node_file" -C "$node_dir.part"
    fi
    "$node_dir.part/bin/node" -v >/dev/null 2>&1 || { echo "${say("cloud.install.node.broken", { version: "${node_version}" })}" >&2; exit 1; }
    mv "$node_dir.part" "$node_dir"
  fi
  ln -s "$node_dir" "$tmp/stillfail/node"
fi
# The Nodes no release here runs on any more, once it runs on this one (a running old one keeps its binary open).
prune_node() {
  [ -n "$node_dir" ] || return 0
  for d in "$(dirname "$node_dir")"/v*; do
    [ "$d" = "$node_dir" ] || rm -rf "$d"
  done
}

# The agents it starts are found on this PATH (Claude Code, Codex, and what they run). Each directory once: run from
# the station (whose PATH is this), it would otherwise grow with every update.
agent_path=$(printf '%s' "$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH:/usr/bin:/bin" | tr ':' '\n' | awk 'NF && !seen[$0]++' | paste -sd: -)
# The service's definition, as this release has it: written below, and compared with the one running now.
if [ "$os" = Darwin ]; then
  service_file="$plist"
  cat > "$tmp/service" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key><array><string>$app/bin/stillfail</string><string>start</string></array>
    <key>EnvironmentVariables</key><dict><key>PATH</key><string>$agent_path</string><key>STILLFAIL_DATA</key><string>$data</string></dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$data/stillfail.log</string>
    <key>StandardErrorPath</key><string>$data/stillfail.log</string>
</dict>
</plist>
PLIST
elif user_systemd; then
  service_file="$unit_dir/$unit"
  # KillMode=process: stopping the service stops the station, not the jobs it runs (the next one takes them up).
  cat > "$tmp/service" <<UNIT
[Unit]
Description=still.fail station
After=network-online.target

[Service]
ExecStart=$app/bin/stillfail start
Environment=PATH=$agent_path
Environment=STILLFAIL_DATA=$data
Restart=always
RestartSec=5
KillMode=process
StandardOutput=append:$data/stillfail.log
StandardError=append:$data/stillfail.log

[Install]
WantedBy=default.target
UNIT
else
  service_file=""
fi

# What the running station says of itself (run/station.json): its pid, when it started, what it can do.
station_json="$cur/run/station.json"
said() { sed -n "s/.*\\"$1\\": *\\([0-9]*\\).*/\\1/p" "$station_json" 2>/dev/null | head -1; }
pid=""
if [ -z "$token" ] && [ -f "$station_json" ]; then
  pid=$(said pid)
  # Still that station (a pid is reused once its process is gone): signals go to nothing else.
  case "$(ps -p "\${pid:-0}" -o command= 2>/dev/null)" in
    *stillfail-station*|*ember-station*) ;;
    *) pid="" ;;
  esac
fi
# The service's definition, less its PATH: what makes a service "changed".
without_path() { sed -e 's#<key>PATH</key><string>[^<]*</string>##' -e '/^Environment=PATH=/d' "$1"; }
same_service() { [ -z "$service_file" ] || { [ -f "$service_file" ] && [ "$(without_path "$tmp/service")" = "$(without_path "$service_file")" ]; }; }
# Whether this runs inside the station: the station among the processes it comes from (an agent's turn, a job).
inside_station() {
  p=$$
  while [ -n "$p" ] && [ "$p" -gt 1 ]; do
    [ "$p" = "$pid" ] && return 0
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
  done
  return 1
}

# Already on this release, and running as its service would: nothing to do.
if [ -n "$pid" ] && [ -z "$migrate" ] && [ -f "$app/VERSION" ] && cmp -s "$tmp/stillfail/VERSION" "$app/VERSION" && same_service; then
  cp "$tmp/stillfail/CHANNEL" "$app/CHANNEL" 2>/dev/null || true
  echo "${say("cloud.install.upToDate", { version: '$(cut -c1-7 "$app/VERSION")' })}"
  exit 0
fi

swapped=""
swap_app() {
  mkdir -p "$data"
  rm -rf "$app.old"
  [ -d "$app" ] && mv "$app" "$app.old"
  mv "$tmp/stillfail" "$app"
  swapped=yes
}

# ~/.ember to ~/.stillfail, once the station from before the rename is stopped, with a link left at the old place (the
# paths written down under it lead there still). Should the move fail, ~/.stillfail is made a link to ~/.ember instead.
move_data() {
  [ -n "$migrate" ] || return 0
  if [ -d "$data" ] && [ ! -L "$data" ]; then rmdir "$data" 2>/dev/null || true; fi
  if mv "$old_data" "$data" 2>/dev/null; then
    ln -s "$data" "$old_data" || echo "${say("cloud.install.move.noLink", { data: "${data}", old: "${old_data}" })}" >&2
    echo "${say("cloud.install.move.moved", { data: "${data}", old: "${old_data}" })}"
  else
    ln -s "$old_data" "$data"
    echo "${say("cloud.install.move.linked", { data: "${data}", old: "${old_data}" })}" >&2
  fi
  migrate=""
}

# Handed over without stopping: the new release goes where the old one was, and the running station execs it.
handed=""
if [ -n "$pid" ] && [ -z "$migrate" ] && [ -n "$(said handoff)" ] && same_service; then
  started=$(said startedAt)
  swap_app
  rm -f "$data/run/handoff-failed"
  step handoff
  echo "${say("cloud.install.handoff.start")}"
  kill -USR2 "$pid"
  # The new one's 60 s to be ready and 90 s to take over (launcher/src/lifecycle.rs Times), and some.
  for _ in $(seq 1 180); do
    sleep 1
    if [ "$(said startedAt)" != "$started" ]; then
      [ "$(said pid)" = "$pid" ] && handed=yes
      break
    fi
    [ -f "$data/run/handoff-failed" ] && break
  done
  if [ -n "$handed" ]; then
    rm -rf "$app.old"
    prune_node
  elif [ -f "$data/run/handoff-failed" ] && kill -0 "$pid" 2>/dev/null && [ "$(said startedAt)" = "$started" ]; then
    # The new release did not come up or take over, and the station is the launcher it was: the release before goes
    # back, for the Node serving on it (one that did not get ready) or the one the launcher starts after a while (one
    # that did not take over, its old one gone; Times::rollback).
    rm -rf "$app.failed"
    mv "$app" "$app.failed" && { mv "$app.old" "$app" || mv "$app.failed" "$app"; }
    rm -rf "$app.failed"
    echo "${say("cloud.install.handoff.keptOld", { why: '$(cat "$data/run/handoff-failed")' })}" >&2
    exit 1
  elif [ -f "$data/run/handoff-failed" ]; then
    echo "${say("cloud.install.handoff.failed", { why: '$(cat "$data/run/handoff-failed")' })}" >&2
  elif [ "$(said startedAt)" != "$started" ]; then
    # It went down mid-way and its service started the new release: done, the usual way.
    handed=restarted
    rm -rf "$app.old"
  else
    echo "${say("cloud.install.handoff.noAnswer")}" >&2
  fi
fi

# Stopped and started again (when not handed over), and said how it went.
restart_and_finish() {
if [ -z "$handed" ] && [ -n "$pid" ] && [ -n "$(said drain)" ] && [ -z "\${STILLFAIL_NO_DRAIN:-\${EMBER_NO_DRAIN:-}}" ]; then
  # Restarted: once no turn runs, so none is cut off (at most 10 minutes; it takes no new ones meanwhile).
  rm -f "$cur/run/drained"
  step drain
  kill -USR1 "$pid"
  echo "${say("cloud.install.drain")}"
  for _ in $(seq 1 630); do
    { [ -f "$cur/run/drained" ] || ! kill -0 "$pid" 2>/dev/null; } && break
    sleep 1
  done
fi

if [ -z "$handed" ]; then
step restart
# One running at a time: the old one stops before the new one takes its place (under either name).
if [ "$os" = Darwin ]; then
  for l in "$label" "$old_label"; do
    launchctl bootout "gui/$(id -u)/$l" 2>/dev/null || true
    # bootout returns before the service is gone; bootstrapping it again before then fails.
    for _ in 1 2 3 4 5 6 7 8 9 10; do launchctl print "gui/$(id -u)/$l" >/dev/null 2>&1 || break; sleep 1; done
  done
  rm -f "$old_plist"
else
  if user_systemd; then
    systemctl --user stop "$unit" 2>/dev/null || true
    if [ -f "$unit_dir/$old_unit" ]; then
      systemctl --user stop "$old_unit" 2>/dev/null || true
      systemctl --user disable "$old_unit" >/dev/null 2>&1 || true
      rm -f "$unit_dir/$old_unit"
      systemctl --user daemon-reload 2>/dev/null || true
    fi
  fi
  for f in "$cur/stillfail.pid" "$cur/ember.pid"; do
    [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null || true
    rm -f "$f"
  done
fi
move_data
[ -n "$swapped" ] || swap_app
rm -rf "$app.old"
prune_node
fi
mkdir -p "$HOME/.local/bin"
ln -sf "$app/bin/stillfail" "$HOME/.local/bin/stillfail"
ln -sf "$app/bin/stillfail" "$HOME/.local/bin/ember"

if [ -n "$token" ]; then
  echo "${say("cloud.install.join")}"
  "$app/bin/stillfail" station enroll "$origin" "$token"
fi

if [ -n "$handed" ]; then
  :
elif [ "$os" = Darwin ]; then
  mkdir -p "$(dirname "$plist")"
  cp "$tmp/service" "$plist"
  started=""
  for _ in 1 2 3 4 5; do
    launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null && { started=yes; break; }
    sleep 2
  done
  [ -n "$started" ] || { echo "${say("cloud.install.launchdFailed", { command: "launchctl bootstrap gui/$(id -u) ${plist}" })}" >&2; exit 1; }
else
  if user_systemd; then
    mkdir -p "$unit_dir"
    cp "$tmp/service" "$unit_dir/$unit"
    systemctl --user daemon-reload
    systemctl --user enable "$unit" >/dev/null 2>&1
    systemctl --user restart "$unit"
    # Also with no one logged in (a server): the user's services start with the machine.
    loginctl enable-linger "$(id -un)" 2>/dev/null || lingering="no"
  else
    nohup env PATH="$agent_path" STILLFAIL_DATA="$data" "$app/bin/stillfail" start >> "$data/stillfail.log" 2>&1 &
    echo $! > "$data/stillfail.pid"
    no_service="yes"
  fi
fi

echo
if [ "$handed" = yes ]; then
  echo "${say("cloud.install.updated")}"
else
  echo "${say("cloud.install.installed")}"
fi
echo "  ${say("cloud.install.where.app", { app: "${app}" })}"
echo "  ${say("cloud.install.where.data", { data: "$data" })}"
echo "  ${say("cloud.install.where.status")}"
[ "$os" = Linux ] && [ -z "\${no_service:-}" ] && echo "  ${say("cloud.install.where.service", { unit: "$unit" })}"
[ -n "\${lingering:-}" ] && echo "  ${say("cloud.install.where.linger", { user: "$(id -un)" })}"
[ -n "\${no_service:-}" ] && echo "  ${say("cloud.install.where.noService")}"
missing=""
command -v claude >/dev/null 2>&1 || missing="$missing Claude Code"
command -v codex >/dev/null 2>&1 || missing="$missing Codex"
if [ -n "$missing" ]; then
  echo
  echo "${say("cloud.install.agents.missing", { missing: "${missing}" })}"
  echo "  ${say("cloud.install.agents.claude")}"
  echo "  ${say("cloud.install.agents.codex")}"
  echo "${say("cloud.install.agents.signIn")}"
fi
}

if [ -z "$handed" ] && [ -n "$pid" ] && inside_station; then
  # Apart from the caller (a process group of its own, output to a file): it restarts once the caller's turn is over.
  mkdir -p "$cur/run"
  echo "${say("cloud.install.inside")}"
  echo "  ${say("cloud.install.insideLog", { log: "$data/run/update.log" })}"
  trap - EXIT
  set -m
  ( trap '' HUP; restart_and_finish; rm -rf "$tmp" ) > "$cur/run/update.log" 2>&1 < /dev/null &
  exit 0
fi
restart_and_finish
`;
