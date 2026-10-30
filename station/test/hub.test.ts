// The hub (src/sessions/hub.ts): routing, sessions, turns, nudges, waits, stops, sign-in retries, hold and release,
// recover and handover, eviction, single-session connects, the station's own chat. Ported from
// the Rust station's hub/tests.rs, on a real Store, a fake chat platform and fake runtimes.
import { runnerId } from "../src/agents/process.ts";
import { CONNECTION_LOST, keyPart, placeIn, sandboxConfig, sandboxName } from "../src/agents/sandbox.ts";
import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { GO_ON_AFTER_AUTH, GO_ON_AFTER_LOST, GO_ON_AFTER_REFILL, GO_ON_AFTER_SPENT, NUDGE, TOOLS_LOST } from "../src/agents/instructions.ts";
import { latest } from "../src/agents/migrations.ts";
import { classifyResult } from "../src/agents/claude.ts";
import { claudeProject, homesFirst, transcriptPaths } from "../src/read/transcript.ts";
import { marksDir, stateOf } from "../src/read/transcripts.ts";
import { sessionKey } from "../src/sessions/hub.ts";
import { addToThread, autoArchive, archive, archiveBy, archiveChat, bindSingle, configure, deleteSession, newSession, openChat, say as sayIn } from "../src/sessions/lifecycle.ts";
import { AUTO, MANUAL } from "../src/store/store.ts";
import { FakeDriver, Rig, matches, message, reply, say, settle, testClock } from "./hub-fakes.ts";

const chat = (runtime: "claude" | "codex" = "claude") => ({ runtime, createdBy: "local" });

test("a new session first says where it can be followed, multi-session connects only", async () => {
  const r = new Rig({ link: true });
  const m = say("<@UBOT> fix the build");
  await r.accept(m);
  await settle();
  assert.equal(r.chat.posts.length, 1);
  assert.equal(r.chat.posts[0]![1], `<https://ember.test/o/ws/st/cl%3AC1%3A${m.threadTs}|在 still.fail 中查看此会话>`);
  assert.deepEqual(r.chat.posts[0]![0], { channel: "C1", threadTs: m.threadTs });
  // Its next message is the same session: nothing more.
  await r.accept({ ...say("<@UBOT> and the tests"), threadTs: m.threadTs });
  await settle();
  assert.equal(r.chat.texts().length, 1);
  // A single-session connect has one session for everything: no link per thread.
  await r.accept(say("<@UBOT> hi"), "team");
  await settle();
  assert.deepEqual(r.teamChat.texts(), []);
  await r.close();
});

test("a mention starts a session and prompts the runtime with the message", async () => {
  const r = new Rig();
  const m = say("<@UBOT> fix the build");
  await r.accept(m);
  await settle();
  const session = r.claude.last();
  assert.equal(session.prompts.length, 1);
  // What the agent is called there comes with the message (the connect's bot and its mention).
  const expected = `<message via="slack" connect="cl" you="ember (<@UBOT>)" thread="C1/${m.ts}" from="U1" ts="${m.ts}">\n<@UBOT> fix the build\n</message>`;
  assert.ok(session.prompts[0]!.includes(expected), session.prompts[0]);
  assert.equal(r.session(sessionKey("cl", "C1", m.threadTs)).runtimeSessionId, session.sessionId);
  assert.ok(session.options.cwd.endsWith("workspace"));
  await r.close();
});

test("thread chatter without a session is ignored", async () => {
  const r = new Rig();
  await r.accept(say("just talking", { addressed: false }));
  await settle();
  assert.equal(r.claude.count(), 0);
  await r.close();
});

test("a mention inside an existing thread records what was said before and tells the agent about it", async () => {
  const r = new Rig();
  const earlier = (ts: string, user: string, text: string) => ({ ts, user, text, fromBot: false });
  r.chat.earlier.set("1.000001", [earlier("1.000001", "U2", "the build is red"), earlier("3.000001", "U3", "since this morning")]);
  await r.accept(message({ threadTs: "1.000001", ts: "5.000001" }));
  await settle();
  const prompt = r.claude.last().prompts[0]!;
  assert.ok(prompt.includes("Thread C1/1.000001 had messages before you were brought in"), prompt);
  assert.ok(!prompt.includes("the build is red"), "earlier messages are recorded, not delivered");
  const thread = r.thread("C1", "1.000001");
  assert.deepEqual(
    r.said(thread.id).map((m) => m.ts),
    ["1.000001", "3.000001", "5.000001"],
  );
  const history = await r.call(sessionKey("cl", "C1", "1.000001"), "chat_history", { to: "C1/1.000001", before: "5.000001" });
  assert.ok(history.includes('from="U2" ts="1.000001">\nthe build is red'), history);
  assert.ok(!history.includes("hello"));
  await r.close();
});

test("files shared in Slack are fetched into the session's uploads and given to the agent, once", async () => {
  const r = new Rig();
  r.chat.shared.set("F1", "error overlay");
  const file = (id: string, name: string) => ({ id, name, size: 13, url: `https://files.slack.com/${id}` });
  const m = say("<@UBOT> 看看", { files: [file("F1", "shot.png"), file("F2", "log.txt")] });
  await r.accept(m);
  await r.accept(m);
  await settle();
  assert.deepEqual(r.chat.downloads, ["F1", "F2"], "a message sent again is not fetched again");
  const [said] = r.said(r.thread("C1", m.threadTs).id);
  assert.equal(said!.text, "<@UBOT> 看看\n\n[无法获取文件 log.txt：missing_scope]");
  assert.equal(said!.attachments.length, 1);
  const [shot] = said!.attachments;
  assert.equal(shot!.name, "shot.png");
  assert.equal(dirname(shot!.path), join(r.session(sessionKey("cl", "C1", m.threadTs)).workspace, "uploads"));
  assert.equal(readFileSync(shot!.path, "utf8"), "error overlay");
  const prompt = r.claude.last().prompts[0]!;
  assert.ok(prompt.includes(`Attached files:\n- ${shot!.path} (shot.png, 13 bytes)`), prompt);
  assert.ok(prompt.includes("无法获取文件 log.txt"), prompt);
  await r.close();
});

test("files shared before the station joined a thread are fetched with what was said", async () => {
  const r = new Rig();
  r.chat.shared.set("F3", "trace");
  r.chat.earlier.set("1.000002", [{ ts: "1.000002", user: "U2", text: "", fromBot: false, files: [{ id: "F3", name: "trace.txt", size: 5, url: "https://files.slack.com/F3" }] }]);
  await r.accept(message({ threadTs: "1.000002", ts: "5.000002" }));
  await settle();
  const [first] = r.said(r.thread("C1", "1.000002").id);
  assert.equal(first!.attachments[0]!.name, "trace.txt");
  assert.equal(readFileSync(first!.attachments[0]!.path, "utf8"), "trace");
  await r.close();
});

test("a message during a running turn is steered into it", async () => {
  const r = new Rig();
  const first = message();
  await r.accept(first);
  await settle();
  await r.accept(reply(first, "9999.1", "also check tests"));
  await settle();
  assert.equal(r.claude.last().prompts.length, 1);
  assert.ok(r.claude.last().steers[0]!.includes("also check tests"));
  await r.close();
});

test("a message during a running turn moves what it waits on to the background, unless its profile says not", async () => {
  const r = new Rig();
  const first = message();
  await r.accept(first);
  await settle();
  await r.accept(reply(first, "9999.1", "also check tests"));
  await settle();
  const session = r.claude.last();
  assert.equal(session.backgrounds, 1);
  r.edit((c) => c.profiles.forEach((p: any) => (p.backgroundOnMessage = false)));
  await r.accept(reply(first, "9999.2", "and lint"));
  await settle();
  assert.equal(session.steers.length, 2);
  assert.equal(session.backgrounds, 1, "off: the message waits for what the turn waits on");
  await r.close();
});

test("the same message delivered twice is handled once", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await r.accept(m);
  await settle();
  assert.equal(r.claude.last().prompts.length, 1);
  await r.close();
});

test("a turn ending without a state is nudged, then reported after max nudges", async () => {
  const r = new Rig({ maxNudges: 1 });
  await r.accept(message());
  await settle();
  r.claude.last().complete();
  await settle();
  const prompts = r.claude.last().prompts;
  assert.equal(prompts.length, 2);
  assert.ok(prompts[1]!.includes("ended without a state"));
  r.claude.last().complete();
  await settle();
  assert.equal(r.claude.last().prompts.length, 2);
  assert.ok(r.chat.lastText().includes("未产出结果"));
  await r.close();
});

test("a turn ending waiting is not nudged nor evicted, and is asked again when the wait is over", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"], now: Date.now() });
  const r = new Rig({ maxWarmClaude: 0, warmMinutes: 0 });
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const said = await r.call(key, "chat_state", { kind: "waiting", seconds: 1, for: "CI 跑完" });
  assert.ok(said.includes("in 10 seconds"), `at least 10: ${said}`);
  r.claude.last().complete();
  await settle();
  const last = r.store.sessionStats(null).get(key)!.lastTurn!;
  assert.deepEqual([last.declared, last.waitFor], ["waiting", "CI 跑完"], "what it waits for is kept with the turn");
  assert.equal(r.claude.last().prompts.length, 1, "not nudged");
  assert.ok(!r.claude.last().disposed, "its background work may run in its process");
  assert.deepEqual(r.chat.texts(), []);
  t.mock.timers.tick(11_000);
  await settle();
  const prompts = r.claude.last().prompts;
  assert.equal(prompts.length, 2);
  assert.ok(prompts[1]!.includes("waiting on work you started (10 seconds)"), prompts[1]);
  assert.deepEqual(
    r.store.listTurns(key).flatMap((t) => t.summary.declared ?? []),
    ["waiting"],
  );
  await r.close();
});

const watchJob = (session: string) => ({
  id: "job_w", sessionKey: session, name: "盯 CI", command: "sleep 600", cwd: "/", port: null, token: "tw", state: "running",
  pgid: null, exitCode: null, startedAt: Date.now(), endedAt: null, restarts: 0, log: "/dev/null", watch: true,
});

test("a wait does not run out while a watch of its session runs", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"], now: Date.now() });
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  r.store.insertJob(watchJob(key));
  await r.call(key, "chat_state", { kind: "waiting", seconds: 10, for: "盯 CI", watch: true });
  r.claude.last().complete();
  await settle();
  assert.equal(r.store.sessionStats(null).get(key)!.lastTurn!.waitWatch, true, "the wait is its watch, as it said");
  for (let i = 0; i < 4; i++) {
    t.mock.timers.tick(10_000);
    await settle();
  }
  assert.equal(r.claude.last().prompts.length, 1, "the watch brings it back, not the clock");
  // The watch over, the wait runs out as any other.
  r.store.jobEnded("job_w", "stopped", null);
  t.mock.timers.tick(11_000);
  await settle();
  assert.equal(r.claude.last().prompts.length, 2);
  await r.close();
});

test("a wait for something else runs out while a watch of its session runs", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"], now: Date.now() });
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  r.store.insertJob(watchJob(key));
  await r.call(key, "chat_state", { kind: "waiting", seconds: 10, for: "读中继的日志" });
  r.claude.last().complete();
  await settle();
  assert.equal(r.store.sessionStats(null).get(key)!.lastTurn!.waitWatch, false);
  t.mock.timers.tick(11_000);
  await settle();
  assert.equal(r.claude.last().prompts.length, 2, "its watch does not stand in for what it waits on");
  await r.close();
});

test("a wait said to be a watch needs one running", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  await assert.rejects(r.call(key, "chat_state", { kind: "waiting", seconds: 10, for: "盯 CI", watch: true }), /watch/);
  await r.close();
});

test("a turn that starts before the wait is over ends it", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"], now: Date.now() });
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  await r.call(key, "chat_state", { kind: "waiting", seconds: 60, for: "CI 跑完" });
  r.claude.last().complete();
  await settle();
  await r.accept(reply(m, "9999.1", "any news?"));
  await settle();
  await r.call(key, "chat_state", { kind: "final" });
  r.claude.last().complete();
  t.mock.timers.tick(120_000);
  await settle();
  assert.equal(r.claude.last().prompts.length, 2, "no word when the old wait's time comes");
  assert.ok((await r.refused(key, "chat_state", { kind: "waiting" })).includes("seconds is required"));
  assert.ok((await r.refused(key, "chat_state", { kind: "waiting", seconds: 60 })).includes("for is required"));
  await r.close();
});

test("a turn that fails after it said it would wait ends failed, not waiting: nothing would ask it again", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"], now: Date.now() });
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  await r.call(key, "chat_state", { kind: "waiting", seconds: 60, for: "CI 跑完" });
  // It went on working after saying so, and its model could not be reached.
  r.claude.last().end({ kind: "failed", reason: "model", message: "API Error: Connection dropped (ECONNRESET)" });
  await settle();
  const last = () => r.store.lastTurn(key)!;
  assert.deepEqual([last().outcome, last().declared, last().waitSeconds], ["failed", null, null], "shown failed, not waiting");
  assert.ok(matches(r.chat.lastText(), ["ECONNRESET"]), r.chat.lastText());
  // As a station from before recorded it: waiting. The next station, started without a handover, puts it right.
  r.store.endTurn(r.store.listTurns(key).at(-1)!.id, "failed", "model: API Error: Connection dropped (ECONNRESET)", "waiting", 60);
  await r.hub.shutdown();
  const claude = new FakeDriver("claude");
  r.hub = r.newHub({ chats: (id) => (id === "cl" ? r.chat : undefined), drivers: [claude, new FakeDriver("codex")], internal: false });
  await r.hub.takeUp();
  r.hub.recover();
  await settle();
  assert.deepEqual([last().outcome, last().declared, last().waitSeconds], ["failed", null, null]);
  t.mock.timers.tick(120_000);
  await settle();
  assert.equal(claude.count(), 0, "not asked again");
  await r.close();
});

test("after a restart without a handover, a wait on record still asks again when it would have", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"], now: Date.now() });
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  await r.call(key, "chat_state", { kind: "waiting", seconds: 60, for: "CI 跑完" });
  r.claude.last().complete();
  await settle();
  // Stopped with nothing handed over (a crash), then the next station on the same store.
  await r.hub.shutdown();
  t.mock.timers.tick(20_000);
  const claude = new FakeDriver("claude");
  r.hub = r.newHub({ chats: (id) => (id === "cl" ? r.chat : undefined), drivers: [claude, new FakeDriver("codex")], internal: false });
  await r.hub.takeUp();
  r.hub.recover();
  await settle();
  t.mock.timers.tick(30_000);
  await settle();
  assert.equal(claude.count(), 0, "not before its time");
  t.mock.timers.tick(11_000);
  await settle();
  assert.ok(claude.last().prompts[0]?.includes("waiting on work you started (60 seconds)"), JSON.stringify(claude.last().prompts));
  await r.close();
});

