// The Comma account provider (src/comma.ts, contract v1 §4–5) in a whole core: the host's session is the account,
// Comma's answers kept in still.fail cloud's shapes, its SSE events followed, member credentials asked for with the
// session and reused as still.fail cloud's are, the workspace operations Comma has mapped and the others refused.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Queue } from "effect";
import { COMMA_ACCOUNT_KEY, commaAccountProvider, credentialOf, meOf, workspaceOf } from "../src/comma.ts";
import { CREDENTIAL_KEY, Core } from "../src/core.ts";
import type { HttpRequest } from "../src/host.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { parseJson, toJsonBytes } from "../src/util.ts";
import { answers, call, nowS } from "./helpers.ts";
import { run } from "./run.ts";

const ORIGIN = "https://comma.test";
const ME = { user: { id: "usr_1", email: "a@x.com", name: "Ada" }, workspaces: [{ id: "ws1", name: "Team", role: "owner" }], relay_urls: ["https://relay.comma.test"] };
const header = (r: HttpRequest, name: string) => r.headers.find(([k]) => k === name)?.[1];

type Rig = { host: FakeHost; core: Core; up: { on: boolean }; asked: number; events: Queue.Queue<Uint8Array | null> | null; token: { value: string | null } };

async function rig(): Promise<Rig> {
  const host = new FakeHost();
  const r: Rig = { host, core: null as unknown as Core, up: { on: true }, asked: 0, events: null, token: { value: "sess-1" } };
  host.onFetch((req) => {
    if (!req.url.startsWith(ORIGIN)) return jsonResponse(404, { error: "not_found" });
    if (!r.up.on) throw new Error("connection refused");
    if (header(req, "authorization") !== `Bearer ${r.token.value}`) return jsonResponse(401, { error: "unauthorized" });
    const path = req.url.slice(ORIGIN.length);
    const key = `${req.method} ${path}`;
    switch (key) {
      case "GET /v1/comma/stations/me":
        return jsonResponse(200, ME);
      case "GET /v1/comma/workspaces/ws1/stations":
        return jsonResponse(200, { stations: [{ id: "st", name: "studio", version: "0.1.9", online: false, enrolled_at: 1, enrolled_by: "usr_1" }] });
      case "POST /v1/comma/workspaces/ws1/station-credential":
        r.asked++;
        return jsonResponse(200, { credential: `c${r.asked}`, issued_at: Math.floor(nowS()), expires_at: Math.floor(nowS()) + 30 * 86400, relay_urls: ["https://relay.comma.test"] });
      case "POST /v1/comma/workspaces/ws1/stations/enrollments":
        return jsonResponse(200, { token: "t", command: `curl -fsSL ${ORIGIN}/stations/install.sh | sh -s -- t`, expires_at: 1 });
      case "PATCH /v1/comma/workspaces/ws1/stations/st":
      case "DELETE /v1/comma/workspaces/ws1/stations/st":
        return jsonResponse(200, {});
      default:
        return jsonResponse(404, { error: "not_found" });
    }
  });
  host.onFetchStream((req) =>
    Effect.gen(function* () {
      const queue = yield* Queue.unbounded<Uint8Array | null>();
      if (req.url === `${ORIGIN}/v1/comma/workspaces/ws1/stations/events`) r.events = queue;
      return { status: 200, headers: [["content-type", "text/event-stream"]] as [string, string][], body: { take: Queue.take(queue) } };
    }),
  );
  r.core = await Core.create(host, { clock: host.time.clock, account: commaAccountProvider({ origin: ORIGIN, bearer: async () => (r.token.value === null ? Promise.reject(new Error("signed out")) : r.token.value) }) });
  return r;
}

async function settled(host: FakeHost, what: () => boolean) {
  for (let i = 0; i < 200 && !what(); i++) await host.settle();
  assert.ok(what(), "settled");
}

