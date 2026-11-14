#!/bin/sh
# Farview's client (AFK-surf/farview, private: its client/, the module fvclient, which draws a chat's Farview tab in the
# app) at the commit farview.pin names, into deps/farview/client, which moon.work names (the user, 2026-11-14: kept out
# of this repository, pulled at a pinned commit). Nothing is fetched while deps/farview holds that commit. In CI its
# read-only deploy key is FARVIEW_DEPLOY_KEY (the workflows' secret); elsewhere git's own credentials for GitHub.
set -eu
A=$(cd "$(dirname "$0")/.." && pwd)
pin=$(tr -d ' \n' < "$A/farview.pin")
d=$A/deps/farview
[ "$(cat "$d/.pin" 2>/dev/null || true)" = "$pin" ] && [ -f "$d/client/moon.mod" ] && exit 0
tmp=$A/deps/farview.tmp
rm -rf "$tmp"
mkdir -p "$tmp"
git init -q "$tmp/git"
url=https://github.com/AFK-surf/farview.git
if [ -n "${FARVIEW_DEPLOY_KEY:-}" ]; then
  umask 077
  printf '%s\n' "$FARVIEW_DEPLOY_KEY" > "$tmp/key"
  url=git@github.com:AFK-surf/farview.git
  export GIT_SSH_COMMAND="ssh -i '$tmp/key' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
fi
git -C "$tmp/git" fetch -q --depth 1 "$url" "$pin"
git -C "$tmp/git" checkout -q FETCH_HEAD
rm -rf "$d"
mkdir -p "$d"
mv "$tmp/git/client" "$d/client"
printf '%s\n' "$pin" > "$d/.pin"
rm -rf "$tmp"
