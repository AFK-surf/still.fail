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
  # Part by part.
  static=()
  # A reviewed stable release gets a fresh, pinned web artifact even when only its notes changed.
  if has '^docs/releases/'; then static+=(web-beta); fi
  # (the app's page, each of the web app's pages: the app and mbui's web host built into it, apps/mbui/scripts/web-app.sh)
  if has '^(web/|client/|rules/js/|apps/mbui/(src|mbui/src|mbui/web|assets)/|package\.json$|pnpm-lock\.yaml$|cloud/(deploy\.py|build-static\.ts|wrangler\.web-beta\.jsonc)$)' && [ ${#static[@]} = 0 ]; then static+=(web-beta); fi
  if has '^(web/|client/|rules/js/|package\.json$|pnpm-lock\.yaml$|cloud/(deploy\.py|build-static\.ts|wrangler\.admin\.jsonc)$)'; then static+=(admin); fi
  if has '^cloud/(src/preview\.ts|build-static\.ts|wrangler\.preview\.jsonc)$'; then static+=(preview); fi
  # The share host's page is the web's Markdown and visualizations, its words, the iroh it binds (client/), and its headers.
  if has '^(web/|client/|rules/js/|package\.json$|pnpm-lock\.yaml$|cloud/(src/share\.ts|share-hosts\.ts|build-static\.ts|wrangler\.share\.jsonc|wrangler\.jsonc|deploy\.py)$)'; then static+=(share); fi
  if has '^(web/src/site/|cloud/wrangler\.site-beta\.jsonc$)'; then static+=(site-beta); fi
  if has '^cloud/(status/|wrangler\.status\.jsonc$)'; then static+=(status); fi
  api=false
  if has_but '^cloud/(src/|wrangler\.jsonc$|package\.json$|deploy\.py$)' '^cloud/src/(relay|relay-worker|preview|share)\.ts$'; then api=true; fi
  # (and what cloud/src takes from outside cloud/: the lock's rules through the station's lock, the client's words and
  # limits; none of them deployed it, so a change to the rules alone reached no cloud, 2026-11-05)
  if has '^(rules/js/|station/src/cloud/lock\.ts$|client/(i18n/|limits\.ts$|core-ts/src/(picture-relay|lock-form)\.ts$))'; then api=true; fi
  relay=false
  if has '^cloud/(src/(relay|relay-worker|limits|auth)\.ts|Dockerfile|relay-entrypoint\.sh|wrangler\.relay\.jsonc)$'; then relay=true; fi
  station=false
  # The station in TypeScript, its native parts (vendor/: the mesh addon's iroh), the rules it checks the lock and
  # vaults by (rules/js), what it shares with the core (client/core-ts/src: scripts/plan-covers.ts finds which), the words it says, the installer it carries (cloud/src/install*.ts: scripts/installers.ts).
  if has '^(station/(src|native)/|rules/js/|client/core-ts/src/(shapes/(dsl|schema|model)|lock-form|whitespace|titles|chat-row|cache-policy|codex-quota|mediaFacts|digest|redact)\.ts$|station/(package\.json|pnpm-lock\.yaml)$|vendor/|client/i18n/|bin/|scripts/(release|station-bundle)\.sh$|scripts/(posthog-key|native|installers|release-sign)\.ts$|cloud/src/(install|install-windows|i18n)\.ts$)'; then station=true; fi
  # The modules' packages (scripts/module-bundle.ts): what one packs (its module.json says), or how they are packed
  # and signed: modules=….
  if [ "${PLAN_MODULES:-1}" = 1 ]; then eval "$(printf '%s\n' "$changed" | node scripts/module-bundle.ts plan)"; else modules=; fi
  # The beta Android app: mbui's in the Kotlin one's place (scripts/release.sh --beta android), released for a
  # change to what apps/mbui's beta is made of (scripts/beta.sh APP_SRC: its code, mbui's with its Android host's
  # Java, the client's, media's, vendor's), or to how it is released.
  android_beta=false
  if has '^(apps/mbui/(src|core|android|ios|engine)/|apps/mbui/mbui/(src|android)/|apps/mbui/(mbui/)?moon\.(mod|work)$|client/|rules/js/|station/src/updates/keys\.ts$|web/public/avatars/index\.json$|media/|vendor/|scripts/(release\.sh|native\.ts)$|\.github/release\.sh$|apps/mbui/scripts/(beta|android|android-core|core)\.sh$)'; then android_beta=true; fi
  # The beta Mac app: mbui's in the Electron one's place (scripts/release.sh --beta desktop), released, as the
  # Android one, for a change to what apps/mbui's Mac app is made of (its code, mbui's with its Mac host, the
  # client's, media's, vendor's) or to how it is built and released.
  mac_beta=false
  if has '^(apps/mbui/(src|core|engine)/|apps/mbui/mbui/src/|apps/mbui/(mbui/)?moon\.(mod|work)$|client/|rules/js/|station/src/updates/keys\.ts$|web/public/avatars/index\.json$|media/|vendor/|scripts/(release|mac-feeds)\.sh$|scripts/native\.ts$|\.github/(release-desktop\.sh|mac_signing\.py)$|apps/mbui/scripts/(beta|mac-app|mac|core)\.sh$|apps/mbui/scripts/mac-icon\.swift$)'; then mac_beta=true; fi
  # The beta Windows app: mbui's in the Electron one's place (scripts/release.sh --beta desktop-win), released, as
  # the Mac one, for a change to what apps/mbui's Windows app is made of (its code, mbui's with its Windows host,
  # its installer, the client's, media's, vendor's) or to how it is built and released.
  win_beta=false
  if has '^(apps/mbui/(src|core|engine|windows)/|apps/mbui/mbui/src/|apps/mbui/(mbui/)?moon\.(mod|work)$|client/|rules/js/|station/src/updates/keys\.ts$|web/public/avatars/index\.json$|media/|vendor/|scripts/(release|win-feeds)\.sh$|scripts/native\.ts$|apps/mbui/scripts/(win|core)\.sh$|apps/mbui/mbui/scripts/win\.sh$|apps/mbui/scripts/mac-icon\.swift$)'; then win_beta=true; fi
  # The mbui app's Windows shell and engine, prebuilt: fetched and the shell's tests run (windows-natives), for a
  # change to what they are made of.
  windows_natives=false
  if has '^(client/shell/|client/Cargo\.(toml|lock)$|vendor/|apps/mbui/engine/|scripts/native\.ts$)'; then windows_natives=true; fi
  # The mbui app's own tests (check-mbui, mbui-check.yml; main's run there on their own): for a change to it, or
  # to mbui (apps/mbui/mbui).
  mbui=false
  if has '^apps/mbui/' || has '^\.github/workflows/mbui-check\.yml$'; then mbui=true; fi
  # The web in Chrome (check-browser): for a change to the web or its browser tests (scripts/check.sh's browser
  # part says which exactly), or to the workflows (the job checks everything then). None, and its eight runners
  # are not started: each fetched pnpm's 280 MB store and did nothing, 2.2 GB of a push's 4 GB of the Actions
  # cache's downloads, whose account limit GitHub slows them by (mbui-only branches, login-flow-look 41162994216,
  # 2026-10-31).
  browser=false
  if [ "$range" = all ] || has '^(web/|test/browser/)' || has_but '^\.github/' '^\.github/workflows/(mbui-|preview\.yml$)'; then browser=true; fi
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
    echo "modules=$modules"
    echo "android_beta=$android_beta"
    echo "mac_beta=$mac_beta"
    echo "win_beta=$win_beta"
    echo "windows_natives=$windows_natives"
    echo "mbui=$mbui"
    echo "browser=$browser"
    echo "release_smoke=$release_smoke"
  }
}

if [ -z "${PLAN_SOURCE:-}" ]; then
  changed=$(cat)
  range=${range:-}
  decide
  print
fi
