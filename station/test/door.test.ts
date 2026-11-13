// The door (src/mesh/door.ts) with an admission that is not the station's: what a later line on the control stream
// (a renewal) does to the connection. One its admission refuses by any error is answered why and closes nothing (the
// station's every refusal: test/renewal-role.test.ts); one it refuses with an `Ending` is answered, and the connection
// closed a while after, as the door closes a refused hello's, nothing more served on it meanwhile: whether or not
// the other end takes the answer in, and from a renewal answered later (a promise) as from one answered at once.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mock, test, type TestContext } from "node:test";
import { type Admit, Ending, door } from "../src/mesh/door.ts";
import { Reader, send, writeLine } from "../src/mesh/wire.ts";
import { wall } from "../src/ops/fibers.ts";
import { memoryMesh } from "./memory-mesh.ts";

const ALPN = Buffer.from("door-test/1");

// The machine's timers are the test's: all the door arms is a refusal's close.
type Timer = { ms: number; fire: () => void };
const timers: Timer[] = [];
let armed: ((timer: Timer) => void) | null = null;
mock.method(wall, "after", (ms: number, fire: () => void) => {
  const timer = { ms, fire };
  timers.push(timer);
  armed?.(timer);
  armed = null;
  return () => {};
});
/// The next timer armed, once it is.
const nextTimer = () => new Promise<Timer>((resolve) => (armed = resolve));

/// A server whose members are "a" and "b", by the name their hello says, and a device connected to it that has not said
/// hello yet. A renewal is let in (its member's name again), refused and the connection left as it was (another's
/// name), or refused and the connection ended (`{out}`: the line an `Ending` is answered by default; `{told}`: a line
/// of its own); with `later`, answered by a promise. `window`: how many bytes a stream's reader may leave unread
/// before a write to it waits (none: any number).
async function setUp(t: TestContext, window = 0) {
  timers.length = 0;
  const mesh = memoryMesh({ window });
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false });
  const [at, device] = await Promise.all([bind(), bind()]);
  t.after(() => Promise.all([at.close(), device.close()]));
  const seen = { streams: 0, ended: 0, closes: [] as [number, string][] };
  const admit: Admit = (hello) => {
    if (hello?.who !== "a" && hello?.who !== "b") return { refused: { line: { error: "nobody's" }, code: 1, reason: "refused", error: new Error("nobody's") } };
    const renewed = (line: any) => {
      if (line?.out) throw new Ending("not this member's any more", 3, "credential_refused");
      if (line?.told) throw new Ending("taken out", 4, "taken_out", { error: "taken out", code: "taken_out" });
      if (line?.who !== hello.who) throw new Error("another member's");
      return { ok: true, who: hello.who };
    };
    return {
      line: { ok: true, who: hello.who },
      renew: (line) => (line?.later ? Promise.resolve().then(() => renewed(line)) : renewed(line)),
      stream: () => {
        seen.streams++;
        return async (asked) => {
          await send(asked.stream, { status: 200, headers: {}, body: Buffer.from(`${hello.who} asked ${asked.head.path}`) });
          await asked.stream.finish();
        };
      },
      ended: () => void seen.ended++,
    };
  };
  const [conn, taken] = await Promise.all([device.connect({ id: at.id() }, ALPN), at.accept()]);
  const close = taken!.close.bind(taken);
  taken!.close = (code, reason) => {
    seen.closes.push([code, reason]);
    close(code, reason);
  };
  /// How serving it ended: null, or what it failed with.
  const served = door(taken!, admit).then(() => null, (e: unknown) => e);
  const first = await conn.openBi();
  const control = new Reader(first);
  /// A line on the control stream (the hello, then renewals) and what it is answered.
  const say = async (line: unknown) => {
    await writeLine(first, line);
    return control.line();
  };
  /// A request on a stream of its own: what it is answered.
  const ask = async (path: string) => {
    const stream = await conn.openBi();
    await writeLine(stream, { method: "GET", path });
    await stream.finish();
    const reader = new Reader(stream);
    return [(await reader.line()).status, (await reader.rest()).toString()];
  };
  return { conn, first, control, say, ask, seen, served };
}

/// How long after a refused hello's line the door closes its connection.
async function refusedHelloMs(t: TestContext) {
  const { say, seen, served } = await setUp(t);
  const timer = nextTimer();
  assert.deepEqual(await say({ who: "nobody" }), { error: "nobody's" });
  const armed = await timer;
  assert.deepEqual([timers.length, seen.closes], [1, []]);
  armed.fire();
  assert.deepEqual(seen.closes, [[1, "refused"]]);
  assert.equal(((await served) as Error).message, "nobody's");
  return armed.ms;
}

