// The still.fail station's installer, served at /install.sh: `curl -fsSL <origin>/install.sh | sh -s -- <token>` on the
// machine that is to be a station. It gets the release for the machine (scripts/release.sh put it in the releases
// bucket, served at /releases/<file>), puts it in ~/.stillfail/app (the data around it stays), links `stillfail` into
// ~/.local/bin, joins the workspace the token is for (a station already in one
// stays in it and joins this one beside it, `enroll --stay`), and runs the station as
// a service of the user (launchd), started at login and again if it stops. Claude Code and Codex are the machine's own:
// it says how to get them when they are missing.
// On Linux the service is a systemd user service (lingering, so it runs with no one logged in); with no user systemd
// (a container, another init) the station is started in the background, and said not to come back after a reboot.
// Without a token, on a station already in a workspace, it updates the station (`stillfail update` runs it so). An update
// does not stop the agents when it can help it: with the service's definition unchanged, the running station hands
// over to the new release in its own process (SIGUSR2, the Rust station's main.rs), turns, runtimes and jobs going on;
// else, or if that fails, the station is first drained (SIGUSR1: it says when it may be stopped; the TS station at
// once, its turns handed over to the next start; the Rust one once no turn runs), then restarted. A station older than these says neither (no run/station.json): it is restarted as before.
// The service's PATH is the caller's (the agents are found on it), so it is not what makes a definition "changed": an
// update from another shell (an agent's, the station's own) would never hand over. Started from inside the station (an
// agent's turn, a job), a restart goes on in the background, apart from the caller: the drain waits for the caller's
// own turn to end, which does not end while it waits. A station already on this release is left as it is.

import { tr, type Lang } from "./i18n.ts";
import { PRODUCTS } from "../../client/i18n/brand.ts";

/**
 * The installer for a still.fail cloud at `origin`, getting the release of `channel` by default: the stable one, or the
 * test channel's (beta/, scripts/release.sh --beta). STILLFAIL_CHANNEL where it runs says otherwise.
 */
export function installScript(origin: string, channel: "stable" | "beta" = "stable", lang: Lang = "zh"): string {
  return script((key, args) => tr(lang, key, args)).replaceAll("__ORIGIN__", origin).replaceAll("__CHANNEL__", channel).replaceAll("__LANG__", lang).replace("__PRODUCTS__", () => productCases());
}

/** The installer's `case "$origin"` for each product other than still.fail (client/i18n/brand.ts): its id and reverse
 * domain, for a cloud on its domains or under them, a port or none. */
function productCases(): string {
  return PRODUCTS.map(({ zones, product }) => {
    const hosts = zones.flatMap((zone) => [`*://${zone}`, `*://${zone}:*`, `*://*.${zone}`, `*://*.${zone}:*`]);
    return `  ${hosts.join("|")}) product=${product.id} reverse=${product.reverse} ;;`;
  }).join("\n");
}

/**
 * The installer a release carries (bin/install.<lang>.sh, scripts/installers.ts), for the station that runs it to update
 * itself (station/src/updates/updates.ts): this one, its cloud the one the station names (STILLFAIL_ORIGIN).
 */
export const bundledInstallScript = (lang: Lang) => installScript("$STILLFAIL_ORIGIN", "stable", lang).replace('origin="$STILLFAIL_ORIGIN"', 'origin="${STILLFAIL_ORIGIN:?}"');

/**
 * A release's file, as the bucket keeps it: stillfail-station-<platform>.tar.gz. Windows' is a zip (install-windows.ts).
 */
export const RELEASE_FILE = /^(stillfail-station-(darwin-arm64|linux-x64|linux-arm64)\.tar\.gz|stillfail-station-win32-x64\.zip)$/;

/** The test channel's release (scripts/release.sh --beta), until promoted to the stable name. */
export const BETA_RELEASE_FILE = /^beta\/stillfail-station-((darwin-arm64|linux-x64|linux-arm64)\.tar\.gz|win32-x64\.zip)$/;

/**
 * The station's releases kept each under a name of its own (scripts/release-deltas.ts: the release before is what a
 * delta is made from, and the names above are put over each release), by channel, build and sha256; and the deltas to
 * each from the builds before it, which station.json and station-beta.json offer (station/src/updates/release.ts).
 */
