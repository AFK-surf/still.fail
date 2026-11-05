# each instr test alone, its process's instructions (macOS /usr/bin/time -l), the median of three: INSTR|name|n
cd "$(dirname "$0")/.." && . scripts/env.sh && native_tests "$PWD"
moon test $NATIVE -p stillfail/sfapp -f 'instr|chat|small|1280|opened' > /dev/null 2>&1
E=_build/native/release/test/stillfail/sfapp/sfapp.whitebox_test.exe
names=$(grep -o '^test "instr|[^"]*"' src/sfapp/zz_instr_wbtest.mbt | sed 's/test "//; s/"$//')
i=0
for name in $names; do
  vals=""
  for r in 1 2 3; do
    v=$( (/usr/bin/time -l $E "zz_instr_wbtest.mbt:$i-$((i+1))" > /dev/null) 2>&1 | awk '/instructions retired/{print $1}')
    vals="$vals $v"
  done
  med=$(echo $vals | tr ' ' '\n' | sort -n | sed -n 2p)
  echo "INSTR|$name|$med|$vals"
  i=$((i+1))
done
