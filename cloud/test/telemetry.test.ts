import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { harness } from "./harness.ts";
import { TELEMETRY_BATCHES_PER_MINUTE as BATCHES_PER_MINUTE } from "../src/limits.ts";

type Harness = Awaited<ReturnType<typeof harness>>;
const hex = (bytes: ArrayBuffer) => Buffer.from(bytes).toString("hex");

async function key() {
  const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const id = hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
  const sign = async (message: string) => hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(message)));
  return { id, sign };
}

/** Axiom as the tests see it: every request it got. */
function fakeAxiom(status = 200) {
  const got: { headers: Record<string, string>; body: any }[] = [];
  const answer = async (request: Request) => {
    got.push({ headers: Object.fromEntries(request.headers), body: JSON.parse(await request.text()) });
    return new Response("{}", { status });
  };
  return { got, answer };
}

const batch = (name = "chat.open", spans = 1) => JSON.stringify({
  resourceSpans: [{
    resource: { attributes: [{ key: "service.name", value: { stringValue: "ember-web" } }] },
    scopeSpans: [{ scope: { name: "ember-core" }, spans: Array.from({ length: spans }, () => ({ traceId: "4bf92f3577b34da6a3ce929d0e0e4736", spanId: "00f067aa0ba902b7", name, kind: 1, startTimeUnixNano: "1", endTimeUnixNano: "2" })) }],
  }],
});

const post = (h: Harness, body: string, headers: Record<string, string> = {}) =>
  h.fetch("/v1/telemetry/traces", { method: "POST", headers: { "content-type": "application/json", ...headers }, body });

async function enrolled(h: Harness) {
  const alice = h.as(await h.login("alice"));
  const workspace = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
  const enrollment = (await (await alice("POST", `/v1/workspaces/${workspace}/enrollments`, { name: "studio" })).json()) as any;
  const station = await key();
  const response = await h.fetch("/v1/stations/enroll", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ token: enrollment.token, station: station.id, signature: await station.sign(`ember-station-enroll-v1:${h.origin}:${enrollment.token}:${station.id}`) }),
  });
  assert.equal(response.status, 200);
  return station;
}

/** A station's signed headers for `body`. */
async function signed(h: Harness, station: Awaited<ReturnType<typeof key>>, body: string, ts = Math.floor(Date.now() / 1000)) {
  const digest = createHash("sha256").update(body).digest("hex");
  return { "x-ember-station": station.id, "x-ember-ts": String(ts), "x-ember-signature": await station.sign(`ember-station-telemetry-v1:${h.origin}:${station.id}:${ts}:${digest}`) };
}

test("a signed-in client's spans go on to Axiom with ember cloud's token", async () => {
  const axiom = fakeAxiom();
  const h = await harness({ axiom: axiom.answer });
  try {
    const tokens = await h.login("alice");
    const body = batch();
    const response = await post(h, body, { authorization: `Bearer ${tokens.access_token}` });
    assert.equal(response.status, 202);
    assert.equal(axiom.got.length, 1);
    assert.equal(axiom.got[0]!.headers.authorization, "Bearer test-axiom-token");
    assert.equal(axiom.got[0]!.headers["x-axiom-dataset"], "ember-test");
    assert.deepEqual(axiom.got[0]!.body, JSON.parse(body));

    // Nobody, or a token that is no good: nothing goes on.
    assert.equal((await post(h, body)).status, 401);
    assert.equal((await post(h, body, { authorization: "Bearer nope" })).status, 401);
    // Not OTLP, or too much of it.
    assert.equal((await post(h, "[]", { authorization: `Bearer ${tokens.access_token}` })).status, 400);
    assert.equal((await post(h, batch("x", 1001), { authorization: `Bearer ${tokens.access_token}` })).status, 413);
    assert.equal(axiom.got.length, 1);
  } finally {
    await h.close();
  }
});

