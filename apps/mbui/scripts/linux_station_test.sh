#!/bin/bash
# This machine's station as the Linux app says it (src/host/linux_station.c, through scripts/linux_station_test.c), in a
# home of the run's own: one started by hand said so, with its release, its data and its workspace, and stopped from
# here; the installer's systemd service said as what runs it, and a machine that only runs tasks taken out of its
# workspace said so. On Linux, with GTK 4's development files and MoonBit (MOON_HOME) for its runtime.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
A="$D/.."
O="$A/out/linux-station"
MOON_HOME=${MOON_HOME:-$HOME/.moon}
rm -rf "$O" && mkdir -p "$O"
cc -Wall -Werror -Wno-unused-function -I "$A/../../libs/mbui/src/host" -I "$MOON_HOME/include" "$D/linux_station_test.c" "$MOON_HOME/lib/runtime/runtime.c" \
  $(pkg-config --cflags --libs gtk4) -lpthread -lm -o "$O/linux_station_test"

# a home of the run's own: a station's data (~/.stillfail) whose run/station.json names a process of the run's, alive
# until it is stopped (a stand-in for the station), and whose mesh/cloud.json names its workspace
S="$O/home"
mkdir -p "$S/.stillfail/run" "$S/.stillfail/mesh" "$S/.stillfail/app"
printf '{"workspace":"ws1","workspace_name":"星火","station":"st1","name":"Studio","removed_at":null}' \
  > "$S/.stillfail/mesh/cloud.json"
tail -f /dev/null & ST=$!
printf '{"pid":%d,"version":"0.1.4321"}' $ST > "$S/.stillfail/run/station.json"
out=$(HOME=$S XDG_CONFIG_HOME=$S/.config "$O/linux_station_test" stop) || { kill $ST 2> /dev/null; exit 1; }
read=$(printf '%s\n' "$out" | grep -a "STATIONCHECK read"); after=$(printf '%s\n' "$out" | grep -a "STATIONCHECK after")
echo "$read"; echo "$after"
for want in '"runner":"other"' '"version":"0.1.4321"' '"installed":true' "\"data\":\"$S/.stillfail\"" \
  '"workspace":{"id":"ws1","name":"星火","station":"st1","stationName":"Studio","removed":false}'; do
  case "$read" in *"$want"*) ;; *) kill $ST 2> /dev/null; echo "station (linux): not said: $want"; exit 1 ;; esac
done
case "$after" in *'"runner":"none"'*) ;; *) kill $ST 2> /dev/null; echo "station (linux): not stopped"; exit 1 ;; esac
wait $ST 2> /dev/null || true
if kill -0 $ST 2> /dev/null; then kill $ST; echo "station (linux): said stopped, still running"; exit 1; fi

# the installer's service there (its unit, where systemd looks for a user's): what runs it
mkdir -p "$S/.config/systemd/user" && : > "$S/.config/systemd/user/stillfail-station.service"
# (its data now a rig's, taken out of its workspace: both said)
printf '{"workspace":"ws1","station":"st1","removed_at":1700000000,"rig":{"owner":"u1"}}' > "$S/.stillfail/mesh/cloud.json"
tail -f /dev/null & ST=$!
printf '{"pid":%d,"version":"0.1.4321"}' $ST > "$S/.stillfail/run/station.json"
read=$(HOME=$S XDG_CONFIG_HOME=$S/.config "$O/linux_station_test" read | grep -a "STATIONCHECK read") || true
kill $ST
echo "$read"
case "$read" in *'"runner":"service"'*'"service":{"kind":"systemd","name":"stillfail-station.service"}'*) ;;
  *) echo "station (linux): its service not said"; exit 1 ;; esac
case "$read" in *'"workspace":{"id":"ws1","station":"st1","removed":true,"rig":true}'*) ;;
  *) echo "station (linux): a rig taken out of its workspace not said"; exit 1 ;; esac
echo "station (linux): one started by hand said and stopped; the service's said as running it"
