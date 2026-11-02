// Approving a new device face to face (docs/workspace-lock.md 新设备; the exchange is src/pair.ts), both ends, with no
// cloud between them: the new device dials its person's trusted devices straight (iroh, PAIR_ALPN, the ids its lock
// names), each that answers shows a fresh code, and the code typed on the new device lets the one showing it sign it in.
//
// A trusted device (an app whose key the lock names): takes the connection on its main endpoint (mesh.ts `takes`),
// checks what it is asked (each workspace's member credential, with the cloud keys of the lock as checked here; that
// this device approves there, for that person), shows the code (`lockPrompts` `pairing`, wherever the person is) and
// signs a `device` entry in each of those workspaces once the new device proves it typed it; turned away (`lockPrompt.
// deny`), after PAIR_TRIES wrong codes, or PAIR_WAIT_MS after it showed the code (wrong ones do not put it off), it signs
// nothing. Its prompt closed (`lockPrompt.hide`), it is no longer shown and the code still holds: a person closes it
// once they have read the code.
//
// A new device (`lock.pair`, its waiting page): dials them all, and once one or more show a code, proves the code typed
// (`lock.pairCode`) to each; the one whose code it was approves it. `me.pair` says how far it got. A trusted device that
// ends it while nothing is typed (turned away, the code too old, gone) is heard at once, not once a code is typed: the
// page says why and asks again (2026-10-30: the boxes stayed after the code was gone).
//
// The wire, a line of JSON each way at a time on one stream: new → `hello {workspaces: [{ws, credential}], kind, label,
// sign_key}`; trusted → `code {workspaces}` (the ones it approves) or `no {error}`; new → `pake {y}`; trusted → `pake
// {y, mac}`; new → `confirm {mac}` when the trusted one's MAC is right, else `wrong`; trusted → `approved {workspaces,
// failed}`, or `wrong {left}` / `no`. A `no` says why: `tries` (out of them), `denied` (turned away there), `late` (the
// code too old), `bad_share`; a trusted device from before `late` closes the stream then with no word. An `approved`
// that signed it in nowhere (each workspace in `failed`, with why) is no approval: the new device says why.
import { ed25519 } from "@noble/curves/ed25519.js";
import { Deferred, Effect, Queue } from "effect";
import type { Inner } from "../core.ts";
import { hooks } from "../core/execute.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import type { IrohConnection, IrohStream } from "../iroh.ts";
import { Signer, WEB_DEVICE_SECS } from "../lock.ts";
import { Lines } from "../mesh.ts";
import { PAIR_ALPN, PAIR_TRIES, pairCode, pairSession, pakeKeys, pakeStart, sameMac, typedCode } from "../pair.ts";
import * as format from "../format.ts";
import * as prefs from "../prefs.ts";
import { get, hex, isObject, parseJson, utf8 } from "../util.ts";
import { fromB64url } from "../vault/crypto.ts";
import { checkLock } from "../vault/lock-check.ts";
import { Lock, baseOf, deviceText, fold, held, nameOf, pairs, read, signerKnown, signerOf, view } from "./lock.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => (Array.isArray(v) ? v : []);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const unhex = (h: string) => (/^([0-9a-f]{2})*$/.test(h) ? Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16)) : new Uint8Array());

/// How long a code waits to be typed, on the trusted device.
export const PAIR_WAIT_MS = 5 * 60_000;
/// How long the new device waits past PAIR_WAIT_MS before it takes a code for gone though its trusted device said
/// nothing (the connection lost without a word, an app put away).
export const PAIR_GRACE_MS = 10_000;
/// How long the new device tries to reach each trusted one.
export const PAIR_DIAL_MS = 20_000;
/// Who signs member credentials, and what kind they are (station/src/cloud/provider.ts STILLFAIL `credential`).
const ISSUERS = ["stillfail-cloud", "ember-cloud"];
const TYPES = ["stillfail-member+jwt", "ember-member+jwt"];

/// One way of a line of JSON at a time, on a stream.
export type Duplex = { send(message: J): Effect.Effect<void, CoreError>; next(): Effect.Effect<J | null, CoreError>; close(): void };

