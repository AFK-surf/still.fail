// The media service's HTTP (docs/media-service.md), on the unix socket the station forwards `/admin/api/m/media/…` to:
// each request comes with its member (`stillfail-viewer`, verified by the station), JSON in and out, refusals as
// `{error, code}`. Books are the member's workspace's; places and notes the member's own; the photo library (photos.ts)
// and the video library (videos.ts, played by hls.ts) the station's, for the members who may write.
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { createReadStream, existsSync, mkdirSync, unlinkSync } from "node:fs";
import { stat } from "node:fs/promises";
import { join } from "node:path";
import { MediaError, bad } from "./errors.ts";
import { type Tools, tools as findTools } from "./ffmpeg.ts";
import { DEFAULT_CAP, type Source, Streamer, clientOf, decide } from "./hls.ts";
import { importPath } from "./importer.ts";
import { Library, defaultBackup } from "./photos.ts";
import { PART, type StationLink } from "./station.ts";
import { type Note, type Place, type Store, openStore } from "./store.ts";
import { Videos } from "./videos.ts";

/// The member a request is for, as the station gives it (`home`: whether its workspace is the station's home
/// workspace); `raw` is the header as it came, passed back as it is when asking the station for the member.
export type Viewer = { sub: string; email: string; name: string; role: string; workspace: string; home: boolean; raw: string };

/// Roles that may change the shelf (import, remove); others (`viewer`) only read, and keep their own place and notes.
const WRITERS = new Set(["owner", "admin", "member"]);

/// The routes a viewer may send a change to (regex sources, relative to the module's root): their own place and notes.
export const VIEWER_WRITES = ["^/books/[^/]+/place$", "^/books/[^/]+/notes/[^/]+$"];

/// The `stillfail-viewer` header: JSON, all ASCII (the station escapes every other character as \uXXXX).
export function viewerOf(header: string | string[] | undefined): Viewer {
  const raw = Array.isArray(header) ? header[0] : header;
  if (!raw) throw new MediaError("forbidden", "缺少成员身份");
  let v: Record<string, unknown> | null = null;
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) v = parsed as Record<string, unknown>;
  } catch {}
  const s = (k: string) => (typeof v?.[k] === "string" ? (v[k] as string) : "");
  if (!v || !s("sub") || !s("workspace")) throw new MediaError("forbidden", "成员身份无效");
  return { sub: s("sub"), email: s("email"), name: s("name"), role: s("role"), workspace: s("workspace"), home: v.home === true, raw };
}

type Ctx = { viewer: Viewer; params: string[]; query: URLSearchParams; body: () => Promise<Record<string, unknown>>; req: IncomingMessage; res: ServerResponse };
/// Bytes kept for good (by default: a book's images are named by their content), or as `cache` says, with `headers`.
/// `file`: a file of the module's folder, sent as it is read.
type Reply = { status?: number; json: unknown } | { bytes: Uint8Array; type: string; cache?: string; headers?: Record<string, string> } | { file: string; type: string; cache?: string } | { json: string; raw: true } | null;
/// Who may: any member, a member who may write (`writer`: changes to the shelf; `photos`, `videos`: anything of the
/// photo or the video library), an owner or admin (`keeper`: the photo library's folders; `videoKeeper`: the video
/// library's).
type Route = { method: string; pattern: RegExp; who: "anyone" | "writer" | "photos" | "keeper" | "videos" | "videoKeeper"; handle: (c: Ctx) => Promise<Reply> | Reply };

const KEEPERS = new Set(["owner", "admin"]);

const MAX_BODY = 1024 * 1024;

/// A body as it is, `most` bytes at most.
function readBytes(req: IncomingMessage, most: number): Promise<Buffer> {
  const tooLarge = () => new MediaError("too_large", `一段最多 ${Math.round(most / 1024 / 1024)} MB`);
  return new Promise((done, fail) => {
    if (Number(req.headers["content-length"] ?? 0) > most) {
      req.resume();
      return fail(tooLarge());
    }
    const parts: Buffer[] = [];
    let size = 0;
    req.on("data", (b: Buffer) => {
      size += b.length;
      if (size > most) {
        fail(tooLarge());
        req.destroy();
      } else parts.push(b);
    });
    req.on("end", () => done(Buffer.concat(parts)));
    req.on("error", fail);
  });
}

