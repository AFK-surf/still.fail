// An agent in brief, for its card (views/brief.ts): its turns and how long they took, its jobs at work.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { jobsText, workText } from "../src/views/brief.ts";

holdLanguage();
const MIN = 60_000;
const turn = (startedAt: number, minutes: number | null) => ({ id: `t${startedAt}`, kind: "input", startedAt, endedAt: minutes === null ? null : startedAt + minutes * MIN });

test("work_counts_turns_and_the_time_finished_ones_took", () => {
  assert.equal(workText([]), null);
  assert.equal(workText([turn(0, 0.2)]), "1 轮");
  assert.equal(workText([turn(0, 5), turn(10 * MIN, 7), turn(30 * MIN, null)]), "3 轮 · 共干了 12 分钟");
  assert.equal(workText([turn(0, 50), turn(60 * MIN, 22)]), "2 轮 · 共干了 1 小时 12 分");
});

test("jobs_at_work_by_what_they_are", () => {
  const job = (name: string, patch: object = {}) => ({ name, state: "running", port: null, ...patch });
  assert.equal(jobsText([]), null);
  assert.equal(jobsText([job("old", { state: "exited", exitCode: 0 }), job("web", { state: "stopped", port: 5173 })]), null);
  assert.equal(
    jobsText([job("web", { port: 5173 }), job("api", { port: 8080 }), job("CI", { watch: true }), job("build"), job("lint")]),
    "服务在线：web、api · 在盯着：CI · 2 个任务在跑",
  );
});