export function streamDuplex(stream: IrohStream, close: () => void): Duplex {
  const lines = new Lines(stream);
  return {
    send: (m) => Effect.mapError(stream.write(utf8(`${JSON.stringify(m)}\n`)), (e) => new CoreError("pair", e.message)),
    next: () => Effect.map(lines.next(), (l) => (l === null ? null : (parseJson(l) ?? null))),
    close,
  };
}

/// A member credential's word on who the device is, checked against the lock's keys (station/src/mesh/credential.ts).
export function credentialOf(token: string, keys: unknown, ws: string, device: string, now: number): { sub: string; email: string; name: string } | null {
  try {
    const [head, body, sig] = token.split(".");
    if (!head || !body || !sig) return null;
    const header = JSON.parse(new TextDecoder().decode(fromB64url(head) ?? new Uint8Array()));
    if (header?.alg !== "EdDSA" || !TYPES.includes(header?.typ)) return null;
    const jwk = arr(get(keys, "keys")).find((k) => header.kid === undefined || k?.kid === header.kid);
    const x = typeof jwk?.x === "string" ? fromB64url(jwk.x) : null;
    const s = fromB64url(sig);
    if (x === null || s === null || !ed25519.verify(s, utf8(`${head}.${body}`), x)) return null;
    const c = JSON.parse(new TextDecoder().decode(fromB64url(body) ?? new Uint8Array()));
    if (!ISSUERS.includes(c?.iss) || c?.ws !== ws || c?.device !== device || !(Number.isInteger(c?.exp) && c.exp > now)) return null;
    return { sub: String(c.sub ?? ""), email: String(c.email ?? ""), name: String(c.name ?? "") };
  } catch {
    return null;
  }
}

// ── the trusted device ──

/// A new device showing this one's code: who, where it asks, the code, how to turn it away.
/// `hidden`: its prompt closed here, the code still good. `until`: when the code is too old (ms).
type Asking = { device: string; name: string; email: string; kind: "app" | "web"; label: string; signKey: string | null; code: string; at: number; until: number; places: { ws: string; sub: string; account: string }[]; hidden: boolean; away: Deferred.Deferred<void> };

const askings = new WeakMap<Inner, Map<string, Asking>>();
const askingsOf = (inner: Inner) => {
  let m = askings.get(inner);
  if (!m) askings.set(inner, (m = new Map()));
  return m;
};
const told = (inner: Inner) => inner.store.invalidate({ topic: "lockPrompts" });

/// A new device's connection, as the mesh's endpoint took it: its one stream served, then closed.
export function served(inner: Inner, connection: IrohConnection): void {
  inner.runner.fork(
    Effect.ignore(
      Effect.ensuring(
        Effect.gen(function* () {
          const stream = yield* connection.acceptBi();
          const me = inner.meshNow()?.deviceId() ?? baseOf(inner);
          if (stream === null || me === null) return;
          yield* serveTrusted(inner, connection.remoteId(), me, streamDuplex(stream, () => connection.close(0, "done")));
        }),
        Effect.sync(() => connection.close(0, "done")),
      ),
      { log: "Unhandled", message: "pairing served" },
    ),
  );
}

/// The workspaces of `hello` this device approves the new one (`peer`) in, as it sees itself (`me`, its base key).
function placesFor(inner: Inner, hello: J, peer: string, me: string): { places: Asking["places"]; who: { sub: string; email: string; name: string } | null } {
  const signer = signerOf(inner);
  const now = Math.floor(inner.host.nowMs() / 1000);
  const places: Asking["places"] = [];
  let who: { sub: string; email: string; name: string } | null = null;
  if (signer === null || !inner.host.appKeys) return { places, who };
  for (const w of arr(get(hello, "workspaces"))) {
    const ws = str(get(w, "ws")) ?? "";
    const account = inner.workspaces.owner(ws);
    const h = held(inner, ws);
    if (account === null || !h?.head) continue;
    let lock;
    try {
      lock = checkLock(h.entries, now);
    } catch {
      continue;
    }
    const mine = lock.devices.get(me);
    // One in the lock already: only an app that does not sign with the key it brings (let in before it kept one) is
    // approved again, as one that signs, and as its own person's.
    const had = lock.devices.get(peer);
    const key = str(get(hello, "sign_key"));
    const upgrade = had !== undefined && had.kind === "app" && get(hello, "kind") === "app" && key !== null && had.sign_key !== key;
    if (lock.disabled || mine?.sign_key !== signer || (had !== undefined && !upgrade)) continue;
    const c = credentialOf(str(get(w, "credential")) ?? "", lock.cloudKeys, ws, peer, now);
    if (c === null || !lock.members.has(c.sub) || (had !== undefined && c.sub !== had.sub)) continue;
    const role = lock.members.get(mine.sub);
    if (role !== "owner" && role !== "admin" && c.sub !== mine.sub) continue;
    who ??= c;
    if (c.sub !== who.sub) continue;
    places.push({ ws, sub: c.sub, account });
  }
  return { places, who };
}

