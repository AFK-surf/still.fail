// A login lent to another station is renewed first when it is in the window it is renewed early in, and lent fresh when
// the renewal answers within LEND_BOUND_MS (10 s, on the lender's clock); past that, the token it has (still lasting
// the usual margin) is lent and the renewal goes on behind, its end said. One past the usual margin waits for its
// renewal as before. The station that asked waits 30 s (mesh/peer.ts ANSWER_MS), as long as a renewal's call to its
// provider may take: a renewal that timed out had its token lent 343 ms after the asker gave up, the chat's turn lost
// (2026-11-14). The renewals here are held until the test says how they end; time is a TestClock.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { type IncomingMessage, type ServerResponse, createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import type { Clock } from "effect";
import { checkConfig } from "../src/accounts/check.ts";
import { type Bound, LEND_BOUND_MS, claudeOAuthToken, renewedBehind } from "../src/accounts/oauth.ts";
import { Cloud } from "../src/cloud/state.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { Fibers } from "../src/ops/fibers.ts";
import { type Line, hearLines } from "../src/ops/log.ts";
import { Sharing } from "../src/share/index.ts";
import { given, settle, testClock } from "./hub-fakes.ts";

const lines: Line[] = [];
hearLines((line) => void lines.push(line));

/// A promise and what settles it.
function held<T = void>() {
  let resolve!: (v: T) => void, reject!: (e: Error) => void;
  const promise = new Promise<T>((res, rej) => ((resolve = res), (reject = rej)));
  return { promise, resolve, reject };
}

/// Whether `p` has settled by the time all set going is done.
async function answered(p: Promise<unknown>): Promise<boolean> {
  let done = false;
  p.then(() => (done = true), () => (done = true));
  await settle();
  return done;
}

