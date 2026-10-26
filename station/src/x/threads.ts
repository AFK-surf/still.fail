// Where an X connect is in what was said to it (docs/x.md), kept in <data>/x-threads.json: the newest mention it has
// read (what it asks for after, so mentions made while the station was away are read once it is back), when it began
// reading (before any mention: what was said before then is not its), and in each conversation the latest mention of
// it there, which its agent's words answer.
import { readFileSync, renameSync, writeFileSync } from "node:fs";
import { log } from "../ops/log.ts";

type Of = { since?: string; began?: number; replyTo?: Record<string, string> };

/// X's ids are 64-bit numbers in decimal: the later, the greater.
export const later = (a: string, b: string) => a.length !== b.length ? a.length > b.length : a > b;

export class XThreads {
  readonly path: string;
  private kept: Record<string, Of> = {};

  constructor(path: string) {
    this.path = path;
    try {
      const v = JSON.parse(readFileSync(path, "utf8"));
      if (v !== null && typeof v === "object" && !Array.isArray(v)) this.kept = v;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") log.warn("x", "x threads file unreadable; starting empty", { error: (error as Error).message });
    }
  }

  private of(connect: string): Of {
    return (this.kept[connect] ??= {});
  }

  private save() {
    const tmp = `${this.path}.tmp`;
    try {
      writeFileSync(tmp, JSON.stringify(this.kept));
      renameSync(tmp, this.path);
    } catch (error) {
      log.warn("x", "x threads not kept", { error: (error as Error).message });
    }
  }

  /// The newest mention read, if any.
  since(connect: string): string | null {
    return this.kept[connect]?.since ?? null;
  }

  /// When the connect began reading (ms), set the first time it is asked.
  began(connect: string, now: number): number {
    const at = this.of(connect);
    if (typeof at.began !== "number") {
      at.began = now;
      this.save();
    }
    return at.began!;
  }

  /// Mentions up to `id` are read.
  read(connect: string, id: string) {
    const at = this.of(connect);
    if (at.since !== undefined && !later(id, at.since)) return;
    at.since = id;
    this.save();
  }

  /// The post the agent's words in a conversation answer: the latest mention heard there.
  replyTo(connect: string, conversation: string): string | null {
    return this.kept[connect]?.replyTo?.[conversation] ?? null;
  }

  heard(connect: string, conversation: string, post: string) {
    const replies = (this.of(connect).replyTo ??= {});
    const had = replies[conversation];
    if (had !== undefined && !later(post, had)) return;
    replies[conversation] = post;
    // The oldest conversations go once there are many.
    const keys = Object.keys(replies);
    if (keys.length > 2000) for (const k of keys.slice(0, keys.length - 2000)) delete replies[k];
    this.save();
  }
}
