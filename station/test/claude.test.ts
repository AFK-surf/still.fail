// The Claude Code driver (src/agents/claude.ts) against a fake claude (test/fake/claude: stream-json as the CLI writes
// it) under the real runner: turns, failures and how they are told apart, abort, steer, a turn of its own, the process
// exiting, background_tools, what it is started with, and a session taken up by a next driver (with a snapshot, and
// after a crash) with its turn's end told once and no live event twice.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, delimiter, dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { ClaudeDriver, type ClaudeDriverOptions, SILENT_SUBAGENTS, SUBAGENT_HOOK, type Turn, backgroundOf, classifyResult, hooksOf, onFrame } from "../src/agents/claude.ts";
import { RenewRefused } from "../src/accounts/console.ts";
import { Said } from "../src/ops/i18n.ts";
import { REPO_RULES_COMMAND, REPO_RULES_HOOK, hookCommand, hookNode } from "../src/agents/repo-rules.ts";
import { SLACK_SPOKEN, SPEAKS } from "../src/tools/mcp.ts";
import { claudeProject } from "../src/read/transcript.ts";
import { allLeft, existingRunners } from "../src/agents/runner.ts";
import { modelLimitOf } from "../src/agents/runtime.ts";
import type { AgentSession, OpenOptions, RuntimeEvent } from "../src/agents/runtime.ts";

const fake = join(dirname(fileURLToPath(import.meta.url)), "fake");
process.env.PATH = `${fake}${delimiter}${process.env.PATH}`;
// Inherited, and not to reach the agent.
process.env.CLAUDECODE = "1";
process.env.CLAUDE_CODE_OAUTH_TOKEN = "leaked";
// Short: the runners' sockets live under it (104 bytes at most on macOS).
const data = mkdtempSync(process.platform === "win32" ? join(tmpdir(), "cl-") : "/tmp/cl-");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/// Looks every 20 ms until `done` holds: what real processes do has no event here. No deadline (it comes, however
/// slow the machine, or the test hangs).
async function eventually(done: () => boolean) {
  while (!done()) await sleep(20);
}
/// The fifos a `gate:<n>:<k>:<name>` turn waits at (test/fake/claude.mjs): `open(part)` lets it go on.
function gates(dump: string, name: string) {
  const at = `${dump}.${name}`;
  if (process.platform !== "win32") for (const part of ["a", "b"]) execFileSync("/usr/bin/mkfifo", [`${at}.${part}`]);
  return { open: (part: "a" | "b") => writeFile(`${at}.${part}`, "go"), said: () => existsSync(`${at}.said`) };
}
const drivers: ClaudeDriver[] = [];
after(async () => {
  await Promise.all(drivers.map((d) => d.shutdown()));
  rmSync(data, { recursive: true, force: true });
});

function driver(
  machineToken?: (env?: unknown, rejected?: string) => Promise<{ token: string; expiresAt: number }>,
  subscriptionToken?: ClaudeDriverOptions["subscriptionToken"],
) {
  const d = new ClaudeDriver({ data, machineToken, subscriptionToken });
  drivers.push(d);
  return d;
}

