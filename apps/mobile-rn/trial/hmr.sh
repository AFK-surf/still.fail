#!/bin/bash
# Time from saving a change to the new code running on the device: the module logs Date.now() as it is evaluated.
F="$HOME/scratch/rn-trial/app/app/(chats)/index.tsx"
L=$HOME/scratch/rn-trial/metro.log
mark=$1
s=$(python3 -c 'import time;print(int(time.time()*1000))')
sed -i '' -E "s/title=\"对话[^\"]*\"/title=\"对话 $mark\"/; s/^console.log\(\"HMR\".*$/console.log(\"HMR\", \"$mark\", Date.now());/" "$F"
for i in $(seq 1 400); do grep -q "HMR $mark " "$L" && break; sleep 0.05; done
t=$(grep "HMR $mark " "$L" | tail -1 | awk '{print $NF}')
python3 -c "print('$mark: %d ms' % ($t-$s))"
