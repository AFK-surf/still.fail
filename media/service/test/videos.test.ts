// The video library over the service's socket (src/videos.ts, hls.ts), with a fake station serving a folder of the
// disk: folders set by an owner and read as them, films and shows recognised by their names and .nfo, posters beside
// them or the station's, subtitles beside them as WebVTT, direct play without ffmpeg, each account's progress and
// "继续观看", events, who may. With an ffmpeg on PATH (a developer's: lavfi makes the fixtures): probing, a poster
// frame, the play decision against a client's list, HLS (remuxed and made H.264) with its segments on the timeline,
// embedded subtitles, the cache's cap.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { request } from "node:http";
import { join } from "node:path";
import { test } from "node:test";
import { tools as findTools } from "../src/ffmpeg.ts";
import { Streamer } from "../src/hls.ts";
import { photoId } from "../src/photos.ts";
import { MEMBER, OWNER, VIEWER, ascii, jpeg, listen, started, wait } from "./helpers.ts";

const write = (file: string, bytes: Buffer | string) => {
  mkdirSync(join(file, ".."), { recursive: true });
  writeFileSync(file, bytes);
};

async function until(f: () => Promise<boolean> | boolean, what: string, ms = 15_000) {
  const end = Date.now() + ms;
  while (!(await f())) {
    if (Date.now() > end) throw new Error(`timed out waiting: ${what}`);
    await wait(100);
  }
}

const nfo = (kind: string, fields: Record<string, string | number>) => `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<${kind}>\n${Object.entries(fields).map(([k, v]) => `  <${k}>${v}</${k}>`).join("\n")}\n</${kind}>\n`;
const b64 = (s: string) => Buffer.from(s).toString("base64");

/// Films and shows as people keep them, the videos only bytes (no ffmpeg reads them here).
function library(dir: string) {
  const films = join(dir, "films");
  write(join(films, "The.Matrix.1999.1080p.BluRay.x264-YTS.mkv"), "matrix");
  write(join(films, "The.Matrix.1999.1080p.BluRay.x264-YTS.zh.srt"), "1\n00:00:01,000 --> 00:00:02,000\n<i>你好</i>\n");
  write(join(films, "Inception (2010) [1080p].mkv"), "inception");
  write(join(films, "Inception (2010) [1080p]-poster.jpg"), jpeg(400, 600));
  write(join(films, "Heat (1995)", "movie.mkv"), "heat");
  write(join(films, "Heat (1995)", "movie-sample.mkv"), "sample");
  write(join(films, "Heat (1995)", "movie.nfo"), nfo("movie", { title: "Heat", originaltitle: "盗火线", year: 1995, plot: "A heist.", genre: "Crime / Thriller", runtime: 170 }));
  write(join(films, "Heat (1995)", "poster.jpg"), jpeg(500, 750));
  write(join(films, "Heat (1995)", "Extras", "Making.Of.mkv"), "extra");
  write(join(films, "让子弹飞 (2010)", "Let.the.Bullets.Fly.2010.mp4"), "bullets");
  write(join(films, "让子弹飞 (2010)", "Let.the.Bullets.Fly.2010.nfo"), nfo("movie", { title: "让子弹飞", year: 2010, runtime: 132 }));
  const shows = join(dir, "shows");
  write(join(shows, "Breaking Bad", "tvshow.nfo"), nfo("tvshow", { title: "绝命毒师", premiered: "2008-01-20", plot: "化学老师。" }));
  write(join(shows, "Breaking Bad", "poster.jpg"), jpeg(680, 1000));
  write(join(shows, "Breaking Bad", "Season 1", "Breaking.Bad.S01E01.720p.mkv"), "e1");
  write(join(shows, "Breaking Bad", "Season 1", "Breaking.Bad.S01E01.720p.nfo"), nfo("episodedetails", { title: "Pilot", season: 1, episode: 1 }));
  write(join(shows, "Breaking Bad", "Season 1", "Breaking.Bad.S01E02.720p.mkv"), "e2");
  write(join(shows, "Breaking Bad", "Season 2", "Breaking.Bad.S02E01.720p.mkv"), "e3");
  write(join(shows, "狂飙", "第1集.mp4"), "k1");
  write(join(shows, "狂飙", "第2集.mp4"), "k2");
  write(join(shows, "The.Office.US.S01E01.mkv"), "o1");
}