test("a station's spans are signed with its key, over the body", async () => {
  const axiom = fakeAxiom();
  const h = await harness({ axiom: axiom.answer });
  try {
    const station = await enrolled(h);
    const body = batch("GET /admin/api/threads");
    assert.equal((await post(h, body, await signed(h, station, body))).status, 202);
    assert.equal(axiom.got.length, 1);
    // Another body under the same signature, an old signature, or a key that is not enrolled: refused.
    assert.equal((await post(h, batch("forged"), await signed(h, station, body))).status, 401);
    assert.equal((await post(h, body, await signed(h, station, body, Math.floor(Date.now() / 1000) - 600))).status, 401);
    const stranger = await key();
    assert.equal((await post(h, body, await signed(h, stranger, body))).status, 401);
    assert.equal(axiom.got.length, 1);
  } finally {
    await h.close();
  }
});

test("each sender has its own budget a minute", async () => {
  const axiom = fakeAxiom();
  const h = await harness({ axiom: axiom.answer });
  try {
    const alice = await h.login("alice");
    const bob = await h.login("bob");
    const body = batch();
    for (let i = 0; i < BATCHES_PER_MINUTE; i++) assert.equal((await post(h, body, { authorization: `Bearer ${alice.access_token}` })).status, 202);
    const refused = await post(h, body, { authorization: `Bearer ${alice.access_token}` });
    assert.equal(refused.status, 429);
    assert.equal(refused.headers.get("retry-after"), "60");
    assert.equal((await post(h, body, { authorization: `Bearer ${bob.access_token}` })).status, 202);
    assert.equal(axiom.got.length, BATCHES_PER_MINUTE + 1);
  } finally {
    await h.close();
  }
});

test("without Axiom, or when it fails, a batch is refused and not retried", async () => {
  const off = await harness();
  try {
    const tokens = await off.login("alice");
    assert.equal((await post(off, batch(), { authorization: `Bearer ${tokens.access_token}` })).status, 503);
  } finally {
    await off.close();
  }
  const axiom = fakeAxiom(500);
  const h = await harness({ axiom: axiom.answer });
  try {
    const tokens = await h.login("alice");
    assert.equal((await post(h, batch(), { authorization: `Bearer ${tokens.access_token}` })).status, 502);
    assert.equal(axiom.got.length, 1);
  } finally {
    await h.close();
  }
});

test("a call in a recorded trace is a span of ember cloud's, without ids", async () => {
  const axiom = fakeAxiom();
  const h = await harness({ axiom: axiom.answer });
  try {
    const alice = await h.login("alice");
    const workspace = ((await (await h.as(alice)("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    const trace = "4bf92f3577b34da6a3ce929d0e0e4736";
    const call = (traceparent?: string) => h.fetch(`/v1/workspaces/${workspace}`, { headers: { authorization: `Bearer ${alice.access_token}`, ...(traceparent ? { traceparent } : {}) } });
    assert.equal((await call(`00-${trace}-00f067aa0ba902b7-01`)).status, 200);
    for (let i = 0; i < 100 && axiom.got.length === 0; i++) await new Promise((r) => setTimeout(r, 10));
    assert.equal(axiom.got.length, 1);
    const resource = axiom.got[0]!.body.resourceSpans[0];
    assert.deepEqual(resource.resource.attributes, [{ key: "service.name", value: { stringValue: "ember-cloud" } }]);
    const span = resource.scopeSpans[0].spans[0];
    assert.equal(span.traceId, trace);
    assert.equal(span.parentSpanId, "00f067aa0ba902b7");
    assert.equal(span.name, "GET /v1/workspaces/:id");
    assert.ok(BigInt(span.endTimeUnixNano) >= BigInt(span.startTimeUnixNano));
    assert.deepEqual(span.attributes.find((a: any) => a.key === "http.response.status_code"), { key: "http.response.status_code", value: { intValue: "200" } });
    assert.ok(!JSON.stringify(span).includes(workspace));

    // Not recorded by the caller, or no trace: no span.
    await call(`00-${trace}-00f067aa0ba902b7-00`);
    await call();
    await new Promise((r) => setTimeout(r, 200));
    assert.equal(axiom.got.length, 1);
  } finally {
    await h.close();
  }
});
