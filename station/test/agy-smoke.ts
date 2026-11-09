// The real Antigravity CLI on a Google account: signed in first with the station's own sign-in (LoginManager, in a
// terminal: the page printed here, the code it shows read from AGY_SMOKE_CODE_FILE once that is written), into a
// profile home of its own; then a session on that sign-in (`agy acp --gemini-dir`) against a local MCP server standing
// in for the station's tools: a turn that calls chat_post, and a second turn in the same conversation taken up again.
// It signs a real account in and makes real model calls: run it by hand, never in CI.
//   AGY_SMOKE_CODE_FILE=/tmp/code node scripts/native.ts run runner -- node station/test/agy-smoke.ts
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { AgyDriver, agyToken } from "../src/agents/agy.ts";
import { LoginManager } from "../src/accounts/login.ts";
import { checkProfile } from "../src/accounts/profiles.ts";
import { isPosting, transcriptPath } from "../src/read/transcript.ts";
import type { OpenOptions, RuntimeEvent, TurnOutcome } from "../src/agents/runtime.ts";

const codeFile = process.env.AGY_SMOKE_CODE_FILE;
if (!codeFile) throw new Error("AGY_SMOKE_CODE_FILE must name where the code Google's page shows will be written");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const data = mkdtempSync(process.platform === "win32" ? join(tmpdir(), "agy-real-") : "/tmp/agy-real-");
const home = join(data, "profile");
const posts: string[] = [];
const server = createServer(async (req, res) => {
  let raw = "";
  for await (const chunk of req) raw += chunk;
  if (req.url !== "/mcp" || req.headers.authorization !== "Bearer smoke-token") { res.statusCode = 401; res.end(); return; }
  if (req.method !== "POST") { res.statusCode = 405; res.end(); return; }
  const body = raw ? JSON.parse(raw) : {};
  if (body.id === undefined) { res.statusCode = 202; res.end(); return; }
  let result: any = {};
  if (body.method === "initialize") result = { protocolVersion: "2025-03-26", capabilities: { tools: {} }, serverInfo: { name: "stillfail-smoke", version: "1" } };
  if (body.method === "tools/list") result = { tools: [{ name: "chat_post", description: "Post a reply to the person's chat.", inputSchema: { type: "object", properties: { text: { type: "string" } }, required: ["text"] } }] };
  if (body.method === "tools/call") {
    posts.push(String(body.params?.arguments?.text ?? ""));
    result = { content: [{ type: "text", text: "Posted" }] };
  }
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify({ jsonrpc: "2.0", id: body.id, result }));
});
await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = (server.address() as any).port;
const logins = new LoginManager(data);
const driver = new AgyDriver({ data });
function turn() {
  let complete!: (outcome: TurnOutcome) => void;
  const done = new Promise<TurnOutcome>((resolve) => { complete = resolve; });
  return { done, event: (e: RuntimeEvent) => { if (e.type === "turnEnded") complete(e.outcome); } };
}
async function completed(done: Promise<TurnOutcome>) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    assert.deepEqual(await Promise.race([done, new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error("turn timeout")), 300_000); })]), { kind: "completed" });
  } finally { clearTimeout(timer); }
}
try {
  rmSync(codeFile, { force: true });
  await logins.start({ id: "smoke", runtime: "agy", home });
  while (logins.get("smoke")?.state === "starting") await sleep(200);
  assert.equal(logins.get("smoke")?.state, "needs_code", logins.get("smoke")?.error ?? "");
  console.log(`Sign in here, then write the code it shows to ${codeFile}:\n${logins.get("smoke")!.url}`);
  while (!existsSync(codeFile)) await sleep(500);
  await logins.submitCode("smoke", readFileSync(codeFile, "utf8"));
  while (logins.get("smoke")?.state === "verifying") await sleep(200);
  assert.equal(logins.get("smoke")?.state, "done", logins.get("smoke")?.error ?? "");
  assert.ok(existsSync(agyToken(home)), "the sign-in is in the profile's files");
  const check = await checkProfile({ runtime: "agy", kind: "subscription", key: "", via: {}, home, env: process.env as any, machine: false });
  console.log("check:", check.state, check.detail);
  const profile = { id: "smoke", runtime: "agy" as const, home, access: { kind: "subscription" } };
  console.log("models:", (await driver.models(profile)).join(", "));
  const options: OpenOptions = { key: "agy-real-smoke", profile, cwd: data, instructions: "Answer only by calling the stillfail chat_post tool with your answer as its text.", mcpToken: "smoke-token", mcpUrl: `http://127.0.0.1:${port}/mcp`, route: "smoke" };
  const first = turn();
  const session = await driver.open(options, first.event);
  await session.prompt("Post the word 'pineapple' with chat_post.");
  await completed(first.done);
  console.log("posted:", posts);
  assert.ok(posts.some((p) => /pineapple/i.test(p)), "the station's tool was called");
  const kept = readFileSync(transcriptPath("agy", home, session.id())!, "utf8").trim().split("\n").map((l) => JSON.parse(l));
  const call = kept.find((l) => l.type === "tool");
  console.log("the call as kept:", JSON.stringify(call));
  assert.ok(isPosting(call.name), `named as the station's tool: ${call.name}`);
  console.log("usage:", JSON.stringify(kept.find((l) => l.type === "usage")));
  const id = session.id();
  await session.dispose();
  const second = turn();
  const resumed = await driver.open({ ...options, resume: id }, second.event);
  await resumed.prompt("Which word did you post before? Post it again with chat_post.");
  await completed(second.done);
  console.log("posted:", posts);
  assert.ok(posts.slice(1).some((p) => /pineapple/i.test(p)), "the conversation taken up again remembers it");
  await resumed.dispose();
  console.log("Antigravity CLI smoke on a Google account passed");
} finally {
  await logins.close();
  await driver.shutdown();
  server.close();
  rmSync(data, { recursive: true, force: true });
}