const id = (dir: string, path: string) => photoId(dir, path);

test("library: folders set by an owner, films and shows by names and .nfo, posters, subtitles, direct play", async (t) => {
  const s = await started(1 << 20);
  t.after(s.stop);
  library(s.dir);
  const member = listen(s.socket, MEMBER);
  await member.ready;
  t.after(member.close);

  assert.deepEqual((await s.call("GET", "/videos/folders", MEMBER)).json, { folders: [] });
  assert.equal((await s.call("PUT", "/videos/folders", MEMBER, { folders: [] })).status, 403, "a member sets no folders");
  assert.equal((await s.call("PUT", "/videos/folders", OWNER, { folders: [{ root: s.dir, path: "films" }] })).status, 400, "a folder has its kind");
  assert.equal((await s.call("PUT", "/videos/folders", OWNER, { folders: [{ root: s.dir, path: "films/Heat (1995)/movie.nfo", kind: "movies" }] })).status, 400, "a file is no folder");
  const set = await s.call("PUT", "/videos/folders", OWNER, { folders: [{ root: s.dir, path: "/films/", kind: "movies" }, { root: s.dir, path: "shows", kind: "shows" }] });
  assert.equal(set.status, 200, JSON.stringify(set.json));
  assert.deepEqual(set.json, { folders: [{ root: s.dir, path: "films", kind: "movies" }, { root: s.dir, path: "shows", kind: "shows" }] });
  await s.service.videos.settled();
  const reads = s.station.seen.asked.filter((a) => a.root === s.dir && a.route !== "/drive/stat");
  assert.ok(reads.length > 0 && reads.every((a) => a.viewer.includes("u-owner")), "read as the owner who set the folders");
  await until(() => member.events.some((e) => e.event === "videos"), "the members told");

  const ids = {
    matrix: id(s.dir, "films/The.Matrix.1999.1080p.BluRay.x264-YTS.mkv"),
    inception: id(s.dir, "films/Inception (2010) [1080p].mkv"),
    heat: id(s.dir, "films/Heat (1995)/movie.mkv"),
    bullets: id(s.dir, "films/让子弹飞 (2010)/Let.the.Bullets.Fly.2010.mp4"),
    e1: id(s.dir, "shows/Breaking Bad/Season 1/Breaking.Bad.S01E01.720p.mkv"),
    e2: id(s.dir, "shows/Breaking Bad/Season 1/Breaking.Bad.S01E02.720p.mkv"),
    e3: id(s.dir, "shows/Breaking Bad/Season 2/Breaking.Bad.S02E01.720p.mkv"),
  };
  const lib = (await s.call("GET", "/videos/library", MEMBER)).json;
  assert.equal(lib.ffmpeg, false);
  assert.deepEqual(lib.recent, []);
  const movies = Object.fromEntries(lib.movies.map((m: any) => [m.id, m]));
  assert.equal(lib.movies.length, 4, JSON.stringify(lib.movies.map((m: any) => m.title)));
  assert.deepEqual([movies[ids.matrix].title, movies[ids.matrix].year, movies[ids.matrix].poster, movies[ids.matrix].hasPoster], ["The Matrix", 1999, null, false]);
  assert.deepEqual([movies[ids.inception].title, movies[ids.inception].year, movies[ids.inception].poster], ["Inception", 2010, b64("th:Inception (2010) [1080p]-poster.jpg")]);
  assert.deepEqual([movies[ids.heat].title, movies[ids.heat].year, movies[ids.heat].poster], ["Heat", 1995, b64("th:poster.jpg")]);
  // The station's poster of an MP4, kept without a ThumbHash (no sips, no ffmpeg here).
  assert.deepEqual([movies[ids.bullets].title, movies[ids.bullets].year, movies[ids.bullets].poster, movies[ids.bullets].hasPoster], ["让子弹飞", 2010, null, true]);
  const shows = Object.fromEntries(lib.shows.map((x: any) => [x.title, x]));
  assert.deepEqual(Object.keys(shows).sort(), ["The Office US", "狂飙", "绝命毒师"].sort());
  assert.deepEqual([shows["绝命毒师"].year, shows["绝命毒师"].seasons, shows["绝命毒师"].episodes, shows["绝命毒师"].unwatched, shows["绝命毒师"].poster], [2008, 2, 3, 3, b64("th:poster.jpg")]);
  assert.deepEqual([shows["狂飙"].seasons, shows["狂飙"].episodes, shows["狂飙"].hasPoster], [1, 2, true]);

  const heat = (await s.call("GET", `/videos/titles/${ids.heat}`, MEMBER)).json;
  assert.deepEqual(heat, {
    id: ids.heat,
    kind: "movie",
    title: "Heat",
    originalTitle: "盗火线",
    year: 1995,
    plot: "A heist.",
    genres: ["Crime", "Thriller"],
    duration: 10200,
    file: { root: s.dir, path: "films/Heat (1995)/movie.mkv" },
    size: 4,
    poster: b64("th:poster.jpg"),
    hasPoster: true,
    probe: "no-ffprobe",
    tracks: { container: null, video: null, audio: [], subtitles: [] },
    progress: null,
  });
  const show = (await s.call("GET", `/videos/titles/${shows["绝命毒师"].id}`, MEMBER)).json;
  assert.equal(show.kind, "show");
  assert.equal(show.plot, "化学老师。");
  assert.deepEqual(
    show.seasons.map((x: any) => [x.season, x.episodes.map((e: any) => [e.id, e.episode, e.title])]),
    [
      [1, [[ids.e1, 1, "Pilot"], [ids.e2, 2, null]]],
      [2, [[ids.e3, 1, null]]],
    ],
  );
  const ep = (await s.call("GET", `/videos/episodes/${ids.e1}`, MEMBER)).json;
  assert.deepEqual([ep.kind, ep.show, ep.showTitle, ep.season, ep.episode, ep.title], ["episode", shows["绝命毒师"].id, "绝命毒师", 1, 1, "Pilot"]);
  assert.equal((await s.call("GET", `/videos/episodes/${ids.heat}`, MEMBER)).status, 404);
  assert.equal((await s.call("GET", "/videos/titles/nope", MEMBER)).status, 404);

  // Posters: the picture beside it as the station's /thumb made it, the station's poster of an MP4.
  const poster = await s.call("GET", `/videos/posters/${ids.heat}`, MEMBER);
  assert.equal(poster.status, 200);
  assert.equal(poster.headers["content-type"], "image/jpeg");
  assert.equal(poster.headers["stillfail-thumbhash"], b64("th:poster.jpg"));
  assert.deepEqual(poster.bytes, jpeg(500, 750));
  assert.equal((await s.call("GET", `/videos/posters/${ids.bullets}`, MEMBER)).status, 200);
  assert.equal((await s.call("GET", `/videos/posters/${ids.matrix}`, MEMBER)).status, 404);

  // Played directly (no ffmpeg); the subtitle beside it made WebVTT here.
  const play = (await s.call("GET", `/videos/${ids.matrix}/play?client=h264,aac`, MEMBER)).json;
  assert.deepEqual(play, { direct: true, file: { root: s.dir, path: "films/The.Matrix.1999.1080p.BluRay.x264-YTS.mkv" }, subtitles: [{ id: "x0", lang: "zh", title: "中文", url: `/videos/${ids.matrix}/subtitles/x0.vtt` }], audio: [], duration: null });
  const vtt = await s.call("GET", `/videos/${ids.matrix}/subtitles/x0.vtt`, MEMBER);
  assert.equal(vtt.headers["content-type"], "text/vtt; charset=utf-8");
  assert.equal(vtt.bytes.toString("utf8"), "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n<i>你好</i>\n");
  assert.equal((await s.call("GET", `/videos/${ids.matrix}/subtitles/x1.vtt`, MEMBER)).status, 404);
  assert.equal((await s.call("GET", `/videos/${ids.matrix}/hls/master.m3u8`, MEMBER)).status, 415, "no HLS without ffmpeg");

  // A file added is found by the station's watch; one removed is gone.
  write(join(s.dir, "films", "Alien.1979.mkv"), "alien");
  await until(async () => (await s.call("GET", "/videos/library", MEMBER)).json.movies.some((m: any) => m.title === "Alien" && m.year === 1979), "the new film");
  execFileSync("rm", [join(s.dir, "shows", "The.Office.US.S01E01.mkv")]);
  await until(async () => !(await s.call("GET", "/videos/library", MEMBER)).json.shows.some((x: any) => x.title === "The Office US"), "the show gone with its episode");
});

