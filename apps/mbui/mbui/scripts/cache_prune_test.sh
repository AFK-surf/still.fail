#!/bin/sh
set -eu
task_root="$PWD"
probe_dir="$task_root/out/cache-prune-probe"
mkdir -p "$probe_dir/bin"
cat > "$probe_dir/bin/date" <<'EOF'
#!/bin/sh
if [ "$*" = '-u +%s' ]; then printf '1800000000\n'; else exec /bin/date "$@"; fi
EOF
cat > "$probe_dir/bin/gh" <<'EOF'
#!/bin/sh
set -eu
call=unknown
ref=
for arg in "$@"; do
  case "$arg" in
    repos/probe/repo) call=default ;;
    'repos/probe/repo/branches?per_page=100') call=branches ;;
    'repos/probe/repo/actions/caches?per_page=100') call=caches ;;
    repos/probe/repo/actions/caches) call=still ;;
    repos/probe/repo/actions/caches/*) call=delete; id=${arg##*/} ;;
    graphql) call=ref ;;
    ref=*) ref=${arg#ref=} ;;
  esac
done
case "$call" in
  default)
    [ "$PROBE_MODE" != fail-default ] || exit 1
    printf 'main\n' ;;
  branches)
    [ "$PROBE_MODE" != fail-branches ] || exit 1
    if [ "$PROBE_MODE" = missing-default ]; then printf 'other\n'; else printf 'main\nlive\n'; fi ;;
  caches)
    [ "$PROBE_MODE" != fail-caches ] || exit 1
    printf '101\tgone-cache\trefs/heads/gone\t2000000\t2026-01-01T00:00:00Z\t2026-01-01T00:00:00Z\n'
    printf '102\tlive-cache\trefs/heads/live\t2000000\t2026-01-01T00:00:00Z\t2026-01-01T00:00:00Z\n'
    printf '103\trecent-cache\trefs/heads/recent\t2000000\t2027-01-15T07:30:01Z\t2027-01-15T07:30:01Z\n'
    printf '104\tpull-cache\trefs/pull/1/merge\t2000000\t2026-01-01T00:00:00Z\t2026-01-01T00:00:00Z\n'
    printf '105\tracy-cache\trefs/heads/racy\t2000000\t2026-01-01T00:00:00Z\t2026-01-01T00:00:00Z\n'
    printf '106\tzero-cache\trefs/heads/live\t0\t2026-01-01T00:00:00Z\t2026-01-01T00:00:00Z\n'
    printf "107\tquoted-cache\trefs/heads/it's&safe\t2000000\t2026-01-01T00:00:00Z\t2026-01-01T00:00:00Z\n"
    case "$PROBE_MODE" in malformed-*)
      # Valid companions must also be left alone when a record could poison sorting or a Gradle cutoff.
      printf '109\trolling-aaaaaaaaaaaaaaaa\trefs/heads/live\t2000000\t2026-01-01T00:00:00Z\t2026-01-01T00:00:00Z\n'
      printf '111\tgradle-home-v1-check-aaaaaaaaaaaaaaaa\trefs/heads/live\t2000000\t2026-01-01T00:00:00Z\t2026-01-01T00:00:00Z\n'
      printf '112\tgradle-transforms-v1-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\trefs/heads/live\t2000000\t2026-01-01T00:00:00Z\t2026-01-01T00:00:00Z\n'
      case "$PROBE_MODE" in
        malformed-deleted) printf '108\tdeleted-bad\trefs/heads/malformed\t2000000\t2026-11-xxT00:00:00Z\t2026-01-01T00:00:00Z\n' ;;
        malformed-rolling) printf '110\trolling-bbbbbbbbbbbbbbbb\trefs/heads/live\t2000000\t2026-02-30T00:00:00Z\t2026-01-01T00:00:00Z\n' ;;
        malformed-home) printf '113\tgradle-home-v1-check-bbbbbbbbbbbbbbbb\trefs/heads/live\t2000000\t2026-01-01T00:00:00Z\t2026-11-xxT00:00:00Z\n' ;;
        malformed-part) printf '114\tgradle-transforms-v1-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\trefs/heads/live\t2000000\t2026-01-01T00:00:00Z\t2026-01-01T24:00:00Z\n' ;;
      esac ;;
    invalid-*)
      # These records are deliberately synthetic; valid neighbours would otherwise be deleted.
      case "$PROBE_MODE" in
        invalid-id-empty) fields='\tbad-cache\trefs/heads/gone\t2000000' ;;
        invalid-id-text) fields='115bad\tbad-cache\trefs/heads/gone\t2000000' ;;
        invalid-id-shell) fields='115;printf injected > out/cache-prune-probe/injected.log\tbad-cache\trefs/heads/gone\t2000000' ;;
        invalid-key-empty) fields='115\t\trefs/heads/gone\t2000000' ;;
        invalid-ref-empty) fields='115\tbad-cache\t\t2000000' ;;
        invalid-size-empty) fields='115\tbad-cache\trefs/heads/gone\t' ;;
        invalid-size-text) fields='115\tbad-cache\trefs/heads/gone\t2000000x' ;;
        invalid-size-negative) fields='115\tbad-cache\trefs/heads/gone\t-1' ;;
        invalid-size-fraction) fields='115\tbad-cache\trefs/heads/gone\t2000000.5' ;;
        invalid-size-overflow) fields='115\tbad-cache\trefs/heads/gone\t9223372036854775808' ;;
        invalid-size-total) fields='115\tbad-cache\trefs/heads/gone\t9223372036854775807' ;;
      esac
      printf '%b\t2026-01-01T00:00:00Z\t2026-01-01T00:00:00Z\n' "$fields" ;;
    esac ;;
  ref)
    printf '%s\n' "$ref" >> "$PROBE_DIR/refs.log"
    if [ "$PROBE_MODE" = fail-ref ]; then printf 'error\n'
    elif [ "$ref" = refs/heads/racy ]; then printf 'present\n'
    elif [ "$ref" = refs/heads/gone ] || [ "$ref" = refs/heads/malformed ] || [ "$ref" = "refs/heads/it's&safe" ]; then printf 'missing\n'
    else printf 'unexpected ref: %s\n' "$ref" >&2; exit 1
    fi ;;
  delete)
    printf '%s\n' "$id" >> "$PROBE_DIR/deletes.log"
    [ "$PROBE_MODE" != fail-delete ] || exit 1 ;;
  still)
    printf '%s\n' "$ref" >> "$PROBE_DIR/still.log"
    printf '101\n107\n' ;;
  *) printf 'unexpected gh call: %s\n' "$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$probe_dir/bin/date" "$probe_dir/bin/gh"
