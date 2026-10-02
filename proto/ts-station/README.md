# Prototype: the station in TypeScript, its iroh a prebuilt Rust addon

- `native/`: the station's iroh as a Node addon (napi-rs): its endpoint as mesh/station makes it (key, relays, mDNS,
  DHT, cubic), connections and streams. Built once per release of it; the TypeScript never rebuilds it.
- `src/main.ts`: the mesh's wire format and member credentials (mesh/station/src/main.rs `serve`, `verify_member`,
  `relay_request`), and the admin API's reads in this process. `src/admin/`: `GET /chats` (and `?archived=1`) and
  `GET /threads/:id/entries`, ported from mesh/app/src/admin/views.rs and store.rs over the station's own
  stillfail.db and archive files. Node 24 runs it as is, or built by esbuild, rolldown or oxc-transform.
- `load/`: a test workspace's keys for a station (`setup`), and a member's client (`ask`, `load`).

Results on studio (2026-10-03), one station's real database (copied; agents stopped, attachments dropped), the Rust
station being the released binary on the same data:

- Same answers: 53 requests (`/chats`, archived, entries with every parameter, an unknown thread) equal field for field.
- Builds: Rust station (no sccache) release cold 77 s, one line 29 s; dev cold 48 s, one line 3 s; target/ 3.1 G.
  TypeScript (1550 lines): pnpm install 1.1 s, node_modules 67 M (pnpm store links); tsgo check 84 ms; esbuild 24 ms,
  rolldown 78 ms, oxc-transform 38 ms; output 46–48 K. The addon: 48 s once, 13 MB, native/target 575 M.
- One request at a time: /chats 115 ms Rust, 129 ms TS; archived 123 / 137 ms; entries 0.16 / 0.25 ms.
- 8 at a time for 30 s (chats, archived, 8 chats' entries): Rust idle 38 MB, peak 93 MB, 41/s, p50 6 ms, p95 920 ms.
  TS run as .ts idle 99 MB (Node's type stripper), built 62–63 MB; peak 300–313 MB (V8's heap grows), 172 MB with
  `--max-old-space-size=96 --max-semi-space-size=2`; 37–38/s; p50 135–260 ms, p95 400–520 ms: one thread, so a heavy
  request holds the rest up (Rust answers the light ones meanwhile on other threads).
