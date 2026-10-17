#!/bin/bash
# What up.sh runs on: the dev cloud's sites (build:cloud) and its dependencies, the TS station (station/dist) and the
# native parts it takes (prebuilt, scripts/native.ts). On studio, in a checkout of this repository (a station_task
# mirror is fine: it has no .git, so one is made for scripts/native.ts, which keys the prebuilt parts by blob hashes).
# Each part is built only when it is not there; FORCE=1 builds all again. Rebuilding the cloud's sites ends a dev cloud
# running from this checkout (cloud/test/dev.ts exits): up.sh again after.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
cd "$ROOT"
[ -d .git ] || { git init -q && git add -A && git -c user.email=devenv@local -c user.name=devenv commit -qm mirror --no-verify; }
[ -d node_modules ] && [ -z "${FORCE:-}" ] || pnpm install --frozen-lockfile --prefer-offline
if [ -n "${FORCE:-}" ] || [ ! -f dist/cloud-web/index.html ]; then pnpm run build:cloud; fi
[ -d cloud/node_modules ] && [ -z "${FORCE:-}" ] || (cd cloud && pnpm install --frozen-lockfile --prefer-offline)
[ -d station/node_modules ] && [ -z "${FORCE:-}" ] || (cd station && pnpm install --frozen-lockfile --prefer-offline)
if [ -n "${FORCE:-}" ] || [ ! -f station/dist/main.js ]; then (cd station && pnpm run build); fi
for part in launcher mesh runner; do node scripts/native.ts file $part > /dev/null; done
echo "built: cloud sites, station, native parts"