test("slack edits are appended to the thread as entries of their own", async () => {
  const r = new Rig();
  const m = say("<@UBOT> typo");
  await r.accept(m);
  const thread = r.thread("C1", m.threadTs);
  const before = r.store.lastEntry(thread.id);
  const edit = { type: "changed" as const, channel: "C1", threadTs: m.threadTs, ts: m.ts, text: "<@UBOT> fixed" };
  await r.hub.receive("cl", edit);
  await r.hub.receive("cl", edit); // Slack repeats roots when replies come
  const entries = r.store.entriesAfter(thread.id, before);
  assert.deepEqual([entries[0]!.kind, entries[0]!.target, entries[0]!.text], ["edit", before, "<@UBOT> fixed"]);
  assert.equal(r.store.lastEntry(thread.id), before + 1);
  await settle();
  await r.close();
});

test("stop aborts the running turn and confirms once it ends", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  await r.accept(reply(m, "9999.2", "<@UBOT> -stop", { addressed: true }));
  await settle();
  const session = r.claude.last();
  assert.equal(session.aborts, 1);
  assert.deepEqual(session.steers, [], "-stop is not forwarded to the agent");
  session.end({ kind: "aborted" });
  await settle();
  assert.equal(r.chat.lastText(), "已停止当前任务");
  assert.equal(session.prompts.length, 1, "no nudge after a stop");
  await r.close();
});

test("stopped while it runs, what it has going in the background does not bring it back", async () => {
  const r = new Rig();
  const stopped: string[] = [];
  r.hub.setJobs({
    stop: async (id) => {
      stopped.push(id);
      r.store.jobEnded(id, "stopped", null);
      return r.store.getJob(id)!;
    },
  });
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  r.store.insertJob({ ...watchJob(key), id: "watch", token: "twatch", port: null, watch: true });
  const session = r.claude.last();
  session.tasks = [{ id: "b1", kind: "command", description: "watch CI" }];
  await r.hub.stop(key);
  await settle();
  // A job's notice its turn cannot take (as Codex's, between steps) waits for the turn's end.
  session.unsteerable = true;
  r.hub.notify(key, "Job watch ended");
  // Its background command ended during the turn: Claude runs what it said as a turn of its own the moment the stopped
  // one ends.
  session.end({ kind: "aborted" });
  session.busyNow = true;
  session.events({ type: "turnStarted" });
  await settle();
  assert.equal(r.chat.lastText(), "已停止当前任务");
  assert.ok(session.disposed, "its process ends, with its background work");
  assert.equal(r.store.lastTurn(key)!.outcome, "aborted", "no turn after the stop");
  assert.equal(r.store.getJob("watch")!.state, "stopped");
  assert.equal(r.claude.count(), 1, "nothing it was told meanwhile starts a turn");
  // Someone's message brings it back, told what was stopped.
  await r.accept(reply(m, "9999.3", "<@UBOT> go on", { addressed: true }));
  await settle();
  const next = r.claude.last();
  assert.notEqual(next, session);
  assert.ok(matches(next.prompts[0]!, ["people stopped you", "- background command b1 (watch CI)\n", "go on"]), next.prompts[0]);
  assert.ok(!next.prompts[0]!.includes("Job watch ended"), next.prompts[0]);
  await r.close();
});

test("stop while waiting ends the wait and its process", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"], now: Date.now() });
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  await r.call(key, "chat_state", { kind: "waiting", seconds: 10, for: "任务跑完" });
  r.claude.last().complete();
  await settle();
  await r.accept(reply(m, "9999.2", "<@UBOT> -stop", { addressed: true }));
  await settle();
  assert.ok(r.claude.last().disposed, "the background work in its process ends with it");
  assert.equal(r.chat.lastText(), "已停止当前任务");
  const last = r.store.lastTurn(key)!;
  assert.deepEqual([last.outcome, last.declared, last.waitSeconds], ["aborted", null, null], "no longer shown running");
  t.mock.timers.tick(30_000);
  await settle();
  assert.equal(r.claude.last().prompts.length, 1, "not asked again when the wait would have been over");
  await r.close();
});

test("stop while waiting ends the jobs that would bring it back, but not its services", async () => {
  const r = new Rig();
  const stopped: string[] = [];
  r.hub.setJobs({
    stop: async (id) => {
      stopped.push(id);
      r.store.jobEnded(id, "stopped", null);
      return r.store.getJob(id)!;
    },
  });
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const job = (id: string, port: number | null, watch: boolean) => r.store.insertJob({ ...watchJob(key), id, token: `t${id}`, port, watch });
  job("build", null, false);
  job("watch", null, true);
  job("page", 47123, false);
  await r.call(key, "chat_state", { kind: "waiting", seconds: 600, for: "任务跑完" });
  r.claude.last().complete();
  await settle();
  await r.hub.stop(key);
  await settle();
  const state = (id: string) => r.store.getJob(id)!.state;
  assert.deepEqual([state("build"), state("watch"), state("page")], ["stopped", "stopped", "running"]);
  assert.equal(r.chat.lastText(), "已停止当前任务");
  await r.close();
});

test("a turn that cannot start is not left starting, and stop clears what is still said to be under way", async () => {
  const r = new Rig();
  r.claude.refuses = "the station this subscription is signed in on did not lend it: station mesh is not ready";
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const phase = () => {
    let said: unknown = "untold";
    const id = r.hub.live.subscribe(key, 0, 0, (l: any) => {
      if (l.type === "steps") said = l.phase;
    });
    r.hub.live.unsubscribe(key, id);
    return said;
  };
  assert.equal(phase(), null, "the failed start ended what was said to be starting");
  assert.equal(r.hub.processState(key), "cold");
  assert.match(r.chat.lastText(), /did not lend it/);
  // Said to be under way some other way: stop, with nothing running, clears it.
  r.hub.live.event(key, { kind: "phase", phase: "starting" });
  assert.notEqual(phase(), null);
  await r.hub.stop(key);
  await settle();
  assert.equal(phase(), null);
  await r.close();
});

test("claude auth retries once, then reports the profile and does not loop", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const first = r.claude.last();
  first.end({ kind: "failed", reason: "auth", message: "401 Missing API key" });
  await settle();
  const retry = r.claude.last();
  assert.ok(first.disposed);
  assert.equal(r.claude.count(), 2);
  assert.equal(retry.options.resume, first.sessionId);
  assert.deepEqual(retry.prompts, [GO_ON_AFTER_AUTH]);
  assert.ok(!r.chat.texts().some((t) => t.includes("认证失败")));
  retry.end({ kind: "failed", reason: "auth", message: "401 Missing API key" });
  await settle();
  assert.equal(r.claude.count(), 2, "a persistent auth failure must stop, not loop");
  assert.ok(matches(r.chat.lastText(), ["认证失败", "401 Missing API key"]));
  assert.equal(r.claude.last().prompts.length, 1);
  // The notice says whose sign-in failed, for the clients to link that profile's page; another failure is no profile's.
  const thread = r.thread("C1", m.threadTs);
  const last = () => r.store.entriesBefore(thread.id, null, 1).pop()!;
  assert.deepEqual([last().authorKind, last().profile], ["ember", "cc"]);
  await r.accept(reply(m, "9999.2", "<@UBOT> again", { addressed: true }));
  await settle();
  r.claude.last().end({ kind: "failed", reason: "exited", message: "exit 1" });
  await settle();
  assert.ok(matches(r.chat.lastText(), ["意外退出"]));
  assert.equal(last().profile, null);
  await r.close();
});

test("a sign-in that failed has its account checked again first: one whose login is over is left, and the turn goes on on another", async () => {
  const r = new Rig();
  r.edit((raw) => {
    raw.profiles[0].models = ["opus"];
    raw.profiles.push({ ...raw.profiles[0], id: "cc2", name: "second" });
  });
  let over = false;
  const checked: string[] = [];
  r.hub.accounts.setHealth((id) => (id === "cc" && over ? { check: { state: "login", detail: "", models: null, checkedAt: 0 } } : {}));
  r.hub.accounts.setRecheck(async (id) => {
    checked.push(id);
    over = true;
  });
  await r.accept(message());
  await settle();
  const first = r.claude.last();
  assert.equal(first.options.profile.id, "cc");
  first.end({ kind: "failed", reason: "auth", message: "401 OAuth token has expired" });
  await settle();
  assert.deepEqual(checked, ["cc"]);
  assert.ok(first.disposed);
  const next = r.claude.last();
  assert.equal(next.options.profile.id, "cc2");
  assert.ok(matches(next.prompts[0]!, [GO_ON_AFTER_AUTH]), next.prompts[0]);
  assert.ok(!r.chat.texts().some((t) => t.includes("认证失败")), "it just goes on");
  await r.close();
});

test("a turn whose sandbox connection was lost goes on once from its transcript, then is said to have ended", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const first = r.claude.last();
  const lost = { kind: "failed" as const, reason: "exited" as const, message: `claude exited (75) during the turn: ${CONNECTION_LOST} (ssh exited 255)` };
  first.end(lost);
  await settle();
  const retry = r.claude.last();
  assert.ok(first.disposed);
  assert.equal(r.claude.count(), 2);
  assert.equal(retry.options.resume, first.sessionId);
  assert.deepEqual(retry.prompts, [GO_ON_AFTER_LOST]);
  assert.ok(!r.chat.texts().some((t) => t.includes("意外退出")));
  // Lost again in the turn it went on in: said, not started again.
  retry.end(lost);
  await settle();
  assert.equal(r.claude.count(), 2);
  assert.ok(matches(r.chat.lastText(), ["意外退出", CONNECTION_LOST]));
  // A runtime that exited by itself is not started again.
  await r.accept(reply(m, "9999.2", "<@UBOT> again", { addressed: true }));
  await settle();
  const third = r.claude.count();
  r.claude.last().end({ kind: "failed", reason: "exited", message: "exit 1" });
  await settle();
  assert.equal(r.claude.count(), third);
  await r.close();
});

test("a runtime not installed is said about it, and what waited goes on once it is installed", async () => {
  const r = new Rig();
  r.claude.missing = true;
  const m = message();
  await r.accept(m);
  await settle();
  assert.equal(r.chat.lastText(), "⚠️ 无法启动 agent：此 station 尚未安装 Claude Code");
  // The notice says which runtime, for the clients to offer installing it; the message waits.
  const thread = r.thread("C1", m.threadTs);
  const last = r.store.entriesBefore(thread.id, null, 1).pop()!;
  assert.deepEqual([last.authorKind, last.runtime, last.profile], ["ember", "claude", null]);
  assert.equal(r.claude.count(), 0);
  // Tried again with nothing said since (a restart gives it what waits): not said again.
  r.hub.installed("claude");
  await settle();
  assert.equal(r.store.entriesAfter(thread.id, last.n).length, 0, "the same notice is not said twice in a row");
  // Another runtime installed: nothing of this session's goes on.
  r.claude.missing = false;
  r.hub.installed("codex");
  await settle();
  assert.equal(r.claude.count(), 0);
  r.hub.installed("claude");
  await settle();
  assert.equal(r.claude.count(), 1);
  assert.ok(r.claude.last().prompts[0]!.includes(m.text), r.claude.last().prompts[0]);
  await r.close();
});

test("claude auth recovers without replaying input, and a later turn can recover again", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = r.claude.last().options.route;
  for (const expected of [2, 3]) {
    r.claude.last().end({ kind: "failed", reason: "auth", message: "401 expired token" });
    await settle();
    assert.equal(r.claude.count(), expected);
    assert.deepEqual(r.claude.last().prompts, [GO_ON_AFTER_AUTH]);
    await r.call(key, "chat_state", { kind: "all_done", done: "测试任务已完成，没有剩余工作" });
    r.claude.last().complete();
    await settle();
    assert.ok(!r.chat.texts().some((t) => t.includes("认证失败")));
    if (expected === 2) {
      await r.accept(reply(m, "9999.2", "<@UBOT> next task", { addressed: true }));
      await settle();
    }
  }
  await r.close();
});

test("claude auth does not restart stopped, held or declared work", async () => {
  for (const mode of ["stop", "hold", "declared"]) {
    const r = new Rig();
    const m = message();
    await r.accept(m);
    await settle();
    if (mode === "stop") await r.accept(reply(m, "9999.2", "<@UBOT> -stop", { addressed: true }));
    else if (mode === "hold") r.hub.hold("drain");
    else await r.call(r.claude.last().options.route, "chat_state", { kind: "all_done", done: "测试任务已完成，没有剩余工作" });
    await settle();
    r.claude.last().end({ kind: "failed", reason: "auth", message: "401" });
    await settle();
    assert.equal(r.claude.count(), 1, mode);
    await r.close();
  }
});

test("claude auth's retry budget and whom the turn is for survive a handover", async () => {
  const r = new Rig();
  await r.accept(message());
  await settle();
  r.claude.last().end({ kind: "failed", reason: "auth", message: "401" });
  await settle();
  const handed = await r.hub.handOver();
  const turn = handed.sessions[0]!.turn!;
  assert.ok(turn.authRetried);
  assert.ok(turn.by.person !== null);
  assert.ok(turn.by.thread !== null);
  await r.close();
});

test("messages that arrive while a turn cannot take them go in the next turn", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const session = r.claude.last();
  session.unsteerable = true;
  await r.accept(reply(m, "9999.3", "one more thing"));
  await settle();
  session.complete();
  await settle();
  assert.equal(session.prompts.length, 2);
  assert.ok(session.prompts[1]!.includes("one more thing"));
  await r.close();
});

test("a connect's runtime, profile and model decide the session", async () => {
  const r = new Rig();
  const m = say("<@UGPT> refactor this");
  await r.accept(m, "gpt");
  await settle();
  assert.deepEqual([r.claude.count(), r.codex.count()], [0, 1]);
  const row = r.session(sessionKey("gpt", "C1", m.threadTs));
  assert.deepEqual([row.profile, row.model], ["cx", null]);
  const n = message();
  await r.accept(n);
  await settle();
  assert.equal(r.session(sessionKey("cl", "C1", n.threadTs)).model, "opus");
  assert.equal(r.claude.last().options.effort, "high", "the connect's effort reaches the runtime");
  // Guidance only: no identity, no name (what it is called comes with each message, per connect).
  const instructions = r.claude.last().options.instructions;
  assert.ok(!instructions.includes("You are ") && !instructions.includes("Claude bot"));
  await r.close();
});

