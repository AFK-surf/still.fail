// What the Rust core kept on the device (client/core-ts/src/kept.ts), read once into records. The Rust core kept threads'
// entries and sessions' transcripts in host storage, in chunks of 256: `thread/<station>/<thread>/<chunk>` (entries
// numbered from 1), `transcript/<station>/<session>/<chunk>` (items from 0), `<log>/meta` the run `{first, last}` it
// holds, and `kept` the index of every log (`{station, opened, chunks: {chunk: bytes}}`). The TS core keeps them as
// `entry`/`transcript` records (data.ts); the first start reads what the Rust core kept into them, so a chat opens from
// the device as it did. What is there is left as it was (the Rust core, if it runs again, still reads it); `kept-read`
// says it was read.
import { Effect } from "effect";
import type { Data } from "./data.ts";
import type { Host } from "./host.ts";
import { parseJson } from "./util.ts";

export const CHUNK = 256;
const INDEX = "kept";
const READ = "kept-read";

type J = any;

const get = (host: Host, key: string): Effect.Effect<unknown> =>
  Effect.map(Effect.orElseSucceed(host.storageGet(key), () => null), (b) => (b ? parseJson(b) : undefined));

/// Reads what the Rust core kept into records, once per device.
export function readKept(host: Host, data: Data): Effect.Effect<void> {
  return Effect.gen(function* () {
    if ((yield* get(host, READ)) !== undefined) return;
    const index = (yield* get(host, INDEX)) as J;
    if (index && typeof index === "object") {
      for (const [name, item] of Object.entries(index as Record<string, J>)) {
        yield* readLog(host, data, name, item);
      }
    }
    yield* Effect.ignore(host.storageSet(READ, new TextEncoder().encode("1")));
  });
}

function readLog(host: Host, data: Data, name: string, item: J): Effect.Effect<void> {
  return Effect.gen(function* () {
    const station = typeof item?.station === "string" ? item.station : null;
    if (!station) return;
    const table = name.startsWith(`thread/${station}/`) ? "entry" : name.startsWith(`transcript/${station}/`) ? "transcript" : null;
    if (!table) return;
    const id = name.slice((table === "entry" ? "thread/" : "transcript/").length + station.length + 1);
    const base = table === "entry" ? 1 : 0;
    const held = (yield* get(host, `${name}/meta`)) as J;
    const first = Number(held?.first);
    const last = Number(held?.last);
    if (!Number.isInteger(first) || !Number.isInteger(last) || last < first) return;
    const items: [number, unknown][] = [];
    for (let chunk = Math.floor((first - base) / CHUNK); chunk <= Math.floor((last - base) / CHUNK); chunk++) {
      const start = Math.max(chunk * CHUNK + base, first);
      const end = Math.min(chunk * CHUNK + base + CHUNK - 1, last);
      const entries = (yield* get(host, `${name}/${chunk}`)) as J;
      // As kept.rs reads a chunk: all of it there, and a thread's entries each where its `n` says.
      if (!Array.isArray(entries) || entries.length !== end + 1 - start) return;
      if (table === "entry" && entries.some((e: J, i: number) => e?.n !== start + i)) return;
      entries.forEach((e: unknown, i: number) => items.push([start + i, e]));
    }
    yield* data.putItems(table, station, id, items);
  });
}
