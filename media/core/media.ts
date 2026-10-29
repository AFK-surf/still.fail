// The media app's module of the core (docs/core-modules.md, docs/media-service.md): the bookshelf of a station's media
// service, what each book holds, where the viewer is in it and what they marked. Topics are read from what is kept on
// the device and brought up to date as they are shown; while any is shown, the service's events stream says what
// changed. Calls ask the service and keep what it says.
import { Effect, Schedule } from "effect";
import { CoreError } from "../../client/core-ts/src/error.ts";
import type { CoreModule, ModuleEnv, ModuleParts } from "../../client/core-ts/src/module.ts";
import { Beside, type Topic } from "../../client/core-ts/src/protocol.ts";
import { SseParser } from "../../client/core-ts/src/station/sse.ts";

/// A place in a book: the chapter, and how far into its text in UTF-16 code units (docs/media-service.md), as of `at`.
export type Place = { chapter: number; offset: number; at: number };

const T = {
  shelf: "media.shelf",
  book: "media.book",
  place: "media.place",
  notes: "media.notes",
  timeline: "media.timeline",
  albums: "media.albums",
  videos: "media.videos",
  video: "media.video",
  progress: "media.progress",
} as const;

/// How many days with photos a timeline's window holds each side of its day, at most.
const DAYS_MOST = 120;

const enc = encodeURIComponent;

// ── params ──

type Params = Record<string, unknown>;
const obj = (params: unknown): Params => (params !== null && typeof params === "object" && !Array.isArray(params) ? (params as Params) : {});
function str(p: Params, key: string): string {
  const v = p[key];
  if (typeof v !== "string" || v === "") throw CoreError.invalid(`${key}: a string`);
  return v;
}
function count(p: Params, key: string): number {
  const v = p[key];
  if (typeof v !== "number" || !Number.isSafeInteger(v) || v < 0) throw CoreError.invalid(`${key}: a whole number`);
  return v;
}
function placeOf(v: unknown): Place {
  const p = obj(v);
  return { chapter: count(p, "chapter"), offset: count(p, "offset"), at: count(p, "at") };
}

