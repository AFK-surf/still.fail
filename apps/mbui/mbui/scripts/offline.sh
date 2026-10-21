#!/bin/bash
# A step's script run with no network (a workflow's `shell: bash scripts/offline.sh {0}`): what a test needs is in the
# checkout or the job set it up before (MoonBit from the cache), so a test that reaches for the network fails every
# time, not now and then as the network does. Linux: a network namespace of its own (unshare -rn: only a loopback,
# down); macOS: sandbox-exec denying every connection over IP. Elsewhere it says so and fails.
set -e
script=$1
case "$(uname)" in
  Linux)
    exec unshare -rn bash --noprofile --norc -eo pipefail "$script" ;;
  Darwin)
    exec sandbox-exec -p '(version 1) (allow default) (deny network-outbound (remote ip)) (deny network-inbound (local ip))' \
      bash --noprofile --norc -eo pipefail "$script" ;;
  *)
    echo "offline.sh: no way here to run without the network ($(uname))" >&2; exit 1 ;;
esac