export const STATION_ARCHIVE = /^station\/archive\/(stable|beta)\/[0-9]+-[0-9a-f]{64}-((darwin-arm64|linux-x64|linux-arm64)\.tar\.gz|win32-x64\.zip|(darwin-arm64|linux-x64|linux-arm64|win32-x64)\.from-[0-9]+-[0-9a-f]{16}\.delta)$/;

/**
 * The Node a release runs on (its NODE_VERSION file says the version), kept apart from it, once per version (scripts/node-dist.sh):
 * the installer gets it when the machine has none of that version yet, with its sha256 to check it by.
 */
export const NODE_FILE = /^node\/node-v[0-9]+\.[0-9]+\.[0-9]+-((darwin-arm64|linux-x64|linux-arm64)\.tar\.gz|win-x64\.zip)(\.sha256)?$/;

/**
 * The apps' builds, as scripts/release.sh puts them beside the station's: what each app's updater reads for the
 * latest (the desktop app's electron-updater), and the files it names.
 */
const APP_FILES: [RegExp, string][] = [
  // The site's film (on it 2026-10-28 to 10-29; a page built then still asks for it), too large for the site's own files.
  [/^site\/film-[a-z]+-[0-9]+\.mp4$/, "video/mp4"],
  // The station's latest release, for stations to say a newer one is out.
  [/^station\.json$/, "application/json"],
  // The test channel's (scripts/release.sh --beta): the station's latest, and the beta apps' (fail.still.desktop.beta,
  // fail.still.android.beta, apps of their own beside the released ones): the desktop one's feed (electron-updater's
  // channel stillfail-beta) and the Android one's, with the builds they name (stillfail-beta-…).
  [/^station-beta\.json$/, "application/json"],
  [/^desktop\/stillfail-beta-mac\.yml$/, "text/yaml; charset=utf-8"],
  [/^desktop\/stillfail-beta\.yml$/, "text/yaml; charset=utf-8"],
  [/^android\/beta\/latest\.json$/, "application/json"],
  [/^desktop\/stillfail-mac\.yml$/, "text/yaml; charset=utf-8"],
  [/^desktop\/(stillfail|monoid)-(beta-)?[0-9.]+-arm64-mac\.zip$/, "application/zip"],
  // The Mac app's own updater's feeds, stable and beta (it is mbui's, apps/mbui, in the Electron app's place:
  // scripts/release.sh desktop; an AppRelease naming the zip above, which stillfail(-beta)-mac.yml names too).
  [/^mac\/(beta\/)?latest\.json$/, "application/json"],
  // Its blockmap, for the updater to download only what changed since the zip it has (releases.ts).
  [/^desktop\/(stillfail|monoid)-(beta-)?[0-9.]+-arm64-mac\.zip\.blockmap$/, "application/octet-stream"],
  // The Windows app's: its feed for an installed Electron app's updater (electron-updater's, named by the channel
  // alone), its installer and, of the Electron app's own installers, their blockmaps.
  [/^desktop\/stillfail\.yml$/, "text/yaml; charset=utf-8"],
  [/^desktop\/(stillfail|monoid)-(beta-)?[0-9.]+-x64-win\.exe$/, "application/vnd.microsoft.portable-executable"],
  [/^desktop\/(stillfail|monoid)-(beta-)?[0-9.]+-x64-win\.exe\.blockmap$/, "application/octet-stream"],
  // Its signature (scripts/release-sign.ts), which the app checks before installing it (scripts/release-sign.ts).
  [/^desktop\/(stillfail|monoid)-(beta-)?[0-9.]+-x64-win\.exe\.sig$/, "application/json"],
  // Their deltas from the builds before (scripts/release-deltas.ts; the feeds below offer them), and the Windows
  // installer's raw form, what later releases' deltas are made from.
  [/^desktop\/(stillfail|monoid)-(beta-)?[0-9.]+-(arm64-mac\.zip|x64-win\.exe)\.from-[0-9]+\.delta$/, "application/octet-stream"],
  [/^desktop\/(stillfail|monoid)-(beta-)?[0-9.]+-x64-win\.exe\.raw\.zst$/, "application/zstd"],
  // It is mbui's (apps/mbui) in the Electron app's place (scripts/release.sh desktop-win): its own updater's feeds,
  // stable and beta (an AppRelease naming the installer above, its signed words in it), as the Mac's.
  [/^win\/(beta\/)?latest\.json$/, "application/json"],
  // The web app the beta Electron app took without a new app, until it was moved to mbui's (2026-10-26): its signed
  // feed and the archives it names.
  [/^desktop\/web\/stillfail-beta-web\.json$/, "application/json"],
  [/^desktop\/web\/stillfail-beta-web-[0-9.]+\.tar\.gz$/, "application/gzip"],
  [/^android\/latest\.json$/, "application/json"],
  // monoid's (release.sh --product monoid), in its own bucket: monoid(-beta)-<n>.apk.
  [/^android\/(stillfail|stillfail-beta|monoid|monoid-beta)-[0-9]+\.apk$/, "application/vnd.android.package-archive"],
  [/^android\/(stillfail|stillfail-beta|monoid|monoid-beta)-[0-9]+\.apk\.from-[0-9]+\.delta$/, "application/octet-stream"],
  // still.fail mbui (apps/mbui: the Android app in mbui, fail.still.mbui, a test app of its own; apps/mbui/scripts/beta.sh):
  // its feed and the builds it names.
  [/^android\/mbui\/latest\.json$/, "application/json"],
  [/^android\/stillfail-mbui-[0-9]+\.apk$/, "application/vnd.android.package-archive"],
  // and its macOS app (apps/mbui/scripts/mac-app.sh): the same kind of feed, the zips it names
  [/^mac\/mbui\/latest\.json$/, "application/json"],
  [/^mac\/stillfail-mbui-[0-9]+-arm64-mac\.zip$/, "application/zip"],
  // and its Windows app (apps/mbui/scripts/beta.sh win: its installer, signed; before 2026-10-26 the .exe with its DLLs
  // and core.hbc, zipped)
  [/^win\/mbui\/latest\.json$/, "application/json"],
  [/^win\/stillfail-mbui-[0-9]+-x64-win\.exe$/, "application/vnd.microsoft.portable-executable"],
  [/^win\/stillfail-mbui-[0-9]+-x64-win\.exe\.from-[0-9]+\.delta$/, "application/octet-stream"],
  [/^win\/stillfail-mbui-[0-9]+-x64-win\.exe\.raw\.zst$/, "application/zstd"],
  [/^win\/stillfail-mbui-[0-9]+-x64-win\.zip$/, "application/zip"],
  // and its Linux app (apps/mbui/scripts/beta.sh linux: the program with its engine, shell and core.hbc, and its installer),
  // each machine's builds a feed of their own (x64's linux/mbui, arm64's linux-arm64/mbui)
  [/^linux(-arm64)?\/mbui\/latest\.json$/, "application/json"],
  [/^linux\/stillfail-mbui-[0-9]+-(x64|arm64)-linux\.tar\.gz$/, "application/gzip"],
  [/^linux\/stillfail-mbui-[0-9]+-(x64|arm64)-linux\.tar\.gz\.from-[0-9]+\.delta$/, "application/octet-stream"],
  // The faces the apps offer beside the system's (scripts/fonts.py): a page's stylesheet and its woff2
  // slices, the Android app's gzipped files; each version in a folder of its own, never changed.
  [/^fonts\/[a-z][a-z0-9-]{0,31}\/[0-9.]+\/font\.css$/, "text/css; charset=utf-8"],
  [/^fonts\/[a-z][a-z0-9-]{0,31}\/[0-9.]+\/[a-z0-9-]+\.woff2$/, "font/woff2"],
  [/^fonts\/[a-z][a-z0-9-]{0,31}\/[0-9.]+\/[a-z0-9]+\.ttf\.gz$/, "application/gzip"],
  // and its preview: the characters of the fonts page alone, for the face to be shown before it is fetched.
  [/^fonts\/[a-z][a-z0-9-]{0,31}\/[0-9.]+\/preview-[0-9a-f]{8}\.ttf$/, "font/ttf"],
  // The iroh-relay still.fail's relays on machines of their own (Beijing's, Hong Kong's) run, built from the iroh the
  // station pins (.github/workflows/relay.yml), named by that commit; cloud/relay-update.sh puts it on a relay.
  [/^relay\/iroh-relay-[0-9a-f]{40}-linux-x64$/, "application/octet-stream"],
  // The DHT node beside it (same workflow), named by its source's tree; cloud/dht-node-update.sh puts it on a relay.
  [/^relay\/dht-node-[0-9a-f]{40}-linux-x64$/, "application/octet-stream"],
  // The native parts prebuilt on a development machine (scripts/native.ts prebuild: the mbui app's Windows shell and
  // engine), each named by the hash of what it is made of, for CI and the builds to fetch (native.ts never builds them
  // there).
  [/^natives\/[a-z][a-z0-9-]{0,31}-(darwin-arm64|linux-x64|linux-arm64|win32-x64|wasm32|android-arm64)-[0-9a-f]{24}\.tar\.gz$/, "application/gzip"],
];