test("Comma's answers in still.fail cloud's shapes", () => {
  assert.deepEqual(meOf(ME), {
    user: { id: "usr_1", email: "a@x.com", name: "Ada", picture: "" },
    workspaces: [{ id: "ws1", name: "Team", role: "owner" }],
    invitations: [],
    relay_urls: ["https://relay.comma.test"],
    relay_url: "https://relay.comma.test",
  });
  assert.equal(meOf({ workspaces: [] }), null);
  assert.deepEqual(workspaceOf("ws1", { stations: [{ id: "st", name: "s" }, { name: "no id" }] }, meOf(ME)), {
    id: "ws1", name: "Team", role: "owner", stations: [{ id: "st", name: "s" }], members: [], invitations: [],
  });
  assert.deepEqual(credentialOf({ credential: "c", issued_at: 1, expires_at: 2, relay_urls: ["https://r"] }), { credential: "c", issued_at: 1, expires_at: 2, relay_url: "https://r" });
  assert.equal(typeof credentialOf({ credential: "c" }), "string");
});

test("the host's session is the account: its workspaces, stations and events", async () => {
  const { host, core } = await rig();
  const inner = core.inner;
  await settled(host, () => inner.accounts.list().length === 1);
  assert.deepEqual(inner.accounts.list(), [{ sub: "usr_1", email: "a@x.com", name: "Ada", picture: "" }]);
  // Kept, for a start with Comma away.
  assert.deepEqual(parseJson(host.stored(COMMA_ACCOUNT_KEY)!), { sub: "usr_1", email: "a@x.com", name: "Ada", picture: "" });
  await settled(host, () => inner.workspaces.owner("ws1") === "usr_1" && inner.cloudSync.nameOf("ws1/st") === "studio");
  assert.deepEqual(await run(inner.cloudSync.relaysNow()), ["https://relay.comma.test"]);
  // Every call carries the session; nothing of the account is asked of still.fail cloud (what changed in the app, its
  // changelog, is the host's to say).
  assert.deepEqual([...new Set(host.requests.filter((q) => !q.url.startsWith(ORIGIN)).map((q) => new URL(q.url).pathname))], ["/v1/changelog"]);
  assert.ok(host.requests.filter((q) => q.url.startsWith(ORIGIN)).every((q) => header(q, "authorization") === "Bearer sess-1"));
  // No login sessions, operator lists or pushes asked for: Comma has none of them here.
  assert.ok(!host.requests.some((q) => /auth\/sessions|admin|push/.test(q.url)));
  core.close();
});

test("a station's SSE event updates the workspace in place; a list change reads it again", async () => {
  const r = await rig();
  const { host, core } = r;
  const inner = core.inner;
  await settled(host, () => r.events !== null && inner.cloudSync.nameOf("ws1/st") === "studio");
  const send = (text: string) => Queue.offerUnsafe(r.events!, new TextEncoder().encode(text));
  const station = () => (inner.data.get({ topic: "workspace", workspace: "ws1" }) as { stations: { online: boolean }[] }).stations[0]!;
  assert.equal(station().online, false);
  const reads = () => host.requests.filter((q) => q.url.endsWith("/v1/comma/workspaces/ws1/stations")).length;
  const before = reads();
  send('event: station\ndata: {"id":"st","online":true}\n\n');
  await settled(host, () => station().online === true);
  assert.equal(reads(), before, "online in place, nothing read");
  send("event: stations\ndata: {}\n\n");
  await settled(host, () => reads() === before + 1);
  // A heartbeat is the socket's pong.
  send(": heartbeat\n\n");
  await host.settle();
  core.close();
});

