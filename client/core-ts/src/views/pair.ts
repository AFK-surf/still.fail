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
// Someone made a member after the lock was turned on is in none of its entries: the cloud says they are a member, and
// nothing signs that as it happens (a web page may add them; they may not have signed in yet). An owner's or admin's
// device shows the code for their first device all the same, and the code typed makes them a member of the lock as it
// signs that device in (2026-11-06: a colleague added to a workspace in security mode asked, and no device anywhere
// showed a code: 「他请求安全码根本跳不出来」).
//
// A new device (`lock.pair`, its waiting page): dials them all, and once one or more show a code, proves the code typed
// (`lock.pairCode`) to each; the one whose code it was approves it. `me.pair` says how far it got. A trusted device that
// ends it while nothing is typed (turned away, the code too old, gone) is heard at once, not once a code is typed: the
// page says why and asks again (2026-10-30: the boxes stayed after the code was gone). One not reached (its app not
// open, a phone's put away) is dialled again every PAIR_REDIAL_MS, PAIR_DIAL_TRIES times in all, a code shown elsewhere
// or not: one the person opens after asking shows its code too (2026-11-05: they asked first, then went to open their
// phone and other computers, and nothing came up on any; each had been dialled once, for 20 seconds, when they asked).
// One reached is not dialled again in that try, whatever came of it: it shows its code once (the user: 「每 10 秒一次
// 也可以，但是比如说最多找 6 次这样。并且如果已经弹出来了，就不要重复弹」; a trusted device met again shows a new code).
//
// The wire, a line of JSON each way at a time on one stream: new → `hello {workspaces: [{ws, credential}], kind, label,
// sign_key}`; trusted → `code {workspaces}` (the ones it approves) or `no {error}`; new → `pake {y}`; trusted → `pake
// {y, mac}`; new → `confirm {mac}` when the trusted one's MAC is right, else `wrong`; trusted → `approved {workspaces,
// failed}`, or `wrong {left}` / `no`. A `no` says why: `tries` (out of them), `denied` (turned away there), `late` (the
// code too old), `bad_share`; a trusted device from before `late` closes the stream then with no word. An `approved`
// that signed it in nowhere (each workspace in `failed`, with why) is no approval: the new device says why.
import { ed25519 } from "@noble/curves/ed25519.js";
import { Deferred, Effect, Fiber, Queue } from "effect";
import type { Inner } from "../core.ts";
import { hooks } from "../core/execute.ts";
import { CoreError, asCoreError } from "../error.ts";
import { t } from "../i18n.ts";
import type { IrohConnection, IrohStream } from "../iroh.ts";
import { Signer, WEB_DEVICE_SECS, entryHash } from "../lock.ts";
import { Lines } from "../mesh.ts";
import { PAIR_ALPN, PAIR_TRIES, pairCode, pairSession, pakeKeys, pakeStart, sameMac, typedCode } from "../pair.ts";
import * as format from "../format.ts";
import * as prefs from "../prefs.ts";
import { get, hex, isObject, parseJson, utf8 } from "../util.ts";
import { fromB64url } from "../vault/crypto.ts";
import { type Checked, checkLock } from "../vault/lock-check.ts";
import { Priority } from "../sync/scheduler.ts";
import { Lock, baseOf, deviceText, fold, held, live, nameOf, pairs, read, signerKnown, signerLoading, signerOf, view } from "./lock.ts";

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
/// How often the new device dials a trusted one it has not reached (from when the last dial began), and how long each
/// dial tries to reach it: the person may open one only after asking.
export const PAIR_REDIAL_MS = 10_000;
export const PAIR_DIAL_MS = PAIR_REDIAL_MS;
/// How many times in all the new device dials a trusted one it does not reach, once asked (the first, then one each
/// PAIR_REDIAL_MS: about a minute).
export const PAIR_DIAL_TRIES = 6;
/// How long the new device waits for a trusted device it reached to say whether it shows a code.
const PAIR_ANSWER_MS = 30_000;
/// Who signs member credentials, and what kind they are (station/src/cloud/provider.ts STILLFAIL `credential`).
const ISSUERS = ["stillfail-cloud"];
const TYPES = ["stillfail-member+jwt"];

