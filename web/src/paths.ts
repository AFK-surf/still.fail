// Which bits of a message name a file on the station by its path (Peeks.tsx draws them as chips).

const CODE_EXT = /\.(?:[cm]?[jt]sx?|json|md|mdx|rs|py|go|kt|kts|swift|java|rb|php|c|cc|cpp|h|hpp|cs|css|scss|html|vue|svelte|ya?ml|toml|ini|sh|zsh|sql|txt|log|csv|xml|svg|png|jpe?g|gif|webp|pdf|lock|gradle|plist|env)$/i;
/** Where an absolute path without an extension is still surely one of the machine's (not a page's route like /admin/api). */
const ROOTS = /^\/(?:Users|Volumes|home|tmp|private|opt|var|etc|srv|mnt|workspace|root)\//;

/**
 * The file (or directory) a bit of inline code names, with the line it points at (`src/a.ts:12`, `a.ts:12:4`,
 * `a.ts#L12`); null when it is not a path. Paths only: absolute ones under the machine's roots or with a file's
 * extension, `~/…`, `./…`, `../…`, or relative ones with a directory and an extension; a bare name with a code file's
 * extension (`Sidebar.tsx`), which is read under the session's working directory.
 */
export function pathIn(code: string): { path: string; line: number | null } | null {
  const text = code.trim();
  if (text === "" || text.length > 400 || /\s|:\/\/|[*?<>|$`'"{}()[\]=,;]/.test(text)) return null;
  const m = /^(.*?)(?::(\d+)(?::\d+)?|#L(\d+)(?:-L?\d+)?)?$/.exec(text)!;
  const path = m[1]!;
  const line = m[2] ?? m[3];
  // `~/.stillfail/agent/...`, `src/…`: a place left out, not a file.
  if (path === "" || path.includes(":") || /(?:^|\/)(?:\.{3,}|…)$/.test(path) || path.includes("…")) return null;
  const last = path.replace(/\/$/, "").split("/").at(-1) ?? "";
  const ext = /\.[A-Za-z0-9]{1,10}$/.test(last) && !/^\.+$/.test(last);
  const ok =
    path.startsWith("~/") || path.startsWith("./") || path.startsWith("../")
      ? path.length > 2
      : path.startsWith("/")
        ? path.split("/").filter(Boolean).length >= 2 && (ext || ROOTS.test(path))
        : path.includes("/")
          ? /^[\w@.-]/.test(path) && (ext || path.endsWith("/")) && !/^\d+(?:\.\d+)*\//.test(path)
          // A bare name: a code file's (not a library's name, as node.js, Vue.js).
          : CODE_EXT.test(last) && !/^\d/.test(last) && !/^[A-Za-z]+\.js$/.test(last);
  return ok ? { path, line: line ? Number(line) : null } : null;
}
