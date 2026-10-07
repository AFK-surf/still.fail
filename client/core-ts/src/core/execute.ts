// Execution of named client calls (core/execute.rs), as Effects. What changes something takes effect in the core at
// once and answers when its source has it (rule 4); a write to still.fail cloud answers once what it changed is read
// again (the account topics show it).
import { Effect } from "effect";
import { Accounts } from "../accounts.ts";
import * as brand from "../brand.ts";
import type { Inner, Progress } from "../core.ts";
import { CoreError, asCoreError } from "../error.ts";
import * as prefs from "../prefs.ts";
import type { ClientId, RequestId } from "../protocol.ts";
import type { SpanContext } from "../trace.ts";
import { Kind } from "../trace.ts";
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
} = {};

/// Runs a call; `at` is the client and id it came with, `ctx` its trace.
export function execute(inner: Inner, call: Call, progress: Progress, at: [ClientId, RequestId], ctx: SpanContext): Effect.Effect<unknown, CoreError> {
  return Effect.suspend((): Effect.Effect<unknown, CoreError> => {
    switch (call.kind) {
      case "authBegin": {
        const deviceName = call.deviceName ?? prefs.deviceName(inner.data) ?? brand.name();
        return Effect.map(inner.accounts.beginSignIn(call.redirectUri, call.returnTo, deviceName), (url) => ({ url }));
      }
      case "authComplete":
        return Effect.map(inner.accounts.completeSignIn(call.query), ([account, returnTo]) => ({ account, return_to: returnTo }));
      case "appleBegin":
      case "appleComplete":
      case "deletionSummary":
      case "deleteAccount": {
        const accounts = inner.accounts;
        if (!(accounts instanceof Accounts)) return Effect.fail(new CoreError("unsupported", "当前账号服务不支持此操作"));
        switch (call.kind) {
          case "appleBegin": return accounts.appleBegin();
          case "appleComplete": return accounts.appleComplete(call.attempt, call.identityToken, call.authorizationCode, call.name, call.state);
          case "deletionSummary": return accounts.deletionSummary(call.account);
          case "deleteAccount": return accounts.deleteAccount(call.account);
        }
      }
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
      case "pushKey":
        return inner.provider.pushKey();
      case "op":
        if ("cloud" in call.op.target) {
          const op = call.op;
          const sub = call.op.target.cloud;
          return Effect.gen(function* () {
            const made = op.method === "POST" && op.path === "/v1/workspaces";
            const result = yield* inner.provider.request(sub, op.method, op.path, op.body, ctx);
            // A workspace made: the invite code kept through signing in is done with.
            if (made) prefs.inviteUsed(inner.data);
            // A write may rename, join or leave a workspace: what the account's topics show is read again first.
            if (op.method !== "GET") yield* inner.cloudSync.refreshAll();
            return result;
          });
        }
        break;
      case "prefsSet":
        return Effect.try({ try: () => (prefs.set(inner.data, call.patch, call.fill, inner.host.nowMs()), null), catch: asCoreError });
      case "clientDevice":
        return Effect.try({
          try: () => {
            prefs.device(inner.data, call.facts);
            hooks.device?.(inner, call.facts);
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
      case "decisionDefer":
        prefs.deferDecision(inner.data, `${call.station}\t${call.thread}\t${call.seq}`, inner.host.nowMs());
        return Effect.succeed(null);
      case "draftPut": {
        const topic = { topic: "draft", station: call.station, chat: call.chat };
        const draft = call.draft;
        const empty = (field: string) => {
          const v = isObject(draft) ? draft[field] : undefined;
          return v === undefined || (typeof v === "string" && v.trim() === "") || (Array.isArray(v) && v.length === 0);
        };
        if (empty("text") && empty("quotes") && empty("files")) inner.data.forgetTopic(topic);
        else inner.data.setSoon(topic, draft);
        return Effect.succeed(null);
      }
      case "draftGet": {
        const v = inner.data.get({ topic: "draft", station: call.station, chat: call.chat });
        return Effect.succeed(v === undefined ? { text: "", quotes: [], files: [] } : v);
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
