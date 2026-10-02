// What the admin API's reads give over a station's database, printed as the station would answer them: for comparing
// with the Rust station's responses.
//
// node src/dump.ts <data dir | db> <viewer email> [archived]                GET /chats (?archived=1)
// node src/dump.ts <data dir | db> <viewer email> entries <thread> [query]  GET /threads/<thread>/entries?<query>
//
// A data directory as a station's: stillfail.db, archive/threads/, config.json. A database path (*.db) is read with
// the directory it is in as its data directory.
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { HttpError, chats, entries, makeStore, openStore } from "./admin/views.ts";

const [path, email, what, thread, query] = process.argv.slice(2);
if (!path || !email) {
  console.error("usage: dump.ts <data dir | db> <viewer email> [archived | entries <thread> [query]]");
  process.exit(2);
}
const station = path.endsWith(".db") ? makeStore(new DatabaseSync(path, { readOnly: true }), dirname(path)) : openStore(path);
const viewer = { sub: "", email, name: "", role: "", workspace: "", device: "" };

/// admin/mod.rs `percent_decode`: `%xx` as a byte, `+` a space, the rest as it is; then UTF-8, lossily.
function percentDecode(s: string): string {
  const bytes = Buffer.from(s, "utf8");
  const out: number[] = [];
  for (let i = 0; i < bytes.length; ) {
    const hex = bytes.subarray(i + 1, i + 3).toString("latin1");
    if (bytes[i] === 0x25 && /^\+?[0-9a-fA-F]{1,2}$/.test(hex) && hex.length === 2) {
      out.push(parseInt(hex, 16));
      i += 3;
    } else if (bytes[i] === 0x2b) {
      out.push(0x20);
      i += 1;
    } else {
      out.push(bytes[i]!);
      i += 1;
    }
  }
  return new TextDecoder("utf-8").decode(Buffer.from(out));
}

/// admin/mod.rs `query_pairs`.
const queryPairs = (q: string): [string, string][] =>
  q
    .replace(/^\?/, "")
    .split("&")
    .filter((p) => p !== "")
    .map((p) => {
      const at = p.indexOf("=");
      return at < 0 ? [percentDecode(p), ""] : [percentDecode(p.slice(0, at)), percentDecode(p.slice(at + 1))];
    });

try {
  if (what === "entries") {
    // The route's own check: a thread id is an i64.
    if (!thread || !/^[+-]?\d+$/.test(thread)) throw new HttpError(404, `unknown thread ${thread}`);
    console.log(JSON.stringify(entries(station, viewer, Number(thread), queryPairs(query ?? ""))));
  } else {
    console.log(JSON.stringify(chats(station, viewer, what === "archived")));
  }
} catch (error) {
  const status = error instanceof HttpError ? error.status : 500;
  console.log(JSON.stringify({ error: (error as Error).message }));
  console.error(`status ${status}`);
  process.exit(1);
}
