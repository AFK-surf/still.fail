// The usage page (`usage`: GET /usage) and the usage a Comma connect sends (`outflowUsage`), by the MoonBit reader
// (station/mb src/readops/usagepage.mbt; read/pool.ts MOVED) as the worker reads them, on the same database: calls of
// sessions of two workspaces and the home one, in still.fail chats, Slack and Feishu threads and none, by people of the
// station's page, a Slack workspace (known and not), the cloud (named and not), of models priced by the catalog, the
// station's table, an effort tier or none, fast and not, at whole minutes and within them; every provider and access an
// account of the config can be on; tasks other stations ran here; the page's year with its chats and cards. Read for
// every viewer, in either language, over spans with partial minutes, with and without the year's range, while the
// details are prepared and as the page waits for the summary.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { learn } from "../src/accounts/catalog.ts";
import { SOURCES } from "../src/agents/providers.ts";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";
import { installCompactUsage, installUsageSummaryChanges } from "../src/store/usage-compact.ts";
import { installUsageSummaryBlocks, usageSummaryBlocksStep } from "../src/store/usage-summary-blocks.ts";

const binary = mbReaderBinary();
const I64_MAX = "9223372036854775807";
const DAY = 86_400_000;

const skip = binary === null ? "the MoonBit program is not built here" : false;
test("the MoonBit reader reads the usage page as the worker does, of the compact statistics", { skip }, () => compare(true));
test("the MoonBit reader reads the usage page as the worker does, of a store from before them", { skip }, () => compare(false));

