// The Cursor driver (src/agents/cursor.ts) and the station's own program it runs (src/agents/cursor-bridge.mjs) against a
// fake SDK (test/fake/cursor-sdk) under the real runner: turns and their steps, what the SDK is given (the key, the
// station's tools with their token, the rules folder with the instructions, the SDK's home apart from HOME, the model),
// the transcript and usage the bridge keeps, a steer into the running turn, cancel, failures told apart, the process
// exiting, resuming, and a session taken up by a next driver (with a snapshot, and after a crash) with its turn's end told
// once.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { modelOf } from "../src/agents/cursor-bridge.mjs";
import { CursorDriver, classifyFailure, cursorHome, outcomeOf, rulesFolder } from "../src/agents/cursor.ts";
import { cursorCall, cursorOutput } from "../src/agents/live.ts";
import type { AgentSession, OpenOptions, RuntimeEvent } from "../src/agents/runtime.ts";
import { allLeft } from "../src/agents/runner.ts";
import { readTimeline, transcriptPath } from "../src/read/transcript.ts";
import { callsOf } from "../src/usage/counter.ts";

const sdk = join(dirname(fileURLToPath(import.meta.url)), "fake", "cursor-sdk");
// Inherited, and not to reach the agent.
process.env.CURSOR_API_KEY = "leaked";
// Short: the runners' sockets live under it (104 bytes at most on macOS).
const data = mkdtempSync(process.platform === "win32" ? join(tmpdir(), "cu-") : "/tmp/cu-");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/// Looks every 20 ms until `done` holds: what real processes do has no event here. No deadline.
async function eventually(done: () => boolean) {
  while (!done()) await sleep(20);
}
/// The fifos a `gate:<name>` turn waits at (test/fake/cursor-sdk): `open(part)` lets it go on.
function gates(dump: string, name: string) {
  const at = `${dump}.${name}`;
  if (process.platform !== "win32") for (const part of ["a", "b"]) execFileSync("/usr/bin/mkfifo", [`${at}.${part}`]);
  return { open: (part: "a" | "b") => writeFile(`${at}.${part}`, "go"), said: () => existsSync(`${at}.said`) };
}
const drivers: CursorDriver[] = [];
after(async () => {
  await Promise.all(drivers.map((d) => d.shutdown()));
  rmSync(data, { recursive: true, force: true });
});

function driver() {
  const d = new CursorDriver({ data, sdk });
  drivers.push(d);
  return d;
}

let n = 0;
/// A Cursor account signed in (its key in the home's cursor/auth.json, as accounts/cursor.ts leaves it).
function options(extra: Partial<OpenOptions> = {}, signedIn = true): OpenOptions & { dump: string } {
  const i = ++n;
  const home = join(data, `h${i}`);
  mkdirSync(cursorHome(home), { recursive: true });
  if (signedIn) writeFileSync(join(cursorHome(home), "auth.json"), JSON.stringify({ apiKey: "crsr_k1", email: "a@b.c", keyName: "still.fail", createdAt: 1 }));
  // A workspace's skills (not the profile home's: agent-home.ts).
  const skills = join(data, `skills${i}`);
  mkdirSync(join(skills, "s1"), { recursive: true });
  const dump = join(data, `dump${i}`);
  return {
    key: `slack:T1:C${i}:1700000000.000${i}`,
    profile: { id: "cu", runtime: "cursor", home, access: { kind: "subscription" }, env: { FAKE_DUMP: dump } },
    cwd: data,
    instructions: "be brief",
    skills,
    mcpToken: "tok",
    mcpUrl: "http://127.0.0.1:4750/mcp",
    route: `route${i}`,
    dump,
    ...extra,
  };
}

function listen() {
  const events: RuntimeEvent[] = [];
  const push = (e: RuntimeEvent) => void events.push(e);
  const until = (what: (events: RuntimeEvent[]) => boolean) => eventually(() => what(events));
  return { events, push, until };
}

const ends = (events: RuntimeEvent[]) => events.filter((e) => e.type === "turnEnded");
const ended = (k: number) => (events: RuntimeEvent[]) => ends(events).length >= k;
const live = (events: RuntimeEvent[]) => events.flatMap((e) => (e.type === "live" ? [e.event] : []));
const deltas = (events: RuntimeEvent[]) => live(events).flatMap((e) => (e.kind === "delta" ? [e.text] : []));
const outcome = (events: RuntimeEvent[], k = 0) => (ends(events)[k] as Extract<RuntimeEvent, { type: "turnEnded" }>).outcome;
const dumped = (dump: string) => readFileSync(dump, "utf8").trim().split("\n").map((l) => JSON.parse(l));

