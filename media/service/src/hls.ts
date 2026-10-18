// Playing a video (docs/media-service.md 影视): directly (the client reads the file through the drive) when it decodes
// the file's container and codecs, else HLS made here on demand: 6-second fragmented-MP4 segments, each made by its
// own ffmpeg run when asked (the next few after it too), the video remuxed when the client decodes its codec (the
// segments then begin at its keyframes), else made H.264 by the encoder there is (VideoToolbox, openh264; x264 in a
// developer's ffmpeg); the audio AAC stereo (AAC of one or two channels kept as it is). Each run's tracks start at 0:
// their tfdt is moved to where the segment is (placeFragments), and the init segment (the same in every run) is kept
// from the first. Kept under the module's folder by file (id, time, size), the least lately used removed above the
// cap (MEDIA_HLS_CAP bytes, 20 GB). At most two runs at once, one per video. Only what the package's LGPL ffmpeg has
// is used: the mp4 muxer, the aac encoder, the scale and format filters.
import { randomBytes } from "node:crypto";
import { mkdir, readFile, readdir, rename, rm, stat, utimes, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { MediaError, bad } from "./errors.ts";
import { type AudioTrack, type Probe, type Tools, findEncoders, type Keyframes, keyframes as probeKeyframes, runFfmpeg } from "./ffmpeg.ts";

export const SEGMENT = 6;
/// Segments made after the one asked for, before the player asks.
export const AHEAD = 3;
/// Runs at once, in all.
const RUNS = 2;
export const DEFAULT_CAP = 20 * 1024 * 1024 * 1024;

/// Video codecs fragmented MP4 carries as they are.
const COPYABLE = new Set(["h264", "hevc", "av1", "vp9"]);
const CONTAINERS = ["mp4", "mkv", "webm", "ts", "avi"];
const ALIASES: Record<string, string> = { avc: "h264", avc1: "h264", h265: "hevc", hvc1: "hevc", hev1: "hevc", "ec-3": "eac3", ec3: "eac3", "ac-3": "ac3", mov: "mp4", m4v: "mp4", matroska: "mkv", m2ts: "ts", mpegts: "ts", vp09: "vp9", av01: "av1", "mp4a": "aac" };

/// What a client says it decodes (`h264,hevc,aac,ac3`, containers among them or not), as a set of names ffprobe uses;
/// H.264 and AAC in MP4 when it says nothing.
export function clientOf(q: string | null): Set<string> {
  return new Set(
    (q === null || q.trim() === "" ? "h264,aac" : q)
      .toLowerCase()
      .split(/[,\s]+/)
      .filter((x) => x !== "")
      .map((x) => ALIASES[x] ?? x),
  );
}

export const containerOf = (path: string) => {
  const ext = path.slice(path.lastIndexOf(".") + 1).toLowerCase();
  return ext === "mov" || ext === "m4v" || ext === "mp4" ? "mp4" : ext === "m2ts" ? "ts" : ext;
};

/// The audio played when none is asked for: the default track, else the first.
export const defaultAudio = (p: Probe): AudioTrack | null => p.audio.find((a) => a.default) ?? p.audio[0] ?? null;

export type Mode = "copy" | "h264";

/// Whether the client plays the file as it is (its container, among the ones it lists, mp4 when it lists none; its
/// video codec; its default audio's), and how HLS would make its video: as it is when the client decodes it.
export function decide(path: string, p: Probe | null, client: Set<string>): { direct: boolean; mode: Mode } {
  if (!p || !p.video) return { direct: true, mode: "h264" };
  const listed = CONTAINERS.filter((c) => client.has(c));
  const containers = listed.length > 0 ? listed : ["mp4"];
  const video = client.has(p.video.codec);
  const audio = defaultAudio(p);
  const direct = containers.includes(containerOf(path)) && video && (!audio || client.has(audio.codec));
  return { direct, mode: video && COPYABLE.has(p.video.codec) ? "copy" : "h264" };
}

/// A video as HLS is made of it: its id, the file ffmpeg reads, what ffprobe said, and its key (id, time, size).
export type Source = { id: string; file: string; probe: Probe; key: string };
type Variant = { mode: Mode; audio: number | null; name: string };
/// Where segments begin (`starts`); a remux's also: how many video packets each has, when its first keyframe is decoded.
type Plan = { starts: number[]; end: number; frames: number[] | null; decodes: number[] | null };
type Job = { key: string; title: string; n: number; wanted: boolean; run: () => Promise<void>; done: Promise<void>; resolve: () => void; reject: (e: unknown) => void };

const VARIANT = /^(copy|h264)-a(\d+|n)$/;

/// The H.264 bitrate for a picture this high (made at most 1080 high).
const bitrateOf = (height: number) => (height <= 480 ? 1_500_000 : height <= 720 ? 4_000_000 : 8_000_000);

export class Streamer {
  readonly #dir: string;
  readonly #tools: Tools;
  readonly #cap: number;
  #encoders: Promise<string[]> | null = null;
  /// The encoders that failed here (the next one is used).
  #failed = new Set<string>();
  /// The encoders that made a segment here (one failing then is the file's fault, not the encoder's).
  #proven = new Set<string>();
  #plans = new Map<string, Promise<Plan | null>>();
  #queue: Job[] = [];
  #jobs = new Map<string, Job>();
  #running = new Set<string>();
  #runs = 0;
  /// The cache's files: size and when last used (the files' mtimes, as found at first).
  #cache: Map<string, { size: number; used: number }> | null = null;
  #total = 0;
  #closed = false;
  #aborts = new Set<AbortController>();

  constructor(o: { dir: string; tools: Tools; cap?: number }) {
    this.#dir = join(o.dir, "hls");
    this.#tools = o.tools;
    this.#cap = o.cap ?? DEFAULT_CAP;
  }

  close() {
    this.#closed = true;
    for (const a of this.#aborts) a.abort();
    for (const j of this.#queue) j.reject(new MediaError("internal", "媒体服务正在停止"));
    this.#queue = [];
  }

  /// The encoder H.264 is made with: the first this ffmpeg has (found once) that has not failed here; null when none.
  async encoder(): Promise<string | null> {
    if (!this.#tools.ffmpeg) return null;
    const all = await (this.#encoders ??= findEncoders(this.#tools.ffmpeg));
    return all.find((e) => !this.#failed.has(e)) ?? null;
  }

  /// Whether HLS can be made of the video in `mode` (ffmpeg there, an encoder when its video is made H.264).
  async can(p: Probe | null, mode: Mode): Promise<boolean> {
    if (!this.#tools.ffmpeg || !p?.video || !p.duration) return false;
    return mode === "copy" || (await this.encoder()) !== null;
  }

  #variant(src: Source, name: string): Variant {
    const m = VARIANT.exec(name);
    if (!m) throw new MediaError("not_found", "没有这个 HLS 列表");
    const audio = m[2] === "n" ? null : Number(m[2]);
    if (audio !== null && !src.probe.audio.some((a) => a.index === audio)) throw new MediaError("not_found", "没有这条音轨");
    const mode = m[1] as Mode;
    if (mode === "copy" && !COPYABLE.has(src.probe.video?.codec ?? "")) throw new MediaError("not_found", "这个视频的编码不能原样放进 HLS");
    return { mode, audio, name };
  }

  // Playlists.

  /// The master playlist: one stream, its video as `mode` says (or as `client` decodes), the audio track `audio`.
  async master(src: Source, q: URLSearchParams): Promise<string> {
    const p = src.probe;
    if (!p.video || !p.duration) throw new MediaError("unsupported", "这个视频没有能播放的画面");
    let mode: Mode;
    const given = q.get("video");
    if (given === "copy" || given === "h264") mode = given;
    else if (given === null || given === "") mode = decide(src.file, p, clientOf(q.get("client"))).mode;
    else throw bad("video 只能是 copy 或 h264");
    if (mode === "copy" && !COPYABLE.has(p.video.codec)) mode = "h264";
    // Remuxed only when its keyframes are known in time; else made H.264.
    if (mode === "copy" && !(await this.#plan(src, mode))) mode = "h264";
    if (mode === "h264" && !(await this.encoder())) throw new MediaError("unsupported", "这台 station 的 ffmpeg 没有 H.264 编码器，只能直接播放");
    const a = q.get("audio");
    let audio: AudioTrack | null;
    if (a === null || a === "") audio = defaultAudio(p);
    else {
      audio = p.audio.find((t) => String(t.index) === a) ?? null;
      if (!audio) throw new MediaError("not_found", "没有这条音轨");
    }
    const height = mode === "copy" ? p.video.height : Math.min(1080, p.video.height || 1080);
    const width = mode === "copy" ? p.video.width : p.video.height ? Math.round((p.video.width * height) / p.video.height / 2) * 2 : 1920;
    const bandwidth = (mode === "copy" ? (p.bitrate ?? 8_000_000) : bitrateOf(height)) + (audio ? 192_000 : 0);
    const name = `${mode}-a${audio ? audio.index : "n"}`;
    return ["#EXTM3U", "#EXT-X-VERSION:7", "#EXT-X-INDEPENDENT-SEGMENTS", `#EXT-X-STREAM-INF:BANDWIDTH=${Math.round(bandwidth)}${width && height ? `,RESOLUTION=${width}x${height}` : ""}`, `${name}/index.m3u8`, ""].join("\n");
  }

  /// A variant's media playlist: its segments, all of them (VOD).
  async media(src: Source, name: string): Promise<string> {
    const v = this.#variant(src, name);
    const plan = await this.#plan(src, v.mode);
    if (!plan) throw new MediaError("conflict", "这个视频的关键帧没读出来，请改用转码播放");
    const lengths = plan.starts.map((s, i) => (plan.starts[i + 1] ?? plan.end) - s);
    const lines = ["#EXTM3U", "#EXT-X-VERSION:7", `#EXT-X-TARGETDURATION:${Math.max(1, Math.ceil(Math.max(...lengths)))}`, "#EXT-X-PLAYLIST-TYPE:VOD", "#EXT-X-MEDIA-SEQUENCE:0", "#EXT-X-INDEPENDENT-SEGMENTS", '#EXT-X-MAP:URI="init.mp4"'];
    lengths.forEach((d, i) => lines.push(`#EXTINF:${d.toFixed(3)},`, `${i}.m4s`));
    lines.push("#EXT-X-ENDLIST", "");
    return lines.join("\n");
  }

  /// Where segments begin: every 6 s when the video is made here; at the first keyframe 6 s or more after the last
  /// start when it is remuxed (with how many video packets each has). Null when the keyframes could not be read.
  #plan(src: Source, mode: Mode): Promise<Plan | null> {
    const duration = src.probe.duration!;
    if (mode === "h264") {
      const starts: number[] = [];
      for (let t = 0; t < duration - 0.05 || starts.length === 0; t += SEGMENT) starts.push(t);
      return Promise.resolve({ starts, end: duration, frames: null, decodes: null });
    }
    const key = src.key;
    let plan = this.#plans.get(key);
    if (!plan) {
      plan = this.#keyframes(src).then((k) => {
        if (!k || k.times.length === 0) return null;
        const starts: number[] = [];
        const frames: number[] = [];
        const decodes: number[] = [];
        let at = -1;
        for (let i = 0; i < k.times.length; i++) {
          const t = k.times[i]!;
          if (starts.length === 0 || t >= starts[starts.length - 1]! + SEGMENT - 0.05) {
            if (t >= duration - 0.05 && starts.length > 0) break;
            if (at >= 0) frames.push(k.packets[i]! - k.packets[at]!);
            starts.push(starts.length === 0 ? 0 : t);
            decodes.push(k.decodes[i]!);
            at = i;
          }
        }
        frames.push(k.total - k.packets[at]!);
        return { starts, end: duration, frames, decodes };
      });
      this.#plans.set(key, plan);
      if (this.#plans.size > 64) this.#plans.delete(this.#plans.keys().next().value!);
    }
    return plan;
  }

  /// The video's keyframes (times from its start, and their packet's number in decode order), kept beside its segments.
  async #keyframes(src: Source): Promise<Keyframes | null> {
    const file = join(this.#dir, src.key, "keyframes.json");
    const kept = await readFile(file, "utf8").catch(() => null);
    if (kept) return JSON.parse(kept) as Keyframes;
    if (!this.#tools.ffprobe) return null;
    const k = await probeKeyframes(this.#tools.ffprobe, src.file, src.probe.start);
    if (!k) return null;
    await mkdir(join(this.#dir, src.key), { recursive: true });
    await writeFile(file, JSON.stringify(k));
    return k;
  }

  // Segments.

  #paths(src: Source, v: Variant) {
    const dir = join(this.#dir, src.key, v.name);
    return { dir, init: join(dir, "init.mp4"), segment: (n: number) => join(dir, `${n}.m4s`) };
  }

  /// The init segment (made with the first segment when there is none yet).
  async init(src: Source, name: string): Promise<string> {
    const v = this.#variant(src, name);
    const at = this.#paths(src, v);
    if (await exists(at.init)) return at.init;
    await this.segment(src, name, 0);
    return at.init;
  }

  /// Segment `n`'s file: kept, or made now (the player's asking first), the next few after it made too.
  async segment(src: Source, name: string, n: number): Promise<string> {
    const v = this.#variant(src, name);
    const plan = await this.#plan(src, v.mode);
    if (!plan) throw new MediaError("conflict", "这个视频的关键帧没读出来，请改用转码播放");
    if (!Number.isInteger(n) || n < 0 || n >= plan.starts.length) throw new MediaError("not_found", "没有这一段");
    const at = this.#paths(src, v);
    // What was queued ahead of where the player was is not wanted now it is elsewhere.
    this.#queue = this.#queue.filter((j) => {
      if (j.title !== src.id || j.wanted || (j.n > n && j.n <= n + AHEAD)) return true;
      this.#jobs.delete(j.key);
      j.reject(new MediaError("conflict", "不再需要这一段"));
      return false;
    });
    // The one asked for first, then the next few.
    const made = (await exists(at.segment(n))) ? null : this.#ask(src, v, plan, n, true);
    // (Refused while the next are asked: refused below, not left unhandled.)
    made?.catch(() => {});
    for (let k = n + 1; k <= Math.min(n + AHEAD, plan.starts.length - 1); k++) {
      if (!(await exists(at.segment(k)))) this.#ask(src, v, plan, k, false).catch(() => {});
    }
    if (made) await made;
    else await this.#used(at.segment(n));
    return at.segment(n);
  }

  /// Segment `n` made (once: asked again, the same run), in its turn.
  #ask(src: Source, v: Variant, plan: Plan, n: number, wanted: boolean): Promise<void> {
    const at = this.#paths(src, v);
    const key = at.segment(n);
    const had = this.#jobs.get(key);
    if (had) {
      if (wanted && !had.wanted) {
        had.wanted = true;
        const i = this.#queue.indexOf(had);
        if (i > 0) {
          this.#queue.splice(i, 1);
          this.#queue.unshift(had);
        }
      }
      return had.done;
    }
    let resolve!: () => void;
    let reject!: (e: unknown) => void;
    const done = new Promise<void>((y, n) => {
      resolve = y;
      reject = n;
    });
    const job: Job = { key, title: src.id, n, wanted, run: () => this.#make(src, v, plan, n), done, resolve, reject };
    this.#jobs.set(key, job);
    if (wanted) this.#queue.unshift(job);
    else this.#queue.push(job);
    this.#pump();
    return done;
  }

  #pump() {
    while (!this.#closed && this.#runs < RUNS) {
      const i = this.#queue.findIndex((j) => !this.#running.has(j.title));
      if (i < 0) return;
      const job = this.#queue.splice(i, 1)[0]!;
      this.#runs++;
      this.#running.add(job.title);
      job
        .run()
        .then(job.resolve, job.reject)
        .finally(() => {
          this.#runs--;
          this.#running.delete(job.title);
          this.#jobs.delete(job.key);
          this.#pump();
        });
    }
  }

  /// One ffmpeg run: segment `n` as a fragmented MP4, split into the init (kept when there is none) and its fragments
  /// (moved to where the segment is).
  async #make(src: Source, v: Variant, plan: Plan, n: number): Promise<void> {
    const at = this.#paths(src, v);
    if (await exists(at.segment(n))) return;
    await mkdir(at.dir, { recursive: true });
    const start = plan.starts[n]!;
    const end = plan.starts[n + 1] ?? plan.end;
    const p = src.probe;
    const tmp = join(at.dir, `.${n}.${randomBytes(4).toString("hex")}.mp4`);
    const args: string[] = [];
    let enc: string | null = null;
    /// Where the other tracks begin after the video's first tfdt: in a remux, where they were cut, against when its
    /// first keyframe is decoded; when made here, where that frame shows (placeFragments).
    let others: number | undefined;
    if (v.mode === "copy") {
      // From the keyframe the segment begins at, its packets up to the next one. A seek in the input lands on a
      // keyframe at or before where it is asked (a Matroska file's, at its cluster's first), so it is asked a little
      // early and the packets before the keyframe (by when they are decoded) left out by the output's -ss; the other
      // tracks cut there too, made as long as the segment.
      const decode = plan.decodes![n]!;
      if (n === 0) {
        args.push("-i", src.file);
        others = Math.max(0, -decode);
      } else {
        const seek = Math.max(0, decode - 1);
        args.push("-ss", seek.toFixed(4), "-i", src.file, "-ss", Math.max(0, decode - seek - 0.0005).toFixed(4));
        others = 0;
      }
      args.push("-map", `0:${p.video!.index}`, "-c:v", "copy", "-frames:v", String(plan.frames![n]!));
      if (p.video!.codec === "hevc") args.push("-tag:v", "hvc1");
      args.push("-t", (end - (n === 0 ? 0 : decode)).toFixed(4));
    } else {
      enc = await this.encoder();
      if (!enc) throw new MediaError("unsupported", "这台 station 的 ffmpeg 没有能用的 H.264 编码器，只能直接播放");
      const height = Math.min(1080, p.video!.height || 1080);
      const rate = bitrateOf(height);
      // Seeking as a remux does: the video is decoded from the keyframe the seek lands on and cut at `start`, and
      // audio kept as it is cut there too (not from where the seek landed).
      if (n === 0) args.push("-i", src.file);
      else {
        const seek = Math.max(0, start - 1);
        args.push("-ss", seek.toFixed(4), "-i", src.file, "-ss", (start - seek).toFixed(4));
      }
      args.push("-t", (end - start).toFixed(4), "-map", `0:${p.video!.index}`);
      // A run's first frame is a keyframe; the next one no sooner than a segment later (openh264 makes them far apart
      // unless told, VideoToolbox as it likes).
      const gop = Math.max(1, Math.round((p.video!.fps ?? 30) * SEGMENT));
      args.push("-vf", `scale=w=-2:h='min(1080,ih)',format=yuv420p`, "-c:v", enc, "-g", String(gop), "-b:v", String(rate), "-maxrate", String(Math.round(rate * 1.5)), "-bufsize", String(rate * 2));
      if (enc === "h264_videotoolbox") args.push("-profile:v", "high", "-allow_sw", "1");
      else if (enc === "libx264") args.push("-preset", "veryfast", "-profile:v", "high");
    }
    if (v.audio !== null) {
      // AAC (mono or stereo) as it is: cut from one stream, segments meet without the silence each run's encoder
      // starts with; anything else made AAC stereo.
      const track = p.audio.find((x) => x.index === v.audio);
      if (track?.codec === "aac" && track.channels <= 2) args.push("-map", `0:${v.audio}`, "-c:a", "copy");
      else args.push("-map", `0:${v.audio}`, "-c:a", "aac", "-ac", "2", "-ar", "48000", "-b:a", "160k");
    }
    args.push("-sn", "-dn", "-map_metadata", "-1", "-map_chapters", "-1", "-f", "mp4", "-movflags", "frag_keyframe+empty_moov+default_base_moof+skip_trailer", "-use_editlist", "0", tmp);
    const abort = new AbortController();
    this.#aborts.add(abort);
    try {
      await runFfmpeg(this.#tools.ffmpeg!, args, 300_000, abort.signal);
      const made = await readFile(tmp);
      const { init, media, tracks } = splitFragmented(made);
      if (media.length === 0) throw new Error("ffmpeg made no fragments");
      const moved = placeFragments(media, start, tracks, n * 10_000, others);
      if (!(await exists(at.init))) {
        await writeFile(`${at.init}.tmp`, init);
        await rename(`${at.init}.tmp`, at.init);
      }
      await writeFile(`${tmp}.m4s`, moved);
      await rename(`${tmp}.m4s`, at.segment(n));
      await this.#added(at.segment(n), moved.length);
      if (enc) this.#proven.add(enc);
    } catch (e) {
      if (e instanceof MediaError) throw e;
      console.error(`media: no HLS segment ${n} of ${src.file}${enc ? ` (${enc})` : ""}: ${(e as Error).message}`);
      // An encoder that fails (VideoToolbox refused, say) while ffmpeg still reads the file: the next one is tried.
      if (enc && !abort.signal.aborted && !this.#closed && !this.#proven.has(enc)) {
        this.#failed.add(enc);
        if (await this.encoder()) return this.#make(src, v, plan, n);
      }
      throw new MediaError("internal", "这一段视频没做出来");
    } finally {
      this.#aborts.delete(abort);
      await rm(tmp, { force: true });
      await rm(`${tmp}.m4s`, { force: true });
    }
  }

  // The cache's cap.

  async #index() {
    if (this.#cache) return this.#cache;
    const cache = new Map<string, { size: number; used: number }>();
    const walk = async (dir: string) => {
      for (const e of await readdir(dir, { withFileTypes: true }).catch(() => [])) {
        const p = join(dir, e.name);
        if (e.isDirectory()) await walk(p);
        else if (e.name.endsWith(".m4s")) {
          const s = await stat(p).catch(() => null);
          if (s) cache.set(p, { size: s.size, used: s.mtimeMs });
        }
      }
    };
    await walk(this.#dir);
    this.#cache = cache;
    this.#total = [...cache.values()].reduce((n, x) => n + x.size, 0);
    return cache;
  }

  async #used(file: string) {
    const cache = await this.#index();
    const e = cache.get(file);
    const now = Date.now();
    if (e) e.used = now;
    await utimes(file, now / 1000, now / 1000).catch(() => {});
  }

  /// A segment kept: the least lately used ones removed while the cache is above its cap.
  async #added(file: string, size: number) {
    const cache = await this.#index();
    const was = cache.get(file);
    this.#total += size - (was?.size ?? 0);
    cache.set(file, { size, used: Date.now() });
    if (this.#total <= this.#cap) return;
    const oldest = [...cache.entries()].sort((a, b) => a[1].used - b[1].used);
    for (const [p, e] of oldest) {
      if (this.#total <= this.#cap * 0.9) break;
      if (p === file) continue;
      await rm(p, { force: true });
      cache.delete(p);
      this.#total -= e.size;
    }
  }

  /// How many bytes the cache holds (its segments).
  async size(): Promise<number> {
    await this.#index();
    return this.#total;
  }
}

const exists = (p: string) => stat(p).then(
  () => true,
  () => false,
);

// Fragmented MP4.

type Box = { type: string; start: number; end: number; body: number };

function boxes(b: Buffer, start: number, end: number): Box[] {
  const out: Box[] = [];
  let i = start;
  while (i + 8 <= end) {
    let size = b.readUInt32BE(i);
    let head = 8;
    if (size === 1) {
      size = Number(b.readBigUInt64BE(i + 8));
      head = 16;
    } else if (size === 0) size = end - i;
    if (size < head || i + size > end) break;
    out.push({ type: b.toString("latin1", i + 4, i + 8), start: i, end: i + size, body: i + head });
    i += size;
  }
  return out;
}

const child = (b: Buffer, box: Box, type: string, skip = 0) => boxes(b, box.body + skip, box.end).find((x) => x.type === type);

export type Track = { timescale: number; video: boolean };

/// A fragmented MP4 split: its init (ftyp, moov), its fragments (moof, mdat…), each track's timescale and whether it
/// is the video.
export function splitFragmented(b: Buffer): { init: Buffer; media: Buffer; tracks: Map<number, Track> } {
  const top = boxes(b, 0, b.length);
  const moov = top.find((x) => x.type === "moov");
  if (!moov) throw new Error("no moov");
  const tracks = new Map<number, Track>();
  for (const trak of boxes(b, moov.body, moov.end).filter((x) => x.type === "trak")) {
    const tkhd = child(b, trak, "tkhd");
    const mdia = child(b, trak, "mdia");
    const mdhd = mdia && child(b, mdia, "mdhd");
    const hdlr = mdia && child(b, mdia, "hdlr");
    if (!tkhd || !mdhd) continue;
    const id = b.readUInt32BE(tkhd.body + (b[tkhd.body] === 1 ? 20 : 12));
    const timescale = b.readUInt32BE(mdhd.body + (b[mdhd.body] === 1 ? 20 : 12));
    tracks.set(id, { timescale, video: hdlr ? b.toString("latin1", hdlr.body + 8, hdlr.body + 12) === "vide" : false });
  }
  const first = top.find((x) => x.type === "moof");
  const media = first ? b.subarray(first.start, top.filter((x) => x.type === "moof" || x.type === "mdat").at(-1)!.end) : Buffer.alloc(0);
  return { init: Buffer.from(b.subarray(0, moov.end)), media: Buffer.from(media), tracks };
}

/// The composition offset of a traf's first sample (its trun's), in its track's timescale; 0 when it has none.
function firstOffset(b: Buffer, traf: Box): number {
  const trun = child(b, traf, "trun");
  if (!trun) return 0;
  const version = b[trun.body]!;
  const flags = b.readUIntBE(trun.body + 1, 3);
  if (!(flags & 0x800) || b.readUInt32BE(trun.body + 4) === 0) return 0;
  let at = trun.body + 8 + (flags & 0x1 ? 4 : 0) + (flags & 0x4 ? 4 : 0);
  at += (flags & 0x100 ? 4 : 0) + (flags & 0x200 ? 4 : 0) + (flags & 0x400 ? 4 : 0);
  return version === 1 ? b.readInt32BE(at) : b.readUInt32BE(at);
}

/// The fragments put where the segment begins, `seconds` in, numbered from `sequence` + 1 (mfhd). ffmpeg starts each
/// track of a run's output at 0 (no edit list), whatever their offset was; here the video's first tfdt is made
/// `seconds` (in its timescale), and the other tracks' first `others` seconds after it, by default where the video's
/// first frame shows (its composition offset: B-frames make it later than its tfdt), so that they play together. The
/// later fragments keep their distance.
export function placeFragments(media: Buffer, seconds: number, tracks: Map<number, Track>, sequence: number, others?: number): Buffer {
  const b = Buffer.from(media);
  const read = (tfdt: Box) => (b[tfdt.body] === 1 ? b.readBigUInt64BE(tfdt.body + 4) : BigInt(b.readUInt32BE(tfdt.body + 4)));
  const firsts = new Map<number, bigint>();
  const trafs: { id: number; tfdt: Box }[] = [];
  let shows = 0;
  let k = 0;
  for (const moof of boxes(b, 0, b.length).filter((x) => x.type === "moof")) {
    const mfhd = child(b, moof, "mfhd");
    if (mfhd) b.writeUInt32BE((sequence + ++k) >>> 0, mfhd.body + 4);
    for (const traf of boxes(b, moof.body, moof.end).filter((x) => x.type === "traf")) {
      const tfhd = child(b, traf, "tfhd");
      const tfdt = child(b, traf, "tfdt");
      if (!tfhd || !tfdt) continue;
      const id = b.readUInt32BE(tfhd.body + 4);
      const t = read(tfdt);
      if (!firsts.has(id)) {
        firsts.set(id, t);
        const track = tracks.get(id);
        if (track?.video) shows = Math.max(0, firstOffset(b, traf)) / track.timescale;
      }
      trafs.push({ id, tfdt });
    }
  }
  for (const { id, tfdt } of trafs) {
    const track = tracks.get(id);
    const ts = track?.timescale ?? 0;
    const at = track?.video ? seconds : seconds + (others ?? shows);
    const v = read(tfdt) - firsts.get(id)! + BigInt(Math.round(at * ts));
    if (b[tfdt.body] === 1) b.writeBigUInt64BE(v, tfdt.body + 4);
    else {
      if (v > 0xffffffffn) throw new Error("tfdt beyond 32 bits");
      b.writeUInt32BE(Number(v), tfdt.body + 4);
    }
  }
  return b;
}
