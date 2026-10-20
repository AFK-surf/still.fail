// The relays' load for the console's 中继 page (views/admin-relays.ts): still.fail cloud's samples change every minute
// (cloud/src/relay-load.ts), so while something shows it, it is read again each minute; nothing reads it otherwise
// (the operator's other lists are read with the account: ADMIN_LISTS).
import { Effect, Fiber } from "effect";
import type { Inner } from "../core.ts";
import type { Owner } from "../core/routing.ts";
import { topicKey, type Topic } from "../protocol.ts";
import { laterSleep } from "../runtime.ts";

/** How often it is read while shown: as often as the relays' counters are sampled. */
export const RELAYS_EVERY_MS = 60_000;

export class AdminRelays implements Owner {
  readonly #core: Inner;
  readonly #live = new Map<string, Fiber.Fiber<unknown, unknown>>();

  constructor(core: Inner) {
    this.#core = core;
  }

  owns(topic: Topic): boolean {
    return topic.topic === "admin" && topic.list === "relays";
  }

  start(topic: Topic): void {
    const key = topicKey(topic);
    if (this.#live.has(key)) return;
    const read = this.#core.cloudSync.adminList(topic.account as string, "relays");
    this.#live.set(key, this.#core.runner.fork(Effect.forever(Effect.andThen(read, laterSleep(RELAYS_EVERY_MS)))) as Fiber.Fiber<unknown, unknown>);
  }

  stop(topic: Topic): void {
    const fiber = this.#live.get(topicKey(topic));
    this.#live.delete(topicKey(topic));
    if (fiber) this.#core.runner.interrupt(fiber);
  }
}
