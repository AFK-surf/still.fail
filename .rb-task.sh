export PATH=$HOME/.moon/bin:/opt/homebrew/bin:$HOME/.cargo/bin:$PATH
ROOT=$PWD
O=$ROOT/o1; rm -rf $O; mkdir -p $O
SFROOT=$(cd $ROOT/../sf && pwd)
fixmods() {
  [ -L "$1" ] && rm "$1"
  [ -d "$1" ] && return 0
  mkdir "$1"
  for e in "$2"/* "$2"/.[!.]*; do n=$(basename "$e"); [ "$n" = "@stillfail" ] && continue; ln -s "$e" "$1/$n"; done
  if [ -d "$2/@stillfail" ]; then
    mkdir "$1/@stillfail"
    for e in "$2/@stillfail"/*; do n=$(basename "$e"); [ "$n" = ui ] && continue; ln -s "$e" "$1/@stillfail/$n"; done
    ln -s "$ROOT/web/ui" "$1/@stillfail/ui"
  fi
}
fixmods $ROOT/node_modules $SFROOT/node_modules
fixmods $ROOT/web/node_modules $SFROOT/web/node_modules
[ -e client/core-ts/node_modules ] || ln -s $SFROOT/client/core-ts/node_modules client/core-ts/node_modules
if [ ! -e web/src/core/iroh-pkg/built.js ]; then
  [ -d .git ] || (git init -q && git add -A >/dev/null 2>&1 && git -c user.email=a@b -c user.name=a commit -qm mirror)
  node scripts/native.ts iroh-pkg > $O/iroh.log 2>&1; echo "iroh-pkg: $?"
fi
node client/core-ts/scripts/shapes.ts --check; echo "shapes --check: $?"
(cd client/core-ts && node --test --test-force-exit test/downloads.test.ts test/drive-kept.test.ts > $O/core.log 2>&1; echo "core tests: $?"; grep -E "^ℹ (pass|fail)|^✖" $O/core.log | head)
(cd client/core-ts && ../../node_modules/.bin/tsgo --noEmit > $O/core-tsc.log 2>&1; echo "core tsgo: $?"; head -10 $O/core-tsc.log | cut -c1-300)
(node_modules/.bin/tsgo -p tsconfig.json > $O/tsc.log 2>&1; echo "root tsgo: $?"; head -10 $O/tsc.log | cut -c1-300)
(node_modules/.bin/tsgo -p web/tsconfig.json > $O/web-tsc.log 2>&1; echo "web tsgo: $?"; head -5 $O/web-tsc.log | cut -c1-300)
cd apps/mbui
. scripts/env.sh >/dev/null 2>&1
bash scripts/core.sh apple aarch64-apple-darwin > $O/apple.log 2>&1; echo "apple core: $?"; grep -E "error|did not" $O/apple.log | head -10 | cut -c1-300
"$MBUI_DIR/scripts/detlint" "$A" --update > $O/detlint.log 2>&1; echo "detlint --update: $?"; grep -E "above its bar" $O/detlint.log | head -5 | cut -c1-300
LINES_OUT=200000 bash scripts/test.sh > $O/test.log 2>&1; echo "test.sh: $?"
grep -a -E "^flow: |Total tests|test .* failed|Active test|FAILED|panicked|diverged" $O/test.log | sort -u | head -20 | cut -c1-400
bash scripts/check.sh > $O/check.log 2>&1; echo "check.sh: $?"; tail -2 $O/check.log | cut -c1-200
