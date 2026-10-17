#!/bin/bash
# Release builds profiled task by task: the RN trial after a one-line JS change, then the current Compose app after a
# one-line Kotlin change. Each prints its wall time and the slowest tasks (Gradle's --profile report).
export PATH=$HOME/.local/bin:$HOME/Library/pnpm:$HOME/.local/node-v24.15.0-darwin-arm64/bin:/opt/homebrew/bin:$PATH
export JAVA_HOME=$HOME/.sdkman/candidates/java/17.0.18-tem ANDROID_HOME=$HOME/Library/Android/sdk
R=~/scratch/rn-trial
top() { # the newest profile report's tasks, slowest first
  f=$(ls -t $1/build/reports/profile/*.html | head -1)
  python3 - "$f" <<'PY'
import re,sys,html
s=open(sys.argv[1]).read()
rows=re.findall(r'<tr>\s*<td class="indentPath">([^<]+)</td>\s*<td class="numeric">([^<]+)</td>\s*<td>([^<]*)</td>',s)
def sec(t):
    m=re.findall(r'([\d.]+)(m|s)',t); return sum(float(v)*(60 if u=='m' else 1) for v,u in m)
rows=[(sec(t),p,r) for p,t,r in rows]
for t,p,r in sorted(rows,reverse=True)[:10]: print('  %6.1fs  %s %s'%(t,p,r))
PY
}
cd $R/app && sed -i '' 's/BUNDLE = "v[0-9]*"/BUNDLE = "v1"/' src/version.ts && echo "// $(date +%s)" >> src/data.ts
cd android && s=$(date +%s); ./gradlew assembleRelease --profile --console=plain > $R/profile-rn.log 2>&1; echo "RN release after a JS change: $(( $(date +%s)-s ))s (exit $?)"; top .
cd $R/sf/apps/android && echo "private val profileProbe = $(date +%s)" >> app/src/main/kotlin/fail/still/android/screens/Action.kt
s=$(date +%s); ./gradlew -PstillfailPrebuiltEngine -PstillfailBeta :app:assembleRelease --profile --console=plain > $R/profile-sf.log 2>&1; echo "Compose release after a Kotlin change: $(( $(date +%s)-s ))s (exit $?)"; top .
git -C $R/sf checkout -q -- apps/android/app/src/main/kotlin/fail/still/android/screens/Action.kt