/// One new device, met: what it asks checked, its code shown until it is typed, turned away, or too late.
export function serveTrusted(inner: Inner, peer: string, me: string, d: Duplex): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const hello = yield* Effect.timeoutOption(d.next(), "30 seconds");
    if (hello._tag === "None" || !isObject(hello.value) || hello.value.t !== "hello") return;
    const { places, who } = placesFor(inner, hello.value, peer, me);
    if (places.length === 0 || who === null) return yield* d.send({ t: "no", error: "not_here" });
    const all = askingsOf(inner);
    const before = all.get(peer);
    if (before) Deferred.doneUnsafe(before.away, Effect.void);
    const kind = get(hello.value, "kind") === "app" ? "app" : "web";
    const asking: Asking = {
      device: peer, name: who.name, email: who.email, kind, label: (str(get(hello.value, "label")) ?? "").slice(0, 120),
      signKey: kind === "app" ? str(get(hello.value, "sign_key")) : null, code: pairCode((b) => inner.host.randomBytes(b)),
      at: Math.floor(inner.host.nowMs() / 1000), until: Math.floor(inner.host.nowMs()) + PAIR_WAIT_MS, places, hidden: false, away: Deferred.makeUnsafe<void>(),
    };
    all.set(peer, asking);
    told(inner);
    const session = pairSession(peer, me, places.map((p) => p.ws));
    yield* Effect.ensuring(
      Effect.gen(function* () {
        yield* d.send({ t: "code", workspaces: places.map((p) => p.ws) });
        let tries = 0;
        let expect: Uint8Array | null = null;
        const wrong = Effect.suspend(() => (tries >= PAIR_TRIES ? d.send({ t: "no", error: "tries" }) : d.send({ t: "wrong", left: PAIR_TRIES - tries })));
        for (;;) {
          const next = yield* Effect.raceAllFirst([
            Effect.map(d.next(), (m) => ({ m }) as const),
            Effect.as(Deferred.await(asking.away), { away: true } as const),
            Effect.as(Effect.sleep(Math.max(0, asking.until - inner.host.nowMs())), { late: true } as const),
          ]);
          if ("away" in next) return yield* d.send({ t: "no", error: "denied" });
          if ("late" in next) return yield* d.send({ t: "no", error: "late" });
          if (next.m === null || !isObject(next.m)) return;
          const m = next.m;
          if (m.t === "pake") {
            if (tries >= PAIR_TRIES) return yield* d.send({ t: "no", error: "tries" });
            tries++;
            const p = pakeStart(asking.code, session, (b) => inner.host.randomBytes(b));
            const keys = pakeKeys(p, unhex(str(m.y) ?? ""), "trusted");
            if (keys === null) return yield* d.send({ t: "no", error: "bad_share" });
            expect = keys.theirs;
            yield* d.send({ t: "pake", y: hex(p.share), mac: hex(keys.mine) });
          } else if (m.t === "confirm" && expect !== null && sameMac(expect, unhex(str(m.mac) ?? ""))) {
            return yield* d.send(yield* approve(inner, asking));
          } else {
            expect = null;
            yield* wrong;
            if (tries >= PAIR_TRIES) return;
          }
        }
      }),
      Effect.sync(() => {
        if (all.get(peer) === asking) all.delete(peer);
        told(inner);
      }),
    );
  });
}

