// The agents' memory and this machine's own Claude Code and Codex sessions read by the MoonBit reader (station/mb
// src/readops/memory.mbt, machine.mbt; read/pool.ts MOVED) as the worker reads them, on the same files: skills of every
// kind of sharing, frontmatter and file, a joined workspace's and a refused one; transcripts of both runtimes with
// what is not said, names given and kept, lines too long or not UTF-8, ends past the part read of the start, files
// written at the same moment, a thread in two files, and the limits a person may ask.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();
const put = (path: string, text: string | Buffer, at?: number) => {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text);
  if (at !== undefined) utimesSync(path, at, at);
};
const jsonl = (...records: unknown[]) => records.map((r) => (typeof r === "string" ? r : JSON.stringify(r))).join("\n") + "\n";

function memoryFiles(data: string) {
  const agent = join(data, "agents");
  writeFileSync(join(data, "config.json"), JSON.stringify({ agentHome: "agents", sharedSkills: { hosted: { id: "sh-host1", allow: ["st-a"] }, plain: "sh-plain", odd: { id: 7 } } }));
  put(join(data, "mesh", "cloud.json"), JSON.stringify({ station: "st-here" }));
  put(join(data, "share", "state.json"), JSON.stringify({
    hosted: { "sh-host1": { told: { "st-b": 3, "st-c": -1, "12": 0, "st-d": 1 }, missing: { "st-d": "offline", "st-e": 4 }, unread: "u1" } },
    borrowed: { "sh-b0rrow": { host: "st-far", allow: null }, "sh-empty": "" },
  }));
  put(join(agent, "MEMORY.md"), "﻿# memory\n");
  const skill = (name: string, text: string | Buffer, files: Record<string, string | Buffer> = {}) => {
    put(join(agent, "skills", name, "SKILL.md"), text);
    for (const [f, t] of Object.entries(files)) put(join(agent, "skills", name, f), t);
  };
  skill("zeta", "---\ndescription: \"项目记忆：zeta\"\r\nname: zeta\n---\nbody", { "b.md": "B", "a.md": "A", "SKILL.conflict-1.md": "c", "notes.txt": "n", "bad.md": Buffer.from([0xff, 0xfe]) });
  skill("alpha", "---\ndescription:   plain words  \n---\n");
  skill("stillfail-chats", "---\ndescription: built in\n---\n");
  skill("hosted", "---\ndescription: \"\"\"quoted\"\"\n---\n", { "SKILL.conflict-2.md": "x", "SKILL.conflict-.md": "y" });
  skill("plain", "no front matter");
  skill("odd", "---\ndescription: 项目记忆：odd\n");
  skill("Émile", "---\ndescription: accent\n---\n");
  skill("notutf8", Buffer.from([0x2d, 0x2d, 0x2d, 0x0a, 0xc3, 0x28]));
  put(join(agent, "skills", "loose.md"), "not a skill");
  for (const [name, id] of [["borrowed", "sh-b0rrow"], ["emptied", "sh-empty"], ["nowhere", "sh-gone"]]) {
    put(join(data, "share", id, "skill", "SKILL.md"), `---\ndescription: ${name}\n---\n`);
    symlinkSync(join(data, "share", id, "skill"), join(agent, "skills", name));
  }
  put(join(agent, "workspaces", "ws_1", "MEMORY.md"), "joined");
  put(join(agent, "workspaces", "ws_1", "skills", "hosted", "SKILL.md"), "---\ndescription: in a joined one\n---\n");
}