/// A token endpoint whose calls are held until `answer` says how; `asked()` once one is held.
async function holding() {
  const calls: ServerResponse[] = [];
  let came = held();
  const server = createServer((req: IncomingMessage, res) => {
    req.resume();
    if (req.method !== "POST") { res.writeHead(404).end(); return; }
    calls.push(res);
    came.resolve();
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  const address = server.address();
  return {
    base: `http://127.0.0.1:${typeof address === "object" && address ? address.port : 0}`,
    calls,
    asked: () => came.promise,
    /// Each call held answered with `status` (200: a new token).
    answer(status: number) {
      came = held();
      for (const res of calls.splice(0)) {
        res.writeHead(status, { "content-type": "application/json", connection: "close" });
        res.end(JSON.stringify(status === 200 ? { access_token: "new", refresh_token: "refresh-new", expires_in: 28800 } : { error: "unavailable" }));
      }
    },
    close: () => new Promise<void>((r) => { server.closeAllConnections(); server.close(() => r()); }),
  };
}

/// Once the renewal's call is at the endpoint, raced against the lend's own end: a socket's arrival is not what settle()
/// waits for (it counts turns with no file request out), so it is never taken by a count of turns. A lend that ends
/// without having called fails the test, saying so.
function called(p: { asked(): Promise<void> }, lend: Promise<unknown>): Promise<void> {
  return Promise.race([
    p.asked(),
    lend.then(
      () => { throw new Error("lent without its renewal called"); },
      (e: Error) => { throw new Error(`failed without its renewal called: ${e.message}`); },
    ),
  ]);
}

const credentials = (expiresAt: number) => ({ claudeAiOauth: { accessToken: "old", refreshToken: "refresh-old", expiresAt, scopes: ["user:inference"] } });
const HOUR = 3_600_000;
const said = (message: string, key: string, value: string) => lines.find((l) => l.message.startsWith(message) && l.fields[key] === value);

/// A Claude login in the window it is renewed early in (half an hour left), lent with the bound on a TestClock.
async function claudeLend() {
  const home = mkdtempSync(join(tmpdir(), "lend-claude-"));
  writeFileSync(join(home, ".credentials.json"), JSON.stringify(credentials(Date.now() + 30 * 60_000)));
  const p = await holding();
  const time = testClock();
  const fibers = new Fibers("lend", time.clock);
  const bound: Bound = { ms: LEND_BOUND_MS, after: (ms, f) => fibers.after(ms, f) };
  const lend = () => claudeOAuthToken({}, home, null, p.base, "en", HOUR, bound);
  return { home, p, time, lend, close: async () => { await fibers.close(); await p.close(); } };
}

test("a Claude login lent in its early-renewal window is renewed first: the fresh token, when the renewal answers within the bound", async () => {
  const c = await claudeLend();
  try {
    const lent = c.lend();
    await called(c.p, lent);
    assert.equal(await answered(lent), false, "waits for the renewal");
    c.p.answer(200);
    // (its answer comes back over a socket: the lend ends by itself, answered)
    assert.equal((await lent)[0], "new");
  } finally { await c.close(); }
});

test("a Claude login whose renewal outlasts the bound is lent as it has it at the bound; the renewal goes on, its end said", async () => {
  const c = await claudeLend();
  try {
    const lent = c.lend();
    await called(c.p, lent);
    await settle();
    assert.equal(await answered(lent), false);
    await c.time.adjust(LEND_BOUND_MS);
    const [token, expiresAt] = await given(lent, "lent at the bound");
    assert.equal(token, "old", "the token it has");
    assert.ok(expiresAt - Date.now() > 25 * 60_000);
    assert.ok(said("a Claude login's renewal outlasted the lend's bound", "login", c.home), "said");
    // Asked again meanwhile: the same renewal waited on, no second call.
    const again = c.lend();
    await settle();
    assert.equal(c.p.calls.length, 1, "one renewal at a time");
    c.p.answer(503);
    await renewedBehind(c.home);
    const line = said("a Claude login was not renewed early", "login", c.home);
    assert.ok(line && typeof line.fields.ms === "number" && Number(line.fields.lastsMin) > 25, "its end said, with how long what was lent lasts");
    assert.equal((await given(again, "the second lend, its renewal over"))[0], "old");
  } finally { await c.close(); }
});

test("a Claude login lent past the usual margin waits for its renewal, and fails as before when it fails", async () => {
  const home = mkdtempSync(join(tmpdir(), "lend-claude-late-"));
  writeFileSync(join(home, ".credentials.json"), JSON.stringify(credentials(Date.now() + 60_000)));
  const p = await holding();
  const time = testClock();
  const fibers = new Fibers("lend", time.clock);
  const bound: Bound = { ms: LEND_BOUND_MS, after: (ms, f) => fibers.after(ms, f) };
  try {
    const lend = claudeOAuthToken({}, home, null, p.base, "en", HOUR, bound);
    lend.catch(() => {});
    await called(p, lend);
    await time.adjust(LEND_BOUND_MS);
    assert.equal(await answered(lend), false, "no bound for it: waits for the renewal");
    p.answer(503);
    await assert.rejects(lend, /503/);
    const renewed = claudeOAuthToken({}, home, null, p.base, "en", HOUR, bound);
    await called(p, renewed);
    p.answer(200);
    assert.equal((await renewed)[0], "new");
  } finally { await fibers.close(); await p.close(); }
});

// ── Codex: the host's own Codex asked to renew it ──

const A = "a".repeat(64);
const B = "b".repeat(64);

/// One workspace of A and B, as share.test.ts's FakeCloud gives it.
function cloudFor(station: string): Cloud {
  const peers = [{ id: A, name: "studio" }, { id: B, name: "mini" }];
  return Object.defineProperties(Object.create(Cloud.prototype), Object.getOwnPropertyDescriptors({
    peersCurrent: true,
    lock: null,
    get state() { return { station, workspace: "w", workspace_name: "w", peers, revocations: [], joined: [] } as any; },
    listen() { return () => {}; },
  })) as any;
}

function station(id: string, others: Map<string, Sharing>, profiles: any[], codexRenewRunning: (id: string) => Promise<boolean>, clock?: Clock.Clock) {
  const data = mkdtempSync(join(tmpdir(), "lend-codex-"));
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles }));
  const config = new ConfigFile(data);
  config.check = checkConfig;
  mkdirSync(join(data, "agent", "skills"), { recursive: true });
  const sharing = new Sharing({
    data, config, cloud: cloudFor(id),
    ask: async (to, _ws, request) => {
      const other = others.get(to);
      if (!other) throw new Error("peer unavailable");
      return other.handle(id, request, "w");
    },
    agentHome: () => join(data, "agent"), env: {},
    claudeToken: async () => { throw new Error("no Claude here"); },
    codexRenewRunning,
    status: async () => ({ check: null, quota: null }),
    changed: () => {},
    ...(clock ? { clock } : {}),
  });
  return { data, config, sharing };
}

