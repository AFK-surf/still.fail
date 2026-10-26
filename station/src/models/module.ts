// The model catalog kept up to date, as a part of the station (parts.ts): what models can do and cost as still.fail
// cloud says (GET /v1/models, cloud/src/models.ts), told to accounts/catalog.ts for the prices and the image check to
// read. Asked for in the background, never held up for: at the start, every six hours, and when a member's device
// connects, so that an app started again brings what came out since (at most once a minute). Revalidated with its
// ETag, and kept in model-catalog.json under the station's data: what the station says from its start until the cloud
// answers.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Effect, Layer } from "effect";
import { learn } from "../accounts/catalog.ts";
import { Fibers } from "../ops/fibers.ts";
import { writePrivate } from "../ops/files.ts";
import { log } from "../ops/log.ts";
import { ControlPlane, Parts, Paths } from "../services.ts";

const EVERY_MS = 6 * 3_600_000;
/// The least time between two asks a device's connecting makes (a phone's several links connect at once).
const AGAIN_MS = 60_000;

type Get = (url: string, init: RequestInit) => Promise<Response>;

export class ModelCatalog {
  #etag: string | null = null;
  #asked = -Infinity;
  #asking: Promise<void> | null = null;
  readonly #file: string;
  readonly #origin: () => string | null;
  readonly #now: () => number;
  readonly #get: Get;

  /// `file`: where it is kept; `origin`: still.fail cloud's, none when the station is in no still.fail cloud.
  constructor(file: string, origin: () => string | null, now: () => number, get: Get = (url, init) => fetch(url, init)) {
    this.#file = file;
    this.#origin = origin;
    this.#now = now;
    this.#get = get;
    try {
      const kept = JSON.parse(readFileSync(file, "utf8"));
      learn(kept?.models);
      if (typeof kept?.etag === "string") this.#etag = kept.etag;
    } catch {
      // None kept yet, or unreadable: the station's own tables answer until the cloud does.
    }
  }

  /// Asks the cloud for what changed; `soon`: not if it was asked less than a minute ago. One ask at a time.
  refresh(soon = false): Promise<void> {
    if (this.#asking !== null || (soon && this.#now() - this.#asked < AGAIN_MS)) return this.#asking ?? Promise.resolve();
    this.#asked = this.#now();
    this.#asking = this.#ask()
      .catch((error) => log.info("models", "the model catalog was not read", { error: (error as Error).message }))
      .finally(() => (this.#asking = null));
    return this.#asking;
  }

  async #ask(): Promise<void> {
    const origin = this.#origin();
    if (origin === null) return;
    const headers: Record<string, string> = { "user-agent": "stillfail-station" };
    if (this.#etag !== null) headers["if-none-match"] = this.#etag;
    const response = await this.#get(`${origin}/v1/models`, { headers, signal: AbortSignal.timeout(30_000) });
    if (response.status === 304) return;
    if (!response.ok) throw new Error(`still.fail cloud answered ${response.status}`);
    const body = await response.json();
    const named = learn(body?.models);
    this.#etag = response.headers.get("etag");
    writePrivate(this.#file, JSON.stringify({ etag: this.#etag, models: body?.models ?? {} }));
    log.info("models", "the model catalog was read", { models: named });
  }
}

export const ModelsLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const plane = yield* ControlPlane;
    const { data } = yield* Paths;
    const parts = yield* Parts;
    // On its own clock, ended with the station.
    const time = yield* Effect.acquireRelease(Effect.sync(() => new Fibers("models")), (t) => Effect.promise(() => t.close()));
    const origin = () => (plane.spec().provider === "stillfail" ? (plane.state.state?.origin ?? null) : null);
    const catalog = new ModelCatalog(join(data, "model-catalog.json"), origin, () => time.now());
    time.after(0, () => void catalog.refresh());
    time.every(EVERY_MS, () => void catalog.refresh());
    parts.memberConnected(() => void catalog.refresh(true));
  }),
);
