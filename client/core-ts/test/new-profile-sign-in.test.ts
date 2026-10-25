// A sign-in for a new profile (the overview's `logins`, docs/client-core.md): a step the station answers for (started,
// its code taken) shows as the call answers, not once the overview is next told; what the station tells after it is
// what shows, and an answer that comes after the station told more is not shown over it.
import assert from "node:assert/strict";
import { test } from "node:test";
import { apply as applyOps } from "../src/delta.ts";
import type { HttpResponse } from "../src/host.ts";
import { type FakeHost, jsonResponse } from "../src/testing.ts";
import { answers, call, subscribe, v } from "./helpers.ts";
import { base, overview, started, stationLater } from "./station-fixture.ts";

const ST = "ws/st";
const AUTHORIZE = "https://claude.ai/oauth/authorize?code=true&client_id=c";
const job = (state: string, more: Record<string, unknown> = {}) => ({ profile: "login-1", runtime: "claude", state, url: null, userCode: null, error: null, startedAt: 1, expiresAt: 2, ...more });
/// The overview with the sign-in in it as the station tells it.
const told = (j: unknown, created: string | null = null) => ({ ...overview, logins: [{ id: "login-1", runtime: "claude", job: j, created, error: null }] });

/// What the core sent since: each subscription's value (deltas applied) into `values`; the messages, for the answers.
function drain(host: FakeHost, values: Map<number, unknown>) {
  const emitted = host.takeEmitted();
  for (const [, message] of emitted) {
    const m = message as Record<string, unknown>;
    if ("value" in m) values.set(m.id as number, m.value);
    else if ("delta" in m) values.set(m.id as number, applyOps(values.get(m.id as number), m.delta as never));
  }
  return emitted;
}

/// The sign-in as the overview topic (the web's page) and the stations topic (the phone's and the desktop's) show it.
function shown(values: Map<number, unknown>) {
  const of = (o: any) => (o?.logins ?? []).find((l: any) => l.id === "login-1") ?? null;
  const page = of(v(values, 1));
  const app = of(v(values, 2)?.find((s: any) => s.station === ST)?.overview);
  assert.deepEqual(app, page, "the same on every page");
  return page;
}

test("a new profile's sign-in: started and its code taken show as the calls answer; what the station tells after shows", async () => {
  const { host, core, push } = await started({ ...base(), "POST /logins": { id: "login-1", job: job("starting") }, "POST /logins/login-1/code": { job: job("verifying", { url: AUTHORIZE }) } });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "overview", station: ST });
  subscribe(core, ui, 2, { topic: "stations", scope: "ws" });
  await host.settle();
  drain(host, values);
  assert.equal(shown(values), null);

  call(core, ui, 10, "login.new", { station: ST, runtime: "claude" });
  await host.settle();
  assert.deepEqual(answers(drain(host, values), 10)?.ok, { id: "login-1", job: job("starting") });
  assert.deepEqual([shown(values).job.state, shown(values).created ?? null], ["starting", null], "there as the call answers, before the station tells it");

  push("overview", told(job("needs_code", { url: AUTHORIZE })));
  await host.settle();
  drain(host, values);
  assert.deepEqual([shown(values).job.state, shown(values).job.url], ["needs_code", AUTHORIZE]);

  call(core, ui, 11, "login.code", { station: ST, id: "login-1", code: "abc#def" });
  await host.settle();
  assert.ok(answers(drain(host, values), 11)?.ok);
  assert.equal(shown(values).job.state, "verifying", "the code taken shows at once: not its field again, empty, until the station's next overview");
  // An overview the station made before the code went in, told after the answer: the code is still taken.
  push("overview", told(job("needs_code", { url: AUTHORIZE })));
  await host.settle();
  drain(host, values);
  assert.equal(shown(values).job.state, "verifying");

  push("overview", told(job("done", { url: AUTHORIZE }), "cuesurf6-proton-me"));
  await host.settle();
  drain(host, values);
  assert.deepEqual([shown(values).job.state, shown(values).created], ["done", "cuesurf6-proton-me"]);
  // Past it, the station's word alone: an overview without the sign-in (its station started again) has none.
  push("overview", overview);
  await host.settle();
  drain(host, values);
  assert.equal(shown(values), null);
  core.close();
});

test("a new profile's sign-in: an answer that comes after the station told more is not shown over it; one dropped is let go", async () => {
  const { host, core, push } = await started({ ...base(), "POST /logins/login-1/code": { job: job("verifying") }, "DELETE /logins/login-1": { ok: true } });
  let answer: ((r: HttpResponse) => void) | null = null;
  stationLater(host, (req) => (req.method === "POST" && req.url.endsWith("/logins/login-1/code") ? new Promise((resolve) => (answer = resolve)) : undefined));
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "overview", station: ST });
  subscribe(core, ui, 2, { topic: "stations", scope: "ws" });
  await host.settle();
  push("overview", told(job("needs_code", { url: AUTHORIZE })));
  await host.settle();
  drain(host, values);
  assert.equal(shown(values).job.state, "needs_code");

  call(core, ui, 11, "login.code", { station: ST, id: "login-1", code: "abc" });
  await host.settle();
  // The station took it, signed in and made the profile, and its overview came before the answer did.
  push("overview", told(job("done"), "cuesurf6-proton-me"));
  await host.settle();
  drain(host, values);
  assert.notEqual(answer, null, "the code went");
  answer!(jsonResponse(200, { job: job("verifying") }));
  await host.settle();
  assert.ok(answers(drain(host, values), 11)?.ok);
  assert.deepEqual([shown(values).job.state, shown(values).created], ["done", "cuesurf6-proton-me"], "what the station told since stays");

  // Dropped while its code was taken: nothing of what was answered is shown any more.
  push("overview", told(job("needs_code")));
  stationLater(host, () => undefined);
  await host.settle();
  call(core, ui, 12, "login.code", { station: ST, id: "login-1", code: "abc" });
  await host.settle();
  drain(host, values);
  assert.equal(shown(values).job.state, "verifying");
  call(core, ui, 13, "login.drop", { station: ST, id: "login-1" });
  await host.settle();
  drain(host, values);
  assert.equal(shown(values).job.state, "needs_code", "as the station last told it, until it tells the sign-in gone");
  core.close();
});
