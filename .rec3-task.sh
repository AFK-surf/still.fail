export PATH=$HOME/.moon/bin:/opt/homebrew/bin:$HOME/.cargo/bin:$PATH
ROOT=$PWD
O=$ROOT/o2; rm -rf $O; mkdir -p $O
node client/core-ts/scripts/shapes.ts; echo "shapes: $?"
(node_modules/.bin/tsgo -p web/tsconfig.json > $O/web-tsc.log 2>&1; echo "web tsgo: $?"; head -5 $O/web-tsc.log | cut -c1-300)
[ -d .git ] || git init -q
# (the packages linked in from the checkout beside are not this checkout's: a clone of it installs its own)
grep -qx node_modules .git/info/exclude 2>/dev/null || echo node_modules >> .git/info/exclude
git rm -r -q --cached --ignore-unmatch node_modules web/node_modules client/core-ts/node_modules >/dev/null 2>&1
git add -A >/dev/null 2>&1 && git -c user.email=a@b -c user.name=a commit -qm "mirror $(date +%s)" >/dev/null 2>&1
git ls-files | grep -c node_modules
export EMBER=$ROOT
export E2E_WORK=$ROOT/../dr-e2e2 E2E_PORT=27187 E2E_RELAY=27140
[ -d $E2E_WORK/ember ] && git -C $E2E_WORK/ember remote set-url origin $ROOT
cd apps/mbui
for p in 27187 27188 27189 27190 27191 27192 27194 27140; do lsof -nP -iTCP:$p -sTCP:LISTEN 2>/dev/null | tail -1; done
bash scripts/rerecord.sh 15-drive-lend drive_zip > $O/rerecord.log 2>&1; echo "rerecord: $?"
grep -a -E "rerecord:|PASS|FAIL|diverg|ok |trace" $O/rerecord.log | tail -30 | cut -c1-300
E2E_WORK=$ROOT/../dr-e2e2 E2E_PORT=27187 E2E_RELAY=27140 bash scripts/e2e-local.sh down > /dev/null 2>&1; echo "down: $?"
