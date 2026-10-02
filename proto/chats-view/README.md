# Prototype: the chat list, ported from the Rust core to TypeScript

A real piece of the client core in TypeScript, to see what porting it is like and what it costs where it would run:
the chat list (client/core/src/views.rs `chats` and `days`, with present.rs, decisions.rs, format.rs, the model names
of client/shapes and the words of client/i18n) as `ts/chats.ts`, about as long as the Rust it ports.

- `make-input.py`: the station's rows (what GET /chats gives) from a copy of a station's database; repeated up to
  2000; `vary` makes every branch run. Its output holds real chats: it is copied between test machines, never committed.
- `rust/`: the Rust core's own functions over that input, as the view calls them: the baseline, and the reference.
- `ts/chats.ts` (+ `build.mjs` for QuickJS with the catalog, `node-run.mjs` for V8); `compare.py`: outputs equal?

Results on studio (2026-10-03), median ms for the whole list, including turning it into the text the UI gets. Hermes
is built from source (facebook/hermes 6e2181b; for the Android CLI, hermes.cpp's fbjni lines left out), run as source
and as bytecode from `hermesc -O` (as React Native ships it: the same numbers).

| rows | Rust core | TS on V8 | TS on QuickJS | TS on Hermes |
|---|---|---|---|---|
| Mac, 342 (one station's real chats) | 9.6 | 5.0 | 25.5 | 11 |
| Mac, 2000 | 58–64 | 23–25 | 152 | 61–64 |
| Android emulator, 342 | 14–15 | | 27.5 | 12 |
| Android emulator, 2000 | 98–121 | | 157–166 | 68–70 |

Equal outputs, field by field, between the Rust core and the TypeScript port on every engine, for the 342 real rows,
2000 rows and 2000 varied rows (cards, waits, failures, watches, Slack origins, several agents, …).

Peak memory (MB, RSS; 5 runs of the list), the same day. Mac by `time -l`; Android emulator by VmHWM (`peak.sh`).
QuickJS runs inside the client shell (with its iroh endpoint), so its baseline includes that.

| rows | Rust core | TS on Node | TS on QuickJS | TS on Hermes (bytecode) |
|---|---|---|---|---|
| Mac, none (baseline) | 6.0 | 45.1 | 14.5 | 9.5 |
| Mac, 342 | 25.1 | 70.7 | 21.9 | 24.1 |
| Mac, 2000 | 107.5 | 145.7 | 70.5 | 63.1 |
| Android emulator, none | — | | 14.2–14.6 | 6.0–8.4 |
| Android emulator, 342 | 25.3–25.4 | | 21.3–21.4 | 21.7–22.4 |
| Android emulator, 2000 | 113.5 | | 51.1–51.6 | 41.3–41.5 |
