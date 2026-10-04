// The calls that change a chat (core/execute.rs, the views' part): sending, making a chat, answering a card, renaming,
// pinning, archiving. Each takes effect here at once (local.ts: the outbox, a chat asked for, a change laid over its
// row) and answers once its station has it; nothing a person does waits on the network to show (rule 4). What was on
// its way when the core stopped goes on as it starts again, under the same idempotency key.
import { Effect } from "effect";
import type { Inner } from "../core.ts";
import { handlers, hooks } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import * as decisions from "../decisions.ts";
import { CoreError, asCoreError } from "../error.ts";
import { t } from "../i18n.ts";
import * as ops from "../ops.ts";
import * as prefs from "../prefs.ts";
import * as refs from "../refs.ts";
import type { SpanContext } from "../trace.ts";
import { StationAddr } from "../station/addr.ts";
import { arr as arrU, get as getU, hex } from "../util.ts";
import { PENDING_PREFIX, sentAs } from "./local.ts";
import type { Views } from "./views.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

type Of<K extends Call["kind"]> = Extract<Call, { kind: K }>;

/// An operation by name, its params checked.
const request = (name: string, params: unknown) =>
  Effect.flatMap(Effect.try({ try: () => ops.request(name, params), catch: asCoreError }), (op) => (op === null ? Effect.fail(CoreError.invalid(name)) : Effect.succeed(op)));

/// A call's result, back as its effect.
const settle = <A>(r: { _tag: "Success"; success: A } | { _tag: "Failure"; failure: CoreError }): Effect.Effect<A, CoreError> =>
  r._tag === "Success" ? Effect.succeed(r.success) : Effect.fail(r.failure);

const parse = (station: string) => Effect.try({ try: () => StationAddr.parse(station), catch: asCoreError });

/// What goes out of a message written here, with the key that makes it go once however often it is sent.
function outgoing(inner: Inner, station: string, text: string, attachments: unknown, quotes: unknown, client: string | null): J {
  const key = new Uint8Array(16);
  inner.host.randomBytes(key);
  const message: J = { text: refs.expand(inner.data, station, text), attachments, quotes, idem: hex(key) };
  const from = client ?? prefs.sentFrom(inner.data);
  if (from !== null && from !== "") message.client = from;
  return message;
}

export class ViewCalls {
  readonly #inner: Inner;
  readonly #views: Views;

  constructor(inner: Inner, views: Views) {
    this.#inner = inner;
    this.#views = views;
  }