/// The new device signed in where it asked and this device approves it: an app as one that signs too, a web page for
/// WEB_DEVICE_SECS.
function approve(inner: Inner, a: Asking): Effect.Effect<J> {
  return Effect.gen(function* () {
    const done: string[] = [];
    const failed: { ws: string; error: string }[] = [];
    for (const p of a.places) {
      const body: J = { id: a.device, sub: p.sub, kind: a.kind, label: a.label };
      if (a.kind === "app" && a.signKey !== null) body.sign_key = a.signKey;
      if (a.kind === "web") body.exp = Math.floor(inner.host.nowMs() / 1000) + WEB_DEVICE_SECS;
      const signed = yield* Effect.result(new Lock(inner, p.ws, p.account, null, true).append("device", body));
      if (signed._tag === "Success") done.push(p.ws);
      else failed.push({ ws: p.ws, error: signed.failure.message });
      yield* Effect.ignore(read(inner, p.ws), { log: "Unhandled", message: "pairing workspace read" });
    }
    return { t: "approved", workspaces: done, failed };
  });
}

/// The `lockPrompts` topic's `pairing`: the new devices showing this one's code, oldest first, but those whose prompt
/// was closed.
function shown(inner: Inner): J[] {
  return [...askingsOf(inner).values()]
    .filter((a) => !a.hidden)
    .sort((a, b) => a.at - b.at)
    .map((a) => ({
      device: a.device, name: a.name, email: a.email, kind: a.kind, label: a.label, code: a.code, created_at: a.at,
      deviceText: deviceText(a), until: a.until, untilText: untilText(inner, a.until),
      workspaces: a.places.map((p) => {
        const v = view(inner, p.ws);
        return { id: p.ws, name: nameOf(inner, p.ws), emoji: str(get(v, "emoji")), icon: str(get(v, "icon")) };
      }),
    }));
}

/// 14:05 前有效: when a code is too old, as the clock says it here.
const untilText = (inner: Inner, until: number) => t("core-misc.lock.pairUntil", { time: format.clock(until, inner.host.utcOffsetMin(until)) });

function deny(inner: Inner, device: string): void {
  const a = askingsOf(inner).get(device);
  if (a) Deferred.doneUnsafe(a.away, Effect.void);
}

/// Its prompt closed: no longer shown, the code good until it is typed, turned away, or too old. Asked again (a new
/// connection), the new device shows a new code, put up again.
function hide(inner: Inner, device: string): void {
  const a = askingsOf(inner).get(device);
  if (!a || a.hidden) return;
  a.hidden = true;
  told(inner);
}

// ── the new device ──

/// A trusted device that showed a code, and the workspaces it approves this one in; `until`, when its code is too old
/// (ms, as this device saw it come).
export type Met = { id: string; d: Duplex; workspaces: string[]; until?: number };
/// This device's try: how far it got, the trusted devices showing a code.
export type Trying = { state: "finding" | "code" | "checking" | "wrong" | "none" | "failed" | "done"; left?: number; error?: string; workspaces: string[]; met: Map<string, Met>; run: number };

const tryings = new WeakMap<Inner, Trying>();
let runs = 0;

function mine(inner: Inner, ws: string): J | null {
  const y = tryings.get(inner);
  if (!y || !y.workspaces.includes(ws)) return null;
  const until = Math.max(0, ...[...y.met.values()].map((m) => m.until ?? 0));
  const typing = y.state === "code" || y.state === "wrong";
  return {
    state: y.state, devices: y.met.size, ...(y.left !== undefined ? { left: y.left } : {}), ...(y.error !== undefined ? { error: y.error } : {}),
    ...(typing && until > 0 ? { until, untilText: untilText(inner, until) } : {}),
  };
}

const changed = (inner: Inner, y: Trying) => inner.store.invalidateAll((t) => (t.topic === "lock" && y.workspaces.includes(String(t.workspace))) || t.topic === "lockPrompts");

