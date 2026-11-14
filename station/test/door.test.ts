// The door (src/mesh/door.ts) with an admission that is not the station's: what a later line on the control stream
// (a renewal) does to the connection. One its admission refuses by any error is answered why and closes nothing (the
// station's every refusal: test/renewal-role.test.ts); one it refuses with an `Ending` is answered, and the connection
// closed a while after, as the door closes a refused hello's, nothing more served on it meanwhile: whether or not
// the other end takes the answer in, and from a renewal answered later (a promise) as from one answered at once.
// And a refused hello served as the station serves it, through accept() (src/mesh/accept.ts): its connection is the
// door's to close, with the refusal's code and reason, and serving it fails only then. Those wait for nothing that may
// never come: what the door is to have done is looked at once all the hello set going is done (hub-fakes.ts `settle`,
// `given`), so a door that does not do it fails them there.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mock, test, type TestContext } from "node:test";
import { Effect, Fiber } from "effect";
import { accept } from "../src/mesh/accept.ts";
import { type Admit, Ending, door } from "../src/mesh/door.ts";
import { hearLines } from "../src/ops/log.ts";
import { Reader, send, writeLine } from "../src/mesh/wire.ts";
import { wall } from "../src/ops/fibers.ts";
import { given, settle } from "./hub-fakes.ts";
import { memoryMesh } from "./memory-mesh.ts";

const ALPN = Buffer.from("door-test/1");
/// How long after a refusal the door closes its connection (door.ts REFUSED_CLOSE_MS, which it gives nobody).
const CLOSE_MS = 200;

