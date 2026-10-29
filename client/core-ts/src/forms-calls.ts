// The forms' topics and calls (core/routing.rs, core/execute.rs for the forms in forms.ts).
import { Effect } from "effect";
import type { Inner } from "./core.ts";
import { handlers } from "./core/execute.ts";
import type { Call } from "./core/calls.ts";
import type { Owner } from "./core/routing.ts";
import { CoreError, asCoreError } from "./error.ts";
import { AgentEnvForms } from "./agent-env.ts";
import { ConnectFlows, DecisionForms, PolicyForms, ProfileFlows, Tokens, tokensOf } from "./forms.ts";
import { t } from "./i18n.ts";
import * as ops from "./ops.ts";
import type { ClientId, Topic } from "./protocol.ts";
import type { Value } from "./store.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const FORMS = new Set(["decisionForm", "policyForm", "agentEnvForm", "profileFlow", "connectFlow", "slackTokens"]);

export class Forms implements Owner {
  readonly decisions: DecisionForms;
  readonly policies: PolicyForms;
  readonly agentEnv: AgentEnvForms;
  readonly profiles: ProfileFlows;
  readonly tokens: Tokens;
  readonly connects: ConnectFlows;

  constructor(inner: Inner) {
    this.decisions = new DecisionForms(inner.store);
    this.policies = new PolicyForms(inner.store);
    this.agentEnv = new AgentEnvForms(inner.store);
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
      {
        // A Feishu bot no longer waited for: the station stops following it (nobody waits on this; a failure leaves it
        // to expire there).
        cancel: (station, id) => {
          const op = ops.request("feishu.cancelRegistration", { station, id });
          if (op !== null) inner.runner.fork(Effect.ignore(inner.stations.perform(op, null), { log: "Unhandled", message: "form op performed" }));
        },
        // Its bot made: the connect is added, as `create` would.
        ready: (topic) => {
          if (this.connects.ready(topic)) inner.runner.fork(Effect.ignore(Effect.suspend(() => this.operate(topic, this.connects.ownerOf(topic), "create", null)), { log: "Unhandled", message: "connect created" }));
        },
      },
    );
  }

  /// One of the wizard's steps that asks its station (`config`, `make`, `verify`, `register`, `create`): its answer
  /// advances only the form it was asked for. Set by installForms.
  operate: (topic: Topic, owner: ClientId, action: string, ctx: J) => Effect.Effect<unknown, CoreError> = () => Effect.fail(CoreError.invalid("connect.flow"));

  owns(topic: Topic): boolean {
    return FORMS.has(topic.topic);
  }

  compute(topic: Topic): Value | undefined {
    try {
      switch (topic.topic) {
        case "decisionForm":
          return { ok: this.decisions.value(topic) };
        case "policyForm":
          return { ok: this.policies.value(topic) };
        case "agentEnvForm":
          return { ok: this.agentEnv.value(topic) };
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
    this.policies.disconnect(client);
    this.agentEnv.disconnect(client);
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
  handlers.policyForm = (_i, call, _p, at, ctx) => {
    const c = call as Extract<Call, { kind: "policyForm" }>;
    if (["open", "edit", "drop"].includes(c.action)) return attempt(() => forms.policies.change(c.topic, at[0], c.action, c.patch));
    return Effect.gen(function* () {
      const input = yield* attempt(() => forms.policies.begin(c.topic, at[0]));
      const answer = yield* Effect.result(Effect.flatMap(request("automaticDecisions.policy", { station: c.topic.station, input }), (op) => perform(op, ctx)));
      forms.policies.finish(c.topic, at[0], answer._tag === "Success");
      if (answer._tag === "Failure") return yield* Effect.fail(answer.failure);
      return answer.success;
    });
  };
  handlers.agentEnvForm = (_i, call, _p, at, ctx) => {
    const c = call as Extract<Call, { kind: "agentEnvForm" }>;
    if (["open", "edit", "drop"].includes(c.action)) return attempt(() => forms.agentEnv.change(c.topic, at[0], c.action, c.patch));
    return Effect.gen(function* () {
      const input = yield* attempt(() => forms.agentEnv.begin(c.topic, at[0]));
      const answer = yield* Effect.result(Effect.flatMap(request("agentEnv.set", { station: c.topic.station, text: input.text }), (op) => perform(op, ctx)));
      forms.agentEnv.finish(c.topic, at[0], answer._tag === "Success");
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
  forms.operate = (topic, owner, action, ctx) =>
    Effect.gen(function* () {
      const station = topic.station as string;
      const tokenTopic = tokensOf(station, topic.form as string);
      const view = yield* attempt(() => forms.connects.value(topic));
      // Slack's tokens are the token form's; the Feishu path has none.
      const slack = !String(view?.step ?? "").startsWith("feishu");
      let input: J = {};
      let verified = false;
      if (slack) {
        yield* attempt(() => forms.tokens.edit(tokenTopic, owner, { install: view?.made?.state ?? null }));
        [input, verified] = yield* attempt(() => forms.tokens.input(tokenTopic, owner));
      }
      const [generation, name, params] = yield* attempt(() => forms.connects.begin(topic, owner, action, input, verified));
      let revision: number | null = null;
      if (slack && action === "verify") {
        const begun = yield* Effect.result(attempt(() => forms.tokens.begin(tokenTopic, owner)));
        if (begun._tag === "Failure") {
          forms.connects.finish(topic, generation, action, { err: begun.failure });
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
      if (!forms.connects.finish(topic, generation, action, transition)) return yield* Effect.fail(CoreError.invalid(t("core-misc.connect.closed")));
      if (answer._tag === "Failure") return yield* Effect.fail(answer.failure);
      return answer.success;
    });
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
        default:
          return yield* forms.operate(c.topic, at[0], c.action, ctx);
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
