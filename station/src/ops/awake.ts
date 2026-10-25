// The machine kept awake while the station has work going. An agent's turn or a job runs with nobody at the machine,
// and the system counts only its keyboard and mouse: one Windows station went to sleep 45 minutes into its agents'
// work ("System Idle") and stood half an hour, its turns stopped with it. While a session runs, waits on work it
// started (its turn ended waiting: a background command, a subagent, a CI it watches), or a job runs (one that is
// work, not a service on a port; and only while its session had a turn lately: a watch may never end), the station
// holds the machine awake (platform `holdAwake`); a minute after the
// last of it ends, it lets go, and the machine sleeps by its own settings again. The screen may still go off; a lid
// closed still sleeps.
import { Effect, Layer } from "effect";
import { Fibers } from "./fibers.ts";
import { log } from "./log.ts";
import { platform } from "../platform/index.ts";
import { Store } from "../services.ts";
import type { Store as StationStore } from "../store/store.ts";

/// How often it is looked at, and how long after the work it is held still (a next turn often follows).
const EVERY = 20_000;
const LINGER = 60_000;
/// How long after its session's last turn a job still counts: a job has no end of its own (a watch kept on forever);
/// one that does end wakes its agent, a turn again, and counts from there.
const JOB_SPAN = 2 * 60 * 60_000;

/// Whether the station has work going at `now`: a session's turn; a session waiting on what it started, until the
/// wait it gave is up (then the station wakes it, a turn again); or a job that is work (watched, or with no port: a
/// service on a port runs on by itself and keeps nobody waiting) within JOB_SPAN of its session's last turn.
/// Looked at every EVERY: what it reads is the sessions shown and the jobs running, never every one ever (an archived
/// session waits on nothing).
export function working(store: Pick<StationStore, "anyRunning" | "liveSessions" | "statsOf" | "jobsRunning">, now: number): boolean {
  if (store.anyRunning()) return true;
  const jobs = store.jobsRunning().filter((j) => j.watch || j.port === null);
  const stats = store.statsOf([...store.liveSessions().map((s) => s.key), ...jobs.map((j) => j.sessionKey)]);
  for (const { lastTurn: t } of stats.values()) {
    if (t?.declared === "waiting" && t.endedAt !== null && now < t.endedAt + (t.waitSeconds ?? 0) * 1000 + LINGER) return true;
  }
  return jobs.some((j) => {
    const last = stats.get(j.sessionKey)?.lastTurn;
    const since = last ? (last.endedAt ?? now) : j.startedAt;
    return now - since < JOB_SPAN;
  });
}

export class Awake {
  readonly #fibers: Fibers;
  readonly #working: (now: number) => boolean;
  readonly #hold: (why: string) => (() => void) | null;
  #release: (() => void) | null = null;
  #lastWork = -Infinity;
  #unheld = false;

  constructor(deps: { working: (now: number) => boolean; hold: (why: string) => (() => void) | null; fibers?: Fibers }) {
    this.#fibers = deps.fibers ?? new Fibers("awake");
    this.#working = deps.working;
    this.#hold = deps.hold;
    this.#fibers.every(EVERY, () => this.check());
  }

  /// Whether it holds the machine awake now.
  get held(): boolean {
    return this.#release !== null;
  }

  check(): void {
    const now = this.#fibers.now();
    if (this.#working(now)) this.#lastWork = now;
    const wanted = now - this.#lastWork < LINGER;
    if (wanted && this.#release === null) {
      this.#release = this.#hold("still.fail agents are working");
      if (this.#release !== null) log.info("awake", "holding the machine awake while agents work");
      else if (!this.#unheld) {
        this.#unheld = true;
        log.warn("awake", "this machine has no way to be held awake: it may sleep while agents work");
      }
    } else if (!wanted && this.#release !== null) {
      this.#release();
      this.#release = null;
      log.info("awake", "the work is done: the machine sleeps by its own settings again");
    }
  }

  async close(): Promise<void> {
    await this.#fibers.close();
    this.#release?.();
    this.#release = null;
  }
}

export const AwakeLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const store = yield* Store;
    yield* Effect.acquireRelease(
      Effect.sync(() => new Awake({ working: (now) => working(store, now), hold: (why) => platform.holdAwake(why) })),
      (awake) => Effect.promise(() => awake.close()),
    );
  }),
);
