#!/usr/bin/env bash
# The Linux host's apt archives and the exact package indexes used to prepare them. A consuming job must not consult
# a newer index or fetch a missing archive: its --no-download install either uses this handoff or fails the contract.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
case "${1:-}" in
  snapshot)
    cache=${2:?apt archive directory}
    out=${3:?handoff directory}
    mkdir -p "$out/archives" "$out/lists"
    find "$cache" -maxdepth 1 -type f -name '*.deb' -exec cp '{}' "$out/archives/" \;
    sudo cp -a /var/lib/apt/lists/. "$out/lists/"
    sudo rm -rf "$out/lists/partial" "$out/lists/lock"
    sudo chown -R "$(id -u):$(id -g)" "$out"
    printf 'Linux host package archives and their apt indexes.\n' > "$out/README"
    ;;
  install)
    handoff=${2:?handoff directory}
    mapfile -t packages < "$D/linux-host-packages.txt"
    sudo mkdir -p "$handoff/archives/partial" "$handoff/lists/partial"
    sudo apt-get -o Dir::State::Lists="$handoff/lists" -o Dir::Cache::Archives="$handoff/archives" \
      install -y -q --no-download --no-install-recommends "${packages[@]}"
    ;;
  *) echo 'linux-host-packages.sh snapshot APT_ARCHIVES HANDOFF | install HANDOFF' >&2; exit 2 ;;
esac
