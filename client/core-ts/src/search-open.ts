// Where something a search found opens (`SearchItem.open`, views/search.ts), as every client has a page for it. Reads
// nothing but the thing found, so the web's demo says it as the core does.
// deno-lint-ignore no-explicit-any
type J = any;
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);

/// What opens a file found by its kind (as a drive's entry is opened): its folder entered, a text read, a video or song
/// played; anything else shown in its folder.
const OPENER: Record<string, "folder" | "read" | "play"> = { folder: "folder", text: "read", markdown: "read", video: "play", audio: "play" };

/// Where a thing found opens (`SearchItem.open`), as every client has a page for it: a service its chat with its page
/// over it, a task its chat with it picked, anything else in a chat that chat; a station its page; a member the
/// workspace's members; a file its place in its station's files (under the folder a read-only member's workspace
/// pinned, `root`, when found there, else from its own folder). Null when it opens nowhere (no chat, no path).
export function openOf(item: J): J | null {
  const station = String(item.station ?? "");
  const chat = str(item.chat);
  switch (item.kind) {
    case "job": {
      if (chat === null) return null;
      const job = str(item.job);
      if (job === null) return { to: "chat", station, chat };
      return { to: num(item.port) !== null ? "service" : "task", station, chat, job };
    }
    case "station":
      return { to: "station", station };
    case "member":
      return { to: "members", station };
    case "file": {
      const path = str(item.path);
      if (path === null) return null;
      const cut = Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\"));
      const [folder, name] = cut > 0 ? [path.slice(0, cut), path.slice(cut + 1)] : [path, ""];
      const pinned = str(item.root);
      const dir = item.dir === true;
      const root = pinned ?? (dir ? path : folder);
      const rel = pinned !== null ? (str(item.rel) ?? "") : dir ? "" : name;
      const how = dir ? "folder" : OPENER[String(item.fileKind ?? "other")];
      if (how === "read" || how === "play") return { to: "files", station, root, path: rel, how };
      return { to: "files", station, root, path: how === "folder" ? rel : rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "" };
    }
    default:
      return chat === null ? null : { to: "chat", station, chat };
  }
}
