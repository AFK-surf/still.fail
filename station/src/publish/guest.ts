// Visitors of published snapshots (docs/public-share.md), on ALPN `stillfail/guest/1`: no credential, nothing of the
// admin API; a stream asks for one snapshot (`{get, key}`) or one of its attachments (`{get, key, file}`) and is
// answered with a JSON head line, then that many bytes. A link that is gone and a key that is wrong are answered alike.
// The relays are shared by every station and device (cloud limits.ts), so a visitor reads what it came for and goes:
// a station holds few of them at once, answers few requests a minute, and drops one that idles.
import { createHash, timingSafeEqual } from "node:crypto";
import { open } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { log } from "../ops/log.ts";
import { wall } from "../ops/fibers.ts";
import type { Store } from "../store/store.ts";
import type { Connection, Stream } from "../mesh/native.ts";
import { Reader, writeLine } from "../mesh/serve.ts";
import { attachmentFile, snapshotFile } from "./index.ts";

export const GUEST_ALPN = Buffer.from("stillfail/guest/1");

export const LIMITS = {
  /// Visitors connected at once, to the whole station.
  connections: 16,
  /// Requests answered a minute, to the whole station.
  perMinute: 240,
  /// Streams being answered at once on one connection.
  streams: 4,
  /// A connection with nothing asked of it for this long is closed.
  idleMs: 30_000,
};

const CHUNK = 64 * 1024;
const ID = /^[A-Za-z0-9_-]{16}$/;
const KEY = /^[A-Za-z0-9_-]{43}$/;
const FILE = /^f\d{1,5}$/;

type Time = { now(): number; after(ms: number, f: () => void): () => void };

const digest = (s: string) => createHash("sha256").update(s).digest();

export class Guests {
  #store: Store;
  #time: Time;
  #limits: typeof LIMITS;
  #open = 0;
  #minute = -1;
  #asked = 0;
  /// The attachments' types of snapshots read lately, by id (a snapshot never changes).
  #types = new Map<string, Map<string, string>>();

  constructor(store: Store, time: Time = wall, limits: typeof LIMITS = LIMITS) {
    this.#store = store;
    this.#time = time;
    this.#limits = limits;
  }

  /// One visitor's connection: a request a stream, until it goes or idles; settled once each is answered.
  async serve(conn: Connection): Promise<void> {
    this.#open++;
    let active = 0;
    const answering: Promise<void>[] = [];
    let idle = () => {};
    const watch = () => {
      idle();
      idle = this.#time.after(this.#limits.idleMs, () => (active > 0 ? watch() : conn.close(0, "idle")));
    };
    watch();
    try {
      for (let stream = await conn.acceptBi(); stream; stream = await conn.acceptBi()) {
        watch();
        if (this.#open > this.#limits.connections || active >= this.#limits.streams || !this.#take()) {
          answering.push(this.#refuse(stream, "busy", "busy").catch(() => {}));
          continue;
        }
        active++;
        answering.push(
          this.#answer(stream)
            .catch((e) => log.info("guest", "request failed", { error: (e as Error).message }))
            .finally(() => {
              active--;
              watch();
            }),
        );
      }
      await Promise.all(answering);
    } finally {
      idle();
      this.#open--;
    }
  }

  /// A request of this minute's, if there is room for one.
  #take(): boolean {
    const minute = Math.floor(this.#time.now() / 60_000);
    if (minute !== this.#minute) {
      this.#minute = minute;
      this.#asked = 0;
    }
    if (this.#asked >= this.#limits.perMinute) return false;
    this.#asked++;
    return true;
  }

  async #refuse(stream: Stream, code: "gone" | "busy", error: string): Promise<void> {
    await writeLine(stream, { error, code });
    await stream.finish();
  }

  async #answer(stream: Stream): Promise<void> {
    const ask = await new Reader(stream).line();
    const id = typeof ask?.get === "string" ? ask.get : "";
    const key = typeof ask?.key === "string" ? ask.key : "";
    const file = ask?.file === undefined ? null : typeof ask.file === "string" ? ask.file : "";
    const published = ID.test(id) ? this.#store.published(id) : null;
    // A wrong key costs as long however much of it is right.
    if (published === null || !KEY.test(key) || !timingSafeEqual(digest(key), digest(published.key)) || (file !== null && !FILE.test(file))) {
      return this.#refuse(stream, "gone", "no such snapshot");
    }
    const path = file === null ? snapshotFile(this.#store, id) : attachmentFile(this.#store, id, file);
    let handle;
    try {
      handle = await open(path, "r");
    } catch {
      return this.#refuse(stream, "gone", "no such snapshot");
    }
    try {
      const size = (await handle.stat()).size;
      const type = file === null ? "application/json" : (this.#typeOf(id, file) ?? "application/octet-stream");
      await writeLine(stream, { ok: true, size, type });
      const buffer = Buffer.alloc(CHUNK);
      for (let at = 0; at < size; ) {
        const { bytesRead } = await handle.read(buffer, 0, Math.min(CHUNK, size - at), at);
        if (bytesRead === 0) break;
        await stream.write(Buffer.from(buffer.subarray(0, bytesRead)));
        at += bytesRead;
      }
      await stream.finish();
    } finally {
      await handle.close();
    }
  }

  /// An attachment's type, as its snapshot says.
  #typeOf(id: string, k: string): string | undefined {
    let types = this.#types.get(id);
    if (types === undefined) {
      types = new Map();
      try {
        const snapshot = JSON.parse(readFileSync(snapshotFile(this.#store, id), "utf8"));
        for (const e of Array.isArray(snapshot?.entries) ? snapshot.entries : []) {
          for (const f of Array.isArray(e?.files) ? e.files : []) if (typeof f?.k === "string" && typeof f?.type === "string") types.set(f.k, f.type);
        }
      } catch {}
      if (this.#types.size >= 32) this.#types.delete(this.#types.keys().next().value!);
      this.#types.set(id, types);
    }
    return types.get(k);
  }
}
