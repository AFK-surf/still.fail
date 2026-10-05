#!/bin/sh
# Lays out the client core for an app that embeds it on Node (an Electron main process, as Comma's desktop app does)
# in DIR/stillfail-core for PLATFORM (default darwin-arm64): client/core-ts's Node host bundled as one CommonJS file,
# the mesh addon it connects to stations with (prebuilt: scripts/native.ts), and typings for what the embedding app
# calls. Nothing is published here. How an app uses it: docs/core-ts.md, "Account providers and embedding".
#   stillfail-core/core-ts.js       (hosts/node.ts: `start`, `commaAccountProvider`, `stillfailAccountProvider`)
#   stillfail-core/core-ts.d.ts     (their types)
#   stillfail-core/mesh.node        (the addon; the app sets STILLFAIL_MESH_NATIVE to it before `start`)
#   stillfail-core/package.json     (name, version 0.1.<BUILD>, main)
#   stillfail-core/VERSION, BUILD   (the commit; the commits in its history)
#   core-bundle.sh DIR [darwin-arm64|linux-x64|linux-arm64]
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: core-bundle.sh DIR [PLATFORM]}
# DIR as the caller named it, from where they are: the steps below run elsewhere.
case "$out" in /*) ;; *) out="$(pwd)/$out" ;; esac
platform=${2:-darwin-arm64}
case "$platform" in
  darwin-arm64|linux-x64|linux-arm64) ;;
  *) echo "no such platform: $platform" >&2; exit 1 ;;
esac
mesh=$(node "$root/scripts/native.ts" file mesh "$platform")
(cd "$root/client/core-ts" && pnpm install --frozen-lockfile --silent >&2)
dir="$out/stillfail-core"
rm -rf "$dir"
mkdir -p "$dir"
# As the desktop app bundles it (apps/desktop/build.sh): the addon and ws's optional natives are not bundled.
(cd "$root/client/core-ts" && pnpm exec esbuild src/hosts/node.ts --bundle --platform=node --format=cjs --target=node22 --outfile="$dir/core-ts.js" \
  --external:electron --external:bufferutil --external:utf-8-validate --log-level=error)
cp "$mesh" "$dir/mesh.node"
build=$(git -C "$root" rev-list --count HEAD)
git -C "$root" rev-parse HEAD > "$dir/VERSION"
echo "$build" > "$dir/BUILD"
cat > "$dir/package.json" <<EOF
{
  "name": "@stillfail/core-node",
  "version": "0.1.$build",
  "private": true,
  "description": "The still.fail client core on Node, for apps that embed it (docs/core-ts.md)",
  "main": "core-ts.js",
  "types": "core-ts.d.ts",
  "os": ["${platform%%-*}"],
  "cpu": ["${platform#*-}"]
}
EOF
cat > "$dir/core-ts.d.ts" <<'EOF'
// The still.fail client core on Node: what an embedding app calls (client/core-ts/src/hosts/node.ts).
export type ClientId = number;
/** Each message the core has for a connected UI, as JSON. */
export type Listener = (client: ClientId, json: string) => void;
/** Who the accounts are with: still.fail cloud's (the default), or Comma's. Opaque to the app. */
export type AccountProviderFactory = { readonly __accountProvider: unique symbol };
export type CommaOptions = {
  /** Comma's backend origin, e.g. https://api.cue.surf (no trailing slash). */
  origin: string;
  /** The app's Comma session token now; rejects when the app is signed out. Never shown to a UI. */
  bearer: () => Promise<string>;
};
export declare function commaAccountProvider(options: CommaOptions): AccountProviderFactory;
export declare const stillfailAccountProvider: AccountProviderFactory;
export type CoreHandle = {
  /** A UI connected: its id, for `receive` and the listener. */
  connect(): ClientId;
  /** A UI's message (the core protocol, docs/client-core.md), as JSON. */
  receive(client: ClientId, json: string): void;
  disconnect(client: ClientId): void;
  close(): Promise<void>;
};
/**
 * A core keeping its data in `dataDir`. `cloudOrigin`: still.fail cloud's (its changelog and app updates are read
 * there); `channel`: "beta" for a beta app. Set STILLFAIL_MESH_NATIVE to this package's mesh.node first.
 */
export declare function start(dataDir: string, cloudOrigin: string, listener: Listener, channel?: string, options?: { account?: AccountProviderFactory }): CoreHandle;
EOF
echo "$dir"
