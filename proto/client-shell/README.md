# Prototype: the client's Rust shell running a TypeScript core

The client half of ../shell-ts: can the app's core be TypeScript, written once, with Rust only as a fixed shell that
gives it iroh? On the web and desktop the TS runs in the page / Electron as is; Android is the hard case, so this runs
the core in QuickJS (rquickjs) inside the shell, the way the app's library would.

- `src/main.rs`: the shell. Network (iroh) on tokio's worker threads, the JS on its own thread; the core gets
  `host.connect/request` (promises), `emit` (to the UI), `now`, `log`, `save`.
- `core/core.ts`: the core. Fetches a station's chats, builds the chat list (filter, pin, sort, sections, relative
  times), and rebuilds and emits it whole on each of 200 changes and 5 searches.
- `core/node-bench.mjs`: the same work on V8, for comparison. `run.sh`: all of it on studio, plus an Android emulator.

Results on studio (2026-10-03; Android = arm64 emulator on the Mac, so a real phone is slower), ms per rebuild of the
whole list, including JSON for the UI:

| chats | V8 (Node, Mac) | QuickJS (Mac) | QuickJS (Android emulator) |
|---|---|---|---|
| 500  | 0.4 | 1.9 | 5.1 |
| 2000 | 1.6 | 8.2 | 21.2 |

Round trip of a small request core → shell → iroh → station and back: 0.2 ms (Mac), 0.7–1.3 ms (emulator).
Android binary 14 MB stripped (iroh + QuickJS; QuickJS's static lib is 2 MB). rquickjs ships no Android bindings:
built with its `bindgen` feature against the NDK (run.sh).

Not settled: a real phone's numbers; QuickJS has no `Intl` (dates, plurals, collation must come from the shell or
a JS library); the real core sends the UI changes rather than whole lists, which is what would keep 2000 chats under
a frame on Android.