/**
 * The files every cloud made of this code serves alike, its stations' and not its apps': the station's releases and
 * feeds, their Node, the faces, the prebuilt native parts and the relay. A cloud whose bucket holds its
 * own apps' builds alone (monoid's: RELEASES_UPSTREAM) reads these from still.fail's when it has none (releases.ts
 * upstreamRelease); never an app's feed or build, which would update its apps to another product's.
 */
export function sharedRelease(file: string): boolean {
  return RELEASE_FILE.test(file) || BETA_RELEASE_FILE.test(file) || STATION_ARCHIVE.test(file) || NODE_FILE.test(file) || /^station(-beta)?\.json$|^(fonts|natives|relay)\//.test(file);
}

/** The content type a file of the releases bucket is served with; null for a name that is not one of its files. */
export function releaseType(file: string): string | null {
  const archive = file.endsWith(".zip") ? "application/zip" : "application/gzip";
  if (RELEASE_FILE.test(file) || BETA_RELEASE_FILE.test(file)) return archive;
  if (STATION_ARCHIVE.test(file)) return file.endsWith(".delta") ? "application/octet-stream" : archive;
  if (NODE_FILE.test(file)) return file.endsWith(".sha256") ? "text/plain; charset=utf-8" : archive;
  return APP_FILES.find(([name]) => name.test(file))?.[1] ?? null;
}

