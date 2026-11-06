#!/bin/sh
# The full check's station halves, run against a small tracked tree with stand-in tools.
set -eu
source_script=$(cd "$(dirname "$0")" && pwd)/check.sh
for var in $(git rev-parse --local-env-vars); do unset "$var"; done
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
repo=$(mktemp -d "${TMPDIR:-/tmp}/stillfail-check-parts.XXXXXX")
trap 'rm -rf "$repo"' EXIT
cd "$repo"
git init -q
git config user.email t@example.com
git config user.name test
mkdir -p scripts station/src station/native/mesh client/shell/src client/core-ts media/core media/service media/test bin
# Its normal PATH puts the real cargo first; keep this fixture's tools first instead.
sed 's|^export PATH=.*|export PATH="$CHECK_PART_TOOLS:$PATH"|' "$source_script" > scripts/check.sh
: > station/src/example.ts
: > station/native/mesh/Cargo.toml
: > client/shell/src/lib.rs
: > client/Cargo.toml
git add scripts/check.sh station/src/example.ts station/native/mesh/Cargo.toml client/shell/src/lib.rs client/Cargo.toml
git commit -qm fixture
for tool in node pnpm cargo rustc; do
  printf '#!/bin/sh\nexit 0\n' > "bin/$tool"
  chmod +x "bin/$tool"
done
PATH="$repo/bin:$PATH"
CHECK_PART_TOOLS="$repo/bin"
export PATH CHECK_PART_TOOLS
run() {
  if ! XDG_CACHE_HOME="$repo/cache-$2" STILLFAIL_CHECK_PART="$1" sh scripts/check.sh all > "$repo/$2.log"; then
    cat "$repo/$2.log"
    exit 1
  fi
}
has() { grep -F "$2" "$repo/$1.log" > /dev/null || { cat "$repo/$1.log"; echo "missing $2" >&2; exit 1; }; }
lacks() { if grep -F "$2" "$repo/$1.log" > /dev/null; then cat "$repo/$1.log"; echo "unexpected $2" >&2; exit 1; fi; }

run station-js js
has js 'tests: station … ok'
has js 'tests: station and core usage stream … ok'
has js 'tests: media … ok'
lacks js 'Rust: station/'
lacks js 'Rust: client'

run 'station-native core' native
has native 'Rust: station/native/mesh … ok'
has native 'Rust: client … ok'
lacks native 'tests: station …'
lacks native 'tests: station and core usage stream …'
lacks native 'tests: media …'

# The original station selection remains both station halves, without client Rust.
run station combined
has combined 'tests: station … ok'
has combined 'Rust: station/native/mesh … ok'
lacks combined 'Rust: client'
echo 'check part cases passed'
