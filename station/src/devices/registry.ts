// The devices attached to this station (设备, 2026-11-10): a phone or a board on its USB, a camera, a printer or a router
// its network reaches, a serial port: what an agent uses that runs no station. Each was added by a member, whose it is,
// and is kept here, its host. A whole station is open to every chat of its workspace, so what is attached to it is
// too: no grant guards it, as none would keep an agent on this machine from its USB or its network (the user,
// 2026-11-10). One that should need its owner's approval is attached to a station that only runs tasks (rig/grants.ts).
import { randomBytes } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import { type Device, type DeviceKind, deviceRefusal } from "../../../client/core-ts/src/rig-form.ts";

/// A device as kept: what it is, its workspace, whose it is, when it was added.
export type Kept = Device & { ws: string; owner: string; owner_email: string; owner_name: string; at: number };

const SCHEMA = `CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  ws TEXT NOT NULL,
  body TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS devices_by_ws ON devices (ws);`;

/// The most devices one workspace attaches to one station.
export const DEVICES_MAX = 200;

export class DeviceRegistry {
  readonly #db: DatabaseSync;

  constructor(db: DatabaseSync) {
    this.#db = db;
    db.exec(SCHEMA);
  }

  /// The workspace's devices attached here, in the order they were added.
  of(ws: string): Kept[] {
    return (this.#db.prepare("SELECT body FROM devices WHERE ws = ? ORDER BY rowid LIMIT ?").all(ws, DEVICES_MAX) as { body: string }[]).map((r) => JSON.parse(r.body) as Kept);
  }

  get(ws: string, id: string): Kept | null {
    const row = this.#db.prepare("SELECT body FROM devices WHERE id = ? AND ws = ?").get(id, ws) as { body: string } | undefined;
    return row === undefined ? null : (JSON.parse(row.body) as Kept);
  }

  /// A device added by `by`: why not, or what was kept.
  add(ws: string, by: { sub: string; email: string; name: string }, given: { name: unknown; kind: unknown; target: unknown; baud?: unknown }, at: number): Kept | string {
    const d: Device = {
      id: randomBytes(8).toString("hex"),
      name: typeof given.name === "string" ? given.name.trim() : "",
      kind: given.kind as DeviceKind,
      target: typeof given.target === "string" ? given.target.trim() : "",
      ...(given.baud === undefined || given.baud === null || given.baud === "" ? {} : { baud: Number(given.baud) }),
    };
    const why = deviceRefusal(d);
    if (why !== null) return why;
    const all = this.of(ws);
    if (all.length >= DEVICES_MAX) return `a station holds ${DEVICES_MAX} devices at most`;
    if (all.some((x) => x.name.toLowerCase() === d.name.toLowerCase())) return `a device named ${d.name} is attached here already`;
    const kept: Kept = { ...d, ws, owner: by.sub, owner_email: by.email.toLowerCase(), owner_name: by.name, at };
    this.#db.prepare("INSERT INTO devices (id, ws, body) VALUES (?, ?, ?)").run(kept.id, ws, JSON.stringify(kept));
    return kept;
  }

  remove(ws: string, id: string): boolean {
    return Number(this.#db.prepare("DELETE FROM devices WHERE id = ? AND ws = ?").run(id, ws).changes) > 0;
  }
}
