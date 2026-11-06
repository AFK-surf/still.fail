export MBUI_TOOLS=$(cd .. && pwd)/tools
. mbui/scripts/env.sh
cd mbui && moon check --target native > ../../c.log 2>&1; grep -a -A8 "^Error" ../../c.log | grep -a "Error\|─\[\|│ " | grep -av "Warning" | head -60 | cut -c1-200; grep -a "Failed with" ../../c.log | tail -1