test("two connects in one thread keep separate sessions, share its messages and reply through their own connection", async () => {
  const r = new Rig();
  const root = say("<@UBOT> <@UGPT> compare notes");
  await r.accept(root);
  await r.accept(root, "gpt");
  await settle();
  const both = reply(root, "9999.7", "both of you: go");
  await r.accept(both);
  await r.accept(both, "gpt");
  await settle();
  assert.ok(r.claude.last().steers[0]!.includes("both of you"));
  assert.ok(r.codex.last().steers[0]!.includes("both of you"));
  await r.call(sessionKey("gpt", "C1", root.threadTs), "chat_post", { to: `C1/${root.threadTs}`, text: "from gpt" });
  assert.deepEqual(r.gptChat.texts(), ["from gpt"]);
  assert.deepEqual(r.chat.texts(), []);
  const thread = r.thread("C1", root.threadTs);
  assert.deepEqual(
    r.store.threadSessions(thread.id).map((m) => [m.session, m.connect]),
    [
      [sessionKey("cl", "C1", root.threadTs), "cl"],
      [sessionKey("gpt", "C1", root.threadTs), "gpt"],
    ],
  );
  assert.deepEqual(
    r.said(thread.id).map((m) => m.authorKind),
    ["person", "person", "agent"],
    "each message once, however many connects saw it",
  );
  await r.close();
});

test("a mention of one connect does not start a session for another connect that sees the message", async () => {
  const r = new Rig();
  await r.accept(say("<@UBOT> only claude", { addressed: false }), "gpt");
  await settle();
  assert.equal(r.codex.count(), 0);
  await r.close();
});

test("after a restart, a cut-off turn is resumed", async () => {
  const first = new Rig();
  await first.accept(message());
  await settle();
  const runtimeId = first.claude.last().sessionId;
  // Same store, new hub and drivers: what a restart looks like.
  const claude = new FakeDriver("claude");
  const hub = first.newHub({ chats: (id) => (id === "cl" ? first.chat : undefined), drivers: [claude, new FakeDriver("codex")], internal: false });
  hub.recover();
  await settle();
  assert.equal(claude.last().options.resume, runtimeId);
  assert.ok(claude.last().prompts[0]!.includes("restarted while you were in the middle of a turn"));
  await hub.shutdown();
  await first.close();
});

test("handed over to the next station, a running turn goes on and what came meanwhile reaches it", async () => {
  const first = new Rig();
  const m = message();
  await first.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const old = first.claude.last();
  const handed = await first.hub.handOver();
  assert.equal(handed.sessions.length, 1);
  assert.ok(handed.sessions[0]!.turn !== null, "its turn goes along");
  assert.ok(existsSync(join(first.dir, "run", "handover.json")), "written for the next station");
  // Said while handing over: it waits, pending, and the old station does nothing more with it.
  await first.accept(reply(m, "9999.7", "one more thing"));
  await settle();
  assert.ok(old.steers.length === 0 && old.prompts.length === 1);
  // The next station: same store, new hub and drivers, what was handed over read back from its file.
  const claude = new FakeDriver("claude");
  const hub = first.newHub({ chats: (id) => (id === "cl" ? first.chat : undefined), drivers: [claude, new FakeDriver("codex")], internal: false });
  await hub.takeUp();
  assert.ok(!existsSync(join(first.dir, "run", "handover.json")), "taken");
  hub.recover();
  await settle();
  const taken = claude.last();
  assert.equal(taken.sessionId, old.sessionId);
  assert.deepEqual(taken.prompts, [], "not resumed: its turn runs on");
  assert.ok(taken.steers[0]?.includes("one more thing"), JSON.stringify(taken.steers));
  assert.ok(first.store.getSession(key)!.running);
  // Its end is the next station's: it ended without a state, so it nudges.
  taken.complete();
  await settle();
  assert.equal(taken.prompts.length, 1, JSON.stringify(taken.prompts));
  assert.ok((taken.prompts as string[])[0]!.includes(NUDGE));
  await hub.shutdown();
  await first.close();
});

test("a job's notice given to a session while the next station starts, before it takes the session up, reaches its agent", async () => {
  const first = new Rig();
  const m = message();
  await first.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const old = first.claude.last();
  old.complete();
  await settle();
  await first.call(key, "chat_state", { kind: "waiting", for: "a task on another station", seconds: 900 });
  old.complete();
  await settle();
  await first.hub.handOver();
  // The next station, held while it starts (agents.ts): a task followed from here is told ended (Remote.resume, once
  // the peers' bus is there) before the hub takes the sessions up (2026-10-30 ccvm, a Studio task's end lost so).
  const claude = new FakeDriver("claude");
  const hub = first.newHub({ chats: (id) => (id === "cl" ? first.chat : undefined), drivers: [claude, new FakeDriver("codex")], internal: false });
  hub.hold("starting");
  hub.notify(key, "Remote task k1 on B: ended");
  await hub.takeUp();
  hub.release("starting");
  hub.recover();
  await settle();
  const taken = claude.last();
  assert.equal(taken.sessionId, old.sessionId);
  assert.ok(taken.prompts.some((p) => typeof p === "string" && p.includes("Remote task k1 on B: ended")), JSON.stringify(taken.prompts));
  await hub.shutdown();
  await first.close();
});

test("a state said while a turn runs outlives a station killed before it handed over: the turn ends in it", async () => {
  const first = new Rig();
  const m = message();
  await first.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const old = first.claude.last();
  await first.call(key, "chat_state", { kind: "all_done", done: "answered" });
  // Killed there (no handover file); its runner keeps the process, still in its turn, and the next station finds it.
  const claude = new FakeDriver("claude");
  claude.left = { id: old.sessionId, busy: true };
  const hub = first.newHub({ chats: (id) => (id === "cl" ? first.chat : undefined), drivers: [claude, new FakeDriver("codex")], internal: false, runners: [runnerId("claude", key)] });
  await hub.takeUp();
  hub.recover();
  await settle();
  const taken = claude.last();
  assert.equal(taken.sessionId, old.sessionId);
  taken.complete();
  await settle();
  const last = first.store.lastTurn(key)!;
  assert.deepEqual([last.outcome, last.declared], ["completed", "final"], "ended done, not without a state");
  assert.deepEqual(taken.prompts, [], "not nudged");
  await hub.shutdown();
  await first.close();
});

test("taken up by a station whose tools are elsewhere, a process told the old address starts again: idle at once, running once its turn ends", async () => {
  const first = new Rig();
  const busy = message();
  const idle = message();
  await first.accept(busy);
  await first.accept(idle);
  await settle();
  const [runningOld, idleOld] = first.claude.sessions;
  idleOld!.complete();
  await settle();
  await first.call(sessionKey("cl", "C1", idle.threadTs), "chat_state", { kind: "all_done", done: "answered" });
  idleOld!.complete();
  await settle();
  assert.ok(!idleOld!.busy() && runningOld!.busy());
  await first.hub.handOver();
  // The next station could not have the port again: its tools are at another address.
  const claude = new FakeDriver("claude");
  const moved = "http://127.0.0.1:2/mcp";
  const hub = first.newHub({ chats: (id) => (id === "cl" ? first.chat : undefined), drivers: [claude, new FakeDriver("codex")], internal: false, mcpUrl: moved });
  await hub.takeUp();
  const [running, idleTaken] = claude.sessions;
  assert.equal(running!.toolsUrl, "http://127.0.0.1:1/mcp", "as it was told");
  hub.toolsAt(moved);
  hub.recover();
  await settle();
  assert.ok(idleTaken!.disposed, "idle: ended at once");
  assert.ok(!running!.disposed, "running: its turn goes on");
  // Its turn ends (it could not post): not nudged in the old process, but resumed in a new one, told why.
  running!.complete();
  await settle();
  assert.ok(running!.disposed);
  const again = claude.last();
  assert.notEqual(again, running);
  assert.equal(again.options.resume, running!.sessionId);
  assert.equal(again.options.mcpUrl, moved);
  assert.ok(again.prompts[0]!.includes(TOOLS_LOST), JSON.stringify(again.prompts));
  // The idle one's next message starts a new process at the new address, resuming.
  await hub.accept("cl", reply(idle, "9999.8", "and another thing"));
  await settle();
  assert.equal(claude.last().options.resume, idleTaken!.sessionId);
  assert.equal(claude.last().options.mcpUrl, moved);
  await hub.shutdown();
  await first.close();
});

test("an agent that loses the station's tools is started again rather than nudged, then its last words are shown", async () => {
  const r = new Rig({ maxNudges: 2 });
  const m = message();
  await r.accept(m);
  await settle();
  const first = r.claude.last();
  first.says("Here is the answer: 42.");
  first.events({ type: "toolsLost", why: "ECONNREFUSED: Unable to connect" });
  first.complete();
  await settle();
  assert.ok(first.disposed, "the process that lost them ends");
  const second = r.claude.last();
  assert.notEqual(second, first);
  assert.equal(second.options.resume, first.sessionId);
  assert.deepEqual(second.prompts, [TOOLS_LOST]);
  assert.ok(!r.chat.texts().some((t) => t.includes("42")));
  // Lost again: given up on (no nudge, no third process); its last words are shown, marked as the station's.
  second.events({ type: "toolsLost", why: 'MCP server "stillfail" is not connected' });
  second.complete();
  await settle();
  assert.equal(r.claude.count(), 2);
  assert.ok(matches(r.chat.lastText(), ["未在对话中回复", "代为转发", "> Here is the answer: 42."]), r.chat.lastText());
  // A new message: a new process, the tools' again.
  await r.accept(reply(m, "9999.9", "still there?"));
  await settle();
  assert.equal(r.claude.count(), 3);
  await r.close();
});

test("a turn given up on after its nudges shows the agent's last words, unless it posted", async () => {
  const r = new Rig({ maxNudges: 1 });
  const m = message();
  await r.accept(m);
  await settle();
  const s = r.claude.last();
  s.says("The build passes.");
  s.complete();
  await settle();
  s.complete();
  await settle();
  assert.ok(matches(r.chat.lastText(), ["代为转发", "> The build passes."]), r.chat.lastText());
  // It posted this time: what it said was seen, the notice is the plain one.
  await r.accept(reply(m, "9999.10", "and now?"));
  await settle();
  s.says("Now it fails.");
  await r.call(sessionKey("cl", "C1", m.threadTs), "chat_post", { to: `C1/${m.threadTs}`, text: "Now it fails." });
  s.complete();
  await settle();
  s.complete();
  await settle();
  assert.ok(r.chat.lastText().includes("未产出结果"), r.chat.lastText());
  await r.close();
});

test("held turns start once released, with what waited meanwhile", async () => {
  const r = new Rig({ maxNudges: 0 });
  const m = message();
  await r.accept(m);
  await settle();
  const session = r.claude.last();
  session.complete();
  await settle();
  r.hub.hold("drain");
  await r.accept(reply(m, "9999.8", "next"));
  await settle();
  assert.equal(session.prompts.length, 1, "held: nothing starts");
  assert.ok(!r.hub.anyRunning());
  r.hub.release("drain");
  await settle();
  assert.equal(session.prompts.length, 2);
  assert.ok(session.prompts[1]!.includes("next"));
  await r.close();
});

test("a station in no workspace starts no turn until it joins one, whatever a drain does", async () => {
  const r = new Rig({ maxNudges: 0 });
  r.hub.hold("unbound");
  const m = message();
  await r.accept(m);
  await settle();
  assert.equal(r.claude.count(), 0, "unbound: no runtime session starts");
  const key = sessionKey("cl", m.channel, m.threadTs);
  assert.equal(r.store.pendingMessages(key).length, 1, "the message waits");
  // A drain that comes and goes meanwhile does not let it through.
  r.hub.hold("drain");
  r.hub.release("drain");
  await settle();
  assert.equal(r.claude.count(), 0);
  assert.ok(r.hub.holds("unbound"));
  r.hub.release("unbound");
  await settle();
  const session = r.claude.last();
  assert.equal(session.prompts.length, 1, "joined: what waited starts");
  assert.ok(session.prompts[0]!.includes("hello"));
  await r.close();
});

test("leaving the workspace ends the runtimes, and coming back resumes the cut-off turn with what it was given", async () => {
  const r = new Rig({ maxNudges: 0 });
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const session = r.claude.last();
  await r.accept(reply(m, "9999.5", "and the docs too"));
  await settle();
  assert.ok(session.steers[0]!.includes("and the docs too"), "given to the running turn");
  assert.deepEqual(r.store.pendingMessages(key), []);
  // An idle process of another session ends as well.
  await r.accept(say("<@UBOT> other"));
  await settle();
  const idle = r.claude.last();
  idle.complete();
  await settle();
  assert.ok(idle !== session && !idle.busyNow && !idle.disposed);

  const said = r.chat.texts().length;
  r.hub.hold("unbound");
  await r.hub.suspendAll();
  assert.ok(session.disposed && idle.disposed, "every runtime process ended");
  assert.equal(session.aborts, 0, "ended, not just interrupted");
  assert.deepEqual([r.claude.shutdowns, r.codex.shutdowns], [1, 1], "and the drivers' own");
  assert.ok(!r.hub.anyRunning());
  assert.equal(r.hub.processState(key), "cold");
  assert.ok(r.session(key).running, "kept for recover");
  assert.deepEqual(
    r.store.pendingMessages(key).map((p) => p.message.text),
    ["and the docs too"],
    "what it may not have read waits again",
  );
  // What the ended runtime still says is not taken: no nudge, no notice, nothing started.
  session.complete();
  await settle();
  assert.equal(r.claude.count(), 2, "no runtime starts while out of the workspace");
  assert.equal(r.chat.texts().length, said, "nothing said in the threads");
  assert.ok(r.session(key).running);

  // Back in the workspace: recover, then release.
  r.hub.recover();
  r.hub.release("unbound");
  await settle();
  const resumed = r.claude.last();
  assert.equal(r.claude.count(), 3, "only the cut-off turn resumes; the idle session waits for its next message");
  assert.equal(resumed.options.resume, session.sessionId, "on the same runtime session");
  assert.ok(matches(resumed.prompts[0]!, ["restarted while you were in the middle of a turn", "and the docs too"]), JSON.stringify(resumed.prompts));
  assert.deepEqual(r.store.pendingMessages(key), []);
  await r.close();
});

test("a turn that had already said final is not resumed after leaving the workspace", async () => {
  const r = new Rig({ maxNudges: 0 });
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  r.hub.hold("unbound");
  await r.hub.suspendAll();
  assert.ok(r.claude.last().disposed);
  assert.ok(!r.session(key).running);
  r.hub.recover();
  r.hub.release("unbound");
  await settle();
  assert.equal(r.claude.count(), 1, "nothing to resume");
  await r.close();
});

test("when the runtime session cannot be resumed, a new one starts and is told to catch up", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const old = r.claude.last();
  old.end({ kind: "failed", reason: "exited", message: "gone" });
  old.events({ type: "closed", why: "gone" });
  await settle();
  r.claude.unresumable.add(old.sessionId);
  await r.accept(reply(m, "9999.4", "still there?"));
  await settle();
  const now = r.claude.last();
  assert.notEqual(now, old);
  assert.equal(now.options.resume, undefined);
  assert.ok(matches(now.prompts[0]!, ["could not be restored", "still there?"]));
  // Told where its earlier conversation is, to read it itself: its execution history and its threads.
  const key = sessionKey("cl", "C1", m.threadTs);
  assert.ok(now.prompts[0]!.includes(`session_history with chat ${key}`) && now.prompts[0]!.includes(`chat_history for C1/${m.threadTs}`), now.prompts[0]);
  await r.close();
});