function drop(y: Trying): void {
  for (const m of y.met.values()) m.d.close();
  y.met.clear();
}

/// The workspaces this device waits in (a lock without it, or, an app, one where it does not sign with its key), and
/// the devices that may approve it in them: its person's own that sign, and the owners' and admins'.
function waitingIn(inner: Inner, base: string): { workspaces: string[]; trusted: string[] } {
  const workspaces: string[] = [];
  const trusted = new Set<string>();
  const signer = signerOf(inner);
  for (const [ws, sub] of inner.workspaces.owned()) {
    const h = held(inner, ws);
    if (!h?.head) continue;
    const f = fold(h.entries);
    const had = f.devices.get(base);
    const unsigned = had !== undefined && had.kind === "app" && inner.host.appKeys === true && (signer === null || had.sign_key !== signer);
    if (f.disabled || (had !== undefined && !unsigned)) continue;
    workspaces.push(ws);
    for (const d of f.devices.values()) {
      const role = f.members.get(d.sub)?.role;
      if (d.id !== base && typeof d.sign_key === "string" && d.kind === "app" && (d.sub === sub || role === "owner" || role === "admin")) trusted.add(d.id);
    }
  }
  return { workspaces, trusted: [...trusted] };
}

/// `lock.pair`: the trusted devices dialled, each that answers asked to show a code.
function begin(inner: Inner): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    const mesh = yield* inner.mesh();
    const base = mesh.deviceId();
    const before = tryings.get(inner);
    if (before) drop(before);
    const { workspaces, trusted } = waitingIn(inner, base);
    if (workspaces.length === 0) return yield* Effect.fail(CoreError.invalid("this device waits in no workspace"));
    const y = trying(inner, workspaces);
    // What it says of itself, in each workspace: a credential for its main endpoint; an app's signing key.
    const credentials: J[] = [];
    for (const ws of workspaces) {
      const c = yield* Effect.result(inner.cloudSync.credential(ws, base, false, base, mesh.lockClaim(ws, base)));
      if (c._tag === "Success") credentials.push({ ws, credential: c.success.credential });
    }
    const signer = inner.host.appKeys ? yield* Effect.mapError(Signer.make(inner.host), (e) => new CoreError("lock_key", t("core-misc.lock.keyNotKept", { error: e.message }))) : null;
    if (signer) signerKnown(inner, signer.id);
    const hello = { t: "hello", v: 1, workspaces: credentials, kind: inner.host.appKeys ? "app" : "web", label: prefs.deviceName(inner.data) ?? "", sign_key: signer?.id ?? null };
    const relays = [...new Set([...(inner.cloudSync.relays ?? []), ...workspaces.flatMap((ws) => inner.cloudSync.workspaceRelays(ws))])];
    inner.runner.fork(
      Effect.gen(function* () {
        yield* Effect.forEach(trusted, (id) => Effect.ignore(Effect.timeout(dial(inner, y, id, relays, hello), PAIR_DIAL_MS)), { concurrency: "unbounded", discard: true });
        if (tryings.get(inner) !== y || y.state !== "finding") return;
        y.state = y.met.size > 0 ? "code" : "none";
        changed(inner, y);
      }),
    );
    return null;
  });
}

/// One trusted device, dialled: kept once it shows a code.
function dial(inner: Inner, y: Trying, id: string, relays: string[], hello: J): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const endpoint = (yield* inner.mesh()).endpoint();
    const connection = yield* Effect.mapError(endpoint.connect({ id, relays }, PAIR_ALPN, []), (e) => new CoreError("pair", e.message));
    const stream = yield* Effect.mapError(connection.openBi(), (e) => new CoreError("pair", e.message));
    const d = streamDuplex(stream, () => connection.close(0, "done"));
    yield* d.send(hello);
    const answer = yield* d.next();
    if (tryings.get(inner) !== y || !isObject(answer) || answer.t !== "code") return d.close();
    keep(inner, y, id, d, arr(answer.workspaces).filter((w): w is string => typeof w === "string"));
  });
}

