// Approving a new device face to face (views/pair.ts) over a line that fails, tested by its properties: each seed draws
// how the connection between the new device and the trusted one behaves (each message held a while, the connection
// cut after some message or never) and what the people do (the code typed right, wrong or half, turned away or the
// prompt closed on the trusted device, time going by), and the real cores on both ends run it on the test clock. What
// must hold whatever happened: the trusted device signs the new one in only when its code was typed in time, not
// turned away, within PAIR_TRIES; every code typed is answered; once the code's time is over the new device's page is
// done or says why it is not, in words that fit what happened (turned away only if it was, out of tries only if they
// were used, too old only once it was, unreachable only if the line went); no prompt stays on the trusted device. A
// failure says its seed: PAIR_FAULT_SEED=<seed> runs only that one (PAIR_FAULT_RUNS=<n> runs n seeds from 1).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Queue } from "effect";
import { CoreError } from "../src/error.ts";
import { t } from "../src/i18n.ts";
import { PAIR_TRIES } from "../src/pair.ts";
import { pairs } from "../src/views/lock.ts";
import { type Duplex, keep, PAIR_GRACE_MS, PAIR_WAIT_MS, serveTrusted, trying } from "../src/views/pair.ts";
import { ME, PHONE, genesis, grant, rig } from "./lock-rig.ts";

