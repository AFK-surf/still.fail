export MBUI_TOOLS=$(cd .. && pwd)/tools
. mbui/scripts/env.sh
(cd mbui && moon test --target native -p mbui/ui > ../../l1.log 2>&1; grep -a "Total" ../../l1.log; grep -a -A6 "^Error" ../../l1.log | head -30; grep -a '\] test .*failed' ../../l1.log | head -8 | cut -c1-500)
moon test --target native -p stillfail/sfapp --filter "the chats' list flung on a phone*" > ../hf.log 2>&1; grep -a "Total" ../hf.log; grep -a "PanicError" -A1 ../hf.log | head -2 | cut -c1-300
