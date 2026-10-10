#!/bin/sh
# Lays out the still.fail station's release in DIR/stillfail for PLATFORM (default darwin-arm64): the station in
# TypeScript (station/, docs/station-ts.md) with its native parts, prebuilt (scripts/native.ts: launcher, mesh, runner),
# and the version of the Node it runs on, which is not in it: the installer gets that once per version
# (scripts/node-dist.sh, cloud/src/install.ts) and links it at stillfail/node; the desktop app runs it on Electron's. scripts/release.sh packs it for install.sh; the desktop app (apps/desktop/build.sh) carries
# it and runs it itself. The layout:
#   stillfail/bin/stillfail                               (the command people and services run; bin/ember beside it)
#   stillfail/mesh/target/release/stillfail-station       (the launcher, with the Rust station's command line and path,
#                                                          ember-station beside it: what the installer, bin/stillfail,
#                                                          the desktop app and services written by older releases run)
#   stillfail/station/{main.js, read/worker.js, skills/, mesh.node, stillfail-runner, package.json}
#   stillfail/NODE_VERSION                                (the version of the Node it runs on: .node-version's)
#   stillfail/dist/admin/posthog.json                     (only the PostHog key the station reports errors with, when
#                                                          $STILLFAIL_POSTHOG names one: scripts/posthog-key.ts; the
#                                                          station finds its release as dist/admin's parent's parent)
#   stillfail/VERSION, BUILD                              (the commit; the commits in its history: version 0.1.<BUILD>)
# On darwin-arm64 the native parts are signed when $STILLFAIL_SIGN_STATION is set (the station release job).
# Its Node is the station's own: the agents' PATH never has it (a runtime installed with it would land there).
# On win32-x64 the executables are .exe, and the command is bin/stillfail.cmd (bin/stillfail.ps1 behind it): no links
# there (they take a privilege on Windows), so no ember beside them.
#   station-bundle.sh DIR [darwin-arm64|linux-x64|linux-arm64|win32-x64]
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: station-bundle.sh DIR [PLATFORM]}
platform=${2:-darwin-arm64}
case "$platform" in
  darwin-arm64|linux-x64|linux-arm64|win32-x64) ;;
  *) echo "no such platform: $platform" >&2; exit 1 ;;
esac
# Written afresh here, so a release never carries what an older build left in dist/admin (its page), nor an old key.
node "$root/scripts/posthog-key.ts" >&2
native() { node "$root/scripts/native.ts" file "$1" "$platform"; }
x=; [ "$platform" = win32-x64 ] && x=.exe
launcher="$(native launcher)"
mesh="$(native mesh)"
runner="$(native runner)"
(cd "$root/station" && pnpm run build >&2)
app="$out/stillfail"
rm -rf "$app"
mkdir -p "$app/bin" "$app/mesh/target/release" "$app/dist" "$app/station/read"
if [ "$platform" = win32-x64 ]; then
  cp "$root/bin/stillfail.cmd" "$root/bin/stillfail.ps1" "$app/bin/"
else
  cp "$root/bin/stillfail" "$app/bin/"
  ln -s stillfail "$app/bin/ember"
fi
cp -R "$root/dist/admin" "$app/dist/admin"
cp "$launcher" "$app/mesh/target/release/stillfail-station$x"
# And on Windows the launcher with no window beside it (what install.ps1's scheduled task runs; scripts/native.ts keeps
# it in the launcher's artifact).
[ "$platform" = win32-x64 ] && cp "$(dirname "$launcher")/stillfail-station-w.exe" "$app/mesh/target/release/"
cp "$mesh" "$runner" "$app/station/"
# macOS asks "find devices on local networks?" (the mesh's mDNS) for the launcher: Node and everything it starts are
# its. Ad hoc, the grant was its hash's: each new launcher asked again, and every Node it started while unanswered put
# up one more. The station release job signs the native parts ($STILLFAIL_SIGN_STATION: .github/sign-station.sh), so
# a grant stays. Not signed is a warning, not a release missed: they are put again as they were (ad hoc), which works.
if [ "$platform" = darwin-arm64 ] && [ -n "${STILLFAIL_SIGN_STATION:-}" ]; then
  sh "$root/.github/sign-station.sh" "$app/mesh/target/release/stillfail-station" fail.still.station \
    "$app/station/$(basename "$runner")" fail.still.runner "$app/station/$(basename "$mesh")" fail.still.mesh >&2 ||
    { echo "::warning::the station's native parts were not signed (.github/sign-station.sh): ad hoc" >&2
      cp "$launcher" "$app/mesh/target/release/stillfail-station"; cp "$mesh" "$runner" "$app/station/"; }
fi
[ "$platform" = win32-x64 ] || ln -s stillfail-station "$app/mesh/target/release/ember-station"
cp "$root/station/dist/main.js" "$app/station/"
cp "$root/station/dist/read/worker.js" "$app/station/read/"
cp -R "$root/station/dist/skills" "$app/station/skills"
# The bundle is an ES module: said, so Node neither guesses nor takes the type of a package.json above the release
# (the desktop app built in apps/desktop has one: every command warned).
printf '{"type":"module"}\n' > "$app/station/package.json"
# The Node it runs on, every release, CI and the desktop app's Electron alike (.node-version): what the tests ran on.
cp "$root/.node-version" "$app/NODE_VERSION"
git -C "$root" rev-parse HEAD > "$app/VERSION"
git -C "$root" rev-list --count HEAD > "$app/BUILD"