test("progress: each account's own, the latest `at` wins, seen at 90%; 继续观看; told to that account only", async (t) => {
  const s = await started(1 << 20);
  t.after(s.stop);
  library(s.dir);
  await s.call("PUT", "/videos/folders", OWNER, { folders: [{ root: s.dir, path: "films", kind: "movies" }, { root: s.dir, path: "shows", kind: "shows" }] });
  await s.service.videos.settled();
  const heat = id(s.dir, "films/Heat (1995)/movie.mkv");
  const matrix = id(s.dir, "films/The.Matrix.1999.1080p.BluRay.x264-YTS.mkv");
  const e1 = id(s.dir, "shows/Breaking Bad/Season 1/Breaking.Bad.S01E01.720p.mkv");
  const e2 = id(s.dir, "shows/Breaking Bad/Season 1/Breaking.Bad.S01E02.720p.mkv");
  const member = listen(s.socket, MEMBER);
  const owner = listen(s.socket, OWNER);
  await Promise.all([member.ready, owner.ready]);
  t.after(() => {
    member.close();
    owner.close();
  });

  assert.deepEqual((await s.call("GET", `/videos/${heat}/progress`, MEMBER)).json, { progress: null });
  const put = (who: typeof MEMBER, item: string, body: unknown) => s.call("PUT", `/videos/${item}/progress`, who, body);
  assert.deepEqual((await put(MEMBER, heat, { position: 600, at: 1000 })).json, { progress: { position: 600, duration: 10200, done: false, at: 1000 } });
  assert.deepEqual((await put(MEMBER, heat, { position: 50, at: 900 })).json, { progress: { position: 600, duration: 10200, done: false, at: 1000 } }, "an older place does not win");
  assert.equal((await put(MEMBER, heat, { position: -1, at: 2000 })).status, 400);
  assert.equal((await put(MEMBER, heat, { position: 1, at: 2000, done: "yes" })).status, 400);
  assert.equal((await put(MEMBER, "nope", { position: 1, at: 2000 })).status, 404);
  await until(() => member.events.filter((e) => e.event === "progress").length === 1, "the member told once");
  assert.deepEqual(member.events.find((e) => e.event === "progress")!.data, { id: heat });
  assert.deepEqual((await s.call("GET", `/videos/${heat}/progress`, OWNER)).json, { progress: null }, "the owner's own");

  await put(MEMBER, matrix, { position: 30, at: 3000 });
  await put(MEMBER, e1, { position: 100, at: 4000, duration: 2800 });
  let lib = (await s.call("GET", "/videos/library", MEMBER)).json;
  assert.deepEqual(
    lib.recent.map((r: any) => [r.id, r.kind, r.position]),
    [
      [e1, "episode", 100],
      [matrix, "movie", 30],
      [heat, "movie", 600],
    ],
  );
  assert.equal(lib.recent[0].showTitle, "绝命毒师");
  assert.equal(lib.recent[0].duration, 2800);
  assert.deepEqual(lib.movies.find((m: any) => m.id === heat).progress, { position: 600, duration: 10200, done: false, at: 1000 });

  // Seen: at 90% of its length, or when the player says so; then not in 继续观看, and the show's unwatched fewer.
  assert.equal((await put(MEMBER, heat, { position: 9200, at: 5000 })).json.progress.done, true);
  assert.equal((await put(MEMBER, e2, { position: 10, at: 6000, done: true })).json.progress.done, true);
  lib = (await s.call("GET", "/videos/library", MEMBER)).json;
  assert.deepEqual(lib.recent.map((r: any) => r.id), [e1, matrix]);
  assert.equal(lib.shows.find((x: any) => x.title === "绝命毒师").unwatched, 2);
  assert.equal((await s.call("GET", "/videos/library", OWNER)).json.recent.length, 0);
  const show = (await s.call("GET", `/videos/titles/${lib.shows.find((x: any) => x.title === "绝命毒师").id}`, MEMBER)).json;
  assert.deepEqual(show.seasons[0].episodes.map((e: any) => e.progress?.done ?? null), [false, true]);
  await wait(300);
  assert.equal(owner.events.filter((e) => e.event === "progress").length, 0, "the owner is not told of the member's progress");
});