/// One way of a line of JSON at a time, on a stream.
export type Duplex = { send(message: J): Effect.Effect<void, CoreError>; next(): Effect.Effect<J | null, CoreError>; close(): void };

export function streamDuplex(stream: IrohStream, close: () => void): Duplex {
  const lines = new Lines(stream);
  return {
    send: (m) => Effect.mapError(stream.write(utf8(`${JSON.stringify(m)}\n`)), (e) => CoreError.plainly("pair", e)),
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
/// A place's `joins`: the lock there has not heard of this person (made a member since it was turned on).
type Asking = { device: string; name: string; email: string; kind: "app" | "web"; label: string; signKey: string | null; code: string; at: number; until: number; places: { ws: string; sub: string; account: string; joins?: boolean }[]; hidden: boolean; away: Deferred.Deferred<void> };

const askings = new WeakMap<Inner, Map<string, Asking>>();
const askingsOf = (inner: Inner) => {
  let m = askings.get(inner);
  if (!m) askings.set(inner, (m = new Map()));
  return m;
};
const told = (inner: Inner) => inner.store.invalidate({ topic: "lockPrompts" });

/// A new device's connection, as the mesh's endpoint took it: its one stream served, what it said last taken by the
/// new device (the stream finished and its end acknowledged), then closed. Closed at once, the close would race what is
/// still on its way (an approval, why it is turned away), and the new device could hear its connection cut instead.
/// Failed or stopped on the way, it is closed as it is.
export function served(inner: Inner, connection: IrohConnection): void {
  inner.runner.fork(
    Effect.ignore(
      Effect.ensuring(
        Effect.gen(function* () {
          const stream = yield* connection.acceptBi();
          const me = inner.meshNow()?.deviceId() ?? baseOf(inner);
          if (stream === null || me === null) return;
          yield* serveTrusted(inner, connection.remoteId(), me, streamDuplex(stream, () => connection.close(0, "done")));
          yield* stream.finish();
          yield* stream.stopped();
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
    // (one whose approval ran out, a web page's: approved again as a new one is)
    const had = live(lock.devices.get(peer), now);
    const key = str(get(hello, "sign_key"));
    const upgrade = had !== undefined && had.kind === "app" && get(hello, "kind") === "app" && key !== null && had.sign_key !== key;
    if (lock.disabled || mine?.sign_key !== signer || !mine.own || (had !== undefined && !upgrade)) continue;
    const c = credentialOf(str(get(w, "credential")) ?? "", lock.cloudKeys, ws, peer, now);
    if (c === null || c.sub === "" || (had !== undefined && c.sub !== had.sub)) continue;
    // Another person's: only their first device that signs, by an owner or admin (any later one they approve from a
    // device of their own: one approved for them would be no one's, signing nothing; lock-check.ts Device `own`).
    const role = lock.members.get(mine.sub);
    if (c.sub !== mine.sub && ((role !== "owner" && role !== "admin") || lock.signed.has(c.sub))) continue;
    who ??= c;
    if (c.sub !== who.sub) continue;
    // (not in the lock: the credential is the cloud's word they are a member; the person here, who gives them the code,
    // is what makes it so)
    places.push({ ws, sub: c.sub, account, ...(lock.members.has(c.sub) ? {} : { joins: true }) });
  }
  return { places, who };
}

/// The requested workspaces this app knows about whose cloud view names a lock it has not read yet. If its held chain
/// already contains that head, it is further ahead than the view and does not need to wait for it.
function locksToRead(inner: Inner, hello: J): string[] {
  const workspaces = new Set<string>();
  for (const w of arr(get(hello, "workspaces"))) {
    const ws = str(get(w, "ws"));
    if (ws === null || inner.workspaces.owner(ws) === null) continue;
    const v = view(inner, ws);
    if (!isObject(v) || !("lock" in v)) continue;
    const hash = str(get(v.lock, "hash")) ?? "";
    const h = held(inner, ws);
    if (hash === (h?.head?.hash ?? "")) continue;
    try {
      if (hash !== "" && h?.entries.some((e) => entryHash(e) === hash)) continue;
    } catch {
      // An incomplete held chain cannot prove it is ahead of the cloud view.
    }
    workspaces.add(ws);
  }
  return [...workspaces];
}

/// Workspaces whose newer lock has not been read cannot yet be used to decide who may approve.
function withoutLocks(hello: J, excluded: string[]): J {
  const blocked = new Set(excluded);
  return { ...hello, workspaces: arr(get(hello, "workspaces")).filter((w) => !blocked.has(str(get(w, "ws")) ?? "")) };
}

/// One new device, met: what it asks checked, its code shown until it is typed, turned away, or too late.
export function serveTrusted(inner: Inner, peer: string, me: string, d: Duplex): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const hello = yield* Effect.timeoutOption(d.next(), "30 seconds");
    if (hello._tag === "None" || !isObject(hello.value) || hello.value.t !== "hello") return;
    // An app can accept a connection while its kept signing key is still being read at startup. That is not a refusal:
    // wait for the read, unless the new device goes away, before deciding whether this device may approve it.
    const loading = signerLoading(inner);
    const stale = locksToRead(inner, hello.value);
    const initial = loading === null ? placesFor(inner, withoutLocks(hello.value, stale), peer, me) : null;
    const needLock = initial === null || initial.places.length === 0;
    let receive = () => d.next();
    let asked = initial;
    if ((loading !== null && arr(get(hello.value, "workspaces")).length > 0) || (needLock && stale.length > 0)) {
      // A host stream read may continue after its waiting effect is interrupted. Keep the same read alive and use its
      // result as the first message after showing the code, so it cannot consume that message behind another read.
      const pending = yield* Effect.forkChild(Effect.orElseSucceed(d.next(), () => null));
      const ready = Effect.gen(function* () {
        if (loading !== null) yield* loading;
        const stale = locksToRead(inner, hello.value);
        let places = placesFor(inner, withoutLocks(hello.value, stale), peer, me);
        // A newer lock is already known but still loading. If no other workspace can answer now, wait for that read:
        // a device just approved in the newer lock can then show this try's code. A ready workspace can proceed now.
        if (signerOf(inner) !== null && places.places.length === 0) {
          const completed = yield* Queue.unbounded<void>();
          yield* Effect.forkChild(Effect.forEach(stale, (ws) =>
            Effect.andThen(Effect.result(inner.scheduler.ask("cloud", `lock/${ws}`, Priority.asked, read(inner, ws))), Queue.offer(completed, undefined)),
          { concurrency: "unbounded", discard: true }));
          // Recheck after each read: an eligible workspace need not wait for an unrelated slow read. A read may
          // succeed while the cloud view moves on again, so never use a lock still known to be behind.
          for (const _ of stale) {
            yield* Queue.take(completed);
            places = placesFor(inner, withoutLocks(hello.value, locksToRead(inner, hello.value)), peer, me);
            if (places.places.length > 0) break;
          }
        }
        return places;
      });
      const result = yield* Effect.raceFirst(Effect.map(ready, (places) => ({ places }) as const), Effect.as(Fiber.join(pending), { away: true } as const));
      if ("away" in result) return;
      asked = result.places;
      let first = true;
      receive = () => {
        if (!first) return d.next();
        first = false;
        return Fiber.join(pending);
      };
    }
    asked ??= placesFor(inner, hello.value, peer, me);
    const { places, who } = asked;
    if (places.length === 0 || who === null) return yield* d.send({ t: "no", error: "not_here" });
    const all = askingsOf(inner);
    const before = all.get(peer);
    if (before) Deferred.doneUnsafe(before.away, Effect.void);
    const kind = get(hello.value, "kind") === "app" ? "app" : "web";
    const asking: Asking = {
      device: peer, name: who.name, email: who.email, kind, label: (str(get(hello.value, "label")) ?? "").slice(0, 120),
      signKey: kind === "app" ? str(get(hello.value, "sign_key")) : null, code: pairCode((b) => inner.host.randomBytes(b)),
      at: Math.floor(inner.host.nowMs() / 1000), until: inner.host.nowMs() + PAIR_WAIT_MS, places, hidden: false, away: Deferred.makeUnsafe<void>(),
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
            Effect.map(receive(), (m) => ({ m }) as const),
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
/// WEB_DEVICE_SECS; its person made a member first where the lock has not heard of them.
function approve(inner: Inner, a: Asking): Effect.Effect<J> {
  return Effect.gen(function* () {
    const done: string[] = [];
    const failed: { ws: string; error: string }[] = [];
    for (const p of a.places) {
      const body: J = { id: a.device, sub: p.sub, kind: a.kind, label: a.label };
      if (a.kind === "app" && a.signKey !== null) body.sign_key = a.signKey;
      if (a.kind === "web") body.exp = Math.floor(inner.host.nowMs() / 1000) + WEB_DEVICE_SECS;
      const lock = new Lock(inner, p.ws, p.account, null, true);
      const signed = yield* Effect.result(Effect.andThen(p.joins === true ? lock.admit(p.sub, a.email) : Effect.void, lock.append("device", body)));
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
    .map((a) => {
      // Who reads the code out decides this: that it also lets someone new into the lock is said as they do.
      const joins = a.places.filter((p) => p.joins === true).map((p) => nameOf(inner, p.ws));
      return {
        device: a.device, name: a.name, email: a.email, kind: a.kind, label: a.label, code: a.code, created_at: a.at,
        deviceText: deviceText(a) + (joins.length > 0 ? t("core-misc.lock.pairJoins", { names: joins.join(t("core-misc.lock.listSep")) }) : ""),
        until: a.until, untilText: untilText(inner, a.until),
        workspaces: a.places.map((p) => {
          const v = view(inner, p.ws);
          return { id: p.ws, name: nameOf(inner, p.ws), emoji: str(get(v, "emoji")), icon: str(get(v, "icon")) };
        }),
      };
    });
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
/// `lost`: a trusted device that showed a code ended since, others still showing theirs (the code typed may be its).
/// `approvedIn`, once `done`: the workspaces it was signed in to (of those it waited in, the others still wait).
/// `approvers`: in each workspace, the trusted devices it dials (its page names them: the person opens one of those).
/// `credentialErrors`: workspaces for which this try could not obtain the credential needed to ask for approval.
export type Trying = { state: "finding" | "code" | "checking" | "wrong" | "none" | "failed" | "done"; left?: number; error?: string; lost?: boolean; approvedIn?: string[]; workspaces: string[]; met: Map<string, Met>; run: number; approvers?: Map<string, string[]>; credentialErrors?: Map<string, string>; lockMoved?: (ws: string) => void; lockReading?: (ws: string) => void };

const tryings = new WeakMap<Inner, Trying>();
let runs = 0;

function mine(inner: Inner, ws: string): J | null {
  const y = tryings.get(inner);
  if (!y || !y.workspaces.includes(ws)) return null;
  const credentialError = y.credentialErrors?.get(ws);
  if (credentialError !== undefined) return { state: "failed", devices: 0, error: credentialError };
  // Signed in elsewhere, not here: no trusted device that answered approves it in this one (2026-11-04: a web page
  // waiting in three workspaces, approved in two, showed this one's page as it was, its code typed, as though nothing
  // had come of it).
  if (y.state === "done" && y.approvedIn !== undefined && !y.approvedIn.includes(ws)) {
    return { state: "failed", devices: 0, error: t("core-misc.lock.pairElsewhere", { names: y.approvedIn.map((w) => nameOf(inner, w)).join(t("core-misc.lock.listSep")) }) };
  }
  const until = Math.max(0, ...[...y.met.values()].map((m) => m.until ?? 0));
  const typing = y.state === "code" || y.state === "wrong";
  // The devices that may approve it here, each whether it shows a code for here now (the lock's view names them).
  const approvers = (y.approvers?.get(ws) ?? []).map((id) => ({ id, showing: y.met.get(id)?.workspaces.includes(ws) === true }));
  return {
    state: y.state, devices: y.met.size, ...(y.left !== undefined ? { left: y.left } : {}), ...(y.error !== undefined ? { error: y.error } : {}),
    ...(typing && until > 0 ? { until, untilText: untilText(inner, until) } : {}),
    ...(y.approvers !== undefined ? { approvers } : {}),
  };
}

const changed = (inner: Inner, y: Trying) => inner.store.invalidateAll((t) => (t.topic === "lock" && y.workspaces.includes(String(t.workspace))) || t.topic === "lockPrompts");

function drop(y: Trying): void {
  for (const m of y.met.values()) m.d.close();
  y.met.clear();
}

/// The workspaces this device waits in (a lock without it, or, an app, one where it does not sign with its key), and
/// the devices that may approve it in them: its person's own that sign, and the owners' and admins' while the person
/// has none that signs (their first; as the checked lock says, where it checks out: views/pair.ts `placesFor`).
/// `approvers`: those of each workspace.
function waitingIn(inner: Inner, base: string): { workspaces: string[]; approvers: Map<string, string[]> } {
  const workspaces: string[] = [];
  const approvers = new Map<string, string[]>();
  const signer = signerOf(inner);
  for (const [ws, sub] of inner.workspaces.owned()) {
    const h = held(inner, ws);
    if (!h?.head) continue;
    const f = fold(h.entries);
    const had = live(f.devices.get(base), Math.floor(inner.host.nowMs() / 1000));
    const unsigned = had !== undefined && had.kind === "app" && inner.host.appKeys === true && (signer === null || had.sign_key !== signer);
    if (f.disabled || (had !== undefined && !unsigned)) continue;
    workspaces.push(ws);
    let checked: Checked | null = null;
    try {
      checked = checkLock(h.entries, Math.floor(inner.host.nowMs() / 1000));
    } catch {}
    const first = checked === null || !checked.signed.has(sub);
    const here: string[] = [];
    for (const d of f.devices.values()) {
      const role = f.members.get(d.sub)?.role;
      const own = checked === null || checked.devices.get(d.id)?.own === true;
      if (d.id !== base && own && typeof d.sign_key === "string" && d.kind === "app" && (d.sub === sub || (first && (role === "owner" || role === "admin")))) {
        here.push(d.id);
      }
    }
    approvers.set(ws, here);
  }
  return { workspaces, approvers };
}

/// Where the new device reaches a trusted one: its mesh's endpoint, dialling the trusted device's id on PAIR_ALPN
/// (tests put a line of their own here).
export const dialer = {
  open(inner: Inner, id: string, relays: string[]): Effect.Effect<Duplex, CoreError> {
    return Effect.gen(function* () {
      const endpoint = (yield* inner.mesh()).endpoint();
      const connection = yield* Effect.mapError(endpoint.connect({ id, relays }, PAIR_ALPN, []), (e) => CoreError.plainly("pair", e));
      const stream = yield* Effect.mapError(connection.openBi(), (e) => {
        connection.close(0, "done");
        return CoreError.plainly("pair", e);
      });
      return streamDuplex(stream, () => connection.close(0, "done"));
    });
  },
};

/// Whether this device's try `y` still looks for trusted devices: the one it is on, not over (approved, ended, or
/// given up on: none reached in PAIR_DIAL_TRIES dials each).
const looking = (inner: Inner, y: Trying) => tryings.get(inner) === y && y.state !== "done" && y.state !== "failed" && y.state !== "none";

/// `lock.pair`: the trusted devices dialled, each that answers asked to show a code.
function begin(inner: Inner): Effect.Effect<unknown, CoreError> {
  return Effect.gen(function* () {
    const mesh = yield* inner.mesh();
    const base = mesh.deviceId();
    const before = tryings.get(inner);
    if (before) drop(before);
    const { workspaces, approvers } = waitingIn(inner, base);
    if (workspaces.length === 0) return yield* Effect.fail(CoreError.invalid("this device waits in no workspace"));
    const y = trying(inner, workspaces);
    y.approvers = approvers;
    // What it says of itself: an app's signing key, and each workspace's credential for its main endpoint.
    const signer = inner.host.appKeys ? yield* Effect.tapError(
      Effect.mapError(Signer.make(inner.host), (e) => CoreError.plainly("lock_key", e, t("core-misc.lock.keyNotKept", { error: asCoreError(e).message }))),
      (error) => Effect.sync(() => {
        // A failed key read ends the request; leaving it as "finding" would imply devices were still being contacted.
        // A cancelled or newer request must not be changed by this one's late failure.
        if (tryings.get(inner) !== y) return;
        y.state = "failed";
        y.error = error.message;
        changed(inner, y);
      }),
    ) : null;
    if (signer) signerKnown(inner, signer.id);
    const relays = [...new Set([...(inner.cloudSync.relays ?? []), ...workspaces.flatMap((ws) => inner.cloudSync.workspaceRelays(ws))])];
    inner.runner.fork(
      Effect.gen(function* () {
        // Without any credential the trusted devices must refuse the request. A brief cloud outage used to be silently
        // dropped here, so even after it recovered each device was asked with no credential and showed no code.
        // Retry until one workspace can be asked, on the same schedule as the device dials. Keep partial success: a
        // workspace whose credential failed says why, while those with credentials can still be approved.
        let credentials: J[] = [];
        let failures = new Map<string, CoreError>();
        for (let n = 0; n < PAIR_DIAL_TRIES && looking(inner, y); n++) {
          const began = inner.host.nowMs();
          credentials = [];
          failures = new Map();
          // A request can connect yet never answer. Bound each attempt to the existing retry interval and fetch the
          // workspaces together, so one slow account cannot indefinitely prevent the others from asking for a code.
          const fetched = yield* Effect.forEach(workspaces, (ws) => Effect.map(
            Effect.result(Effect.timeoutOption(inner.cloudSync.credential(ws, base, false, base, mesh.lockClaim(ws, base)), PAIR_REDIAL_MS)),
            (result) => ({ ws, result }),
          ), { concurrency: "unbounded" });
          if (!looking(inner, y)) break;
          for (const { ws, result } of fetched) {
            if (result._tag === "Failure") failures.set(ws, result.failure);
            else if (result.success._tag === "Some") credentials.push({ ws, credential: result.success.value.credential });
            else failures.set(ws, CoreError.plainly("timeout", "credential request timed out"));
          }
          if (credentials.length > 0 || !looking(inner, y)) break;
          // A rejected or expired login will not recover by asking again, unlike a network failure or rate limit.
          if ([...failures.values()].every((e) => e.status !== undefined && e.status >= 400 && e.status < 500 && e.status !== 408 && e.status !== 429)) break;
          const wait = PAIR_REDIAL_MS - (inner.host.nowMs() - began);
          if (wait > 0 && n + 1 < PAIR_DIAL_TRIES) yield* Effect.sleep(wait);
        }
        if (!looking(inner, y)) return;
        y.credentialErrors = new Map([...failures].map(([ws, error]) => [ws, error.message]));
        if (credentials.length === 0 && failures.size > 0) {
          y.state = "failed";
          y.error = failures.values().next().value!.message;
          changed(inner, y);
          return;
        }
        changed(inner, y);
        const hello = { t: "hello", v: 1, workspaces: credentials, kind: inner.host.appKeys ? "app" : "web", label: prefs.deviceName(inner.data) ?? "", sign_key: signer?.id ?? null };
        // A lock can move while credentials or devices are being sought. Follow it for this try, asking newly named
        // approvers too, but never dial one a second time after its seek ended: it may already be showing a code.
        const asked = new Set<string>();
        const done = Deferred.makeUnsafe<void>();
        let active = 1; // Hold completion until the initial seeks and any pending lock reads have been started.
        const finish = () => {
          if (--active === 0) {
            delete y.lockMoved;
            delete y.lockReading;
            Deferred.doneUnsafe(done, Effect.void);
          }
        };
        const track = (work: Effect.Effect<void>) => {
          active++;
          inner.runner.fork(Effect.ensuring(work, Effect.sync(finish)));
        };
        const credentialWorkspaces = new Set(credentials.map((c) => c.ws as string));
        const reads = new Set<string>();
        const watchRead = (ws: string) => {
          if (!looking(inner, y) || !credentialWorkspaces.has(ws) || !locksToRead(inner, hello).includes(ws)) return;
          // A later head may arrive while this workspace is already reading. Follow that head too; the scheduler
          // folds requests for the same read together, while each wait has its own deadline.
          const key = JSON.stringify([ws, str(get(get(view(inner, ws), "lock"), "hash"))]);
          if (reads.has(key)) return;
          reads.add(key);
          const work = Effect.ignore(Effect.timeoutOption(inner.scheduler.ask("cloud", `lock/${ws}`, Priority.asked, read(inner, ws)), PAIR_DIAL_TRIES * PAIR_REDIAL_MS));
          track(Effect.ensuring(work, Effect.sync(() => { reads.delete(key); })));
        };
        const refresh = () => {
          if (!looking(inner, y)) return;
          const current = waitingIn(inner, base);
          y.approvers = current.approvers;
          changed(inner, y);
          for (const ws of y.workspaces) {
            if (!credentialWorkspaces.has(ws)) continue;
            for (const id of current.approvers.get(ws) ?? []) {
              if (asked.has(id)) continue;
              asked.add(id);
              track(seek(inner, y, id, relays, hello));
            }
          }
        };
        y.lockMoved = (ws) => { if (y.workspaces.includes(ws)) refresh(); };
        y.lockReading = (ws) => { if (y.workspaces.includes(ws)) watchRead(ws); };
        // If a newer head is already known, wait a bounded time for its read even when the old approvers all answer
        // immediately. A ready workspace can show its code meanwhile, without waiting for another workspace's read.
        for (const ws of locksToRead(inner, hello)) watchRead(ws);
        refresh();
        finish();
        yield* Deferred.await(done);
        // Each reached without a code shown, or not reached in PAIR_DIAL_TRIES dials.
        if (tryings.get(inner) !== y || y.state !== "finding") return;
        y.state = y.met.size > 0 ? "code" : "none";
        changed(inner, y);
      }),
    );
    return null;
  });
}

/// One trusted device, dialled until it is reached, this try is over, or PAIR_DIAL_TRIES dials did not reach it: one
/// each PAIR_REDIAL_MS from when the last began. Reached, it is not dialled again, whatever it answered: a code (kept),
/// that it shows none, or nothing (its answer lost: it may show a code all the same, and met again it would show
/// another). A code shown by another meanwhile, it is still dialled: the person may have this one at hand, not that.
function seek(inner: Inner, y: Trying, id: string, relays: string[], hello: J): Effect.Effect<void> {
  return Effect.gen(function* () {
    for (let n = 0; n < PAIR_DIAL_TRIES && looking(inner, y) && !y.met.has(id); n++) {
      const began = inner.host.nowMs();
      const reached = yield* Effect.orElseSucceed(dial(inner, y, id, relays, hello), () => false);
      if (reached) return;
      const wait = PAIR_REDIAL_MS - (inner.host.nowMs() - began);
      if (wait > 0 && n + 1 < PAIR_DIAL_TRIES) yield* Effect.sleep(wait);
    }
  });
}

/// One trusted device, dialled (PAIR_DIAL_MS to reach it): kept once it shows a code. Whether it was reached (it was
/// told who asks); not reached, it fails.
function dial(inner: Inner, y: Trying, id: string, relays: string[], hello: J): Effect.Effect<boolean, CoreError> {
  return Effect.gen(function* () {
    const reached = yield* Effect.timeoutOption(dialer.open(inner, id, relays), PAIR_DIAL_MS);
    if (reached._tag === "None") return yield* Effect.fail(CoreError.plainly("pair", "not reached"));
    const d = reached.value;
    yield* Effect.onError(d.send(hello), () => Effect.sync(() => d.close()));
    const answer = yield* Effect.orElseSucceed(Effect.timeoutOption(d.next(), PAIR_ANSWER_MS), () => null);
    // (no word from it, or this try over meanwhile, or another begun: nothing kept of it)
    if (answer === null || answer._tag === "None" || !looking(inner, y) || !isObject(answer.value) || answer.value.t !== "code") {
      d.close();
      return true;
    }
    keep(inner, y, id, d, arr(answer.value.workspaces).filter((w): w is string => typeof w === "string"));
    return true;
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
  const m: Met = { id, d, workspaces, until: inner.host.nowMs() + PAIR_WAIT_MS };
  // Whether it is still one of this try's, nothing being checked with it now: what it says then is said to nobody.
  const idle = () => tryings.get(inner) === y && y.met.get(id) === m && y.state !== "checking";
  const end = (why: CoreError) => {
    d.close();
    y.met.delete(id);
    if (y.met.size === 0) {
      y.state = "failed";
      y.error = endedText([why]);
      delete y.left;
    } else y.lost = true;
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
    // Not approved as far as this device heard, a trusted device having ended as the code was proved to it: it may have
    // signed it in all the same, its answer lost on the way back (its line gone, its app put away as it answered;
    // 2026-11-04 a phone signed a web page in and the page said the code was wrong). The lock as the cloud keeps it says.
    if (approved === null && ends.length > 0) {
      const now = Math.floor(inner.host.nowMs() / 1000);
      const inNow: string[] = [];
      for (const ws of y.workspaces) {
        yield* Effect.ignore(read(inner, ws), { log: "Unhandled", message: "pairing workspace read" });
        if (live(fold(held(inner, ws)?.entries ?? []).devices.get(base), now) !== undefined) inNow.push(ws);
      }
      if (inNow.length > 0) approved = { t: "approved", workspaces: inNow, failed: [] };
    }
    if (approved !== null) {
      drop(y);
      y.state = "done";
      y.approvedIn = arr(get(approved, "workspaces")).filter((w): w is string => typeof w === "string");
      for (const ws of y.approvedIn) yield* Effect.ignore(read(inner, ws), { log: "Unhandled", message: "pairing workspace read" });
    } else if (y.met.size > 0) {
      y.state = "wrong";
      y.left = left;
      // Wrong at those still showing a code, while another ended as it was proved to: the code may well have been that
      // one's (its line gone, its app put away), not wrong at all.
      y.error = t(ends.length > 0 || y.lost ? "core-misc.lock.pairWrongOrGone" : "core-misc.lock.pairWrong", { n: left });
    } else {
      y.state = "failed";
      y.error = endedText(ends);
    }
    changed(inner, y);
    if (approved === null) return yield* Effect.fail(y.state === "wrong" ? new CoreError("pair_wrong", y.error ?? "") : new CoreError("pair_ended", y.error ?? ""));
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
  pairs.moved = (inner, ws) => tryings.get(inner)?.lockMoved?.(ws);
  pairs.reading = (inner, ws) => tryings.get(inner)?.lockReading?.(ws);
  pairs.run = (inner, name, _ws, params) => {
    if (name === "pair") return begin(inner);
    if (name === "pairCode") return prove(inner, str(params.code) ?? "");
    cancel(inner);
    return Effect.succeed(null);
  };
}
