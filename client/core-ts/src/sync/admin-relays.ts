// The relays' load for the console's 中继 page (views/admin-relays.ts): still.fail cloud samples it every minute
// (cloud/src/relay-load.ts) and tells the operator's devices it did (a `relays` event); while something shows it and a
// page of the app is in view, it is read then, and as it is first shown. Nothing reads it otherwise (the operator's
// other lists are read with the account: ADMIN_LISTS).
import { Effect, Fiber } from "effect";
import type { Inner } from "../core.ts";
import type { Owner } from "../core/routing.ts";
import { topicKey, type Topic } from "../protocol.ts";

type Shown = { topic: Topic; fiber: Fiber.Fiber<unknown, unknown> | null; again: boolean };

export class AdminRelays implements Owner {
  readonly #core: Inner;
  readonly #live = new Map<string, Shown>();

  constructor(core: Inner) {
    this.#core = core;
  }

  owns(topic: Topic): boolean {
    return topic.topic === "admin" && topic.list === "relays";
  }

  start(topic: Topic): void {
    const key = topicKey(topic);
    if (this.#live.has(key)) return;
    this.#live.set(key, { topic, fiber: null, again: false });
    this.#read(key);
  }

  /// still.fail cloud sampled the relays (`sub`'s socket said so): each list of them shown for that account read again.
  told(sub: string): void {
    for (const [key, shown] of this.#live) if (shown.topic.account === sub) this.#read(key);
  }

  stop(topic: Topic): void {
    const shown = this.#live.get(topicKey(topic));
    this.#live.delete(topicKey(topic));
    if (shown?.fiber) this.#core.runner.interrupt(shown.fiber);
  }

  /// Reads it once a page of the app is in view; asked again meanwhile, once more after.
  #read(key: string): void {
    const shown = this.#live.get(key);
    if (!shown) return;
    if (shown.fiber !== null) {
      shown.again = true;
      return;
    }
    const inView = Effect.suspend(() => this.#core.attention?.attend.untilShown() ?? Effect.void);
    const read = this.#core.cloudSync.adminList(shown.topic.account as string, "relays");
    shown.fiber = this.#core.runner.fork(
      Effect.andThen(inView, read).pipe(
        Effect.ensuring(
          Effect.sync(() => {
            shown.fiber = null;
            if (shown.again && this.#live.get(key) === shown) {
              shown.again = false;
              this.#read(key);
            }
          }),
        ),
      ),
    ) as Fiber.Fiber<unknown, unknown>;
  }
}