test("videos are the home workspace's writers': viewers and other workspaces refused", async (t) => {
  const s = await started();
  t.after(s.stop);
  for (const [method, path] of [["GET", "/videos/library"], ["GET", "/videos/folders"], ["PUT", "/videos/folders"], ["GET", "/videos/x/play"], ["GET", "/videos/x/progress"], ["PUT", "/videos/x/progress"], ["GET", "/videos/posters/x"]] as const) {
    const r = await s.call(method, path, VIEWER, method === "PUT" ? {} : undefined);
    assert.equal(r.status, 403, `viewer ${method} ${path}`);
  }
  const away = ascii({ sub: "u-away", email: "away@example.com", name: "外", role: "owner", workspace: "w9", home: false });
  for (const path of ["/videos/library", "/videos/folders"]) {
    const status = await new Promise<number>((resolve, reject) => {
      request({ socketPath: s.socket, path, headers: { "stillfail-viewer": away } }, (res) => {
        res.resume();
        resolve(res.statusCode!);
      })
        .on("error", reject)
        .end();
    });
    assert.equal(status, 403, `another workspace's owner: ${path}`);
  }
});

// With ffmpeg.

/// The service's ffmpeg and ffprobe (MEDIA_FFMPEG, MEDIA_FFPROBE: the package's, say), and the one on PATH that makes
/// the fixtures (it needs lavfi).
const tools = findTools();
const dev = findTools({ PATH: process.env.PATH });
const noFfmpeg = !tools.ffmpeg || !tools.ffprobe || !dev.ffmpeg ? "no ffmpeg/ffprobe on PATH" : false;
/// ThumbHashes by sips on macOS (the package's ffmpeg reads no JPEG), by the developer's ffmpeg elsewhere.
const sips = existsSync("/usr/bin/sips") ? "/usr/bin/sips" : null;

