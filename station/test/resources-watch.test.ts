// What of this machine still.fail uses (resources/watch.ts): whose each process is, and what each used between two
// looks. The process table and the usage counts are the test's.
import assert from "node:assert/strict";
import { test } from "node:test";
import { resourceRoutes } from "../src/api/routes/usage.ts";
import { ResourceWatch, type Usage, whoseOf } from "../src/resources/watch.ts";
import type { ProcessInfo } from "../src/platform/index.ts";

const p = (pid: number, ppid: number, pgid: number, command: string): ProcessInfo => ({ pid, ppid, pgid, bytes: 0, command });
const APP = "/Applications/youdid.wtf.app/Contents/MacOS/youdid.wtf";
const HELPER = "/Applications/youdid.wtf.app/Contents/Frameworks/youdid.wtf Helper (Renderer).app/Contents/MacOS/youdid.wtf Helper (Renderer)";

const table = [
  p(1, 0, 1, "launchd"),
  p(9, 1, 9, "stillfail-station"),
  p(10, 9, 10, "node"),
  // A chat's runner and its runtime, which runs a browser.
  p(20, 1, 20, "stillfail-runner"),
  p(21, 20, 20, "claude"),
  p(22, 21, 22, "chrome-headless-shell"),
  // A profile's runner (codex), no one chat's.
  p(30, 1, 30, "stillfail-runner"),
  p(31, 30, 30, "codex"),
  // A chat's job, started by the station, in its own group.
  p(40, 10, 40, "sh"),
  p(41, 40, 40, "python3"),
  // The app and its helper; and someone else's program.
  p(50, 1, 50, APP),
  p(51, 50, 50, HELPER),
  p(60, 1, 60, "Safari"),
];
const options = {
  runners: () => [{ runner: 20, pid: 21, session: "s1" }, { runner: 30, pid: 31, session: null }],
  jobs: () => [{ session: "s2", pgid: 40 }],
  isApp: (command: string) => command.includes("youdid.wtf.app/"),
  self: [10, 9],
};

test("whose: a chat's runner and job with all under them, the agents', the app's, the station's; the rest no one's", () => {
  const whose = whoseOf(table, options);
  const key = (pid: number) => whose.get(pid)?.key;
  assert.deepEqual([20, 21, 22].map(key), ["chat:s1", "chat:s1", "chat:s1"]);
  assert.deepEqual([30, 31].map(key), ["agents", "agents"]);
  assert.deepEqual([40, 41].map(key), ["chat:s2", "chat:s2"]);
  assert.deepEqual([50, 51].map(key), ["app", "app"]);
  assert.deepEqual([9, 10].map(key), ["station", "station"]);
  assert.equal(key(60), undefined);
  assert.equal(key(1), undefined);
});

test("whose: what runs on its own naming a chat's directory is that chat's, with all under it", () => {
  const rows = [...table, p(70, 1, 70, "sh"), p(71, 70, 70, "python3"), p(80, 1, 80, "vim")];
  const args = new Map([[70, "sh /data/sessions/c-1/workspace/run.sh"], [71, "python3 render.py"], [80, "vim /elsewhere/notes"]]);
  const whose = whoseOf(rows, options, args, [{ dir: "/data/sessions/c-1/workspace", session: "s3" }]);
  assert.deepEqual([70, 71].map((pid) => whose.get(pid)?.key), ["chat:s3", "chat:s3"]);
  assert.equal(whose.get(80), undefined);
});

const used = (cpuS: number, mb: number, wakeups: number, joules: number): Usage => ({ cpuNs: cpuS * 1e9, footprint: mb * 1e6, wakeups, energyNj: joules * 1e9 });

