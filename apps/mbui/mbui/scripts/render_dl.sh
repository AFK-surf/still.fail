#!/bin/bash
# The draw list the renderer's references are of, goldens/render/controls.dl (kitdemo's controls page over mini1's kept
# text, as a Tester printed it: src/kitdemo/gallery/dl_print_wbtest.mbt), copied into $1 (default
# out/render/controls.dl). Kept beside the references, not printed each run: they say what each renderer draws of one
# list, so only a renderer or the list's format (src/ui/drawlist.mbt) changes them, never a control drawn otherwise
# (#2259's dark segmented thumb turned main's mbui-render red, its own PR not running it). A PR that changes the
# format makes it again (render_dl_make) and the references with it. Sourced by the hosts' render scripts
# (scripts/render_android.sh, render_windows.sh, render_linux.sh, render_web.sh, render_offscreen.sh) from the
# repository's root.
render_dl_make() {
  local out=${1:-goldens/render/controls.dl}
  MBUI_DL_PRINT=1 moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
    awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > "$out"
  [ -s "$out" ] || { echo "render_dl_make: no draw list"; return 1; }
}

render_dl() {
  local out=${1:-out/render/controls.dl}
  mkdir -p "$(dirname "$out")"
  cp goldens/render/controls.dl "$out"
  # and lines' (src/kitdemo/gallery/dl_print_wbtest.mbt lines_shown) beside it, lines.dl: no reference, its picture checked by
  # scripts/chk lines
  MBUI_DL_PRINT=lines moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
    awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > "$(dirname "$out")/lines.dl"
  [ -s "$(dirname "$out")/lines.dl" ] || { echo "render_dl: no lines draw list"; return 1; }
  # and shapes' (src/kitdemo/gallery/dl_print_wbtest.mbt shapes_shown), shapes.dl, checked by scripts/chk shapes
  MBUI_DL_PRINT=shapes moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
    awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > "$(dirname "$out")/shapes.dl"
  [ -s "$(dirname "$out")/shapes.dl" ] || { echo "render_dl: no shapes draw list"; return 1; }
  # The contained blur's straight-edge detail and rounded corners (checked by scripts/chk contained).
  MBUI_DL_PRINT=contained moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
    awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > "$(dirname "$out")/contained.dl"
  [ -s "$(dirname "$out")/contained.dl" ] || { echo "render_dl: no contained draw list"; return 1; }
  # and a spinner's two moments' (src/kitdemo/gallery/dl_print_wbtest.mbt partial_shown), partial-a.dl and
  # partial-b.dl: the second drawn only where it differs from the first (mbui-render's MBUI_DL_FROM), render_partial
  local k
  for k in partial-a partial-b; do
    MBUI_DL_PRINT=$k moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
      awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > "$(dirname "$out")/$k.dl"
    [ -s "$(dirname "$out")/$k.dl" ] || { echo "render_dl: no $k draw list"; return 1; }
  done
  render_matte_dl "$(dirname "$out")"
}

# Light pictures over a matte, filling a rounded frame or letterboxed, and references with the same appearance.
render_matte_dl() {
  local dir=$1 k
  for k in matte-fill matte-fill-reference matte-contain matte-contain-reference matte-inset matte-inset-reference; do
    MBUI_DL_PRINT=$k moon_test_native src/kitdemo/gallery/dl_print_wbtest.mbt 2>/dev/null |
      awk '/^DLEND/{p=0} p{print} /^DLBEGIN/{p=1}' > "$dir/$k.dl"
    [ -s "$dir/$k.dl" ] || { echo "render_matte_dl: no $k draw list"; return 1; }
  done
}

render_matte() {
  local host=$1 dir=${2:-out/render} k
  for k in matte-fill matte-contain matte-inset; do
    if ! cmp -s "$dir/$k.png" "$dir/$k-reference.png"; then
      echo "render_$host: $k differs from its reference frame"
      return 1
    fi
  done
  echo "render_$host: pictures and mattes share their rounded frames"
}

# Partial redraw (docs/partial-redraw.md): out/render/partial.png, partial-b.dl drawn only where it differs from
# partial-a.dl drawn before it, the same to the byte as partial.whole.png, partial-b.dl drawn whole ($1: the host's
# name, said).
render_partial() {
  if cmp -s out/render/partial.png out/render/partial.whole.png; then
    echo "render_$1: a frame drawn only where it differs is the frame drawn whole, to the byte"
  else
    echo "render_$1: a frame drawn only where it differs is not the frame drawn whole (out/render/partial.png, partial.whole.png)"
    return 1
  fi
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
    # (a key may have several lines: each a machine the references were checked on, the same to the byte there)
    want=$(sed -n "s/^$k //p" "$ref")
    have=$(sed -n "s/^$k //p" out/render/machine.txt)
    if ! printf '%s\n' "$want" | grep -Fxq -- "$have"; then
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