/// `compact`: the statistics a station keeps now (store/usage-compact.ts, with their summary blocks), else the details
/// of a store from before them (store/usage-detail.ts).
async function compare(compact: boolean) {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-usage-page-"));
  const profiles: unknown[] = [
    { id: "cc", name: "  Claude  ", runtime: "claude", access: { kind: "subscription" } },
    { id: "cx", name: "", runtime: "codex", access: { kind: "subscription" } },
    { id: "ds", runtime: "dsh", access: { kind: "subscription" } },
    { id: "dsv", runtime: "dsh", access: { kind: "env" } },
    { id: "go", runtime: "codex", access: { kind: "opencode-go", key: "k" } },
    { id: "ak", runtime: "codex", access: { kind: "anthropic-api", key: "k" } },
    { id: "odd", runtime: "nonsense" },
    { id: "bare" },
    { id: "listed", runtime: "grok", access: [] },
    { id: "12", name: "Numbered", runtime: "cursor" },
    { id: "3", name: "Three", runtime: "devin" },
    { id: "cc", name: "Again", runtime: "hermes" },
    { name: "no id" },
    null,
    { id: "kimi", runtime: "codex", access: { kind: "api-provider", provider: "kimi-code", login: true } },
    { id: "kimi-key", runtime: "codex", access: { kind: "api-provider", provider: "kimi-code" } },
    { id: "nobody", access: { kind: "api-provider" } },
    { id: "unknown", access: { kind: "api-provider", provider: "who" } },
  ];
  // every provider, at no address, at addresses usable and not, with each protocol
  for (const s of SOURCES) {
    profiles.push({ id: `p-${s.id}`, runtime: "claude", access: { kind: "api-provider", provider: s.id } });
    for (const [i, endpoint] of [" https://gw.example/v1/a/b/ ", "https://gw.example/v1//", "https://gw.example/v1", "http://gw.example/compat", "ftp://x", "https://", "https://a b"].entries()) {
      profiles.push({ id: `p-${s.id}-${i}`, access: { kind: "api-provider", provider: s.id, endpoint } });
      for (const protocol of ["chat_completions", "responses", "anthropic", "other", ""])
        profiles.push({ id: `p-${s.id}-${i}-${protocol}`, access: { kind: "api-provider", provider: s.id, endpoint, protocol } });
    }
  }
  writeFileSync(join(data, "config.json"), JSON.stringify({
    profiles,
    connects: [{ id: "team", slack: { team: { id: "T1", name: "Team" } } }, { id: "fs", kind: "feishu", feishu: { tenant: { name: "Co" } } }],
  }));
  writeFileSync(join(data, "slack-names.json"), JSON.stringify({
    "c:T1:C1": { channel: "general" }, "u:T1:U1": { person: { name: "Una", email: "una@x", picture: "https://p/u1" } },
  }));
  writeFileSync(join(data, "feishu-names.json"), JSON.stringify({ "u:fs:ou1": { person: { name: "飞书人" } } }));
  learn({ "claude-opus-5-5": { cost: { input: 3, output: 15, cacheRead: 0.3 } }, "told-model": { cost: { input: 1, output: 2 } }, "gemini-4-hydrogen": { cost: { input: 0.5, output: 1, cacheRead: 0.05 } } });
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const db = store.db;
  if (compact) {
    installCompactUsage(db, () => 0);
    installUsageSummaryChanges(db);
    installUsageSummaryBlocks(db);
  }
  const session = (key: string, ws: string | null, connect = "ember") =>
    store.insertSession({ key, connect, runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ws } as Parameters<Store["insertSession"]>[0]);
  session("a", "w");
  session("b", null);
  session("c", "x");
  session("s", "w", "team");
  session("f", null, "fs");
  const named = store.openThread("ember", "CHAT", "named", "Named chat", null).id;
  store.joinThread(named, "a", "ember");
  const unnamed = store.openThread("ember", "CHAT", "unnamed", null, null).id;
  store.joinThread(unnamed, "b", "ember");
  const slack = store.openThread("slack:T1", "C1", "1.1", null, null).id;
  store.joinThread(slack, "s", "team");
  store.insertMessage({ ...newMessage(slack, "1.1", "person", "U1", "<@U9> please   look\nat this"), at: 10 } as ReturnType<typeof newMessage>);
  const quiet = store.openThread("slack:T1", "C1", "1.2", null, null).id;
  store.joinThread(quiet, "s", "team");
  const feishu = store.openThread("feishu:fs", "oc1", "m1", null, null).id;
  store.joinThread(feishu, "f", "fs");
  // a chat of the home workspace's and of w's both (counted once for a viewer of both)
  const both = store.openThread("ember", "CHAT", "both", "Both", null).id;
  store.joinThread(both, "a", "ember");
  store.joinThread(both, "b", "ember");
  const far = store.openThread("ember", "CHAT", "far", "Far", null).id;
  store.joinThread(far, "c", "ember");
  db.prepare("UPDATE threads SET hidden_at = 5 WHERE id = ?").run(far);
  let id = 0;
  const call = (sessionKey: string, at: number, model: string | null, of: { thread?: number | null; person?: string | null; profile?: string }, extra: Record<string, unknown> = {}) =>
    store.recordUsage(`/t/${sessionKey}`, { session: sessionKey, offset: ++id, model }, "claude", [[{
      id: `call${id}`, at, model, subagent: false, fast: false, input: 1000 * id, cacheRead: 300, cacheWrite: 20, cacheWriteLong: 5, output: 70, calls: 1,
      context: null, window: null, ...extra,
    }, { turn: null, thread: of.thread ?? null, person: of.person ?? null, profile: of.profile ?? "cc" }]] as never);
  call("a", 60_000, "claude-opus-5-5", { thread: named, person: "p@x" });
  call("a", 90_500, "anthropic/claude-opus-5-5[1m]", { thread: named, person: "local" }, { fast: true });
  call("a", DAY + 120_000, "gpt-6-luna", { thread: named, person: "q@x", profile: "cx" });
  call("b", 30_000, "gemini-4-hydrogen-high", { thread: unnamed, person: "local" });
  call("b", 2 * DAY + 5, "unpriced-model", { thread: unnamed, person: "slack:team:U2" });
  call("b", 3 * DAY, null, { person: null });
  call("s", 45_000, "told-model", { thread: slack, person: "slack:team:U1" });
  call("s", 61_000, "claude-sonnet-5-5", { thread: quiet, person: "slack:team:U1" });
  call("f", 200_000, "claude-haiku-4-5", { thread: feishu, person: "slack:fs:ou1" });
  call("c", 100_000, "claude-opus-4-8", { thread: far, person: "p@x", profile: "go" });
  call("a", 400 * DAY, "claude-opus-5-5", { thread: named, person: "p@x" });
  // a model of the station's table by its effort tier, one only named like one of it, a call of the home workspace's
  // within a minute the span begins in
  call("b", 47_000, "claude-sonnet-4-6-high", { thread: unnamed, person: "local" });
  call("c", 3 * DAY + 7, "claude-opus-4-8x", { thread: far, person: "p@x" });
  for (const [job, at, key] of [["j1", 1000, "a"], ["j2", 2 * DAY, "b"], ["j3", 70_000, "c"], ["j4", -5, "a"], ["j5", 30_500, "a"], ["j6", 30_500, "b"]] as const)
    db.prepare("INSERT INTO remote_runs (job, at, session) VALUES (?, ?, ?)").run(job, at, key);
  const card = db.prepare("INSERT INTO card_outcomes (thread, n, author, labels, answered, said) VALUES (?, ?, 'agent', '[]', 1, ?)");
  card.run(named, 1, 1); card.run(named, 2, 0); card.run(slack, 3, 1); card.run(far, 4, 0);
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  for (const r of [worker, program]) r.names.set("p@x", "Pat");
  const read = (r: Readers, op: string, args: unknown, lang: "zh" | "en") => r.read(op, args, lang).then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const viewers = [null, { email: "p@x", workspace: "w", home: true }, { email: "p@x", workspace: "x", home: false }, { email: "p@x", workspace: "w" }];
  const spans: [string | number, string | number][] = [[0, I64_MAX], ["0", "180000"], [30_500, 95_000], [61_000, 61_000], [90_000, 30_000], [-DAY, 2 * DAY + 1], [DAY, "9223372036854775806"]];
  const all = async (r: Readers) => {
    const out: unknown[] = [];
    for (const lang of ["zh", "en"] as const)
      for (const viewer of viewers)
        for (const [from, to] of spans)
          for (const tz of [0, 480, -300])
            out.push(await read(r, "usage", { lang, from, to, tz, viewer, ...(tz === 480 ? { reading: false } : {}) }, lang));
    for (const viewer of viewers) {
      for (const historyRange of [undefined, { from: 0, to: 365 * DAY }, { from: -480 * 60_000, to: 2 * DAY - 480 * 60_000 }, { from: 1, to: DAY }, { from: 0, to: 400 * DAY }])
        for (const tz of [0, 480])
          out.push(await read(r, "usage", { lang: "en", from: 0, to: I64_MAX, tz, viewer, history: true, ...(historyRange ? { historyRange } : {}) }, "en"));
      out.push(await read(r, "usage", { lang: "zh", from: 0, to: I64_MAX, tz: 0, viewer, detailsPreparing: true, history: true }, "zh"));
      for (const prepared of [true, false])
        out.push(await read(r, "usage", { lang: "en", from: 30_500, to: 95_000, tz: 0, viewer, summaryStrict: true, summaryPrepared: prepared }, "en"));
    }
    out.push(await read(r, "usage", { from: 1.5, to: 2, tz: 0 }, "en"));
    out.push(await read(r, "usage", { from: "x", to: 2, tz: 0 }, "en"));
    for (const ws of [undefined, { workspace: "w", home: true }, { workspace: "x" }, { workspace: "w", home: false }, "w"])
      for (const [from, to, tz] of [[0, 40 * DAY, 0], [30_500, 95_000, 2000], [0, 5 * DAY, -3000], [1.5, "x", 60]] as [unknown, unknown, unknown][])
        out.push(await read(r, "outflowUsage", { from, to, tz, ...(ws === undefined ? {} : { ws }) }, "zh"));
    return out;
  };
  try {
    if (compact) {
      // before the summary blocks are prepared: those that wait for them are refused
      const waiting = async (r: Readers) => {
        const out: unknown[] = [];
        for (const viewer of viewers)
          for (const prepared of [undefined, true, false])
            out.push(await read(r, "usage", { lang: "en", from: 30_500, to: 95_000, tz: 0, viewer, ...(prepared === undefined ? {} : { summaryStrict: true, summaryPrepared: prepared }) }, "en"));
        return out;
      };
      assert.deepEqual(await waiting(program), await waiting(worker));
      while (!usageSummaryBlocksStep(db).done) { /* each step a transaction of its own */ }
    }
    const first = await all(program);
    const second = await all(worker);
    for (let i = 0; i < first.length; i++) assert.deepEqual(first[i], second[i], `read ${i}`);
    // from when every call was counted, as the compact statistics say it (begun after the first call, or not known
    // when that was); and the cards' outcomes not all known yet
    const some = async (r: Readers) => {
      const out: unknown[] = [];
      for (const viewer of viewers) out.push(await read(r, "usage", { lang: "en", from: 30_500, to: I64_MAX, tz: 0, viewer, history: true }, "en"));
      return out;
    };
    for (const change of [...(compact ? ["UPDATE usage_compact_since SET since = 75000, first_unknown = 0", "UPDATE usage_compact_since SET since = 1, first_unknown = 0",
      "UPDATE usage_compact_since SET first_unknown = 1"] : ["UPDATE usage_span SET first_at = 75000", "UPDATE usage_span SET first_at = NULL"]),
    "CREATE TABLE card_outcomes_incomplete (id INTEGER PRIMARY KEY)"]) {
      db.exec(change);
      assert.deepEqual(await some(program), await some(worker), change);
    }
    // calls counted after the summary blocks were made, and one of them grown: what the blocks hold and what changed since
    call("a", 120_000, "claude-opus-5-5", { thread: named, person: "p@x" });
    call("b", 2 * DAY + 30, "claude-opus-5-5", { thread: unnamed, person: "local" });
    db.prepare("UPDATE usage SET input = input + 7, calls = calls + 1 WHERE at = 60000").run();
    const spanned = async (r: Readers) => {
      const out: unknown[] = [];
      for (const viewer of viewers) for (const [from, to] of spans) out.push(await read(r, "usage", { lang: "en", from, to, tz: 0, viewer }, "en"));
      return out;
    };
    assert.deepEqual(await spanned(program), await spanned(worker));
    const said = JSON.stringify(first);
    for (const sign of ["\"title\":\"Named chat\"", "\"title\":\"please look\"", "general", "\"name\":\"Una\"", "\"name\":\"Pat\"", "\"remoteRuns\":[{", "\"places\":{", "\"cards\":", "\"beforeDay\":", "\"detailsPreparing\":true", "\"runtime\":\"grok\"", "\"runtime\":\"dsh\"", "\"runtime\":\"codex\"", "\"model\":\"told-model\"", "\"account\":"])
      assert.ok(said.includes(sign), sign);
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
}