/// Each track's first tfdt in a segment, in seconds, by its handler ("vide", "soun"), and how long its samples last.
function timeline(init: Buffer, segment: Buffer) {
  type B = { type: string; body: number; end: number };
  const boxes = (b: Buffer, start: number, end: number): B[] => {
    const out: B[] = [];
    for (let i = start; i + 8 <= end; ) {
      const size = b.readUInt32BE(i);
      out.push({ type: b.toString("latin1", i + 4, i + 8), body: i + 8, end: i + size });
      i += size;
    }
    return out;
  };
  const kid = (b: Buffer, x: B, type: string) => boxes(b, x.body, x.end).find((y) => y.type === type)!;
  const moov = boxes(init, 0, init.length).find((x) => x.type === "moov")!;
  const tracks = new Map<number, { ts: number; kind: string }>();
  for (const trak of boxes(init, moov.body, moov.end).filter((x) => x.type === "trak")) {
    const tkhd = kid(init, trak, "tkhd");
    const mdia = kid(init, trak, "mdia");
    const mdhd = kid(init, mdia, "mdhd");
    const hdlr = kid(init, mdia, "hdlr");
    tracks.set(init.readUInt32BE(tkhd.body + (init[tkhd.body] === 1 ? 20 : 12)), { ts: init.readUInt32BE(mdhd.body + (init[mdhd.body] === 1 ? 20 : 12)), kind: init.toString("latin1", hdlr.body + 8, hdlr.body + 12) });
  }
  const defaults = new Map<number, number>();
  const mvex = boxes(init, moov.body, moov.end).find((x) => x.type === "mvex");
  for (const trex of mvex ? boxes(init, mvex.body, mvex.end).filter((x) => x.type === "trex") : []) defaults.set(init.readUInt32BE(trex.body + 4), init.readUInt32BE(trex.body + 12));
  const at: Record<string, number> = {};
  const lasts: Record<string, number> = {};
  for (const moof of boxes(segment, 0, segment.length).filter((x) => x.type === "moof")) {
    for (const traf of boxes(segment, moof.body, moof.end).filter((x) => x.type === "traf")) {
      const tfhd = kid(segment, traf, "tfhd");
      const tfdt = kid(segment, traf, "tfdt");
      const track = segment.readUInt32BE(tfhd.body + 4);
      const t = tracks.get(track)!;
      const flags = segment.readUIntBE(tfhd.body + 1, 3);
      const fixed = flags & 0x8 ? segment.readUInt32BE(tfhd.body + 8 + (flags & 0x1 ? 8 : 0) + (flags & 0x2 ? 4 : 0)) : (defaults.get(track) ?? 0);
      let time = Number(segment[tfdt.body] === 1 ? segment.readBigUInt64BE(tfdt.body + 4) : BigInt(segment.readUInt32BE(tfdt.body + 4)));
      at[t.kind] ??= time / t.ts;
      for (const trun of boxes(segment, traf.body, traf.end).filter((x) => x.type === "trun")) {
        const f = segment.readUIntBE(trun.body + 1, 3);
        let p = trun.body + 8 + (f & 0x1 ? 4 : 0) + (f & 0x4 ? 4 : 0);
        for (let k = segment.readUInt32BE(trun.body + 4); k > 0; k--) {
          time += f & 0x100 ? segment.readUInt32BE(p) : fixed;
          p += (f & 0x100 ? 4 : 0) + (f & 0x200 ? 4 : 0) + (f & 0x400 ? 4 : 0) + (f & 0x800 ? 4 : 0);
        }
      }
      lasts[t.kind] = time / t.ts;
    }
  }
  return { at, lengths: Object.fromEntries(Object.entries(lasts).map(([k, end]) => [k, end - at[k]!])) };
}