test("idle claude processes beyond the warm limit are evicted, oldest first, as soon as another goes idle", async () => {
  const time = testClock();
  const r = new Rig({ maxWarmClaude: 1, warmMinutes: 0, clock: time.clock });
  await r.accept(message({ ts: "1.1", threadTs: "1.1" }));
  await settle();
  r.claude.last().end({ kind: "aborted" });
  await settle();
  assert.ok(!r.claude.last().disposed, "within the limit");
  // Idle for a moment longer than the next one will be.
  await time.adjust(5);
  await r.accept(message({ ts: "2.1", threadTs: "2.1" }));
  await settle();
  r.claude.last().end({ kind: "aborted" });
  await settle();
  assert.deepEqual(
    r.claude.sessions.map((s) => s.disposed),
    [true, false],
  );
  await r.close();
});

test("an idle process beyond the limit is evicted at its own deadline", async () => {
  const time = testClock();
  const r = new Rig({ maxWarmClaude: 0, warmMinutes: 0.002, clock: time.clock }); // 120 ms
  await r.accept(message());
  await settle();
  r.claude.last().end({ kind: "aborted" });
  await settle();
  await time.adjust(119);
  await settle();
  assert.ok(!r.claude.last().disposed, "not idle long enough yet");
  await time.adjust(1);
  await settle();
  assert.ok(r.claude.last().disposed);
  await r.close();
});

/// Waits for what a real process does (the stand-in front door below), looking every 5 ms; no deadline.
async function until(check: () => boolean) {
  while (!check()) await new Promise((r) => setTimeout(r, 5));
}

test("in sandboxes an idle session's process ends after the sandbox idle time, whatever its runtime, and its sandbox is stopped", async () => {
  const time = testClock();
  const r = new Rig({ clock: time.clock });
  // The front door as l4es's: `rm NAME` said deleted, each call kept.
  const calls = join(r.dir, "ssh-calls");
  writeFileSync(join(r.dir, "ssh"), `#!/bin/sh\nprintf '%s\\n' "$*" >> '${calls}'\nfor a; do last=$a; done\necho "deleting $last"\n`);
  chmodSync(join(r.dir, "ssh"), 0o755);
  const path = process.env.PATH;
  process.env.PATH = `${r.dir}:${path}`;
  const unplace = placeIn(r.dir, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host", idleMinutes: 0.002 } }), () => []); // 120 ms
  try {
    const a = message();
    await r.accept(a);
    const b = say("<@UGPT> look", { threadTs: "1700000001.000200", ts: "1700000001.000200" });
    await r.accept(b, "gpt");
    await settle();
    // Ended so that nothing follows (a turn that completes undeclared is nudged on).
    r.claude.last().end({ kind: "aborted" });
    r.codex.last().end({ kind: "aborted" });
    await settle();
    await time.adjust(119);
    await settle();
    assert.ok(!r.claude.last().disposed && !r.codex.last().disposed, "not idle long enough yet");
    await time.adjust(1);
    await settle();
    // Both ended (no warm limit, no Codex exception), both sandboxes stopped through the front door.
    assert.ok(r.claude.last().disposed && r.codex.last().disposed);
    await until(() => existsSync(calls) && readFileSync(calls, "utf8").trim().split("\n").length === 2);
    const stopped = readFileSync(calls, "utf8").trim().split("\n").map((l) => l.split(" ").slice(-3).join(" ")).sort();
    const keyA = sessionKey("cl", "C1", a.threadTs);
    const keyB = sessionKey("gpt", "C1", b.threadTs);
    assert.deepEqual(stopped, [`_.ws@host rm ${sandboxName(keyPart(keyA))}`, `_.ws@host rm ${sandboxName(keyPart(keyB))}`].sort());
  } finally {
    unplace();
    process.env.PATH = path;
    await r.close();
  }
});

/// A stand-in l4es front door in `dir`, on PATH: `ls` answers what `<dir>/ls` holds, `rm NAME` says it deleted it;
/// each call kept in `<dir>/ssh-calls`.
function frontDoor(dir: string): { calls: () => string[]; restore: () => void } {
  const calls = join(dir, "ssh-calls");
  writeFileSync(join(dir, "ssh"), `#!/bin/sh\nprintf '%s\\n' "$*" >> '${calls}'\nfor a; do prev=$last; last=$a; done\nif [ "$last" = ls ]; then cat '${join(dir, "ls")}'; else echo "deleting $last"; fi\n`);
  chmodSync(join(dir, "ssh"), 0o755);
  const path = process.env.PATH;
  process.env.PATH = `${dir}:${path}`;
  return { calls: () => (existsSync(calls) ? readFileSync(calls, "utf8").trim().split("\n").map((l) => l.split(" ").slice(-2).join(" ")) : []), restore: () => (process.env.PATH = path) };
}

test("a session's idle time goes with it to the next station: taken up, it is not idle afresh", async () => {
  const time = testClock();
  const first = new Rig({ clock: time.clock });
  const door = frontDoor(first.dir);
  const unplace = placeIn(first.dir, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host", idleMinutes: 0.002 } }), () => []); // 120 ms
  try {
    await first.accept(message());
    await settle();
    first.claude.last().end({ kind: "aborted" });
    await settle();
    await time.adjust(100);
    await settle();
    const handed = await first.hub.handOver();
    assert.equal(handed.sessions[0]!.idleMs, 100);
    const claude = new FakeDriver("claude");
    const hub = first.newHub({ chats: (id) => (id === "cl" ? first.chat : undefined), drivers: [claude, new FakeDriver("codex")], internal: false });
    await hub.takeUp();
    hub.recover();
    await settle();
    await time.adjust(19);
    await settle();
    assert.ok(!claude.last().disposed, "not idle long enough yet");
    await time.adjust(1);
    await settle();
    assert.ok(claude.last().disposed, "ended 120 ms after it went idle, not 120 ms after it was taken up");
    await hub.shutdown();
  } finally {
    unplace();
    door.restore();
    await first.close();
  }
});

test("a sandbox of a session nothing runs in is stopped; one in use, or not this station's, is left", async () => {
  const r = new Rig();
  const door = frontDoor(r.dir);
  const unplace = placeIn(r.dir, () => sandboxConfig({ sandbox: { ssh: "{name}.ws@host" } }), () => []);
  try {
    const busy = message();
    await r.accept(busy);
    const cold = say("<@UBOT> other", { threadTs: "1700000002.000300", ts: "1700000002.000300" });
    await r.accept(cold);
    await settle();
    // The second's process ended some other way than going idle (it exited).
    r.claude.last().end({ kind: "aborted" });
    await settle();
    await r.hub.evict(sessionKey("cl", "C1", cold.threadTs));
    await settle();
    const name = (m: { threadTs: string }) => sandboxName(keyPart(sessionKey("cl", "C1", m.threadTs)));
    writeFileSync(join(r.dir, "ls"), [
      "Workspace ws",
      "NAME                            STATE     CPU   IDLE",
      `${name(busy)}   running   0%    deleted in 50 min if unused  labels=`,
      `${name(cold)}   running   0%    deleted in 50 min if unused  labels=`,
      "s-someone-else-0123456789       running   0%    deleted in 50 min if unused  labels=",
      `${name({ threadTs: "1700000003.000400" })}   running   0%    1 session(s)  labels=`,
    ].join("\n") + "\n");
    await r.hub.sweepSandboxes();
    assert.deepEqual(door.calls(), ["_.ws@host ls", `rm ${name(cold)}`]);
  } finally {
    unplace();
    door.restore();
    await r.close();
  }
});

test("a running turn is never evicted", async () => {
  const time = testClock();
  const r = new Rig({ maxWarmClaude: 0, warmMinutes: 0, clock: time.clock });
  await r.accept(message());
  await time.adjust(60_000);
  await settle();
  assert.ok(!r.claude.last().disposed);
  await r.close();
});

test("a single-session connect gathers every thread into one session and replies where asked", async () => {
  const r = new Rig();
  const a = say("<@UTEAM> build A");
  await r.accept(a, "team");
  await settle();
  await r.accept(say("unrelated chatter", { addressed: false, channel: "C2" }), "team");
  const b = say("<@UTEAM> build B", { channel: "C2" });
  await r.accept(b, "team");
  await settle();
  assert.equal(r.claude.count(), 1);
  assert.equal(r.store.listSessions().length, 1);
  const bound = r.store.binding("team")!;
  assert.equal(r.session(bound).scope, "all");
  const session = r.claude.last();
  assert.ok(matches(session.steers[0]!, ['thread="C2/', "build B"]));
  assert.ok(![...session.steers, ...session.prompts].join("\n").includes("unrelated chatter"));
  // A reply in a thread the session already follows needs no mention.
  await r.accept(reply(a, "9999.8", "and tests too"), "team");
  await settle();
  assert.ok(session.steers.at(-1)!.includes("and tests too"));
  await r.call(bound, "chat_post", { to: `C2/${b.threadTs}`, text: "B done" });
  assert.deepEqual(r.teamChat.posts, [[{ channel: "C2", threadTs: b.threadTs }, "B done"]]);
  await r.close();
});

test("a single-session connect without require mention hears every message", async () => {
  const r = new Rig({ teamRequireMention: false });
  await r.accept(say("anyone around?", { addressed: false }), "team");
  await settle();
  assert.equal(r.claude.count(), 1);
  assert.ok(r.claude.last().prompts[0]!.includes("anyone around?"));
  await r.close();
});

test("a single-session connect can be pointed at a new or an existing session", async () => {
  const r = new Rig();
  await r.accept(say("<@UTEAM> one"), "team");
  await settle();
  const old = r.store.binding("team")!;
  const fresh = bindSingle(r.hub, "team", null, "值班", null);
  assert.notEqual(fresh, old);
  assert.equal(r.session(fresh).title, "值班");
  await r.accept(say("<@UTEAM> two"), "team");
  await settle();
  assert.equal(r.claude.count(), 2, "the new binding got its own runtime session");
  assert.ok(r.claude.last().prompts[0]!.includes("two"));

  // Binding a session that another connect started: replies still go out where each thread came in.
  const m = say("<@UBOT> from cl");
  await r.accept(m);
  await settle();
  const clKey = sessionKey("cl", "C1", m.threadTs);
  bindSingle(r.hub, "team", clKey, null, null);
  const t = say("<@UTEAM> via team", { channel: "C7" });
  await r.accept(t, "team");
  await settle();
  assert.deepEqual(
    r.store.sessionThreads(clKey).map((x) => [x.thread.channel, x.connect]),
    [
      ["C7", "team"],
      ["C1", "cl"],
    ],
  );
  await r.call(clKey, "chat_post", { to: `C7/${t.threadTs}`, text: "to team thread" });
  await r.call(clKey, "chat_post", { to: `C1/${m.threadTs}`, text: "to cl thread" });
  assert.deepEqual(r.teamChat.texts(), ["to team thread"]);
  assert.deepEqual(r.chat.texts(), ["to cl thread"]);
  assert.throws(() => bindSingle(r.hub, "team", sessionKey("gpt", "C1", "1.1"), null, null), /unknown session/);
  assert.throws(() => bindSingle(r.hub, "cl", null, null, null), /not single-session/);
  await r.close();
});

test("a chat opened on the admin page reaches the session like Slack, and the agent answers there", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  r.claude.last().complete();
  await settle();
  r.store.setTitle(key, "排查");
  const thread = openChat(r.hub, key, "local", null);
  assert.equal(thread.title, "排查", "its own chat keeps the name the session was given");
  sayIn(r.hub, thread.id, "local", "现在进展如何？");
  await settle();
  const prompt = r.claude.last().prompts.at(-1)!;
  assert.ok(prompt.includes(`<message via="web" connect="ember" thread="EMBER/${thread.threadTs}" from="管理员 (local)"`), prompt);
  assert.ok(prompt.includes("现在进展如何"));
  const to = `EMBER/${thread.threadTs}`;
  assert.equal(await r.call(key, "chat_post", { to, text: "快好了", kind: "all_done", done: "答了进展：快好了，没有别的要做" }), `Posted to ${to}, and recorded state all_done.`);
  assert.deepEqual(
    r.said(thread.id).map((x) => [x.authorKind, x.text]),
    [
      ["person", "现在进展如何？"],
      ["agent", "快好了"],
    ],
  );
  assert.equal(r.chat.texts().length, 1, "only the Slack thread's own answer went to Slack");
  assert.ok((await r.call(key, "chat_history", { to })).includes("现在进展如何"));
  assert.throws(() => openChat(r.hub, "nope", "local", null), /unknown session/);
  await r.close();
});

test("a person's message in a chat with several agents reaches each of them once", async () => {
  const r = new Rig();
  const one = newSession(r.hub, chat("claude"));
  const two = newSession(r.hub, chat("codex"));
  addToThread(r.hub, one[1].id, two[0]);
  const quote = { author: "Claude", role: "agent", ts: "1.000001", text: "上一条", comment: "这里" };
  sayIn(r.hub, one[1].id, "a@example.com", "你们俩分一下工", [], [quote]);
  await settle();
  for (const driver of [r.claude, r.codex]) {
    assert.equal(driver.count(), 1);
    const prompt = driver.last().prompts[0]!;
    assert.ok(prompt.includes("[Quote] From your own earlier message 1.000001 in this conversation:\n> 上一条\nTheir comment on it: 这里\n\n你们俩分一下工"), prompt);
  }
  assert.equal(r.store.pendingMessages(one[0]).length + r.store.pendingMessages(two[0]).length, 0);
  const said = r.said(one[1].id);
  assert.equal(said[0]!.text, "你们俩分一下工", "the words are stored as typed; the quote is a column");
  assert.equal(said[0]!.quotes[0]!.comment, "这里");
  await r.close();
});

test("a pending message edited before delivery reaches the agent as edited", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const session = r.claude.last();
  session.unsteerable = true;
  const edited = reply(m, "9999.5", "first draft");
  await r.accept(edited);
  await settle(); // it waits: the running turn takes no steer
  await r.hub.receive("cl", { type: "changed", channel: "C1", threadTs: m.threadTs, ts: edited.ts, text: "final words" });
  session.complete();
  await settle();
  const prompt = session.prompts[1]!;
  assert.ok(prompt.includes("final words") && !prompt.includes("first draft"), prompt);
  assert.equal(r.store.pendingMessages(sessionKey("cl", "C1", m.threadTs)).length, 0);
  await r.close();
});