test("a renewal refused by an error is answered it, and the connection goes on as it was let in", async (t) => {
  const { conn, say, ask, seen } = await setUp(t);
  assert.deepEqual(await say({ who: "a" }), { ok: true, who: "a" });
  assert.deepEqual(await ask("/1"), [200, "a asked /1"]);
  assert.deepEqual(await say({ who: "a" }), { ok: true, who: "a" }, "a renewal let in");
  assert.deepEqual(await say({ who: "b" }), { error: "another member's" });
  assert.deepEqual(await say({ who: "a" }), { ok: true, who: "a" }, "the control stream is read on");
  assert.deepEqual(await ask("/2"), [200, "a asked /2"]);
  assert.deepEqual([timers.length, seen.closes, seen.ended, conn.isClosed()], [0, [], 0, false], "nothing armed, nothing closed");
});

test("a renewal refused with an Ending is answered, and the connection closed after it as a refused hello's is", async (t) => {
  const afterHello = await refusedHelloMs(t);
  const { conn, control, say, ask, seen, served } = await setUp(t);
  assert.deepEqual(await say({ who: "a" }), { ok: true, who: "a" });
  assert.deepEqual(await ask("/1"), [200, "a asked /1"]);
  const timer = nextTimer();
  assert.deepEqual(await say({ out: true }), { error: "not this member's any more" });
  const afterRenewal = await timer;
  // The same while, the connection open until then; no later line is read.
  assert.deepEqual([timers.length, afterRenewal.ms, seen.closes, conn.isClosed()], [1, afterHello, [], false]);
  assert.equal(await control.line(), null, "the control stream is finished");
  // A stream opened meanwhile is reset, what answers a request not asked for it.
  const late = await conn.openBi();
  await assert.rejects(late.read(), /stream reset/);
  assert.deepEqual([seen.streams, seen.ended], [1, 0]);
  afterRenewal.fire();
  assert.deepEqual(seen.closes, [[3, "credential_refused"]]);
  assert.equal(await conn.closed(), "credential_refused");
  // Serving it failed with the Ending, once what the admission started was stopped.
  const failed = await served;
  assert.ok(failed instanceof Ending);
  assert.deepEqual([failed.message, failed.code, failed.reason, seen.ended, seen.streams], ["not this member's any more", 3, "credential_refused", 1, 1]);
});

test("an Ending's own line is what the renewal is answered", async (t) => {
  const { conn, say, seen, served } = await setUp(t);
  assert.deepEqual(await say({ who: "b" }), { ok: true, who: "b" });
  const timer = nextTimer();
  assert.deepEqual(await say({ told: true }), { error: "taken out", code: "taken_out" });
  (await timer).fire();
  assert.deepEqual(seen.closes, [[4, "taken_out"]]);
  assert.equal(await conn.closed(), "taken_out");
  assert.ok((await served) instanceof Ending);
});

test("an Ending closes the connection though the other end takes in nothing of its control stream", async (t) => {
  const afterHello = await refusedHelloMs(t);
  // A stream holds 16 bytes unread, and a write to it waits from then on.
  const { conn, first, control, say, seen, served } = await setUp(t, 16);
  assert.deepEqual(await say({ who: "a" }), { ok: true, who: "a" });
  // A renewal whose answer is left unread: the next answer's write waits on this end.
  await writeLine(first, { who: "a" });
  const timer = nextTimer();
  await writeLine(first, { out: true });
  // The close is set as the renewal is refused, its line not written.
  const afterRenewal = await timer;
  assert.deepEqual([timers.length, afterRenewal.ms, seen.closes, conn.isClosed()], [1, afterHello, [], false]);
  afterRenewal.fire();
  assert.deepEqual(seen.closes, [[3, "credential_refused"]]);
  assert.ok((await served) instanceof Ending);
  assert.equal(seen.ended, 1);
  // All this end was ever sent: the first renewal's answer, the Ending's line never.
  assert.deepEqual(await control.line(), { ok: true, who: "a" });
  assert.equal(await control.line(), null);
});

test("a renewal answered by a promise is answered what it gives, refused as it fails, and ended by an Ending it fails with", async (t) => {
  const afterHello = await refusedHelloMs(t);
  const { conn, control, say, ask, seen, served } = await setUp(t);
  assert.deepEqual(await say({ who: "a" }), { ok: true, who: "a" });
  assert.deepEqual(await say({ who: "a", later: true }), { ok: true, who: "a" });
  assert.deepEqual(await say({ who: "b", later: true }), { error: "another member's" });
  assert.deepEqual(await ask("/1"), [200, "a asked /1"]);
  assert.deepEqual([timers.length, seen.closes, conn.isClosed()], [0, [], false], "nothing armed, nothing closed");
  const timer = nextTimer();
  assert.deepEqual(await say({ out: true, later: true }), { error: "not this member's any more" });
  const afterRenewal = await timer;
  assert.deepEqual([timers.length, afterRenewal.ms, seen.closes], [1, afterHello, []]);
  assert.equal(await control.line(), null, "the control stream is finished");
  afterRenewal.fire();
  assert.deepEqual(seen.closes, [[3, "credential_refused"]]);
  assert.ok((await served) instanceof Ending);
});
