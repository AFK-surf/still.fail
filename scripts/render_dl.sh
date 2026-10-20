#!/bin/bash
# The draw list the renderer's references are of (kitdemo's controls page over mini1's kept text,
# src/kitdemo/dl_print_wbtest.mbt), as a Tester prints it: into $1 (default out/render/controls.dl). Sourced by the
# hosts' render scripts (scripts/render_android.sh, render_windows.sh, render_web.sh) from the repository's root.
render_dl() {
  local out=${1:-out/render/controls.dl}
  mkdir -p "$(dirname "$out")"
  MBUI_DL_PRINT=1 moon test --target js src/kitdemo/dl_print_wbtest.mbt 2>/dev/null |
    awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > "$out"
  [ -s "$out" ] || { echo "render_dl: no draw list"; return 1; }
}

# The picture against its reference, on the machine the references were made on: goldens/render/$1.txt's lines
# whose key is one of $2 (space separated: what draws the picture there, emulator, browser, fonts…) the same in
# out/render/machine.txt, and
# out/render/controls.png the same as goldens/render/$1-controls.png to the byte. Either not: a failure saying what
# to do (a new machine: every reference of the host made again in one PR, from the workflow's artifact).
render_against() {
  local host=$1 keys=$2 ref=goldens/render/$1.txt bad=0 k want have
  if [ ! -f "$ref" ] || [ ! -f "goldens/render/$host-controls.png" ]; then
    echo "no reference for $host yet: commit this run's artifact (render-$host) as goldens/render/$host-controls.png and $host.txt"
    return 1
  fi
  for k in $keys; do
    want=$(sed -n "s/^$k //p" "$ref")
    have=$(sed -n "s/^$k //p" out/render/machine.txt)
    if [ "$want" != "$have" ]; then
      echo "$k: this run's is \"$have\", the references were made on \"$want\": make them all again in one PR (this run's artifact), saying so"
      bad=1
    fi
  done
  [ $bad = 0 ] || return 1
  if cmp -s out/render/controls.png "goldens/render/$host-controls.png"; then
    echo "the same to the byte"
  else
    echo "goldens/render/$host-controls.png: not what this runner draws now (this run's artifact has it)"
    return 1
  fi
}
