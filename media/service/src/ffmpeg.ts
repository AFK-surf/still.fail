// Where the media service's ffmpeg and ffprobe are: MEDIA_FFMPEG and MEDIA_FFPROBE when set (a build of one's own:
// FFmpeg's LGPL lets anyone use theirs); else those its package carries, in the bin/ the station names
// (MODULE_BIN_DIR: scripts/module-bundle.ts packs the native part `ffmpeg` there, scripts/ffmpeg.ts); else the ones on
// PATH (development, tests).
import { existsSync } from "node:fs";
import { join } from "node:path";

export type Tools = { ffmpeg: string; ffprobe: string };

export function tools(env: NodeJS.ProcessEnv = process.env): Tools {
  const bin = env.MODULE_BIN_DIR;
  const of = (name: "ffmpeg" | "ffprobe", given: string | undefined) =>
    given || (bin && existsSync(join(bin, name)) ? join(bin, name) : name);
  return { ffmpeg: of("ffmpeg", env.MEDIA_FFMPEG), ffprobe: of("ffprobe", env.MEDIA_FFPROBE) };
}
