// The model catalog kept up to date, as a part of the station (parts.ts): what models can do and cost as still.fail
// cloud says (GET /v1/models, cloud/src/models.ts), told to accounts/catalog.ts for the prices and the image check to
// read. Asked for in the background, never held up for: at the start, and as the cloud says the catalog changed (its
// presence socket: plane.ts `told`), naming the ETag it changed to. Revalidated with its ETag, and kept in
// model-catalog.json under the station's data: what the station says from its start until the cloud answers. Models it
// names that it did not before are told to the accounts, which check their makers' profiles again.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Effect, Layer } from "effect";
import { learn, named as namedKeys } from "../accounts/catalog.ts";
import { Fibers } from "../ops/fibers.ts";
import { writePrivate } from "../ops/files.ts";
import { log } from "../ops/log.ts";
import { AgentsSide, ControlPlane, Paths } from "../services.ts";


type Get = (url: string, init: RequestInit) => Promise<Response>;

export class ModelCatalog {
  #etag: string | null = null;
  #asking: Promise<void> | null = null;
  /// Asked for again while an ask went on: asked once more after it.
  #again = false;
  readonly #file: string;
  readonly #origin: () => string | null;
  readonly #get: Get;
  readonly #added: (keys: string[]) => void;

  /// `file`: where it is kept; `origin`: still.fail cloud's, none when the station is in no still.fail cloud; `added`:
  /// told the keys of the models a catalog the cloud sent names that the one before did not (none the first time).
  constructor(file: string, origin: () => string | null, _now: () => number, get: Get = (url, init) => fetch(url, init), added: (keys: string[]) => void = () => {}) {
    this.#file = file;
    this.#origin = origin;
    this.#get = get;
    this.#added = added;
    try {
      const kept = JSON.parse(readFileSync(file, "utf8"));
      learn(kept?.models);
      if (typeof kept?.etag === "string") this.#etag = kept.etag;
    } catch {
      // None kept yet, or unreadable: the station's own tables answer until the cloud does.
    }
  }

  /// Asks the cloud for what changed: `etag`, the catalog it said it changed to (asked for by it, past what a cache on
  /// the way kept). One ask at a time; asked again while one goes on, asked once more after it.
  refresh(etag?: string): Promise<void> {
    if (etag !== undefined && etag === this.#etag) return this.#asking ?? Promise.resolve();
    if (this.#asking !== null) {
      this.#again = true;
      return this.#asking;
    }
    this.#asking = this.#ask(etag)
      .catch((error) => log.info("models", "the model catalog was not read", { error: (error as Error).message }))
      .finally(() => {
        this.#asking = null;
        if (this.#again) {
          this.#again = false;
          void this.refresh();
        }
      });
    return this.#asking;
  }

  async #ask(etag?: string): Promise<void> {
    const origin = this.#origin();
    if (origin === null) return;
    const headers: Record<string, string> = { "user-agent": "stillfail-station" };
    if (this.#etag !== null) headers["if-none-match"] = this.#etag;
    const v = etag === undefined ? "" : `?v=${encodeURIComponent(etag)}`;
    const response = await this.#get(`${origin}/v1/models${v}`, { headers, signal: AbortSignal.timeout(30_000) });
    if (response.status === 304) return;
    if (!response.ok) throw new Error(`still.fail cloud answered ${response.status}`);
    const body = await response.json();
    const before = new Set(namedKeys());
    const named = learn(body?.models);
    const added = before.size === 0 ? [] : namedKeys().filter((k) => !before.has(k));
    this.#etag = response.headers.get("etag");
    writePrivate(this.#file, JSON.stringify({ etag: this.#etag, models: body?.models ?? {} }));
    log.info("models", "the model catalog was read", { models: named });
    if (added.length > 0) this.#added(added);
  }
}

export const ModelsLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const plane = yield* ControlPlane;
    const { data } = yield* Paths;
    const side = yield* AgentsSide;
    // On its own clock, ended with the station.
    const time = yield* Effect.acquireRelease(Effect.sync(() => new Fibers("models")), (t) => Effect.promise(() => t.close()));
    const origin = () => (plane.spec().provider === "stillfail" ? (plane.state.state?.origin ?? null) : null);
    const catalog = new ModelCatalog(join(data, "model-catalog.json"), origin, () => time.now(), undefined, (keys) => side.current?.accounts.newModels(keys));
    time.after(0, () => void catalog.refresh());
    plane.told("models", (said) => void catalog.refresh(said.type === "models" ? said.etag : undefined));
  }),
);
