# Sourced by the scripts that run a tool of tools/ (chk, detlint, apk; the app's assets, icons, strings, …): what it is
# built for. In development, wasm-gc, run in Node by wasmrun.mjs (the user, 2026-11-03: no C compiled for what is only
# developed with); in CI (GITHUB_ACTIONS) or with MBUI_TOOLS_NATIVE=1, native, as CI keeps them
# (.github/actions/mbui-moonbit). TT the target, TX its program's extension; tool_exec PROGRAM ARGS… runs it. The
# script sets TOOLS_SCRIPTS (this directory) first.
if [ -n "${GITHUB_ACTIONS:-}" ] || [ "${MBUI_TOOLS_NATIVE:-}" = 1 ]; then
  TT=native TX=exe
  tool_exec() { exec "$@"; }
else
  TT=wasm-gc TX=wasm
  tool_exec() { exec node "$TOOLS_SCRIPTS/wasmrun.mjs" "$@"; }
fi
