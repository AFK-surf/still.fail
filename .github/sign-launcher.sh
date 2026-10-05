#!/bin/sh
# Signs the station's launcher (scripts/station-bundle.sh, in the station release job) with the desktop app's
# certificate under one identifier, so macOS keeps its Local Network grant across releases (an ad hoc launcher's grant
# was its hash's: each new one asked again). The certificate from MACOS_SIGNING_CERTIFICATE_B64/_PASSWORD goes in a
# keychain of its own, in the user's search list only while signing: under the lock .github/release-desktop.py holds
# while its own is there, for the jobs beside each other on mini1 share the one search list (setting it under the
# other job left electron-builder without the identity and this codesign with errSecInternalComponent, 86b06866).
#   sign-launcher.sh FILE
set -eu
file=${1:?usage: sign-launcher.sh FILE}
root=$(cd "$(dirname "$0")/.." && pwd)
: "${MACOS_SIGNING_CERTIFICATE_B64:?}" "${MACOS_SIGNING_CERTIFICATE_PASSWORD:?}"
if [ -z "${STILLFAIL_SIGNING_LOCKED:-}" ]; then
  STILLFAIL_SIGNING_LOCKED=1 exec lockf "$HOME/.stillfail-mac-signing.lock" sh "$0" "$@"
fi
identity=$(node -p 'require(process.argv[1]).build.mac.identity' "$root/apps/desktop/package.json")
dir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/stillfail-signing.XXXXXX")
keychain="$dir/signing.keychain-db"
keypass=$(openssl rand -hex 32)
previous=$(security list-keychains -d user | tr -d '"')
trap 'security list-keychains -d user -s $previous; security delete-keychain "$keychain" 2>/dev/null; rm -rf "$dir"' EXIT
(umask 077 && printf '%s' "$MACOS_SIGNING_CERTIFICATE_B64" | base64 -d > "$dir/certificate.p12")
security create-keychain -p "$keypass" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keypass" "$keychain"
security import "$dir/certificate.p12" -k "$keychain" -P "$MACOS_SIGNING_CERTIFICATE_PASSWORD" -T /usr/bin/codesign > /dev/null
security set-key-partition-list -S apple-tool:,apple: -k "$keypass" "$keychain" > /dev/null
rm "$dir/certificate.p12"
security list-keychains -d user -s "$keychain" $previous
codesign --force --timestamp=none --sign "$identity" --keychain "$keychain" --identifier fail.still.station "$file"
codesign --verify --strict "$file"
