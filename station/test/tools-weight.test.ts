// What the agents' tools weigh as they are declared (src/tools/mcp.ts `weight`): several runtimes put the whole list in
// every session's context, so it is held under ceilings here (station/AGENTS.md, Agents). A declaration is what its
// factory gives, whatever it is given, so the list is made of every factory src/sessions/agents.ts and the parts'
// modules call, with nothing behind them: no tool is run.
//
// That the list is the station's is held by reading the source (the first test): the factories called where tools are
// given, how many times a part gives tools, in any file of src/, and every tool's name written as tools are declared
// (`name: "…"`, then its description). What it cannot see: a tool given through a factory or a `parts.tools(` already
// there, or spread into the list of src/sessions/agents.ts as a constant, whose name is not such a literal (a name
// computed, its description said before its name); and what the endpoint makes of the list itself (station_tool).
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { test } from "node:test";
import { CORE, type Tool, weight } from "../src/tools/mcp.ts";
import { stationTools } from "./station-tools.ts";

/// The factories the list (test/station-tools.ts `stationTools`) is made of, by the names their callers call them by.
const FACTORIES = [
  "chatTools", "archiveTools", "remoteTools", "workspaceSizeTools", "jobTools", "screenTools", "permissionTools", "computerTools", "forwardTools", "relayTools",
  "phoneTools", "adbTools", "browserTools", "deviceTools", "feedbackTools", "feishuTools", "loginTools", "retireTools", "rigTools", "searchTools", "vaultTools",
];
/// How many times the parts give tools (`parts.tools(`, anywhere in src/): one a factory above but adb's, which also
/// gives phone_send by itself.
const PARTS_GIVE = 12;

// The ceilings, in bytes: what the list weighed once it was slimmed (2026-11-14: 60,925 in all, from 80,230; the core
// ones 13,951, from 22,140; chat_post the heaviest at 4,705, from 8,125), each rounded up to the next thousand. The
// whole list's is 63,000 and not 61,000 for station_retire (1,827), which came the same day (#6084): 62,752 with it.
// TOOLS_WEIGHT_TABLE=1 prints every tool's.
const TOTAL = 63_000;
const CORE_TOTAL = 14_000;
const HEAVIEST = 5_000;
// One tool's input schema, as compact JSON. Not a rounding: Codex 0.169.0 strips every description from an MCP tool's
// input schema once it is over 5,000 bytes (measured 2026-11-14 with the station's list against a fake model endpoint:
// the cut is between 4,980 and 5,010 bytes). chat_post's was 7,113 then and reached Codex's models as 1,167 bytes with
// none of its 25 parameter descriptions; it is 4,312 now. Never raise this past what Codex keeps.
const SCHEMA = 4_500;

/// What to do about a ceiling passed, said to whoever passed it.
const TOLD = "Shorten it: a description says what the tool does and when to use it, a format nobody could guess, a warning whose absence loses or leaks something; the details go to the tool's skill in src/skills/, which the description names. Raising a ceiling needs its reason said in the change (station/AGENTS.md, Agents).";

const schemaBytes = (t: Tool) => Buffer.byteLength(JSON.stringify(t.inputSchema));
const table = (tools: readonly Tool[]) => [...tools].sort((a, b) => weight(b) - weight(a)).map((t) => `${String(weight(t)).padStart(6)}  ${t.name}`).join("\n");

test("the list here is the station's: every factory its tools are given by, and every tool the source declares", () => {
  const src = new URL("../src/", import.meta.url);
  const files = (readdirSync(src, { recursive: true }) as string[]).filter((f) => f.endsWith(".ts")).map((f) => f.replaceAll("\\", "/"));
  const texts = new Map(files.map((f) => [f, readFileSync(new URL(f, src), "utf8")]));
  const givesIn = (text: string) => text.split("parts.tools(").length - 1;
  // The factories called where tools are given: the agents' own list, and any file a part gives tools in.
  const called = new Set([...texts].filter(([f, text]) => f === "sessions/agents.ts" || givesIn(text) > 0).flatMap(([, text]) => [...text.matchAll(/\b([A-Za-z]+Tools)\(/g)].map((m) => m[1]!)));
  called.delete("allTools");
  assert.deepEqual([...called].sort(), [...FACTORIES].sort(), "a factory of tools was added or taken away: make stationTools() in test/station-tools.ts of the same ones, so that its tools are weighed");
  const gives = [...texts.values()].reduce((n, text) => n + givesIn(text), 0);
  assert.equal(gives, PARTS_GIVE, "a part gives tools somewhere new (parts.tools): add them to stationTools() in test/station-tools.ts, so that they are weighed");
  // Every tool the source declares is weighed, and nothing else: one added inside a list already given is seen here.
  const declared = new Set([...texts.values()].flatMap((text) => [...text.matchAll(/\bname: "([a-z][a-z_]*)",\s*description\b/g)].map((m) => m[1]!)));
  assert.deepEqual([...declared].sort(), stationTools().map((t) => t.name).sort(), "the tools src/ declares (name, then description) are not those this test weighs: add the new one to stationTools() in test/station-tools.ts, or take out the one that went");
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