test("deleting a session ends its process and removes its workspace, the threads only it was in and what the readers kept of its transcript's reading", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const row = r.session(key);
  // The runtime's transcript lives in the profile's home and stays.
  const transcript = join(r.config.profiles[0]!.home, "projects", "x", `${row.runtimeSessionId}.jsonl`);
  mkdirSync(dirname(transcript), { recursive: true });
  writeFileSync(transcript, "{}\n");
  // Read as a reader reads it (read/sessions.ts `transcriptState`).
  const marks = marksDir(r.config.dataDir);
  stateOf("claude", transcriptPaths("claude", r.config.dataDir, homesFirst(r.config.profiles, row.profile), r.store.runtimeSessions(key)).paths, marks);
  assert.equal(readdirSync(marks).length, 1);
  assert.ok(existsSync(row.workspace));
  await deleteSession(r.hub, key);
  assert.ok(r.claude.last().disposed);
  assert.equal(r.store.getSession(key), null);
  assert.equal(r.store.threadAt("slack:T1", "C1", m.threadTs), null);
  assert.ok(!existsSync(row.workspace));
  assert.ok(!existsSync(dirname(row.workspace)));
  assert.ok(existsSync(transcript));
  assert.deepEqual(readdirSync(marks), []);
  await r.close();
});

test("archiving hands an idle session to cold storage, never on a timer for what was archived before", async () => {
  const packed: string[] = [];
  const restored: string[] = [];
  const r = new Rig({ cold: { isCold: () => false, restore: (key) => void restored.push(key), pack: (key) => void packed.push(key) } });
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  await r.call(key, "chat_state", { kind: "final" });
  r.claude.last().complete();
  await settle();
  r.store.setArchived(key, true, MANUAL);
  autoArchive(r.hub, Date.now() + 3 * 86_400_000);
  await settle();
  assert.deepEqual(packed, [], "a timer must not pack old archives");
  archive(r.hub, key, true);
  await settle();
  assert.ok(r.claude.last().disposed, "its idle process ends");
  assert.deepEqual(packed, [key], "an explicit archive does");
  archive(r.hub, key, false);
  assert.deepEqual(restored, [key]);
  await r.close();
});

test("archiving ends the wait and every job and service; only a new message wakes it, and none reaches one archived by hand", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"], now: Date.now() });
  for (const by of [AUTO, MANUAL]) {
    const r = new Rig();
    const stopped: string[] = [];
    r.hub.setJobs({
      stop: async (id) => {
        stopped.push(id);
        r.store.jobEnded(id, "stopped", null);
        return r.store.getJob(id)!;
      },
    });
    const m = message();
    await r.accept(m);
    await settle();
    const key = sessionKey("cl", "C1", m.threadTs);
    r.store.insertJob({ ...watchJob(key), id: "build", token: "tb", watch: false });
    r.store.insertJob({ ...watchJob(key), id: "page", token: "tp", port: 47123, watch: false });
    await r.call(key, "chat_state", { kind: "waiting", seconds: 10, for: "任务跑完" });
    r.claude.last().complete();
    await settle();
    archiveBy(r.hub, key, true, by);
    await settle();
    assert.deepEqual(stopped.sort(), ["build", "page"], by);
    t.mock.timers.tick(30_000);
    r.hub.notify(key, "a job ended");
    await settle();
    assert.equal(r.claude.last().prompts.length, 1, `${by}: neither the clock nor a notice wakes it`);
    assert.ok(r.store.getSession(key)!.archivedAt !== null);
    await r.accept(reply(m, "9999.2", "<@UBOT> 还在吗", { addressed: true }));
    await settle();
    if (by === AUTO) {
      assert.equal(r.store.getSession(key)!.archivedAt, null, "a new message brings it back");
      assert.ok(r.claude.last().prompts.at(-1)!.includes("还在吗"));
    } else {
      assert.ok(r.store.getSession(key)!.archivedAt !== null, "archived by hand, it stays so");
      assert.equal(r.claude.last().prompts.length, 1);
      assert.ok(r.chat.lastText().includes("已手动归档"), r.chat.lastText());
      // Shown again by hand, it hears what is said from then on.
      archive(r.hub, key, false);
      await r.accept(reply(m, "9999.3", "<@UBOT> 回来了", { addressed: true }));
      await settle();
      assert.ok(r.claude.last().prompts.at(-1)!.includes("回来了"));
    }
    await r.close();
  }
});

test("idle chats that are done are archived by the station; busy, blocked, unread and bound ones stay", async () => {
  const r = new Rig();
  const day = 86_400_000;
  const m = message();
  await r.accept(m);
  await settle();
  const idle = sessionKey("cl", "C1", m.threadTs);
  await r.call(idle, "chat_state", { kind: "final" });
  r.claude.last().complete();
  await settle();
  const b = say("<@UBOT> look", { channel: "C2" });
  await r.accept(b);
  await settle();
  const blocked = sessionKey("cl", "C2", b.threadTs);
  await r.call(blocked, "chat_state", { kind: "block" });
  r.claude.last().complete();
  await settle();
  const [web, thread] = newSession(r.hub, chat());
  sayIn(r.hub, thread.id, "local", "hi");
  await settle();
  // The agent's answer is unread: the chat stays.
  await r.call(web, "chat_post", { to: `EMBER/${thread.threadTs}`, text: "hello", kind: "final" });
  r.claude.last().complete();
  await settle();
  await r.accept(say("<@UBOT> hi"), "team");
  await settle();
  const bound = r.store.binding("team")!;
  await r.call(bound, "chat_state", { kind: "final" });
  r.claude.last().complete();
  await settle();

  const now = Date.now();
  const due = autoArchive(r.hub, now);
  assert.ok(r.store.listSessions().every((s) => s.archivedAt === null), "nothing has idled a day yet");
  // The next look is when the first of them will have idled a day, not on an hourly sweep.
  assert.ok(due !== null && due > now && due <= now + day, `next due ${due}`);
  const later = Date.now() + 2 * day;
  autoArchive(r.hub, later);
  assert.equal(r.session(idle).archivedBy, AUTO);
  assert.equal(r.session(blocked).archivedAt, null, "stopped at a block");
  assert.equal(r.session(web).archivedAt, null, "unread");
  assert.equal(r.session(bound).archivedAt, null, "a single-session connect's");
  r.store.setRead("local", thread.id, r.store.lastEntry(thread.id));
  // A job of its own still up (a watch above all): it stays until the job is over.
  r.store.insertJob(watchJob(web));
  autoArchive(r.hub, later);
  assert.equal(r.session(web).archivedAt, null, "its watch runs");
  r.store.jobEnded("job_w", "stopped", null);
  // Pinned by anyone, it stays in the lists.
  r.store.setPin("dev@example.com", web, true);
  autoArchive(r.hub, later);
  assert.equal(r.session(web).archivedAt, null, "pinned");
  r.store.setPin("dev@example.com", web, false);
  autoArchive(r.hub, later);
  assert.equal(r.session(web).archivedBy, AUTO);
  assert.ok(r.store.getThread(thread.id)!.hiddenAt !== null, "its own chat with it");
  // Someone writes in the Slack thread again: its session is back.
  await r.accept(reply(m, "9999.5", "<@UBOT> one more"));
  assert.equal(r.session(idle).archivedAt, null);
  // A chat opened with a session that has one is a chat of its own, archived alone.
  archive(r.hub, web, false);
  r.store.setTitle(web, "值班");
  const second = openChat(r.hub, web, "local", null);
  assert.equal(second.home, null);
  assert.equal(second.title, null, "a chat of its own does not take the session's name");
  archiveChat(r.hub, second.id, true);
  assert.equal(r.session(web).archivedAt, null);
  assert.ok(r.store.getThread(second.id)!.hiddenAt !== null);
  archiveChat(r.hub, thread.id, true);
  assert.equal(r.session(web).archivedBy, MANUAL);
  await settle();
  await r.close();
});

test("a session heard only in Slack is archived after three idle days even when stopped at a block", async () => {
  const r = new Rig();
  const day = 86_400_000;
  const m = message();
  await r.accept(m);
  await settle();
  const blocked = sessionKey("cl", "C1", m.threadTs);
  await r.call(blocked, "chat_state", { kind: "block" });
  r.claude.last().complete();
  await settle();
  const [web, thread] = newSession(r.hub, chat());
  sayIn(r.hub, thread.id, "local", "hi");
  await settle();
  await r.call(web, "chat_state", { kind: "block" });
  r.claude.last().complete();
  await settle();
  r.store.setRead("local", thread.id, r.store.lastEntry(thread.id));

  const now = Date.now();
  const due = autoArchive(r.hub, now + 2 * day);
  assert.equal(r.session(blocked).archivedAt, null, "two days are not enough");
  assert.ok(due !== null && due <= now + 3 * day + 60_000, `next due ${due}`);
  autoArchive(r.hub, now + 4 * day);
  assert.equal(r.session(blocked).archivedBy, AUTO);
  assert.equal(r.session(web).archivedAt, null, "a still.fail chat's block waits for its starter");
  // Someone answers in the Slack thread: it is back.
  await r.accept(reply(m, "9999.5", "<@UBOT> here you go"));
  assert.equal(r.session(blocked).archivedAt, null);
  await settle();
  await r.close();
});

test("pinned chats survive idle archiving, their agent's other chats too, but can be archived by hand", async () => {
  const r = new Rig();
  const [key, thread] = newSession(r.hub, chat());
  r.store.setPin("alice", key, true);
  autoArchive(r.hub, Date.now() + 3 * 86_400_000);
  assert.equal(r.session(key).archivedAt, null);
  assert.equal(r.store.getThread(thread.id)!.hiddenAt, null);
  const second = openChat(r.hub, key, "alice", null);
  autoArchive(r.hub, Date.now() + 3 * 86_400_000);
  assert.equal(r.store.getThread(second.id)!.hiddenAt, null);
  archiveChat(r.hub, second.id, true);
  assert.ok(r.store.getThread(second.id)!.hiddenAt !== null);
  archiveChat(r.hub, thread.id, true);
  assert.ok(r.session(key).archivedAt !== null);
  await settle();
  await r.close();
});

test("kept chats survive idle archiving but can be archived by hand", async () => {
  const r = new Rig();
  const [key, thread] = newSession(r.hub, chat());
  r.store.keepChat("alice", thread.id);
  autoArchive(r.hub, Date.now() + 3 * 86_400_000);
  assert.equal(r.session(key).archivedAt, null);
  assert.equal(r.store.getThread(thread.id)!.hiddenAt, null);
  const second = openChat(r.hub, key, "alice", null);
  r.store.keepChat("alice", second.id);
  autoArchive(r.hub, Date.now() + 3 * 86_400_000);
  assert.equal(r.store.getThread(second.id)!.hiddenAt, null);
  archiveChat(r.hub, second.id, true);
  assert.ok(r.store.getThread(second.id)!.hiddenAt !== null);
  archiveChat(r.hub, thread.id, true);
  assert.ok(r.session(key).archivedAt !== null);
  await settle();
  await r.close();
});

test("where only what the archive review recommended is archived on its own, an idle chat waits for its recommendation", async () => {
  const r = new Rig();
  const later = Date.now() + 3 * 86_400_000;
  const [key, thread] = newSession(r.hub, chat());
  r.edit((raw: any) => { raw.autoArchiveReviewed = true; });
  autoArchive(r.hub, later);
  assert.equal(r.session(key).archivedAt, null, "the review is off: nothing goes");
  r.edit((raw: any) => { raw.automaticDecisions = { completion: { enabled: true, model: "m" } }; });
  autoArchive(r.hub, later);
  assert.equal(r.session(key).archivedAt, null, "not recommended yet");
  r.store.suggestArchive(key, thread.id, r.store.lastEntry(thread.id));
  autoArchive(r.hub, later);
  assert.equal(r.session(key).archivedBy, AUTO);
  await settle();
  await r.close();
});

const withProfile = (id: string, name: string, models: string[]) => (raw: any) => raw.profiles.push({ ...raw.profiles[0], id, name, models });

test("a session changes profile, model and effort by hand, and is taken on by another profile when its own cannot run", async () => {
  const r = new Rig();
  const m = say("<@UBOT> fix the build");
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const refused = async (p: Promise<unknown>) => {
    try {
      await p;
    } catch (error) {
      return (error as Error).message;
    }
    throw new Error("not refused");
  };
  r.edit(withProfile("cc2", "another", ["opus"]));
  // Changed while a turn runs: that turn goes on in its process, which ends before the next turn; the next starts on
  // the new profile.
  const running = r.claude.last();
  await configure(r.hub, key, { profile: "cc2" });
  assert.equal(r.session(key).profile, "cc2");
  assert.ok(!running.disposed, "the running turn is not cut off");
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  running.complete();
  await settle();
  await r.accept({ ...say("<@UBOT> once more"), threadTs: m.threadTs });
  await settle();
  assert.ok(running.disposed, "its process ended before the next turn");
  assert.equal(r.claude.last().options.profile.id, "cc2", "the next turn runs as changed");
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  r.claude.last().complete();
  await settle();
  assert.ok((await refused(configure(r.hub, key, { profile: "cx" }))).includes("无法运行 Claude Code"));
  r.edit(withProfile("cc3", "third", []));
  assert.ok((await refused(configure(r.hub, key, { profile: "cc3" }))).includes("「third」未启用 opus"), "only one with its model enabled");
  // Its model and effort change too, to what a profile of its runtime runs.
  assert.ok((await refused(configure(r.hub, key, { model: "gpt-5" }))).includes("没有可运行 gpt-5 的 Claude Code Profile"));
  assert.ok((await refused(configure(r.hub, key, { effort: "ultra" }))).includes("思考深度只有"));
  r.edit((raw) => raw.profiles.filter((p: any) => p.id === "cc" || p.id === "cc2").forEach((p: any) => (p.models = [...(p.models ?? []), "sonnet"])));
  // Another model on the same profile while a turn runs: its process takes it in place before the next turn, nothing
  // it runs in the background lost to a new start.
  await r.accept({ ...say("<@UBOT> and again"), threadTs: m.threadTs });
  await settle();
  const same = r.claude.last();
  assert.ok(same.busyNow);
  await configure(r.hub, key, { model: "sonnet", effort: "low" });
  assert.deepEqual(same.retuned, [], "not while its turn runs");
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  same.complete();
  await settle();
  await r.accept({ ...say("<@UBOT> on sonnet"), threadTs: m.threadTs });
  await settle();
  assert.equal(r.claude.last(), same, "the same process");
  assert.deepEqual(same.retuned, [["sonnet", "low"]]);
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  same.complete();
  await settle();
  // Idle, one that cannot take it in place (Claude and another effort) ends at once; the next turn starts as changed.
  same.retunable = false;
  await configure(r.hub, key, { effort: "high" });
  assert.ok(same.disposed);
  await configure(r.hub, key, { profile: "cc2", model: "sonnet", effort: "low" });
  let row = r.session(key);
  assert.deepEqual([row.model, row.effort], ["sonnet", "low"]);
  assert.ok(row.profilePinned, "kept to it by hand");
  // Another model alone: what went with the old one starts over, the effort default and the profile the station's pick
  // among those with it enabled.
  r.edit((raw) => raw.profiles.filter((p: any) => p.id === "cc3").forEach((p: any) => (p.models = [...p.models, "haiku"])));
  await configure(r.hub, key, { model: "haiku" });
  row = r.session(key);
  assert.deepEqual([row.model, row.effort, row.profile, row.profilePinned], ["haiku", null, "cc3", false]);
  await configure(r.hub, key, { profile: "cc2", model: "sonnet", effort: "low" });
  // Given back to the station, and its own used up: the next start runs on the other one, which takes it on.
  await configure(r.hub, key, { profile: null });
  assert.ok(!r.session(key).profilePinned);
  await r.hub.evict(key);
  r.hub.accounts.setHealth((id) => (id === "cc2" ? { quota: { state: "ok", windows: [{ label: "每周", usedPercent: 100, resetsAt: null }], detail: null, checkedAt: 0 } } : {}));
  await r.accept({ ...say("<@UBOT> and the tests"), threadTs: m.threadTs });
  await settle();
  assert.equal(r.session(key).profile, "cc");
  await r.close();
});

