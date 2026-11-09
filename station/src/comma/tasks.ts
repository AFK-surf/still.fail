// The Comma Tasks a Comma connect's agents work in, kept in <data>/comma-tasks.json: for each connect, each Task by its
// address at Comma (`task`, as task.invite named it), the thread it is here (channel TASK, its ts made from the
// address), how it was started (who asked, the runtime and model it was asked to run), how far Comma gave it
// (`fetched`: task.put's `through`, what task.hello says) and through which Message the station's session answered it
// already (`answered`: Comma says so with an invite made again; those Messages are not handed to the session again).
import { createHash } from "node:crypto";
import { readFileSync, renameSync, writeFileSync } from "node:fs";
import { log } from "../ops/log.ts";

/// Where Comma Tasks are, as threads here.
export const TASK_CHANNEL = "TASK";

/// How a Task was started, as task.invite said: who asked (a Comma user's id), and what it asked to run.
export type Start = { requester: string; title: string | null; runtime: string | null; model: string | null };

export type Task = { task: string; threadTs: string; start: Start; fetched: number; answered: number; left?: true };

type Kept = Record<string, Record<string, Task>>;

/// A Task's thread ts, made of its address as a thread's ts reads (`<seconds>.<micros>`, what a thread address takes:
/// agents/instructions.ts parseThreadAddress), the same for the same Task.
export const threadTsOf = (task: string): string => {
  const h = createHash("sha256").update(task).digest();
  return `${h.readUInt32BE(0)}.${String(h.readUInt32BE(4) % 1_000_000).padStart(6, "0")}`;
};

export class CommaTasks {
  readonly path: string;
  private kept: Kept = {};

  constructor(path: string) {
    this.path = path;
    try {
      const v = JSON.parse(readFileSync(path, "utf8"));
      if (v !== null && typeof v === "object" && !Array.isArray(v)) this.kept = v;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") log.warn("comma", "comma tasks file unreadable; starting empty", { error: (error as Error).message });
    }
  }

  private save() {
    const tmp = `${this.path}.tmp`;
    try {
      writeFileSync(tmp, JSON.stringify(this.kept));
      renameSync(tmp, this.path);
    } catch (error) {
      log.warn("comma", "comma tasks not kept", { error: (error as Error).message });
    }
  }

  get(connect: string, task: string): Task | null {
    return this.kept[connect]?.[task] ?? null;
  }

  /// The Task whose thread here has this ts.
  byThread(connect: string, threadTs: string): Task | null {
    return Object.values(this.kept[connect] ?? {}).find((t) => t.threadTs === threadTs) ?? null;
  }

  /// The connect's Tasks it still takes part in (not left).
  taking(connect: string): Task[] {
    return Object.values(this.kept[connect] ?? {}).filter((t) => t.left !== true);
  }

  /// The station takes part in `task` (again, with an invite made again: what it answered through is kept as the most
  /// said).
  invited(connect: string, task: string, start: Start, answered: number): Task {
    const at = (this.kept[connect] ??= {});
    const had = at[task];
    const t: Task = { task, threadTs: had?.threadTs ?? threadTsOf(task), start, fetched: had?.fetched ?? 0, answered: Math.max(had?.answered ?? 0, answered) };
    at[task] = t;
    this.save();
    return t;
  }

  /// Comma gave the Task through `through`, and said its session answered it through `answered`.
  given(connect: string, task: string, through: number | null, answered: number | null) {
    const t = this.kept[connect]?.[task];
    if (!t) return;
    if (through !== null) t.fetched = Math.max(t.fetched, through);
    if (answered !== null) t.answered = Math.max(t.answered, answered);
    this.save();
  }

  /// The Task runs elsewhere now (task.leave): nothing of it is taken again.
  left(connect: string, task: string) {
    const t = this.kept[connect]?.[task];
    if (!t || t.left) return;
    t.left = true;
    this.save();
  }

  /// A connect removed: its Tasks with it.
  forget(connect: string) {
    if (!(connect in this.kept)) return;
    delete this.kept[connect];
    this.save();
  }
}
