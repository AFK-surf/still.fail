// The forms' topics and calls (core/routing.rs, core/execute.rs for the forms in forms.ts).
import { Effect } from "effect";
import type { Inner } from "./core.ts";
import { handlers } from "./core/execute.ts";
import type { Call } from "./core/calls.ts";
import type { Owner } from "./core/routing.ts";
import { CoreError, asCoreError } from "./error.ts";
import { ConnectFlows, DecisionForms, ProfileFlows, Tokens, tokensOf } from "./forms.ts";
import { t } from "./i18n.ts";
import * as ops from "./ops.ts";
import type { ClientId, Topic } from "./protocol.ts";
import type { Value } from "./store.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const FORMS = new Set(["decisionForm", "profileFlow", "connectFlow", "slackTokens"]);

export class Forms implements Owner {
  readonly decisions: DecisionForms;
  readonly profiles: ProfileFlows;
  readonly tokens: Tokens;
  readonly connects: ConnectFlows;

  constructor(inner: Inner) {
    this.decisions = new DecisionForms(inner.store);
    this.profiles = new ProfileFlows(inner.store);
    this.tokens = new Tokens();
    this.connects = new ConnectFlows(
      inner.store,
      (topic) => inner.choose.compute(topic),
      (station, form) => {
        try {
          inner.choose.set(station, `connect-new:${form}`, { clear: true });
        } catch {
          // A form not known: nothing to clear.
        }
      },
    );
  }

  owns(topic: Topic): boolean {
    return FORMS.has(topic.topic);
  }

  compute(topic: Topic): Value | undefined {
    try {
      switch (topic.topic) {
        case "decisionForm":
          return { ok: this.decisions.value(topic) };
        case "profileFlow":
          return { ok: this.profiles.value(topic) };
        case "connectFlow":
          return { ok: this.connects.value(topic) };
        default:
          return { ok: this.tokens.value(topic) };
      }
    } catch (e) {
      return { err: asCoreError(e) };
    }
  }

  /// A UI went away: its forms go with it.
  disconnect(inner: Inner, client: ClientId): void {
    this.decisions.disconnect(client);
    this.profiles.disconnect(client);
    this.connects.disconnect(client);
    this.tokens.disconnect(client);
    inner.store.invalidateAll((t) => FORMS.has(t.topic));
  }
}

const attempt = <A>(f: () => A) => Effect.try({ try: f, catch: asCoreError });
const request = (name: string, params: unknown) =>
  Effect.flatMap(attempt(() => ops.request(name, params)), (op) => (op === null ? Effect.fail(CoreError.invalid(name)) : Effect.succeed(op)));

