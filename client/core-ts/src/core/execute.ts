// Execution of named client calls, as Effects. What changes something takes effect in the core at
// once and answers when its source has it (rule 4); a write to still.fail cloud answers once what it changed is read
// again (the account topics show it), or after `REREAD_WAIT_MS` with the reading left to go on.
import { Deferred, Effect } from "effect";
import * as brand from "../brand.ts";
import type { Inner, Progress } from "../core.ts";
import { CoreError, asCoreError } from "../error.ts";
import { inkKept } from "../highlight.ts";
import { markdown } from "../markdown.ts";
import { bookAnswer, keepBook, keptBook, searchBook } from "../reader.ts";
import { Beside } from "../protocol.ts";
import * as keymap from "../keymap.ts";
import * as prefs from "../prefs.ts";
import type { ClientId, RequestId } from "../protocol.ts";
import type { SpanContext } from "../trace.ts";
import { Kind } from "../trace.ts";
import { t } from "../i18n.ts";
import { CLOUD_WRITE_MS, cloudSilent } from "../lock-pending.ts";
import { isObject } from "../util.ts";
import { Wake } from "../wake.ts";
import type { Call } from "./calls.ts";
import { UI_FAULT_CATEGORIES, UI_FAULT_OTHER } from "../ui-faults.ts";

export type Handler = (inner: Inner, call: Call, progress: Progress, at: [ClientId, RequestId], ctx: SpanContext) => Effect.Effect<unknown, CoreError>;

/// What later parts of the core execute (station calls, views, choose, attend…): each module adds its kinds here.
export const handlers: Partial<Record<Call["kind"] | "migrateDevice", Handler>> = {};

/// What other modules hear of calls the core runs itself.
export const hooks: {
  device?: (inner: Inner, facts: unknown) => void;
  updateNoticeOpen?: (inner: Inner, station: string, open: boolean) => void;
  /// A station's enrollment made: its commands, as the workspace lock has them say (views/lock.ts).
  enrolled?: (inner: Inner, sub: string, workspace: string, made: unknown) => Effect.Effect<unknown, CoreError>;
  /// A station refused this device for the workspace lock (what to say of it); why a station is not asked now
  /// (views/lock.ts).
  lockRefused?: (inner: Inner, workspace: string, station: string, theirs: unknown, told?: { person?: unknown; entries?: unknown; out?: unknown; left?: unknown }) => CoreError | null;
  lockWaiting?: (inner: Inner, workspace: string, station: string) => CoreError | null;
  /// A member about to be taken out of a workspace or given another role, or a station taken out: so in its lock
  /// first, by this device's signature where it signs there (views/lock.ts).
  roster?: (inner: Inner, sub: string, workspace: string, what: Roster) => Effect.Effect<unknown, CoreError>;
  /// A change of the roster's pending in the lock (`roster`'s `{pending: {id}}`) whose write to the cloud then failed:
  /// dropped, so that the change is not made at all, as the call's failure says (views/lock.ts).
  pendingDrop?: (inner: Inner, workspace: string, id: string) => void;
  /// People added to a workspace (the cloud's answer): so in its lock too, with the role given (views/lock.ts).
  added?: (inner: Inner, sub: string, workspace: string, role: string, answer: unknown) => Effect.Effect<unknown, CoreError>;
  /// A new device's connection, met face to face (views/pair.ts).
  lockPair?: (inner: Inner, connection: import("../iroh.ts").IrohConnection) => void;
} = {};