test("a session given back to the station has its account picked again as a new one's would be, its own process not counted", async () => {
  const r = new Rig();
  const m = say("<@UBOT> fix the build");
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  // Both run its model (opus, its connect's).
  r.edit((raw) => {
    raw.profiles[0].models = ["opus"];
    raw.profiles.push({ ...raw.profiles[0], id: "cc2", name: "another" });
  });
  const used = (cc: number, cc2: number) =>
    r.hub.accounts.setHealth((id) => ({ quota: { state: "ok", windows: [{ label: "5h", usedPercent: id === "cc" ? cc : cc2, resetsAt: null }], detail: null, checkedAt: 0 } }));
  const on = () => [r.session(key).profile, r.session(key).profilePinned];
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  r.claude.last().complete();
  await settle();
  assert.equal(r.session(key).profile, "cc");
  // Its process stays on cc: counted, cc would look the busier one, and it would move for nothing.
  used(30, 40);
  await configure(r.hub, key, { repick: true });
  assert.deepEqual(on(), ["cc", false]);
  // Kept to cc2 by hand, then given back: it stays there until picked again, when the pool's choice takes it.
  await configure(r.hub, key, { profile: "cc2" });
  await configure(r.hub, key, { profile: null });
  assert.deepEqual(on(), ["cc2", false]);
  await configure(r.hub, key, { profile: "cc2" });
  await configure(r.hub, key, { repick: true });
  assert.deepEqual(on(), ["cc", false]);
  // With a profile given, that one is kept to.
  await configure(r.hub, key, { profile: "cc2", repick: true });
  assert.deepEqual(on(), ["cc2", true]);
  await r.close();
});

test("a session leaves an account whose five hours are nearly full for one with room, when its context was just compacted or is about to be", async () => {
  const time = testClock();
  const r = new Rig({ clock: time.clock });
  const now = time.clock.currentTimeMillisUnsafe();
  const HOUR = 60 * 60 * 1000;
  const used: Record<string, number> = { cc: 10, cc2: 10 };
  const quota = (five: number) => ({
    state: "ok",
    windows: [
      { label: "5 小时", usedPercent: five, resetsAt: now + 2 * HOUR, minutes: 300 },
      { label: "每周", usedPercent: 20, resetsAt: now + 100 * HOUR, minutes: 7 * 24 * 60 },
    ],
    detail: null,
    checkedAt: now,
  });
  r.hub.accounts.setHealth((id) => ({ quota: quota(used[id] ?? 0) }));
  const m = say("<@UBOT> fix the build");
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const turn = async (text: string) => {
    await r.accept({ ...say(`<@UBOT> ${text}`), threadTs: m.threadTs });
    await settle();
  };
  const done = async () => {
    await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
    r.claude.last().complete();
    await settle();
  };
  // Its calls as the usage counter records them: [turn, context] each, on its profile.
  let call = 0;
  const calls = (session: string, profile: string, each: [string, number][]) =>
    r.store.recordUsage(`/t/${session}`, { session, offset: call, model: "m" }, "claude", each.map(([turn, context]) => [
      { id: `c${call++}`, at: now + call, model: "m", subagent: false, fast: false, input: 0, cacheRead: context, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context, window: null },
      { turn, person: null, thread: null, profile },
    ]));
  await done();
  // Both run its model.
  r.edit((raw) => (raw.profiles[0].models = ["opus"]));
  r.edit(withProfile("cc2", "another", ["opus"]));
  const own = r.session(key).profile;
  const other = own === "cc" ? "cc2" : "cc";
  // Where its model is compacted here: another session's went from 200k to 15k.
  calls("ember:elsewhere", own, [["x", 200_000], ["x", 15_000]]);
  // Nearly full, its context neither just compacted nor about to be: it stays, in the same process.
  used[own] = 85;
  calls(key, own, [["t1", 60_000], ["t1", 90_000]]);
  const first = r.claude.last();
  await turn("once more");
  assert.equal(r.claude.last(), first);
  assert.equal(r.session(key).profile, own);
  await done();
  // Its runtime compacted it, but its process has work going in the background, which would end with it: it stays.
  calls(key, own, [["t2", 120_000], ["t2", 20_000]]);
  first.tasks = [{ id: "a1", kind: "agent", description: "profile the build" }];
  await r.hub.evict(key);
  assert.ok(!first.disposed);
  await turn("meanwhile");
  assert.equal(r.claude.last(), first);
  assert.equal(r.session(key).profile, own);
  await done();
  // That work over: the next turn starts afresh on the other, its process ended first.
  first.tasks = [];
  await turn("and again");
  assert.ok(first.disposed);
  assert.equal(r.session(key).profile, other);
  assert.equal(r.claude.last().options.profile.id, other);
  await done();
  // Both nearly full: it stays where it is, compacted or not.
  used[other] = 90;
  const second = r.claude.last();
  calls(key, other, [["t3", 120_000], ["t3", 20_000]]);
  await turn("on and on");
  assert.equal(r.claude.last(), second);
  assert.equal(r.session(key).profile, other);
  await done();
  // About to be compacted: three quarters of where its model is compacted here.
  used[own] = 10;
  calls(key, other, [["t4", 100_000], ["t5", 140_000], ["t6", 151_000]]);
  await turn("nearly full");
  assert.equal(r.session(key).profile, own);
  await done();
  // Kept to it by hand: it stays however full.
  used[own] = 90;
  used[other] = 10;
  await configure(r.hub, key, { profile: own });
  calls(key, own, [["t7", 120_000], ["t7", 20_000]]);
  await turn("pinned");
  assert.equal(r.session(key).profile, own);
  await done();
  await r.close();
});

test("a session runs on the subscription; its allowance used up, on the API key, and back on the subscription when it can run again and that loses little", async () => {
  const time = testClock();
  const r = new Rig({ clock: time.clock });
  const now = time.clock.currentTimeMillisUnsafe();
  r.edit((raw) => {
    raw.profiles[0] = { ...raw.profiles[0], access: { kind: "subscription" }, models: ["opus"] };
    raw.profiles.push({ id: "key", runtime: "claude", home: "homes/key", access: { kind: "anthropic-api", key: "k" }, models: ["opus"] });
  });
  const used = { cc: 60 };
  r.hub.accounts.setHealth((id) =>
    id === "cc" ? { quota: { state: "ok", windows: [{ label: "每周", usedPercent: used.cc, resetsAt: null }], detail: null, checkedAt: now } } : { quota: { state: "unsupported", windows: [], detail: "", checkedAt: now } },
  );
  const m = say("<@UBOT> fix the build");
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  assert.equal(r.session(key).profile, "cc", "an API key, counted as half used, does not come before it");
  const turn = async (text: string) => {
    await r.accept({ ...say(`<@UBOT> ${text}`), threadTs: m.threadTs });
    await settle();
  };
  const done = async () => {
    await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
    r.claude.last().complete();
    await settle();
  };
  let call = 0;
  const calls = (profile: string, each: [string, number][]) =>
    r.store.recordUsage(`/t/${key}`, { session: key, offset: call, model: "m" }, "claude", each.map(([turn, context]) => [
      { id: `c${call++}`, at: now + call, model: "m", subagent: false, fast: false, input: 0, cacheRead: context, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context, window: null },
      { turn, person: null, thread: null, profile },
    ]));
  await done();
  // Used up: the next turn goes on on the key.
  used.cc = 100;
  await turn("once more");
  assert.equal(r.session(key).profile, "key");
  await done();
  // Refilled, its context neither just compacted nor about to be: it stays on the key for now.
  used.cc = 0;
  calls("key", [["t1", 60_000], ["t1", 90_000]]);
  const onKey = r.claude.last();
  await turn("and again");
  assert.equal(r.claude.last(), onKey);
  assert.equal(r.session(key).profile, "key");
  await done();
  // Compacted: the next turn starts afresh on the subscription.
  calls("key", [["t2", 120_000], ["t2", 20_000]]);
  await turn("and on");
  assert.ok(onKey.disposed);
  assert.equal(r.session(key).profile, "cc");
  await done();
  await r.close();
});

test("the station's variables for its agents changed: a process that could take a model in place still ends, the next starts with them", async () => {
  const r = new Rig();
  const m = say("<@UBOT> fix the build");
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  const running = r.claude.last();
  // Changed while a turn runs: that turn goes on; its process ends before the next.
  r.hub.everyChanged();
  await settle();
  assert.ok(!running.disposed, "the running turn is not cut off");
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  running.complete();
  await settle();
  await r.accept({ ...say("<@UBOT> once more"), threadTs: m.threadTs });
  await settle();
  assert.ok(running.disposed, "its process ended before the next turn");
  assert.deepEqual(running.retuned, [], "not retuned in place");
  const next = r.claude.last();
  assert.notEqual(next, running);
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  next.complete();
  await settle();
  // Idle: it ends at once.
  r.hub.everyChanged();
  await settle();
  assert.ok(next.disposed);
  assert.deepEqual(next.retuned, []);
  await r.close();
});

test("a deleted profile's sessions go on on another, and stop when no other can run them", async () => {
  const r = new Rig();
  const m = say("<@UBOT> fix the build");
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  r.edit(withProfile("cc2", "another", ["opus"]));
  r.hub.store.setSessionProfile(key, "cc", true);
  // Deleted while a turn runs on it: that turn goes on, the next runs on the other one, kept to it no longer.
  const running = r.claude.last();
  r.edit((raw) => (raw.profiles = raw.profiles.filter((p: any) => p.id !== "cc")));
  await r.hub.profileGone("cc");
  assert.deepEqual([r.session(key).profile, r.session(key).profilePinned], ["cc2", false]);
  assert.ok(!running.disposed && running.aborts === 0, "the running turn is not cut off");
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  running.complete();
  await settle();
  await r.accept({ ...say("<@UBOT> once more"), threadTs: m.threadTs });
  await settle();
  assert.ok(running.disposed, "its process ended before the next turn");
  const moved = r.claude.last();
  assert.equal(moved.options.profile.id, "cc2");
  // The last one that runs it deleted too: its turn is stopped and its process does not start another.
  r.edit((raw) => (raw.profiles = raw.profiles.filter((p: any) => p.id !== "cc2")));
  await r.hub.profileGone("cc2");
  await settle();
  assert.equal(moved.aborts, 1);
  moved.end({ kind: "aborted" });
  await settle();
  await r.accept({ ...say("<@UBOT> and again"), threadTs: m.threadTs });
  await settle();
  assert.ok(moved.disposed, "not left running on the deleted profile");
  assert.equal(r.claude.last(), moved, "no process started without a profile");
  await r.close();
});

test("a connect or a new chat can keep its sessions to one profile; otherwise the pool picks", async () => {
  const r = new Rig();
  r.edit((raw) => {
    raw.profiles.push({ ...raw.profiles[0], id: "cc2", name: "second", models: ["opus"] });
    raw.connects.find((c: any) => c.id === "cl").bind.profile = "cc2";
  });
  const m = say("<@UBOT> hi");
  await r.accept(m);
  await settle();
  const row = r.session(sessionKey("cl", "C1", m.threadTs));
  assert.deepEqual([row.profile, row.profilePinned], ["cc2", true]);
  // A new chat given a profile keeps to it; one that has not the model on is refused.
  const pinned = (model: string) => ({ ...chat(), model, profile: "cc2" });
  const [key] = newSession(r.hub, pinned("opus"));
  assert.deepEqual([r.session(key).profile, r.session(key).profilePinned], ["cc2", true]);
  assert.throws(() => newSession(r.hub, pinned("sonnet")), /未启用 sonnet/);
  const [auto] = newSession(r.hub, chat());
  assert.ok(!r.session(auto).profilePinned);
  await r.close();
});

test("the Slack thread a turn works for says what the agent is doing until the turn ends", async () => {
  const r = new Rig();
  const m = say("<@UBOT> fix the build");
  await r.accept(m);
  await settle();
  const session = r.claude.last();
  session.events({ type: "live", event: { kind: "start", id: "t1", step: "tool", tool: "Bash" } });
  session.events({ type: "live", event: { kind: "end", id: "t1" } });
  session.complete();
  await settle();
  assert.deepEqual(
    r.chat.statuses.map((s) => s[2]),
    ["正在思考…", "正在运行命令…", "正在思考…", ""],
  );
  assert.equal(r.chat.statuses[0]![0], `C1/${m.threadTs}`);
  assert.equal(r.chat.statuses[0]![1], m.ts, "the message that started it, for the fallback reaction");
  await r.close();
});

test("agents in one thread hear each other: a post reaches the thread's other sessions, marked a bot, and not its author", async () => {
  const r = new Rig();
  const root = say("<@UBOT> <@UGPT> work this out together");
  await r.accept(root);
  await r.accept(root, "gpt");
  await settle();
  const [cl, gpt] = [sessionKey("cl", "C1", root.threadTs), sessionKey("gpt", "C1", root.threadTs)];
  await r.call(cl, "chat_state", { kind: "final" });
  await r.call(gpt, "chat_state", { kind: "final" });
  r.claude.last().complete();
  r.codex.last().complete();
  await settle();
  const before = r.claude.last().prompts.length;
  await r.call(gpt, "chat_post", { to: `C1/${root.threadTs}`, text: "I'll take the tests; can you do the build?" });
  await settle();
  const prompts = r.claude.last().prompts;
  assert.equal(prompts.length, before + 1);
  assert.ok(matches(prompts.at(-1)!, ['from="ember (<@UGPT>)" bot ts="', "\">\nI'll take the tests; can you do the build?"]), prompts.at(-1));
  assert.ok(!r.codex.last().prompts.some((p) => p.includes("I'll take the tests")), "not back to its author");
  // Slack's copy of that post, seen through the other connect, is not a message of its own.
  await r.accept(reply(root, "9999.9", "I'll take the tests; can you do the build?", { user: "UGPT" }));
  await settle();
  assert.equal(r.claude.last().prompts.length, before + 1);
  await r.close();
});

