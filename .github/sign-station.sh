#!/bin/sh
# Signs the station's native parts (scripts/station-bundle.sh, in the station release job: the launcher, the runner and
# the mesh addon) with the desktop app's identity, each under one identifier, so macOS keeps what it granted them
# across releases (the launcher's Local Network grant: an ad hoc one's was its hash's, each new one asked again). The
# identity is in the signing keychain .github/mac_signing.py puts on the user's search list, under the lock mini1's
# signing jobs share (setting the list under another job left electron-builder without the identity and this codesign
# with errSecInternalComponent, 86b06866).
#   sign-station.sh FILE IDENTIFIER [FILE IDENTIFIER]…
set -eu
[ $# -ge 2 ] && [ $(($# % 2)) = 0 ] || { echo "usage: sign-station.sh FILE IDENTIFIER [FILE IDENTIFIER]…" >&2; exit 2; }
[ -n "${MAC_SIGN_IDENTITY:-}" ] || exec python3 "$(dirname "$0")/mac_signing.py" run -- sh "$0" "$@"
while [ $# -gt 0 ]; do
  codesign --force --timestamp=none --sign "$MAC_SIGN_IDENTITY" --identifier "$2" "$1"
  codesign --verify --strict "$1"
  shift 2
done
