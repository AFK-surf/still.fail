// Execution of named client calls (core/execute.rs), as Effects. What changes something takes effect in the core at
// once and answers when its source has it (rule 4); a write to still.fail cloud answers once what it changed is read
// again (the account topics show it).
import { Effect } from "effect";
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
import { isObject } from "../util.ts";
import { Wake } from "../wake.ts";
import type { Call } from "./calls.ts";

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
  lockRefused?: (inner: Inner, workspace: string, station: string, theirs: unknown) => CoreError | null;
  lockWaiting?: (inner: Inner, workspace: string, station: string) => CoreError | null;
  /// A new device's connection, met face to face (views/pair.ts).
  lockPair?: (inner: Inner, connection: import("../iroh.ts").IrohConnection) => void;
} = {};

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
        return Effect.succeed({});
      }
      case "clientError": {
        const key = `${call.source}\u0000${call.message}`;
        const now = inner.host.nowMs();
        const was = inner.reported.get(key);
        if (was === undefined || now - was > 60_000) {
          inner.reported.set(key, now);
          const span = inner.tracer.always("client.error", Kind.Internal);
          span.set("stillfail.source", call.source);
          span.set("error.type", "client");
          span.set("exception.message", [...call.message].slice(0, 1000).join(""));
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
            let result = yield* inner.provider.request(sub, op.method, op.path, op.body, ctx);
            // A locked workspace's station joins with the lock's hash, to pin it (views/lock.ts).
            const enrolling = op.method === "POST" ? /^\/v1\/workspaces\/([^/]+)\/enrollments$/.exec(op.path) : null;
            if (enrolling && hooks.enrolled) result = yield* hooks.enrolled(inner, sub, decodeURIComponent(enrolling[1]!), result);
            // A workspace made: the invite code kept through signing in is done with.
            if (made) prefs.inviteUsed(inner.data);
            // A write may rename, join or leave a workspace: what the account's topics show is read again first.
            if (op.method !== "GET") yield* inner.cloudSync.refreshAll();
            return result;
          });
        }
        break;
      case "prefsSet":
        // (what is brought after everything else goes by them: fill.ts)
        return Effect.try({ try: () => (prefs.set(inner.data, call.patch, call.fill, inner.host.nowMs()), inner.fill?.poke(), null), catch: asCoreError });
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
          inner.store.invalidate({ topic: "prefs" });
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
      case "module":
        return call.call.def.run(call.call.params, { progress, client: at[0], id: at[1], trace: ctx });
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
