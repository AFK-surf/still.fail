#!/bin/sh
# cloud/deploy.py in CI (.github/workflows/pipeline.yml): its deploy directory made for this run from the
# environment's secrets (removed after), the builds kept for promote-web in mini1's ~/stillfail-deploy/builds,
# and a dropped connection ("fetch failed") tried again, up to three times.
#   sh .github/deploy.sh [--dry-run] PART…
# The secrets, each a file's content (none of them needed for --dry-run): CLOUDFLARE_API_TOKEN (without it, the
# machine's own `wrangler login`), DEPLOY_KEYS_JSON (keys.json), GOOGLE_OAUTH_JSON (google-oauth.json), AXIOM_JSON,
# VAPID_JSON, FCM_SERVICE_ACCOUNT_JSON, POSTHOG_JSON, APPLE_JSON (apple.json, Sign in with Apple), REVIEW_ACCOUNTS_JSON
# (review-accounts.json, App Store review's password sign-in).
set -eu
cd "$(dirname "$0")/.."
pnpm install --frozen-lockfile --prefer-offline > /dev/null
(cd cloud && pnpm install --frozen-lockfile --prefer-offline > /dev/null)

dir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/stillfail-deploy.XXXXXX")
trap 'rm -rf "$dir"' EXIT
umask 077
put() { if [ -n "$2" ]; then printf '%s' "$2" > "$dir/$1"; fi; }
put keys.json "${DEPLOY_KEYS_JSON:-}"
put google-oauth.json "${GOOGLE_OAUTH_JSON:-}"
put axiom.json "${AXIOM_JSON:-}"
put vapid.json "${VAPID_JSON:-}"
put fcm-service-account.json "${FCM_SERVICE_ACCOUNT_JSON:-}"
put posthog.json "${POSTHOG_JSON:-}"
put apple.json "${APPLE_JSON:-}"
put review-accounts.json "${REVIEW_ACCOUNTS_JSON:-}"
umask 022
mkdir -p "$HOME/stillfail-deploy/builds"
ln -s "$HOME/stillfail-deploy/builds" "$dir/builds"
# The API without keys.json would make new ones: everyone logged out, every station's grant distrusted.
case " $* " in *" --dry-run "*) ;; *" api "*) [ -s "$dir/keys.json" ] || { echo "DEPLOY_KEYS_JSON is not set: not deploying the API"; exit 1; } ;; esac
[ -n "${CLOUDFLARE_API_TOKEN:-}" ] || unset CLOUDFLARE_API_TOKEN
export STILLFAIL_DEPLOY_DIR="$dir"

for try in 1 2 3; do
  (cd cloud && python3 deploy.py "$@") > "$dir/out.txt" 2>&1 && break
  if [ $try = 3 ] || ! grep -q "fetch failed" "$dir/out.txt"; then tail -60 "$dir/out.txt"; exit 1; fi
  echo "network dropped (try $try), trying again"; sleep 10
done
grep -E "^(deploying|deployed|bundling|bundled|kept|check|note|promoting)" "$dir/out.txt" || true
