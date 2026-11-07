// FFmpeg for the media service (the native part `ffmpeg` of scripts/native.ts, carried in the media service's package: docs/station-modules.md): ffmpeg and
// ffprobe built from FFmpeg's release tarball, as LGPL-2.1-or-later only (no --enable-gpl, no --enable-nonfree, no
// --enable-version3: nothing GPL, nothing unredistributable), with only what the media service uses (--disable-everything,
// then the formats, codecs and filters below). Static but for the system's own libraries: on macOS its frameworks and
// libz; on Linux glibc (2.28 and later, through zig, as the station's other Linux parts are built) and nothing else
// (zlib and Cisco's openh264 built in). H.264 is encoded by VideoToolbox on macOS and by openh264 on Linux; audio by
// FFmpeg's own AAC encoder. Every source is pinned and checked against its SHA-256; nothing is patched, so the
// corresponding source of what is shipped is those tarballs and this file (SOURCE, beside the binaries, says so).
//
// Its key is made of this file alone (its own zig, no Rust toolchain): a media service package carries the build its
// key names (scripts/module-bundle.ts), and its version moves with this file.
import { spawnSync, type SpawnSyncOptions } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { availableParallelism, tmpdir } from "node:os";
import { join } from "node:path";

export type FfmpegTarget = "darwin-arm64" | "linux-x64" | "linux-arm64";
export const TARGETS: FfmpegTarget[] = ["darwin-arm64", "linux-x64", "linux-arm64"];

type Source = { name: string; version: string; url: string; sha256: string; license: string; file?: string };
/// Where still.fail keeps its own copy of each shipped source, as the LGPL asks: the release `third-party-sources` of
/// the repository, each tarball under `file` (or its upstream name), the same bytes as upstream's.
const COPIES = "https://github.com/AFK-surf/still.fail/releases/download/third-party-sources";
const copyOf = (s: Source): string | null => (s === NASM ? null : `${COPIES}/${s.file ?? s.url.split("/").pop()}`);
export const FFMPEG: Source = {
  name: "FFmpeg",
  version: "9.0.2",
  url: "https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz",
  sha256: "8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e",
  license: "LGPL-2.1-or-later",
};
/// Linux's H.264 encoder (libopenh264), built from Cisco's source.
export const OPENH264: Source = {
  name: "OpenH264",
  version: "2.6.0",
  url: "https://github.com/cisco/openh264/archive/refs/tags/v2.6.0.tar.gz",
  sha256: "558544ad358283a7ab2930d69a9ceddf913f4a51ee9bf1bfb9e377322af81a69",
  license: "BSD-2-Clause",
  file: "openh264-2.6.0.tar.gz",
};
/// Linux's zlib (the PNG decoder needs it; compressed MOV headers and Matroska tracks use it). macOS has its own.
export const ZLIB: Source = {
  name: "zlib",
  version: "1.3.2",
  url: "https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz",
  sha256: "bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16",
  license: "Zlib",
};
/// The assembler for x86-64's SIMD (FFmpeg's and openh264's): built here for the build only, not shipped.
export const NASM: Source = {
  name: "NASM",
  version: "3.02",
  url: "https://www.nasm.us/pub/nasm/releasebuilds/3.02/nasm-3.02.tar.xz",
  sha256: "87336eba53b4acfe917424ab5d500d2b0054d9f5148d35c2273ccf2cfb712f0d",
  license: "BSD-2-Clause",
};
/// zig, the Linux builds' C compiler from a Mac (its own pin, part of the key: scripts/native.ts ZIG may move without
/// building FFmpeg again).
export const ZIG = "0.16.0";
/// The oldest macOS the binaries run on.
const MACOS_MIN = "12.0";
const ZIG_TARGET: Record<string, string> = { "linux-x64": "x86_64-linux-gnu.2.28", "linux-arm64": "aarch64-linux-gnu.2.28" };

