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
# Each client's TCP connection to the relay, as the kernel sees it (ss -ti): how the last stretch to each device and
# station goes (its round trip, what had to be sent again, how fast it delivers), which the relay's own counters do not
# say: 2026-10-30 a phone on 衡阳移动 got 8-19 KB/s through Beijing while the relay saw nothing wrong. One line each:
#   node_conn <peer, its last byte(s) zeroed> <port> <rtt ms> <min rtt ms> <bytes sent> <bytes sent again>
#     <delivery rate, bits/s> <ms since it last sent> <1 when the sender had nothing more to send>
# Only those that sent in the last minute; the address cut to its /24 (/48), never the whole of it.
conns=$(ss -tinH state established '( sport = :443 )' 2>/dev/null | awk '
  /^[0-9]/ { peer = $4; next }
  peer != "" {
    port = peer; sub(/.*:/, "", port); ip = peer; sub(/:[0-9]+$/, "", ip); gsub(/^\[|\]$/, "", ip); sub(/^::ffff:/, "", ip)
    if (ip ~ /^[0-9.]+$/) { n = split(ip, b, "."); ip = b[1] "." b[2] "." b[3] ".0" } else { n = split(ip, b, ":"); ip = b[1] ":" b[2] ":" b[3] "::" }
    rtt = 0; minrtt = 0; sent = 0; again = 0; rate = 0; last = 999999; limited = 0
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^rtt:/) { v = $i; sub(/^rtt:/, "", v); sub(/\/.*/, "", v); rtt = v }
      else if ($i ~ /^minrtt:/) { v = $i; sub(/^minrtt:/, "", v); minrtt = v }
      else if ($i ~ /^bytes_sent:/) { v = $i; sub(/^bytes_sent:/, "", v); sent = v }
      else if ($i ~ /^bytes_retrans:/) { v = $i; sub(/^bytes_retrans:/, "", v); again = v }
      else if ($i == "delivery_rate") { v = $(i + 1); sub(/bps$/, "", v); rate = v }
      else if ($i ~ /^lastsnd:/) { v = $i; sub(/^lastsnd:/, "", v); last = v }
      else if ($i == "app_limited") limited = 1
    }
    if (last + 0 < 60000) print "node_conn " ip " " port " " rtt " " minrtt " " sent " " again " " rate " " last " " limited
    peer = ""
  }' | head -n 200)
printf '%s\n%s\n%s\n' "$metrics" "$machine" "$conns" | curl -4 -fsS --max-time 20 -o /dev/null \
  -H "x-stillfail-relay: $RELAY_URL" -H "content-type: text/plain" \
  --data-binary @- "${CLOUD:-https://app.still.fail}/v1/relays/load"