export PROBE_DIR="$probe_dir" GH_REPO=probe/repo
export PATH="$probe_dir/bin:$PATH"
bad_records='invalid-id-empty invalid-id-text invalid-id-shell invalid-key-empty invalid-ref-empty invalid-size-empty invalid-size-text invalid-size-negative invalid-size-fraction invalid-size-overflow invalid-size-total'
for mode in normal fail-default fail-branches missing-default fail-caches fail-ref malformed-deleted malformed-rolling malformed-home malformed-part $bad_records; do
  [ -z "${PROBE_ONLY:-}" ] || [ "$PROBE_ONLY" = "$mode" ] || continue
  export PROBE_MODE="$mode"
  : > "$probe_dir/deletes.log"
  : > "$probe_dir/refs.log"
  : > "$probe_dir/injected.log"
  set +e
  sh scripts/chk cache-prune --dry-run > "$probe_dir/$mode.log" 2>&1
  status=$?
  set -e
  if [ "$mode" = normal ]; then
    [ "$status" -eq 0 ]
    grep -q '^would delete gone-cache ' "$probe_dir/$mode.log"
    grep -q '^would delete quoted-cache ' "$probe_dir/$mode.log"
    [ "$(grep -c '^would delete ' "$probe_dir/$mode.log")" -eq 2 ]
    grep -Fxq "refs/heads/it's&safe" "$probe_dir/refs.log"
  else
    [ "$status" -ne 0 ]
    ! grep -q '^would delete ' "$probe_dir/$mode.log"
    case "$mode" in
      malformed-*) grep -q 'invalid cache time; nothing deleted' "$probe_dir/$mode.log"; [ ! -s "$probe_dir/refs.log" ] ;;
      invalid-*) grep -q 'invalid cache record; nothing deleted' "$probe_dir/$mode.log"; [ ! -s "$probe_dir/refs.log" ] ;;
    esac
  fi
  [ ! -s "$probe_dir/deletes.log" ]
  [ ! -s "$probe_dir/injected.log" ]
done
for mode in malformed-deleted malformed-rolling malformed-home malformed-part $bad_records; do
  [ -z "${PROBE_ONLY:-}" ] || [ "$PROBE_ONLY" = "$mode" ] || continue
  export PROBE_MODE="$mode"
  : > "$probe_dir/deletes.log"
  : > "$probe_dir/refs.log"
  : > "$probe_dir/injected.log"
  set +e
  sh scripts/chk cache-prune > "$probe_dir/$mode-write.log" 2>&1
  status=$?
  set -e
  [ "$status" -ne 0 ]
  case "$mode" in
    malformed-*) grep -q 'invalid cache time; nothing deleted' "$probe_dir/$mode-write.log" ;;
    invalid-*) grep -q 'invalid cache record; nothing deleted' "$probe_dir/$mode-write.log" ;;
  esac
  [ ! -s "$probe_dir/deletes.log" ]
  [ ! -s "$probe_dir/refs.log" ]
  [ ! -s "$probe_dir/injected.log" ]
done
[ -z "${PROBE_ONLY:-}" ] || exit 0
export PROBE_MODE=normal
: > "$probe_dir/deletes.log"
sh scripts/chk cache-prune > "$probe_dir/delete.log" 2>&1
[ "$(sort "$probe_dir/deletes.log" | tr '\n' ' ')" = '101 107 ' ]
export PROBE_MODE=fail-delete
: > "$probe_dir/deletes.log"
set +e
sh scripts/chk cache-prune > "$probe_dir/delete-fail.log" 2>&1
status=$?
set -e
[ "$status" -ne 0 ]
grep -q 'chk cache-prune: deleting' "$probe_dir/delete-fail.log"
printf 'Synthetic branch, cache and deletion-error paths passed; gh was a local stub.\n'