/// A seeded random (mulberry32): the same seed, the same draws.
function rng(seed: number) {
  let s = seed >>> 0;
  const next = () => {
    let x = (s += 0x6d2b79f5);
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
  return { next, int: (n: number) => Math.floor(next() * n) };
}

type Act = { kind: "right" | "wrong" | "half" | "deny" | "hide" | "wait"; ms: number };

/// What a seed draws: each message's delay (ms), after how many messages the connection is cut (none: never), what the
/// people do, in order.
function draw(seed: number) {
  const r = rng(seed);
  const delays = Array.from({ length: 16 }, () => [0, 0, 20, 300, 2_000, 6_000][r.int(6)]!);
  const cutAfter = r.int(3) === 0 ? 1 + r.int(10) : null;
  const kinds: Act["kind"][] = ["right", "wrong", "wrong", "half", "deny", "hide", "wait", "wait", "wait"];
  const acts = Array.from({ length: 1 + r.int(7) }, (): Act => ({ kind: kinds[r.int(kinds.length)]!, ms: [1_000, 30_000, 90_000, 4 * 60_000][r.int(4)]! }));
  return { delays, cutAfter, acts };
}

/// Two ends of a connection on the core's clock: the n-th message (both ways counted) arrives `delays[n]` ms after it is
/// sent, each way in order; after `cutAfter` messages the connection is cut (each end hears its end, sending fails).
function line(fork: (e: Effect.Effect<void>) => void, delays: number[], cutAfter: number | null): { ends: [Duplex, Duplex]; cut: () => boolean } {
  const a = Effect.runSync(Queue.unbounded<unknown>());
  const b = Effect.runSync(Queue.unbounded<unknown>());
  let sent = 0;
  let cut = false;
  // When the last message each way arrives: a later one never overtakes it.
  const last = new Map<unknown, Promise<void>>();
  const cutNow = () => {
    if (cut) return;
    cut = true;
    Queue.offerUnsafe(a, null);
    Queue.offerUnsafe(b, null);
  };
  const end = (mine: Queue.Queue<unknown>, theirs: Queue.Queue<unknown>): Duplex => ({
    send: (m) =>
      Effect.suspend(() => {
        if (cut) return Effect.fail(new CoreError("pair", "the connection was cut"));
        const n = sent++;
        const copy = JSON.parse(JSON.stringify(m));
        const before = last.get(theirs) ?? Promise.resolve();
        const arrived = new Promise<void>((done) =>
          fork(Effect.andThen(Effect.sleep(delays[n % delays.length]!), Effect.promise(() => before)).pipe(Effect.andThen(Effect.sync(() => {
            if (!cut) Queue.offerUnsafe(theirs, copy);
            if (cutAfter !== null && n + 1 >= cutAfter) cutNow();
            done();
          })))),
        );
        last.set(theirs, arrived);
        return Effect.void;
      }),
    next: () => Queue.take(mine) as Effect.Effect<any>,
    close: () => void Queue.offerUnsafe(theirs, null),
  });
  return { ends: [end(a, b), end(b, a)], cut: () => cut };
}

const TEXTS = {
  denied: t("core-misc.lock.pairDenied"),
  tries: t("core-misc.lock.pairTries"),
  late: t("core-misc.lock.pairLate"),
  gone: t("core-misc.lock.pairGone"),
};

async function once(seed: number): Promise<string[]> {
  const { delays, cutAfter, acts } = draw(seed);
  const said: string[] = [`delays ${delays.join(",")}; cut after ${cutAfter ?? "never"}`];
  const g = grant();
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], g.keys, ME) }));
  await r.watch({ topic: "lock", workspace: "ws" });
  const prompts = await r.watch({ topic: "lockPrompts" });
  const inner = r.core.inner;
  const { ends: [trusted, phone], cut } = line((e) => void inner.runner.fork(e), delays, cutAfter);
  inner.runner.fork(Effect.ignore(serveTrusted(inner, PHONE, ME, trusted)));
  const start = r.host.nowMs();

  // The new device's hello and the trusted device's answer, as `dial` has them; then kept, as `begin` keeps it.
  const answer: unknown[] = [];
  inner.runner.fork(Effect.ignore(Effect.andThen(phone.send({ t: "hello", v: 1, workspaces: [{ ws: "ws", credential: g.credential("ws", PHONE, "s2") }], kind: "app", label: "Pixel 8", sign_key: "ed25519:" + "11".repeat(32) }), Effect.map(phone.next(), (m) => answer.push(m)))));
  for (let i = 0; i < 300 && answer.length === 0; i++) await r.host.time.pass(100);
  const code: string | undefined = (await prompts()).pairing[0]?.code;
  const y = trying(inner, ["ws"]);
  const met = (answer[0] as { t?: string } | undefined)?.t === "code";
  if (met) keep(inner, y, ME, phone, ["ws"]);
  said.push(met ? `shown ${code}` : `no code: ${JSON.stringify(answer[0] ?? null)}`);
  // The new device's own key from here (the pairing session is its base key and the trusted one's).
  inner.mesh = () => Effect.succeed({ deviceId: () => PHONE } as never);

  // What happened, for what the end may say.
  let denied = false;
  let wrongs = 0;
  // The right code typed before the code's time was over (its messages' delays aside), and well before it.
  let goodTyped: number | null = null;
  let surelyGood = false;
  for (const act of acts) {
    const at = r.host.nowMs() - start;
    if (act.kind === "deny") {
      denied = true;
      await r.ask("lockPrompt.deny", { device: PHONE });
    } else if (act.kind === "hide") await r.ask("lockPrompt.hide", { device: PHONE });
    else if (act.kind === "wait") await r.host.time.pass(act.ms, 500);
    else {
      const typed = act.kind === "right" ? (code ?? "000000") : act.kind === "half" ? "123" : code === "222222" ? "333333" : "222222";
      let got: string;
      try {
        await r.ask("lock.pairCode", { workspace: "ws", code: typed });
        got = "approved";
      } catch (e) {
        got = (e as { code?: string }).code ?? (e as Error).message;
        // Every code typed is answered (the rig's `ask` gives up after 40 s on the clock).
        assert.notEqual((e as Error).message, "lock.pairCode: no answer", `seed ${seed}: a code typed got no answer\n${said.join("\n")}`);
      }
      if (act.kind === "wrong") wrongs++;
      if (act.kind === "right" && goodTyped === null && !denied && wrongs < PAIR_TRIES && at < PAIR_WAIT_MS + 60_000) goodTyped = at;
      if (act.kind === "right" && !denied && wrongs < PAIR_TRIES && at < PAIR_WAIT_MS - 60_000) surelyGood = true;
      said.push(`  typed ${act.kind} at ${Math.round(at / 1000)} s: ${got}`);
      continue;
    }
    said.push(`  ${act.kind}${act.kind === "wait" ? ` ${act.ms / 1000} s` : ""} at ${Math.round(at / 1000)} s`);
  }
  // The code's time over, and the new device's grace past it.
  await r.host.time.pass(PAIR_WAIT_MS + PAIR_GRACE_MS + 60_000, 500);
  const posted = r.cloud.posted.filter((p) => p.ws === "ws" && p.kind === "device" && p.id === PHONE).length;
  const end = pairs.mine(inner, "ws") as { state: string; error?: string } | null;
  const shown = (await prompts()).pairing;
  said.push(`end: ${JSON.stringify(end)}; signed ${posted}; ${cut() ? "cut" : "not cut"}; prompts ${shown.length}`);
  const why = `seed ${seed}:\n${said.join("\n")}`;

  // Signed in once at most, and only for the code typed in time, not turned away, within its tries.
  assert.ok(posted <= 1, `signed in twice; ${why}`);
  if (posted === 1) assert.notEqual(goodTyped, null, `signed in without the code typed in time; ${why}`);
  // The right code typed in time, not turned away, within its tries, over a line never cut: signed in.
  if (met && surelyGood && !cut()) assert.equal(posted, 1, `the right code typed in time, yet not signed in; ${why}`);
  // Done only when signed in; signed in with nothing cut, done.
  if (end?.state === "done") assert.equal(posted, 1, `done but not signed in; ${why}`);
  if (posted === 1 && !cut()) assert.equal(end?.state, "done", `signed in but the new device not done; ${why}`);
  // Over: done, or said why it is not, in words that fit.
  if (met) {
    assert.ok(end !== null && ["done", "failed"].includes(end.state), `still ${end?.state} once the code's time is over; ${why}`);
    if (end!.state === "failed") {
      const fits = [denied && TEXTS.denied, wrongs >= PAIR_TRIES && TEXTS.tries, TEXTS.late, cut() && TEXTS.gone].filter(Boolean);
      assert.ok(fits.includes(end!.error!), `says “${end!.error}”, which is not what happened; ${why}`);
    }
  }
  // Nothing left up on the trusted device.
  assert.deepEqual(shown, [], `a prompt stays on the trusted device; ${why}`);
  return said;
}

const RUNS = Number(process.env.PAIR_FAULT_RUNS ?? 40);
const seeds = process.env.PAIR_FAULT_SEED ? [Number(process.env.PAIR_FAULT_SEED)] : Array.from({ length: RUNS }, (_, i) => i + 1);

test("a new device approved face to face over a line that fails: signed in only for the code typed in time, and always said how it went", async () => {
  for (const seed of seeds) {
    const said = await once(seed);
    if (process.env.PAIR_FAULT_TRACE) console.error(`seed ${seed}: ${said.join(" | ")}`);
  }
});
