#!/bin/sh
# A command's peak resident memory (VmHWM, KB) on Linux/Android, where there is no `time -l`: it runs in the
# background and its /proc status is read until it exits. Its output goes to /dev/null. peak.sh <command…>
"$@" > /dev/null 2>&1 &
pid=$!
peak=0
while kill -0 $pid 2>/dev/null; do
  now=$(grep VmHWM /proc/$pid/status 2>/dev/null | tr -s ' ' | cut -d' ' -f2)
  [ -n "$now" ] && peak=$now
done
wait $pid
echo "$peak"