function readBody(req: IncomingMessage): Promise<Record<string, unknown>> {
  return new Promise((done, fail) => {
    const parts: Buffer[] = [];
    let size = 0;
    req.on("data", (b: Buffer) => {
      size += b.length;
      if (size > MAX_BODY) {
        fail(new MediaError("too_large", "请求内容太大"));
        req.destroy();
      } else parts.push(b);
    });
    req.on("end", () => {
      const text = Buffer.concat(parts).toString("utf8");
      if (!text.trim()) return done({});
      try {
        const v = JSON.parse(text) as unknown;
        if (v === null || typeof v !== "object" || Array.isArray(v)) throw new Error("not an object");
        done(v as Record<string, unknown>);
      } catch {
        fail(bad("请求内容不是有效的 JSON"));
      }
    });
    req.on("error", fail);
  });
}

const int = (v: unknown, what: string, min = 0): number => {
  if (typeof v !== "number" || !Number.isInteger(v) || v < min) throw bad(`${what}无效`);
  return v;
};
const time = (v: unknown): number => {
  if (typeof v !== "number" || !Number.isFinite(v) || v < 0) throw bad("时间（at）无效");
  return Math.round(v);
};
const str = (v: unknown, what: string, most: number, optional = false): string | undefined => {
  if (v === undefined || v === null) {
    if (optional) return undefined;
    throw bad(`缺少${what}`);
  }
  if (typeof v !== "string" || v.length > most) throw bad(`${what}无效`);
  return v;
};

const NOTE_ID = /^[A-Za-z0-9_-]{1,64}$/;

/// A thumbnail's size: `grid` and `large` are the same one for now (the station's 720×600).
const thumbSize = (q: URLSearchParams) => {
  const size = q.get("size") ?? "large";
  if (size !== "grid" && size !== "large") throw bad("size 只能是 grid 或 large");
  return size;
};

/// Who listens to `/events`: a member's connections, by workspace, account and role.
type Listener = { workspace: string; sub: string; role: string; home: boolean; res: ServerResponse };

export type Service = { server: Server; store: Store; photos: Library; videos: Videos; streamer: Streamer; close: () => Promise<void> };

/// `backup`: the photo library's backup folder (MEDIA_BACKUP_DIR, else ~/Pictures/still.fail); `sips`: macOS's sips,
/// for the thumbnails of HEIC and GIF (and the ThumbHashes of videos' posters), null where there is none; `tools`:
/// ffmpeg and ffprobe (found as ffmpeg.ts `tools` finds them when not given); `hlsCap`: the bytes HLS segments are kept in
/// (MEDIA_HLS_CAP, else 20 GB).
export type Options = { dir: string; socket: string; station: StationLink; backup?: string; sips?: string | null; tools?: Tools; hlsCap?: number };

/// The photo library's changes are told this long after the last one.
const PHOTOS_SETTLE = 1000;
/// The most thumbnails asked at once.
const MOST_THUMBS = 64;

