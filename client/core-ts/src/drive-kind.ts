// What kind an entry of a station's drive is, by its name, and what a press on it does (the `drive` topic's `kind` and
// `opens`: drive.ts). It imports nothing: a made-up core (the web's demo, its stories) names its entries as the core does.

/// What kind an entry is (its mark; what opens it: `opensOf`).
export type DriveKind = "folder" | "video" | "audio" | "image" | "markdown" | "text" | "code" | "csv" | "html" | "pdf" | "subtitle" | "other";

const EXT: Record<string, DriveKind> = {};
const put = (kind: DriveKind, exts: string) => exts.split(" ").forEach((e) => (EXT[e] = kind));
put("video", "mp4 m4v mov webm mkv avi ts m2ts flv wmv 3gp");
put("audio", "mp3 m4a aac flac wav ogg opus wma");
put("image", "png jpg jpeg gif webp svg heic bmp avif");
put("markdown", "md markdown");
put("text", "txt log text");
put("code", "js mjs cjs ts tsx jsx json py rb go rs java kt kts swift c h cc cpp hpp cs php sh zsh bash fish ps1 sql yaml yml toml ini conf cfg xml css scss less lua pl r dart vue svelte gradle mk cmake");
put("csv", "csv tsv");
put("html", "html htm");
put("pdf", "pdf");
put("subtitle", "srt vtt ass ssa sub");

/// How an entry is opened: entered, read in the reader, played, previewed as a chat's files are, or saved to the device.
export type DriveOpener = "folder" | "read" | "play" | "preview" | "save";

/// What a press on an entry of a kind does (every client's, docs/drive.md).
export function opensOf(kind: DriveKind): DriveOpener {
  switch (kind) {
    case "folder": return "folder";
    case "text": case "markdown": return "read";
    case "video": case "audio": return "play";
    case "image": case "pdf": case "code": case "csv": case "html": case "subtitle": return "preview";
    default: return "save";
  }
}

/// What kind a file is, by its name.
export function kindOf(name: string): DriveKind {
  const dot = name.lastIndexOf(".");
  const ext = dot <= 0 ? "" : name.slice(dot + 1).toLowerCase();
  if (ext === "" && /^(readme|license|licence|changelog|makefile|dockerfile)$/i.test(name)) return "text";
  return EXT[ext] ?? "other";
}

