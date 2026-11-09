#!/bin/sh
# Tells each still.fail cloud that reads the releases bucket that a release is out (POST /v1/releases/out, believed by
# the OIDC token GitHub gives this workflow run): every device and station connected to it reads its feed again then,
# never on a timer (cloud/src/status.ts receiveReleased). A cloud not reached only means its stations and apps learn of
# it at their next start or at the next release.
#   release-told.sh <origin>…
set -u
[ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] || { echo "no OIDC token for this job (permissions: id-token: write)" >&2; exit 0; }
for origin in "$@"; do
  token=$(curl -fsS -H "authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=$origin" | jq -r .value) || token=""
  if [ -n "$token" ] && curl -fsS --retry 3 -X POST -H "authorization: Bearer $token" "$origin/v1/releases/out" > /dev/null; then
    echo "$origin told"
  else
    echo "$origin not told" >&2
  fi
done
