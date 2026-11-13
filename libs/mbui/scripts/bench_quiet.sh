#!/bin/bash
# Waits (up to QUIET_MAX seconds, default 1200) until no build or emulator is
# busy (a compiler, Gradle, an emulator taking over 5% of a core) and all
# processes together take less than QUIET_CPU % of a core (default 300),
# then prints the machine's load: benchmarks drift with whatever else the
# machine is doing.
max=${QUIET_MAX:-1200}
limit=${QUIET_CPU:-300}
heavy='moon|moonc|clang|cc1|ld|gradle|java|qemu-system[^/]*|swift-frontend|xcodebuild|zig|go'
t=0
while :; do
  busy=$(ps -Ao pcpu,comm | awk '$1 > 5' | grep -Ec "/($heavy)\$" || true)
  cpu=$(ps -Ao pcpu | awk 'NR>1{s+=$1} END{printf "%d", s}')
  if [ "$busy" -eq 0 ] && [ "$cpu" -lt "$limit" ]; then break; fi
  if [ $t -ge $max ]; then echo "bench_quiet: still busy after ${max}s (builds: $busy, CPU: $cpu%)" >&2; break; fi
  sleep 10; t=$((t + 10))
done
echo "load: $(uptime | sed 's/.*load averages*: //') · all processes ${cpu}% CPU · waited ${t}s"
ps -Ao pcpu,comm -r | sed -n 2,6p | awk '{c=$1; $1=""; n=split($0,p,"/"); printf "  %5s%%  %s\n", c, p[n]}'
