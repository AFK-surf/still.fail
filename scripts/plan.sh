#!/usr/bin/env bash
# Which parts a change deploys and which checks it runs (pipeline.yml's plan): the paths it changed on stdin, one a
# line; `range` (all: every file, as when there is no deployed/beta) and GITHUB_REF, GITHUB_EVENT_NAME from the
# environment. Prints key=value lines (GITHUB_OUTPUT's). scripts/plan-covers.ts checks, path by path, that every file a
# deployed part is built from deploys it (sourced with PLAN_SOURCE=1: `decide` for `changed`, one path).
set -eu

# Whether a changed path matches $1 (and, has_but, not $2). One path (plan-covers.ts asks of thousands one at a time)
# is matched in the shell, many with grep.
has() {
  if [[ $changed != *$'\n'* ]]; then [[ $changed =~ $1 ]]; else printf '%s\n' "$changed" | grep -qE "$1"; fi
}
has_but() {
  if [[ $changed != *$'\n'* ]]; then [[ $changed =~ $1 ]] && ! [[ $changed =~ $2 ]]; else printf '%s\n' "$changed" | grep -E "$1" | grep -qvE "$2"; fi
}

decide() {
  # The agents' rules (AGENTS.md, CLAUDE.md) are built into nothing, and kept true by small changes of their own: one
  # deploys and releases nothing (client/core-ts/AGENTS.md alone put out the web, the admin and three apps' betas, by
  # its directory). scripts/plan-covers.ts holds it.
  # (the right side reads the caller's `changed`: it is expanded before the local one is made)
  local changed="$(printf '%s\n' "$changed" | grep -vE '(^|/)(AGENTS|CLAUDE)\.md$' || true)"
  # Part by part.
  static=()
  # A reviewed stable release gets a fresh, pinned web artifact even when only its notes changed.
  if has '^docs/releases/'; then static+=(web-beta); fi
  # (the app's page, each of the web app's pages: the app and mbui's web host built into it, apps/mbui/scripts/web-app.sh;
  # the Worker that serves them, cloud/src/web.ts)
  if has '^(web/|client/|rules/js/|apps/mbui/(src|assets)/|libs/mbui/(src|web)/|package\.json$|pnpm-lock\.yaml$|cloud/(deploy\.py|build-static\.ts|wrangler\.web-beta\.jsonc|src/(web|compat)\.ts)$|apps/mbui/scripts/web-app\.sh$)' && [ ${#static[@]} = 0 ]; then static+=(web-beta); fi
  if has '^(web/|client/|rules/js/|package\.json$|pnpm-lock\.yaml$|cloud/(deploy\.py|build-static\.ts|wrangler\.admin\.jsonc)$)'; then static+=(admin); fi
  if has '^cloud/(src/preview\.ts|build-static\.ts|wrangler\.preview\.jsonc)$'; then static+=(preview); fi
  # (the official site, website/, with the legal pages it serves from web/public)
  if has '^(website/|web/public/((en/)?(terms|privacy|trademark)\.html|legal\.css|favicon-beta\.svg|favicon-beta-32\.png|apple-touch-icon-beta\.png)$|cloud/wrangler\.site-beta\.jsonc$)'; then static+=(site-beta); fi
  if has '^cloud/(status/|wrangler\.status\.jsonc$)'; then static+=(status); fi
  api=false
  if has_but '^cloud/(src/|wrangler\.jsonc$|package\.json$|deploy\.py$)' '^cloud/src/(relay|relay-worker|preview)\.ts$'; then api=true; fi
  # (and what cloud/src takes from outside cloud/: the lock's rules through the station's lock, how the station keeps
  # a lock's forks, the client's words and limits; none of them deployed it, so a change to the rules alone reached no
  # cloud, 2026-11-05)
  if has '^(rules/js/|station/src/cloud/(lock|log-keep)\.ts$|client/(i18n/|limits\.ts$|core-ts/src/(picture-relay|lock-form)\.ts$))'; then api=true; fi
  relay=false
  if has '^cloud/(src/(relay|relay-worker|limits|auth)\.ts|Dockerfile|relay-entrypoint\.sh|wrangler\.relay\.jsonc)$'; then relay=true; fi
  station=false
  # The station in TypeScript, its native parts (vendor/: the mesh addon's iroh), its programs in MoonBit (station/mb: the
  # shell they link, client/shell, and mbui's effect), the rules it checks the lock and
  # vaults by (rules/js), what it shares with the core (client/core-ts/src: scripts/plan-covers.ts finds which), the words it says, the installer it carries (cloud/src/install*.ts: scripts/installers.ts), its deltas (scripts/delta.ts, release-deltas.ts).
  if has '^(station/(src|native|mb)/|client/shell/|libs/mbui/src/effect/|rules/js/|client/core-ts/src/(shapes/(dsl|schema|model)|lock-form|rig-form|whitespace|titles|chat-row|cache-policy|codex-quota|mediaFacts|digest|redact)\.ts$|station/(package\.json|pnpm-lock\.yaml)$|vendor/|client/i18n/|bin/|scripts/(release|station-bundle)\.sh$|scripts/(posthog-key|native|installers|release-sign|delta|release-deltas)\.ts$|cloud/src/(install|install-windows|i18n)\.ts$)'; then station=true; fi
  # The beta Android app: mbui's in the Kotlin one's place (scripts/release.sh --beta android), released for a
  # change to what apps/mbui's beta is made of (scripts/beta.sh APP_SRC: its code, mbui's with its Android host's
  # Java, JZlib among it, the client's, media's, vendor's), to the tool that packs and repacks its APK (mbui's
  # tools/apk: the repacked APK is what the app's delta applier makes byte for byte), or to how it is released (its
  # deltas too).
  android_beta=false
  if has '^(apps/mbui/(src|core|android|ios|engine)/|libs/mbui/(src|android)/|(apps|libs)/mbui/moon\.(mod|work)$|client/|rules/js/|station/src/(updates/keys|api/moved-from)\.ts$|web/public/avatars/index\.json$|media/|vendor/|libs/mbui/tools/apk/|scripts/(release\.sh|native\.ts|delta\.ts|release-deltas\.ts)$|\.github/release\.sh$|apps/mbui/scripts/(beta|android|android-core|core)\.sh$)'; then android_beta=true; fi
  # The beta Mac app: mbui's in the Electron one's place (scripts/release.sh --beta desktop), released, as the
  # Android one, for a change to what apps/mbui's Mac app is made of (its code, mbui's with its Mac host, the
  # client's, media's, vendor's) or to how it is built and released.
  mac_beta=false
  if has '^(apps/mbui/(src|core|engine)/|libs/mbui/src/|(apps|libs)/mbui/moon\.(mod|work)$|client/|rules/js/|station/src/(updates/keys|api/moved-from)\.ts$|web/public/avatars/index\.json$|media/|vendor/|scripts/(release|mac-feeds)\.sh$|scripts/(native|delta|release-deltas)\.ts$|\.github/(release-desktop\.sh|mac_signing\.py)$|apps/mbui/scripts/(beta|mac-app|mac|core)\.sh$|apps/mbui/scripts/mac-icon\.swift$)'; then mac_beta=true; fi
  # The beta Windows app: mbui's in the Electron one's place (scripts/release.sh --beta desktop-win), released, as
  # the Mac one, for a change to what apps/mbui's Windows app is made of (its code, mbui's with its Windows host,
  # its installer, the client's, media's, vendor's) or to how it is built and released.
  win_beta=false
  if has '^(apps/mbui/(src|core|engine|windows)/|libs/mbui/src/|(apps|libs)/mbui/moon\.(mod|work)$|client/|rules/js/|station/src/(updates/keys|api/moved-from)\.ts$|web/public/avatars/index\.json$|media/|vendor/|scripts/(release|win-feeds)\.sh$|scripts/(native|delta|release-deltas|release-sign)\.ts$|apps/mbui/scripts/(win|core)\.sh$|libs/mbui/scripts/win\.sh$|apps/mbui/scripts/mac-icon\.swift$)'; then win_beta=true; fi
  # The mbui app's Windows shell and engine, prebuilt: fetched and the shell's tests run (windows-natives), for a
  # change to what they are made of.
  windows_natives=false
  if has '^(client/shell/|client/Cargo\.(toml|lock)$|vendor/|apps/mbui/engine/|scripts/native\.ts$)'; then windows_natives=true; fi
  # The component library's page (apps/mbui/scripts/kit-web.sh, monoid's alone: cloud/wrangler.kit.jsonc), built by
  # mbui-web and deployed by monoid-kit, for a change to what it is made of (the app's code and mbui's, mbui's web host)
  # or to how it is built and served.
  kit=false
  if has '^(apps/mbui/(src|assets)/|libs/mbui/(src|web)/|(apps|libs)/mbui/moon\.(mod|work)$|apps/mbui/scripts/(kit-web\.sh|kit\.html|web\.sh|env\.sh|mbui\.sh|assets)$|libs/mbui/scripts/(web|env)\.sh$|apps/mbui/tools/assets/|cloud/(deploy\.py|wrangler\.kit\.jsonc)$)'; then kit=true; fi
  # The mbui app's own tests (check-mbui, mbui-check.yml; main's run there on their own): for a change to it, or
  # to mbui (libs/mbui).
  mbui=false
  if has '^(apps|libs)/mbui/' || has '^\.github/workflows/mbui-check\.yml$'; then mbui=true; fi
  # The station's tests (check-station: scripts/check.sh's station-tests, in slices on Linux runners): for a change to
  # what they read, as check.sh says it (its station_paths, read from there: said once), to the check itself, or to
  # CI's own files (which make every check run whole: pipeline.yml).
  station_tests=false
  station_paths=$(sed -n "s/^ *station_paths='\(.*\)'\$/\1/p" "$(dirname "${BASH_SOURCE[0]}")/check.sh")
  [ -n "$station_paths" ] || { echo "scripts/plan.sh: no station_paths in scripts/check.sh" >&2; exit 1; }
  if has "$station_paths" || has '^scripts/check\.sh$' || has_but '^\.github/' '^\.github/workflows/(mbui-|preview\.yml$)'; then station_tests=true; fi
  # The core's tests (check-core: scripts/check.sh's core-tests, in slices on Linux runners): for a change to what
  # they read, as check.sh says it (its core_test_paths, read from there), to the check itself, or to CI's own files.
  core_tests=false
  core_test_paths=$(sed -n "s/^ *core_test_paths='\(.*\)'\$/\1/p" "$(dirname "${BASH_SOURCE[0]}")/check.sh")
  [ -n "$core_test_paths" ] || { echo "scripts/plan.sh: no core_test_paths in scripts/check.sh" >&2; exit 1; }
  if has "$core_test_paths" || has '^scripts/check\.sh$' || has_but '^\.github/' '^\.github/workflows/(mbui-|preview\.yml$)'; then core_tests=true; fi
  # Exercise the GitHub-hosted web and Mac release paths, without secrets or publishing, when their CI changes.
  release_smoke=false
  if [ "${GITHUB_REF:-}" != refs/heads/main ] && { [ "${GITHUB_EVENT_NAME:-}" = workflow_dispatch ] || has '^(\.github/workflows/pipeline\.yml$|\.github/deploy\.sh$|\.github/actions/(setup|natives|mbui-moonbit)/|scripts/release\.sh$)'; }; then release_smoke=true; fi
}

print() {
  {
    echo "range=$range"
    echo "parts=${static[*]}"
    echo "static=$([ ${#static[@]} -gt 0 ] && echo true || echo false)"
    echo "api=$api"
    echo "relay=$relay"
    echo "station=$station"
    echo "android_beta=$android_beta"
    echo "mac_beta=$mac_beta"
    echo "win_beta=$win_beta"
    echo "windows_natives=$windows_natives"
    echo "kit=$kit"
    echo "mbui=$mbui"
    echo "station_tests=$station_tests"
    echo "core_tests=$core_tests"
    echo "release_smoke=$release_smoke"
  }
}

if [ -z "${PLAN_SOURCE:-}" ]; then
  changed=$(cat)
  range=${range:-}
  decide
  print
fi
