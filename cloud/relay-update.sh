#!/bin/sh
# Puts another iroh-relay on one of still.fail's relays on machines of their own (Beijing's, Hong Kong's), run there as
# root, given the zzj3720/iroh commit station/native/mesh/Cargo.toml pins (its build is in the releases bucket:
# .github/workflows/relay.yml). From Studio, the one machine that reaches them:
#   ssh root@39.105.157.122 sh -s <commit> < cloud/relay-update.sh
# It is fetched there, not copied over: from the home network the upload stalls, and Hong Kong gets ~25 KB/s from
# anywhere, so the download goes on from where it stopped. The relay is restarted on it only when nothing else has
# the file open (a fetch left running once made systemd fail "Text file busy" for 14 minutes, 2026-10-29), and put back
# as it was when its HTTPS does not answer within 20 s. A `udp_bind_addr` left in relay.toml from when stations could
# ask for the relay's UDP way (2026-10-29/30) is taken out: none asks any more.
set -eu
rev=${1:?the iroh commit}
url=${CLOUD:-https://app.still.fail}/releases/relay/iroh-relay-$rev-linux-x64
bin=/usr/local/bin/iroh-relay
conf=/etc/iroh-relay/relay.toml
part=$bin.part-$rev
got=""
for try in $(seq 1 30); do
  curl -fsS -C - --max-time 120 -o "$part" "$url" && { got=yes; break; }
  echo "fetching: $(stat -c %s "$part" 2>/dev/null || echo 0) bytes so far, going on" >&2
done
[ -n "$got" ] || { echo "could not fetch $url" >&2; exit 1; }
chmod 755 "$part"
"$part" --version
if fuser "$part" >/dev/null 2>&1; then echo "something still has $part open" >&2; exit 1; fi
cp -p "$bin" "$bin.before"
cp -p "$conf" "$conf.before"
if grep -q '^udp_bind_addr' "$conf"; then
  grep -v '^udp_bind_addr' "$conf.before" > "$conf"
fi
rm -f "$bin" && mv "$part" "$bin"
systemctl restart iroh-relay
for i in $(seq 1 10); do
  sleep 2
  if curl -fsSk -o /dev/null --max-time 4 https://127.0.0.1/; then
    echo "iroh-relay $rev is up"; journalctl -u iroh-relay --since -30s --no-pager | grep -m3 'serving'; exit 0
  fi
done
echo "iroh-relay $rev did not come up: putting the one before back" >&2
journalctl -u iroh-relay -n 15 --no-pager >&2
rm -f "$bin" && cp -p "$bin.before" "$bin"
cat "$conf.before" > "$conf"
systemctl restart iroh-relay
exit 1