// A variable is always braced where words follow it ("\${app}（…）"): sh may take the first byte of a non-ASCII
// character for part of its name, and set -u stops the script there.
// What it says is in the language it was asked for (?lang=, Accept-Language); `say` gives it, with what the shell puts
// in ($names, $(commands)) given as arguments.
const script = (say: (key: string, args?: Record<string, string>) => string) => `#!/bin/sh
# Installs the still.fail station on this machine and joins it to a workspace in still.fail cloud:
#   curl -fsSL __ORIGIN__/install.sh | sh -s -- <token> [<lock>] [rig:<person>]
# <lock>: the workspace lock's hash the station pins (a locked workspace's command gives it).
# rig:<person>: the machine joins as a rig (a station that only runs tasks), its person's own lock's hash pinned (a rig's command gives it).
# STILLFAIL_CHANNEL=beta gets the test channel's release (stable: the usual one); this copy defaults to __CHANNEL__.
# The token comes from 「添加 station」 in still.fail. Running it again updates it and keeps its data (~/.stillfail).
set -eu
origin="__ORIGIN__"
token="\${1:-}"
lock="\${2:-}"
rig="\${3:-}"
case "$lock" in rig:*) rig="$lock" lock="" ;; esac
# The product its cloud is (client/i18n/brand.ts): another product's station has a data directory, a command and a
# service of its own beside still.fail's on the same machine (monoid's: ~/.monoid, \`monoid\`, build.monoid.station).
product=stillfail reverse=fail.still
case "$origin" in
__PRODUCTS__
esac
# The data: $STILLFAIL_DATA, else ~/.stillfail.
data="\${STILLFAIL_DATA:-$HOME/.$product}"
cur="$data"
# Where the update is, for the station to show on its pages: download, handoff, drain,
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
# Windows' Linux (WSL): its PATH carries Windows' own directories (/mnt/c/…), whose programs are not the agents'; its
# systemd is off unless /etc/wsl.conf turns it on; and it runs only while Windows keeps it up (keep_wsl).
wsl=""
[ "$os" = Linux ] && grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null && wsl=yes
app="$data/app"
label="$reverse.station"
plist="$HOME/Library/LaunchAgents/$label.plist"
unit_dir="\${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
unit="$product-station.service"
# Whether this Linux has a systemd for the user to run services in (not a container's, not another init).
user_systemd() { command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; }
# WSL keeps a distribution up only while something of Windows' holds it (a terminal, a wsl.exe): with none, its
# services stop with it, and it does not start with Windows. So a wsl.exe that holds it, hidden, started at each
# Windows sign-in from the user's Startup folder ($keeper, a script for wscript) and now. Through WSL's interop
# (cmd.exe, wscript.exe on its PATH): none from a station's own update (no terminal of Windows' there; done before).
keeper_sleep=3153600000
keep_wsl() {
  [ -n "\${WSL_DISTRO_NAME:-}" ] && command -v wslpath >/dev/null 2>&1 && command -v cmd.exe >/dev/null 2>&1 || return 1
  appdata=$(cd / && cmd.exe /c "echo %APPDATA%" 2>/dev/null | tr -d '\\r')
  case "$appdata" in ?:\\\\*) ;; *) return 1 ;; esac
  startup="$(wslpath -u "$appdata")/Microsoft/Windows/Start Menu/Programs/Startup"
  [ -d "$startup" ] || return 1
  keeper="$startup/$product-station-$WSL_DISTRO_NAME.vbs"
  keeper_win=$(wslpath -w "$keeper")
  printf 'CreateObject("WScript.Shell").Run "wsl.exe -d ""%s"" --exec sleep %s", 0, False\\r\\n' "$WSL_DISTRO_NAME" "$keeper_sleep" > "$keeper" || return 1
  pgrep -fx "sleep $keeper_sleep" >/dev/null 2>&1 || (cd / && cmd.exe /c wscript.exe "$keeper_win" >/dev/null 2>&1) || return 1
}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

channel="\${STILLFAIL_CHANNEL:-__CHANNEL__}"
# (Said once: not again by the release's own installer, handed the download below.)
case "$channel" in
  beta) release="beta/stillfail-station-$platform.tar.gz"; [ -n "\${STILLFAIL_INSTALLER_HANDED:-}" ] || echo "${say("cloud.install.downloadBeta")}" ;;
  *) channel=stable; release="stillfail-station-$platform.tar.gz"; [ -n "\${STILLFAIL_INSTALLER_HANDED:-}" ] || echo "${say("cloud.install.download")}" ;;
esac
step download
sha256_of() { { shasum -a 256 "$1" 2>/dev/null || sha256sum "$1"; } | cut -d' ' -f1; }
# Handed a release already downloaded (by the installer of the release before, below, or by the station, which made it
# from a delta: station/src/updates/release.ts): taken, its directory removed.
case "\${STILLFAIL_ARCHIVE:-}" in
  */stillfail-handed.*/stillfail.tar.gz)
    mv "$STILLFAIL_ARCHIVE" "$tmp/stillfail.tar.gz"
    rm -rf "$(dirname "$STILLFAIL_ARCHIVE")" ;;
  *) curl -fL --progress-bar "$origin/releases/$release" -o "$tmp/stillfail.tar.gz" ;;
esac
# A station updating itself says what the release must hash to, as its signed words say (station/src/updates/signed.ts):
# anything else is not installed.
if [ -n "\${STILLFAIL_RELEASE_SHA256:-}" ] && [ "$(sha256_of "$tmp/stillfail.tar.gz")" != "$STILLFAIL_RELEASE_SHA256" ]; then
  echo "${say("cloud.install.release.mismatch")}" >&2
  exit 1
fi
# Gzipped or not (tar finds out as it reads): what a station made from a delta is the tar itself, under the same name,
# and STILLFAIL_RELEASE_SHA256 then that tar's. Only an installer from this one on is handed one: the station that made
# it runs the installer it carries, which hands it on to the new release's own, with the same hash.
tar -xf "$tmp/stillfail.tar.gz" -C "$tmp"
# The release checked so is installed by its own installer (bin/install.<lang>.sh in it, scripts/installers.ts): what
# it does from here (its service, its handover) is the new release's, as the cloud's newest installer did it before.
lang="\${STILLFAIL_INSTALL_LANG:-__LANG__}"
if [ -n "\${STILLFAIL_RELEASE_SHA256:-}" ] && [ -z "\${STILLFAIL_INSTALLER_HANDED:-}" ] && [ -f "$tmp/stillfail/bin/install.$lang.sh" ]; then
  keep=$(mktemp -d "\${TMPDIR:-/tmp}/stillfail-handed.XXXXXX")
  mv "$tmp/stillfail.tar.gz" "$keep/stillfail.tar.gz"
  cp "$tmp/stillfail/bin/install.$lang.sh" "$keep/install.sh"
  rm -rf "$tmp"
  trap - EXIT
  STILLFAIL_ARCHIVE="$keep/stillfail.tar.gz" STILLFAIL_INSTALLER_HANDED=1 exec sh "$keep/install.sh" "$@"
fi
# Which channel the release came from, for the station.
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
    # This install's own (the station's update and one asked for can run at once), not one of the v* the next one prunes.
    part="$cur/node/.part-v$node_version.$$"
    rm -rf "$part"
    mkdir -p "$part/bin"
    own=$(command -v node 2>/dev/null || true)
    # With the signed hash of the Node binary (STILLFAIL_NODE_SHA256), the machine's own only when it is that very one.
    if [ -n "$own" ] && [ "$("$own" -v 2>/dev/null)" = "v$node_version" ] && { [ -z "\${STILLFAIL_NODE_SHA256:-}" ] || [ "$(sha256_of "$own")" = "$STILLFAIL_NODE_SHA256" ]; }; then
      cp "$own" "$part/bin/node"
    elif [ -n "\${STILLFAIL_NODE_SHA256:-}" ]; then
      node_file="node-v$node_version-$platform.tar.gz"
      echo "${say("cloud.install.node.download", { version: "${node_version}" })}"
      if ! curl -fL --progress-bar "$origin/releases/node/$node_file" -o "$tmp/$node_file"; then
        echo "${say("cloud.install.node.failed", { version: "${node_version}", origin: "${origin}" })}" >&2
        exit 1
      fi
      tar -xzf "$tmp/$node_file" -C "$part"
      if [ "$(sha256_of "$part/bin/node")" != "$STILLFAIL_NODE_SHA256" ]; then
        rm -rf "$part"
        echo "${say("cloud.install.node.mismatch", { version: "${node_version}" })}" >&2
        exit 1
      fi
    else
      node_file="node-v$node_version-$platform.tar.gz"
      echo "${say("cloud.install.node.download", { version: "${node_version}" })}"
      if ! curl -fL --progress-bar "$origin/releases/node/$node_file" -o "$tmp/$node_file" || ! curl -fsSL "$origin/releases/node/$node_file.sha256" -o "$tmp/$node_file.sha256"; then
        echo "${say("cloud.install.node.failed", { version: "${node_version}", origin: "${origin}" })}" >&2
        exit 1
      fi
      want=$(cut -d' ' -f1 < "$tmp/$node_file.sha256")
      got=$(sha256_of "$tmp/$node_file")
      if [ -z "$want" ] || [ "$want" != "$got" ]; then
        echo "${say("cloud.install.node.mismatch", { version: "${node_version}" })}" >&2
        exit 1
      fi
      tar -xzf "$tmp/$node_file" -C "$part"
    fi
    "$part/bin/node" -v >/dev/null 2>&1 || { rm -rf "$part"; echo "${say("cloud.install.node.broken", { version: "${node_version}" })}" >&2; exit 1; }
    # Another install may have put the same one there meanwhile: the first one stays.
    if [ -x "$node_dir/bin/node" ]; then rm -rf "$part"; else rm -rf "$node_dir" && mv "$part" "$node_dir"; fi
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
# In WSL, none of Windows' (a Windows npm's \`claude\` there would run Windows' Node).
agent_path=$(printf '%s' "$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH:/usr/bin:/bin" | tr ':' '\n' | awk -v wsl="$wsl" 'NF && !(wsl && index($0, "/mnt/") == 1) && !seen[$0]++' | paste -sd: -)
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
    *stillfail-station*) ;;
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

# One install at a time: two at once (the station updating itself as CI's \`stillfail update\` ran, both to a release
# that could not start, 2026-11-04) each put aside the app the other had just put in, and the one whose handover failed
# put back the release that could not start. The next waits for the one before (its handover is over within 180 s),
# then finds what it left; one whose holder is gone is taken over, as is one held past 300 s.
lock_dir="$cur/run/install.lock"
mkdir -p "$cur/run"
waited=0
until mkdir "$lock_dir" 2>/dev/null; do
  holder=$(cat "$lock_dir/pid" 2>/dev/null || true)
  if { [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; } || [ "$waited" -ge 300 ]; then rm -rf "$lock_dir"; continue; fi
  sleep 1
  waited=$((waited + 1))
done
echo $$ > "$lock_dir/pid"
trap 'rm -rf "$tmp" "$lock_dir"' EXIT

# Already on this release, and running as its service would: nothing to do.
if [ -n "$pid" ] && [ -f "$app/VERSION" ] && cmp -s "$tmp/stillfail/VERSION" "$app/VERSION" && same_service; then
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

# Handed over without stopping: the new release goes where the old one was, and the running station execs it. Only a
# launcher that becomes the release's own as it hands over (\`renew\`, station/native/launcher/src/run.rs) is handed
# over to: one from before would run on, never changed, until the machine's next start; it is restarted once instead.
handed=""
if [ -n "$pid" ] && [ -n "$(said handoff)" ] && [ -n "$(said renew)" ] && same_service; then
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
if [ -z "$handed" ] && [ -n "$pid" ] && [ -n "$(said drain)" ] && [ -z "\${STILLFAIL_NO_DRAIN:-}" ]; then
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
# One running at a time: the old one stops before the new one takes its place.
if [ "$os" = Darwin ]; then
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  # bootout returns before the service is gone; bootstrapping it again before then fails.
  for _ in 1 2 3 4 5 6 7 8 9 10; do launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 || break; sleep 1; done
else
  if user_systemd; then
    systemctl --user stop "$unit" 2>/dev/null || true
  fi
  if [ -f "$cur/stillfail.pid" ]; then kill "$(cat "$cur/stillfail.pid")" 2>/dev/null || true; fi
  rm -f "$cur/stillfail.pid"
fi
[ -n "$swapped" ] || swap_app
rm -rf "$app.old"
prune_node
fi
mkdir -p "$HOME/.local/bin"
ln -sf "$app/bin/stillfail" "$HOME/.local/bin/$product"

if [ -n "$token" ]; then
  echo "${say("cloud.install.join")}"
  "$app/bin/stillfail" station enroll "$origin" "$token" --stay \${lock:+--lock "$lock"} \${rig:+--rig "\${rig#rig:}"}
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
if [ -n "$wsl" ] && [ -n "\${no_service:-}" ]; then
  echo "  ${say("cloud.install.where.wslSystemd")}"
elif [ -n "\${no_service:-}" ]; then
  echo "  ${say("cloud.install.where.noService")}"
elif [ -n "$wsl" ]; then
  # Said when it is set up, or could not be on a machine joining a workspace (an update leaves it as it was).
  if keep_wsl; then echo "  ${say("cloud.install.where.wslKept", { distro: "\${WSL_DISTRO_NAME}" })}"
  elif [ -n "$token" ]; then echo "  ${say("cloud.install.where.wslKeep", { distro: "\${WSL_DISTRO_NAME:-<distro>}" })}"; fi
fi
# The agents as the station will find them (its PATH).
missing=""
(PATH="$agent_path"; command -v claude) >/dev/null 2>&1 || missing="$missing Claude Code"
(PATH="$agent_path"; command -v codex) >/dev/null 2>&1 || missing="$missing Codex"
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
  # (the lock held on by what goes on, its pid in it)
  ( trap '' HUP; restart_and_finish; rm -rf "$tmp" "$lock_dir" ) > "$cur/run/update.log" 2>&1 < /dev/null &
  echo $! > "$lock_dir/pid"
  exit 0
fi
restart_and_finish
`;
