// What a chat says of its connection (pill.rs; the `connection` topic): its link to its station while down or coming
// back, else what its workspace's `status` says. When it shows is decided here: trouble at once; coming back only
// once it has lasted BUSY_MS; "已连上" for BACK_MS once all is well again, after a busy or a trouble was shown. These
// timers only time what is on screen (rule 2: a display may sample while shown); nothing is asked of the network.
import { Effect, type Fiber } from "effect";
import * as brand from "./brand.ts";
import type { Owner } from "./core/routing.ts";
import { t } from "./i18n.ts";
import * as looks from "./looks.ts";
import { topicKey, type Topic } from "./protocol.ts";
import type { Runner } from "./runtime.ts";
import type { Store, Value, Watch } from "./store.ts";
import { ofAddress } from "./workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;

export const BUSY_MS = 1_500;
export const BACK_MS = 1_500;

export const nothing = (): J => ({ tone: null, text: null, items: [] });

/// When what is not as it should be shows, as it goes on.
export class Timing {
  since: number | null = null;
  shown = false;
  backUntil: number | null = null;

  step(now: number, raw: [J, boolean] | null): [J, number | null] {
    if (raw !== null) {
      const [value, lasted] = raw;
      if (this.since === null) this.since = now;
      if (lasted || this.shown || value.tone === "trouble" || now - this.since >= BUSY_MS) {
        this.shown = true;
        this.backUntil = null;
        return [value, null];
      }
      this.backUntil = null;
      return [nothing(), this.since + BUSY_MS - now];
    }
    const was = this.since;
    this.since = null;
    if (was !== null) {
      const shown = this.shown;
      this.shown = false;
      if (shown) this.backUntil = now + BACK_MS;
    }
    if (this.backUntil !== null && now < this.backUntil) return [{ tone: "back", text: t("core-misc.pill.back"), items: [] }, this.backUntil - now];
    this.backUntil = null;
    return [nothing(), null];
  }
}

/// What is not as it should be for a chat on a station, before when it shows is decided.
export function raw(link: J, status: J): [J, boolean] | null {
  const items = status?.items ?? [];
  if (link !== null && typeof link === "object") {
    const trouble = link.tone === "trouble";
    return [{ tone: trouble ? "trouble" : "busy", text: link.text ?? null, detail: link.detail ?? null, items: trouble ? [] : items }, false];
  }
  if (status === null || status === undefined) return null;
  const text = (or: string) => (typeof status.text === "string" ? status.text : or);
  if (status.state === "trouble") return [{ tone: "trouble", text: text(t("core-misc.pill.cloud_down", { brand: brand.name() })), items }, true];
  if (status.state === "slow") return [{ tone: "busy", text: text(""), items }, true];
  return null;
}

type Live = { watches: Watch[]; timing: Timing; due: number | null; timer: Fiber.Fiber<unknown, unknown> | null };

/// The live `connection` topics.
export class Pills implements Owner {
  readonly #store: Store;
  readonly #runner: Runner;
  readonly #now: () => number;
  readonly #stationName: (station: string) => string;
  readonly #live = new Map<string, Live>();

  constructor(store: Store, runner: Runner, now: () => number, stationName: (station: string) => string) {
    this.#store = store;
    this.#runner = runner;
    this.#now = now;
    this.#stationName = stationName;
  }

  owns(topic: Topic): boolean {
    return topic.topic === "connection";
  }

  static #sources(station: string): [Topic, Topic] {
    return [{ topic: "link", station }, { topic: "status", workspace: ofAddress(station) }];
  }

  start(topic: Topic): void {
    const watches = Pills.#sources(topic.station as string).map((s) => this.#store.watch(s, () => this.#store.invalidate(topic)));
    this.#live.set(topicKey(topic), { watches, timing: new Timing(), due: null, timer: null });
    this.#store.invalidate(topic);
  }

  stop(topic: Topic): void {
    const live = this.#live.get(topicKey(topic));
    this.#live.delete(topicKey(topic));
    if (!live) return;
    for (const w of live.watches) w.drop();
    if (live.timer) this.#runner.interrupt(live.timer);
  }

  compute(topic: Topic): Value | undefined {
    const station = topic.station as string;
    const live = this.#live.get(topicKey(topic));
    if (!live) return undefined;
    const [linkTopic, statusTopic] = Pills.#sources(station);
    const l = this.#store.get(linkTopic);
    const link = l !== undefined ? looks.linkShown(l, this.#stationName(station)) : null;
    const status = this.#store.get(statusTopic) ?? null;
    const now = this.#now();
    const [value, again] = live.timing.step(now, raw(link, status));
    const at = again !== null ? now + again : null;
    const fresh = at !== null && live.due !== at;
    live.due = at;
    if (again !== null && fresh) {
      if (live.timer) this.#runner.interrupt(live.timer);
      live.timer = this.#runner.fork(
        Effect.sleep(Math.max(Math.ceil(again), 0)).pipe(
          Effect.andThen(
            Effect.sync(() => {
              if (this.#live.get(topicKey(topic)) === live) this.#store.invalidate(topic);
            }),
          ),
        ),
      ) as Fiber.Fiber<unknown, unknown>;
    }
    return { ok: value };
  }
}
