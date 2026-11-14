// What the agents' tools weigh as they are declared (src/tools/mcp.ts `weight`): several runtimes put the whole list in
// every session's context, so it is held under ceilings here (station/AGENTS.md, Agents). A declaration is what its
// factory gives, whatever it is given, so the list is made of every factory src/sessions/agents.ts and the parts'
// modules call, with nothing behind them: no tool is run.
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { test } from "node:test";
import { PHONE_SEND, adbTools, phoneTools } from "../src/adb/tool.ts";
import { browserTools } from "../src/browser/tool.ts";
import { deviceTools } from "../src/devices/tool.ts";
import { feishuTools } from "../src/feishu/tool.ts";
import { loginTools } from "../src/logins/tool.ts";
import { rigTools } from "../src/rigs/tool.ts";
import { searchTools } from "../src/search/tool.ts";
import { archiveTools } from "../src/tools/archive.ts";
import { chatTools } from "../src/tools/chat.ts";
import { computerTools } from "../src/tools/computer.ts";
import { feedbackTools } from "../src/tools/feedback.ts";
import { forwardTools } from "../src/tools/forward.ts";
import { jobTools } from "../src/tools/jobs.ts";
import { CORE, type Tool, weight } from "../src/tools/mcp.ts";
import { permissionTools } from "../src/tools/permissions.ts";
import { relayTools } from "../src/tools/relays.ts";
import { remoteTools } from "../src/tools/remote.ts";
import { screenTools } from "../src/tools/screen.ts";
import { workspaceSizeTools } from "../src/tools/workspace-size.ts";
import { vaultTools } from "../src/vault/tool.ts";

/// The factories the list below is made of, by the names their callers call them by.
const FACTORIES = [
  "chatTools", "archiveTools", "remoteTools", "workspaceSizeTools", "jobTools", "screenTools", "permissionTools", "computerTools", "forwardTools", "relayTools",
  "phoneTools", "adbTools", "browserTools", "deviceTools", "feedbackTools", "feishuTools", "loginTools", "rigTools", "searchTools", "vaultTools",
];
/// How many times the parts' modules give tools (`parts.tools(`): one a factory above but adb's, which also gives
/// phone_send by itself.
const PARTS_GIVE = 11;

/// Every tool a station declares to a session, where it declares the most (a stable station of still.fail cloud, which
/// has the feedback tools too): those of src/sessions/agents.ts, then the parts' (their modules' `parts.tools(…)`), each
/// factory given nothing, since a declaration reads none of it.
function stationTools(): Tool[] {
  const none = {} as any;
  return [
    ...chatTools(none),
    ...archiveTools(none),
    ...remoteTools(none),
    ...workspaceSizeTools(none, none),
    ...jobTools(none, () => null),
    ...screenTools(none, () => null),
    ...permissionTools(null, () => null),
    ...computerTools(none),
    ...forwardTools(none),
    ...relayTools(none),
    ...phoneTools(none, async () => ""),
    { ...PHONE_SEND, run: async () => "" },
    ...adbTools(() => []),
    ...browserTools(none),
    ...deviceTools(none),
    ...feedbackTools(none, () => null, () => null),
    ...feishuTools(() => undefined, () => false),
    ...loginTools(none),
    ...rigTools(none),
    ...searchTools(none),
    ...vaultTools(none, () => null, none),
  ];
}

// The ceilings, in bytes: what the list weighed once it was slimmed (2026-11-14: 60,284 in all, from 80,230; the core
// ones 13,894, from 22,140; chat_post the heaviest at 4,665, from 8,125), each rounded up to the next thousand.
// TOOLS_WEIGHT_TABLE=1 prints every tool's.
const TOTAL = 61_000;
const CORE_TOTAL = 14_000;
const HEAVIEST = 5_000;
// One tool's input schema, as compact JSON. Not a rounding: Codex 0.169.0 strips every description from an MCP tool's
// input schema once it is over 5,000 bytes (measured 2026-11-14 with the station's list against a fake model endpoint:
// the cut is between 4,980 and 5,010 bytes). chat_post's was 7,113 then and reached Codex's models as 1,167 bytes with
// none of its 25 parameter descriptions; it is 4,272 now. Never raise this past what Codex keeps.
const SCHEMA = 4_500;

