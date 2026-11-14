// Two workspaces of real size (test/real-size.ts) of one account, in the former records store, which the core imports
// as it first starts: what apps/mbui/core/wsswitch.m switches between (apps/mbui/scripts/core.sh ws-switch).
// `node bench/ws-switch-seed.ts <dir> [scale]`; KEPT=<files>x<parts>: files of chats kept on the device as well;
// WS2_LANDS=new: ws2 left with no chat open, so 大屏's frame lands on a new chat there (what reads `stations` first);
// STATIONS=up: each workspace's four stations up as the device last found them (its `link` records "online", link.ts:
// taken for up until its link finds out anew), what apps/mbui/core/wsswitch.m keeps so by a network that never answers.
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { Effect } from "effect";
import { NodeHost } from "../src/hosts/node.ts";
import { CHAT, fixture } from "../test/real-size.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const [, , dir, scaleArg] = process.argv;
if (!dir) throw new Error("usage: ws-switch-seed.ts <dir> [scale]");
const scale = Number(scaleArg ?? "1");
const SUB = "s1";
const SEP = "\u0001";
const NOW = Date.now();

mkdirSync(dir, { recursive: true });
const host = new NodeHost(dir, "http://127.0.0.1:9", false, () => {});
const nowS = Math.floor(NOW / 1000);
await Effect.runPromise(host.storageSet("accounts", new TextEncoder().encode(JSON.stringify([{ sub: SUB, email: "me@x.com", name: "Sam", picture: "", access: "a", refresh: "r", access_expires: nowS + 365 * 86400 }]))));
const db = new DatabaseSync(join(dir, "core.db"));
db.exec("PRAGMA journal_mode = WAL; CREATE TABLE IF NOT EXISTS records (tbl TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (tbl, key)) WITHOUT ROWID;");
const put = db.prepare("INSERT OR REPLACE INTO records (tbl, key, value) VALUES (?, ?, ?)");
const enc = new TextEncoder();
const rec = (tbl: string, key: string, value: unknown) => put.run(tbl, key, enc.encode(JSON.stringify(value)));
db.exec("BEGIN");
// (the device's prefs as a device that was used has them: without, the first switch's write of `workspace` is the
// first prefs there are, and everything reading a part of them is made again for it, which no real switch does. ws2 was
// left on its chat of real size (`openChat`, workspaceMarks' `chat`): the wide frame lands on it there, on a new chat
// in ws; with WS2_LANDS=new on a new chat there too)
const ws2Lands = process.env.WS2_LANDS ?? "chat";
const stationsUp = (process.env.STATIONS ?? "down") === "up";
if (!["up", "down"].includes(process.env.STATIONS ?? "down")) throw new Error(`STATIONS=${process.env.STATIONS}: up or down`);
if (ws2Lands !== "chat" && ws2Lands !== "new") throw new Error(`WS2_LANDS=${ws2Lands}: chat or new`);
rec("prefs", "device", { workspace: "ws", lang: "zh", ...(ws2Lands === "chat" ? { openChat: { ws2: { station: "ws2/maple", key: CHAT.keys[0] } } } : {}) });
rec("me", SUB, { workspaces: [{ id: "ws", name: "Acme" }, { id: "ws2", name: "Second" }], invitations: [], relay_url: null, user: { email: "me@x.com" } });
const counts: Record<string, number> = {};
for (const ws of ["ws", "ws2"]) {
  // (the chat with all its messages: where it opens, its first unread, is on the device, so it opens without its station)
  const all: [J, J][] = ws === "ws" ? fixture(NOW) : JSON.parse(JSON.stringify(fixture(NOW)).replaceAll('"ws/', '"ws2/'));
  for (const [topic, value] of all) {
    const st = topic.station as string;
    const list = (table: string, idOf: (v: J) => string) => {
      const rows: J[] = [];
      for (let r = 0; r < scale; r++) for (const v of value as J[]) rows.push(r === 0 ? v : table === "thread" ? { ...v, id: v.id + r * 100000 } : table === "session_summary" ? { ...v, key: `${v.key}-${r}` } : { ...v, id: `${v.id}-${r}`, session: `${v.session}-${r}`, thread: typeof v.thread === "number" ? v.thread + r * 100000 : v.thread });
      rec("list", `${table}${SEP}${st}`, rows.map(idOf));
      for (const v of rows) rec(table, `${st}${SEP}${idOf(v)}`, v);
      counts[`${ws} ${table}`] = (counts[`${ws} ${table}`] ?? 0) + rows.length;
    };
    switch (topic.topic) {
      case "workspace":
        rec("workspace", ws, { ...value, id: ws, stations: value.stations.map((s: J, i: number) => ({ ...s, online: i < 4 })) });
        if (stationsUp) for (const [i, s] of (value.stations as J[]).entries()) if (i < 4) rec("link", `${ws}/${s.id}`, "online");
        break;
      case "overview":
        rec("overview", st, value);
        break;
      case "stationUsage":
        rec("usage", st, value);
        break;
      case "sessions":
        list("session_summary", (v) => String(v.key));
        break;
      case "threads":
        list("thread", (v) => String(v.id));
        break;
      case "chatRows":
        list("row", (v) => String(v.id));
        break;
      case "archivedRows":
        list("archived_row", (v) => String(v.id));
        break;
      // the chat's messages, held on the device as its log (db/import.ts reads `entry` <station>, <thread>, <n>)
      case "thread":
        for (const e of value.entries as J[]) rec("entry", `${st}${SEP}${topic.thread}${SEP}${e.n}`, e);
        counts[`${ws} entry`] = (counts[`${ws} entry`] ?? 0) + value.entries.length;
        break;
    }
  }
}
db.exec("COMMIT");
db.close();
host.close();
// What the device keeps of files opened in chats (drive-kept.ts): KEPT=<files>x<parts>, each kept whole, read a month ago.
const [files, parts] = (process.env.KEPT ?? "0x0").split("x").map(Number) as [number, number];
if (files > 0) {
  mkdirSync(join(dir, "databases"), { recursive: true });
  const kept = new DatabaseSync(join(dir, "databases", "drive-kept.db"));
  kept.exec(`PRAGMA journal_mode = WAL; CREATE TABLE IF NOT EXISTS kept (
    id TEXT PRIMARY KEY, kind TEXT NOT NULL, mtime INTEGER NOT NULL, size INTEGER NOT NULL, type TEXT NOT NULL, used INTEGER NOT NULL
  ); CREATE TABLE IF NOT EXISTS part (
    id TEXT NOT NULL, at INTEGER NOT NULL, length INTEGER NOT NULL, key TEXT NOT NULL, PRIMARY KEY (id, at, length)
  );`);
  const putKept = kept.prepare("INSERT INTO kept (id, kind, mtime, size, type, used) VALUES (?, ?, ?, ?, ?, ?)");
  const putPart = kept.prepare("INSERT INTO part (id, at, length, key) VALUES (?, ?, ?, ?)");
  const PART = 1024 * 1024;
  kept.exec("BEGIN");
  for (let f = 0; f < files; f++) {
    const id = `chat\nws/maple\nk-maple-${f % 100}\n截屏 2026-10-${String(f % 28 + 1).padStart(2, "0")} ${f}.png`;
    putKept.run(id, "chat", 0, parts * PART, "image/png", NOW - 30 * 86400_000 - f * 1000);
    for (let i = 0; i < parts; i++) putPart.run(id, i * PART, PART, `drive-kept-${f.toString(16).padStart(12, "0")}${i.toString(16).padStart(12, "0")}`);
  }
  kept.exec("COMMIT");
  kept.close();
}
console.log(JSON.stringify({ seeded: dir, scale, counts, kept: { files, parts } }));
process.exit(0);
