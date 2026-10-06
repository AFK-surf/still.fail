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

/** Axiom as the tests see it: every request it got, and `until` one it got is so (what a Worker sends once its answer is out). */
function fakeAxiom(status = 200) {
  const got: { headers: Record<string, string>; body: any }[] = [];
  const waiting = new Set<() => void>();
  const answer = async (request: Request) => {
    got.push({ headers: Object.fromEntries(request.headers), body: JSON.parse(await request.text()) });
    for (const wake of waiting) wake();
    return new Response("{}", { status });
  };
  const until = async <T>(find: (g: typeof got) => T | undefined): Promise<T> => {
    for (;;) {
      const found = find(got);
      if (found !== undefined) return found;
      await new Promise<void>((resolve) => {
        const wake = () => (waiting.delete(wake), resolve());
        waiting.add(wake);
      });
    }
  };
  return { got, answer, until };
}

/** The spans' trace ids, in the order Axiom got them. */
const traces = (got: { body: any }[]) => got.map((g) => g.body.resourceSpans[0].scopeSpans[0].spans[0].traceId);

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
    body: JSON.stringify({ token: enrollment.token, station: station.id, signature: await station.sign(`stillfail-station-enroll-v1:${h.origin}:${enrollment.token}:${station.id}`) }),
  });
  assert.equal(response.status, 200);
  return station;
}

/** A station's signed headers for `body`. */
async function signed(h: Harness, station: Awaited<ReturnType<typeof key>>, body: string, ts = h.now()) {
  const digest = createHash("sha256").update(body).digest("hex");
  return { "x-stillfail-station": station.id, "x-stillfail-ts": String(ts), "x-stillfail-signature": await station.sign(`stillfail-station-telemetry-v1:${h.origin}:${station.id}:${ts}:${digest}`) };
}

test("a signed-in client's spans go on to Axiom with still.fail cloud's token", async () => {
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
    assert.equal((await post(h, body, await signed(h, station, body, h.now() - 600))).status, 401);
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

test("a call in a recorded trace is a span of still.fail cloud's, without ids", async () => {
  const axiom = fakeAxiom();
  const h = await harness({ axiom: axiom.answer });
  try {
    const alice = await h.login("alice");
    const workspace = ((await (await h.as(alice)("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
    const trace = "4bf92f3577b34da6a3ce929d0e0e4736";
    const call = (traceparent?: string) => h.fetch(`/v1/workspaces/${workspace}`, { headers: { authorization: `Bearer ${alice.access_token}`, ...(traceparent ? { traceparent } : {}) } });
    assert.equal((await call(`00-${trace}-00f067aa0ba902b7-01`)).status, 200);
    await axiom.until((got) => got[0]);
    assert.equal(axiom.got.length, 1);
    const resource = axiom.got[0]!.body.resourceSpans[0];
    assert.deepEqual(resource.resource.attributes, [{ key: "service.name", value: { stringValue: "stillfail-cloud" } }]);
    const span = resource.scopeSpans[0].spans[0];
    assert.equal(span.traceId, trace);
    assert.equal(span.parentSpanId, "00f067aa0ba902b7");
    assert.equal(span.name, "GET /v1/workspaces/:id");
    assert.ok(BigInt(span.endTimeUnixNano) >= BigInt(span.startTimeUnixNano));
    assert.deepEqual(span.attributes.find((a: any) => a.key === "http.response.status_code"), { key: "http.response.status_code", value: { intValue: "200" } });
    assert.ok(!JSON.stringify(span).includes(workspace));

    // Not recorded by the caller, or no trace: no span. (One more recorded call after them: its span is the next.)
    await call(`00-${trace}-00f067aa0ba902b7-00`);
    await call();
    const next = "5ce0e9a56015fec5aadfa328ae398115";
    assert.equal((await call(`00-${next}-00f067aa0ba902b7-01`)).status, 200);
    await axiom.until((got) => traces(got).find((t) => t === next));
    assert.deepEqual(traces(axiom.got), [trace, next]);
  } finally {
    await h.close();
  }
});

test("a traced refresh's span says what became of the session, and the answer carries no notes", async () => {
  const axiom = fakeAxiom();
  const h = await harness({ axiom: axiom.answer });
  try {
    const alice = await h.login("alice");
    let n = 0;
    const refresh = async (token: string) => {
      const trace = (++n).toString(16).padStart(32, "a");
      const response = await h.fetch("/v1/auth/refresh", {
        method: "POST",
        headers: { authorization: `Bearer ${token}`, "content-type": "application/json", traceparent: `00-${trace}-00f067aa0ba902b7-01` },
        body: JSON.stringify({ request_id: `01J00000000000000000000${String(n).padStart(3, "0")}` }),
      });
      assert.equal(response.headers.get("x-stillfail-span"), null);
      const body = (await response.json()) as any;
      const span = await axiom.until((got) => got.map((g) => g.body.resourceSpans[0].scopeSpans[0].spans[0]).find((s: any) => s.traceId === trace));
      const notes = Object.fromEntries(span.attributes.map((a: any) => [a.key, a.value.stringValue ?? Number(a.value.intValue)]));
      return { status: response.status, body, notes };
    };
    const first = await refresh(alice.refresh_token);
    assert.equal(first.status, 200);
    assert.equal(first.notes["stillfail.auth.outcome"], "rotated");
    assert.equal(first.notes["stillfail.account"], alice.subject);
    assert.equal(first.notes["stillfail.session"], alice.session_id);
    assert.deepEqual([first.notes["stillfail.auth.presented_generation"], first.notes["stillfail.auth.generation"]], [0, 1]);

    const again = await refresh(alice.refresh_token);
    assert.equal(again.notes["stillfail.auth.outcome"], "retried");
    assert.equal(typeof again.notes["stillfail.auth.rotated_ago"], "number");

    const second = await refresh(first.body.refresh_token);
    assert.equal(second.notes["stillfail.auth.outcome"], "rotated");
    // The first credential again, past the one retry the session keeps: reuse, and the session is gone.
    const reused = await refresh(alice.refresh_token);
    assert.equal(reused.status, 401);
    assert.deepEqual([reused.notes["stillfail.auth.outcome"], reused.notes["stillfail.auth.presented_generation"], reused.notes["stillfail.auth.generation"]], ["reused", 0, 2]);
    const gone = await refresh(second.body.refresh_token);
    assert.equal(gone.status, 401);
    assert.equal(gone.notes["stillfail.auth.outcome"], "no_session");
    assert.equal(gone.notes["stillfail.auth.gone"], "reused");

    const forged = await refresh(`${alice.refresh_token.split(".").slice(0, 2).join(".")}.forged`);
    assert.equal(forged.status, 401);
    assert.equal(forged.notes["stillfail.auth.outcome"], "invalid_token");
    assert.equal(forged.notes["stillfail.account"], alice.subject);
  } finally {
    await h.close();
  }
});