export function installForms(inner: Inner): Forms {
  const forms = new Forms(inner);
  inner.router.owners.push(forms);
  const perform = (op: ops.Request, ctx: J) => inner.stations.perform(op, ctx);
  handlers.decisionForm = (_i, call, _p, at, ctx) => {
    const c = call as Extract<Call, { kind: "decisionForm" }>;
    if (["open", "edit", "drop"].includes(c.action)) return attempt(() => forms.decisions.change(c.topic, at[0], c.action, c.patch));
    return Effect.gen(function* () {
      const input = yield* attempt(() => forms.decisions.begin(c.topic, at[0]));
      const answer = yield* Effect.result(Effect.flatMap(request("automaticDecisions.save", { station: c.topic.station, input }), (op) => perform(op, ctx)));
      forms.decisions.finish(c.topic, at[0], answer._tag === "Success");
      if (answer._tag === "Failure") return yield* Effect.fail(answer.failure);
      return answer.success;
    });
  };
  handlers.profileFlow = (_i, call, _p, at, ctx) => {
    const c = call as Extract<Call, { kind: "profileFlow" }>;
    if (["open", "edit", "drop"].includes(c.action)) return attempt(() => forms.profiles.change(c.topic, at[0], c.action, c.patch));
    return Effect.gen(function* () {
      const input = yield* attempt(() => forms.profiles.begin(c.topic, at[0]));
      input.station = c.topic.station;
      const answer = yield* Effect.result(Effect.flatMap(request("profile.add", input), (op) => perform(op, ctx)));
      forms.profiles.finish(c.topic, at[0], answer._tag === "Failure" ? answer.failure : null);
      if (answer._tag === "Failure") return yield* Effect.fail(answer.failure);
      return answer.success;
    });
  };
  handlers.connectFlow = (_i, call, _p, at, ctx) => {
    const c = call as Extract<Call, { kind: "connectFlow" }>;
    const station = c.topic.station as string;
    const tokenTopic = tokensOf(station, c.topic.form as string);
    const patch: J = c.patch;
    return Effect.gen(function* () {
      switch (c.action) {
        case "open":
          yield* attempt(() => forms.connects.open(c.topic, at[0], patch));
          yield* attempt(() => forms.tokens.edit(tokenTopic, at[0], {}));
          break;
        case "drop":
          forms.connects.drop(c.topic, at[0]);
          forms.tokens.drop(tokenTopic, at[0]);
          inner.store.invalidate(tokenTopic);
          return {};
        case "edit":
          yield* attempt(() => forms.connects.edit(c.topic, at[0], patch));
          break;
        case "go":
          return yield* attempt(() => forms.connects.go(c.topic, at[0], typeof patch?.to === "string" ? patch.to : ""));
        default: {
          const view = yield* attempt(() => forms.connects.value(c.topic));
          yield* attempt(() => forms.tokens.edit(tokenTopic, at[0], { install: view?.made?.state ?? null }));
          const [input, verified] = yield* attempt(() => forms.tokens.input(tokenTopic, at[0]));
          const [generation, name, params] = yield* attempt(() => forms.connects.begin(c.topic, at[0], c.action, input, verified));
          let revision: number | null = null;
          if (c.action === "verify") {
            const begun = yield* Effect.result(attempt(() => forms.tokens.begin(tokenTopic, at[0])));
            if (begun._tag === "Failure") {
              forms.connects.finish(c.topic, generation, c.action, { err: begun.failure });
              return yield* Effect.fail(begun.failure);
            }
            revision = begun.success[0];
          }
          const answer = yield* Effect.result(Effect.flatMap(request(name, params), (op) => perform(op, ctx)));
          const result = answer._tag === "Success" ? { ok: answer.success } : { err: answer.failure };
          let current = true;
          if (revision !== null) {
            current = forms.tokens.finish(tokenTopic, revision, result);
            inner.store.invalidate(tokenTopic);
          }
          const transition = current ? result : { err: CoreError.invalid(t("core-misc.connect.token_changed")) };
          if (!forms.connects.finish(c.topic, generation, c.action, transition)) return yield* Effect.fail(CoreError.invalid(t("core-misc.connect.closed")));
          if (answer._tag === "Failure") return yield* Effect.fail(answer.failure);
          return answer.success;
        }
      }
      inner.store.invalidate(c.topic);
      return yield* attempt(() => forms.connects.value(c.topic));
    });
  };
  handlers.slackTokens = (_i, call, _p, at, ctx) => {
    const c = call as Extract<Call, { kind: "slackTokens" }>;
    return Effect.gen(function* () {
      if (c.action === "edit") yield* attempt(() => forms.tokens.edit(c.topic, at[0], c.patch));
      else if (c.action === "drop") forms.tokens.drop(c.topic, at[0]);
      else {
        const [revision, input, verified] = yield* attempt(() => forms.tokens.begin(c.topic, at[0]));
        if (verified) return true;
        input.station = c.topic.station;
        const answer = yield* Effect.result(Effect.flatMap(request("slack.verify", input), (op) => perform(op, ctx)));
        const ok = forms.tokens.finish(c.topic, revision, answer._tag === "Success" ? { ok: answer.success } : { err: answer.failure });
        inner.store.invalidate(c.topic);
        if (answer._tag === "Failure") return yield* Effect.fail(answer.failure);
        return ok;
      }
      inner.store.invalidate(c.topic);
      return forms.tokens.value(c.topic);
    });
  };
  return forms;
}