/// Tiny films made by the developer's ffmpeg: an MP4 (H.264, AC-3) and an MKV (H.264, AAC, an embedded Chinese SRT),
/// 8 s at 25 fps with a keyframe every second; an SRT beside the MKV.
function fixtures(dir: string) {
  const films = join(dir, "films");
  mkdirSync(films, { recursive: true });
  const ff = (...args: string[]) => execFileSync(dev.ffmpeg!, ["-hide_banner", "-loglevel", "error", "-y", ...args]);
  const encoders = execFileSync(dev.ffmpeg!, ["-hide_banner", "-encoders"]).toString();
  const h264 = /\slibx264\s/.test(encoders) ? ["-c:v", "libx264", "-g", "25", "-pix_fmt", "yuv420p"] : ["-c:v", "h264_videotoolbox", "-g", "25"];
  const src = ["-f", "lavfi", "-i", "testsrc=duration=8:size=320x240:rate=25", "-f", "lavfi", "-i", "sine=duration=8:frequency=440"];
  ff(...src, ...h264, "-c:a", "ac3", join(films, "Sintel.2010.mp4"));
  write(join(dir, "embedded.srt"), "1\n00:00:01,000 --> 00:00:03,000\n片中字幕\n");
  ff(...src, "-i", join(dir, "embedded.srt"), "-map", "0:v", "-map", "1:a", "-map", "2:s", ...h264, "-c:a", "aac", "-c:s", "srt", "-metadata:s:s:0", "language=chi", join(films, "Big.Buck.Bunny.2008.mkv"));
  write(join(films, "Big.Buck.Bunny.2008.en.srt"), "1\n00:00:00,500 --> 00:00:01,500\nHello\n");
}

