// Execution of named client calls (core/execute.rs).
import * as brand from "../brand.ts";
import type { Inner, Progress } from "../core.ts";
import { CoreError, asCoreError } from "../error.ts";
import { t } from "../i18n.ts";
import * as prefs from "../prefs.ts";
import type { ClientId, RequestId } from "../protocol.ts";
import type { SpanContext } from "../trace.ts";
import { Kind } from "../trace.ts";
import { isObject, parseJson } from "../util.ts";
import { Wake } from "../wake.ts";
import * as accountState from "./account_state.ts";
import type { Call } from "./calls.ts";

/// What later parts of the core execute (station calls, views, choose, attend…): each module adds its kinds here.
export const handlers: Partial<Record<Call["kind"], (inner: Inner, call: Call, progress: Progress, at: [ClientId, RequestId], ctx: SpanContext, signal: AbortSignal) => Promise<unknown>>> = {};

/// Runs a call; `at` is the client and id it came with, `ctx` its trace.
export async function execute(inner: Inner, call: Call, progress: Progress, at: [ClientId, RequestId], ctx: SpanContext, signal: AbortSignal): Promise<unknown> {
  switch (call.kind) {
    case "authBegin": {
      const deviceName = call.deviceName ?? prefs.deviceName(inner.data) ?? brand.name();
      const url = await inner.accounts.beginSignIn(call.redirectUri, call.returnTo, deviceName);
      return { url };
    }
    case "authComplete": {
      const [account, returnTo] = await inner.accounts.completeSignIn(call.query);
      return { account, return_to: returnTo };
    }
    case "wake": {
      const wake = new Wake(inner.host.nowMs(), Math.max(call.away, 0), call.network && !call.retry, call.retry);
      // What is asked again as the wake fails what was under way goes on new connections.
      if (wake.suspectsConnections()) inner.host.resetConnections();
      inner.wakes.wake(wake);
      return {};
    }
    case "clientError": {
      const key = `${call.source}\u0000${call.message}`;
      const now = inner.host.nowMs();
      const at = inner.reported.get(key);
      const fresh = at === undefined || now - at > 60_000;
      if (fresh) {
        inner.reported.set(key, now);
        const span = inner.tracer.always("client.error", Kind.Internal);
        span.set("stillfail.source", call.source);
        span.set("error.type", "client");
        span.set("exception.message", [...call.message].slice(0, 1000).join(""));
        span.fail();
        span.end();
      }
      return {};
    }
    case "signOut":
      await inner.accounts.signOut(call.account);
      return null;
    case "pushKey": {
      let response;
      try {
        response = await inner.host.fetch({ method: "GET", url: `${inner.host.cloudOrigin()}/v1/push/key`, headers: [], body: null });
      } catch (e) {
        throw asCoreError(e);
      }
      const data = parseJson(response.body);
      const vapid = isObject(data) ? data.vapid : undefined;
      if (typeof vapid === "string" && response.status === 200) return { vapid };
      throw new CoreError("push_unavailable", t("core-misc.call.push_unavailable", { brand: brand.name() }));
    }
    case "op":
      if ("cloud" in call.op.target) {
        const op = call.op;
        const made = op.method === "POST" && op.path === "/v1/workspaces";
        const result = await inner.cloud.request(call.op.target.cloud, op.method, op.path, op.body, ctx);
        // A workspace made: the invite code kept through signing in is done with.
        if (made) prefs.inviteUsed(inner.data);
        // A write may rename, join or leave a workspace: what the account topics show changed too.
        if (op.method !== "GET") await accountState.refreshAll(inner);
        return result;
      }
      break;
    case "prefsSet":
      prefs.set(inner.data, call.patch, call.fill, inner.host.nowMs());
      return null;
    case "decisionDefer":
      prefs.deferDecision(inner.data, `${call.station}\t${call.thread}\t${call.seq}`, inner.host.nowMs());
      return null;
    case "draftPut": {
      const topic = { topic: "draft", station: call.station, chat: call.chat };
      const draft = call.draft;
      const empty = (field: string) => {
        const v = isObject(draft) ? draft[field] : undefined;
        return v === undefined || (typeof v === "string" && v.trim() === "") || (Array.isArray(v) && v.length === 0);
      };
      if (empty("text") && empty("quotes") && empty("files")) inner.data.forgetTopic(topic);
      else inner.data.setSoon(topic, draft);
      return null;
    }
    case "draftGet": {
      const v = inner.data.get({ topic: "draft", station: call.station, chat: call.chat });
      return v === undefined ? { text: "", quotes: [], files: [] } : v;
    }
    case "migrate":
      if (call.accounts !== null) await inner.accounts.migrate(call.accounts);
      if (call.device !== null) {
        const handler = handlers.migrate;
        if (handler) await handler(inner, call, progress, at, ctx, signal);
      }
      return null;
  }
  const handler = handlers[call.kind];
  if (handler) return handler(inner, call, progress, at, ctx, signal);
  throw new CoreError("unsupported", `not in the TS core yet: ${call.kind}`);
}
