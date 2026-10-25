#!/bin/bash
# CI only. Read-only ASC identity/duplicate preflight; Apple altool alone performs upload.
# Sourced by testflight.sh so no JWT/key is written to Actions outputs.
asc_token() {
  local now header payload data sig r s
  now=$(date +%s)
  header=$(jq -cn --arg kid "$ASC_KEY_ID" '{alg:"ES256",kid:$kid,typ:"JWT"}' | b64url)
  payload=$(jq -cn --arg iss "$ASC_ISSUER_ID" --argjson now "$now" '{iss:$iss,iat:$now,exp:($now+600),aud:"appstoreconnect-v1"}' | b64url)
  data=$header.$payload
  printf %s "$data" | openssl dgst -sha256 -sign "$API_PRIVATE_KEYS_DIR/AuthKey_$ASC_KEY_ID.p8" -out "$T/signature.der"
  # OpenSSL emits DER ECDSA; JWT requires two unsigned, 32-byte integers.
  r=$(openssl asn1parse -inform DER -in "$T/signature.der" | awk '/INTEGER/{sub(/.*:/, ""); print; exit}')
  s=$(openssl asn1parse -inform DER -in "$T/signature.der" | awk '/INTEGER/{sub(/.*:/, ""); n++; if(n==2) print}')
  [[ $r =~ ^[0-9A-Fa-f]{1,64}$ && $s =~ ^[0-9A-Fa-f]{1,64}$ ]] || fail 'invalid ES256 signature'
  sig=$(printf '%064s%064s' "$r" "$s" | tr ' ' 0 | xxd -r -p | b64url)
  ASC_TOKEN=$data.$sig
}
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
asc_get() {
  curl --fail --silent --show-error --globoff --max-time 60 \
    -H "Authorization: Bearer $ASC_TOKEN" "https://api.appstoreconnect.apple.com/v1/$1"
}
asc_preflight() {
  asc_token
  asc_get 'apps/6818750243' > "$T/app.json"
  jq -e '.data.type == "apps" and .data.id == "6818750243" and .data.attributes.bundleId == "fail.still.iphone"' "$T/app.json" >/dev/null || fail 'ASC app/bundle mismatch'
  asc_get "builds?filter[app]=6818750243&filter[version]=$RELEASE_BUILD&limit=200" > "$T/builds.json"
  jq -e '.data | type == "array"' "$T/builds.json" >/dev/null || fail 'invalid ASC builds response'
  # Reject reused numbers across marketing versions, including expired builds. No delete/expire calls.
  jq -e '(.data | length) == 0 and (.links.next == null)' "$T/builds.json" >/dev/null || fail 'build number already exists or result is incomplete; choose a fresh number'
}
