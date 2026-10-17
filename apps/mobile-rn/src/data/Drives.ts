// A drive's folders and files as the pages show and name them (data/Drives.kt: the drive's own, a station's page, a
// chat's files, a screen's drops). Here, below the pages, so that the pages, the drive and the screens do not depend on
// each other.
import { File } from "expo-file-system";
import type { DriveEntry, DriveRoot } from "../../../../web/src/core/shapes.ts";
import { t } from "../i18n";

/** Kotlin's compareBy over one key: by its natural order. */
const by = <T, K extends number | string | boolean>(key: (x: T) => K) => (a: T, b: T) => {
  const x = key(a);
  const y = key(b);
  return x < y ? -1 : x > y ? 1 : 0;
};

/**
 * A folder's entries as shown, as the web's (web/src/drive/order.ts): hidden ones (a name starting with `.`) left out
 * unless asked, folders first, then by name (the station's order), time or size (the newest and largest first) or kind;
 * `-down` turns it the other way.
 */
export function arranged(entries: readonly DriveEntry[], sort: string, hidden: boolean): DriveEntry[] {
  const dash = sort.indexOf("-");
  const kind = dash >= 0 ? sort.substring(0, dash) : sort;
  const down = sort.endsWith("-down");
  const shown = hidden ? [...entries] : entries.filter((it) => !it.name.startsWith("."));
  const named = new Map<string, number>();
  entries.forEach((e, i) => named.set(e.name, i));
  const byName = by<DriveEntry, number>((it) => named.get(it.name) ?? 0);
  const ext = (name: string) => { const dot = name.lastIndexOf("."); return dot >= 0 ? name.substring(dot + 1).toLowerCase() : ""; };
  const order: (a: DriveEntry, b: DriveEntry) => number =
    kind === "time" ? (a, b) => b.mtime - a.mtime || byName(a, b)
    : kind === "size" ? (a, b) => b.size - a.size || byName(a, b)
    : kind === "kind" ? (a, b) => by<DriveEntry, string>((it) => it.kind)(a, b) || by<DriveEntry, string>((it) => ext(it.name))(a, b) || byName(a, b)
    : byName;
  const turned = down ? (a: DriveEntry, b: DriveEntry) => order(b, a) : order;
  // Array.prototype.sort is stable, as Kotlin's sortedWith.
  return shown.sort((a, b) => by<DriveEntry, boolean>((it) => !it.dir)(a, b) || turned(a, b));
}

/** What the station page's row says of a drive: how many folders it lends, or that it lends none. */
export function driveValue(roots: readonly DriveRoot[]): string {
  return roots.length === 0 ? t("android-misc.drive.row.none") : t("android-misc.drive.roots.count", { n: roots.length });
}

/** A name not among `taken`: "name (1).ext", "name (2).ext"… */
export function freeName(name: string, taken: ReadonlySet<string>): string {
  if (!taken.has(name)) return name;
  const found = name.lastIndexOf(".");
  const dot = found > 0 ? found : name.length;
  const stem = name.substring(0, dot);
  const ext = name.substring(dot);
  let n = 1;
  while (taken.has(`${stem} (${n})${ext}`)) n++;
  return `${stem} (${n})${ext}`;
}

/** A picked document's name and size, as its provider says (-1 when it does not). */
export function picked(uri: string): [string, number] {
  const last = decodeURIComponent(uri.split("/").filter(Boolean).at(-1) ?? "");
  let name = last.substring(last.lastIndexOf("/") + 1) || "file";
  let size = -1;
  try {
    const file = new File(uri);
    if (file.name) name = file.name;
    if (file.exists) size = file.size;
  } catch {
    // A provider that says nothing: the name from its address, the size not known.
  }
  return [name, size];
}