let n = 0;
function options(extra: Partial<OpenOptions> & { machine?: boolean } = {}): OpenOptions & { dump: string } {
  const i = ++n;
  const home = join(data, `h${i}`);
  mkdirSync(home, { recursive: true });
  // A login in its file: nothing is looked for in the keychain.
  writeFileSync(join(home, ".credentials.json"), "{}");
  const dump = join(data, `dump${i}`);
  const { machine, ...rest } = extra;
  return {
    key: `slack:T1:C${i}:1700000000.000${i}`,
    profile: { id: "cc", runtime: "claude", home, access: { kind: "opencode-go", key: "k1" }, env: { FAKE_DUMP: dump }, machine },
    cwd: data,
    instructions: "be brief",
    mcpToken: "tok",
    mcpUrl: "http://127.0.0.1:4750/mcp",
    route: `route${i}`,
    dump,
    ...rest,
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
const deltas = (events: RuntimeEvent[]) => events.flatMap((e) => (e.type === "live" && e.event.kind === "delta" ? [e.event.text] : []));
const outcome = (events: RuntimeEvent[], k = 0) => (ends(events)[k] as Extract<RuntimeEvent, { type: "turnEnded" }>).outcome;
const stdin = (dump: string) => readFileSync(`${dump}.stdin`, "utf8").trim().split("\n").map((l) => JSON.parse(l));

// Each test has its own driver, profile and runners: they run side by side.
test("what a process runs in the background, as its task frames tell it", () => {
  const turn: Turn = { busy: false, aborting: false, authFailure: null, closed: false };
  const feed = (frame: object) => onFrame(frame, turn, () => {}, () => {});
  const ids = () => backgroundOf(turn).map((t) => `${t.kind}:${t.id}:${t.description}`);
  feed({ type: "system", subtype: "init" });
  feed({ type: "system", subtype: "task_started", task_id: "a1", task_type: "local_agent", description: "gaps", is_backgrounded: true });
  feed({ type: "system", subtype: "task_started", task_id: "b1", task_type: "local_bash", description: "watch CI", is_backgrounded: true });
  feed({ type: "system", subtype: "task_started", task_id: "b2", task_type: "local_bash", description: "build", is_backgrounded: false });
  feed({ type: "system", subtype: "task_started", task_id: "b3", task_type: "local_bash", description: "test", is_backgrounded: false });
  // A subagent's own command is the subagent's.
  feed({ type: "system", subtype: "task_started", task_id: "b4", task_type: "local_bash", description: "its", is_backgrounded: true, owned_by_subagent: true });
  assert.deepEqual(ids(), ["agent:a1:gaps", "command:b1:watch CI"]);
  // Moved to the background (ctrl+b); one waited on ends.
  feed({ type: "system", subtype: "task_updated", task_id: "b2", patch: { is_backgrounded: true } });
  feed({ type: "system", subtype: "task_notification", task_id: "b3", status: "completed" });
  assert.deepEqual(ids(), ["agent:a1:gaps", "command:b1:watch CI", "command:b2:build"]);
  feed({ type: "result", result: "ok" });
  assert.deepEqual(ids(), ["agent:a1:gaps", "command:b1:watch CI", "command:b2:build"]);
  // Ended: told by a notification, or by an update with a final status.
  feed({ type: "system", subtype: "task_updated", task_id: "a1", patch: { status: "killed", end_time: 1 } });
  feed({ type: "system", subtype: "task_notification", task_id: "b1", status: "failed" });
  feed({ type: "system", subtype: "task_updated", task_id: "b2", patch: { status: "running" } });
  assert.deepEqual(ids(), ["command:b2:build"]);
});

test("what it has going in the background is said again as it changes, each with when it was seen starting", () => {
  const turn: Turn = { busy: false, aborting: false, authFailure: null, closed: false };
  const told: unknown[] = [];
  let now = 1_000;
  const feed = (frame: object) => onFrame(frame, turn, (e) => void (e.type === "live" && e.event.kind === "tasks" && told.push(e.event.tasks)), () => {}, () => now);
  feed({ type: "system", subtype: "init" });
  feed({ type: "system", subtype: "task_started", task_id: "a1", task_type: "local_agent", description: "gaps", is_backgrounded: true });
  now = 5_000;
  // One the turn waits on is not in the background: nothing said of it, until it is moved there.
  feed({ type: "system", subtype: "task_started", task_id: "b1", task_type: "local_bash", description: "build", is_backgrounded: false });
  assert.equal(told.length, 1);
  now = 9_000;
  feed({ type: "system", subtype: "task_updated", task_id: "b1", patch: { is_backgrounded: true } });
  feed({ type: "result", result: "ok" });
  feed({ type: "system", subtype: "task_notification", task_id: "a1", status: "completed" });
  assert.deepEqual(told, [
    [{ id: "a1", kind: "agent", description: "gaps", startedAt: 1_000 }],
    [{ id: "a1", kind: "agent", description: "gaps", startedAt: 1_000 }, { id: "b1", kind: "command", description: "build", startedAt: 5_000 }],
    [{ id: "b1", kind: "command", description: "build", startedAt: 5_000 }],
  ]);
});

test("a /compact that compacted nothing ends failed, saying why; one that did, completed", () => {
  const ended: unknown[] = [];
  const emit = (e: RuntimeEvent) => e.type === "turnEnded" && ended.push(e.outcome);
  const turn: Turn = { busy: true, aborting: false, authFailure: null, closed: false, compacting: true };
  // As Claude Code 2.1.289 says it: compacting, how it went, then a result of success all the same.
  onFrame({ type: "system", subtype: "status", status: "compacting" }, turn, emit, () => {});
  onFrame({ type: "system", subtype: "status", status: null, compact_result: "failed", compact_error: "Not enough messages to compact." }, turn, emit, () => {});
  onFrame({ type: "system", subtype: "init" }, turn, emit, () => {});
  onFrame({ type: "result", subtype: "success", is_error: false }, turn, emit, () => {});
  assert.deepEqual(ended, [{ kind: "failed", reason: "other", message: "Not enough messages to compact." }]);
  assert.equal(turn.compacting, false);
  Object.assign(turn, { busy: true, compacting: true });
  onFrame({ type: "system", subtype: "status", status: null, compact_result: "success" }, turn, emit, () => {});
  onFrame({ type: "system", subtype: "compact_boundary", compact_metadata: { trigger: "manual" } }, turn, emit, () => {});
  onFrame({ type: "result", subtype: "success", is_error: false }, turn, emit, () => {});
  assert.deepEqual(ended[1], { kind: "completed" });
  // A failed compaction in a turn of its own (automatic) is not this turn's failure.
  Object.assign(turn, { busy: true });
  onFrame({ type: "system", subtype: "status", status: null, compact_result: "failed", compact_error: "x" }, turn, emit, () => {});
  onFrame({ type: "result", subtype: "success", is_error: false }, turn, emit, () => {});
  assert.deepEqual(ended[2], { kind: "completed" });
});

test("a command a turn waited on and was never told ended does not outlive the turn", () => {
  const turn: Turn = { busy: false, aborting: false, authFailure: null, closed: false };
  onFrame({ type: "system", subtype: "task_started", task_id: "b1", task_type: "local_bash", description: "x", is_backgrounded: false }, turn, () => {}, () => {});
  onFrame({ type: "result", result: "ok" }, turn, () => {}, () => {});
  assert.deepEqual(backgroundOf(turn), []);
  assert.deepEqual(turn.tasks, {});
});

describe("the Claude Code driver", { concurrency: true }, () => {
  test("a text-only request disables built-in and configured MCP tools", async () => {
    const d = driver();
    const o = options({ textOnly: true });
    const session = await d.open(o, listen().push);
    // Opening starts the runner; the fake writes its invocation when its process actually begins.
    await eventually(() => existsSync(o.dump) && readFileSync(o.dump, "utf8").endsWith("\n"));
    const started = JSON.parse(readFileSync(o.dump, "utf8").trim());
    const args = started.argv as string[];
    assert.equal(args[args.indexOf("--tools") + 1], "");
    assert.ok(args.includes("--strict-mcp-config"));
    assert.ok(args.includes("--no-session-persistence"));
    assert.ok(!args.includes("--dangerously-skip-permissions"));
    assert.deepEqual(JSON.parse(args[args.indexOf("--mcp-config") + 1]!), { mcpServers: {} });
    // With none of the station's tools, nothing to keep a subagent from, and nothing said of hooks.
    const settings = JSON.parse(args[args.indexOf("--settings") + 1]!);
    assert.equal(settings.hooks.PreToolUse, undefined);
    assert.equal("disableAllHooks" in settings, false);
    await session.dispose();
  });

  test("a turn completes, from a process started with the flags and environment of claude.rs", async () => {
    const d = driver();
    const o = options({ model: "m1", effort: "high" });
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    assert.match(session.id(), /^[0-9a-f-]{36}$/);
    await session.prompt("say:hello");
    assert.equal(session.busy(), true);
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    assert.equal(session.busy(), false);
    assert.ok(!events.some((e) => e.type === "turnStarted"), "our own prompt's turn is not one started without us");
    const live = events.flatMap((e) => (e.type === "live" ? [e.event] : []));
    assert.deepEqual(live.filter((e) => e.kind !== "phase").map((e) => e.kind), ["start", "delta", "end"]);
    assert.deepEqual(live.filter((e) => e.kind === "phase").map((e) => (e as { phase: string }).phase), ["requesting", "responding", "working"]);
    assert.deepEqual(deltas(events), ["hello"]);

    const started = JSON.parse(readFileSync(o.dump, "utf8").trim());
    const mcp = JSON.stringify({ mcpServers: { stillfail: { type: "http", url: o.mcpUrl, headers: { Authorization: "Bearer ${STILLFAIL_MCP_TOKEN}" } } } });
    assert.deepEqual(started.argv, [
      "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
      "--dangerously-skip-permissions", "--session-id", session.id(), "--model", "m1", "--effort", "high",
      "--append-system-prompt", "be brief", "--mcp-config", mcp,
      "--disallowedTools", "ScheduleWakeup,CronCreate,CronDelete,CronList,RemoteTrigger", "--settings", started.argv.at(-1),
    ]);
    // Claude Code's own that a chat agent here cannot use stays out of its context.
    const settings = JSON.parse(started.argv.at(-1));
    assert.equal(settings.disableClaudeAiConnectors, true);
    assert.equal(settings.skillOverrides.loop, "off");
    assert.equal(settings.skillOverrides["anthropic-skills:computer-use"], "off");
    assert.equal(settings.skillOverrides["anthropic-skills:docx"], "name-only");
    // A repository's rules told as its tools first touch it (test/repo-rules-hook.test.ts).
    const [rules] = settings.hooks.PostToolUse;
    assert.match(rules.matcher, /^Bash\|Read\|/);
    assert.ok(rules.hooks[0].command.includes(REPO_RULES_HOOK), rules.hooks[0].command);
    // A subagent kept from the tools a session speaks by (test/subagent-hook.test.ts): those tools, slack_api for its
    // writes, and no other, as Claude Code names them.
    assert.deepEqual(Object.keys(settings.hooks).sort(), ["PostToolUse", "PreToolUse", "SessionStart"]);
    assert.deepEqual(settings.hooks.PreToolUse, SILENT_SUBAGENTS.PreToolUse);
    const [silent] = settings.hooks.PreToolUse;
    assert.equal(settings.hooks.PreToolUse.length, 1);
    assert.equal(silent.matcher, [...SPEAKS, "slack_api"].map((tool) => `mcp__stillfail__${tool}`).join("|"));
    assert.equal(silent.matcher, "mcp__stillfail__chat_post|mcp__stillfail__chat_state|mcp__stillfail__session_send|mcp__stillfail__chat_create|mcp__stillfail__chat_leave|mcp__stillfail__chat_archive|mcp__stillfail__slack_api");
    // One command, the hook's file by the station's Node, told the Slack methods that write as one quoted word, and
    // given up on (the call let through) after seconds, not Claude Code's ten minutes.
    assert.deepEqual(silent.hooks, [{ type: "command", command: hookCommand(SUBAGENT_HOOK, SLACK_SPOKEN.join(",")), timeout: 10 }]);
    assert.equal(silent.hooks[0].command, `'${process.execPath}' '${SUBAGENT_HOOK}' '${SLACK_SPOKEN.join(",")}' 2>/dev/null || true`);
    assert.match(silent.hooks[0].command, /' 'chat\.postMessage,chat\.postEphemeral,[A-Za-z.,]+,assistant\.threads\.,chat\.startStream,chat\.appendStream,chat\.stopStream' 2>/);
    // No settings file of the machine, the project or the working directory turns the hook off (a subagent wrote one).
    assert.equal(settings.disableAllHooks, false);
    const [compacted] = settings.hooks.SessionStart;
    assert.equal(compacted.matcher, "compact");
    assert.ok(compacted.hooks[0].command.includes(REPO_RULES_HOOK), compacted.hooks[0].command);
    const env = started.env;
    assert.equal(env.CLAUDE_CONFIG_DIR, o.profile.home);
    assert.equal(env.STILLFAIL_MCP_TOKEN, "tok");
    assert.equal(env.STILLFAIL_RUNTIME_SESSION_ID, session.id());
    assert.equal(env.CLAUDE_CODE_CERT_STORE, "bundled");
    assert.equal(env.CLAUDE_CODE_SILENT_TURN_REMINDER, "0");
    assert.equal(env.CLAUDECODE, undefined);
    assert.equal(env.CLAUDE_CODE_OAUTH_TOKEN, undefined, "not a profile's own");
    // OpenCode Go's access, its route the session's.
    assert.equal(env.ANTHROPIC_BASE_URL, "https://opencode.ai/zen/go");
    assert.equal(env.ANTHROPIC_API_KEY, "k1");
    assert.equal(env.ANTHROPIC_CUSTOM_HEADERS, `x-opencode-session: ${o.route}`);
    assert.equal(env.ANTHROPIC_SMALL_FAST_MODEL, "claude-haiku-5-5");
    if (process.platform === "darwin") assert.match(env.PATH.split(":")[0], /stillfail-no-keychain-\d+$/, "a security that holds nothing of Claude Code's");

    // The user's message, as stream-json input.
    assert.deepEqual(stdin(o.dump)[0], { type: "user", message: { role: "user", content: [{ type: "text", text: "say:hello" }] } });
    await assert.rejects(session.prompt("x").then(() => session.prompt("y")), /a turn is already running/);
    await until(ended(2));
    await session.dispose();
    await until((e) => e.some((x) => x.type === "closed"));
  });

  test("a session continued from a terminal keeps its subagents from speaking too, and is given nothing else of the station's settings", async () => {
    const d = driver();
    const o = options({ instructions: "" });
    const { push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("say:hi");
    await until(ended(1));
    const started = JSON.parse(readFileSync(o.dump, "utf8").trim());
    assert.ok(!started.argv.includes("--append-system-prompt") && !started.argv.includes("--disallowedTools"));
    const settings = JSON.parse(started.argv[started.argv.indexOf("--settings") + 1]);
    assert.deepEqual(Object.keys(settings), ["disableAllHooks", "hooks"]);
    assert.equal(settings.disableAllHooks, false);
    assert.deepEqual(settings.hooks, SILENT_SUBAGENTS);
    await session.dispose();
  });

  test("the hooks' files are the ones named, the build ships them, and they are run by a Node that outlives an update", () => {
    // The files by name: a constant pointed at another file would pass every test that only compares it with itself.
    assert.equal(basename(SUBAGENT_HOOK), "subagent-hook.mjs");
    assert.equal(basename(REPO_RULES_HOOK), "repo-rules-hook.mjs");
    for (const file of [SUBAGENT_HOOK, REPO_RULES_HOOK]) assert.ok(existsSync(file), file);
    // A release has them beside its bundle: the build copies each there, or a session's command names a file that is not.
    const build: string = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8")).scripts.build;
    const copied = build.split("&&").map((step) => step.trim().split(/\s+/)).find((words) => words[0] === "cp" && words.at(-1) === "dist/" && words[1] !== "-R") ?? [];
    for (const file of ["src/agents/subagent-hook.mjs", "src/agents/repo-rules-hook.mjs"]) assert.ok(copied.includes(file), `${file} is not copied to dist/ by the build: ${copied.join(" ")}`);
    // In a release (<app>/station/<hook>, <app>/node the release's Node) the command names that Node, which the next
    // release's takes the place of; the Node the station runs on is a version's own directory, pruned after an update.
    // Where either installer puts it (bin/node; node.exe on Windows), whichever is there.
    for (const own of [join("/app", "node", "bin", "node"), join("/app", "node", "node.exe")]) {
      assert.equal(hookNode(join("/app", "station", "subagent-hook.mjs"), (path) => path === own), own);
    }
    // A checkout, these tests: no Node beside it, its own.
    assert.equal(hookNode(join("/app", "station", "subagent-hook.mjs"), () => false), process.execPath);
    assert.equal(hookNode(SUBAGENT_HOOK), process.execPath);
    assert.equal(REPO_RULES_COMMAND, `'${process.execPath}' '${REPO_RULES_HOOK}' 2>/dev/null || true`);
    // Every word quoted for the shell that runs it, a quote in one too.
    assert.equal(hookCommand("/a b/it's.mjs", "x y", "$(z)"), `'${process.execPath}' '/a b/it'\\''s.mjs' 'x y' '$(z)' 2>/dev/null || true`);
  });

  test("sets of hooks are joined event by event, none replacing another's", () => {
    const a = { PreToolUse: [{ matcher: "A" }], PostToolUse: [{ matcher: "B" }] };
    assert.deepEqual(hooksOf(a, SILENT_SUBAGENTS), { PreToolUse: [{ matcher: "A" }, ...SILENT_SUBAGENTS.PreToolUse], PostToolUse: [{ matcher: "B" }] });
    assert.deepEqual(hooksOf({}, SILENT_SUBAGENTS), SILENT_SUBAGENTS);
    assert.deepEqual(a, { PreToolUse: [{ matcher: "A" }], PostToolUse: [{ matcher: "B" }] }, "what it is given is left as it was");
  });

  test("a session kept to less context starts Claude Code compacting at it", async () => {
    const d = driver();
    const o = options({ context: 300_000 });
    const { push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("say:hi");
    await until(ended(1));
    const started = JSON.parse(readFileSync(o.dump, "utf8").trim());
    const settings = JSON.parse(started.argv[started.argv.indexOf("--settings") + 1]);
    assert.equal(settings.autoCompactWindow, 300_000);
    assert.equal(settings.disableClaudeAiConnectors, true, "with the station's own settings");
    await session.dispose();
  });

  test("Fast on an Anthropic key, a Claude subscription or an OpenRouter key is Claude Code's fastMode, as the session is set else as its profile is, and needs a new process", async () => {
    const d = driver();
    const fastMode = async (o: OpenOptions & { dump: string }) => {
      const { push, until } = listen();
      const session = await d.open(o, push);
      await session.prompt("say:hi");
      await until(ended(1));
      const started = JSON.parse(readFileSync(o.dump, "utf8").trim());
      const at = started.argv.indexOf("--settings");
      return [session, at < 0 ? undefined : JSON.parse(started.argv[at + 1]).fastMode] as const;
    };
    const keyed = (extra: Partial<OpenOptions> = {}, fast?: boolean) => {
      const base = options(extra);
      return { ...base, profile: { ...base.profile, access: { kind: "anthropic-api", key: "sk-ant-1" }, ...(fast === undefined ? {} : { fast }) } };
    };
    const [onProfile, profileFast] = await fastMode(keyed({}, true));
    assert.equal(profileFast, true, "its profile's default");
    const [standard, sessionOff] = await fastMode(keyed({ fast: false }, true));
    assert.equal(sessionOff, false, "the session's own over its profile's, said so a /fast in its home does not stay on");
    const [, off] = await fastMode(keyed());
    assert.equal(off, false);
    // A Claude subscription's goes to Claude Code too: it runs Fast while the account's usage credits are on.
    const sub = options({ fast: true });
    const [onSubscription, subscriptionFast] = await fastMode({ ...sub, profile: { ...sub.profile, access: { kind: "subscription" } } });
    assert.equal(subscriptionFast, true);
    // An OpenRouter key's too (OpenRouter serves speed: "fast" from Anthropic's fast tier); another provider's not.
    const provider = (id: string) => {
      const base = options({ fast: true });
      return { ...base, profile: { ...base.profile, access: { kind: "api-provider" as const, key: "k", provider: id } } };
    };
    const [onOpenRouter, openRouterFast] = await fastMode(provider("openrouter"));
    assert.equal(openRouterFast, true);
    const [onOtherProvider, otherProviderFast] = await fastMode(provider("minimax"));
    assert.equal(otherProviderFast, undefined, "a provider not known to take it");
    const [notKeyed, other] = await fastMode(options({ fast: true }));
    assert.equal(other, undefined, "not an account that takes it");
    // Another Fast is not taken in place; the same is, with another model.
    const o = keyed({ fast: false }, true);
    assert.equal(standard.retune?.({ ...o, model: "m2" }), true);
    assert.equal(standard.retune?.({ ...o, model: "m2", fast: true }), false);
    assert.equal(standard.retune?.({ ...o, model: "m2", fast: undefined }), false, "back to its profile's, which is on");
    assert.equal(notKeyed.retune?.({ ...options({ fast: false }), model: "m2" }), true);
    await Promise.all([onProfile, standard, onSubscription, onOpenRouter, onOtherProvider, notKeyed].map((s) => s.dispose()));
  });

  test("a Kimi Code sign-in's key is read from its home by Claude Code's key helper, not given it", async () => {
    const d = driver();
    const base = options();
    const o = { ...base, profile: { ...base.profile, home: join(data, "kimi's home"), access: { kind: "api-provider", provider: "kimi-code", login: true } } };
    mkdirSync(o.profile.home, { recursive: true });
    writeFileSync(join(o.profile.home, ".credentials.json"), "{}");
    const { push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("say:hi");
    await until(ended(1));
    const started = JSON.parse(readFileSync(o.dump, "utf8").trim());
    const at = started.argv.indexOf("--settings");
    assert.equal(JSON.parse(started.argv[at + 1]).apiKeyHelper, `cat '${join(data, "kimi'\\''s home", "kimi-code.token")}'`);
    assert.equal(started.env.ANTHROPIC_BASE_URL, "https://api.kimi.com/coding");
    assert.deepEqual([started.env.ANTHROPIC_AUTH_TOKEN, started.env.ANTHROPIC_API_KEY, started.env.CLAUDE_CODE_API_KEY_HELPER_TTL_MS], [undefined, undefined, "60000"]);
    await session.dispose();
  });

  test("a failed result is told apart by what claude said; is_error decides, not subtype", async () => {
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options(), push);
    for (const [i, prompt] of ["fail:auth", "fail:rate", "fail:model", "say:You've hit your weekly limit"].entries()) {
      await session.prompt(prompt);
      await until(ended(i + 1));
    }
    assert.deepEqual(outcome(events, 0), { kind: "failed", reason: "auth", message: "API Error: 401 invalid x-api-key" });
    assert.deepEqual(outcome(events, 1), { kind: "failed", reason: "rate_limit", message: "You've hit your weekly limit · resets Oct 8" });
    assert.deepEqual(outcome(events, 2), { kind: "failed", reason: "context", message: "prompt is too long" });
    assert.deepEqual(outcome(events, 3), { kind: "completed" }, "a successful text saying a limit is no failure");
    assert.equal(classifyResult("Claude AI usage limit reached"), "rate_limit");
    assert.equal(classifyResult("You've reached your Fable limit. Switch to another model, or manage usage credits at https://claude.ai/settings/usage?from=cc_cli_limit_message, to continue."), "rate_limit");
    // A model's own limit names the model; an account's window is no model (#4365).
    assert.equal(modelLimitOf("You've reached your Fable limit. Switch to another model, or manage usage credits at https://claude.ai/settings/usage, to continue."), "Fable");
    assert.equal(modelLimitOf("Claude usage limit reached: you have reached your weekly usage limit"), null);
    assert.equal(modelLimitOf("You've hit your session limit · resets 3:40am"), null);
    assert.equal(classifyResult("session limit configuration is invalid"), "model");
    assert.equal(classifyResult('API Error: 403 {"error":{"type":"forbidden","message":"Request not allowed"}}'), "refused");
    assert.equal(classifyResult("API Error: 403 OAuth token does not meet scope requirement"), "auth");
    assert.equal(classifyResult('API Error: 529 {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'), "overloaded");
    await session.dispose();
  });

  test("an hourly allowance failure is a rate limit; the same words in a reply are not", () => {
    for (const text of ["You've hit your 5-hour limit · resets 7:50am (UTC)", "You've hit your 5 hour limit", "You've hit your 3-hour limit"]) {
      for (const is_error of [true, false]) {
        const { events, push } = listen();
        const turn: Turn = { busy: true, aborting: false, authFailure: null, closed: false };
        onFrame({ type: "result", subtype: "success", is_error, result: text }, turn, push, () => {});
        assert.deepEqual(outcome(events), is_error ? { kind: "failed", reason: "rate_limit", message: text } : { kind: "completed" });
      }
    }
    assert.equal(classifyResult("5-hour limit configuration is invalid"), "model");
  });

  test("a session that ran in another directory is resumed from where claude looks, its cwd's project; none at all is refused", async () => {
    // Claude Code 2.1.63 resumes only from the project of the directory it runs in (FB-16: a chat whose turns all ended
    // at once with error_during_execution, "No conversation found with session ID").
    const d = driver();
    const o = options({ cwd: mkdtempSync(join(data, "cwd-")) });
    const id = "0c0c0c0c-0000-4000-8000-000000000001";
    const before = join(o.profile.home, "projects", "-somewhere-else");
    mkdirSync(before, { recursive: true });
    writeFileSync(join(before, `${id}.jsonl`), '{"type":"user"}\n');
    const session = await d.open({ ...o, resume: id }, listen().push);
    const here = join(o.profile.home, "projects", claudeProject(realpathSync(o.cwd))!, `${id}.jsonl`);
    assert.equal(readFileSync(here, "utf8"), '{"type":"user"}\n');
    appendFileSync(here, '{"type":"assistant"}\n');
    assert.equal(readFileSync(join(before, `${id}.jsonl`), "utf8"), '{"type":"user"}\n{"type":"assistant"}\n', "one file, under both names");
    await session.dispose();
    await assert.rejects(d.open({ ...options(), resume: "0c0c0c0c-0000-4000-8000-000000000002" }, listen().push), /no claude transcript/);
  });

  test("a turn that failed with no result says claude's errors, not just error_during_execution", () => {
    // As claude 2.1.321 ends a turn it could not run (here --resume of a session it has not).
    const said = "No conversation found with session ID: 11111111-1111-1111-1111-111111111111";
    const { events, push } = listen();
    const turn: Turn = { busy: true, aborting: false, authFailure: null, closed: false };
    onFrame({ type: "result", subtype: "error_during_execution", is_error: true, num_turns: 0, errors: [said] }, turn, push, () => {});
    assert.deepEqual(outcome(events), { kind: "failed", reason: classifyResult(said), message: said });
    const none = listen();
    onFrame({ type: "result", subtype: "error_during_execution", is_error: true, errors: [] }, { busy: true, aborting: false, authFailure: null, closed: false }, none.push, () => {});
    assert.equal((outcome(none.events) as { message: string }).message, "error_during_execution");
  });

  test("the first api_retry 401 interrupts the turn, which fails as auth", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("retry401");
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "failed", reason: "auth", message: "401 invalid token" });
    const interrupts = stdin(o.dump).filter((m) => m.type === "control_request" && m.request.subtype === "interrupt");
    assert.equal(interrupts.length, 1, "interrupted once");
    assert.match(interrupts[0].request_id, /^interrupt-/);
    await session.dispose();
  });

  test("an api_retry 403 Request not allowed fails as refused, not auth: signing in again would not help", async () => {
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options(), push);
    await session.prompt("retry403");
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "failed", reason: "refused", message: "403 Request not allowed" });
    await session.dispose();
  });

  test("abort interrupts the turn; its end still comes, as aborted", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.abort(); // nothing running: nothing sent
    await session.prompt("hold:2");
    await until((e) => deltas(e).length >= 2);
    await session.abort();
    await session.abort(); // once
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "aborted" });
    assert.equal(stdin(o.dump).filter((m) => m.type === "control_request").length, 1);
    assert.deepEqual(deltas(events), ["d0 ", "d1 "]);
    await session.dispose();
  });

  test("steer adds input to the running turn; with nothing running it is refused", async () => {
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options(), push);
    assert.equal(await session.steer("early"), false);
    await session.prompt("hold:1");
    await until((e) => deltas(e).length >= 1);
    assert.equal(await session.steer("more"), true);
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    assert.ok(deltas(events).includes("steer:more"));
    assert.equal(events.filter((e) => e.type === "turnStarted").length, 0);
    await session.dispose();
  });

  test("a turn that starts without a prompt of ours is told as turnStarted", async () => {
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options(), push);
    await session.prompt("again");
    await until(ended(2));
    const kinds = events.filter((e) => e.type !== "live").map((e) => e.type);
    assert.deepEqual(kinds, ["turnEnded", "turnStarted", "turnEnded"]);
    assert.equal(session.busy(), false);
    await session.dispose();
  });

  test("the process exiting during a turn fails it as exited, with its last stderr, then closes the session", async () => {
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options(), push);
    await session.prompt("exit");
    await until((e) => e.some((x) => x.type === "closed"));
    const told = events.filter((e) => e.type !== "live");
    assert.deepEqual(told, [
      { type: "turnEnded", outcome: { kind: "failed", reason: "exited", message: "claude exited (3) during the turn: noise\nerror: An unknown error occurred (Unexpected)" } },
      { type: "closed", why: "claude exited (3): noise\nerror: An unknown error occurred (Unexpected)" },
    ]);
    await assert.rejects(session.prompt("again"), /closed/);
    // Read to the end, its runner is gone.
    await eventually(() => !existingRunners(data).some((r) => r.args.includes(session.id())));
  });

  test("background_tools sends background_tasks; the call it waited on returns and the turn goes on", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.backgroundTools(); // nothing running: nothing sent
    await session.prompt("tool");
    // The call starts again with its input once that is complete.
    await until((e) => e.some((x) => x.type === "live" && x.event.kind === "start" && x.event.input === '{"command":"sleep 60"}'));
    await session.backgroundTools();
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    const requests = stdin(o.dump).filter((m) => m.type === "control_request");
    assert.equal(requests.length, 1);
    assert.equal(requests[0].request.subtype, "background_tasks");
    assert.match(requests[0].request_id, /^background-/);
    const live = events.flatMap((e) => (e.type === "live" ? [e.event] : []));
    assert.ok(live.some((e) => e.kind === "delta" && e.id === "call_1" && e.field === "output" && e.text === "moved to background"));
    assert.ok(live.some((e) => e.kind === "end" && e.id === "call_1"));
    await session.dispose();
  });

  test("a machine profile runs on the machine's token, and a token about to run out does not stop it", async () => {
    let expiresAt = Date.now() + 3600_000;
    const d = driver(async () => ({ token: "machine-token", expiresAt }));
    const o = options({ machine: true });
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("say:hi");
    await until(ended(1));
    const env = JSON.parse(readFileSync(o.dump, "utf8").trim()).env;
    assert.equal(env.CLAUDE_CODE_OAUTH_TOKEN, "machine-token");
    if (process.platform === "darwin") assert.doesNotMatch(env.PATH.split(":")[0], /stillfail-no-keychain/);
    await session.dispose();
    expiresAt = Date.now() + 60_000;
    const soon = listen();
    const s2 = await d.open(options({ machine: true }), soon.push);
    await s2.prompt("say:hi");
    await soon.until(ended(1));
    await s2.dispose();
  });

  test("a token handed over is renewed in the process: claude asks on a 401 and the turn goes on, never started again", async () => {
    const given: (string | undefined)[] = [];
    let next = 1;
    const d = driver(async (_env?: unknown, rejected?: string) => {
      given.push(rejected);
      return { token: `machine-${next}`, expiresAt: Date.now() + 60_000 };
    });
    const o = options({ machine: true });
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    // A token about to run out no longer stops a turn: it is renewed when refused.
    next = 2;
    await session.prompt("expired");
    await until(ended(1));
    const env = JSON.parse(readFileSync(o.dump, "utf8").trim()).env;
    assert.equal(env.CLAUDE_CODE_OAUTH_TOKEN, "machine-1");
    assert.equal(env.CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH, "1");
    assert.equal(env.CLAUDE_CODE_ENTRYPOINT, "claude-desktop");
    assert.deepEqual(outcome(events), { kind: "completed" });
    assert.deepEqual(given, [undefined, "machine-1"], "renewed with the refused one named");
    const answers = stdin(o.dump).filter((m) => m.type === "control_response");
    assert.equal(answers.length, 1);
    assert.equal(answers[0].response.response.accessToken, "machine-2");
    assert.equal(stdin(o.dump).filter((m) => m.type === "control_request").length, 0, "not interrupted");
    // No newer token: it is told so, and the turn fails on authentication as before.
    await session.prompt("expired");
    await until(ended(2));
    assert.equal((outcome(events, 1) as { reason?: string }).reason, "auth");
    assert.equal(stdin(o.dump).filter((m) => m.type === "control_response").at(-1).response.response.reason, "refresh_failed");
    await session.dispose();
  });

  test("a local subscription runs on a token renewed by the station, and falls back to its kept token without touching .credentials.json when renewal fails", async () => {
    const subOptions = () => {
      const base = options();
      const creds = JSON.stringify({ claudeAiOauth: { accessToken: "kept-tok", refreshToken: "rt" } });
      writeFileSync(join(base.profile.home, ".credentials.json"), creds);
      return { ...base, creds, profile: { ...base.profile, id: "sub", access: { kind: "subscription" as const } } };
    };

    // 1. Central renewal at open() and in-place renewal on 401 via oauth_token_refresh.
    const asked: [string, string | undefined][] = [];
    let next = 1;
    const d1 = driver(undefined, async (p, rejected) => {
      asked.push([p.id, rejected]);
      return { token: `sub-${next}`, expiresAt: Date.now() + 3600_000 };
    });
    const o1 = subOptions();
    const l1 = listen();
    const s1 = await d1.open(o1, l1.push);
    next = 2;
    await s1.prompt("expired");
    await l1.until(ended(1));
    const env1 = JSON.parse(readFileSync(o1.dump, "utf8").trim()).env;
    assert.equal(env1.CLAUDE_CODE_OAUTH_TOKEN, "sub-1");
    assert.equal(env1.CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH, "1");
    assert.equal(env1.CLAUDE_CODE_ENTRYPOINT, "claude-desktop");
    if (process.platform === "darwin") assert.match(env1.PATH.split(":")[0], /stillfail-no-keychain-\d+$/);
    assert.deepEqual(outcome(l1.events), { kind: "completed" });
    assert.deepEqual(deltas(l1.events), ["token:sub-2"]);
    assert.deepEqual(asked, [["sub", undefined], ["sub", "sub-1"]]);
    assert.equal(readFileSync(join(o1.profile.home, ".credentials.json"), "utf8"), o1.creds);
    await s1.dispose();

    // 2. Transient failure in open() hands over the kept token with RENEWED so oauth_token_refresh retries in-place.
    let transient = true;
    const d2 = driver(undefined, async (_p, rejected) => {
      if (transient) {
        transient = false;
        throw new Said("network down");
      }
      assert.equal(rejected, "kept-tok");
      return { token: "sub-3", expiresAt: Date.now() + 3600_000 };
    });
    const o2 = subOptions();
    const l2 = listen();
    const s2 = await d2.open(o2, l2.push);
    await s2.prompt("expired");
    await l2.until(ended(1));
    const env2 = JSON.parse(readFileSync(o2.dump, "utf8").trim()).env;
    assert.equal(env2.CLAUDE_CODE_OAUTH_TOKEN, "kept-tok");
    assert.equal(env2.CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH, "1");
    assert.deepEqual(outcome(l2.events), { kind: "completed" });
    assert.deepEqual(deltas(l2.events), ["token:sub-3"]);
    await s2.dispose();

    // 3. Permanent refusal (RenewRefused) in open() hands over the kept token without RENEWED so a 401 fails on auth
    //    (triggering recheck/failover) instead of throwing in open() or letting Claude Code delete .credentials.json.
    const d3 = driver(undefined, async () => {
      throw new RenewRefused(400, "revoked");
    });
    const o3 = subOptions();
    const l3 = listen();
    const s3 = await d3.open(o3, l3.push);
    await s3.prompt("expired");
    await l3.until(ended(1));
    const env3 = JSON.parse(readFileSync(o3.dump, "utf8").trim()).env;
    assert.equal(env3.CLAUDE_CODE_OAUTH_TOKEN, "kept-tok");
    assert.equal(env3.CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH, undefined);
    assert.equal((outcome(l3.events) as { reason?: string }).reason, "auth");
    assert.equal(readFileSync(join(o3.profile.home, ".credentials.json"), "utf8"), o3.creds);
    await s3.dispose();
  });

  for (const crashed of [false, true]) {
    test(`a next driver takes the session up ${crashed ? "after a crash (no snapshot)" : "from its snapshot"}: the turn ends once, no live event twice`, async () => {
      const first = driver();
      const o = options();
      const a = listen();
      const session = await first.open(o, a.push);
      const gate = gates(o.dump, "g");
      await session.prompt("gate:12:4:g");
      await a.until((e) => deltas(e).length >= 4);
      let snapshot: unknown = null;
      if (!crashed) snapshot = JSON.parse(JSON.stringify(session.snapshot()));
      // Stops: the process goes on under its runner, saying the rest of its reply with nobody reading.
      first.detach();
      // (the station let go before the next takes up, as the hub waits: every line handled acknowledged)
      await allLeft();
      await gate.open("a");
      await eventually(gate.said);
      const next = driver();
      const b = listen();
      const taken: AgentSession = await next.adopt(o, snapshot, b.push);
      assert.equal(taken.id(), session.id());
      assert.equal(taken.busy(), true);
      await gate.open("b");
      await b.until(ended(1));
      const all = [...a.events, ...b.events];
      assert.equal(ends(all).length, 1, "the turn's end, once");
      assert.deepEqual(outcome(b.events), { kind: "completed" });
      assert.deepEqual(deltas(all), Array.from({ length: 12 }, (_, i) => `d${i} `), "every delta once, in order");
      assert.equal(all.filter((e) => e.type === "live" && e.event.kind === "start").length, 1);
      assert.equal(all.filter((e) => e.type === "live" && e.event.kind === "end").length, 1, "the step started before ends after");
      // After a crash the new station is told a turn is running that it did not start.
      assert.equal(b.events.filter((e) => e.type === "turnStarted").length, crashed ? 1 : 0);
      // It goes on as before.
      await taken.prompt("say:after");
      await b.until(ended(2));
      assert.deepEqual(outcome(b.events, 1), { kind: "completed" });
      await taken.dispose();
      await b.until((e) => e.some((x) => x.type === "closed"));
      assert.ok(!a.events.some((e) => e.type === "closed"), "the first driver hears nothing after letting go");
    });
  }
});
