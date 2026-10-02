# Prototype: Rust shell, TypeScript logic

The question: can the station keep Rust only as a fixed shell (iroh connections, SQLite, child processes) and run all
its logic in TypeScript, so that day-to-day changes need no Rust build?

- `shell/` (Rust): holds the iroh endpoint and its connections and a SQLite database; starts the logic as a child
  process and talks to it in JSON lines over stdin/stdout (protocol at the top of `shell/src/main.rs`). SIGHUP
  restarts the logic: the next one starts while the old keeps answering, takes new streams once ready, and the old
  finishes what it has and exits. A logic that dies has its unanswered streams handed to the next one.
- `logic/main.ts`: the "station". Answers each request with a SQLite insert and count, run by Node 22.18+ directly.
- `run.sh`: one client sends 600 requests over one iroh connection (10 ms apart) while the logic is restarted as is,
  restarted after its code changed (no cargo), and killed with `kill -9`.

Result on studio (2026-10-03, Node 22.20, 3 runs): 600/600 answered every run, the same connection open throughout,
slowest request about 115 ms (the requests the killed logic held, handed to the next one); logic start to ready
50–80 ms; first shell build 35 s, `target/` 836 MB.

Not settled here: a request handed on after a crash may have had effects already (the killed logic may have written
before dying), so handed-on writes need idempotency keys, as the station's admin writes have; streams (events,
previews) across the boundary need back-pressure; Android would run the same logic in an embedded engine (QuickJS).
