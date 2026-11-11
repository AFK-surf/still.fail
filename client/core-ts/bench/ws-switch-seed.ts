// Two workspaces of real size (test/real-size.ts) of one account, in the former records store, which the core imports
// as it first starts: what apps/mbui/core/wsswitch.m switches between (apps/mbui/scripts/core.sh ws-switch).
// `node bench/ws-switch-seed.ts <dir> [scale]`; KEPT=<files>x<parts>: files of chats kept on the device as well.
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { Effect } from "effect";
import { NodeHost } from "../src/hosts/node.ts";
import { OPENS, fixture } from "../test/real-size.ts";

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
// first prefs there are, and everything reading a part of them is made again for it, which no real switch does)
rec("prefs", "device", { workspace: "ws", lang: "zh" });
rec("me", SUB, { workspaces: [{ id: "ws", name: "Acme" }, { id: "ws2", name: "Second" }], invitations: [], relay_url: null, user: { email: "me@x.com" } });
const counts: Record<string, number> = {};
for (const ws of ["ws", "ws2"]) {
  const all: [J, J][] = ws === "ws" ? fixture(NOW, OPENS) : JSON.parse(JSON.stringify(fixture(NOW, OPENS)).replaceAll('"ws/', '"ws2/'));
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
