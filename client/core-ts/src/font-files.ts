// A face's files on a device whose app keeps no files of its own (the mbui app; docs/fonts.md): what the Android app
// does itself in files/fonts, done here in the host's storage. A face chosen is fetched (`fonts.fetch {id}`), each of its
// files as it is put (gzipped), how far it got said on the `fonts` topic; the app unzips each and checks it by its
// hash, and that is kept instead (`fonts.keep {sha256}` + the file); `fonts.file {sha256}` gives back either, saying
// which. Where the host keeps each value as a file of its own (the native apps' shell), the prefs' `faces` say where
// a chosen face's files are (`path`, fonts.ts `setKeptAt`): the app's host reads them there as the app starts, none of
// them carried through here nor checked again (the app falls back on `fonts.file` where one cannot be read: one kept
// as fetched). A face's files stay once fetched, chosen or not (the `fonts` topic's `kept`: the faces whole here), so
// choosing one again asks nothing of the network. A face's preview
// (`fonts.preview {id}`: the fonts page's characters alone, tens of KB) is fetched once and kept whatever is chosen.
import { Effect } from "effect";
import { CoreError } from "./error.ts";
import * as fonts from "./fonts.ts";
import type { Host } from "./host.ts";
import { t } from "./i18n.ts";
import type { Owner } from "./core/routing.ts";
import { Beside, type Topic } from "./protocol.ts";
import type { Store, Value } from "./store.ts";
import { isObject, parseJson, toJsonBytes } from "./util.ts";

/// What is kept, by file's hash: gzipped as fetched, or unzipped as the app checked it.
const INDEX = "fonts/kept";
const fileKey = (sha256: string) => `fonts/file/${sha256}`;
const previewKey = (id: string, url: string) => `fonts/preview/${id}/${url.slice(url.lastIndexOf("/") + 1)}`;

type Kept = Record<string, "gz" | "ttf">;

export type FontsCall = { kind: "fetch"; id: string } | { kind: "preview"; id: string } | { kind: "file"; sha256: string } | { kind: "keep"; sha256: string; bytes: Uint8Array };

export class FontFiles implements Owner {
  readonly #host: Host;
  readonly #store: Store;
  /// A face being fetched: how far, 0 to 1.
  readonly #fetching = new Map<string, number>();
  /// A face whose fetch failed: why.
  readonly #failed = new Map<string, string>();
  #kept: Kept | null = null;

  constructor(host: Host, store: Store) {
    this.#host = host;
    this.#store = store;
  }

  owns(topic: Topic): boolean {
    return topic.topic === "fonts";
  }