test("in a chat on the station's page with several agents, what one posts reaches the others", async () => {
  const r = new Rig();
  const one = newSession(r.hub, chat("claude"));
  const two = newSession(r.hub, chat("codex"));
  addToThread(r.hub, one[1].id, two[0]);
  sayIn(r.hub, one[1].id, "local", "分一下工");
  await settle();
  await r.call(one[0], "chat_state", { kind: "final" });
  await r.call(two[0], "chat_state", { kind: "final" });
  r.claude.last().complete();
  r.codex.last().complete();
  await settle();
  await r.call(one[0], "chat_post", { to: `EMBER/${one[1].threadTs}`, text: "我来写接口" });
  await settle();
  const heard = r.codex.last().prompts.at(-1)!;
  assert.ok(matches(heard, ['from="Claude Code" bot ts="', '">\n我来写接口']), heard);
  await r.close();
});

test("a mention Slack sends twice at once makes one session without an error", async () => {
  const r = new Rig();
  for (let i = 0; i < 20; i++) {
    const m = say("<@UBOT> fix the build", { ts: `${100 + i}.000001`, threadTs: `${100 + i}.000001` });
    // app_mention and message for the same post, handled side by side as the Slack socket does.
    await Promise.all([r.accept(m), r.accept(m)]);
  }
  await settle();
  assert.ok(!r.chat.texts().some((t) => t.includes("无法创建会话")), JSON.stringify(r.chat.texts()));
  assert.equal(r.hub.gates.size, 0);
  assert.equal(r.store.listSessions().length, 20);
  await r.close();
});

test("a turn that runs out of allowance goes on on another account, or once the session is changed", async () => {
  const r = new Rig();
  r.edit((raw) => {
    raw.profiles[0].models = ["opus"];
    raw.profiles.push({ ...raw.profiles[0], id: "cc2", name: "second" });
  });
  const spent = (text: string) => ({ kind: "failed" as const, reason: classifyResult(text), message: text });
  const m = message();
  await r.accept(m);
  await settle();
  const first = r.claude.last();
  const key = first.options.route;
  const on = r.session(key).profile;
  // Left to the station: another account takes it on, in a process of its own, and goes on.
  first.end(spent("You've hit your session limit · resets 3:40am (Asia/Tokyo)"));
  await settle();
  assert.ok(first.disposed, "its process ran on the account left");
  const second = r.claude.last();
  assert.equal(r.claude.count(), 2);
  assert.notEqual(second.options.profile.id, on);
  assert.equal(r.session(key).profile, second.options.profile.id);
  assert.ok(!r.session(key).profilePinned);
  assert.ok(r.chat.texts().every((t) => !t.includes("额度")), "it just goes on, saying nothing");
  // In a new runtime session of its own (sessions/afresh.ts).
  assert.equal(second.options.resume, undefined);
  assert.equal(second.prompts.length, 1);
  assert.ok(matches(second.prompts[0]!, ["This is a new conversation", GO_ON_AFTER_SPENT]), second.prompts[0]);
  // That one runs out too: none left, so it says so and waits.
  second.end(spent("usage limit reached"));
  await settle();
  assert.equal(r.claude.count(), 2, "no account left to go on with");
  assert.ok(matches(r.chat.lastText(), ["已达到额度或速率限制", "usage limit reached"]));
  // Changed by hand (here: kept to the first again): it goes on by itself.
  await configure(r.hub, key, { profile: on });
  await settle();
  const third = r.claude.last();
  assert.equal(r.claude.count(), 3);
  assert.equal(third.options.profile.id, on);
  assert.equal(third.prompts.length, 1);
  assert.ok(matches(third.prompts[0]!, ["This is a new conversation", GO_ON_AFTER_SPENT]), third.prompts[0]);
  // A change after a turn that ended well starts nothing.
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  third.complete();
  await settle();
  await configure(r.hub, key, { profile: null });
  await settle();
  assert.equal(r.claude.count(), 3);
  await r.close();
});

test("an account spent with none to move to is said once; what wakes it waits for the refill, a person is tried at once", async () => {
  const time = testClock();
  const r = new Rig({ clock: time.clock });
  const HOUR = 60 * 60 * 1000;
  const now = time.clock.currentTimeMillisUnsafe();
  r.hub.accounts.setHealth(() => ({ quota: { state: "ok", windows: [{ label: "5h", usedPercent: 100, resetsAt: now + 2 * HOUR, minutes: 300 }], detail: null, checkedAt: now } }));
  const spent = { kind: "failed" as const, reason: classifyResult("usage limit reached"), message: "You've hit your limit · resets 5pm" };
  const said = () => r.chat.texts().filter((t) => t.includes("已达到额度或速率限制"));
  const m = message();
  await r.accept(m);
  await settle();
  const agent = r.claude.last();
  const key = agent.options.route;
  agent.end(spent);
  await settle();
  assert.equal(said().length, 1);
  assert.ok(matches(said()[0]!, ["没有其他可用账号", "You've hit your limit"]), said()[0]);
  // Jobs' notices meanwhile: no turn for them (it would run into the allowance again), nothing said again.
  r.hub.notify(key, "a job ended");
  r.hub.notify(key, "another job ended");
  await settle();
  assert.equal(agent.prompts.length, 1, "no turn while its account is spent");
  assert.equal(said().length, 1);
  // At the refill: it goes on by itself; the notices follow that turn.
  await time.adjust(2 * HOUR);
  await settle();
  assert.equal(agent.prompts.length, 2);
  assert.equal(agent.prompts[1], GO_ON_AFTER_REFILL);
  // Spent again (the refill read wrong): still said only once, and it waits again (an hour, none known now).
  r.hub.accounts.setHealth(() => ({}));
  agent.end(spent);
  await settle();
  assert.equal(said().length, 1, "the thread ends with it already");
  assert.equal(agent.prompts.length, 2);
  // A person's message is tried at once, and its failure told them.
  await r.accept(reply(m, "9999.3", "<@UBOT> 还在吗", { addressed: true }));
  await settle();
  assert.equal(agent.prompts.length, 3);
  assert.ok(agent.prompts[2]!.includes("还在吗"));
  agent.end(spent);
  await settle();
  assert.equal(said().length, 2, "told the person who asked");
  await time.adjust(HOUR);
  await settle();
  assert.equal(agent.prompts[3], GO_ON_AFTER_REFILL);
  // A turn that ends well: what waited is given.
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  agent.complete();
  await settle();
  assert.ok(matches(agent.prompts[4]!, ["a job ended", "another job ended"]), agent.prompts[4]);
  await r.close();
});

test("taken up by the next station, a process runs on the account it was started on, whose allowance it spends; it moves before its next turn", async () => {
  const time = testClock();
  const r = new Rig({ clock: time.clock });
  r.edit((raw) => {
    raw.profiles[0].models = ["opus"];
    raw.profiles.push({ ...raw.profiles[0], id: "cc2", name: "second" });
  });
  const now = time.clock.currentTimeMillisUnsafe();
  const full = { quota: { state: "ok", windows: [{ label: "每周", usedPercent: 100, resetsAt: now + 24 * 60 * 60 * 1000, minutes: 10080 }], detail: null, checkedAt: now } };
  // Both start on the first account, the second full for now.
  r.hub.accounts.setHealth((id) => (id === "cc2" ? full : {}));
  const busy = message();
  const idle = message();
  await r.accept(busy);
  await r.accept(idle);
  await settle();
  const [busyOld, idleOld] = r.claude.sessions;
  const busyKey = busyOld!.options.route;
  const idleKey = idleOld!.options.route;
  assert.ok(busyOld!.options.profile.id === "cc" && idleOld!.options.profile.id === "cc");
  idleOld!.complete();
  await settle();
  await r.call(idleKey, "chat_state", { kind: "all_done", done: "answered" });
  idleOld!.complete();
  await settle();
  await r.hub.handOver();
  // The next station finds the first account full and the second refilled.
  const claude = new FakeDriver("claude");
  const hub = r.newHub({ chats: (id) => (id === "cl" ? r.chat : undefined), drivers: [claude, new FakeDriver("codex")], internal: false });
  hub.accounts.setHealth((id) => (id === "cc" ? full : {}));
  await hub.takeUp();
  hub.recover();
  await settle();
  const busyTaken = claude.sessions.find((s) => s.sessionId === busyOld!.sessionId)!;
  const idleTaken = claude.sessions.find((s) => s.sessionId === idleOld!.sessionId)!;
  assert.ok(busyTaken.options.profile.id === "cc" && idleTaken.options.profile.id === "cc", "taken up where their processes run");
  assert.ok(r.session(busyKey).profile === "cc" && r.session(idleKey).profile === "cc", "not moved by being taken up");
  // The running turn runs into the first account's allowance: the second takes it on.
  busyTaken.end({ kind: "failed", reason: classifyResult("usage limit reached"), message: "You've hit your weekly limit · resets Oct 26 at 9pm" });
  await settle();
  assert.ok(busyTaken.disposed);
  const busyNext = claude.last();
  assert.equal(busyNext.options.profile.id, "cc2");
  assert.equal(r.session(busyKey).profile, "cc2");
  assert.ok(matches(busyNext.prompts[0]!, [GO_ON_AFTER_SPENT]), busyNext.prompts[0]);
  assert.ok(r.chat.texts().every((t) => !t.includes("额度")), "it just goes on, saying nothing");
  // The idle one, given a message, leaves its process on the full account first.
  await hub.accept("cl", reply(idle, "9999.5", "<@UBOT> one more", { addressed: true }));
  await settle();
  assert.ok(idleTaken.disposed);
  assert.deepEqual(idleTaken.prompts, []);
  const idleNext = claude.last();
  assert.equal(idleNext.options.profile.id, "cc2");
  assert.ok(idleNext.prompts[0]!.includes("one more"), idleNext.prompts[0]);
  await hub.shutdown();
  await r.close();
});

test("on another account a conversation goes on in a new runtime session, its history read on; on its own it is taken up", async () => {
  const r = new Rig();
  r.edit((raw) => {
    raw.profiles[0].models = ["opus"];
    raw.profiles.push({ ...raw.profiles[0], id: "cc2", name: "second" });
  });
  const spent = { kind: "failed" as const, reason: classifyResult("usage limit reached"), message: "usage limit reached" };
  // The profiles share a home here, so their transcripts, in the project of the session's workspace.
  const transcript = (id: string, said: string, context: number) => {
    const path = join(r.config.profiles[0]!.home, "projects", claudeProject(r.session(key).workspace)!, `${id}.jsonl`);
    mkdirSync(dirname(path), { recursive: true });
    const usage = { input_tokens: 3, cache_read_input_tokens: context - 1003, cache_creation_input_tokens: 1000 };
    writeFileSync(path, [{ type: "user", message: { role: "user", content: said } }, { type: "assistant", message: { id: `m-${id}`, role: "assistant", content: [{ type: "text", text: "ok" }], usage } }].map((l) => JSON.stringify(l)).join("\n") + "\n");
  };
  const m = message();
  await r.accept(m);
  await settle();
  const first = r.claude.last();
  const key = first.options.route;
  const on = r.session(key).profile;
  transcript(first.id(), "first", 200_000);
  first.end(spent);
  await settle();
  // Moved to the other account: not taken up there, but started afresh, told where its past is.
  const second = r.claude.last();
  assert.notEqual(second.options.profile.id, on);
  assert.equal(second.options.resume, undefined);
  assert.notEqual(second.id(), first.id());
  assert.equal(second.prompts.length, 1);
  assert.ok(matches(second.prompts[0]!, ["This is a new conversation", `session_history with chat ${key}`, `C1/${m.threadTs}`, GO_ON_AFTER_SPENT]), second.prompts[0]);
  assert.deepEqual(r.store.runtimeSessions(key), [first.id(), second.id()]);
  assert.equal(r.store.ranOn(key, second.id()), second.options.profile.id);
  // Its history goes on from the first's.
  transcript(second.id(), "second", 1_000);
  assert.deepEqual(r.hub.live.before(key, 100, 100)![1].filter((e) => e.kind === "user").map((e) => e.text), ["first", "second"]);
  // Its process gone, on the same account: taken up as before.
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  second.complete();
  await settle();
  await r.hub.evict(key);
  await r.accept({ ...message(), threadTs: m.threadTs });
  await settle();
  const third = r.claude.last();
  assert.equal(third.options.resume, second.id());
  assert.ok(!third.prompts[0]!.includes("This is a new conversation"));
  // Back on the first account, however short the conversation: afresh again.
  third.end(spent);
  await settle();
  await configure(r.hub, key, { profile: on });
  await settle();
  const fourth = r.claude.last();
  assert.equal(fourth.options.resume, undefined);
  assert.ok(matches(fourth.prompts[0]!, ["This is a new conversation", GO_ON_AFTER_SPENT]), fourth.prompts[0]);
  assert.deepEqual(r.store.runtimeSessions(key), [first.id(), second.id(), fourth.id()]);
  await r.close();
});

test("a process ended with work going in the background: its next turn is told what stopped, its subagents taken to the new runtime session", async () => {
  const time = testClock();
  const r = new Rig({ clock: time.clock });
  const now = time.clock.currentTimeMillisUnsafe();
  r.edit((raw) => {
    raw.profiles[0].models = ["opus"];
    raw.profiles.push({ ...raw.profiles[0], id: "cc2", name: "second" });
  });
  const used: Record<string, number> = {};
  r.hub.accounts.setHealth((id) => ({ quota: { state: "ok", windows: [{ label: "每周", usedPercent: used[id] ?? 10, resetsAt: now + 100 * 3600_000, minutes: 7 * 24 * 60 }], detail: null, checkedAt: now } }));
  const m = message();
  await r.accept(m);
  await settle();
  const first = r.claude.last();
  const key = first.options.route;
  const on = r.session(key).profile;
  // Its transcript and its subagent's, where Claude Code keeps them (the profiles share a home here).
  const project = join(r.config.profiles[0]!.home, "projects", "-w");
  mkdirSync(join(project, first.id(), "subagents"), { recursive: true });
  writeFileSync(join(project, `${first.id()}.jsonl`), `${JSON.stringify({ type: "user", message: { role: "user", content: "hi" } })}\n`);
  writeFileSync(join(project, first.id(), "subagents", "agent-a1.jsonl"), "{}\n");
  writeFileSync(join(project, first.id(), "subagents", "agent-a1.meta.json"), "{}");
  first.tasks = [{ id: "a1", kind: "agent", description: "profile the build" }, { id: "b1", kind: "command", description: "watch CI" }];
  await r.call(key, "chat_state", { kind: "waiting", seconds: 600, for: "the build" });
  first.complete();
  await settle();
  // Its account used up: the next turn is on the other, in a new runtime session.
  used[on] = 100;
  await r.accept({ ...message(), threadTs: m.threadTs });
  await settle();
  assert.ok(first.disposed);
  const second = r.claude.last();
  assert.notEqual(second.options.profile.id, on);
  assert.notEqual(second.id(), first.id());
  assert.ok(matches(second.prompts[0]!, ["This is a new conversation", "background was stopped", "- subagent a1 (profile the build): SendMessage to it goes on from where it stopped", "- background command b1 (watch CI)\n"]), second.prompts[0]);
  assert.ok(existsSync(join(project, second.id(), "subagents", "agent-a1.jsonl")));
  assert.ok(existsSync(join(project, second.id(), "subagents", "agent-a1.meta.json")));
  // Told once.
  await r.call(key, "chat_post", { to: `C1/${m.threadTs}`, text: "done", kind: "final" });
  second.complete();
  await settle();
  await r.accept({ ...message(), threadTs: m.threadTs });
  await settle();
  assert.equal(r.claude.last(), second);
  assert.ok(!second.prompts[1]!.includes("background was stopped"), second.prompts[1]);
  await r.close();
});