/// What is enabled after --disable-everything: what the media service reads (the containers and codecs of films and
/// series, their subtitles), writes (HLS of MPEG-TS or fMP4 segments, MP4, WebVTT, JPEG posters) and needs between.
export const COMPONENTS = {
  demuxer: ["mov", "matroska", "mpegts", "avi", "ass", "srt", "webvtt"],
  muxer: ["mp4", "mov", "mpegts", "hls", "webvtt", "image2", "mjpeg", "null"],
  decoder: [
    "h264", "hevc", "vp8", "vp9", "mpeg2video", "mpeg4", "mjpeg", "png",
    "aac", "ac3", "eac3", "mp3", "mp3float", "opus", "vorbis", "flac", "dca", "truehd", "pcm*",
    "subrip", "srt", "ass", "ssa", "webvtt", "mov_text",
    // What lavfi hands on (the self-test's input).
    "wrapped_avframe",
  ],
  // wrapped_avframe and pcm_s16le: what `-f null -` writes (decoding a whole file to time it or check it).
  encoder: ["aac", "mjpeg", "webvtt", "wrapped_avframe", "pcm_s16le"],
  parser: ["h264", "hevc", "aac", "ac3", "vp8", "vp9", "mpegaudio", "mpegvideo", "mpeg4video", "dca", "opus", "vorbis", "flac", "mjpeg"],
  bsf: ["h264_mp4toannexb", "hevc_mp4toannexb", "aac_adtstoasc", "extract_extradata", "vp9_superframe", "null"],
  filter: [
    "scale", "format", "aresample", "null", "anull", "fps",
    // What the ffmpeg command puts in every graph.
    "buffer", "buffersink", "abuffer", "abuffersink", "aformat", "atrim", "trim", "crop", "hflip", "vflip", "transpose",
    // Inputs for a self-test (`-f lavfi -i testsrc`), a few kB.
    "testsrc", "sine",
  ],
  protocol: ["file", "pipe"],
  indev: ["lavfi"],
} as const;

/// FFmpeg's configure flags for `target` (but where the build's own tools are, which the build adds).
export function configureFlags(target: FfmpegTarget): string[] {
  const list = (kind: keyof typeof COMPONENTS, more: string[] = []) => `--enable-${kind}=${[...COMPONENTS[kind], ...more].join(",")}`;
  const darwin = target === "darwin-arm64";
  return [
    "--disable-gpl", "--disable-nonfree", "--disable-version3",
    "--enable-static", "--disable-shared", "--disable-autodetect", "--disable-debug", "--disable-doc", "--disable-network",
    "--disable-programs", "--enable-ffmpeg", "--enable-ffprobe",
    "--disable-everything",
    list("demuxer"), list("muxer"), list("decoder"),
    list("encoder", darwin ? ["h264_videotoolbox"] : ["libopenh264"]),
    list("parser"), list("bsf"), list("filter"), list("protocol"), list("indev"),
    "--enable-zlib",
    ...(darwin
      ? ["--enable-videotoolbox", "--enable-hwaccel=h264_videotoolbox,hevc_videotoolbox", "--arch=arm64", "--target-os=darwin", `--extra-cflags=-mmacosx-version-min=${MACOS_MIN}`, `--extra-ldflags=-mmacosx-version-min=${MACOS_MIN}`]
      : ["--enable-libopenh264", "--enable-cross-compile", "--target-os=linux", `--arch=${target === "linux-x64" ? "x86_64" : "aarch64"}`, "--disable-stripping", "--pkg-config-flags=--static"]),
    "--extra-version=stillfail",
  ];
}

/// What the artifact holds: the two commands, then what has to go with them (FFmpeg's license and where its source
/// is; on Linux the notices of what is built in).
export const files = (target: FfmpegTarget): string[] => [
  "ffmpeg", "ffprobe", "ffmpeg-LICENSE.md", "ffmpeg-COPYING.LGPLv2.1", "SOURCE",
  ...(target === "darwin-arm64" ? [] : ["openh264-LICENSE", "zlib-LICENSE"]),
];

/// All the key needs to know of a build (with this file's hash, native.ts adds).
export const recipe = (target: FfmpegTarget) => ({
  sources: [FFMPEG, ...(target === "darwin-arm64" ? [] : [OPENH264, ZLIB]), ...(target === "linux-x64" ? [NASM] : [])].map(({ name, version, sha256 }) => ({ name, version, sha256 })),
  configure: configureFlags(target),
  zig: target === "darwin-arm64" ? undefined : ZIG,
  macos: target === "darwin-arm64" ? MACOS_MIN : undefined,
});

const log = (msg: string) => process.stderr.write(`ffmpeg: ${msg}\n`);

function run(cmd: string, args: string[], options: SpawnSyncOptions = {}) {
  const done = spawnSync(cmd, args, { stdio: ["ignore", process.stderr, process.stderr], ...options });
  if (done.error) throw done.error;
  if (done.status !== 0) throw new Error(`${cmd} ${args.join(" ")}: exit ${done.status ?? done.signal}`);
}

