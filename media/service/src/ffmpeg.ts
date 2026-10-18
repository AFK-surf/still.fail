// ffmpeg and ffprobe, as the media service's package ships them (docs/media-service.md 影视): where they are
// (MEDIA_FFMPEG / MEDIA_FFPROBE, else $MODULE_BIN_DIR, else PATH), what ffprobe says of a video (its streams, their
// codecs and languages, its length, HDR), which H.264 encoder there is, and running them with a time limit.
import { execFile, spawn } from "node:child_process";
import { accessSync, constants, statSync } from "node:fs";
import { open } from "node:fs/promises";
import { delimiter, join } from "node:path";

export type Tools = { ffmpeg: string | null; ffprobe: string | null };

function executable(p: string): boolean {
  try {
    accessSync(p, constants.X_OK);
    return statSync(p).isFile();
  } catch {
    return false;
  }
}

/// ffmpeg and ffprobe: each from its variable (MEDIA_FFMPEG, MEDIA_FFPROBE), else in the package's bin folder
/// ($MODULE_BIN_DIR, set by the station), else on PATH; null when not found.
export function tools(env: NodeJS.ProcessEnv = process.env): Tools {
  const find = (name: "ffmpeg" | "ffprobe", variable: string): string | null => {
    const given = env[variable];
    if (given) return executable(given) ? given : null;
    if (env.MODULE_BIN_DIR && executable(join(env.MODULE_BIN_DIR, name))) return join(env.MODULE_BIN_DIR, name);
    for (const dir of (env.PATH ?? "").split(delimiter)) {
      if (dir && executable(join(dir, name))) return join(dir, name);
    }
    return null;
  };
  return { ffmpeg: find("ffmpeg", "MEDIA_FFMPEG"), ffprobe: find("ffprobe", "MEDIA_FFPROBE") };
}

/// Whether the service itself may read the file (a folder macOS protects, read through still.fail Helper, is not).
export async function readable(file: string): Promise<boolean> {
  if (!file.startsWith("/")) return false;
  try {
    const f = await open(file, "r");
    try {
      await f.read(Buffer.alloc(1), 0, 1, 0);
    } finally {
      await f.close();
    }
    return true;
  } catch {
    return false;
  }
}

/// A program's output (stdout as bytes), refused when it fails or takes longer than `ms`.
export function output(cmd: string, args: string[], ms = 60_000, most = 64 * 1024 * 1024): Promise<Buffer> {
  return new Promise((done, fail) => {
    execFile(cmd, args, { timeout: ms, maxBuffer: most, encoding: "buffer" }, (e, stdout, stderr) => {
      if (e) {
        const tail = Buffer.from(stderr ?? "").toString("utf8").trim().split("\n").slice(-3).join(" | ");
        return fail(new Error(`${cmd.split("/").pop()} failed: ${tail || e.message}`));
      }
      done(stdout);
    });
  });
}

/// Runs ffmpeg (quietly, overwriting), killed when `signal` aborts or after `ms`.
export function runFfmpeg(ffmpeg: string, args: string[], ms = 120_000, signal?: AbortSignal): Promise<void> {
  return new Promise((done, fail) => {
    const child = spawn(ffmpeg, ["-hide_banner", "-nostdin", "-loglevel", "error", "-y", ...args], { stdio: ["ignore", "ignore", "pipe"] });
    let err = "";
    child.stderr.on("data", (b: Buffer) => {
      if (err.length < 8192) err += b.toString("utf8");
    });
    const timer = setTimeout(() => child.kill("SIGKILL"), ms);
    const abort = () => child.kill("SIGKILL");
    signal?.addEventListener("abort", abort, { once: true });
    child.on("error", (e) => {
      clearTimeout(timer);
      fail(e);
    });
    child.on("close", (code, sig) => {
      clearTimeout(timer);
      signal?.removeEventListener("abort", abort);
      if (code === 0) done();
      else fail(new Error(`ffmpeg ${sig ? `killed (${sig})` : `exited ${code}`}: ${err.trim().split("\n").slice(-3).join(" | ")}`));
    });
  });
}

// What a video is.

export type VideoTrack = { index: number; codec: string; profile: string | null; width: number; height: number; hdr: "hdr10" | "hlg" | "dolby-vision" | null; fps: number | null; bitDepth: number | null; mime: string | null };
export type AudioTrack = { index: number; codec: string; lang: string | null; title: string | null; channels: number; default: boolean };
export type SubtitleTrack = { index: number; codec: string; lang: string | null; title: string | null; default: boolean; forced: boolean; text: boolean };
export type Probe = { container: string; duration: number | null; bitrate: number | null; start: number; video: VideoTrack | null; audio: AudioTrack[]; subtitles: SubtitleTrack[] };

/// Subtitle codecs that are text (made WebVTT by ffmpeg); the others are pictures (PGS, DVD).
const TEXT_SUBS = new Set(["subrip", "srt", "ass", "ssa", "webvtt", "mov_text", "text", "microdvd", "subviewer", "jacosub", "sami", "realtext", "stl", "mpl2", "pjs", "vplayer"]);

type Stream = Record<string, unknown> & { tags?: Record<string, string>; disposition?: Record<string, number>; side_data_list?: { side_data_type?: string }[] };