/// Starts the service: opens media.db in `dir`, listens on `socket`.
export async function startService(o: Options): Promise<Service> {
  mkdirSync(o.dir, { recursive: true });
  const store = openStore(join(o.dir, "media.db"));
  const listeners = new Set<Listener>();
  const send = (pick: (l: Listener) => boolean, event: string, data: unknown) => {
    const frame = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
    for (const l of listeners) if (pick(l)) l.res.write(frame);
  };
  const shelfChanged = (workspace: string) => send((l) => l.workspace === workspace, "shelf", {});
  const placeChanged = (v: Viewer, book: string) => send((l) => l.workspace === v.workspace && l.sub === v.sub, "place", { book });
  const notesChanged = (v: Viewer, book: string) => send((l) => l.workspace === v.workspace && l.sub === v.sub, "notes", { book });
  let photosTimer: NodeJS.Timeout | null = null;
  const photosChanged = () => {
    if (photosTimer) clearTimeout(photosTimer);
    photosTimer = setTimeout(() => {
      photosTimer = null;
      send((l) => WRITERS.has(l.role) && l.home, "photos", {});
    }, PHOTOS_SETTLE);
    photosTimer.unref();
  };
  const photos = new Library({
    store,
    link: o.station,
    dir: o.dir,
    backup: o.backup ?? defaultBackup(),
    sips: o.sips !== undefined ? o.sips : process.platform === "darwin" ? "/usr/bin/sips" : null,
    changed: photosChanged,
  });
  let videosTimer: NodeJS.Timeout | null = null;
  const videosChanged = () => {
    if (videosTimer) clearTimeout(videosTimer);
    videosTimer = setTimeout(() => {
      videosTimer = null;
      send((l) => WRITERS.has(l.role) && l.home, "videos", {});
    }, PHOTOS_SETTLE);
    videosTimer.unref();
  };
  const progressChanged = (v: Viewer, id: string) => send((l) => l.sub === v.sub && l.home && WRITERS.has(l.role), "progress", { id });
  const tools = o.tools ?? findTools();
  if (!tools.ffmpeg || !tools.ffprobe) console.error(`media: no ${[!tools.ffmpeg && "ffmpeg", !tools.ffprobe && "ffprobe"].filter(Boolean).join(" or ")}: videos are only named and played directly`);
  const videos = new Videos({ store, link: o.station, dir: o.dir, tools, sips: o.sips !== undefined ? o.sips : process.platform === "darwin" ? "/usr/bin/sips" : null, changed: videosChanged });
  const cap = Number(process.env.MEDIA_HLS_CAP);
  const streamer = new Streamer({ dir: o.dir, tools, cap: o.hlsCap ?? (Number.isFinite(cap) && cap > 0 ? cap : DEFAULT_CAP) });
  /// What HLS is made of: the video, probed, in a file the service may read itself, with ffmpeg there.
  const sourceOf = async (id: string): Promise<Source> => {
    const v = videos.item(id);
    const probe = videos.probeOf(v);
    if (!tools.ffmpeg) throw new MediaError("unsupported", "这台 station 没有 ffmpeg，只能直接播放");
    if (!probe?.video || !probe.duration) throw new MediaError("unsupported", "这个视频还没读出时长和编码，只能直接播放");
    const file = await videos.fileOf(v);
    if (!file) throw new MediaError("unsupported", "媒体服务读不到这个文件（受保护的文件夹），只能直接播放");
    return { id: v.id, file, probe, key: `${v.id}-${v.mtime}-${v.size}` };
  };
  const heartbeat = setInterval(() => {
    for (const l of listeners) l.res.write(": ping\n\n");
  }, 25_000);
  heartbeat.unref();

  /// The book `id` of the member's workspace, or 404.
  const bookOf = (v: Viewer, id: string) => {
    const b = store.book(v.workspace, id);
    if (!b) throw new MediaError("not_found", "找不到这本书");
    return b;
  };
  /// How far into the book a place is (0..1), by the chapters' chars.
  const readOf = (toc: { chars: number }[], p: Place) => {
    const total = toc.reduce((n, c) => n + c.chars, 0);
    if (total === 0) return 0;
    const chapter = Math.min(p.chapter, toc.length);
    const before = toc.slice(0, chapter).reduce((n, c) => n + c.chars, 0);
    const within = Math.min(p.offset, toc[chapter]?.chars ?? 0);
    return Math.min(1, (before + within) / total);
  };

  const routes: Route[] = [
    {
      method: "GET",
      pattern: /^\/books$/,
      who: "anyone",
      handle: ({ viewer }) => {
        const places = store.places(viewer.sub, viewer.workspace);
        const books = store.books(viewer.workspace).map((b) => {
          const place = places.get(b.id);
          return {
            id: b.id,
            title: b.title,
            author: b.author,
            format: b.format,
            cover: null,
            ...(b.cover ? { coverRef: b.cover } : {}),
            chapters: b.toc.length,
            added: b.added,
            ...(place ? { place, read: readOf(b.toc, place) } : {}),
          };
        });
        return { json: { books } };
      },
    },
    {
      method: "POST",
      pattern: /^\/books\/import$/,
      who: "writer",
      handle: async ({ viewer, body }) => {
        const b = await body();
        const root = str(b.root, "根目录（root）", 4096)!;
        const path = str(b.path ?? "", "路径（path）", 4096)!;
        const result = await importPath({ store, link: o.station, changed: shelfChanged }, viewer.raw, viewer.workspace, root, path);
        return { json: result };
      },
    },
    {
      method: "GET",
      pattern: /^\/books\/([^/]+)$/,
      who: "anyone",
      handle: ({ viewer, params }) => {
        const b = bookOf(viewer, params[0]!);
        return { json: { id: b.id, title: b.title, author: b.author, toc: b.toc } };
      },
    },
    {
      method: "DELETE",
      pattern: /^\/books\/([^/]+)$/,
      who: "writer",
      handle: ({ viewer, params }) => {
        if (!store.removeBook(viewer.workspace, params[0]!)) throw new MediaError("not_found", "找不到这本书");
        shelfChanged(viewer.workspace);
        return { json: {} };
      },
    },
    {
      method: "GET",
      pattern: /^\/books\/([^/]+)\/chapters\/(\d+)$/,
      who: "anyone",
      handle: ({ viewer, params }) => {
        const b = bookOf(viewer, params[0]!);
        const c = store.chapter(b.id, Number(params[1]));
        if (!c) throw new MediaError("not_found", "这本书没有这一章");
        return { json: `{"chars":${c.chars},"blocks":${c.blocks}}`, raw: true };
      },
    },
    {
      method: "GET",
      pattern: /^\/books\/([^/]+)\/images\/([^/]+)$/,
      who: "anyone",
      handle: ({ viewer, params }) => {
        const b = bookOf(viewer, params[0]!);
        const img = store.image(b.id, params[1]!);
        if (!img) throw new MediaError("not_found", "找不到这张图片");
        return { bytes: img.bytes, type: img.type };
      },
    },
    {
      method: "GET",
      pattern: /^\/books\/([^/]+)\/place$/,
      who: "anyone",
      handle: ({ viewer, params }) => {
        const b = bookOf(viewer, params[0]!);
        return { json: { place: store.place(b.id, viewer.sub) } };
      },
    },
    {
      method: "PUT",
      pattern: /^\/books\/([^/]+)\/place$/,
      who: "anyone",
      handle: async ({ viewer, params, body }) => {
        const b = bookOf(viewer, params[0]!);
        const v = await body();
        const chapter = int(v.chapter, "章节（chapter）");
        if (chapter >= b.toc.length) throw bad("章节（chapter）超出了这本书的范围");
        const p: Place = { chapter, offset: int(v.offset, "位置（offset）"), at: time(v.at) };
        const kept = store.setPlace(b.id, viewer.sub, p);
        if (kept.changed) placeChanged(viewer, b.id);
        return { json: { place: kept.place } };
      },
    },
    {
      method: "GET",
      pattern: /^\/books\/([^/]+)\/notes$/,
      who: "anyone",
      handle: ({ viewer, params }) => {
        const b = bookOf(viewer, params[0]!);
        return { json: { notes: store.notes(b.id, viewer.sub) } };
      },
    },
    {
      method: "PUT",
      pattern: /^\/books\/([^/]+)\/notes\/([^/]+)$/,
      who: "anyone",
      handle: async ({ viewer, params, body }) => {
        const b = bookOf(viewer, params[0]!);
        const id = params[1]!;
        if (!NOTE_ID.test(id)) throw bad("笔记 id 无效（1 到 64 个字母、数字、_ 或 -）");
        const v = await body();
        const chapter = int(v.chapter, "章节（chapter）");
        if (chapter >= b.toc.length) throw bad("章节（chapter）超出了这本书的范围");
        const start = int(v.start, "开始位置（start）");
        const end = int(v.end, "结束位置（end）");
        if (end < start) throw bad("结束位置（end）不能在开始位置（start）之前");
        const note = str(v.note, "笔记（note）", 100_000, true);
        const n: Note = { id, chapter, start, end, text: str(v.text, "划线文字（text）", 20_000)!, ...(note !== undefined ? { note } : {}), color: str(v.color, "颜色（color）", 32)!, at: time(v.at) };
        const kept = store.putNote(b.id, viewer.sub, n);
        if (!kept.mine) throw new MediaError("forbidden", "这条笔记不是你的");
        if (kept.changed) notesChanged(viewer, b.id);
        return { json: { note: kept.note } };
      },
    },
    {
      method: "DELETE",
      pattern: /^\/books\/([^/]+)\/notes\/([^/]+)$/,
      who: "anyone",
      handle: ({ viewer, params }) => {
        const b = bookOf(viewer, params[0]!);
        const r = store.removeNote(b.id, viewer.sub, params[1]!);
        if (r === "missing") throw new MediaError("not_found", "找不到这条笔记");
        if (r === "theirs") throw new MediaError("forbidden", "这条笔记不是你的");
        notesChanged(viewer, b.id);
        return { json: {} };
      },
    },
    {
      method: "GET",
      pattern: /^\/photos\/folders$/,
      who: "photos",
      handle: () => ({ json: photos.view() }),
    },
    {
      method: "PUT",
      pattern: /^\/photos\/folders$/,
      who: "keeper",
      handle: async ({ viewer, body }) => ({ json: await photos.setFolders(viewer, (await body()).folders) }),
    },
    {
      method: "GET",
      pattern: /^\/photos\/timeline$/,
      who: "photos",
      handle: ({ query }) => ({ json: photos.timeline(query) }),
    },
    {
      method: "GET",
      pattern: /^\/photos\/albums$/,
      who: "photos",
      handle: () => ({ json: photos.albums() }),
    },
    {
      method: "GET",
      pattern: /^\/photos\/items\/([^/]+)$/,
      who: "photos",
      handle: ({ params }) => ({ json: photos.item(params[0]!) }),
    },
    {
      method: "GET",
      pattern: /^\/photos\/thumbs\/([^/]+)$/,
      who: "photos",
      handle: async ({ params, query }) => {
        thumbSize(query);
        const t = await photos.thumb(params[0]!);
        if (!t) throw new MediaError("not_found", "这个文件做不出缩略图");
        return { bytes: t.bytes, type: t.type, cache: "private, no-cache", headers: { "stillfail-width": String(t.w), "stillfail-height": String(t.h), ...(t.hash ? { "stillfail-thumbhash": t.hash } : {}) } };
      },
    },
    {
      method: "GET",
      pattern: /^\/photos\/thumbs$/,
      who: "photos",
      handle: async ({ query }) => {
        thumbSize(query);
        const ids = [...new Set((query.get("ids") ?? "").split(",").filter((x) => x !== ""))];
        if (ids.length === 0) throw bad("缺少 ids");
        if (ids.length > MOST_THUMBS) throw bad(`一次最多 ${MOST_THUMBS} 张`);
        // Four made at a time; one that cannot be made (or is gone) is left out of the index.
        const made: (Awaited<ReturnType<Library["thumb"]>> | null)[] = new Array(ids.length).fill(null);
        let next = 0;
        const worker = async () => {
          while (next < ids.length) {
            const i = next++;
            made[i] = await photos.thumb(ids[i]!).catch((e) => {
              if (e instanceof MediaError && e.code !== "station") return null;
              throw e;
            });
          }
        };
        await Promise.all([worker(), worker(), worker(), worker()]);
        const index: { id: string; offset: number; length: number; w: number; h: number }[] = [];
        const parts: Uint8Array[] = [];
        let offset = 0;
        made.forEach((t, i) => {
          if (!t) return;
          index.push({ id: ids[i]!, offset, length: t.bytes.length, w: t.w, h: t.h });
          parts.push(t.bytes);
          offset += t.bytes.length;
        });
        return { bytes: Buffer.concat(parts), type: "application/octet-stream", cache: "private, no-cache", headers: { "stillfail-index": JSON.stringify(index) } };
      },
    },
    {
      method: "GET",
      pattern: /^\/photos\/has$/,
      who: "photos",
      handle: ({ query }) => ({ json: photos.has(query.get("hash")) }),
    },
    {
      method: "POST",
      pattern: /^\/photos\/upload$/,
      who: "photos",
      handle: ({ viewer, query, req }) => photos.upload(viewer, query, () => readBytes(req, PART)),
    },
    {
      method: "GET",
      pattern: /^\/videos\/folders$/,
      who: "videos",
      handle: () => ({ json: videos.view() }),
    },
    {
      method: "PUT",
      pattern: /^\/videos\/folders$/,
      who: "videoKeeper",
      handle: async ({ viewer, body }) => ({ json: await videos.setFolders(viewer, (await body()).folders) }),
    },
    {
      method: "GET",
      pattern: /^\/videos\/library$/,
      who: "videos",
      handle: ({ viewer }) => ({ json: videos.library(viewer) }),
    },
    {
      method: "GET",
      pattern: /^\/videos\/titles\/([^/]+)$/,
      who: "videos",
      handle: ({ viewer, params }) => ({ json: videos.title(viewer, params[0]!) }),
    },
    {
      method: "GET",
      pattern: /^\/videos\/episodes\/([^/]+)$/,
      who: "videos",
      handle: ({ viewer, params }) => ({ json: videos.episode(viewer, params[0]!) }),
    },
    {
      method: "GET",
      pattern: /^\/videos\/posters\/([^/]+)$/,
      who: "videos",
      handle: async ({ params }) => {
        const p = await videos.poster(params[0]!);
        if (!p) throw new MediaError("not_found", "这部片子没有海报");
        return { bytes: p.bytes, type: p.type, cache: "private, no-cache", headers: { "stillfail-width": String(p.w), "stillfail-height": String(p.h), ...(p.hash ? { "stillfail-thumbhash": p.hash } : {}) } };
      },
    },
    {
      method: "GET",
      pattern: /^\/videos\/([^/]+)\/play$/,
      who: "videos",
      handle: async ({ params, query }) => {
        const v = videos.item(params[0]!);
        const p = videos.probeOf(v);
        const d = decide(v.path, p, clientOf(query.get("client")));
        const file = tools.ffmpeg ? await videos.fileOf(v) : null;
        const hls = !d.direct && file && (await streamer.can(p, d.mode)) ? `/videos/${v.id}/hls/master.m3u8?video=${d.mode}` : undefined;
        const subtitles = videos
          .subtitles(v)
          .filter((s) => s.text && (s.external || file))
          .map((s) => ({ id: s.id, lang: s.lang, title: s.title, url: `/videos/${v.id}/subtitles/${s.id}.vtt`, ...(s.forced ? { forced: true } : {}), ...(s.default ? { default: true } : {}) }));
        return {
          json: {
            direct: d.direct || hls === undefined,
            ...(hls ? { hls } : {}),
            file: { root: v.root, path: v.path },
            subtitles,
            audio: (p?.audio ?? []).map((a) => ({ index: a.index, lang: a.lang, title: a.title, codec: a.codec, channels: a.channels, ...(a.default ? { default: true } : {}) })),
            duration: videos.durationOf(v),
          },
        };
      },
    },
    {
      method: "GET",
      pattern: /^\/videos\/([^/]+)\/hls\/master\.m3u8$/,
      who: "videos",
      handle: async ({ params, query }) => {
        const text = await streamer.master(await sourceOf(params[0]!), query);
        return { bytes: Buffer.from(text), type: "application/vnd.apple.mpegurl", cache: "private, no-cache" };
      },
    },
    {
      method: "GET",
      pattern: /^\/videos\/([^/]+)\/hls\/([^/]+)\/index\.m3u8$/,
      who: "videos",
      handle: async ({ params }) => {
        const text = await streamer.media(await sourceOf(params[0]!), params[1]!);
        return { bytes: Buffer.from(text), type: "application/vnd.apple.mpegurl", cache: "private, no-cache" };
      },
    },
    {
      method: "GET",
      pattern: /^\/videos\/([^/]+)\/hls\/([^/]+)\/init\.mp4$/,
      who: "videos",
      handle: async ({ params }) => ({ file: await streamer.init(await sourceOf(params[0]!), params[1]!), type: "video/mp4", cache: "private, no-cache" }),
    },
    {
      method: "GET",
      pattern: /^\/videos\/([^/]+)\/hls\/([^/]+)\/(\d+)\.m4s$/,
      who: "videos",
      handle: async ({ params }) => ({ file: await streamer.segment(await sourceOf(params[0]!), params[1]!, Number(params[2])), type: "video/iso.segment", cache: "private, no-cache" }),
    },
    {
      method: "GET",
      pattern: /^\/videos\/([^/]+)\/subtitles\/([^/]+)\.vtt$/,
      who: "videos",
      handle: async ({ params }) => ({ bytes: Buffer.from(await videos.subtitle(params[0]!, params[1]!)), type: "text/vtt; charset=utf-8", cache: "private, no-cache" }),
    },
    {
      method: "GET",
      pattern: /^\/videos\/([^/]+)\/progress$/,
      who: "videos",
      handle: ({ viewer, params }) => ({ json: videos.progress(viewer, params[0]!) }),
    },
    {
      method: "PUT",
      pattern: /^\/videos\/([^/]+)\/progress$/,
      who: "videos",
      handle: async ({ viewer, params, body }) => {
        const kept = videos.setProgress(viewer, params[0]!, await body());
        if (kept.changed) progressChanged(viewer, params[0]!);
        return { json: kept.json };
      },
    },
    {
      method: "GET",
      pattern: /^\/events$/,
      who: "anyone",
      handle: ({ viewer, res }) => {
        res.writeHead(200, { "content-type": "text/event-stream; charset=utf-8", "cache-control": "no-store", "x-accel-buffering": "no" });
        res.write(": ok\n\n");
        const l: Listener = { workspace: viewer.workspace, sub: viewer.sub, role: viewer.role, home: viewer.home, res };
        listeners.add(l);
        res.on("close", () => listeners.delete(l));
        return null;
      },
    },
  ];

  /// Once stopping, connections are not kept for another request.
  let stopping = false;
  const answer = (res: ServerResponse, status: number, body: string, type = "application/json; charset=utf-8") => {
    res.writeHead(status, { "content-type": type, "content-length": Buffer.byteLength(body), "cache-control": "no-store", ...(stopping ? { connection: "close" } : {}) });
    res.end(body);
  };
  const fail = (res: ServerResponse, e: unknown) => {
    if (res.headersSent) return void res.destroy();
    if (e instanceof MediaError) return answer(res, e.status, JSON.stringify({ error: e.message, code: e.code }));
    console.error("media: request failed", e);
    answer(res, 500, JSON.stringify({ error: "媒体服务出错了，请稍后再试", code: "internal" }));
  };

  const handle = async (req: IncomingMessage, res: ServerResponse) => {
    const url = new URL(req.url ?? "/", "http://media");
    const path = url.pathname.length > 1 ? url.pathname.replace(/\/+$/, "") : url.pathname;
    if (req.method === "GET" && path === "/manifest") return answer(res, 200, JSON.stringify({ viewerWrites: VIEWER_WRITES }));
    const viewer = viewerOf(req.headers["stillfail-viewer"]);
    const matching = routes.filter((r) => r.pattern.test(path));
    const route = matching.find((r) => r.method === req.method);
    if (!route) throw new MediaError("not_found", matching.length > 0 ? "不支持这个请求方法" : "没有这个接口", matching.length > 0 ? 405 : 404);
    if (route.who === "writer" && !WRITERS.has(viewer.role)) throw new MediaError("forbidden", "只读成员不能修改书架");
    if (route.who === "photos" && !WRITERS.has(viewer.role)) throw new MediaError("forbidden", "只读成员看不到照片");
    if (route.who === "videos" && !WRITERS.has(viewer.role)) throw new MediaError("forbidden", "只读成员看不到影视");
    // The photos and videos are the station's own people's: its home workspace's, not those of another it joined.
    if ((route.who === "photos" || route.who === "keeper") && !viewer.home) throw new MediaError("forbidden", "照片只给这台 station 所在的主 workspace 的成员看");
    if ((route.who === "videos" || route.who === "videoKeeper") && !viewer.home) throw new MediaError("forbidden", "影视只给这台 station 所在的主 workspace 的成员看");
    if (route.who === "keeper" && !KEEPERS.has(viewer.role)) throw new MediaError("forbidden", "只有 owner 和 admin 能设置照片库的文件夹");
    if (route.who === "videoKeeper" && !KEEPERS.has(viewer.role)) throw new MediaError("forbidden", "只有 owner 和 admin 能设置片库的文件夹");
    if (route.who === "photos" || route.who === "keeper") photos.noteWriter(viewer);
    let params: string[];
    try {
      params = route.pattern.exec(path)!.slice(1).map((p) => decodeURIComponent(p));
    } catch {
      throw bad("路径无效");
    }
    const reply = await route.handle({ viewer, params, query: url.searchParams, body: () => readBody(req), req, res });
    if (reply === null) return;
    if ("bytes" in reply) {
      res.writeHead(200, {
        "content-type": reply.type,
        "content-length": reply.bytes.byteLength,
        "cache-control": reply.cache ?? "private, max-age=31536000, immutable",
        ...reply.headers,
        ...(stopping ? { connection: "close" } : {}),
      });
      res.end(reply.bytes);
    } else if ("file" in reply) {
      const s = await stat(reply.file).catch(() => null);
      if (!s) throw new MediaError("not_found", "这一段已经不在了，请再试一次");
      res.writeHead(200, { "content-type": reply.type, "content-length": s.size, "cache-control": reply.cache ?? "private, no-cache", ...(stopping ? { connection: "close" } : {}) });
      const stream = createReadStream(reply.file);
      stream.on("error", () => res.destroy());
      res.on("close", () => stream.destroy());
      stream.pipe(res);
    } else if ("raw" in reply) answer(res, 200, reply.json);
    else answer(res, reply.status ?? 200, JSON.stringify(reply.json));
  };

  const server = createServer((req, res) => {
    handle(req, res).catch((e) => fail(res, e));
  });
  if (existsSync(o.socket)) unlinkSync(o.socket);
  photos.start();
  videos.start();
  await new Promise<void>((done, failed) => {
    server.once("error", failed);
    server.listen(o.socket, () => {
      server.off("error", failed);
      done();
    });
  });

  let closed: Promise<void> | null = null;
  return {
    server,
    store,
    photos,
    videos,
    streamer,
    close: () =>
      (closed ??= new Promise<void>((done) => {
        stopping = true;
        clearInterval(heartbeat);
        if (photosTimer) clearTimeout(photosTimer);
        if (videosTimer) clearTimeout(videosTimer);
        for (const l of listeners) l.res.destroy();
        listeners.clear();
        streamer.close();
        server.close(() => {
          Promise.all([photos.close(), videos.close()]).finally(() => {
            store.close();
            done();
          });
        });
        server.closeIdleConnections();
      })),
  };
}
