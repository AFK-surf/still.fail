#!/bin/sh
# Puts the DHT node (cloud/dht-node) on one of still.fail's relays on machines of their own, run there as root, given
# the tree of cloud/dht-node it is built from (`git rev-parse <commit>:cloud/dht-node`; its build is in the releases
# bucket: .github/workflows/relay.yml). From a machine that can reach the relay:
#   ssh root@<relay-host> sh -s <tree> < cloud/dht-node-update.sh
# The relay's cloud firewall has to let UDP 6881 in. Put back as it was when the node does not stay up for 10 s.
set -eu
tree=${1:?the tree of cloud/dht-node}
url=${CLOUD:-https://app.still.fail}/releases/relay/dht-node-$tree-linux-x64
bin=/usr/local/bin/stillfail-dht-node
unit=/etc/systemd/system/stillfail-dht-node.service
part=$bin.part-$tree
got=""
for try in $(seq 1 30); do
  curl -fsS -C - --max-time 120 -o "$part" "$url" && { got=yes; break; }
  echo "fetching: $(stat -c %s "$part" 2>/dev/null || echo 0) bytes so far, going on" >&2
done
[ -n "$got" ] || { echo "could not fetch $url" >&2; exit 1; }
chmod 755 "$part"
[ -f "$bin" ] && cp -p "$bin" "$bin.before"
cat > "$unit" <<UNIT
[Unit]
Description=still.fail's Mainline DHT node
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$bin 6881
DynamicUser=yes
Restart=always
RestartSec=5
MemoryMax=256M

[Install]
WantedBy=multi-user.target
UNIT
rm -f "$bin" && mv "$part" "$bin"
systemctl daemon-reload
systemctl enable --now stillfail-dht-node
systemctl restart stillfail-dht-node
sleep 10
if systemctl is-active -q stillfail-dht-node; then
  echo "the DHT node $tree is up"; journalctl -u stillfail-dht-node --since -30s --no-pager | tail -1; exit 0
fi
echo "the DHT node $tree did not stay up" >&2
journalctl -u stillfail-dht-node -n 15 --no-pager >&2
if [ -f "$bin.before" ]; then rm -f "$bin" && cp -p "$bin.before" "$bin" && systemctl restart stillfail-dht-node; else systemctl disable --now stillfail-dht-node; fi
exit 1