export const media: CoreModule = {
  name: "media",
  install(env: ModuleEnv): ModuleParts {
    const topic = {
      shelf: (station: string): Topic => ({ topic: T.shelf, station }),
      book: (station: string, book: string): Topic => ({ topic: T.book, station, book }),
      place: (station: string, book: string): Topic => ({ topic: T.place, station, book }),
      notes: (station: string, book: string): Topic => ({ topic: T.notes, station, book }),
      albums: (station: string): Topic => ({ topic: T.albums, station }),
    };
    // What a topic is read as, from the service, and kept as.
    const source = (t: Topic): { path: string; key: string; take: (got: unknown) => unknown } | null => {
      const book = typeof t.book === "string" ? t.book : "";
      switch (t.topic) {
        case T.shelf:
          return { path: "/books", key: "shelf", take: (got) => got };
        case T.book:
          return { path: `/books/${enc(book)}`, key: `book/${book}`, take: (got) => got };
        case T.place:
          // `{place}` or nothing yet: kept as `{place: null}`, so the topic says "none" rather than "not known".
          return { path: `/books/${enc(book)}/place`, key: `place/${book}`, take: (got) => ({ place: obj(got).place ?? null }) };
        case T.notes:
          return { path: `/books/${enc(book)}/notes`, key: `notes/${book}`, take: (got) => got };
        // A window of the photos' timeline: `before` and `after` days that have photos about `around` (none: the
        // latest), each kept as it was read.
        case T.timeline: {
          const around = typeof t.around === "string" && /^\d{4}-\d{2}-\d{2}$/.test(t.around) ? t.around : "";
          const days = (v: unknown, fallback: number) => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? Math.min(v, DAYS_MOST) : fallback);
          const before = days(t.before, 30);
          const after = days(t.after, around === "" ? 0 : 30);
          return { path: `/photos/timeline?${around ? `around=${around}&` : ""}before=${before}&after=${after}`, key: `timeline/${around}/${before}/${after}`, take: (got) => got };
        }
        case T.albums:
          return { path: "/photos/albums", key: "albums", take: (got) => got };
        // The films and shows: the library's first page (films, shows, what is being watched), one film or show, and
        // where the viewer is in one.
        case T.videos:
          return { path: "/videos/library", key: "videos", take: (got) => got };
        case T.video: {
          const id = typeof t.id === "string" ? t.id : "";
          return { path: `/videos/titles/${enc(id)}`, key: `video/${id}`, take: (got) => got };
        }
        case T.progress: {
          const id = typeof t.id === "string" ? t.id : "";
          return { path: `/videos/${enc(id)}/progress`, key: `progress/${id}`, take: (got) => ({ progress: obj(got).progress ?? null }) };
        }
      }
      return null;
    };
    const read = (t: Topic) => {
      const s = source(t);
      const station = String(t.station);
      if (!s) return Effect.void;
      return env.request(station, "GET", s.path, null, { quiet: true }).pipe(
        Effect.tap((got) => Effect.sync(() => env.keep(station, s.key, s.take(got), t))),
        Effect.asVoid,
      );
    };
    // Shown topics by station; a station with any has its events followed.
    const shown = new Map<string, Map<string, Topic>>();
    const following = new Map<string, () => void>();
    // A topic by its params, whatever order they came in.
    const keyOf = (t: Topic) => JSON.stringify(Object.entries(t).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
    const follow = (station: string) =>
      Effect.scoped(
        Effect.gen(function* () {
          const reply = yield* env.stream(station, "/events");
          // Opened (again): what is shown may have changed meanwhile.
          for (const t of shown.get(station)?.values() ?? []) yield* Effect.ignore(read(t), { log: "Unhandled", message: "media read" });
          const parser = new SseParser();
          for (;;) {
            const chunk = yield* reply.body.take;
            if (chunk === null) return;
            for (const [event, data] of parser.feed(chunk)) {
              const book = (() => {
                try {
                  return String(obj(JSON.parse(data)).book ?? "");
                } catch {
                  return "";
                }
              })();
              const of = shown.get(station);
              if (!of) continue;
              // The photos changed: every window of the timeline shown, and the albums.
              if (event === "photos") {
                for (const t of [...of.values()].filter((t) => t.topic === T.timeline || t.topic === T.albums)) yield* Effect.ignore(read(t), { log: "Unhandled", message: "media read" });
                continue;
              }
              // The films and shows changed: the library and each shown; the viewer's place in one: it, and the library
              // (what is being watched).
              if (event === "videos" || event === "progress") {
                const id = (() => {
                  try {
                    return String(obj(JSON.parse(data)).id ?? "");
                  } catch {
                    return "";
                  }
                })();
                const which = [...of.values()].filter((t) => t.topic === T.videos || (event === "videos" ? t.topic === T.video : t.topic === T.progress && t.id === id));
                for (const t of which) yield* Effect.ignore(read(t), { log: "Unhandled", message: "media read" });
                continue;
              }
              const asked = event === "shelf" ? topic.shelf(station) : event === "place" ? topic.place(station, book) : event === "notes" ? topic.notes(station, book) : null;
              // A book changed: its contents too, if shown.
              const also = event === "shelf" ? [...of.values()].filter((t) => t.topic === T.book) : [];
              for (const t of [asked, ...also]) if (t && of.has(keyOf(t))) yield* Effect.ignore(read(t), { log: "Unhandled", message: "media read" });
            }
          }
        }),
      ).pipe(
        Effect.ignore({ log: "Unhandled", message: "media followed" }),
        // Ended or failed: opened again a moment later, for as long as anything is shown.
        Effect.andThen(Effect.sleep("5 seconds")),
        Effect.repeat(Schedule.forever),
        Effect.asVoid,
      );
    const kept = (station: string, t: Topic): unknown => {
      const s = source(t);
      return s ? env.kept(station, s.key) : undefined;
    };
    // A place set here is shown at once; the service keeps the latest (`at`).
    const setPlace = (station: string, book: string, place: Place) => {
      const was = obj(env.kept(station, `place/${book}`)).place as Place | null | undefined;
      if (!was || was.at <= place.at) env.keep(station, `place/${book}`, { place }, topic.place(station, book));
    };

    return {
      topics: {
        owns: (t) => source(t) !== null,
        start: (t) => {
          const station = String(t.station);
          let of = shown.get(station);
          if (!of) shown.set(station, (of = new Map()));
          of.set(keyOf(t), t);
          env.fork(Effect.ignore(read(t), { log: "Unhandled", message: "media read" }));
          if (!following.has(station)) following.set(station, env.fork(follow(station)));
        },
        stop: (t) => {
          const station = String(t.station);
          const of = shown.get(station);
          of?.delete(keyOf(t));
          if (of && of.size === 0) {
            shown.delete(station);
            following.get(station)?.();
            following.delete(station);
          }
        },
        compute: (t) => {
          const value = kept(String(t.station), t);
          return value === undefined ? undefined : { ok: value };
        },
      },
      keyed: {
        [T.shelf]: { fields: { books: { key: ["id"] } } },
        [T.notes]: { fields: { notes: { key: ["id"] } } },
        [T.timeline]: { fields: { days: { key: ["day"], item: { fields: { items: { key: ["id"] } } } } } },
        [T.albums]: { fields: { albums: { key: ["id"] } } },
        [T.videos]: { fields: { movies: { key: ["id"] }, shows: { key: ["id"] }, recent: { key: ["id"] } } },
      },
      calls: {
        // A chapter's text: kept on the device once read, so a book read before opens without the station.
        chapter: {
          parse: (params) => {
            const p = obj(params);
            return { station: str(p, "station"), book: str(p, "book"), index: count(p, "index") };
          },
          run: (p: { station: string; book: string; index: number }) => {
            const key = `chapter/${p.book}/${p.index}`;
            const had = env.kept(p.station, key);
            if (had !== undefined) return Effect.succeed(had);
            return Effect.tap(env.request(p.station, "GET", `/books/${enc(p.book)}/chapters/${p.index}`, null), (got) =>
              Effect.sync(() => env.keep(p.station, key, got, { topic: "media.chapter", station: p.station, book: p.book, index: p.index })),
            );
          },
          station: (p: { station: string }) => p.station,
        },
        // A picture in a book, its bytes beside the answer.
        image: {
          parse: (params) => {
            const p = obj(params);
            return { station: str(p, "station"), book: str(p, "book"), ref: str(p, "ref") };
          },
          run: (p: { station: string; book: string; ref: string }) =>
            Effect.flatMap(env.exchange(p.station, "GET", `/books/${enc(p.book)}/images/${enc(p.ref)}`, [], new Uint8Array()), (r) => {
              if (r.status < 200 || r.status >= 300) return Effect.fail(new CoreError("not_found", `图片读取失败（${r.status}）`));
              const type = r.headers.find(([k]) => k.toLowerCase() === "content-type")?.[1] ?? "application/octet-stream";
              return Effect.succeed(new Beside({ type, size: r.body.length }, r.body));
            }),
          station: (p: { station: string }) => p.station,
        },
        "place.set": {
          parse: (params) => {
            const p = obj(params);
            return { station: str(p, "station"), book: str(p, "book"), place: placeOf(p.place) };
          },
          run: (p: { station: string; book: string; place: Place }) => {
            setPlace(p.station, p.book, p.place);
            return Effect.as(env.request(p.station, "PUT", `/books/${enc(p.book)}/place`, p.place, { quiet: true }), null);
          },
          station: (p: { station: string }) => p.station,
        },
        "note.put": {
          parse: (params) => {
            const p = obj(params);
            const note = obj(p.note);
            return { station: str(p, "station"), book: str(p, "book"), id: str(note, "id"), note };
          },
          run: (p: { station: string; book: string; id: string; note: Params }) =>
            Effect.andThen(env.request(p.station, "PUT", `/books/${enc(p.book)}/notes/${enc(p.id)}`, p.note), Effect.as(read(topic.notes(p.station, p.book)), null)),
          station: (p: { station: string }) => p.station,
          counts: true,
        },
        "note.remove": {
          parse: (params) => {
            const p = obj(params);
            return { station: str(p, "station"), book: str(p, "book"), id: str(p, "id") };
          },
          run: (p: { station: string; book: string; id: string }) =>
            Effect.andThen(env.request(p.station, "DELETE", `/books/${enc(p.book)}/notes/${enc(p.id)}`, null), Effect.as(read(topic.notes(p.station, p.book)), null)),
          station: (p: { station: string }) => p.station,
          counts: true,
        },
        // Photos' thumbnails, many at once (a grid's screenful): their bytes one after another beside the answer, where
        // each is in them (`index`: id, offset, length, w, h).
        thumbs: {
          parse: (params) => {
            const p = obj(params);
            const ids = Array.isArray(p.ids) ? p.ids.filter((i): i is string => typeof i === "string" && /^[0-9a-f]{1,64}$/.test(i)) : [];
            if (ids.length === 0 || ids.length > 64) throw CoreError.invalid("ids: 1 to 64 photos");
            return { station: str(p, "station"), ids, size: p.size === "large" ? "large" : "grid" };
          },
          run: (p: { station: string; ids: string[]; size: string }) =>
            Effect.flatMap(env.exchange(p.station, "GET", `/photos/thumbs?ids=${p.ids.join(",")}&size=${p.size}`, [], new Uint8Array()), (r) => {
              if (r.status < 200 || r.status >= 300) return Effect.fail(new CoreError("not_found", `缩略图读取失败（${r.status}）`));
              const said = r.headers.find(([k]) => k.toLowerCase() === "stillfail-index")?.[1] ?? "[]";
              let index: unknown;
              try {
                index = JSON.parse(said);
              } catch {
                index = [];
              }
              return Effect.succeed(new Beside({ index }, r.body));
            }),
          station: (p: { station: string }) => p.station,
        },
        // One photo's thumbnail (`large`: to look at it), its bytes beside the answer.
        thumb: {
          parse: (params) => {
            const p = obj(params);
            return { station: str(p, "station"), id: str(p, "id"), size: p.size === "grid" ? "grid" : "large" };
          },
          run: (p: { station: string; id: string; size: string }) =>
            Effect.flatMap(env.exchange(p.station, "GET", `/photos/thumbs/${enc(p.id)}?size=${p.size}`, [], new Uint8Array()), (r) => {
              if (r.status < 200 || r.status >= 300) return Effect.fail(new CoreError("not_found", `缩略图读取失败（${r.status}）`));
              const header = (name: string) => r.headers.find(([k]) => k.toLowerCase() === name)?.[1];
              return Effect.succeed(new Beside({ type: header("content-type") ?? "image/jpeg", w: Number(header("stillfail-width") ?? 0), h: Number(header("stillfail-height") ?? 0) }, r.body));
            }),
          station: (p: { station: string }) => p.station,
        },
        // A photo or video as it is: when, how big, where on the drive (its original read as a drive file), its camera.
        item: {
          parse: (params) => {
            const p = obj(params);
            return { station: str(p, "station"), id: str(p, "id") };
          },
          run: (p: { station: string; id: string }) => env.request(p.station, "GET", `/photos/items/${enc(p.id)}`, null),
          station: (p: { station: string }) => p.station,
        },
        // The folders the photos are from (the phones' backups always among them), and setting them (owners and admins).
        "photos.folders": {
          parse: (params) => ({ station: str(obj(params), "station") }),
          run: (p: { station: string }) => env.request(p.station, "GET", "/photos/folders", null),
          station: (p: { station: string }) => p.station,
        },
        "photos.setFolders": {
          parse: (params) => {
            const p = obj(params);
            const folders = Array.isArray(p.folders) ? p.folders.map(obj).map((f) => ({ root: str(f, "root"), path: typeof f.path === "string" ? f.path : "" })) : [];
            return { station: str(p, "station"), folders };
          },
          run: (p: { station: string; folders: { root: string; path: string }[] }) =>
            Effect.tap(env.request(p.station, "PUT", "/photos/folders", { folders: p.folders }), () => read(topic.albums(p.station))),
          station: (p: { station: string }) => p.station,
          counts: true,
        },
        // A phone's backup: whether a photo is there already (by its sha256), and its parts sent up, resumed from `have`.
        "photos.has": {
          parse: (params) => {
            const p = obj(params);
            const hash = str(p, "hash");
            if (!/^[0-9a-f]{64}$/.test(hash)) throw CoreError.invalid("hash: a sha256");
            return { station: str(p, "station"), hash };
          },
          run: (p: { station: string; hash: string }) => env.request(p.station, "GET", `/photos/has?hash=${p.hash}`, null, { quiet: true }),
          station: (p: { station: string }) => p.station,
        },
        "photos.upload": {
          parse: (params, bytes) => {
            const p = obj(params);
            if (bytes === undefined || bytes.length === 0) throw CoreError.invalid("bytes: the part going up");
            const hash = str(p, "hash");
            if (!/^[0-9a-f]{64}$/.test(hash)) throw CoreError.invalid("hash: a sha256");
            return { station: str(p, "station"), name: str(p, "name"), size: count(p, "size"), hash, taken: typeof p.taken === "number" ? p.taken : null, offset: count(p, "offset"), bytes };
          },
          run: (p: { station: string; name: string; size: number; hash: string; taken: number | null; offset: number; bytes: Uint8Array }) => {
            const q = `name=${enc(p.name)}&size=${p.size}&hash=${p.hash}&offset=${p.offset}${p.taken === null ? "" : `&taken=${p.taken}`}`;
            return Effect.flatMap(env.exchange(p.station, "POST", `/photos/upload?${q}`, [["content-type", "application/octet-stream"]], p.bytes, { quiet: true }), (r) => {
              let said: unknown = {};
              try {
                said = JSON.parse(new TextDecoder().decode(r.body));
              } catch {}
              return r.status >= 200 && r.status < 300 ? Effect.succeed(said) : Effect.fail(new CoreError("upload", String(obj(said).error ?? `上传失败（${r.status}）`)));
            });
          },
          station: (p: { station: string }) => p.station,
        },
        // How a film or an episode is played on this client (`client`: the formats it decodes itself): its file as it is
        // (read as a drive file), or an HLS stream made as it is played; its subtitles and audio tracks.
        "video.play": {
          parse: (params) => {
            const p = obj(params);
            const client = typeof p.client === "string" && /^[a-z0-9,]{0,200}$/.test(p.client) ? p.client : "";
            return { station: str(p, "station"), id: str(p, "id"), client };
          },
          run: (p: { station: string; id: string; client: string }) => env.request(p.station, "GET", `/videos/${enc(p.id)}/play?client=${p.client}`, null),
          station: (p: { station: string }) => p.station,
        },
        // Any of a film's streamed parts (`/videos/…`: its HLS lists and segments, its subtitles), bytes beside the answer:
        // what an app's player loads through its own loader.
        "video.fetch": {
          parse: (params) => {
            const p = obj(params);
            const path = str(p, "path");
            if (!/^\/videos\/[^?#]*(\?[^#]*)?$/.test(path) || path.includes("..")) throw CoreError.invalid("path: one of the videos' own");
            return { station: str(p, "station"), path };
          },
          run: (p: { station: string; path: string }) =>
            Effect.flatMap(env.exchange(p.station, "GET", p.path, [], new Uint8Array(), { quiet: true }), (r) => {
              if (r.status < 200 || r.status >= 300) return Effect.fail(new CoreError("not_found", `读取失败（${r.status}）`));
              const type = r.headers.find(([k]) => k.toLowerCase() === "content-type")?.[1] ?? "application/octet-stream";
              return Effect.succeed(new Beside({ type, size: r.body.length }, r.body));
            }),
          station: (p: { station: string }) => p.station,
        },
        "video.poster": {
          parse: (params) => {
            const p = obj(params);
            return { station: str(p, "station"), id: str(p, "id") };
          },
          run: (p: { station: string; id: string }) =>
            Effect.flatMap(env.exchange(p.station, "GET", `/videos/posters/${enc(p.id)}`, [], new Uint8Array()), (r) => {
              if (r.status < 200 || r.status >= 300) return Effect.fail(new CoreError("not_found", `海报读取失败（${r.status}）`));
              const header = (name: string) => r.headers.find(([k]) => k.toLowerCase() === name)?.[1];
              return Effect.succeed(new Beside({ type: header("content-type") ?? "image/jpeg", w: Number(header("stillfail-width") ?? 0), h: Number(header("stillfail-height") ?? 0) }, r.body));
            }),
          station: (p: { station: string }) => p.station,
        },
        // Where the viewer is in a film or an episode: shown at once, the service keeping the latest (`at`).
        "video.progress.set": {
          parse: (params) => {
            const p = obj(params);
            const position = typeof p.position === "number" && Number.isFinite(p.position) && p.position >= 0 ? p.position : -1;
            if (position < 0) throw CoreError.invalid("position: seconds into it");
            return { station: str(p, "station"), id: str(p, "id"), progress: { position, at: count(p, "at"), ...(p.done === true ? { done: true } : {}) } };
          },
          run: (p: { station: string; id: string; progress: { position: number; at: number; done?: boolean } }) => {
            const key = `progress/${p.id}`;
            const was = obj(obj(env.kept(p.station, key)).progress);
            if (typeof was.at !== "number" || was.at <= p.progress.at) env.keep(p.station, key, { progress: p.progress }, { topic: T.progress, station: p.station, id: p.id });
            return Effect.as(env.request(p.station, "PUT", `/videos/${enc(p.id)}/progress`, p.progress, { quiet: true }), null);
          },
          station: (p: { station: string }) => p.station,
        },
        "video.folders": {
          parse: (params) => ({ station: str(obj(params), "station") }),
          run: (p: { station: string }) => env.request(p.station, "GET", "/videos/folders", null),
          station: (p: { station: string }) => p.station,
        },
        "video.setFolders": {
          parse: (params) => {
            const p = obj(params);
            const folders = Array.isArray(p.folders)
              ? p.folders.map(obj).map((f) => {
                  if (f.kind !== "movies" && f.kind !== "shows") throw CoreError.invalid("kind: movies or shows");
                  return { root: str(f, "root"), path: typeof f.path === "string" ? f.path : "", kind: f.kind };
                })
              : [];
            return { station: str(p, "station"), folders };
          },
          run: (p: { station: string; folders: unknown[] }) => Effect.as(env.request(p.station, "PUT", "/videos/folders", { folders: p.folders }), null),
          station: (p: { station: string }) => p.station,
          counts: true,
        },
        // A book file, or every book in a folder, of the station's drive put on the shelf.
        import: {
          parse: (params) => {
            const p = obj(params);
            return { station: str(p, "station"), root: str(p, "root"), path: typeof p.path === "string" ? p.path : "" };
          },
          run: (p: { station: string; root: string; path: string }) =>
            Effect.tap(env.request(p.station, "POST", "/books/import", { root: p.root, path: p.path }), () => read(topic.shelf(p.station))),
          station: (p: { station: string }) => p.station,
          counts: true,
        },
        remove: {
          parse: (params) => {
            const p = obj(params);
            return { station: str(p, "station"), book: str(p, "book") };
          },
          run: (p: { station: string; book: string }) =>
            Effect.andThen(env.request(p.station, "DELETE", `/books/${enc(p.book)}`, null), Effect.as(read(topic.shelf(p.station)), null)),
          station: (p: { station: string }) => p.station,
          counts: true,
        },
      },
    };
  },
};