/// `source`'s tarball unpacked in `work` (checked against its SHA-256 first): its directory. From upstream, else from
/// still.fail's copy.
function fetchSource(source: Source, work: string): string {
  const file = join(work, source.url.split("/").pop()!);
  const copy = copyOf(source);
  try {
    run("curl", ["-fsSL", "--retry", "5", "--retry-all-errors", source.url, "-o", file]);
  } catch (e) {
    if (!copy) throw e;
    console.error(`native: ${source.url} not fetched (${(e as Error).message}); from ${copy}`);
    run("curl", ["-fsSL", "--retry", "5", "--retry-all-errors", copy, "-o", file]);
  }
  const got = createHash("sha256").update(readFileSync(file)).digest("hex");
  if (got !== source.sha256) throw new Error(`${source.url}: sha256 ${got}, not ${source.sha256}`);
  const dir = join(work, `${source.name.toLowerCase()}-src`);
  mkdirSync(dir);
  run("tar", ["-xf", file, "-C", dir, "--strip-components", "1"]);
  rmSync(file);
  return dir;
}

/// A shell script at `path` running `line` with its arguments.
function script(path: string, line: string) {
  writeFileSync(path, `#!/bin/sh\n${line}\n`);
  chmodSync(path, 0o755);
}

/// ffmpeg and ffprobe for `target` built into `out` (a fresh directory), with their notices and SOURCE.
export function build(target: FfmpegTarget, out: string): void {
  const work = join(process.env.CARGO_TARGET_DIR ? join(process.env.CARGO_TARGET_DIR, "native") : tmpdir(), `ffmpeg-${target}-${process.pid}`);
  rmSync(work, { recursive: true, force: true });
  mkdirSync(work, { recursive: true });
  const jobs = String(availableParallelism());
  const env: NodeJS.ProcessEnv = { ...process.env, PATH: ["/opt/homebrew/bin", process.env.PATH].join(":"), LC_ALL: "C" };
  try {
    const flags = configureFlags(target);
    const extra: string[] = [];
    const ffmpeg = fetchSource(FFMPEG, work);
    if (target !== "darwin-arm64") {
      const zig = spawnSync("zig", ["version"], { env, encoding: "utf8" }).stdout?.trim();
      if (zig !== ZIG) log(`zig ${zig || "(none)"} here, the key assumes ${ZIG}`);
      // The cross tools: zig's clang for the target (no sanitizer: zig's default for an unoptimized compile, which
      // configure's tests are; not openh264's -march=armv8-a, which zig does not know: the target's baseline is
      // that), its ar and ranlib.
      const bin = join(work, "bin");
      mkdirSync(bin);
      const triple = ZIG_TARGET[target]!;
      const drop = `for a; do shift; [ "$a" = -march=armv8-a ] || set -- "$@" "$a"; done`;
      script(join(bin, "cc"), `${drop}\nexec zig cc -target ${triple} -fno-sanitize=all "$@"`);
      script(join(bin, "c++"), `${drop}\nexec zig c++ -target ${triple} -fno-sanitize=all "$@"`);
      script(join(bin, "ar"), `exec zig ar "$@"`);
      script(join(bin, "ranlib"), `exec zig ranlib "$@"`);
      const prefix = join(work, "prefix");
      mkdirSync(join(prefix, "lib"), { recursive: true });
      mkdirSync(join(prefix, "include"), { recursive: true });
      let nasm: string | null = null;
      if (target === "linux-x64") {
        // NASM for this machine, for the build.
        const src = fetchSource(NASM, work);
        run("sh", ["./configure", `--prefix=${join(work, "tools")}`], { cwd: src, env });
        run("make", [`-j${jobs}`], { cwd: src, env });
        nasm = join(src, "nasm");
      }
      // zlib: its sources compiled as they are (its configure looks at the machine it runs on, not the target).
      const z = fetchSource(ZLIB, work);
      const zfiles = ["adler32", "compress", "crc32", "deflate", "gzclose", "gzlib", "gzread", "gzwrite", "infback", "inffast", "inflate", "inftrees", "trees", "uncompr", "zutil"];
      for (const f of zfiles) run(join(bin, "cc"), ["-O2", "-fPIC", "-DHAVE_UNISTD_H", "-DHAVE_STDARG_H", "-c", `${f}.c`, "-o", `${f}.o`], { cwd: z, env });
      run(join(bin, "ar"), ["rcs", join(prefix, "lib/libz.a"), ...zfiles.map((f) => `${f}.o`)], { cwd: z, env });
      for (const h of ["zlib.h", "zconf.h"]) copyFileSync(join(z, h), join(prefix, "include", h));
      // openh264, static, with its SIMD.
      const h264 = fetchSource(OPENH264, work);
      run("make", [
        `-j${jobs}`, "OS=linux", `ARCH=${target === "linux-x64" ? "x86_64" : "arm64"}`, `CC=${join(bin, "cc")}`, `CXX=${join(bin, "c++")}`, `AR=${join(bin, "ar")}`,
        ...(nasm ? [`ASM=${nasm}`] : []), `PREFIX=${prefix}`, "install-static",
      ], { cwd: h264, env });
      // pkg-config, answering for openh264 alone (as installed above; its C++ runtime zig's libc++): nothing of this
      // machine's own packages can come in.
      script(join(bin, "pkg-config"), [
        `case " $* " in *" --version "*) echo 0.29.2; exit 0;; *" openh264 "*) ;; *) exit 1;; esac`,
        `for a; do case "$a" in`,
        `  --modversion) echo ${OPENH264.version};;`,
        `  --cflags) echo "-I${prefix}/include";;`,
        `  --libs) echo "-L${prefix}/lib -lopenh264 -lc++ -lpthread -lm";;`,
        `esac; done`,
      ].join("\n"));
      extra.push(
        `--cc=${join(bin, "cc")}`, `--cxx=${join(bin, "c++")}`, `--ar=${join(bin, "ar")}`, `--ranlib=${join(bin, "ranlib")}`, "--nm=nm",
        `--pkg-config=${join(bin, "pkg-config")}`, "--host-cc=cc",
        `--extra-cflags=-I${join(prefix, "include")}`, `--extra-ldflags=-L${join(prefix, "lib")} -s`,
        ...(nasm ? [`--x86asmexe=${nasm}`] : []),
      );
      copyFileSync(join(h264, "LICENSE"), join(out, "openh264-LICENSE"));
      copyFileSync(join(z, "LICENSE"), join(out, "zlib-LICENSE"));
    } else {
      extra.push("--cc=clang");
    }
    run("sh", ["./configure", ...flags, ...extra], { cwd: ffmpeg, env });
    if (target !== "darwin-arm64") {
      // glibc 2.28 links sysctl(), but zig's headers (glibc's newest, which dropped it) have no sys/sysctl.h; Linux
      // counts CPUs by sched_getaffinity anyway.
      const config = join(ffmpeg, "config.h");
      writeFileSync(config, readFileSync(config, "utf8").replace("#define HAVE_SYSCTL 1", "#define HAVE_SYSCTL 0"));
    }
    run("make", [`-j${jobs}`, "ffmpeg", "ffprobe"], { cwd: ffmpeg, env });
    for (const f of ["ffmpeg", "ffprobe"]) {
      copyFileSync(join(ffmpeg, f), join(out, f));
      chmodSync(join(out, f), 0o755);
    }
    copyFileSync(join(ffmpeg, "LICENSE.md"), join(out, "ffmpeg-LICENSE.md"));
    copyFileSync(join(ffmpeg, "COPYING.LGPLv2.1"), join(out, "ffmpeg-COPYING.LGPLv2.1"));
    writeFileSync(join(out, "SOURCE"), sourceNote(target));
    for (const f of files(target)) if (!existsSync(join(out, f))) throw new Error(`the build made no ${f}`);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

/// SOURCE: what the binaries beside it are, under which licenses, and where their complete source is.
export function sourceNote(target: FfmpegTarget): string {
  const built = target === "darwin-arm64" ? [FFMPEG] : [FFMPEG, OPENH264, ZLIB];
  return [
    `ffmpeg and ffprobe (${target}), as still.fail's media service runs them.`,
    "",
    `They are FFmpeg ${FFMPEG.version}, built as LGPL-2.1-or-later only (no GPL or non-free part), unmodified, from:`,
    ...built.map((s) => `  ${s.name} ${s.version} (${s.license}): ${s.url}\n    still.fail's copy: ${copyOf(s)}\n    sha256 ${s.sha256}`),
    "",
    "FFmpeg is free software under the GNU Lesser General Public License, version 2.1 or later (ffmpeg-LICENSE.md,",
    "ffmpeg-COPYING.LGPLv2.1). You may get its source above (upstream's, or still.fail's copy of the same bytes),",
    "rebuild it, change it and use your own build in place of these (the media service runs $MEDIA_FFMPEG and",
    "$MEDIA_FFPROBE when they are set).",
    ...(target === "darwin-arm64" ? [] : [
      "OpenH264 (Copyright (c) 2013, Cisco Systems) is under the BSD 2-Clause license (openh264-LICENSE); zlib",
      "(Copyright (C) 1995-2026 Jean-loup Gailly and Mark Adler) under the zlib license (zlib-LICENSE).",
    ]),
    "",
    "How they were built: scripts/ffmpeg.ts in https://github.com/AFK-surf/still.fail, with these configure flags",
    "(and the build's own tool paths):",
    ...configureFlags(target).map((f) => `  ${f}`),
    "",
  ].join("\n");
}
