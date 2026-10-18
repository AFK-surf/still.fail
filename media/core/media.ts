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
} as const;

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
    const keyOf = (t: Topic) => `${t.topic}\n${String(t.book ?? "")}`;
    const follow = (station: string) =>
      Effect.scoped(
        Effect.gen(function* () {
          const reply = yield* env.stream(station, "/events");
          // Opened (again): what is shown may have changed meanwhile.
          for (const t of shown.get(station)?.values() ?? []) yield* Effect.ignore(read(t));
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
              const asked = event === "shelf" ? topic.shelf(station) : event === "place" ? topic.place(station, book) : event === "notes" ? topic.notes(station, book) : null;
              // A book changed: its contents too, if shown.
              const also = event === "shelf" ? [...of.values()].filter((t) => t.topic === T.book) : [];
              for (const t of [asked, ...also]) if (t && of.has(keyOf(t))) yield* Effect.ignore(read(t));
            }
          }
        }),
      ).pipe(
        Effect.ignore,
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
          env.fork(Effect.ignore(read(t)));
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
