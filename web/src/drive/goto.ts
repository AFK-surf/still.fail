// A folder typed by its path on the files' page (⌘⇧G, pages/FilesGo.tsx), worked out: `mba:~/Projects` names the station
// before the colon (its name, or the start of it), `~` its home, a path with no slash in front is under the folder shown
// (another station's: under its home), and what is typed of the last part is what Tab completes.

/** A station as this needs it: its address, its name, its home (a member who browses everywhere). */
export interface Named { station: string; name: string; overview?: { drive?: { home?: string | undefined } | undefined } | undefined }

/** A child of a folder on a station (its own separator: Windows' backslash, else a slash). */
const childOf = (folder: string, name: string) => {
  const sep = folder.includes("\\") && !folder.includes("/") ? "\\" : "/";
  return folder.endsWith(sep) ? `${folder}${name}` : `${folder}${sep}${name}`;
};

/** What is typed, worked out: the station, the folder it names (absolute), and what is typed of its last part. */
export function resolveTyped(typed: string, views: readonly Named[], from: { station: string; abs: string }): { station: string; abs: string; parent: string; partial: string } | null {
  const colon = typed.indexOf(":");
  const named = colon > 0 && !/^[A-Za-z]:[\\/]/.test(typed) ? typed.slice(0, colon).trim().toLowerCase() : null;
  const s = named === null ? views.find((v) => v.station === from.station) : views.find((v) => v.name.toLowerCase() === named) ?? views.find((v) => v.name.toLowerCase().startsWith(named));
  if (!s) return null;
  const rest = (named === null ? typed : typed.slice(colon + 1)).trim();
  const home = s.overview?.drive?.home ?? null;
  const base = rest === "" || rest === "~" ? home : rest.startsWith("~/") ? (home ? childOf(home, rest.slice(2)) : null) : rest.startsWith("/") || /^[A-Za-z]:[\\/]/.test(rest) ? rest : s.station === from.station ? childOf(from.abs, rest) : home ? childOf(home, rest) : null;
  if (base === null) return null;
  const ends = /[\\/]$/.test(rest) || rest === "" || rest === "~";
  const abs = ends && base.length > 1 ? base.replace(/[\\/]+$/, "") || "/" : base;
  const cut = Math.max(abs.lastIndexOf("/"), abs.lastIndexOf("\\"));
  return { station: s.station, abs, parent: ends ? abs : cut <= 0 ? "/" : abs.slice(0, cut), partial: ends ? "" : abs.slice(cut + 1) };
}

