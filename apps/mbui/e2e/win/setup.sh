#!/bin/bash
# The installer (apps/mbui/windows/setup.c, scripts/win.sh setup) end to end on Windows (mbui.yml's windows job): put
# into a folder of this run's (/D=), as the desktop app's updater runs it (/S --updated); its files there, its uninstall
# entry, its start menu's shortcut; then run again over what it put there (an update); then the uninstaller's copy
# taking it all away (--uninstall-from, as the uninstaller in the folder starts it from the temporary folder). Says what
# it checked in out/setup/result.txt; fails on the first that does not hold.
#   apps/mbui/e2e/win/setup.sh SETUP.exe      (MBUI_VARIANT's words: the mbui variant's by default)
set -u
# (its switches given as written: Git Bash takes /S for a path, S:/, and the installer, hearing none, showed its window,
# opened the app and its uninstaller asked whether to go on, a question nobody answers here)
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
D="$(cd "$(dirname "$0")" && pwd)"
SETUP=$1
w() { cygpath -w "$1"; }
NAME=${SETUP_NAME:-still.fail mbui}
EXE=${SETUP_EXE:-stillfail}
ID=${SETUP_ID:-fail.still.mbui}
INTO=$RUNNER_TEMP/setup-into
OUT=$(dirname "$SETUP")
rm -rf "$INTO"
: > "$OUT/result.txt"
fails=0
check() {
  local what=$1
  shift
  if eval "$*"; then echo "ok   $what" | tee -a "$OUT/result.txt"; else echo "FAIL $what" | tee -a "$OUT/result.txt"; fails=$((fails + 1)); fi
}
entry() { reg.exe query "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$ID" /v "$1" 2>/dev/null | tr -d '\r' | sed -n "s/^ *$1 *REG_[A-Z_]* *//p"; }
menu=$(powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('Programs')" | tr -d '\r')

"$SETUP" /S --updated "/D=$(w "$INTO")" > "$OUT/install.log" 2>&1
check "installed (it exited 0)" '[ $? = 0 ]'
# what runs from the folder (silent and not asked to, the installer opens nothing)
running() { powershell.exe -NoProfile -Command "@(Get-Process | Where-Object { \$_.Path -like '$(w "$INTO")\\*' }).Count" | tr -d '\r'; }
check "nothing opened (/S, no --force-run)" '[ "$(running)" = 0 ]'
check "its program, engine, shell and core in the folder" '[ -f "$INTO/$EXE.exe" ] && [ -f "$INTO/stillfail_engine.dll" ] && [ -f "$INTO/stillfail_shell.dll" ] && [ -f "$INTO/core.hbc" ]'
check "its uninstaller beside them, the program alone" '[ -f "$INTO/Uninstall $NAME.exe" ] && [ $(wc -c < "$INTO/Uninstall $NAME.exe") -lt 2000000 ]'
check "its uninstall entry, at the folder ($(entry DisplayName))" '[ "$(entry InstallLocation)" = "$(w "$INTO")" ]'
check "the start menu's shortcut" '[ -f "$(cygpath -u "$menu")/$NAME.lnk" ]'

# again over it, a file of the old one's that the new one does not carry gone with it
echo old > "$INTO/left-from-before.dll"
"$SETUP" /S --updated "/D=$(w "$INTO")" > "$OUT/update.log" 2>&1
check "put in again over what was there (it exited 0)" '[ $? = 0 ] && [ -f "$INTO/$EXE.exe" ]'
check "what the one before had and this does not, gone" '[ ! -f "$INTO/left-from-before.dll" ]'

cp "$INTO/Uninstall $NAME.exe" "$RUNNER_TEMP/setup-uninstall.exe"
"$RUNNER_TEMP/setup-uninstall.exe" --uninstall-from "$(w "$INTO")" /S > "$OUT/uninstall.log" 2>&1
check "taken away: the folder, its uninstall entry, its shortcut" '[ ! -d "$INTO" ] && [ -z "$(entry InstallLocation)" ] && [ ! -f "$(cygpath -u "$menu")/$NAME.lnk" ]'
for f in install update uninstall; do echo "== $f.log"; tail -15 "$OUT/$f.log"; done
echo "setup: $fails failed" | tee -a "$OUT/result.txt"
[ $fails = 0 ]
