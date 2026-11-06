#!/bin/sh
# Exercise the actual pre-push hook against a small history with main and arch/next.
set -eu
hook=$(cd "$(dirname "$0")/.." && pwd)/.githooks/pre-push
base_script=$(cd "$(dirname "$0")" && pwd)/branch-base.sh
# Hooks inherit their caller's Git directory and index. Clear those before
# creating the fixture so its commits and refs cannot touch the real checkout.
for var in $(git rev-parse --local-env-vars); do unset "$var"; done
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
repo=$(mktemp -d "${TMPDIR:-/tmp}/stillfail-pre-push.XXXXXX")
trap 'rm -rf "$repo"' EXIT
cd "$repo"
git init -q
git config user.email t@example.com
git config user.name test
git commit -qm initial --allow-empty
main=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$main"
git checkout -qb next
git commit -qm next --allow-empty
next=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/arch/next "$next"
git checkout -qb feature
git commit -qm feature --allow-empty
feature=$(git rev-parse HEAD)

mkdir scripts
cp "$base_script" scripts/branch-base.sh
cat > scripts/check.sh <<'SH'
#!/bin/sh
printf 'check %s %s\n' "$1" "$2" >> "$TASK_LOG"
[ "${CHECK_FAIL:-0}" != 1 ]
SH
cat > scripts/undone.sh <<'SH'
#!/bin/sh
printf 'undone %s %s\n' "$1" "$2" >> "$TASK_LOG"
[ "${UNDONE_FAIL:-0}" != 1 ]
SH
TASK_LOG="$repo/calls"
export TASK_LOG
unset STILLFAIL_SKIP_CHECKS EMBER_SKIP_CHECKS
zero=0000000000000000000000000000000000000000
run() {
  : > "$TASK_LOG"
  printf 'refs/heads/feature %s %s %s\n' "$1" "${3:-refs/heads/feature}" "$2" | sh "$hook" > /dev/null
}
expect() {
  if ! grep -Fx "$1" "$TASK_LOG" > /dev/null; then
    echo "FAIL: expected $1; got $(cat "$TASK_LOG")" >&2
    exit 1
  fi
}

# Both guards compare a new arch/next branch with its actual base.
run "$feature" "$zero"
expect "check push $next..$feature"
expect "undone $next $feature"

# The integration branch itself is still checked against main, even when
# its remote tracking ref points to the exact commit under test in CI.
git update-ref refs/remotes/origin/arch/next "$feature"
run "$feature" "$zero" refs/heads/arch/next
expect "check push $main..$feature"
expect "undone $main $feature"
git update-ref refs/remotes/origin/arch/next "$next"

# A later arch/next commit does not hide changes made on an older branch.
git checkout -q next
git commit -qm 'next advances' --allow-empty
git update-ref refs/remotes/origin/arch/next HEAD
run "$feature" "$zero"
expect "check push $next..$feature"
expect "undone $next $feature"

# A branch from main continues using main, and an existing remote ref uses
# its actual remote SHA even when it differs from either base.
git checkout -qb main-feature "$main"
git commit -qm 'main feature' --allow-empty
main_feature=$(git rev-parse HEAD)
run "$main_feature" "$zero"
expect "check push $main..$main_feature"
expect "undone $main $main_feature"
run "$feature" "$next"
expect "check push $next..$feature"
expect "undone $next $feature"

# A newer main branch must not select an older arch/next ancestor.
git update-ref refs/remotes/origin/main "$main_feature"
git commit -qm 'later main feature' --allow-empty
later=$(git rev-parse HEAD)
run "$later" "$zero"
expect "check push $main_feature..$later"
expect "undone $main_feature $later"
git update-ref refs/remotes/origin/main "$main"

# When arch/next is unavailable the original main fallback still applies.
git update-ref -d refs/remotes/origin/arch/next
run "$feature" "$zero"
expect "check push $main..$feature"
expect "undone $main $feature"

# A failing quick check or undone guard must still reject the push.
if CHECK_FAIL=1 run "$feature" "$zero"; then echo 'FAIL: check failure allowed' >&2; exit 1; fi
if UNDONE_FAIL=1 run "$feature" "$zero"; then echo 'FAIL: undone failure allowed' >&2; exit 1; fi
echo 'pre-push cases passed'