/// What a write to still.fail cloud changes of a workspace's roster, as its lock has one: a member out, a member's
/// role, a station out.
export type Roster = { member: string; gone: true } | { member: string; role: string } | { station: string };
function rosterOf(method: string, path: string, body: unknown): { ws: string; what: Roster } | null {
  const m = /^\/v1\/workspaces\/([^/]+)\/(members|stations|added)\/([^/]+)$/.exec(path);
  if (m === null) return null;
  const [ws, kind, id] = [m[1]!, m[2]!, m[3]!].map((x) => decodeURIComponent(x)) as [string, string, string];
  // (one added who has not signed in yet is held in the lock under their email: views/lock.ts `pendingOf`)
  if (kind === "added") return method === "DELETE" ? { ws, what: { member: `pending:${id.trim().toLowerCase()}`, gone: true } } : null;
  if (method === "DELETE") return { ws, what: kind === "members" ? { member: id, gone: true } : { station: id } };
  const role = isObject(body) ? body.role : undefined;
  return method === "PATCH" && kind === "members" && typeof role === "string" ? { ws, what: { member: id, role } } : null;
}

// (CLOUD_WRITE_MS: src/lock-pending.ts, where the lock's own writes to the cloud end by it too)
export { CLOUD_WRITE_MS };

/// How long a write to still.fail cloud that went through waits for the account's topics read again before it answers:
/// that read goes on after. 2026-11-11 a member added answered after 3 min 40 s, the POST itself under a second: every
/// account's topics were read again on a link where the workspace's stations were not reached, and the button turned
/// all that while (the person took it for not added).
export const REREAD_WAIT_MS = 3_000;

/// `reread` run to its end, waited on for `REREAD_WAIT_MS` at most; a span under the call's trace says how long it took.
function rereadAfterWrite(inner: Inner, reread: Effect.Effect<void>, ctx: SpanContext): Effect.Effect<void> {
  const span = inner.tracer.child("cloud.reread", Kind.Internal, ctx);
  const done = Deferred.makeUnsafe<void>();
  inner.runner.fork(
    Effect.ensuring(
      reread,
      Effect.sync(() => {
        span?.end();
        Deferred.doneUnsafe(done, Effect.void);
      }),
    ),
  );
  return Effect.raceFirst(
    Deferred.await(done),
    Effect.sleep(REREAD_WAIT_MS).pipe(Effect.andThen(Effect.sync(() => span?.set("stillfail.answered_before", true)))), // timer: a deadline on what a call waits for
  );
}

