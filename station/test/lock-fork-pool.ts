// What the fork-choice runners share (lock-fork-choice.test.ts, lock-roster.test.ts): a pool of worker threads that
// answer jobs, every job queued at once and handed out as threads come free, and the tables' printing. A job's worlds
// are seeded by the job alone: which thread runs it changes nothing of what it measures.
import { availableParallelism } from "node:os";
import { after } from "node:test";
import { Worker } from "node:worker_threads";

/// LOCK_FORK_WORKERS, by default as many as the machine runs at once (`availableParallelism`), at most 6: CI's runners
/// have few cores, and the station's tests run in slices of files there, one file at a time.
export const WORKERS = Number(process.env.LOCK_FORK_WORKERS ?? Math.max(1, Math.min(6, availableParallelism())));

/// Worker threads of `file` (which answers `{id, job}` with `{id, out}` where its `workerData` says so); `ask` queues a
/// job. The threads are let go once the file's tests are over.
export function pool<J>(file: URL, data: Record<string, unknown>): <T>(job: J) => Promise<T> {
  const workers = Array.from({ length: WORKERS }, () => new Worker(file, { workerData: data, execArgv: [] }));
  const waiting: { id: number; job: J; done: (out: any) => void; fail: (e: Error) => void }[] = [];
  const running = new Map<number, (typeof waiting)[number]>();
  const idle = [...workers];
  let ids = 0;
  const next = () => {
    while (idle.length > 0 && waiting.length > 0) {
      const w = idle.pop()!, j = waiting.shift()!;
      running.set(j.id, j);
      w.postMessage({ id: j.id, job: j.job });
    }
  };
  for (const w of workers) {
    w.on("message", (m: { id: number; out: unknown }) => {
      const j = running.get(m.id)!;
      running.delete(m.id);
      idle.push(w);
      j.done(m.out);
      next();
    });
    w.on("error", (e) => {
      for (const j of running.values()) j.fail(e);
    });
  }
  after(() => Promise.all(workers.map((w) => w.terminate())));
  return <T>(job: J) => new Promise<T>((done, fail) => {
    waiting.push({ id: ids++, job, done, fail });
    next();
  });
}

export const print = (line = "") => console.log(line);
export const pct = (n: number, of: number) => (of === 0 ? "-" : `${((100 * n) / of).toFixed(1)}%`);
export const mean = (xs: number[]) => (xs.length === 0 ? 0 : xs.reduce((a, b) => a + b, 0) / xs.length);
export const row = (cells: (string | number)[], widths: number[]) => cells.map((c, i) => String(c).padEnd(widths[i] ?? 10)).join(" ");
export const toldLines = (title: string, log: string[]) => {
  print(`  smallest world, ${title}:`);
  for (const line of log) print(`    ${line}`);
};
