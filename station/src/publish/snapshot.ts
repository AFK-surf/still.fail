// A published snapshot (docs/public-share.md): what the readers make of a chat (read/publish.ts `publishDraft`), and
// the snapshot.json the share page reads, made of it with the attachments ticked.
type Json = any;

/// The snapshot's format (`v`), as the share page reads it.
export const SNAPSHOT_VERSION = 1;

/// An attachment of the snapshot: its number in it (`k`), what it is, and (for the route alone) where it is now.
export type DraftFile = { k: string; name: string; size: number; type: string; width?: number; height?: number; thumbhash?: string; n: number; path: string };

/// A chat as a snapshot would show it.
export type Draft = {
  title: string;
  upto: number;
  entries: { n: number; at: number; authorKind: string; author: string; text: string; files: string[] }[];
  /// How many things were hidden, by message (those with none left out).
  redacted: { n: number; count: number }[];
  files: DraftFile[];
};

/// What a draft's snapshot is, with the attachments `ticked` (`null`: all): the share page's snapshot.json.
export function snapshotOf(d: Draft, station: string, by: string, at: number, ticked: Set<string> | null): Json {
  const files = new Map(d.files.filter((f) => ticked === null || ticked.has(f.k)).map((f) => [f.k, f]));
  return {
    v: SNAPSHOT_VERSION,
    title: d.title,
    station,
    at,
    by,
    entries: d.entries.map((e) => ({
      n: e.n,
      at: e.at,
      authorKind: e.authorKind,
      author: e.author,
      text: e.text,
      files: e.files.flatMap((k) => {
        const f = files.get(k);
        if (f === undefined) return [];
        const { n: _n, path: _path, ...shown } = f;
        return [shown];
      }),
    })),
    redacted: d.redacted.reduce((sum, r) => sum + r.count, 0),
  };
}
