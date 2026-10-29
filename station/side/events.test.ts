// GET /events following a job's log by its real watch (fs.watch): the OS tells of the growth, when it does, so it runs
// beside the checks (`pnpm test:side`). test/events.test.ts covers the rest, on a TestClock. Its time a TestClock here
// too, moved only by the watch's own 200 ms wait: the 5 s look never comes, so a log told again was told by the watch,
// however long the OS took to say so (a wall-clock bound of 4 s failed on mini1 under load, main b1ee5247, 40817480230).
import assert from "node:assert/strict";
import { appendFileSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Events } from "../src/api/events.ts";
import { testClock } from "../test/hub-fakes.ts";

const viewer = { sub: "a@x", email: "a@x", name: "a@x", role: "member", workspace: "w", device: "d" };
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

test("a job's log is told as it grows, by its watch (before the 5 s look)", async () => {
  const dir = mkdtempSync(join(tmpdir(), "events-"));
  const time = testClock();
  const events = new Events({
    clock: time.clock,
    readers: { read: async () => "[]" } as any,
    subscribe: () => () => {},
    host: async () => ({}),
    jobLog: (id) => (id === "j" ? join(dir, "j.log") : null),
    tail: (path) => readFileSync(path, "utf8"),
    outputAt: () => 7,
    sessionExists: () => true,
  });
  writeFileSync(join(dir, "j.log"), "one\n");
  const it = ((await events.open(viewer, "zh", false, [], [["j", 50]])).body as AsyncIterableIterator<Buffer>)[Symbol.asyncIterator]();
  const texts: string[] = [];
  const pump = (async () => {
    for (;;) {
      const next = await it.next();
      if (next.done) return;
      const m = /event: job-log\ndata: (.*)\n/.exec(next.value.toString());
      if (m) texts.push(JSON.parse(m[1]!).text);
    }
  })();
  while (texts.length < 1) await sleep(20);
  appendFileSync(join(dir, "j.log"), "two\n");
  // each wait begun after it (the watch's 200 ms, once the OS has told of the write) let run, the clock kept short of the
  // 5 s look's
  let moved = 0;
  while (texts.length < 2) {
    await time.begun(time.asked() + 1);
    assert.ok(moved + 200 < 5_000, "told by the watch, not the 5 s look");
    await time.adjust(200);
    moved += 200;
    for (let i = 0; i < 10 && texts.length < 2; i++) await sleep(5);
  }
  assert.deepEqual(texts, ["one\n", "one\ntwo\n"]);
  await it.return?.();
  await pump;
});