  /// What is kept is read from the host's storage the first time the topic is wanted, said once it is read.
  start(): void {
    if (this.#kept === null) Effect.runFork(Effect.map(this.#index(), () => this.#changed()));
  }

  compute(): Value {
    const kept = this.#kept;
    const whole = kept === null ? [] : fonts.ids().filter((id) => fonts.faceOf(id)!.files.every((f) => kept[f.sha256] !== undefined));
    return { ok: { fetching: Object.fromEntries(this.#fetching), failed: Object.fromEntries(this.#failed), kept: whole } };
  }

  #changed(): void {
    this.#store.invalidate({ topic: "fonts" });
  }

  run(call: FontsCall): Effect.Effect<unknown, CoreError> {
    switch (call.kind) {
      case "fetch":
        return this.fetch(call.id);
      case "preview":
        return this.preview(call.id);
      case "file":
        return this.file(call.sha256);
      case "keep":
        return this.keep(call.sha256, call.bytes);
    }
  }

  #index(): Effect.Effect<Kept> {
    return Effect.gen({ self: this }, function* () {
      if (this.#kept === null) {
        const raw = parseJson(yield* Effect.orElseSucceed(this.#host.storageGet(INDEX), () => null));
        const kept: Kept = {};
        if (isObject(raw)) for (const [sha, how] of Object.entries(raw)) if (how === "gz" || how === "ttf") kept[sha] = how;
        this.#kept = kept;
      }
      return this.#kept;
    });
  }

  #save(): Effect.Effect<void, CoreError> {
    return Effect.mapError(this.#host.storageSet(INDEX, toJsonBytes(this.#kept ?? {})), (e) => new CoreError("fonts", e.message));
  }

  /// Face `id`'s files fetched, those not kept yet, each whole; null once all are here (gzipped, or as the app kept
  /// them). Failed: said on the topic too, until it is fetched again.
  fetch(id: string): Effect.Effect<null, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const face = fonts.faceOf(id);
      if (face === null) return yield* Effect.fail(CoreError.invalid(t("core-misc.params.invalid", { error: `id ${id}` })));
      if (this.#fetching.has(id)) return null;
      const kept = yield* this.#index();
      this.#fetching.set(id, 0);
      this.#failed.delete(id);
      this.#changed();
      let done = 0;
      const got = yield* Effect.result(
        Effect.gen({ self: this }, function* () {
          for (const f of face.files) {
            if (kept[f.sha256] !== undefined) {
              done += f.bytes;
              continue;
            }
            const parts: Uint8Array[] = [];
            let size = 0;
            yield* Effect.scoped(
              Effect.gen({ self: this }, function* () {
                const r = yield* Effect.mapError(this.#host.fetchStream({ method: "GET", url: f.url, headers: [], body: null }), (e) => new CoreError("fonts", e.message));
                if (r.status !== 200) return yield* Effect.fail(new CoreError("fonts", t("android-misc.updates.httpStatus", { status: r.status })));
                while (true) {
                  const part = yield* Effect.mapError(r.body.take, (e) => new CoreError("fonts", e.message));
                  if (part === null) break;
                  parts.push(part);
                  size += part.length;
                  // said each percent, not each part
                  const p = Math.min(100, Math.floor(((done + size) * 100) / Math.max(1, face.bytes))) / 100;
                  if (p !== this.#fetching.get(id)) {
                    this.#fetching.set(id, p);
                    this.#changed();
                  }
                }
              }),
            );
            const whole = new Uint8Array(size);
            let at = 0;
            for (const part of parts) {
              whole.set(part, at);
              at += part.length;
            }
            yield* Effect.mapError(this.#host.storageSet(fileKey(f.sha256), whole), (e) => new CoreError("fonts", e.message));
            kept[f.sha256] = "gz";
            yield* this.#save();
            done += f.bytes;
          }
        }),
      );
      this.#fetching.delete(id);
      if (got._tag === "Failure") this.#failed.set(id, got.failure.message);
      this.#changed();
      if (got._tag === "Failure") return yield* Effect.fail(got.failure);
      return null;
    });
  }

  /// Where the host keeps a file, by its hash, as a file of its own: null while none is kept (or not as a file).
  at(sha256: string): string | null {
    return this.#host.storagePath?.(fileKey(sha256)) ?? null;
  }

  /// A file kept, by its hash: its bytes, and whether they are as fetched (gzipped) or as the app kept them.
  file(sha256: string): Effect.Effect<Beside, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const how = (yield* this.#index())[sha256];
      const bytes = how === undefined ? null : yield* Effect.orElseSucceed(this.#host.storageGet(fileKey(sha256)), () => null);
      if (how === undefined || bytes === null) return yield* Effect.fail(new CoreError("not_found", t("core-misc.params.invalid", { error: `sha256 ${sha256}` })));
      return new Beside({ zipped: how === "gz" }, bytes);
    });
  }

  /// A file as the app unzipped and checked it, kept instead of what was fetched.
  keep(sha256: string, bytes: Uint8Array): Effect.Effect<null, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const kept = yield* this.#index();
      if (kept[sha256] === undefined) return yield* Effect.fail(new CoreError("not_found", t("core-misc.params.invalid", { error: `sha256 ${sha256}` })));
      yield* Effect.mapError(this.#host.storageSet(fileKey(sha256), bytes), (e) => new CoreError("fonts", e.message));
      kept[sha256] = "ttf";
      yield* this.#save();
      return null;
    });
  }

  /// Face `id`'s preview: kept, else fetched and kept.
  preview(id: string): Effect.Effect<Beside, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const face = fonts.faceOf(id);
      if (face === null || face.preview === undefined) return yield* Effect.fail(CoreError.invalid(t("core-misc.params.invalid", { error: `id ${id}` })));
      const key = previewKey(id, face.preview);
      const kept = yield* Effect.orElseSucceed(this.#host.storageGet(key), () => null);
      if (kept !== null) return new Beside({}, kept);
      const r = yield* Effect.mapError(this.#host.fetch({ method: "GET", url: face.preview, headers: [], body: null }), (e) => new CoreError("fonts", e.message));
      if (r.status !== 200) return yield* Effect.fail(new CoreError("fonts", t("android-misc.updates.httpStatus", { status: r.status })));
      yield* Effect.ignore(this.#host.storageSet(key, r.body), { log: "Unhandled", message: "font kept" });
      return new Beside({}, r.body);
    });
  }
}
