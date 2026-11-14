// Stations keeping the agents' memory (src/share/memory.ts) for a test: each a directory of its own, a cloud that only
// lists who is in the workspace, the station transport a direct call. A station can be off (it answers nothing) or
// started again from what it wrote to its disk.
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Cloud } from "../src/cloud/state.ts";
import { MemorySync } from "../src/share/memory.ts";

export type MemoryStation = { id: string; name: string; data: string; home: string; sync: MemorySync; up: boolean };

export function memoryWorld(stations: { id: string; name: string }[]) {
  const all = new Map<string, MemoryStation>();
  const peers = stations.map((s) => ({ id: s.id, name: s.name }));
  const cloudFor = (station: string, name: string) =>
    Object.defineProperties(Object.create(Cloud.prototype), Object.getOwnPropertyDescriptors({
      peersCurrent: true,
      lock: null,
      get state() {
        return { station, name, workspace: "w", workspace_name: "w", peers, revocations: [], joined: [] } as any;
      },
      listen() {
        return () => {};
      },
    })) as Cloud;
  const make = (id: string, name: string, data: string, home: string) =>
    new MemorySync({
      data,
      cloud: cloudFor(id, name),
      agentHome: () => home,
      still: true,
      ask: async (to, ws, request) => {
        const other = all.get(to);
        if (!other || !other.up) throw new Error("peer unavailable");
        return JSON.parse(JSON.stringify(await other.sync.handle(id, request, ws)));
      },
    });
  for (const { id, name } of stations) {
    const data = mkdtempSync(join(tmpdir(), "memory-"));
    const home = join(data, "agent");
    mkdirSync(join(home, "skills"), { recursive: true });
    all.set(id, { id, name, data, home, sync: make(id, name, data, home), up: true });
  }
  return {
    all,
    at: (id: string) => all.get(id)!,
    /// Each station given (that is up) looks at its files and brings every other level, one after another.
    async level(...order: string[]) {
      for (const id of order) if (all.get(id)!.up) await all.get(id)!.sync.levelNow();
    },
    /// A station started again from what it wrote (`change`: what is done to its disk while it is stopped).
    async restart(id: string, change: (s: MemoryStation) => void = () => {}) {
      const s = all.get(id)!;
      await s.sync.stop();
      change(s);
      s.sync = make(s.id, s.name, s.data, s.home);
    },
    async done() {
      for (const s of all.values()) {
        await s.sync.stop();
        rmSync(s.data, { recursive: true, force: true });
      }
    },
  };
}

export const writeAt = (s: MemoryStation, path: string, text: string) => {
  mkdirSync(join(s.home, path, ".."), { recursive: true });
  writeFileSync(join(s.home, path), text);
};
export const readAt = (s: MemoryStation, path: string) => (existsSync(join(s.home, path)) ? readFileSync(join(s.home, path), "utf8") : null);

/// A record put in a stopped station's kept state as a station of before would have written it (with its content kept).
export function keepRecord(s: MemoryStation, path: string, content: string, rec: { at: number; by: string; origin?: true }) {
  const bytes = Buffer.from(content, "utf8");
  const hash = createHash("sha256").update(bytes).digest("hex");
  const dir = join(s.data, "share", "memory");
  mkdirSync(join(dir, "blobs"), { recursive: true });
  writeFileSync(join(dir, "blobs", hash), bytes);
  const file = join(dir, "w.json");
  const kept = JSON.parse(readFileSync(file, "utf8"));
  kept.files[path] = { hash, at: rec.at, by: rec.by, prev: [], size: bytes.length, mode: 0o644, ...(rec.origin ? { origin: true } : {}) };
  writeFileSync(file, JSON.stringify(kept));
}
