#!/bin/sh
# The test channel's desktop app (fail.still.desktop.beta), released from studio: it is signed with the Apple Development
# certificate in studio's login keychain, which only its logged-in GUI session can use (~/bin/ember-gui runs a command
# there). CI (.github/workflows/pipeline.yml, on mini1) runs this on studio over ssh:
#   ssh studio "sh -s <commit>" < .github/desktop-on-studio.sh   (RELEASE_DIR=dir: into it, not the bucket)
# The commit is built in a worktree of its own (~/ember-wt/ci-desktop), never studio's checkout.
set -eu
sha=${1:?usage: desktop-on-studio.sh <commit>}
export PATH="$HOME/.local/bin:$HOME/Library/pnpm:$HOME/.local/node-v24.15.0-darwin-arm64/bin:$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"
repo=~/WebstormProjects/ember
wt=~/ember-wt/ci-desktop
# A deploy fetching at the same moment holds the ref's lock: tried again.
for try in 1 2 3; do git -C $repo fetch -q github && break; sleep 10; done
[ -d $wt ] || git -C $repo worktree add -q --detach $wt "$sha"
git -C $wt checkout -q -f --detach "$sha"
(cd $wt && pnpm install --frozen-lockfile --prefer-offline >/dev/null && cd apps/desktop && pnpm install --frozen-lockfile --prefer-offline >/dev/null && cd ../../cloud && pnpm install --frozen-lockfile --prefer-offline >/dev/null)
EMBER_GUI_WAIT=1 ~/bin/ember-gui ci-desktop "export PATH='$PATH'; cd $wt && ${RELEASE_DIR:+RELEASE_DIR=$RELEASE_DIR} sh scripts/release.sh --beta desktop"
