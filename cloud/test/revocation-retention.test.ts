import assert from "node:assert/strict";
import test from "node:test";
import { build } from "esbuild";
import { Miniflare, convertV4MiniflareOptions, Log, LogLevel } from "miniflare";

const DAY = 86400;
const START = 4_102_444_800;
const expiry = (at: number) => (at + 31 * DAY + 1) * 1000;

// Actual Directory methods in an ephemeral SQLite DO; no real Axiom, relay,
// customer persistence or production test routes. Explicit alarm invocations
// verify the stored schedule and purge semantics, NOT real-provider delivery SLA.
test("revocations: inclusive replay, autonomous schedule, monotonic retries and shared presence alarm", { timeout: 30000 }, async () => {
  const script = (await build({ entryPoints: ["test/revocation-retention-worker.ts"], bundle: true, write: false, format: "esm", platform: "node", external: ["cloudflare:workers", "cloudflare:sockets", "node:*"], conditions: ["workerd", "worker", "browser"], banner: { js: 'import { createRequire } from "node:module"; const require = createRequire("file:///worker.js");' } })).outputFiles[0].text;
  const mf = new Miniflare(convertV4MiniflareOptions({ log: new Log(LogLevel.ERROR), workers: [{ name: "retention-test", modules: true, script, compatibilityDate: "2026-09-08", compatibilityFlags: ["nodejs_compat"],
    bindings: { PUBLIC_ORIGIN: "https://retention.test", GRANT_SIGNING_JWK: JSON.stringify({ kty: "OKP", crv: "Ed25519", d: "synthetic", x: "synthetic", kid: "test" }) },
    durableObjects: { DIRECTORY: { className: "RevocationFixture", useSQLite: true } },
    outboundService: () => { throw new Error("outbound I/O prohibited in retention fixture"); },
  }] }));
  const call = async (body: unknown, expectedStatus = 200): Promise<any> => {
    const response = await mf.dispatchFetch("https://retention.test/test", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    const text = await response.text();
    assert.equal(response.status, expectedStatus, `fixture ${JSON.stringify(body)}: HTTP ${response.status}\n${text}`);
    try { return JSON.parse(text); }
    catch (error) { throw new Error(`fixture ${JSON.stringify(body)} returned non-JSON: ${text}`, { cause: error }); }
  };
  const sockets: any[] = [];
  const connect = async (race = false) => {
    const response = await mf.dispatchFetch(`https://retention.test/${race ? "connect-race" : "connect"}`, { headers: { upgrade: "websocket" } });
    assert.equal(response.status, 101);
    const ws = response.webSocket!;
    sockets.push(ws);
    const frames: any[] = [];
    let pong: (() => void) | undefined;
    ws.addEventListener("message", event => event.data === "pong" ? pong?.() : frames.push(JSON.parse(event.data as string)));
    ws.accept();
    return { frames, ping: () => new Promise<void>(resolve => { pong = resolve; ws.send("ping"); }) };
  };
  try {
    const original = await call({ op: "seed", now: START * 1000 });
    assert.equal(original.clearanceTarget, DAY * 1000, "24h clearance target only, not SLA");
    assert.equal(original.alarm, null, "first mutation starts with zero sockets and no alarm");
    await call({ op: "fail", count: 2 });
    let state = await call({ op: "revoke", sids: ["session-a"], cutoff: START }, 503);
    assert.equal(state.mutationRejected, true, "both scheduling attempts failing rejects the actual mutation promise");
    assert.equal(state.errors.length, 1);
    assert.match(state.errors[0], /synthetic_alarm_failure/);
    assert.equal(state.alarm, null, "failure cannot be mistaken for a durable wake-up");
    assert.deepEqual(state.revocations, [{ workspace: "a", kind: "sid", id: "session-a", at: START }], "SQL row survives failure with original cutoff");
    state = await call({ op: "revoke", now: (START + 1) * 1000, sids: ["session-a"], cutoff: START });
    assert.equal(state.mutationRejected, false);
    assert.equal(state.revocations[0].at, START, "explicit original-cutoff retry does not extend retention");
    assert.deepEqual(state.errors, []);
    assert.equal(state.alarm, expiry(START), "zero sockets/traffic: durable alarm at first expired second");
    state = await call({ op: "revoke", now: (START + DAY) * 1000, sids: ["session-a"], cutoff: START });
    assert.equal(state.revocations[0].at, START);
    assert.equal(state.alarm, expiry(START), "same explicit cutoff does not reset retention");
    state = await call({ op: "revoke", sids: ["session-a"], cutoff: START - DAY });
    assert.equal(state.revocations[0].at, START, "older retry cannot lower cutoff");
    assert.equal(state.alarm, expiry(START));
    await call({ op: "legacy", workspace: "b", kind: "sub", id: "other-sub", cutoff: START + DAY });
    await call({ op: "legacy", workspace: "a", kind: "sid", id: "other-sid", cutoff: START + DAY });
    state = await call({ op: "restart" });
    assert.equal(state.alarm, expiry(START), "constructor rearms legacy rows without resetting cutoff");
    state = await call({ op: "alarm", now: (START + 31 * DAY) * 1000 });
    assert.equal(state.revocations.length, 3, "inclusive 31-day boundary is not purged");
    assert.equal(state.alarm, expiry(START));
    const boundary = await connect();
    await boundary.ping();
    assert.deepEqual(boundary.frames[0].revocations.find((r: any) => r.id === "session-a"), { kind: "sid", id: "session-a", at: START }, "wire replay unchanged at inclusive boundary");
    state = await call({ op: "alarm", now: expiry(START) });
    assert.equal(state.revocations.length, 2, "first expired second purges exactly expired row");
    await call({ op: "revoke", sids: ["session-a"], cutoff: START });
    await boundary.ping();
    assert.equal(boundary.frames.filter(f => f.type === "revoke" && f.id === "session-a").length, 0, "expired retry cannot broadcast after purge");
    state = await call({ op: "inspect" });
    assert.equal(state.revocations.some((r: any) => r.id === "session-a"), false, "expired retry cannot resurrect");
    const later = START + 31 * DAY + 1;
    state = await call({ op: "revoke", sids: ["session-a"], cutoff: later });
    await boundary.ping();
    assert.deepEqual(boundary.frames.find(f => f.type === "revoke"), { type: "revoke", kind: "sid", id: "session-a", at: later }, "new genuine revocation persists then broadcasts unchanged frame");
    assert.equal(state.revocations.find((r: any) => r.id === "session-a").at, later);
    state = await call({ op: "disconnect" });
    state = await call({ op: "alarm" });
    assert.equal(state.alarm, expiry(START + DAY), "disconnect all stations never cancels pending purge");
    state = await call({ op: "alarm", now: expiry(START + DAY) });
    assert.deepEqual(state.revocations.map((r: any) => r.id), ["session-a"], "zero sockets: purge happens without revocation traffic");
    assert.equal(state.alarm, expiry(later));
    assert.deepEqual(state.users, original.users);
    assert.deepEqual(state.identities, original.identities, "Apple mapping is untouched");
    assert.deepEqual(state.memberships, original.memberships, "other users/workspaces untouched");
    const live = await connect(true);
    await live.ping();
    state = await call({ op: "inspect" });
    assert.equal(state.alarm, expiry(START + DAY) + 90_000, "station connect advances far-future purge to presence deadline");
    const unchanged = state.alarm;
    // Repeated calls coordinate asynchronously but may not overwrite the earlier presence deadline.
    state = await call({ op: "revoke", sids: ["later-session"] });
    assert.equal(state.alarm, unchanged);
    state = await call({ op: "revoke", sids: ["later-session"] });
    await live.ping();
    const sessionFrames = () => live.frames.filter(f => f.type === "revoke" && f.id === "later-session");
    assert.equal(sessionFrames().length, 2, "distinct same-second session revocations still broadcast");
    state = await call({ op: "revoke", sids: ["later-session"], cutoff: START + 32 * DAY + 1 });
    await live.ping();
    assert.equal(sessionFrames().length, 2, "explicit same-cutoff retry does not duplicate the broadcast");
    assert.equal(state.alarm, unchanged, "same-second revocations do not extend retention or presence");
    state = await call({ op: "role", role: "admin" });
    assert.equal(state.revocations.find((r: any) => r.id === "bob" && r.kind === "sub").at, START + 32 * DAY + 1, "existing callers retain fresh cutoffs");
    state = await call({ op: "remove" });
    await live.ping();
    assert.equal(live.frames.filter(f => f.type === "revoke" && f.id === "bob").length, 2, "same-second role change and removal each reach the station");
    assert.equal(state.revocations.find((r: any) => r.id === "bob" && r.kind === "sub").at, START + 32 * DAY + 1, "same-second mutation retains the original persisted cutoff");
    const beforeFailureWrites = state.writes.length;
    await call({ op: "fail" });
    state = await call({ op: "revoke", sids: ["fault-session"] }, 503);
    assert.equal(state.writes.length, beforeFailureWrites + 2, "transient scheduling failure gets an immediate recovery attempt");
    assert.equal(state.mutationRejected, true);
    assert.equal(state.errors.length, 1, "mutation scheduling rejection propagates to its caller");
    assert.match(state.errors[0], /synthetic_alarm_failure/);
    state = await call({ op: "revoke", sids: ["fault-session"] });
    assert.deepEqual(state.errors, [], "failed queue remains recoverable on stable retry");
    assert.equal(state.alarm, unchanged);
    await call({ op: "fail" });
    state = await call({ op: "alarm" }, 503);
    assert.equal(state.errors.length, 1, "alarm rejects scheduling errors for provider retry");
    state = await call({ op: "alarm" });
    assert.deepEqual(state.errors, []);
    state = await call({ op: "disconnect" });
    await call({ op: "fail" });
    state = await call({ op: "restart" }, 503);
    assert.equal(state.errors.length, 1, "startup scheduling failure is awaited and visible");
    state = await call({ op: "restart" });
    assert.deepEqual(state.errors, []);
    assert.equal(state.alarm, expiry(later), "startup with no sockets preserves remaining purge schedule");
  } finally {
    for (const socket of sockets) { try { socket.close(1000); } catch {} }
    await mf.dispose();
  }
});