// The machine's timers are the test's: all the door arms is a refusal's close.
// (`off`: whether it was called off, which `calledOff` is told as it is.)
type Timer = { ms: number; fire: () => void; off: boolean };
const timers: Timer[] = [];
let armed: ((timer: Timer) => void) | null = null;
let calledOff: (() => void) | null = null;
mock.method(wall, "after", (ms: number, fire: () => void) => {
  const timer: Timer = { ms, fire, off: false };
  timers.push(timer);
  armed?.(timer);
  armed = null;
  return () => {
    timer.off = true;
    calledOff?.();
  };
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
  const admit = admission(seen);
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

/// Who that server lets in, and what it counts of those it did. One it refuses is answered a line as long as its
/// hello asks (`long`: that many bytes more).
function admission(seen: { streams: number; ended: number }): Admit {
  return (hello) => {
    if (hello?.who !== "a" && hello?.who !== "b") {
      const line = { error: "nobody's", ...(hello?.long > 0 ? { long: "x".repeat(hello.long) } : {}) };
      return { refused: { line, code: 1, reason: "refused", error: new Error("nobody's") } };
    }
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
}

/// That server with its connections taken by accept(), as the station takes its own, and a device connected to it that
/// has not said hello yet. `trace`: every close of the connection the server calls, what the log says of the mesh and
/// a timer called off, in order. `way`, how what the server writes on a stream goes: as it is written; "deaf", never
/// (the other end takes in nothing); "slow", written at once (as QUIC's write is, once the bytes are in its buffer)
/// and on its way only from `carry()` on, what has not gone as the server closes the connection lost with it (as
/// QUIC's close leaves what is outstanding). "unheard": the connection's end cannot be waited for (`closed()` fails).
async function setUpTaken(t: TestContext, way: "" | "deaf" | "slow" | "unheard" = "") {
  timers.length = 0;
  const trace: string[] = [];
  hearLines((l) => void (l.at === "mesh" && trace.push(`said: ${l.message} ${JSON.stringify(l.fields)}`)));
  calledOff = () => void trace.push("timer off");
  t.after(() => {
    hearLines(null);
    calledOff = null;
  });
  const mesh = memoryMesh();
  const bind = () => mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [], discovery: false });
  const [at, device] = await Promise.all([bind(), bind()]);
  const seen = { streams: 0, ended: 0 };
  const admit = admission(seen);
  /// A slow way's: what is written and has not gone, in order; and whether it goes as it is written by now.
  const held: (() => Promise<void>)[] = [];
  let carried = false;
  const carry = () => {
    carried = true;
    for (const go of held.splice(0)) void go().catch(() => {});
  };
  const running = Effect.runFork(Effect.scoped(accept(at, {
    arrived: (taken) => {
      const close = taken.close.bind(taken);
      taken.close = (code, reason) => {
        trace.push(`close ${code} ${reason}`);
        held.length = 0;
        close(code, reason);
      };
      if (way === "unheard") taken.closed = () => Promise.reject(new Error("no word of its end"));
      if (way !== "deaf" && way !== "slow") return;
      const acceptBi = taken.acceptBi.bind(taken);
      taken.acceptBi = async () => {
        const stream = await acceptBi();
        if (stream === null) return null;
        if (way === "deaf") stream.write = () => new Promise<void>(() => {});
        else {
          const [write, finish] = [stream.write.bind(stream), stream.finish.bind(stream)];
          // (In pieces, as packets carry it.)
          const pieces = (bytes: Buffer) => Array.from({ length: Math.ceil(bytes.length / 16384) }, (_, i) => () => write(bytes.subarray(i * 16384, (i + 1) * 16384)));
          const goes = async (how: (() => Promise<void>)[]) => {
            if (!carried) held.push(...how);
            else for (const go of how) await go();
          };
          stream.write = (bytes) => goes(pieces(bytes));
          stream.finish = () => goes([finish]);
        }
        return stream;
      };
    },
    serve: (taken) => door(taken, admit),
    closing: "station stopping",
  })));
  let stopped = false;
  const stop = () => (stopped ? Promise.resolve() : ((stopped = true), Effect.runPromise(Fiber.interrupt(running)).then(() => {})));
  t.after(async () => {
    await stop();
    await Promise.all([at.close(), device.close()]);
  });
  const conn = await device.connect({ id: at.id() }, ALPN);
  const first = await conn.openBi();
  const control = new Reader(first, 1 << 20);
  /// The hello said, and all it sets going done: the one timer the door armed as it refused it.
  const refused = async (hello: unknown) => {
    await writeLine(first, hello);
    await settle();
    assert.deepEqual(timers.map((timer) => timer.ms), [CLOSE_MS], "the door sets its close as it refuses the hello");
    return timers[0]!;
  };
  /// The next line of the control stream (null: its end), which is there by now.
  const line = () => given(control.line(), "the control stream's next line, or its end");
  /// What the connection was closed with, which it is by now.
  const closed = () => given(conn.closed(), "the connection closed");
  return { conn, line, closed, refused, carry, seen, trace, stop };
}

/// How long after a refused hello's line the door closes its connection.
async function refusedHelloMs(t: TestContext) {
  const { say, seen, served } = await setUp(t);
  const timer = nextTimer();
  assert.deepEqual(await say({ who: "nobody" }), { error: "nobody's" });
  const armed = await timer;
  assert.deepEqual([timers.length, armed.ms, seen.closes], [1, CLOSE_MS, []]);
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

const ENDED = 'said: connection ended {"error":"Error: nobody\'s"}';

test("a refused hello served through accept is closed by the door, with the refusal's code and reason, and said once", async (t) => {
  const { conn, line, closed, refused, seen, trace } = await setUpTaken(t);
  const armed = await refused({ who: "nobody" });
  assert.deepEqual(await line(), { error: "nobody's" });
  assert.equal(await line(), null, "the control stream is finished");
  // Its line gone and all that set going done, it is kept: not closed as serving it would fail, nothing said of it.
  assert.deepEqual([armed.off, trace, conn.isClosed()], [false, [], false]);
  // What it asks meanwhile is not answered: no stream of it is taken.
  const asked = await conn.openBi();
  await writeLine(asked, { method: "GET", path: "/1" });
  await asked.finish();
  armed.fire();
  await settle();
  // The door's close first, which is the one the other end sees; then serving it failed, which is said, and what
  // accept does of a connection served no more finds it closed.
  assert.deepEqual(trace, ["close 1 refused", "timer off", ENDED, "close 0 station stopping"]);
  assert.equal(await closed(), "refused");
  await assert.rejects(asked.read(), /connection lost/);
  assert.deepEqual(seen, { streams: 0, ended: 0 });
});

test("a refused hello's line arrives whole, a long one on a slow way too: its connection is kept under it", async (t) => {
  const { conn, line, closed, refused, carry, trace } = await setUpTaken(t, "slow");
  const long = 262144;
  const armed = await refused({ who: "nobody", long });
  // Written, and none of it gone yet: a close now would lose it, and none is made.
  assert.deepEqual([armed.off, trace, conn.isClosed()], [false, [], false]);
  carry();
  const told = await line();
  assert.deepEqual([told.error, told.long.length], ["nobody's", long]);
  assert.equal(await line(), null, "the control stream is finished");
  assert.deepEqual([armed.off, trace, conn.isClosed()], [false, [], false]);
  armed.fire();
  await settle();
  assert.deepEqual(trace, ["close 1 refused", "timer off", ENDED, "close 0 station stopping"]);
  assert.equal(await closed(), "refused");
});

test("a refused hello's connection is closed as late though the other end takes in nothing of it", async (t) => {
  const { conn, closed, refused, trace } = await setUpTaken(t, "deaf");
  // The close is set as the hello is refused, its line never written.
  const armed = await refused({ who: "nobody" });
  assert.deepEqual([armed.off, trace, conn.isClosed()], [false, [], false]);
  armed.fire();
  await settle();
  assert.deepEqual(trace, ["close 1 refused", "timer off", ENDED, "close 0 station stopping"]);
  assert.equal(await closed(), "refused");
});

test("a refused hello's connection goes at once as the other end closes it, or as the server stops", async (t) => {
  // The other end, its line read, closes it (as a device does): serving it fails then, the door's close called off.
  const read = await setUpTaken(t);
  await read.refused({ who: "nobody" });
  assert.deepEqual(await read.line(), { error: "nobody's" });
  read.conn.close(0, "credential refused");
  await settle();
  assert.deepEqual(read.trace, ["timer off", ENDED, "close 0 station stopping"]);
  // The server stops: closed by that, at once and with its reason, and the door's close called off.
  const stopping = await setUpTaken(t);
  await stopping.refused({ who: "nobody" });
  await stopping.stop();
  assert.equal(await stopping.closed(), "station stopping");
  await settle();
  assert.deepEqual(stopping.trace, ["close 0 station stopping", "timer off"]);
});

test("a refused hello's serving fails with the refusal though its connection's end cannot be waited for", async (t) => {
  const { refused, trace } = await setUpTaken(t, "unheard");
  // No word of how it ended: the door's close is called off and serving it fails as refused, not with that, so the
  // loop closes it.
  const armed = await refused({ who: "nobody" });
  assert.deepEqual([armed.off, trace], [true, ["timer off", ENDED, "close 0 station stopping"]]);
});
