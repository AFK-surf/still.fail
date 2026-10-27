# What the app on the simulator drew at the drive's SHOT chat, as instances (MBUI_DRAW_DUMP): those near the list
# card's foot right corner (x -5..60, y 590..700 points), for seeing how they are clipped.
D="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$D"
export SIMCTL_CHILD_MBUI_DRAW_LOG=1
bash scripts/story/film_ios.sh story-iduo-ios-stills > out/story/dump1.txt 2>&1
N=$(python3 - <<'PY'
n = 0
for l in open('out/ios/app.log', errors='replace'):
    if l.startswith('DRAWHASH '): n = int(l.split()[1])
    if 'DRIVE LOG SHOT chat' in l: break
print(n)
PY
)
echo "frame $N"
export SIMCTL_CHILD_MBUI_DRAW_DUMP=$N
bash scripts/story/film_ios.sh story-iduo-ios-stills > out/story/dump2.txt 2>&1
python3 - <<'PY'
for l in open('out/ios/app.log', errors='replace'):
    if not l.startswith('DRAWDUMP inst'): continue
    v = [int(x) / 64 for x in l.split()[2:]]
    if -5 < v[0] < 60 and 590 < v[1] < 700:
        print(' '.join('%g' % x for x in v[:52]))
PY