  get #local() {
    return this.#views.local;
  }

  /// Posts an outgoing message into a chat: it leaves the outbox as the chat's entries reach it; a failure leaves it
  /// there as `failed`.
  deliver(station: string, thread: number, id: string, ctx: SpanContext | null): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const entry = this.#local.outboxGet(station, thread, id);
      if (entry === undefined) return yield* Effect.fail(CoreError.invalid(t("core-misc.call.no_outbox")));
      const result = yield* Effect.result(Effect.andThen(parse(station), this.#inner.stations.post(station, thread, sentAs(entry), ctx, typeof entry.idem === "string" ? entry.idem : undefined)));
      if (result._tag === "Success") {
        this.#views.outboxSent(station, thread, id, result.success);
        return { seq: result.success };
      }
      this.#local.outboxState(station, thread, id, result.failure.message);
      return yield* Effect.fail(result.failure);
    });
  }

  /// Asks the station for a chat asked for here; once made, what waited for it goes, in order.
  makeChat(key: string): void {
    const tried = this.#local.pendingTry(key);
    if (tried === null) return;
    const [station, ask] = tried;
    this.#inner.runner.fork(
      Effect.gen({ self: this }, function* () {
        const made = yield* Effect.result(
          Effect.gen({ self: this }, function* () {
            yield* parse(station);
            // What the new chat changes (the lists, the footprint) is read again beside what waited for it, not before.
            const op: ops.Request = { target: { station }, method: "POST", path: "/sessions", body: ask, fallback: null, effect: { kind: "none" } };
            const answer = yield* this.#inner.stations.perform(op, null);
            const session = get(answer, "key");
            const thread = get(get(answer, "thread"), "id");
            if (typeof session !== "string" || typeof thread !== "number") return yield* Effect.fail(new CoreError("bad_response", t("core-misc.call.no_new_session")));
            return [session, thread, answer] as [string, number, unknown];
          }),
        );
        if (made._tag === "Failure") {
          this.#local.pendingFailed(key, made.failure.message);
          return;
        }
        const [session, thread, answer] = made.success;
        const sends = this.#local.pendingMade(key, session, thread);
        yield* Effect.all(
          [
            this.#inner.stations.afterWrite(station, { kind: "session", key: null }, answer),
            Effect.forEach(sends, ([id]) => Effect.ignore(this.deliver(station, thread, id, null)), { discard: true }),
          ],
          { concurrency: "unbounded", discard: true },
        );
      }),
    );
  }

  /// Asks an agent's station for its chat, behind what was sent to it meanwhile.
  makeFirst(station: string, key: string): void {
    this.#inner.runner.fork(
      Effect.gen({ self: this }, function* () {
        const made = yield* Effect.result(
          Effect.gen({ self: this }, function* () {
            yield* parse(station);
            const op = yield* request("chat.forSession", { station, session: key });
            const answer = yield* this.#inner.stations.perform(op, null);
            const id = get(answer, "id");
            if (typeof id !== "number") return yield* Effect.fail(new CoreError("bad_response", t("core-misc.call.no_chat")));
            return id;
          }),
        );
        if (made._tag === "Failure") {
          this.#local.firstFailed(station, key, made.failure.message);
          return;
        }
        for (const [id] of this.#local.firstMade(station, key, made.success)) yield* Effect.ignore(this.deliver(station, made.success, id, null));
      }),
    );
  }

  /// What was on its way when the core last stopped goes on: messages sent and not answered, chats asked for.
  resume(): void {
    this.#local.forgetUnanswered();
    for (const key of this.#local.unmade()) this.makeChat(key);
    for (const [station, key] of this.#local.firstsMaking()) {
      if (this.#local.firstTry(station, key)) this.makeFirst(station, key);
    }
    for (const [station, thread, list] of this.#local.outboxes()) {
      for (const m of list) {
        if (m.state === "sending" && (m.seq === undefined || m.seq === null)) this.#inner.runner.fork(Effect.ignore(this.deliver(station, thread, String(m.id), null)));
      }
    }
  }

  /// The card a row asks with, still pending: else it was answered already.
  #pendingCard(station: string, thread: number, seq: number): Effect.Effect<J, CoreError> {
    const row = this.#inner.data.chatOfThread(station, thread);
    const card = row !== undefined ? decisions.asked(row) : null;
    return card !== null && get(card, "seq") === seq ? Effect.succeed(card) : Effect.fail(CoreError.invalid(t("core-misc.call.already_answered")));
  }

  install(): void {
    const inner = this.#inner;
    const local = this.#local;
    const views = this.#views;
    const send = (station: string, thread: number, message: J, ctx: SpanContext | null) => {
      const id = views.outboxAdd(station, thread, message);
      return this.deliver(station, thread, id, ctx);
    };
    handlers.chatSend = (_inner, call, _p, _at, ctx) => {
      const c = call as Of<"chatSend">;
      return Effect.andThen(parse(c.station), Effect.suspend(() => send(c.station, c.thread, outgoing(inner, c.station, c.text, c.attachments, c.quotes, c.client), ctx)));
    };
    handlers.chatCreate = (_inner, call) => {
      const c = call as Of<"chatCreate">;
      return Effect.andThen(
        parse(c.station),
        Effect.sync(() => {
          const key = local.pendingNew(c.station, c.ask);
          this.makeChat(key);
          return { key };
        }),
      );
    };
    handlers.chatSendTo = (_inner, call, _p, _at, ctx) => {
      const c = call as Of<"chatSendTo">;
      return Effect.suspend((): Effect.Effect<unknown, CoreError> => {
        const message = outgoing(inner, c.station, c.text, c.attachments, c.quotes, c.client);
        const pending = local.pendingThread(c.station, c.session);
        if (typeof pending === "number") return send(c.station, pending, message, ctx);
        if (pending === null) {
          const failed = local.pendingFailedNow(c.session);
          const id = local.pendingQueue(c.session, message);
          if (id === null) return Effect.fail(CoreError.invalid(t("core-misc.call.no_chat")));
          if (failed) this.makeChat(c.session);
          return Effect.succeed({ id });
        }
        if (c.session.startsWith(PENDING_PREFIX)) return Effect.fail(CoreError.invalid(t("core-misc.call.no_chat")));
        const bound = local.firstWaits(c.station, c.session) ? null : views.boundThread(c.station, c.session);
        if (bound !== null) return send(c.station, bound, message, ctx);
        const [id, ask] = local.firstQueue(c.station, c.session, message);
        if (ask) this.makeFirst(c.station, c.session);
        return Effect.succeed({ id });
      });
    };
    handlers.chatRetry = (_inner, call, _p, _at, ctx) => {
      const c = call as Of<"chatRetry">;
      return Effect.suspend(() => {
        if (local.outboxGet(c.station, c.thread, c.id) === undefined) return Effect.fail(CoreError.invalid(t("core-misc.call.no_outbox")));
        local.outboxState(c.station, c.thread, c.id, null);
        return this.deliver(c.station, c.thread, c.id, ctx);
      });
    };
    handlers.chatDiscard = (_inner, call) => {
      const c = call as Of<"chatDiscard">;
      return Effect.sync(() => {
        local.outboxRemove(c.station, c.thread, c.id);
        return null;
      });
    };
    handlers.chatRetryIn = (_inner, call, progress, at, ctx) => {
      const c = call as Of<"chatRetryIn">;
      return Effect.suspend((): Effect.Effect<unknown, CoreError> => {
        const pending = local.pendingThread(c.station, c.session);
        if (typeof pending === "number") return handlers.chatRetry!(inner, { kind: "chatRetry", station: c.station, thread: pending, id: c.id }, progress, at, ctx);
        if (pending === null) {
          this.makeChat(c.session);
          return Effect.succeed(null);
        }
        if (local.firstWaits(c.station, c.session)) {
          if (local.firstTry(c.station, c.session)) this.makeFirst(c.station, c.session);
          return Effect.succeed(null);
        }
        return Effect.fail(CoreError.invalid(t("core-misc.call.no_chat")));
      });
    };
    handlers.chatDiscardIn = (_inner, call) => {
      const c = call as Of<"chatDiscardIn">;
      return Effect.suspend((): Effect.Effect<unknown, CoreError> => {
        const pending = local.pendingThread(c.station, c.session);
        if (typeof pending === "number") local.outboxRemove(c.station, pending, c.id);
        else if (pending === null) local.pendingDiscard(c.session, c.id);
        else if (local.firstWaits(c.station, c.session)) local.firstDiscard(c.station, c.session, c.id);
        else return Effect.fail(CoreError.invalid(t("core-misc.call.no_chat")));
        return Effect.succeed(null);
      });
    };
    handlers.chatArchive = (_inner, call, progress, at, ctx) => {
      const c = call as Of<"chatArchive">;
      return Effect.gen(function* () {
        if (!("station" in c.op.target)) return yield* Effect.fail(CoreError.invalid(t("core-misc.params.station")));
        const station = c.op.target.station;
        if (c.archived) local.archiving(station, c.thread, c.session, true);
        const change = local.changing(station, c.thread, c.session, {}, c.archived);
        const result = yield* Effect.result(handlers.op!(inner, { kind: "op", op: c.op }, progress, at, ctx));
        if (c.archived) local.archiving(station, c.thread, c.session, false);
        local.changed(change, result._tag === "Success", inner.data.rowsRev(station));
        return yield* settle(result);
      });
    };
    handlers.chatChange = (_inner, call, progress, at, ctx) => {
      const c = call as Of<"chatChange">;
      return Effect.gen(function* () {
        if (!("station" in c.op.target)) return yield* Effect.fail(CoreError.invalid(t("core-misc.params.station")));
        const station = c.op.target.station;
        const row: Record<string, unknown> = {};
        if (c.title !== null) row.title = c.title;
        if (c.pinned !== null) row.pinned = c.pinned ? inner.host.nowMs() : null;
        if (c.keep) row.archiveReminderDismissed = true;
        const change = local.changing(station, c.thread, c.session, row, null);
        const result = yield* Effect.result(handlers.op!(inner, { kind: "op", op: c.op }, progress, at, ctx));
        local.changed(change, result._tag === "Success", inner.data.rowsRev(station));
        return yield* settle(result);
      });
    };
    handlers.decisionAnswer = (_inner, call, progress, at, ctx) => {
      const c = call as Of<"decisionAnswer">;
      const self = this;
      return Effect.gen(function* () {
        const card = yield* self.#pendingCard(c.station, c.thread, c.seq);
        const answer = decisions.answer(card, c.option);
        if (answer === null) return yield* Effect.fail(CoreError.invalid(t("core-misc.call.no_option")));
        prefs.undeferDecision(inner.data, decisions.deferralKey(c.station, c.thread, c.seq));
        if (decisions.closes(card, c.option)) {
          const op = yield* request("decision.close", { station: c.station, thread: c.thread, seq: c.seq, option: c.option });
          const change = local.changing(c.station, c.thread, "", { card: null, decision: null }, null);
          const result = yield* Effect.result(handlers.op!(inner, { kind: "op", op }, progress, at, ctx));
          local.changed(change, result._tag === "Success", inner.data.rowsRev(c.station));
          return yield* settle(result);
        }
        const [text, quotes] = answer;
        return yield* send(c.station, c.thread, outgoing(inner, c.station, text, [], quotes, null), ctx);
      });
    };
    handlers.decisionReply = (_inner, call, _p, _at, ctx) => {
      const c = call as Of<"decisionReply">;
      const self = this;
      return Effect.gen(function* () {
        const card = yield* self.#pendingCard(c.station, c.thread, c.seq);
        const extras = arr(c.attachments).length > 0 || arr(c.quotes).length > 0;
        const reply = decisions.reply(card, c.text, extras);
        if (reply === null) return yield* Effect.fail(CoreError.invalid(t("core-misc.call.reply_in_chat")));
        const [text, quotes] = reply;
        prefs.undeferDecision(inner.data, decisions.deferralKey(c.station, c.thread, c.seq));
        return yield* send(c.station, c.thread, outgoing(inner, c.station, text, c.attachments, [...quotes, ...arr(c.quotes)], null), ctx);
      });
    };
    handlers.chatRef = (_inner, call) => {
      const c = call as Of<"chatRef">;
      return Effect.sync(() => ({ mark: refs.mark(inner.data, c.base ?? inner.host.cloudOrigin(), c.station, c.id, c.title) }));
    };
    handlers.chatRefsKeep = (_inner, call) => {
      const c = call as Of<"chatRefsKeep">;
      return Effect.sync(() => {
        refs.keep(inner.data, c.links);
        return null;
      });
    };
    handlers.profileModels = (_inner, call, progress, at, ctx) => {
      const c = call as Of<"profileModels">;
      return Effect.gen(function* () {
        if (!("station" in c.op.target)) return yield* Effect.fail(CoreError.invalid(t("core-misc.params.missing_station")));
        const station = c.op.target.station;
        if (!inner.data.beginModels(station, c.id, c.models)) return yield* Effect.fail(CoreError.invalid(t("core-misc.call.models_saving")));
        const result = yield* Effect.result(handlers.op!(inner, { kind: "op", op: c.op }, progress, at, ctx));
        inner.data.endModels(station, c.id);
        return yield* settle(result);
      });
    };
    hooks.updateNoticeOpen = (_inner, station, open) => views.updateNoticeOpen(station, open);
  }
}