/// ffprobe's JSON (`-show_format -show_streams`) as the service keeps it.
export function parseProbe(json: string): Probe {
  const p = JSON.parse(json) as { format?: Record<string, unknown> & { tags?: Record<string, string> }; streams?: Stream[] };
  const num = (v: unknown) => {
    const n = typeof v === "string" ? Number(v) : typeof v === "number" ? v : NaN;
    return Number.isFinite(n) ? n : null;
  };
  const tag = (s: Stream, k: string) => {
    const tags = s.tags ?? {};
    const key = Object.keys(tags).find((x) => x.toLowerCase() === k);
    const v = key ? tags[key]!.trim() : "";
    return v && v !== "und" ? v : null;
  };
  const streams = p.streams ?? [];
  const fmt = p.format ?? {};
  const v = streams.find((s) => s.codec_type === "video" && !(s.disposition?.attached_pic === 1) && s.codec_name !== "mjpeg" && s.codec_name !== "png");
  let video: VideoTrack | null = null;
  if (v) {
    const transfer = String(v.color_transfer ?? "");
    const dovi = (v.side_data_list ?? []).some((d) => /dovi|dolby vision/i.test(d.side_data_type ?? "")) || v.codec_tag_string === "dvh1" || v.codec_tag_string === "dvhe";
    const rate = String(v.avg_frame_rate ?? v.r_frame_rate ?? "");
    const [a, b] = rate.split("/").map(Number);
    const fps = a && b ? Math.round((a / b) * 1000) / 1000 : null;
    const pix = String(v.pix_fmt ?? "");
    const depth = num(v.bits_per_raw_sample) ?? (/10(le|be)?$|p010/.test(pix) ? 10 : /12(le|be)?$/.test(pix) ? 12 : pix ? 8 : null);
    video = {
      index: num(v.index) ?? 0,
      codec: String(v.codec_name ?? "unknown"),
      profile: typeof v.profile === "string" ? v.profile : null,
      width: num(v.width) ?? 0,
      height: num(v.height) ?? 0,
      hdr: dovi ? "dolby-vision" : transfer === "smpte2084" ? "hdr10" : transfer === "arib-std-b67" ? "hlg" : null,
      fps,
      bitDepth: depth,
      mime: typeof v.mime_codec_string === "string" ? v.mime_codec_string : null,
    };
  }
  const audio: AudioTrack[] = streams
    .filter((s) => s.codec_type === "audio")
    .map((s) => ({ index: num(s.index) ?? 0, codec: String(s.codec_name ?? "unknown"), lang: tag(s, "language"), title: tag(s, "title"), channels: num(s.channels) ?? 2, default: s.disposition?.default === 1 }));
  const subtitles: SubtitleTrack[] = streams
    .filter((s) => s.codec_type === "subtitle")
    .map((s) => {
      const codec = String(s.codec_name ?? "unknown");
      return { index: num(s.index) ?? 0, codec, lang: tag(s, "language"), title: tag(s, "title"), default: s.disposition?.default === 1, forced: s.disposition?.forced === 1, text: TEXT_SUBS.has(codec) };
    });
  const duration = num(fmt.duration) ?? (v ? num(v.duration) : null);
  return { container: String(fmt.format_name ?? ""), duration: duration !== null && duration > 0 ? duration : null, bitrate: num(fmt.bit_rate), start: num(fmt.start_time) ?? 0, video, audio, subtitles };
}

/// What ffprobe says of the file.
export async function probe(ffprobe: string, file: string): Promise<Probe> {
  const out = await output(ffprobe, ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", file], 60_000);
  return parseProbe(out.toString("utf8"));
}

export type Keyframes = { times: number[]; decodes: number[]; packets: number[]; total: number };

/// The video's keyframes, by its packets (in decode order): their times from its start (when they show, and when they
/// are decoded: earlier with B-frames), their packets' numbers, and how many packets there are; where a remuxed segment
/// may begin. Null when that takes longer than `ms` (a large
/// Matroska file is read whole).
export async function keyframes(ffprobe: string, file: string, start: number, ms = 120_000): Promise<Keyframes | null> {
  let out: Buffer;
  try {
    out = await output(ffprobe, ["-v", "error", "-select_streams", "v:0", "-show_entries", "packet=pts_time,dts_time,flags", "-of", "csv=p=0", file], ms, 1024 * 1024 * 1024);
  } catch {
    return null;
  }
  const k: Keyframes = { times: [], decodes: [], packets: [], total: 0 };
  for (const line of out.toString("latin1").split("\n")) {
    if (!line.trim()) continue;
    const [pts, dts, flags] = line.split(",");
    const n = k.total++;
    if (!flags?.startsWith("K")) continue;
    const t = Number(pts !== "N/A" && pts ? pts : dts);
    if (!Number.isFinite(t)) continue;
    const d = Number(dts !== "N/A" && dts ? dts : t);
    const rel = Math.max(0, t - start);
    // In decode order; one not after the last (a broken file's) is left out.
    if (k.times.length > 0 && rel <= k.times[k.times.length - 1]!) continue;
    k.times.push(rel);
    k.decodes.push(Number.isFinite(d) ? Math.min(d, t) - start : t - start);
    k.packets.push(n);
  }
  return k;
}

/// The H.264 encoders tried, in order: VideoToolbox on macOS, openh264 (the package's on Linux), x264 (only a
/// developer's ffmpeg has it: the package's is LGPL).
const ENCODERS = ["h264_videotoolbox", "libopenh264", "libx264"];

/// The H.264 encoders this ffmpeg has, in the order they are tried (whether one works here is known when it is used:
/// the package's ffmpeg has no lavfi to try one on, and VideoToolbox may be refused, as on a Mac without a session).
export async function findEncoders(ffmpeg: string): Promise<string[]> {
  let listed = "";
  try {
    listed = (await output(ffmpeg, ["-hide_banner", "-encoders"], 20_000)).toString("utf8");
  } catch {
    return [];
  }
  return ENCODERS.filter((enc) => (enc !== "h264_videotoolbox" || process.platform === "darwin") && new RegExp(`\\s${enc}\\s`).test(listed));
}