const jwt = (seconds: number) => ["{}", JSON.stringify({ exp: Math.floor(Date.now() / 1000) + seconds }), "s"].map((p) => Buffer.from(p).toString("base64url")).join(".");
const login = (seconds: number) => JSON.stringify({ tokens: { id_token: "id", access_token: jwt(seconds), account_id: "acct", refresh_token: "r" } });
const CODEX = { id: "plus", name: "ChatGPT Plus", runtime: "codex", access: { kind: "subscription" }, home: "homes/plus", env: {} };

/// A shares its Codex login (lasting `seconds`) with B, A on a TestClock set at now; the Codex running on it at A is asked to
/// renew it, and its answer held (`renewal`; `renewed(seconds)` writes the login it renews to first).
async function sharedCodex(seconds: number) {
  const all = new Map<string, Sharing>();
  const asked: string[] = [];
  const renewal = held<boolean>();
  const reached = held();
  const time = testClock();
  // (the share's clock at now, as the logins' expiries are: a TestClock begins at 0, where every login lasts for ever)
  await time.adjust(Date.now());
  const a = station(A, all, [CODEX], (id) => (asked.push(id), reached.resolve(), renewal.promise), time.clock);
  const b = station(B, all, [], async () => false);
  all.set(A, a.sharing).set(B, b.sharing);
  const file = join(a.data, "homes", "plus", "auth.json");
  mkdirSync(join(a.data, "homes", "plus"), { recursive: true });
  writeFileSync(file, login(seconds));
  await a.sharing.shareProfile("plus", true, null);
  await a.sharing.reconcile();
  await b.sharing.reconcile();
  const copy = b.config.raw().profiles[0];
  assert.ok(copy, "B has A's");
  const renewed = (lasts: number) => { writeFileSync(file, login(lasts)); renewal.resolve(true); };
  return { a, b, asked, time, renewal, renewed, reached: reached.promise, copy: { ...copy, home: join(b.data, copy.home) } };
}

test("a Codex login lent in its early-renewal window is renewed first: the fresh one, when the renewal answers within the bound", async () => {
  const s = await sharedCodex(2 * 3600);
  try {
    const lent = s.b.sharing.lendCodex(s.copy);
    await given(s.reached, "its renewal asked");
    assert.equal(await answered(lent), false, "waits for the renewal");
    s.renewed(10 * 86400);
    assert.ok((await given(lent, "lent once renewed")) > Date.now() + 9 * 86400_000, "the renewed login");
  } finally { await s.a.sharing.close(); await s.b.sharing.close(); }
});

test("a Codex login whose renewal outlasts the bound is lent as it has it at the bound; the renewal goes on, a failure said", async () => {
  const s = await sharedCodex(2 * 3600);
  try {
    const lent = s.b.sharing.lendCodex(s.copy);
    await given(s.reached, "its renewal asked");
    assert.equal(await answered(lent), false);
    await s.time.adjust(LEND_BOUND_MS);
    const until = await given(lent, "lent at the bound");
    assert.ok(until > Date.now() + 3600_000 && until <= Date.now() + 2 * 3600_000, "the login it has");
    assert.ok(said("a shared Codex login's renewal outlasted the lend's bound", "profile", "plus"), "said");
    const again = s.b.sharing.lendCodex(s.copy, true);
    await settle();
    assert.deepEqual(s.asked, ["plus"], "one renewal at a time");
    s.renewal.reject(new Error("the app-server did not answer"));
    await s.a.sharing.renewedBehind("plus");
    const line = said("renewing a shared Codex login failed", "profile", "plus");
    assert.ok(line && typeof line.fields.ms === "number" && Number(line.fields.lastsMin) > 100, "its end said, with how long what was lent lasts");
    assert.ok((await given(again, "the second lend, its renewal over")) > Date.now() + 3600_000);
  } finally { await s.a.sharing.close(); await s.b.sharing.close(); }
});

test("a Codex login lent with less than an hour left waits for its renewal, and is refused as before when it fails", async () => {
  const s = await sharedCodex(600);
  try {
    const lent = s.b.sharing.lendCodex(s.copy);
    lent.catch(() => {});
    await given(s.reached, "its renewal asked");
    await s.time.adjust(LEND_BOUND_MS);
    assert.equal(await answered(lent), false, "no bound for it: waits for the renewal");
    s.renewal.reject(new Error("refused"));
    await assert.rejects(lent, /未能借出/);
  } finally { await s.a.sharing.close(); await s.b.sharing.close(); }
});
