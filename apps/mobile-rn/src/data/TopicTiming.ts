// What the bar's timing (BarTiming, in the app) hears of the topics followed here (data/TopicTiming.kt): this module
// does not see the app, so the app says where it goes when it starts (BarTiming.start); before that, nowhere.
import type { Topic } from "../../../../web/src/core/client.ts";

export const TopicTiming = {
  /** A topic followed anew by a page (Topics.ts PageTopics), `held` if what it showed first was a value already. */
  followed: (_topic: Topic, _held: boolean): void => undefined,
  /** A topic's value come in (`arrived`, performance.now() ms) and read; `failed` when it could not be. */
  decoded: (_topic: Topic, _arrived: number, _value: unknown, _failed: boolean): void => undefined,
  /** What a page shows of a topic now. */
  shown: (_topic: Topic, _value: unknown, _failed: boolean): void => undefined,
};