/// This device's try begun, in `workspaces`: what came of one before forgotten.
export function trying(inner: Inner, workspaces: string[]): Trying {
  const y: Trying = { state: "finding", workspaces, met: new Map(), run: ++runs };
  tryings.set(inner, y);
  changed(inner, y);
  return y;
}

/// A trusted device that shows a code, kept: what it says while no code is being checked (`no`: turned away, the code
/// too old; its end), and its code's time up with no word from it (PAIR_WAIT_MS and PAIR_GRACE_MS since it came), end
/// it here at once, and the last one ended says why (`endedText`), so the page asks again; what it answers a code
/// typed is `tryOne`'s.
export function keep(inner: Inner, y: Trying, id: string, raw: Duplex, workspaces: string[]): Met {
  const heard = Effect.runSync(Queue.unbounded<J | null>());
  const closed = Deferred.makeUnsafe<void>();
  const d: Duplex = {
    send: raw.send,
    next: () => Queue.take(heard),
    close: () => {
      Deferred.doneUnsafe(closed, Effect.void);
      raw.close();
    },
  };
  const m: Met = { id, d, workspaces, until: Math.floor(inner.host.nowMs()) + PAIR_WAIT_MS };
  // Whether it is still one of this try's, nothing being checked with it now: what it says then is said to nobody.
  const idle = () => tryings.get(inner) === y && y.met.get(id) === m && y.state !== "checking";
  const end = (why: CoreError) => {
    d.close();
    y.met.delete(id);
    if (y.met.size === 0) {
      y.state = "failed";
      y.error = endedText([why]);
      delete y.left;
    }
    changed(inner, y);
  };
  y.met.set(id, m);
  if (y.state === "finding" || y.state === "none") y.state = "code";
  changed(inner, y);
  inner.runner.fork(
    Effect.gen(function* () {
      for (;;) {
        const next = yield* Effect.raceFirst(
          Effect.map(Effect.orElseSucceed(raw.next(), () => null), (msg) => ({ msg }) as const),
          Effect.as(Deferred.await(closed), { closed: true } as const),
        );
        if ("closed" in next) return;
        const msg = next.msg;
        if ((msg === null || (isObject(msg) && msg.t === "no")) && idle()) return end(ended(msg));
        Queue.offerUnsafe(heard, msg);
        if (msg === null) return;
      }
    }),
  );
  // (being checked then: its answer, or its end, is `tryOne`'s)
  inner.runner.fork(
    Effect.raceFirst(
      Effect.andThen(Effect.sleep(PAIR_WAIT_MS + PAIR_GRACE_MS), Effect.sync(() => idle() && end(new CoreError("pair_late", "the trusted device's code is too old")))),
      Deferred.await(closed),
    ),
  );
  return m;
}

/// `lock.pairCode`: the code typed proved to each trusted device showing one; the one it was signs this device in.
function prove(inner: Inner, typed: string): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    const y = tryings.get(inner);
    const code = typedCode(typed);
    if (y?.state === "failed") return yield* Effect.fail(new CoreError("pair_ended", y.error ?? ""));
    if (!y || y.met.size === 0) return yield* Effect.fail(CoreError.invalid("no trusted device shows a code"));
    if (code === null) return yield* Effect.fail(new CoreError("pair_code", t("core-misc.lock.pairBadCode")));
    const base = (yield* inner.mesh()).deviceId();
    y.state = "checking";
    changed(inner, y);
    const results = yield* Effect.forEach([...y.met.values()], (m) => Effect.map(Effect.result(tryOne(inner, m, base, code)), (r) => [m, r] as const), { concurrency: "unbounded" });
    let approved: J | null = null;
    let left = 0;
    const ends: CoreError[] = [];
    for (const [m, r] of results) {
      if (r._tag === "Success" && "approved" in r.success) approved = r.success.approved;
      else if (r._tag === "Success" && "left" in r.success) left = Math.max(left, r.success.left);
      else {
        if (r._tag === "Failure") ends.push(r.failure);
        m.d.close();
        y.met.delete(m.id);
      }
    }
    if (approved !== null) {
      drop(y);
      y.state = "done";
      for (const ws of arr(get(approved, "workspaces"))) if (typeof ws === "string") yield* Effect.ignore(read(inner, ws), { log: "Unhandled", message: "pairing workspace read" });
    } else if (y.met.size > 0) {
      y.state = "wrong";
      y.left = left;
    } else {
      y.state = "failed";
      y.error = endedText(ends);
    }
    changed(inner, y);
    if (approved === null) return yield* Effect.fail(y.state === "wrong" ? new CoreError("pair_wrong", t("core-misc.lock.pairWrong", { n: left })) : new CoreError("pair_ended", y.error ?? ""));
    return approved;
  });
}