test("codex model efforts validate new chats, changes and pinned accounts", async () => {
  const r = new Rig();
  r.edit((raw) => {
    const p = raw.profiles.find((p: any) => p.id === "cx");
    p.models = ["gpt-6-astra"];
    raw.profiles.push({ ...p, id: "limited" });
  });
  r.hub.accounts.setHealth((id) => ({
    check: {
      state: "ok", detail: "", models: ["gpt-6-astra"], checkedAt: 0,
      modelEfforts: { codex: { "gpt-6-astra": id === "limited" ? ["low", "medium", "high", "xhigh", "max"] : ["low", "medium", "high", "xhigh", "max", "ultra"] } },
    },
  }));
  const fresh = (profile: string | null, effort: string) => ({ runtime: "codex" as const, profile, model: "openai/gpt-6-astra", effort, createdBy: "local" });
  const [key] = newSession(r.hub, fresh(null, "max"));
  assert.equal(r.session(key).effort, "max");
  assert.throws(() => newSession(r.hub, fresh(null, "minimal")));
  assert.throws(() => newSession(r.hub, fresh(null, "ultra")));
  const [pinned] = newSession(r.hub, fresh("cx", "ultra"));
  assert.equal(r.session(pinned).effort, "ultra");
  // A profile change must not carry an unsupported depth to the destination.
  await assert.rejects(configure(r.hub, pinned, { profile: "limited" }));
  await assert.rejects(configure(r.hub, pinned, { profile: null }));
  await configure(r.hub, key, { profile: "cx", effort: "ultra" });
  assert.equal(r.session(key).effort, "ultra");
  await configure(r.hub, key, { profile: null, effort: null });
  assert.equal(r.session(key).effort, null);
  await r.close();
});

test("a session from before a change is told it once, and a new one never", async () => {
  const r = new Rig();
  const m = message();
  await r.accept(m);
  await settle();
  const key = sessionKey("cl", "C1", m.threadTs);
  assert.ok(!r.claude.last().prompts[0]!.includes("still.fail changed how you work"), "a new session has today's instructions");
  await r.call(key, "chat_state", { kind: "all_done", done: "答完了它问的事" });
  r.claude.last().complete();
  await settle();
  // As a session from before the notes: told them with its next turn, once.
  r.store.setToldNotes(key, 0);
  await r.accept(reply(m, "9999.1", "还有一件"));
  await settle();
  const prompts = r.claude.last().prompts;
  assert.ok(prompts.at(-1)!.startsWith("[still.fail changed how you work"), prompts.at(-1));
  const full = join(r.session(key).workspace, ".stillfail-instructions.md");
  assert.ok(prompts.at(-1)!.includes(full), "it says where today's instructions are");
  assert.equal(readFileSync(full, "utf8"), r.claude.last().options.instructions, "the file contains the full current instructions");
  assert.equal(r.store.toldNotes(key), latest());
  await r.call(key, "chat_state", { kind: "all_done", done: "答完了它问的事" });
  r.claude.last().complete();
  await settle();
  await r.accept(reply(m, "9999.2", "再一件"));
  await settle();
  assert.ok(!r.claude.last().prompts.at(-1)!.includes("still.fail changed how you work"));
  await r.close();
});

test("fast is per session, and null restores the subscription default", async () => {
  const r = new Rig();
  const [a] = newSession(r.hub, { ...chat("codex"), fast: true });
  const [b] = newSession(r.hub, chat("codex"));
  assert.equal(r.session(a).fast, true);
  assert.equal(r.session(b).fast, null);
  r.store.setRuntimeSessionId(a, "thread-a");
  r.store.setRuntimeSessionId(b, "thread-b");
  await configure(r.hub, a, { fast: false });
  assert.equal(r.store.codexSessionFast("thread-a"), false);
  assert.equal(r.store.codexSessionFast("thread-b"), null);
  await configure(r.hub, a, {});
  assert.equal(r.session(a).fast, false, "unrelated changes preserve an explicit standard speed");
  await configure(r.hub, a, { fast: null });
  assert.equal(r.session(a).fast, null);
  const [claude] = newSession(r.hub, chat("claude"));
  await assert.rejects(configure(r.hub, claude, { fast: true }));
  await r.close();
});

/// A machine with one Claude Code session and one Codex session (machine_sessions/tests.rs `machine`).
function machine(root: string, project: string) {
  const roots = { claude: join(root, ".claude/projects"), codex: join(root, ".codex/sessions") };
  const lines = (records: unknown[]) => records.map((r) => `${JSON.stringify(r)}\n`).join("");
  const cwd = project;
  // As Claude Code names a project's directory: every character but a letter or a digit as `-` (C:\a\b is C--a-b).
  const claudeDir = join(roots.claude, cwd.replace(/[^A-Za-z0-9]/g, "-"));
  mkdirSync(claudeDir, { recursive: true });
  writeFileSync(
    join(claudeDir, "11111111-aaaa-bbbb-cccc-000000000001.jsonl"),
    lines([
      { type: "ai-title", aiTitle: "Old name" },
      { type: "user", cwd, isMeta: true, timestamp: "2026-09-01T00:00:00.000Z", message: { content: "meta" } },
      { type: "user", cwd, timestamp: "2026-09-01T00:00:01.000Z", message: { content: "<command-name>/model</command-name>" } },
      { type: "user", cwd, timestamp: "2026-09-01T00:00:02.000Z", message: { content: "fix   the\nbuild" } },
      { type: "assistant", cwd, timestamp: "2026-09-01T00:00:03.000Z", message: { content: [{ type: "thinking", thinking: "hm" }, { type: "text", text: "Looking." }] } },
      { type: "assistant", cwd, timestamp: "2026-09-01T00:00:04.000Z", message: { content: [{ type: "tool_use", id: "t1", name: "Bash", input: {} }] } },
      { type: "user", cwd, timestamp: "2026-09-01T00:00:05.000Z", message: { content: [{ type: "tool_result", tool_use_id: "t1", content: "ok" }] } },
      { type: "assistant", cwd, isSidechain: true, timestamp: "2026-09-01T00:00:05.500Z", message: { content: [{ type: "text", text: "a subagent" }] } },
      { type: "assistant", cwd, timestamp: "2026-09-01T00:00:06.000Z", message: { model: "claude-opus-5-5", content: [{ type: "text", text: "Fixed." }] } },
      { type: "assistant", cwd, isApiErrorMessage: true, timestamp: "2026-09-01T00:00:06.500Z", message: { content: [{ type: "text", text: "Not logged in · Please run /login" }] } },
      { type: "user", cwd, isCompactSummary: true, timestamp: "2026-09-01T00:00:07.000Z", message: { content: "This session is being continued…" } },
      { type: "user", cwd, timestamp: "2026-09-01T00:00:08.000Z", message: { content: [{ type: "text", text: "thanks" }] } },
      { type: "ai-title", aiTitle: "Fix the build" },
    ]),
  );
  const codexDir = join(roots.codex, "2026/09/02");
  mkdirSync(codexDir, { recursive: true });
  writeFileSync(
    join(codexDir, "rollout-2026-09-02T00-00-00-22222222-aaaa-bbbb-cccc-000000000001.jsonl"),
    lines([
      { type: "session_meta", payload: { id: "22222222-aaaa-bbbb-cccc-000000000001", cwd } },
      { type: "response_item", timestamp: "2026-09-02T00:00:01.000Z", payload: { type: "message", role: "user", content: [{ type: "input_text", text: "add a test" }] } },
      { type: "turn_context", payload: { model: "gpt-5.5" } },
      { type: "response_item", timestamp: "2026-09-02T00:00:03.000Z", payload: { type: "message", role: "assistant", content: [{ type: "output_text", text: "Added." }] } },
    ]),
  );
  return roots;
}

test("a session the machine kept goes on in a chat, run in its own directory, with what was said in it", async () => {
  const { find } = await import("../src/read/machine.ts");
  const { continueMachineSession } = await import("../src/sessions/lifecycle.ts");
  const { readTimeline } = await import("../src/read/transcript.ts");
  const r = new Rig();
  const root = join(r.dir, "machine");
  const project = join(root, "app");
  mkdirSync(project, { recursive: true });
  writeFileSync(join(project, "main.rs"), "fn main() {}");
  const roots = machine(root, project);
  const found = find(roots, "claude", "11111111-aaaa-bbbb-cccc-000000000001")!;
  const [key, thread] = await continueMachineSession(r.hub, roots, found, "local");
  const row = r.session(key);
  assert.equal(row.cwd, project);
  assert.equal(row.runtimeSessionId, found.id);
  assert.ok(row.workspace.endsWith("workspace") && !row.workspace.startsWith(project));
  assert.equal(r.store.getThread(thread.id)!.title, "Fix the build");
  const copy = join(r.dir, "transcripts/claude", found.path.slice(roots.claude.length + 1));
  assert.deepEqual(readFileSync(copy), readFileSync(found.path));
  const said = r.said(thread.id);
  // Only a note of where it came from, linking to what was said before: nothing of it is copied into the chat.
  assert.equal(said.length, 1);
  assert.equal(said[0]!.authorKind, "ember");
  assert.ok(said[0]!.text.startsWith("继续本机 Claude Code 在"), said[0]!.text);
  const last = readTimeline("claude", found.path).length - 1;
  assert.ok(said[0]!.text.endsWith(`[查看之前的对话](?history=${key}&entry=${last})`), said[0]!.text);
  await settle();
  assert.equal(r.claude.count(), 0, "what was said before is not handed to the agent again");

  sayIn(r.hub, thread.id, "local", "and the tests");
  await settle();
  const opened = r.claude.last();
  assert.equal(opened.options.resume, found.id);
  assert.equal(opened.options.cwd, project);
  assert.equal(opened.options.instructions, "", "its system prompt is left as it began");
  assert.equal(opened.prompts.length, 1);
  const first = opened.prompts[0]!;
  assert.ok(first.startsWith("This session began in a terminal and now goes on in still.fail"), first);
  assert.ok(first.includes("<stillfail-instructions>") && first.includes("and the tests"));
  assert.ok(first.includes(`- Project directory: ${project}.`));
  opened.complete();
  await settle();
  sayIn(r.hub, thread.id, "local", "one more");
  await settle();
  assert.ok(!r.claude.last().prompts.at(-1)!.includes("<stillfail-instructions>"), "said once");

  // Going on with it again is the same chat.
  const again = find(roots, "claude", found.id)!;
  assert.equal((await continueMachineSession(r.hub, roots, again, "local"))[0], key);

  // Deleting the chat leaves the project and the machine's transcript alone.
  r.claude.last().complete();
  await settle();
  await deleteSession(r.hub, key);
  assert.ok(existsSync(join(project, "main.rs")));
  assert.ok(existsSync(found.path));
  await r.close();
});

test("a continued session that cannot be resumed is told to read the terminal's own transcript", async () => {
  const { find } = await import("../src/read/machine.ts");
  const { continueMachineSession } = await import("../src/sessions/lifecycle.ts");
  const r = new Rig();
  const root = join(r.dir, "machine");
  const project = join(root, "app");
  mkdirSync(project, { recursive: true });
  const roots = machine(root, project);
  r.roots = roots;
  const found = find(roots, "claude", "11111111-aaaa-bbbb-cccc-000000000001")!;
  const [key, thread] = await continueMachineSession(r.hub, roots, found, "local");
  r.claude.unresumable.add(found.id);
  sayIn(r.hub, thread.id, "local", "具体什么问题");
  await settle();
  const opened = r.claude.last();
  assert.equal(opened.options.resume, undefined);
  const first = opened.prompts[0]!;
  // The machine's own transcript, not the station's copy of it.
  assert.ok(first.includes(`what was said there is in ${found.path}`) && !first.includes(join(r.dir, "transcripts")), first);
  assert.ok(first.includes(`session_history with chat ${key}`), first);
  await r.close();
});

// root reads a directory whatever its mode says.
// Windows has no chmod that keeps the owner out.
test("a directory the station may not read is told as that, not left to the agent to fail in", { skip: process.getuid?.() === 0 || process.platform === "win32" }, async () => {
  const { find } = await import("../src/read/machine.ts");
  const { continueMachineSession } = await import("../src/sessions/lifecycle.ts");
  const r = new Rig();
  const root = join(r.dir, "machine");
  const project = join(root, "Documents/proj");
  mkdirSync(project, { recursive: true });
  const roots = machine(root, project);
  const found = find(roots, "claude", "11111111-aaaa-bbbb-cccc-000000000001")!;
  // As macOS privacy protection answers a station nobody gave access to: it may stat the directory, not list it.
  chmodSync(project, 0o000);
  try {
    await assert.rejects(continueMachineSession(r.hub, roots, found, "local"), /无权读取目录/);
    assert.equal(r.store.listSessions().length, 0);
    // One continued while it could be read, and read no more later: its turn says why, and no agent is started.
    chmodSync(project, 0o755);
    const [, thread] = await continueMachineSession(r.hub, roots, found, "local");
    chmodSync(project, 0o000);
    sayIn(r.hub, thread.id, "local", "go on");
    await settle();
    assert.equal(r.claude.count(), 0);
    const notice = r.said(thread.id).at(-1)!;
    assert.equal(notice.authorKind, "ember");
    assert.ok(notice.text.includes("无权读取目录") && notice.text.includes(project), notice.text);
  } finally {
    chmodSync(project, 0o755);
  }
  await r.close();
});

test("a session whose directory is gone is not continued", async () => {
  const { find } = await import("../src/read/machine.ts");
  const { continueMachineSession } = await import("../src/sessions/lifecycle.ts");
  const r = new Rig();
  const root = join(r.dir, "machine");
  const roots = machine(root, join(root, "gone"));
  const found = find(roots, "codex", "22222222-aaaa-bbbb-cccc-000000000001")!;
  await assert.rejects(continueMachineSession(r.hub, roots, found, "local"), /已不存在/);
  assert.equal(r.store.listSessions().length, 0);
  await r.close();
});