function machineFiles(home: string) {
  const claude = join(home, ".claude", "projects");
  const codex = join(home, "codex-home");
  const t = 1_790_000_000;
  const user = (text: unknown, extra: object = {}) => ({ type: "user", cwd: "/w/one", timestamp: "2026-11-01T10:00:00.250Z", message: { content: text }, ...extra });
  const assistant = (text: string, model = "claude-x") => ({ type: "assistant", timestamp: "2026-11-01T10:00:05Z", message: { model, content: [{ type: "text", text }, { type: "tool_use" }] } });
  put(join(claude, "-w-one", "c-1.jsonl"), jsonl(
    { type: "summary", summary: "  old summary " },
    user("<command-name>/clear</command-name>"),
    user("meta", { isMeta: true }),
    user([{ type: "text", text: "  first\tthing   asked\n\nhere " }, { type: "image" }]),
    assistant("one"), assistant("two"), "not json", user("Caveat: x"),
    { type: "ai-title", aiTitle: "AI named" }, { type: "assistant", message: { model: "<synthetic>", content: "x" } },
  ), t);
  put(join(claude, "-w-one", "c-2.jsonl"), jsonl(user("x".repeat(500)), { type: "custom-title", customTitle: " Mine " }, assistant("ok", "m2")), t);
  put(join(claude, "-w-two", "c-3.jsonl"), jsonl({ type: "user", message: { content: "no cwd anywhere" } }), t + 5);
  const long = "y".repeat(300 * 1024);
  put(join(claude, "-w-two", "c-4.jsonl"), Buffer.concat([
    Buffer.from(jsonl(user(long), user("after a long one"), { type: "user", cwd: "/w/four", message: { content: "s" } })),
    Buffer.from([0xff, 0x0a]), Buffer.from(jsonl(user("after bad bytes"))),
  ]), t - 10);
  const filler = Array.from({ length: 300 }, (_, i) => ({ type: "progress", i, pad: "z".repeat(1000) }));
  put(join(claude, "-w-two", "c-5.jsonl"), jsonl(user("big one"), ...filler, { type: "custom-title", customTitle: "from the tail" }, assistant("end", "tail-model")).replace(/\n/g, "\r\n"), t - 20);
  put(join(claude, "-w-two", "notes.txt"), "x", t + 100);
  put(join(claude, "stray.jsonl"), "{}", t + 100);
  const meta = (id: string, cwd = "/w/codex") => ({ type: "session_meta", payload: { id, cwd } });
  const event = (type: string, message: string) => ({ type: "event_msg", timestamp: "2026-11-02T01:02:03.4Z", payload: { type, message } });
  put(join(codex, "sessions", "2026", "11", "02", "rollout-2026-11-02T01-00-00-x-1.jsonl"), jsonl(
    meta("x-1"),
    { type: "response_item", payload: { type: "message", role: "user", content: [{ text: "<environment_context>cwd</environment_context>" }, { text: "ignored when events" }] } },
    event("user_message", "# AGENTS.md instructions\nstuff"),
    event("user_message", "# Context\n## My request for Codex:\n  do the thing  "),
    event("agent_message", "done"), event("agent_message", "and more"),
    { type: "event_msg", payload: { type: "item_completed", item: { type: "UserMessage", content: [{ text: "<environment_context_x>kept" }, { text: "<user_instructions>" }] } } },
    { type: "turn_context", payload: { model: "gpt-z" } },
  ), t + 1);
  put(join(codex, "sessions", "2026", "11", "01", "rollout-2026-11-01T00-00-00-x-1_part.jsonl"), jsonl(meta("x-1"), event("user_message", "older copy")), t);
  put(join(codex, "sessions", "2026", "11", "01", "rollout-2026-11-01T00-00-00-x-2.jsonl"), jsonl(
    meta("x-2", "/w/two"),
    { type: "response_item", payload: { type: "message", role: "user", content: [{ text: "<permissions>" }, { text: "<wrapped>all</wrapped>" }, { text: "real ask" }, { text: "second part" }] } },
    { type: "response_item", payload: { type: "message", role: "assistant", content: [{ text: "answer" }] } },
  ), t + 1);
  put(join(codex, "sessions", "rollout-nometa-x-3.jsonl"), jsonl(event("user_message", "no meta")), t + 2);
  put(join(codex, "session_index.jsonl"), jsonl({ id: "x-2", thread_name: " named two " }, { id: "x-1", thread_name: "first name" }, { id: "x-1", thread_name: "  " }, { id: "x-1", thread_name: "last name" }));
  return { codex };
}

test("the MoonBit reader reads the agents' memory and the machine's sessions as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-machine-"));
  const home = join(data, "home");
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  memoryFiles(data);
  const { codex } = machineFiles(home);
  for (const [key, runtime, current, at] of [["s-old", "claude", "c-1", 1], ["s-new", "claude", "c-1", 5], ["s-codex", "codex", "x-2", 1]] as const) {
    store.insertSession({ key, connect: "ember", runtime, profile: "own", workspace: "/w", token: key, createdAt: 1, lastActiveAt: at, ws: null } as Parameters<Store["insertSession"]>[0]);
    store.setRuntimeSessionId(key, current);
  }
  const saved = { HOME: process.env.HOME, CODEX_HOME: process.env.CODEX_HOME };
  process.env.HOME = home;
  process.env.CODEX_HOME = codex;
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  const read = (readers: Readers, op: string, args: unknown) => readers.read(op, args, "en").then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (readers: Readers) => {
    const out: unknown[] = [];
    for (const args of [{}, { workspace: "ws_1" }, { workspace: "ws-none" }, { workspace: "../up" }]) out.push(await read(readers, "memory", args));
    out.push(await read(readers, "machineSessions", {}));
    for (const [runtime, id] of [["claude", "c-1"], ["claude", "c-2"], ["claude", "c-4"], ["claude", "c-5"], ["codex", "x-1"], ["codex", "x-2"], ["codex", "x-3"], ["claude", "c-9"], ["claude", "../c-1"], ["claude", ""], ["gemini", "c-1"]])
      for (const lang of ["en", "zh"]) out.push(await read(readers, "machineSession", { lang, runtime, id, limit: undefined }));
    for (const limit of ["0", "1", "+2", "0002", "abc", "", "-1", "18446744073709551615", "18446744073709551616", "99999"])
      out.push(await read(readers, "machineSession", { lang: "en", runtime: "codex", id: "x-1", limit }));
    return out;
  };
  try {
    const first = await all(program);
    assert.deepEqual(first, await all(worker));
    const said = JSON.stringify(first);
    for (const sign of ["st-here", "sh-b0rrow", "\"unread\":\"u1\"", "in a joined one", "not a workspace id", "AI named", "from the tail", "tail-model", "last name", "named two", "do the thing", "real ask\\nsecond part", "No such local session: c-9", "本机没有这个会话：c-9", "no runtime gemini", "s-new"])
      assert.ok(said.includes(sign), sign);
  } finally {
    worker.close(); program.close();
    store.close();
    process.env.HOME = saved.HOME;
    if (saved.CODEX_HOME === undefined) delete process.env.CODEX_HOME;
    else process.env.CODEX_HOME = saved.CODEX_HOME;
    rmSync(data, { recursive: true, force: true });
  }
});