/// What the new device says once no trusted device takes a code any more, as they ended (`tryOne`'s errors): one
/// could not sign it in, turned it away, ran out of tries, kept the code too long; else none could be reached.
function endedText(ends: CoreError[]): string {
  const codes = ends.map((e) => e.code);
  const unsigned = ends.find((e) => e.code === "pair_unsigned");
  if (unsigned) return t("core-misc.lock.pairUnsigned", { error: unsigned.message });
  if (codes.includes("pair_denied")) return t("core-misc.lock.pairDenied");
  if (codes.includes("pair_tries")) return t("core-misc.lock.pairTries");
  if (codes.includes("pair_late")) return t("core-misc.lock.pairLate");
  return t("core-misc.lock.pairGone");
}

/// An `approved` that signed this device in nowhere: why, as the trusted device said it of each workspace.
function unsigned(answer: J): CoreError {
  const why = arr(answer.failed).map((f) => str(get(f, "error"))).filter((e): e is string => !!e);
  return new CoreError("pair_unsigned", [...new Set(why)].join(t("core-misc.lock.listSep")) || "nothing signed");
}

/// A trusted device's answer that ends it (`no {error}`, or the stream's end): why, as an error's code.
function ended(answer: unknown): CoreError {
  const why = isObject(answer) && answer.t === "no" ? str(answer.error) : null;
  if (why === "tries") return new CoreError("pair_tries", "the trusted device took its last try");
  if (why === "denied") return new CoreError("pair_denied", "turned away on the trusted device");
  if (why === "late") return new CoreError("pair_late", "the trusted device's code is too old");
  return new CoreError("pair_gone", "the trusted device gave up");
}

/// One trusted device: the code proved, its answer; ended there, why (`ended`).
export function tryOne(inner: Inner, m: Met, base: string, code: string): Effect.Effect<{ approved: J } | { left: number }, CoreError> {
  return Effect.gen(function* () {
    const p = pakeStart(code, pairSession(base, m.id, m.workspaces), (b) => inner.host.randomBytes(b));
    yield* m.d.send({ t: "pake", y: hex(p.share) });
    const r = yield* m.d.next();
    if (!isObject(r) || r.t !== "pake") return yield* Effect.fail(ended(r));
    const keys = pakeKeys(p, unhex(str(r.y) ?? ""), "new");
    if (keys !== null && sameMac(keys.theirs, unhex(str(r.mac) ?? ""))) {
      yield* m.d.send({ t: "confirm", mac: hex(keys.mine) });
      const a = yield* m.d.next();
      if (isObject(a) && a.t === "approved") return arr(a.workspaces).length > 0 ? { approved: a } : yield* Effect.fail(unsigned(a));
      return yield* Effect.fail(ended(a));
    }
    yield* m.d.send({ t: "wrong" });
    const w = yield* m.d.next();
    if (isObject(w) && w.t === "wrong" && typeof w.left === "number" && w.left > 0) return { left: w.left };
    return yield* Effect.fail(ended(w));
  });
}

function cancel(inner: Inner): void {
  const y = tryings.get(inner);
  if (!y) return;
  drop(y);
  tryings.delete(inner);
  changed(inner, y);
}

export function install(_inner: Inner): void {
  hooks.lockPair = served;
  pairs.shown = shown;
  pairs.mine = mine;
  pairs.deny = deny;
  pairs.hide = hide;
  pairs.run = (inner, name, _ws, params) => {
    if (name === "pair") return begin(inner);
    if (name === "pairCode") return prove(inner, str(params.code) ?? "");
    cancel(inner);
    return Effect.succeed(null);
  };
}
