// A heap snapshot of the running station, asked for from the command line (`stillfail heap`): what its main thread's
// memory holds, to be opened in Chrome's DevTools (Memory). The command leaves a request in <data>/run; the station,
// which watches that directory, writes the snapshot beside it and says where in an answer. It holds whatever the
// station holds (tokens too), so it is the owner's alone (0600), and only the latest is kept. Taking it holds the
// station for a few seconds.
//
// What a directory's watcher says is not counted on (macOS's FSEvents coalesces a file written and renamed into an
// event named after either, and one that starts a moment after a file came does not tell of it): any event makes the
// station look for a request, and the command touches its request until it is taken and reads its answer as it waits.
import { createWriteStream, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, utimesSync, watch } from "node:fs";
import { join } from "node:path";
import { pipeline } from "node:stream/promises";
import { getHeapSnapshot } from "node:v8";
import { writePrivate } from "./files.ts";
import { log } from "./log.ts";
import { wall } from "./fibers.ts";

const REQUEST = "heap.request";
const ANSWER = "heap.answer";
const SNAPSHOT = /^heap-.*\.heapsnapshot$/;
/// How long the command waits for the station's answer.
const WAIT_MS = 120_000;
/// How often the command looks for its answer, and touches its request while it is not taken.
const LOOK_MS = 250;

export type HeapAnswer = { path: string; bytes: number; ms: number } | { error: string };

const runDir = (data: string) => join(data, "run");

/// Takes a snapshot each time one is asked for, as long as the station runs; how to stop.
export function answerHeapRequests(data: string): () => void {
  const dir = runDir(data);
  mkdirSync(dir, { recursive: true });
  let taking = false;
  const take = async () => {
    if (taking) return;
    // Claimed by renaming it: two station processes (a handover) see it, one takes it.
    const claimed = join(dir, `${REQUEST}.${process.pid}`);
    try {
      renameSync(join(dir, REQUEST), claimed);
    } catch {
      return;
    }
    taking = true;
    rmSync(claimed, { force: true });
    const path = join(dir, `heap-${new Date(wall.now()).toISOString().replace(/[:.]/g, "-")}.heapsnapshot`);
    const started = wall.now();
    let answer: HeapAnswer;
    try {
      for (const name of readdirSync(dir)) if (SNAPSHOT.test(name)) rmSync(join(dir, name), { force: true });
      await pipeline(getHeapSnapshot(), createWriteStream(path, { mode: 0o600 }));
      answer = { path, bytes: statSync(path).size, ms: wall.now() - started };
      log.info("heap", "heap snapshot written", answer);
    } catch (error) {
      rmSync(path, { force: true });
      answer = { error: (error as Error).message };
      log.warn("heap", "heap snapshot not written", answer);
    } finally {
      taking = false;
    }
    writePrivate(join(dir, ANSWER), JSON.stringify(answer));
    // One asked for while this one was being taken.
    void take();
  };
  const watcher = watch(dir, () => void take());
  watcher.on("error", (error) => log.warn("heap", "not watching for heap snapshot requests", { error: String(error) }));
  // One asked for while no station ran.
  void take();
  return () => watcher.close();
}

/// `stillfail-station heap`: asks the running station for a snapshot and waits for its answer; the exit code.
export async function heapCommand(data: string, waitMs = WAIT_MS): Promise<number> {
  const dir = runDir(data);
  const request = join(dir, REQUEST);
  const answerPath = join(dir, ANSWER);
  rmSync(answerPath, { force: true });
  writePrivate(request, String(process.pid));
  let answer: HeapAnswer | null = null;
  for (const until = wall.now() + waitMs; wall.now() < until; ) {
    if (existsSync(answerPath)) {
      answer = JSON.parse(readFileSync(answerPath, "utf8")) as HeapAnswer;
      break;
    }
    // Not taken yet: told again (a station whose watcher missed it, or started after it); taken, it is gone.
    try {
      const now = new Date(wall.now());
      utimesSync(request, now, now);
    } catch {}
    await wall.sleep(LOOK_MS);
  }
  rmSync(answerPath, { force: true });
  if (answer === null) {
    rmSync(request, { force: true });
    console.error("the station did not answer: is it running on this data directory?");
    return 1;
  }
  if ("error" in answer) {
    console.error(`the station could not write a heap snapshot: ${answer.error}`);
    return 1;
  }
  console.log(`${answer.path} (${Math.round(answer.bytes / 1048576)} MB, ${answer.ms} ms)`);
  return 0;
}