/// Runs a call; `at` is the client and id it came with, `ctx` its trace.
export function execute(inner: Inner, call: Call, progress: Progress, at: [ClientId, RequestId], ctx: SpanContext): Effect.Effect<unknown, CoreError> {
  return Effect.suspend((): Effect.Effect<unknown, CoreError> => {
    switch (call.kind) {
      case "authBegin": {
        const deviceName = call.deviceName ?? prefs.deviceName(inner.data) ?? brand.name();
        return Effect.map(inner.accounts.beginSignIn(call.redirectUri, call.returnTo, deviceName), (url) => ({ url }));
      }
      case "authPassword": {
        const deviceName = call.deviceName ?? prefs.deviceName(inner.data) ?? brand.name();
        return Effect.map(inner.accounts.passwordSignIn(call.email, call.password, deviceName), (account) => ({ account }));
      }
      case "authComplete":
        return Effect.map(inner.accounts.completeSignIn(call.query), ([account, returnTo]) => ({ account, return_to: returnTo }));
      case "wake": {
        const wake = new Wake(inner.host.nowMs(), Math.max(call.away, 0), call.network && !call.retry, call.retry);
        // What is asked again as the wake fails what was under way goes on new connections.
        if (wake.suspectsConnections()) inner.host.resetConnections();
        inner.wakes.wake(wake);
        // Said always (a call this quick is not otherwise): 2026-10-30 a phone's links to its four stations all went in
        // the same second, every few minutes, which was taken for the app frozen while off screen; nothing said it was.
        const span = inner.tracer.always("client.wake", Kind.Internal);
        span.set("stillfail.away_ms", Math.round(wake.away));
        if (wake.network) span.set("stillfail.network", true);
        if (wake.retry) span.set("stillfail.retry", true);
        span.set("stillfail.reset", wake.suspectsConnections());
        span.end();
        return Effect.succeed({});
      }
      case "clientError": {
        // A UI fault's text can hold editor keys made from file paths: only its category leaves (ui-faults.ts), whatever
        // an app sends, an older one's original text too.
        const message = call.source === "ui_fault" && !UI_FAULT_CATEGORIES.includes(call.message) ? UI_FAULT_OTHER : call.message;
        const key = `${call.source}\u0000${message}`;
        const now = inner.host.nowMs();
        const was = inner.reported.get(key);
        if (was === undefined || now - was > 60_000) {
          inner.reported.set(key, now);
          const span = inner.tracer.always("client.error", Kind.Internal);
          span.set("stillfail.source", call.source);
          span.set("error.type", "client");
          span.set("exception.message", [...message].slice(0, 1000).join(""));
          span.fail();
          span.end();
        }
        return Effect.succeed({});
      }
      case "signOut":
        return Effect.as(inner.accounts.signOut(call.account), null);
      // The account deleted in the cloud (DELETE /v1/me), then forgotten here as signing out does.
      case "deleteAccount":
        return Effect.as(Effect.andThen(inner.provider.request(call.account, "DELETE", "/v1/me", null), inner.accounts.signOut(call.account)), null);
      case "pushKey":
        return inner.provider.pushKey();
      case "op":
        if ("cloud" in call.op.target) {
          const op = call.op;
          const sub = call.op.target.cloud;
          return Effect.gen(function* () {
            const made = op.method === "POST" && op.path === "/v1/workspaces";
            // Taken out of a locked workspace, or a member's role changed: so in its lock too, or it would be the cloud's
            // word alone (it could hold back a credential's end, let one back in, and the lock would still take them as
            // it says, an admin made a member signing as an admin there still).
            const roster = rosterOf(op.method, op.path, op.body);
            const signed = roster && hooks.roster ? yield* hooks.roster(inner, sub, roster.ws, roster.what) : null;
            const adding = op.method === "POST" ? /^\/v1\/workspaces\/([^/]+)\/members$/.exec(op.path) : null;
            const enrolling = op.method === "POST" ? /^\/v1\/workspaces\/([^/]+)\/enrollments$/.exec(op.path) : null;
            // The roster's writes end by CLOUD_WRITE_MS. One whose lock's entry is pending (no station took it) and that
            // fails here leaves nothing changed: that entry is dropped too, as the failure says (nothing saved).
            const asked = inner.provider.request(sub, op.method, op.path, op.body, ctx);
            const bounded = roster || adding || enrolling
              ? Effect.flatMap(Effect.timeoutOption(asked, CLOUD_WRITE_MS), (o) => (o._tag === "Some" ? Effect.succeed(o.value) : Effect.fail(cloudSilent()))) // timer: a deadline on what a call waits for
              : asked;
            const pendingId = isObject(signed) && isObject(signed.pending) && typeof signed.pending.id === "string" ? signed.pending.id : null;
            let result = yield* (pendingId !== null && roster ? Effect.tapError(bounded, () => Effect.sync(() => hooks.pendingDrop?.(inner, roster.ws, pendingId))) : bounded);
            // The lock's entry pending (no station took it): the answer says so, the cloud's with its row as `pending`
            // (`LockPending`), which the app says in place of its done words.
            const pendingRow = (said: unknown) => (isObject(said) && isObject(said.pending) ? said.pending : null);
            const withPending = (row: unknown) => (row === null ? result : { ...(isObject(result) ? result : {}), pending: row });
            if (roster) result = withPending(pendingRow(signed));
            // People added: so in a locked workspace's lock too, with the role given (views/lock.ts `added`).
            if (adding && hooks.added) {
              const role = isObject(op.body) && typeof op.body.role === "string" ? op.body.role : "member";
              result = withPending(pendingRow(yield* hooks.added(inner, sub, decodeURIComponent(adding[1]!), role, result)));
            }
            // A locked workspace's station joins with the lock's hash, to pin it (views/lock.ts).
            if (enrolling && hooks.enrolled) result = yield* hooks.enrolled(inner, sub, decodeURIComponent(enrolling[1]!), result);
            // A workspace made: the invite code kept through signing in is done with.
            if (made) prefs.inviteUsed(inner.data);
            // A write may rename, join or leave a workspace: what the account's topics show is read again first, for a
            // while (`REREAD_WAIT_MS`): the write is done, and the topics follow as they are read.
            if (op.method !== "GET") yield* rereadAfterWrite(inner, inner.cloudSync.refreshAll(), ctx);
            // An answer on a bug report: its replies read again (the cloud says so too, on the events socket).
            const answered = op.method === "POST" ? /^\/v1\/workspaces\/([^/]+)\/feedback\//.exec(op.path) : null;
            if (answered) inner.cloudSync.feedbackChanged(decodeURIComponent(answered[1]!));
            return result;
          });
        }
        break;
      case "prefsSet":
        return Effect.try({
          try: () => {
            prefs.set(inner.data, call.patch, call.fill, inner.host.nowMs());
            // (what is brought after everything else goes by these two, fill.ts `bounds`: looked at again only for
            // them, not for every pref set: the workspace switched to waited on it, the chats' list behind it)
            if (isObject(call.patch) && ("fillOff" in call.patch || "fillMax" in call.patch)) inner.fill?.poke();
            return null;
          },
          catch: asCoreError,
        });
      case "keysSet":
        return Effect.try({
          try: () => {
            const { patch, moved, said } = keymap.change(inner.data.shared({ topic: "prefs" }), call.action, call.keys);
            prefs.set(inner.data, { keys: patch }, false, inner.host.nowMs());
            return { moved, said };
          },
          catch: asCoreError,
        });
      case "clientDevice":
        return Effect.try({
          try: () => {
            prefs.device(inner.data, call.facts);
            inner.adb.deviceTold();
            hooks.device?.(inner, call.facts);
            const build = isObject(call.facts) ? call.facts.build : undefined;
            if (typeof build === "string" && build.trim() !== "") inner.tracer.setVersion(build.trim());
            return null;
          },
          catch: asCoreError,
        });
      case "stationUpdateNotice":
        if (call.action === "dismiss") {
          prefs.dismissStationUpdate(inner.data, call.station, call.version!);
        }
        hooks.updateNoticeOpen?.(inner, call.station, call.action === "open");
        return Effect.succeed({});
      case "codeInk":
        return Effect.succeed({ ink: inkKept(call.code, call.lang) });
      case "markdown":
        return Effect.succeed({ md: markdown(call.text) });
      case "readerBook": {
        const { id, book } = keepBook(call.text, call.markdown);
        return Effect.succeed(bookAnswer(id, book, call.text, call));
      }
      case "readerText": {
        const book = keptBook(call.id);
        if (!book) return Effect.fail(CoreError.invalid(t("core-misc.reader.gone")));
        return Effect.succeed(new Beside({ length: book.text.length }, new TextEncoder().encode(book.text)));
      }
      case "readerSearch": {
        const book = keptBook(call.id);
        if (!book) return Effect.fail(CoreError.invalid(t("core-misc.reader.gone")));
        return Effect.succeed({ at: searchBook(book, call.query, call.limit) });
      }
      case "draftPut": {
        return Effect.succeed(inner.composers.putDraft(call.station, call.chat, call.draft));
      }
      case "draftGet": {
        return Effect.succeed(inner.composers.readDraft(call.station, call.chat));
      }
      case "migrate":
        return Effect.gen(function* () {
          if (call.accounts !== null) yield* inner.accounts.migrate(call.accounts);
          if (call.device !== null && handlers.migrateDevice) yield* handlers.migrateDevice(inner, call, progress, at, ctx);
          return null;
        });
    }
    const handler = handlers[call.kind];
    if (handler) return handler(inner, call, progress, at, ctx);
    return Effect.fail(new CoreError("unsupported", `not in the TS core yet: ${call.kind}`));
  });
}
