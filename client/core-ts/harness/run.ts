// The side-by-side run (docs/core-ts.md, 怎么验证): the same script of UI messages, against the same fake still.fail
// cloud (harness/cloud.ts, started afresh for each), given to the Rust core (client/node's napi addon) and to the TS
// core (hosts/node.ts); every message each sends to the UI is recorded per step and compared.
//
//   node harness/run.ts <path to stillfail_core.node> [--only rust|ts] [--keep]
//
// Normalized, as truly nondeterministic: the PKCE `state` and `code_challenge` in auth.begin's url (random), a
// `doing` item's `since` (when it was asked) and the access tokens in nothing (they never reach a UI). Everything else
// must be equal: the messages' order per subscription, values, deltas, answers, errors and their words.
import { mkdtempSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { isDeepStrictEqual } from "node:util";
import { FakeCloud, T0 } from "./cloud.ts";
import { start as startTs } from "../src/hosts/node.ts";
import { apply } from "../src/delta.ts";
import { SCRIPT, type Ctx } from "./script.ts";

type CoreApi = { connect(): number; receive(client: number, json: string): void; disconnect(client: number): void };
type Start = (dataDir: string, origin: string, listener: (client: number, json: string) => void) => CoreApi;

/// Each run its own port: a core from a run before (the Rust one cannot be stopped) does not reach the next run's cloud.
const PORTS: Record<string, number> = { rust: 47_311, ts: 47_312 };

export type Recorded = { step: string; messages: unknown[]; states: Record<string, unknown> }[];

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function run(name: string, start: Start): Promise<Recorded> {
  const cloud = new FakeCloud();
  const port = PORTS[name];
  const ORIGIN = `http://127.0.0.1:${port}`;
  await cloud.listen(port);
  const dir = mkdtempSync(join(tmpdir(), `core-${name}-`));
  let inbox: unknown[] = [];
  let last = Date.now();
  const core = start(dir, ORIGIN, (_client, json) => {
    inbox.push(JSON.parse(json));
    last = Date.now();
  });
  const client = core.connect();
  const states = new Map<number, unknown>();
  const recorded: Recorded = [];
  const answers = new Map<number, unknown>();
  const ctx: Ctx = {
    cloud,
    answer: (id) => answers.get(id),
    send: (message) => core.receive(client, typeof message === "string" ? message : JSON.stringify(message)),
    disconnect: () => core.disconnect(client),
  };
  for (const step of SCRIPT) {
    inbox = [];
    last = Date.now();
    await step.run(ctx);
    // Quiet for 400 ms (or at most 15 s): what the step set going has gone out.
    const begun = Date.now();
    await sleep(step.wait ?? 0);
    while (Date.now() - last < 400 && Date.now() - begun < 15_000) await sleep(50);
    for (const m of inbox as Record<string, unknown>[]) {
      const id = m.id as number;
      if ("value" in m) states.set(id, m.value);
      else if ("delta" in m) states.set(id, apply(states.get(id), m.delta as never));
      else if ("ok" in m || "error" in m) answers.set(id, m.ok ?? m.error);
    }
    recorded.push({ step: step.name, messages: inbox.map(normalize), states: Object.fromEntries([...states].map(([k, v]) => [String(k), normalize(v)])) });
  }
  core.disconnect(client);
  await cloud.close();
  await sleep(200);
  rmSync(dir, { recursive: true, force: true });
  return recorded;
}

/// What differs between runs by nature, made the same.
function normalize(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(normalize);
  if (v !== null && typeof v === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, x] of Object.entries(v)) {
      if (k === "url" && typeof x === "string" && x.includes("/v1/auth/google/start")) out[k] = x.replace(/^http:\/\/127\.0\.0\.1:\d+/, "CLOUD").replace(/state=[^&]*/, "state=*").replace(/code_challenge=[^&]*/, "code_challenge=*");
      else if (k === "since" && typeof x === "number") out[k] = "*";
      else out[k] = normalize(x);
    }
    return out;
  }
  return v;
}

const addon = process.argv[2];
const only = process.argv.includes("--only") ? process.argv[process.argv.indexOf("--only") + 1] : null;
const require = createRequire(import.meta.url);
const results: Record<string, Recorded> = {};
if (only !== "ts") results.rust = await run("rust", (require(addon) as { start: Start }).start);
if (only !== "rust") results.ts = await run("ts", startTs as Start);
void T0;

if (results.rust && results.ts) {
  let same = 0;
  let differ = 0;
  let deliberate = 0;
  for (let i = 0; i < SCRIPT.length; i++) {
    const r = results.rust[i];
    const t = results.ts[i];
    // Each subscription's and each call's messages in their order; across them the order is the cores' own (the Rust
    // core reads its live topics in a HashMap's order, which differs from run to run).
    const byId = (ms: unknown[]) => {
      const out: Record<string, unknown[]> = {};
      for (const m of ms as { id: number }[]) (out[String(m.id)] ??= []).push(m);
      return out;
    };
    const exact = isDeepStrictEqual(r.messages, t.messages);
    const reordered = !exact && isDeepStrictEqual(byId(r.messages), byId(t.messages));
    const states = isDeepStrictEqual(r.states, t.states);
    if ((exact || reordered) && states) {
      same++;
      console.log(`✔ ${r.step} (${r.messages.length} messages${reordered ? ", interleaved otherwise" : ""})`);
    } else if (SCRIPT[i].deliberate) {
      deliberate++;
      console.log(`≠ ${r.step}: differs as meant (${SCRIPT[i].deliberate})`);
    } else {
      differ++;
      console.log(`✖ ${r.step}: ${exact ? "messages equal" : reordered ? "same messages, another order" : "messages differ"}; ${states ? "states equal" : "states differ"}`);
      if (!exact) {
        console.log(`  rust: ${JSON.stringify(r.messages)}`);
        console.log(`  ts:   ${JSON.stringify(t.messages)}`);
      }
      if (!states) {
        for (const k of new Set([...Object.keys(r.states), ...Object.keys(t.states)])) {
          if (!isDeepStrictEqual(r.states[k], t.states[k])) console.log(`  state ${k}:\n    rust ${JSON.stringify(r.states[k])}\n    ts   ${JSON.stringify(t.states[k])}`);
        }
      }
    }
  }
  // Whatever happened on the way, the UI must end with the same values.
  const end = isDeepStrictEqual(results.rust[SCRIPT.length - 1].states, results.ts[SCRIPT.length - 1].states);
  console.log(`\n${same} steps the same, ${deliberate} different as meant, ${differ} differ; the end state ${end ? "the same" : "DIFFERS"}`);
  process.exit(differ === 0 && end ? 0 : 1);
} else {
  const [name, recorded] = Object.entries(results)[0];
  for (const r of recorded) console.log(`${name} ${r.step}: ${JSON.stringify(r.messages)}`);
  process.exit(0);
}