test("what each used since the last look, by whose and process; one begun since counts whole; no one's is not read", async () => {
  let now = 1_000_000;
  let rows = table;
  let counts = new Map<number, Usage>(table.map((r) => [r.pid, used(1, 100, 10, 1)]));
  const asked: number[][] = [];
  const watch = new ResourceWatch({
    clock: { currentTimeMillisUnsafe: () => now } as never,
    table: async () => rows,
    usage: (pids) => {
      asked.push(pids);
      return pids.map((pid) => counts.get(pid) ?? null);
    },
    ...options,
  });
  // The first look only reads where they are.
  await watch.look();
  assert.equal(watch.snapshot().at, null);
  assert.ok(!asked[0]!.includes(60), "Safari is not read");
  // 10 s later: the browser used 5 s of CPU, 30 J, woke 1000 times; the app's helper 1 s and 5 J; a new command of the
  // chat's began and used 2 s and 2 J.
  now += 10_000;
  rows = [...table, p(23, 21, 23, "node")];
  counts = new Map(counts);
  counts.set(22, used(6, 400, 1010, 31));
  counts.set(51, used(2, 500, 10, 6));
  counts.set(23, used(2, 50, 0, 2));
  await watch.look();
  const shot = watch.snapshot();
  const by = Object.fromEntries(shot.groups.map((g) => [g.key, g]));
  const s1 = by["chat:s1"]!;
  assert.ok(Math.abs(s1.cpu - 70) < 1e-9, "50% + 20%");
  assert.ok(Math.abs(s1.watts - 3.2) < 1e-9);
  assert.ok(Math.abs(s1.wakeups - 100) < 1e-9);
  assert.equal(s1.memory, 400e6 + 50e6 + 100e6 * 2, "the footprints now: the browser, the command, the runner and claude");
  assert.deepEqual(s1.processes.map((x) => x.name), ["chrome-headless-shell", "node", "stillfail-runner", "claude"]);
  assert.ok(Math.abs(by.app!.cpu - 10) < 1e-9);
  assert.equal(by.app!.processes[0]!.name, "youdid.wtf Helper (Renderer)");
  assert.equal(shot.groups[0]!.key, "chat:s1");
  assert.ok(Math.abs(shot.total.watts - 3.7) < 1e-9);
  assert.equal(shot.history.length, 1);
  assert.ok(Math.abs(shot.hours[0]!.joules["chat:s1"]! - 32) < 1e-6);
  await watch.close();
});

test("a process there before but no one's (its chat begun since) counts from the next look, not whole", async () => {
  let now = 0;
  let runners = [{ runner: 20, pid: 21, session: "s1" }];
  const counts = new Map<number, Usage>(table.map((r) => [r.pid, used(1000, 100, 0, 1000)]));
  const watch = new ResourceWatch({
    clock: { currentTimeMillisUnsafe: () => now } as never,
    table: async () => table,
    usage: (pids) => pids.map((pid) => counts.get(pid) ?? null),
    ...options,
    runners: () => runners,
  });
  await watch.look();
  now += 5000;
  runners = [...runners, { runner: 30, pid: 31, session: "s9" }];
  await watch.look();
  assert.equal(watch.snapshot().groups.find((g) => g.key === "chat:s9"), undefined);
  await watch.close();
});

test("GET /resources: the chats named; one the asker does not see counted as the agents'", async () => {
  let wanted = 0;
  const use = (cpu: number) => ({ cpu, memory: 1, watts: cpu / 10, wakeups: 1 });
  const watch = {
    want: async () => void wanted++,
    snapshot: () => ({
      at: 1, everyMs: 5000, counted: true, total: use(3), history: [],
      groups: [
        { key: "chat:mine", kind: "chat", session: "mine", ...use(2), processes: [{ pid: 5, name: "node", ...use(2) }] },
        { key: "chat:theirs", kind: "chat", session: "theirs", ...use(1), processes: [{ pid: 6, name: "cargo", ...use(1) }] },
      ],
      hours: [{ at: 0, joules: { "chat:mine": 10, "chat:theirs": 5, app: 1 } }],
    }),
  } as unknown as ResourceWatch;
  let asked: unknown = null;
  const read = async (_r: unknown, op: string, args: { sessions: string[] }) => {
    asked = [op, [...args.sessions].sort()];
    return { status: 200, headers: {}, body: Buffer.from(JSON.stringify({ mine: { thread: 7, title: "排查 p99" }, theirs: null })) };
  };
  const [route] = resourceRoutes({ read } as never, watch);
  const answer = await route!.handle({ viewer: { workspace: "w" } } as never, []);
  assert.equal(wanted, 1);
  assert.deepEqual(asked, ["resourceChats", ["mine", "theirs"]]);
  const body = JSON.parse((answer.body as Buffer).toString("utf8"));
  assert.deepEqual(body.groups.map((g: { key: string; cpu: number }) => [g.key, g.cpu]), [["chat:mine", 2], ["agents", 1]]);
  assert.deepEqual(body.groups[1].processes.map((x: { name: string }) => x.name), ["cargo"]);
  assert.deepEqual(body.hours[0].joules, { "chat:mine": 10, agents: 5, app: 1 });
  assert.deepEqual(body.chats, { mine: { thread: 7, title: "排查 p99" } });
});
