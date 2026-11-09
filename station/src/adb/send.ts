// phone_send: a file sent to a granted phone the way a chat's file is downloaded (GET /sessions/:key/parts, the phone
// fetching it a part at a time), not over adb, whose every packet waits for the phone's OKAY across the link (the phone's
// own session has no delayed_ack: client/shell adb.rs) and whose push begins again from nothing when a tunnel breaks.
// The file is put in the session's uploads under a name of its content, so a fetch cut short goes on from what the
// phone has of it when asked again.
import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { copyFile, mkdir, rename, stat } from "node:fs/promises";
import { basename, isAbsolute, join } from "node:path";
import { wall } from "../ops/fibers.ts";
import type { Connection, Stream } from "../mesh/native.ts";
import { Reader, writeLine } from "../mesh/serve.ts";

/// How long the phone has to take the fetch's stream.
const FETCH_OPEN = 10_000;

/// `given` (absolute, or in the session's `workspace`) in its uploads as `<sha256 prefix>-<name>`: its name there and size.
export async function staged(workspace: string, given: string): Promise<{ name: string; size: number }> {
  const path = isAbsolute(given) ? given : join(workspace, given);
  const meta = await stat(path).catch(() => null);
  if (meta === null) throw new Error(`no such file: ${given}`);
  if (!meta.isFile()) throw new Error(`not a file: ${given}`);
  const hash = createHash("sha256");
  for await (const piece of createReadStream(path)) hash.update(piece as Buffer);
  const safe = Array.from(basename(path)).map((c) => (c === "\\" || c === "/" || c.codePointAt(0)! < 0x20 ? "_" : c)).join("");
  const name = `${hash.digest("hex").slice(0, 16)}-${safe}`;
  const dir = join(workspace, "uploads");
  const at = join(dir, name);
  if ((await stat(at).catch(() => null))?.size !== meta.size) {
    await mkdir(dir, { recursive: true });
    await copyFile(path, `${at}.part`);
    await rename(`${at}.part`, at);
  }
  return { name, size: meta.size };
}

/// What the phone said of a fetch: where it put the file, or why it stopped and how much it has.
export type Fetched = { path: string } | { error: string; at: number; old: boolean };

/// The phone on `conn` asked to fetch session `key`'s upload `name` (`size` bytes); `heard` as each part comes.
export async function fetchOnPhone(conn: Connection, key: string, name: string, size: number, heard?: (at: number) => void, signal?: AbortSignal): Promise<Fetched> {
  let stream: Stream | null = null;
  const abort = () => void stream?.reset(0).catch(() => {});
  signal?.addEventListener("abort", abort, { once: true });
  let at = 0;
  try {
    stream = await wall.within(FETCH_OPEN, conn.openBi(), "the phone did not take the file");
    await writeLine(stream, { fetch: { key, name, size } });
    await stream.finish();
    const reader = new Reader(stream);
    for (;;) {
      const said = await reader.line();
      if (said === null) return { error: "the phone ended the fetch", at, old: false };
      if (typeof said.path === "string") return { path: said.path };
      if (typeof said.error === "string") {
        // An app from before fetches takes the stream for a tunnel of a kind it does not know.
        return { error: said.error, at: typeof said.at === "number" ? said.at : at, old: said.at === undefined && said.error === "无法识别的通道" };
      }
      if (typeof said.at === "number") {
        at = said.at;
        heard?.(at);
      }
    }
  } catch (error) {
    if (signal?.aborted) throw error;
    return { error: (error as Error).message, at, old: false };
  } finally {
    signal?.removeEventListener("abort", abort);
  }
}
