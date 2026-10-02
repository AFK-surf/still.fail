# Prototype: the chat list, ported from the Rust core to TypeScript

A real piece of the client core in TypeScript, to see what porting it is like and what it costs where it would run:
the chat list (client/core/src/views.rs `chats` and `days`, with present.rs, decisions.rs, format.rs, the model names
of client/shapes and the words of client/i18n) as `ts/chats.ts`, about as long as the Rust it ports.

- `make-input.py`: the station's rows (what GET /chats gives) from a copy of a station's database; repeated up to
  2000; `vary` makes every branch run. Its output holds real chats: it is copied between test machines, never committed.
- `rust/`: the Rust core's own functions over that input, as the view calls them: the baseline, and the reference.
- `ts/chats.ts` (+ `build.mjs` for QuickJS with the catalog, `node-run.mjs` for V8); `compare.py`: outputs equal?

Results on studio (2026-10-03), median ms for the whole list, including turning it into the text the UI gets:

| rows | Rust core (Mac) | TS on V8 (Mac) | TS on QuickJS (Mac) | Rust core (Android emulator) | TS on QuickJS (Android emulator) |
|---|---|---|---|---|---|
| 342 (one station's real chats) | 9.3 | 5.1 | 25.4 | 12.0 | 25.5 |
| 2000 | 56.8 | 23.0 | 150.3 | 85.4 | 153.0 |

Equal outputs, field by field, between the Rust core and the TypeScript port on every engine, for the 342 real rows,
2000 rows and 2000 varied rows (cards, waits, failures, watches, Slack origins, several agents, …).
