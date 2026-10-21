// The core's timers and clocks in an mbui app: the engine's (real time) on a device, the app's own in a run on a clock
// of its own (a settled screenshot run on macOS, Android's own_clock, Windows's: what a frame shows does not hang on
// how fast the machine is, so neither does what the core does when). Imported before anything of the core, so
// hermes-globals.ts finds setTimeout here and the core's `__native.monotonic`/`now` are these.
//
// The app turns it to its clock with `{"clock": ms}` (the app's clock now), sent where it would have woken the core:
// the timers due by then are run, in the order they are due, with what each sets due by then too; once what they
// started has run (microtasks, and what is due at once), the app is told `{"clocked": ms, "next": due | null, "later":
// due | null}` on its clock: the next one due that what is shown waits for (a retry, a request's time running out),
// and the next one it does not (setInterval's, the core's laterSleep: a keepalive, a shown clock's next second). It is
// told so again whenever either changes (a call that set a timeout, one cleared), with no `clock` asked. Timers set
// before the first `clock` (the core's start) go over to the app's clock with what they had left. Until then, and on
// a device always, every timer is the engine's.
import type { HermesNative } from "@core/hosts/hermes-globals.ts";

// deno-lint-ignore no-explicit-any
const g = globalThis as any;
const engine = g.__native as HermesNative;

type Timer = { id: number; due: number; seq: number; later: boolean; run: () => void };

/// The timers by id: on the engine's clock (`monotonic`) until the app's is taken, then on the app's.
const timers = new Map<number, Timer>();
let nextId = 1;
let seq = 0;
/// The app's clock (ms) as its last `clock` said; null while the engine's is used.
let own: number | null = null;
/// The client the app's `clock` came from: where `clocked` goes.
let clockedTo = 0;
/// An engine timer of this file's own (the step after a task that set or ran timers on the app's clock): no core
/// timer's id.
const STEP = 2 ** 52;
let stepping = false;
/// A `clock` not answered yet.
let owed = false;
/// What the app was last told (empty: never told).
let told = "";

/// What the engine's loop calls as one of its timers is due; hermes-globals.ts's own (put after this, for its timers,
/// which are these) passed over.
const fire = (id: number) => {
  if (id === STEP) return step();
  const t = timers.get(id);
  if (!t) return;
  timers.delete(id);
  t.run();
};
Object.defineProperty(g, "__stillfail_timer", { get: () => fire, set: () => {}, configurable: true });

function set(run: () => void, ms: number, later = false): number {
  const id = nextId++;
  const wait = Math.max(0, Number(ms) || 0);
  // (the core's laterSleep says which, just before it sets it)
  if (g.__stillfail_later === ms) later = true;
  g.__stillfail_later = undefined;
  timers.set(id, { id, due: (own ?? engine.monotonic()) + wait, seq: ++seq, later, run });
  if (own === null) engine.setTimer(id, wait);
  else soon();
  return id;
}

function clear(id: number): void {
  if (!timers.delete(id)) return;
  if (own === null) engine.clearTimer(id);
  else soon();
}

g.setTimeout = (fn: (...a: unknown[]) => void, ms?: number, ...args: unknown[]) => set(() => fn(...args), ms ?? 0);
g.clearTimeout = (id: number) => clear(id);
g.setInterval = (fn: (...a: unknown[]) => void, ms?: number, ...args: unknown[]) => {
  const every = Math.max(0, Number(ms) || 0);
  let id = 0;
  const tick = () => {
    // the same id again, due `every` on
    timers.set(id, { id, due: (own ?? engine.monotonic()) + every, seq: ++seq, later: true, run: tick });
    if (own === null) engine.setTimer(id, every);
    else soon();
    fn(...args);
  };
  id = set(tick, every, true);
  return id;
};
g.clearInterval = g.clearTimeout;

/// The first due, by when and then by when it was set (of those `later` or not, when it says).
function first(later?: boolean): Timer | null {
  let f: Timer | null = null;
  for (const t of timers.values()) {
    if (later !== undefined && t.later !== later) continue;
    if (f === null || t.due < f.due || (t.due === f.due && t.seq < f.seq)) f = t;
  }
  return f;
}

/// Runs what is due on the app's clock, one at a time (each set while running may be due too).
function runDue(): boolean {
  let ran = false;
  for (;;) {
    const t = first();
    if (t === null || own === null || t.due > own) return ran;
    timers.delete(t.id);
    ran = true;
    t.run();
  }
}

/// A step once this task's microtasks are drained (the engine runs a timer after them).
function soon(): void {
  if (stepping) return;
  stepping = true;
  engine.setTimer(STEP, 0);
}

/// After a task that ran or set timers on the app's clock has run: what is due at once run too, and again, until
/// nothing is; then the app told when the next one is, when it asked (`clock`) or that changed.
function step(): void {
  stepping = false;
  if (runDue()) return soon();
  const next = first(false)?.due ?? null;
  const later = first(true)?.due ?? null;
  const said = JSON.stringify([next, later]);
  if (!owed && said === told) return;
  owed = false;
  told = said;
  engine.emit(clockedTo, JSON.stringify({ clocked: own, next, later }));
}

/// The app's clock is now `ms`: its first `clock` takes every timer over to it.
function clockTo(client: number, ms: number): void {
  clockedTo = client;
  if (own === null) {
    const now = engine.monotonic();
    for (const t of timers.values()) {
      engine.clearTimer(t.id);
      t.due = ms + Math.max(0, t.due - now);
    }
  }
  own = Math.max(own ?? ms, ms);
  owed = true;
  runDue();
  soon();
}

/// The time of day on the app's clock: the day its hosts start a run on its own clock from (mac_app.m's
/// mb_host_wall_ms, android_host.c's), on with it.
const OWN_DAY = 1790000000000;

g.__native = {
  ...engine,
  monotonic: () => own ?? engine.monotonic(),
  now: () => (own === null ? engine.now() : OWN_DAY + own),
};

/// The core's way in, with the app's `clock` taken here (after hosts/engine.ts has put it: call once the core's entry
/// has run).
export function takeClock(): void {
  const core = g.__stillfail;
  const receive = core.receive as (client: number, json: string) => void;
  core.receive = (client: number, json: string) => {
    if (json.startsWith('{"clock":')) {
      const said = JSON.parse(json) as { clock: number };
      if (typeof said.clock === "number") return clockTo(client, said.clock);
    }
    receive(client, json);
  };
}
