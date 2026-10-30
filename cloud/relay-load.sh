#!/bin/sh
# Sends this machine's relay's counters to still.fail cloud, for the admin's console (its 中继 page: src/relay-load.ts),
# run every minute by a systemd timer on the relays on machines of their own (Beijing's, Hong Kong's, Shenzhen's). still.fail cloud
# believes it as the relay whose address it comes from. /etc/iroh-relay/load.env says which relay this is:
#   RELAY_URL=https://39.105.157.122
#   CLOUD=https://app.still.fail   (optional)
# Installing it (as root):
#   install -m 755 relay-load.sh /usr/local/bin/relay-load
#   printf '[Unit]\nDescription=relay load to still.fail cloud\n[Service]\nType=oneshot\nEnvironmentFile=/etc/iroh-relay/load.env\nExecStart=/usr/local/bin/relay-load\n' > /etc/systemd/system/relay-load.service
#   printf '[Unit]\nDescription=relay load every minute\n[Timer]\nOnBootSec=1min\nOnUnitActiveSec=1min\nAccuracySec=5s\n[Install]\nWantedBy=timers.target\n' > /etc/systemd/system/relay-load.timer
#   systemctl daemon-reload && systemctl enable --now relay-load.timer
set -eu
: "${RELAY_URL:?}"
metrics=$(curl -fsS --max-time 5 http://127.0.0.1:9090/metrics)
# When they were read: the post can take many seconds to get there, and rates are worked out between samples.
now=$(date +%s)
# The network card's bytes in and out (the default route's), and the load average.
card=$(ip route show default | awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}')
machine=$(awk -v card="$card:" '$1 == card { print "node_rx " $2; print "node_tx " $10 }' /proc/net/dev; awk '{ print "node_load1 " $1 }' /proc/loadavg; echo "node_time $now")
printf '%s\n%s\n' "$metrics" "$machine" | curl -4 -fsS --max-time 20 -o /dev/null \
  -H "x-stillfail-relay: $RELAY_URL" -H "content-type: text/plain" \
  --data-binary @- "${CLOUD:-https://app.still.fail}/v1/relays/load"