test("with ffmpeg: probed, a poster frame, play decisions, HLS remuxed and made H.264, embedded subtitles", { skip: noFfmpeg }, async (t) => {
  const s = await started(1 << 20, sips, tools);
  t.after(s.stop);
  fixtures(s.dir);
  await s.call("PUT", "/videos/folders", OWNER, { folders: [{ root: s.dir, path: "films", kind: "movies" }] });
  await s.service.videos.settled();
  const mp4 = id(s.dir, "films/Sintel.2010.mp4");
  const mkv = id(s.dir, "films/Big.Buck.Bunny.2008.mkv");

  const lib = (await s.call("GET", "/videos/library", MEMBER)).json;
  assert.equal(lib.ffmpeg, true);
  const sintel = lib.movies.find((m: any) => m.id === mp4);
  assert.equal(sintel.title, "Sintel");
  assert.equal(typeof sintel.poster, "string", "a frame's ThumbHash");
  const poster = await s.call("GET", `/videos/posters/${mp4}`, MEMBER);
  assert.equal(poster.headers["content-type"], "image/jpeg");
  assert.equal(poster.headers["stillfail-width"], "320");
  assert.deepEqual([...poster.bytes.subarray(0, 2)], [0xff, 0xd8]);

  const title = (await s.call("GET", `/videos/titles/${mkv}`, MEMBER)).json;
  assert.equal(title.probe, "done");
  assert.ok(Math.abs(title.duration - 8) < 0.2, String(title.duration));
  assert.deepEqual(title.tracks.video, { codec: "h264", profile: title.tracks.video.profile, width: 320, height: 240, hdr: null, fps: 25, bitDepth: 8 });
  assert.deepEqual(title.tracks.audio.map((a: any) => [a.index, a.codec]), [[1, "aac"]]);
  assert.deepEqual(title.tracks.subtitles.map((x: any) => [x.id, x.lang, x.text]), [["x0", "en", true], ["s2", "chi", true]]);

  // Direct when the client decodes it all; else HLS: remuxed when it decodes the video, else made H.264.
  const play = async (item: string, client: string) => (await s.call("GET", `/videos/${item}/play?client=${client}`, MEMBER)).json;
  assert.equal((await play(mp4, "h264,ac3")).direct, true);
  assert.equal((await play(mp4, "h264,aac")).direct, false, "its audio is AC-3");
  const hevcOnly = await play(mp4, "hevc,aac");
  assert.deepEqual([hevcOnly.direct, hevcOnly.hls], [false, `/videos/${mp4}/hls/master.m3u8?video=h264`]);
  const remux = await play(mkv, "h264,aac");
  assert.deepEqual([remux.direct, remux.hls], [false, `/videos/${mkv}/hls/master.m3u8?video=copy`]);
  assert.deepEqual(remux.audio.map((a: any) => [a.index, a.codec, a.channels]), [[1, "aac", 1]]);
  assert.deepEqual(remux.subtitles.map((x: any) => x.url), [`/videos/${mkv}/subtitles/x0.vtt`, `/videos/${mkv}/subtitles/s2.vtt`]);
  assert.equal((await play(mkv, "h264,aac,mkv")).direct, true);

  const embedded = await s.call("GET", `/videos/${mkv}/subtitles/s2.vtt`, MEMBER);
  assert.equal(embedded.status, 200);
  assert.match(embedded.bytes.toString("utf8"), /^WEBVTT[\s\S]*00:0?0?:?01\.000 --> 00:0?0?:?03\.000\n片中字幕/);

  // The MKV's AAC kept as it is (a seek in it lands at its cluster's start, before the keyframe), the MP4's AC-3 made AAC.
  for (const [item, mode] of [[mkv, "copy"], [mkv, "h264"], [mp4, "h264"]] as const) {
    const master = await s.call("GET", `/videos/${item}/hls/master.m3u8?video=${mode}`, MEMBER);
    assert.equal(master.status, 200, master.bytes.toString());
    assert.equal(master.headers["content-type"], "application/vnd.apple.mpegurl");
    const variant = master.bytes.toString().trim().split("\n").at(-1)!;
    assert.equal(variant, `${mode}-a1/index.m3u8`);
    const media = (await s.call("GET", `/videos/${item}/hls/${variant}`, MEMBER)).bytes.toString();
    assert.match(media, /#EXT-X-PLAYLIST-TYPE:VOD/);
    assert.match(media, /#EXT-X-MAP:URI="init.mp4"/);
    const listed = [...media.matchAll(/#EXTINF:([\d.]+),\n(\d+)\.m4s/g)].map((m) => Number(m[1]));
    assert.equal(listed.length, 2, media);
    assert.ok(Math.abs(listed[0]! - 6) < 0.05 && Math.abs(listed[1]! - 2) < 0.1, media);
    const base = `/videos/${item}/hls/${mode}-a1`;
    const second = await s.call("GET", `${base}/1.m4s`, MEMBER);
    assert.equal(second.status, 200, second.bytes.toString());
    assert.equal(second.headers["content-type"], "video/iso.segment");
    const first = await s.call("GET", `${base}/0.m4s`, MEMBER);
    const init = await s.call("GET", `${base}/init.mp4`, MEMBER);
    assert.equal(init.bytes.toString("latin1", 4, 8), "ftyp");
    // Each segment on the timeline where the playlist puts it, as long as it says: the video at its start, the audio
    // within a few frames (B-frames show the first picture 2 frames after its tfdt).
    for (const [n, seg] of [[0, first.bytes], [1, second.bytes]] as const) {
      const { at, lengths } = timeline(init.bytes, seg);
      const what = `${item === mkv ? "mkv" : "mp4"} ${mode} segment ${n}: ${JSON.stringify({ at, lengths })}`;
      assert.ok(Math.abs(at.vide! - n * 6) < 0.001, what);
      assert.ok(Math.abs(at.soun! - n * 6) <= 0.1, what);
      assert.ok(Math.abs(lengths.vide! - listed[n]!) <= 0.15 && Math.abs(lengths.soun! - listed[n]!) <= 0.15, what);
    }
    assert.equal((await s.call("GET", `${base}/2.m4s`, MEMBER)).status, 404);
    assert.equal((await s.call("GET", `/videos/${item}/hls/copy-a7/index.m3u8`, MEMBER)).status, 404);
  }
  // The pieces the player is sent decode as one film: the remuxed one frame for frame as the file, the one made
  // H.264 with all its frames.
  const md5s = (file: string) =>
    execFileSync(dev.ffmpeg!, ["-v", "error", "-i", file, "-map", "0:v", "-f", "framemd5", "-"])
      .toString()
      .split("\n")
      .filter((l) => l && !l.startsWith("#"))
      .map((l) => l.split(",").at(-1)!.trim());
  const remuxed = join(s.dir, "remuxed.mp4");
  const copyBase = `/videos/${mkv}/hls/copy-a1`;
  writeFileSync(remuxed, Buffer.concat([(await s.call("GET", `${copyBase}/init.mp4`, MEMBER)).bytes, (await s.call("GET", `${copyBase}/0.m4s`, MEMBER)).bytes, (await s.call("GET", `${copyBase}/1.m4s`, MEMBER)).bytes]));
  assert.deepEqual(md5s(remuxed), md5s(join(s.dir, "films", "Big.Buck.Bunny.2008.mkv")));
  const whole = join(s.dir, "whole.mp4");
  const base = `/videos/${mp4}/hls/h264-a1`;
  writeFileSync(whole, Buffer.concat([(await s.call("GET", `${base}/init.mp4`, MEMBER)).bytes, (await s.call("GET", `${base}/0.m4s`, MEMBER)).bytes, (await s.call("GET", `${base}/1.m4s`, MEMBER)).bytes]));
  const frames = execFileSync(tools.ffprobe!, ["-v", "error", "-count_frames", "-select_streams", "v:0", "-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", whole]).toString().trim();
  assert.equal(Number(frames), 200);
});

test("with ffmpeg: the HLS cache keeps under its cap, the least lately used segment removed first", { skip: noFfmpeg }, async (t) => {
  const s = await started(1 << 20, sips, tools);
  t.after(s.stop);
  fixtures(s.dir);
  const file = join(s.dir, "films", "Sintel.2010.mp4");
  const { probe } = await import("../src/ffmpeg.ts");
  const p = await probe(tools.ffprobe!, file);
  const streamer = new Streamer({ dir: join(s.dir, "cache"), tools, cap: 1 });
  t.after(() => streamer.close());
  const src = { id: "x", file, probe: p, key: "x-1-1" };
  const zero = await streamer.segment(src, "h264-a1", 0);
  assert.ok(existsSync(zero));
  const one = await streamer.segment(src, "h264-a1", 1);
  assert.ok(existsSync(one));
  assert.ok(!existsSync(zero), "the older segment removed above the cap");
  assert.equal(await streamer.size(), readFileSync(one).length);
});