/// What to do about a ceiling passed, said to whoever passed it.
const TOLD = "Shorten it: a description says what the tool does and when to use it, a format nobody could guess, a warning whose absence loses or leaks something; the details go to the tool's skill in src/skills/, which the description names. Raising a ceiling needs its reason said in the change (station/AGENTS.md, Agents).";

const schemaBytes = (t: Tool) => Buffer.byteLength(JSON.stringify(t.inputSchema));
const table = (tools: readonly Tool[]) => [...tools].sort((a, b) => weight(b) - weight(a)).map((t) => `${String(weight(t)).padStart(6)}  ${t.name}`).join("\n");

test("the list here is made of every factory the station gives its sessions' tools by", () => {
  const src = new URL("../src/", import.meta.url);
  const modules = readdirSync(src, { withFileTypes: true }).filter((d) => d.isDirectory()).flatMap((d) => {
    try {
      return [readFileSync(new URL(`${d.name}/module.ts`, src), "utf8")];
    } catch {
      return [];
    }
  });
  const called = new Set([...modules, readFileSync(new URL("sessions/agents.ts", src), "utf8")].flatMap((text) => [...text.matchAll(/\b([A-Za-z]+Tools)\(/g)].map((m) => m[1]!)));
  called.delete("allTools");
  assert.deepEqual([...called].sort(), [...FACTORIES].sort(), "a factory of tools was added or taken away: make stationTools() in this test of the same ones, so that its tools are weighed");
  const gives = modules.reduce((n, text) => n + text.split("parts.tools(").length - 1, 0);
  assert.equal(gives, PARTS_GIVE, "a part gives tools somewhere new (parts.tools): add them to stationTools() in this test, so that they are weighed");
});

test("the tools a station declares stay under their ceilings: the whole list, the core ones, the heaviest, a schema", (t) => {
  const tools = stationTools();
  assert.equal(new Set(tools.map((x) => x.name)).size, tools.length, "no name twice");
  for (const name of CORE) assert.ok(tools.some((x) => x.name === name), `${name} is a core tool and is not in the list`);
  const total = tools.reduce((n, x) => n + weight(x), 0);
  const core = tools.filter((x) => CORE.includes(x.name)).reduce((n, x) => n + weight(x), 0);
  const heaviest = [...tools].sort((a, b) => weight(b) - weight(a))[0]!;
  const widest = [...tools].sort((a, b) => schemaBytes(b) - schemaBytes(a))[0]!;
  t.diagnostic(`${tools.length} tools, ${total} bytes; core ${core}; heaviest ${heaviest.name} ${weight(heaviest)}; largest schema ${widest.name} ${schemaBytes(widest)}`);
  if (process.env.TOOLS_WEIGHT_TABLE) t.diagnostic(`\n${table(tools)}`);
  assert.ok(total <= TOTAL, `the tools declare ${total} bytes, more than ${TOTAL}. ${TOLD}\n${table(tools)}`);
  assert.ok(core <= CORE_TOTAL, `the core tools declare ${core} bytes, more than ${CORE_TOTAL}. ${TOLD}\n${table(tools.filter((x) => CORE.includes(x.name)))}`);
  assert.ok(weight(heaviest) <= HEAVIEST, `${heaviest.name} declares ${weight(heaviest)} bytes, more than ${HEAVIEST} for one tool. ${TOLD}`);
  assert.ok(schemaBytes(widest) <= SCHEMA, `${widest.name}'s input schema is ${schemaBytes(widest)} bytes, more than ${SCHEMA}: over 5,000 Codex gives its model the tool with no parameter descriptions at all. Shorten its parameters' descriptions, keeping there what a model needs to call it right; this ceiling is not raised.`);
});
