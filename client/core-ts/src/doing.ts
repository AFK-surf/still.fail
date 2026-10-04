// What a person set going on this device and the core has not finished (the `doing` topic; doing.rs): every call that
// changes something, from the moment it is asked until its answer. One that failed stays a few seconds more, with why.
import { t } from "./i18n.ts";

type Entry = { id: number; call: string; params: Map<string, string>; since: number; failed: string | null };

/// How long a failure stays where it was asked.
export const FAILED_SHOWN_MS = 6_000;

export class Doing {
  #next = 0;
  #list: Entry[] = [];

  /// One begun; `end` it with what this gives.
  start(call: string, params: unknown, now: number): number {
    const id = ++this.#next;
    const plain = new Map<string, string>();
    if (params !== null && typeof params === "object" && !Array.isArray(params)) {
      for (const [k, v] of Object.entries(params)) {
        const w = words(v);
        if (w !== null) plain.set(k, w);
      }
    }
    this.#list.push({ id, call, params: plain, since: now, failed: null });
    return id;
  }

  end(id: number): void {
    this.#list = this.#list.filter((e) => e.id !== id);
  }

  fail(id: number, why: string): void {
    const e = this.#list.find((e) => e.id === id);
    if (e) e.failed = why;
  }

  /// The topic's value: what is under way, oldest first.
  value(rechecking: (params: Map<string, string>) => boolean): unknown {
    const doing = this.#list.map((e) => {
      const stage = e.failed !== null ? "failed" : rechecking(e.params) ? "rechecking" : "running";
      const item: Record<string, unknown> = { call: e.call, params: Object.fromEntries(e.params), since: Math.trunc(e.since), stage };
      if (stage === "rechecking") item.note = t("core-misc.doing.rechecking");
      if (e.failed !== null) item.error = e.failed;
      return item;
    });
    return { doing };
  }
}

function words(v: unknown): string | null {
  if (typeof v === "string") return v;
  if (typeof v === "number") return Number.isInteger(v) ? String(v) : rustFloat(v);
  if (typeof v === "boolean") return String(v);
  return null;
}

/// A float as serde_json's Number prints it (1.5, 1e21 as 1e21).
function rustFloat(v: number): string {
  return String(v);
}

/// Calls whose params are too big to keep a copy of while they run.
export function heavy(name: string): boolean {
  return ["station.upload", "station.upload.part", "station.preview", "preview.socket.send", "draft.put", "chat.send", "migrate", "push.register"].includes(name);
}