test("member credentials: asked with the session, kept a day, the kept one serving while Comma is away", async () => {
  const r = await rig();
  const { host, core } = r;
  const inner = core.inner;
  await settled(host, () => inner.workspaces.owner("ws1") === "usr_1");
  const credential = (fresh: boolean) => run(inner.cloudSync.credential("ws1", "dev", fresh, null));
  const first = await credential(false);
  assert.equal(first.credential, "c1");
  assert.equal(first.relay_url, "https://relay.comma.test");
  const asked = host.requests.find((q) => q.url.endsWith("/station-credential"))!;
  assert.deepEqual(parseJson(asked.body!), { device: "dev" });
  assert.equal((await credential(false)).credential, "c1");
  assert.equal(r.asked, 1);
  // A day on, with Comma away: the kept one, until it runs out.
  const old = { device: "dev", credential: "old", issued_at: Math.floor(nowS()) - 2 * 86400, expires_at: Math.floor(nowS()) + 86400, relay_url: "" };
  host.store(`${CREDENTIAL_KEY}/usr_1/ws1`, toJsonBytes(old));
  r.up.on = false;
  assert.equal((await credential(false)).credential, "old");
  host.store(`${CREDENTIAL_KEY}/usr_1/ws1`, toJsonBytes({ ...old, expires_at: Math.floor(nowS()) - 1 }));
  await assert.rejects(credential(false));
  r.up.on = true;
  assert.equal((await credential(false)).credential, "c2");
  core.close();
});

test("workspace operations Comma has go to it; the others are refused as unsupported", async () => {
  const r = await rig();
  const { host, core } = r;
  await settled(host, () => core.inner.workspaces.owner("ws1") === "usr_1");
  const ui = core.connect();
  call(core, ui, 1, "workspace.enroll", { account: "usr_1", workspace: "ws1", name: "mini" });
  call(core, ui, 2, "workspace.renameStation", { account: "usr_1", workspace: "ws1", station: "st", name: "studio 2" });
  call(core, ui, 3, "workspace.removeStation", { account: "usr_1", workspace: "ws1", station: "st" });
  call(core, ui, 4, "workspace.invite", { account: "usr_1", workspace: "ws1", role: "member", email: "b@x.com" });
  call(core, ui, 5, "auth.begin", { redirect_uri: "https://x/auth/callback", return_to: "/" });
  const emitted: [number, unknown][] = [];
  await settled(host, () => {
    emitted.push(...(host.takeEmitted() as [number, unknown][]));
    return [1, 2, 3, 4, 5].every((id) => answers(emitted as never, id) !== undefined);
  });
  assert.deepEqual(answers(emitted as never, 1)!.ok, { token: "t", command: `curl -fsSL ${ORIGIN}/stations/install.sh | sh -s -- t`, expires_at: 1 });
  assert.deepEqual(answers(emitted as never, 2)!.ok, {});
  assert.deepEqual(answers(emitted as never, 3)!.ok, {});
  assert.equal((answers(emitted as never, 4)!.error as { code: string }).code, "unsupported");
  assert.equal((answers(emitted as never, 5)!.error as { code: string }).code, "unsupported");
  const sent = host.requests.filter((q) => q.method !== "GET").map((q) => [q.method, q.url.slice(ORIGIN.length)]);
  assert.deepEqual(sent.filter(([, p]) => !p.endsWith("/station-credential")), [
    ["POST", "/v1/comma/workspaces/ws1/stations/enrollments"],
    ["PATCH", "/v1/comma/workspaces/ws1/stations/st"],
    ["DELETE", "/v1/comma/workspaces/ws1/stations/st"],
  ]);
  core.close();
});

test("the app signed out: the account goes", async () => {
  const r = await rig();
  const { host, core } = r;
  await settled(host, () => core.inner.accounts.list().length === 1);
  r.token.value = null;
  await assert.rejects(run(core.inner.accounts.accessToken("usr_1")), (e: { code: string }) => e.code === "signed_out");
  // Another start of the core with Comma refusing the session (401): what was kept of the account goes.
  r.token.value = "sess-2";
  const second = await Core.create(host, { clock: host.time.clock, account: commaAccountProvider({ origin: ORIGIN, bearer: async () => "stale" }) });
  assert.equal(second.inner.accounts.list().length, 1, "started with the kept account");
  await settled(host, () => second.inner.accounts.list().length === 0);
  assert.equal(host.stored(COMMA_ACCOUNT_KEY), undefined);
  core.close();
  second.close();
});
