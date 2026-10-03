// One core's data directory opened by the other (docs/core-ts.md, 数据兼容): the Rust core (its Node addon, built from a commit that still has it: 7091dc84) signs
// in, sets prefs and a draft, and the TS core opened on its directory shows the same accounts, workspaces, prefs and
// draft before reaching anything; then the other way round (going back to the Rust core keeps what the TS core did).
//
//   node harness/handover.ts <path to stillfail_core.node>
import { mkdtempSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { isDeepStrictEqual } from "node:util";
import { FakeCloud } from "./cloud.ts";
import { start as startTs } from "../src/hosts/node.ts";
import { apply } from "../src/delta.ts";

type CoreApi = { connect(): number; receive(client: number, json: string): void; disconnect(client: number): void };
type Start = (dataDir: string, origin: string, listener: (client: number, json: string) => void) => CoreApi;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const PORT = 47_321;
const ORIGIN = `http://127.0.0.1:${PORT}`;

/// A UI of a core: what each subscription shows and what each call answered.
function ui(start: Start, dir: string) {
  const states = new Map<number, unknown>();
  const answers = new Map<number, unknown>();
  let last = Date.now();
  const core = start(dir, ORIGIN, (_c, json) => {
    const m = JSON.parse(json) as Record<string, unknown>;
    const id = m.id as number;
    if ("value" in m) states.set(id, m.value);
    else if ("delta" in m) states.set(id, apply(states.get(id), m.delta as never));
    else if ("ok" in m || "error" in m) answers.set(id, m.ok ?? m.error);
    last = Date.now();
  });
  const client = core.connect();
  return {
    send: (m: unknown) => core.receive(client, JSON.stringify(m)),
    states,
    answers,
    async quiet() {
      const begun = Date.now();
      await sleep(100);
      while (Date.now() - last < 400 && Date.now() - begun < 10_000) await sleep(50);
    },
    leave: () => core.disconnect(client),
  };
}

/// Signs `who` in and leaves prefs and a draft.
async function use(u: ReturnType<typeof ui>, who: string, appearance: string, text: string) {
  u.send({ id: 1, subscribe: { topic: "accounts" } });
  u.send({ id: 50, call: "auth.begin", params: { redirect_uri: "stillfail://auth/callback", return_to: "/" } });
  await u.quiet();
  const state = new URL(String((u.answers.get(50) as { url: string }).url)).searchParams.get("state");
  u.send({ id: 51, call: "auth.complete", params: { query: `?code=code-${who}&state=${state}` } });
  await u.quiet();
  u.send({ id: 52, call: "prefs.set", params: { appearance, onlyMine: true } });
  u.send({ id: 53, call: "draft.put", params: { station: "ws1/st1", chat: "new", text, quotes: [], files: [] } });
  await u.quiet();
}

/// What a UI sees of a directory at once: accounts, workspaces, prefs, the draft.
async function look(u: ReturnType<typeof ui>) {
  u.send({ id: 1, subscribe: { topic: "accounts" } });
  u.send({ id: 2, subscribe: { topic: "workspaces" } });
  u.send({ id: 3, subscribe: { topic: "prefs" } });
  u.send({ id: 60, call: "draft.get", params: { station: "ws1/st1", chat: "new" } });
  await u.quiet();
  const accounts = (u.states.get(1) as { sub: string; email: string }[] | undefined)?.map((a) => [a.sub, a.email]);
  const workspaces = u.states.get(2);
  const prefs = u.states.get(3) as Record<string, unknown> | undefined;
  return { accounts, workspaces, appearance: prefs?.appearance, onlyMine: prefs?.onlyMine, draft: u.answers.get(60) };
}

const require = createRequire(import.meta.url);
const rust = (require(process.argv[2]!) as { start: Start }).start;
const cloud = new FakeCloud();
await cloud.listen(PORT);
let failed = 0;
for (const [from, to, fromName, toName, who] of [
  [rust, startTs as Start, "Rust", "TS", "alice"],
  [startTs as Start, rust, "TS", "Rust", "bob"],
] as const) {
  const dir = mkdtempSync(join(tmpdir(), "handover-"));
  const before = ui(from, dir);
  await use(before, who, "dark", `${who} 的草稿`);
  const seen = await look(before);
  before.leave();
  await sleep(500);
  const after = ui(to, dir);
  const opened = await look(after);
  after.leave();
  const same = isDeepStrictEqual(seen, opened) && seen.accounts?.length === 1 && seen.draft !== undefined && (seen.draft as { text: string }).text !== "";
  if (!same) failed++;
  console.log(`${same ? "✔" : "✖"} ${fromName} → ${toName}: ${JSON.stringify(opened)}${same ? "" : `\n  ${fromName} saw ${JSON.stringify(seen)}`}`);
  rmSync(dir, { recursive: true, force: true });
}
await cloud.close();
process.exit(failed === 0 ? 0 : 1);