describe("the Cursor driver", { concurrency: true }, () => {
  test("a turn completes, the SDK given the key, the station's tools, the rules folder and a home of its own", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    assert.match(session.id(), /^agent-[0-9a-f-]{36}$/);
    await session.prompt("say:hello");
    assert.equal(session.busy(), true);
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    assert.equal(session.busy(), false);
    assert.ok(!events.some((e) => e.type === "turnStarted"), "our own prompt's turn is not one started without us");
    assert.deepEqual(live(events).filter((e) => e.kind === "start").map((e) => (e as { step: string }).step), ["thinking", "text"]);
    assert.deepEqual(deltas(events), ["thinking ", "it over", "hel", "lo"]);

    const [created] = dumped(o.dump);
    // The key the sign-in minted, not the station's own; the station's tools with the session's token.
    assert.equal(created.env.CURSOR_API_KEY, "crsr_k1");
    assert.deepEqual(created.create.mcpServers, { stillfail: { type: "http", url: o.mcpUrl, headers: { Authorization: "Bearer tok" } } });
    // Auto when the profile names no model.
    assert.deepEqual(created.create.model, { id: "default" });
    // The station's instructions a project rule in a folder of the session's own; the person's Cursor rules not read.
    const rules = created.create.local.dirs[0];
    assert.deepEqual(created.create.local, { cwd: o.cwd, dirs: [rules], settingSources: ["project"] });
    assert.match(readFileSync(join(rules, ".cursor", "rules", "stillfail.mdc"), "utf8"), /^---\ndescription: still\.fail station\nalwaysApply: true\n---\nbe brief\n$/);
    assert.ok(!existsSync(join(rules, "AGENTS.md")), "no memory but the one with the instructions");
    assert.ok(existsSync(join(rules, ".cursor", "skills", "s1")), "the workspace's skills linked in");
    // The SDK's home in the profile's (its agents kept there), while HOME stays the station's for what the agent runs.
    assert.equal(created.home, join(cursorHome(o.profile.home), "sessions", "home"));
    assert.equal(created.env.HOME, process.env.HOME);
    assert.ok(existsSync(join(created.home, ".cursor", "fake-agents", session.id())));
  });

  test("the model named is the SDK's selection, its variant's parameters apart; another between turns is the next prompt's", async () => {
    assert.deepEqual(modelOf("gpt-5.5[reasoning=high, fast=false]"), { id: "gpt-5.5", params: [{ id: "reasoning", value: "high" }, { id: "fast", value: "false" }] });
    assert.deepEqual(modelOf("composer-2.5"), { id: "composer-2.5" });
    assert.equal(modelOf(""), undefined);
    const d = driver();
    const o = options({ model: "composer-2.5" });
    const { push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("one");
    await until(ended(1));
    assert.equal(session.retune?.({ ...o, model: "gpt-5.5[reasoning=high]" }), true);
    await session.prompt("two");
    await until(ended(2));
    const sends = dumped(o.dump).filter((l) => l.send !== undefined);
    assert.deepEqual(sends.map((s) => s.model), [{ id: "composer-2.5" }, { id: "gpt-5.5", params: [{ id: "reasoning", value: "high" }] }]);
  });

  test("a tool call is a step with its input and output; the transcript has the turn, the call and its result, and its usage", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("cmd");
    await until(ended(1));
    const call = live(events).find((e) => e.kind === "start" && e.step === "tool") as { tool: string; input: string; id: string };
    assert.equal(call.tool, "shell");
    assert.deepEqual(JSON.parse(call.input), { command: "ls" });
    assert.ok(live(events).some((e) => e.kind === "delta" && e.id === call.id && e.field === "output" && e.text === "a\nb\n"));
    assert.ok(live(events).some((e) => e.kind === "end" && e.id === call.id));

    const path = transcriptPath("cursor", o.profile.home, session.id());
    assert.equal(path, join(cursorHome(o.profile.home), "sessions", `${session.id()}.jsonl`));
    const timeline = readTimeline("cursor", path!).map(({ kind, text, tool, ok }) => ({ kind, text, ...(tool ? { tool } : {}), ...(ok !== undefined ? { ok } : {}) }));
    assert.deepEqual(timeline, [
      { kind: "user", text: "cmd" },
      { kind: "tool_call", text: JSON.stringify({ command: "ls" }, null, 2), tool: "shell" },
      { kind: "tool_result", text: "a\nb\n", ok: true },
      { kind: "assistant", text: "listed" },
    ]);
    const calls = callsOf("cursor", readFileSync(path!, "utf8"), false, { model: null, codexId: null });
    assert.deepEqual(calls.map(({ input, cacheRead, cacheWrite, output }) => ({ input, cacheRead, cacheWrite, output })), [{ input: 10, cacheRead: 3, cacheWrite: 0, output: 5 }]);
  });

  test("a steer goes into the running turn, which takes it and goes on; with nothing running it is not delivered", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    assert.equal(await session.steer("too early"), false);
    await session.prompt("hold");
    await until((e) => deltas(e).join("") === "waiting");
    assert.equal(await session.steer("also this"), true);
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    assert.equal(deltas(events).join(""), "waitingsteer:also this");
    // The message steered in is the history's, in its place.
    const timeline = readTimeline("cursor", transcriptPath("cursor", o.profile.home, session.id())!);
    assert.deepEqual(timeline.map((e) => [e.kind, e.text]), [["user", "hold"], ["assistant", "waiting"], ["user", "also this"], ["assistant", "steer:also this"]]);
  });

  test("abort cancels the turn; its end comes as aborted, and the session goes on", async () => {
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options(), push);
    await session.prompt("hold");
    await until((e) => deltas(e).join("") === "waiting");
    await session.abort();
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "aborted" });
    await session.prompt("say:again");
    await until(ended(2));
    assert.deepEqual(outcome(events, 1), { kind: "completed" });
  });

  test("failures are told apart: a key refused is the sign-in's, a run's error the model's", async () => {
    assert.equal(classifyFailure("unauthenticated", "Invalid User API Key"), "auth");
    assert.equal(classifyFailure("resource_exhausted", "usage limit reached"), "rate_limit");
    assert.equal(classifyFailure("", "the model failed"), "model");
    assert.deepEqual(outcomeOf({ status: "finished" }), { kind: "completed" });
    assert.deepEqual(outcomeOf({ status: "cancelled" }), { kind: "aborted" });
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options({}, false), push);
    // Not signed in: no key, and the inherited one is not it.
    await session.prompt("say:hi");
    await until(ended(1));
    assert.equal((outcome(events) as { reason: string }).reason, "auth");
    assert.equal(session.busy(), false);
    const s2 = await driver().open(options(), push);
    await s2.prompt("error:internal");
    await until(ended(2));
    assert.deepEqual(outcome(events, 1), { kind: "failed", reason: "model", message: "the model failed (internal)" });
  });

  test("a call to the station's tools failing as unreachable is told as toolsLost, named as Claude Code names it", async () => {
    assert.deepEqual(cursorCall("mcp", { providerIdentifier: "stillfail", toolName: "chat_post", args: { text: "hi" } }), ["mcp__stillfail__chat_post", { text: "hi" }]);
    assert.equal(cursorOutput({ status: "success", value: { content: [{ text: { text: "ok" } }] } }), "ok");
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options(), push);
    await session.prompt("tools");
    await until(ended(1));
    assert.ok(events.some((e) => e.type === "toolsLost" && /ECONNREFUSED/.test(e.why)));
    assert.ok(live(events).some((e) => e.kind === "start" && e.tool === "mcp__stillfail__chat_post"));
  });

  test("the process exiting during a turn fails it as exited, then closes the session", async () => {
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options(), push);
    await session.prompt("exit");
    await until((e) => e.some((x) => x.type === "closed"));
    assert.equal((outcome(events) as { reason: string }).reason, "exited");
  });

  test("a session is resumed by its id in a new process; one the station has no transcript of is refused before it starts", async () => {
    const o = options();
    const first = listen();
    const one = await driver().open(o, first.push);
    const id = one.id();
    await one.prompt("one");
    await first.until(ended(1));
    await one.dispose();
    const second = listen();
    const two = await driver().open({ ...o, resume: id }, second.push);
    assert.equal(two.id(), id);
    await two.prompt("two");
    await second.until(ended(1));
    assert.deepEqual(readTimeline("cursor", transcriptPath("cursor", o.profile.home, id)!).filter((e) => e.kind === "assistant").map((e) => e.text), ["one", "two"]);
    await assert.rejects(driver().open({ ...o, resume: "agent-gone" }, () => {}), /no Cursor session agent-gone/);
  });

  test("the rules folder is the session's own, written again with its instructions", () => {
    const home = join(data, "rules-home");
    mkdirSync(home, { recursive: true });
    const a = rulesFolder(home, "k1", "first");
    assert.equal(rulesFolder(home, "k1", "second"), a);
    assert.notEqual(rulesFolder(home, "k2", "other"), a);
    assert.match(readFileSync(join(a, ".cursor", "rules", "stillfail.mdc"), "utf8"), /\nsecond\n$/);
  });

  for (const crashed of [false, true]) {
    test(`a next driver takes the session up ${crashed ? "after a crash (no snapshot)" : "from its snapshot"}: the turn ends once, no live event twice`, async () => {
      const o = options();
      const a = listen();
      const first = driver();
      const gate = gates(o.dump, "g");
      const session = await first.open(o, a.push);
      await session.prompt("gate:g");
      await a.until((e) => deltas(e).join("") === "first");
      let snapshot: unknown = null;
      if (!crashed) snapshot = JSON.parse(JSON.stringify(session.snapshot()));
      first.detach();
      // (the station let go before the next takes up, as the hub waits: every line handled acknowledged)
      await allLeft();
      const b = listen();
      const taken: AgentSession = await driver().adopt(o, snapshot, b.push);
      assert.equal(taken.id(), session.id());
      assert.equal(taken.busy(), true);
      await gate.open("a");
      await eventually(gate.said);
      await gate.open("b");
      await b.until(ended(1));
      assert.deepEqual(outcome(b.events), { kind: "completed" });
      assert.equal(ends(a.events).length + ends(b.events).length, 1, "the turn's end told once");
      assert.equal([...deltas(a.events), ...deltas(b.events)].join(""), "firstsecond", "no live event twice");
    });
  }
});
