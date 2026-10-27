# which swap settings fold the simulator back: each tried, SpringBoard's word on it and whether the inner screen is lit
cd "$(dirname "$0")/../.."
ID=$(xcrun simctl list devices -j | python3 -c "import json,sys;print([x['udid'] for ds in json.load(sys.stdin)['devices'].values() for x in ds if x['name']=='sf-film-duo'][0])")
INNER=61297E4F-3F53-46A8-92F6-440AE1603896
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=17.0 -isysroot "$SDK" -fobjc-arc -framework Foundation \
  scripts/story/fold.m -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker scripts/story/fold.ent -o out/story/fold || exit 1
codesign -s - -f out/story/fold 2>/dev/null
lit() { xcrun simctl io $ID screenshot --display=$INNER /tmp/sf-try-$$.png >/dev/null 2>&1; stat -f %z /tmp/sf-try-$$.png; }
for args in "0.64 0 0 0 0"; do
  echo "== $args (inner before: $(lit))"
  xcrun simctl spawn $ID "$PWD/out/story/fold" swap $args 2>&1 | grep -v "implemented in both"
  sleep 2
  xcrun simctl spawn $ID log show --last 6s --predicate 'eventMessage CONTAINS "SBDisplayToolService"' 2>/dev/null | grep -v "log run" | cut -c120-500 | tail -8
  echo "inner after: $(lit)"
done
rm -f /tmp/sf-try-$$.png
