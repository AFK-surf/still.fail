#!/bin/sh
# The workspace of a copy of an app's module staged beside a copy of mbui (scripts/linux.sh, win.sh): the copy itself,
# mbui's copy ($2, as the copy names it), and every other member of the app's own moon.work ($1's: a module of the
# app's, pulled in beside it) where it is, by its absolute path; mbui itself ($3) left out, its copy standing for it.
app=$1
copy=$2
mbui=$(cd "$3" && pwd -P)
printf 'members = [\n  ".",\n  "%s",\n' "$copy"
sed -n 's/^ *"\([^"]*\)",* *$/\1/p' "$app/moon.work" 2>/dev/null | while read -r m; do
  [ "$m" = . ] && continue
  p=$(cd "$app/$m" 2>/dev/null && pwd -P) || continue
  [ "$p" = "$mbui" ] && continue
  # (Git Bash on Windows: moon takes the path as Windows has it)
  if command -v cygpath > /dev/null; then p=$(cygpath -m "$p"); fi
  printf '  "%s",\n' "$p"
done
printf ']\n'
