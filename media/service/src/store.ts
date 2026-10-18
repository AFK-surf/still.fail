// media.db (node:sqlite, WAL): the books of each workspace with their chapters and images, and each account's reading
// place and notes; the station's photo library (its items, its folders). Its own schema version (`user_version`), moved forward by MIGRATIONS in order; a database newer
// than this service is refused.
import { DatabaseSync } from "node:sqlite";
import { type Parsed, type TocEntry, chapterChars } from "./blocks.ts";

/// One step each; the database's user_version is how many have run.
const MIGRATIONS = [
  `
CREATE TABLE books (
  id TEXT PRIMARY KEY,
  workspace TEXT NOT NULL,
  title TEXT NOT NULL,
  author TEXT NOT NULL,
  format TEXT NOT NULL,
  root TEXT NOT NULL,
  path TEXT NOT NULL,
  size INTEGER NOT NULL,
  mtime INTEGER NOT NULL,
  added INTEGER NOT NULL,
  cover TEXT,
  toc TEXT NOT NULL,
  UNIQUE (workspace, root, path)
);
CREATE TABLE chapters (
  book TEXT NOT NULL REFERENCES books (id) ON DELETE CASCADE,
  idx INTEGER NOT NULL,
  title TEXT NOT NULL,
  chars INTEGER NOT NULL,
  blocks TEXT NOT NULL,
  PRIMARY KEY (book, idx)
);
CREATE TABLE images (
  book TEXT NOT NULL REFERENCES books (id) ON DELETE CASCADE,
  ref TEXT NOT NULL,
  type TEXT NOT NULL,
  bytes BLOB NOT NULL,
  PRIMARY KEY (book, ref)
);
CREATE TABLE places (
  book TEXT NOT NULL REFERENCES books (id) ON DELETE CASCADE,
  sub TEXT NOT NULL,
  chapter INTEGER NOT NULL,
  pos INTEGER NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (book, sub)
);
CREATE INDEX places_sub ON places (sub);
CREATE TABLE notes (
  book TEXT NOT NULL REFERENCES books (id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  sub TEXT NOT NULL,
  chapter INTEGER NOT NULL,
  start INTEGER NOT NULL,
  stop INTEGER NOT NULL,
  text TEXT NOT NULL,
  note TEXT,
  color TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (book, id)
);
`,
  `
CREATE TABLE photo_items (
  id TEXT PRIMARY KEY,
  root TEXT NOT NULL,
  path TEXT NOT NULL,
  dir TEXT NOT NULL,
  album TEXT NOT NULL,
  kind TEXT NOT NULL,
  size INTEGER NOT NULL,
  mtime INTEGER NOT NULL,
  taken INTEGER NOT NULL,
  day TEXT NOT NULL,
  w INTEGER,
  h INTEGER,
  duration REAL,
  camera TEXT,
  lens TEXT,
  lat REAL,
  lon REAL,
  thumbhash TEXT,
  sha256 TEXT,
  seen INTEGER NOT NULL
);
CREATE INDEX photo_items_day ON photo_items (day, taken);
CREATE INDEX photo_items_album ON photo_items (album, taken);
CREATE INDEX photo_items_dir ON photo_items (root, dir);
CREATE INDEX photo_items_sha256 ON photo_items (sha256) WHERE sha256 IS NOT NULL;
CREATE INDEX photo_items_unhashed ON photo_items (taken) WHERE thumbhash IS NULL;
CREATE TABLE photo_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
`,
];

export type BookRow = { id: string; workspace: string; title: string; author: string; format: string; root: string; path: string; size: number; mtime: number; added: number; cover: string | null; toc: TocEntry[] };
export type Place = { chapter: number; offset: number; at: number };
export type Note = { id: string; chapter: number; start: number; end: number; text: string; note?: string; color: string; at: number };

type Row = Record<string, unknown>;

const bookOf = (r: Row): BookRow => ({ ...(r as Omit<BookRow, "toc">), toc: JSON.parse(r.toc as string) as TocEntry[] });
const placeOf = (r: Row): Place => ({ chapter: r.chapter as number, offset: r.pos as number, at: r.at as number });
const noteOf = (r: Row): Note => ({
  id: r.id as string,
  chapter: r.chapter as number,
  start: r.start as number,
  end: r.stop as number,
  text: r.text as string,
  ...(r.note !== null ? { note: r.note as string } : {}),
  color: r.color as string,
  at: r.at as number,
});

/// A photo or video of the library: where it is (`dir` is its folder's path under `root`), which album (`album`: the
/// library folder's id, or "backup"), what it says of itself. `thumbhash` null until its thumbnail was made ("" when
/// none could be); `sha256` known for what was uploaded; `seen` the pass that last found it.
export type PhotoRow = {
  id: string;
  root: string;
  path: string;
  dir: string;
  album: string;
  kind: "photo" | "video";
  size: number;
  mtime: number;
  taken: number;
  day: string;
  w: number | null;
  h: number | null;
  duration: number | null;
  camera: string | null;
  lens: string | null;
  lat: number | null;
  lon: number | null;
  thumbhash: string | null;
  sha256: string | null;
  seen: number;
};

const PHOTO_COLUMNS = ["id", "root", "path", "dir", "album", "kind", "size", "mtime", "taken", "day", "w", "h", "duration", "camera", "lens", "lat", "lon", "thumbhash", "sha256", "seen"] as const;

export type Store = ReturnType<typeof openStore>;

export function openStore(file: string) {
  const db = new DatabaseSync(file);
  db.exec("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;");
  const version = (db.prepare("PRAGMA user_version").get() as { user_version: number }).user_version;
  if (version > MIGRATIONS.length) throw new Error(`media.db is at version ${version}, newer than this service (${MIGRATIONS.length})`);
  for (let v = version; v < MIGRATIONS.length; v++) {
    db.exec("BEGIN IMMEDIATE");
    try {
      db.exec(MIGRATIONS[v]!);
      db.exec(`PRAGMA user_version = ${v + 1}`);
      db.exec("COMMIT");
    } catch (e) {
      db.exec("ROLLBACK");
      throw e;
    }
  }

  const tx = <T>(f: () => T): T => {
    db.exec("BEGIN IMMEDIATE");
    try {
      const out = f();
      db.exec("COMMIT");
      return out;
    } catch (e) {
      db.exec("ROLLBACK");
      throw e;
    }
  };

  const q = {
    byPath: db.prepare("SELECT id, size, mtime FROM books WHERE workspace = ? AND root = ? AND path = ?"),
    insertBook: db.prepare("INSERT INTO books (id, workspace, title, author, format, root, path, size, mtime, added, cover, toc) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"),
    updateBook: db.prepare("UPDATE books SET title = ?, author = ?, format = ?, size = ?, mtime = ?, cover = ?, toc = ? WHERE id = ?"),
    clearChapters: db.prepare("DELETE FROM chapters WHERE book = ?"),
    clearImages: db.prepare("DELETE FROM images WHERE book = ?"),
    insertChapter: db.prepare("INSERT INTO chapters (book, idx, title, chars, blocks) VALUES (?, ?, ?, ?, ?)"),
    insertImage: db.prepare("INSERT INTO images (book, ref, type, bytes) VALUES (?, ?, ?, ?)"),
    books: db.prepare("SELECT * FROM books WHERE workspace = ? ORDER BY added DESC, id"),
    book: db.prepare("SELECT * FROM books WHERE workspace = ? AND id = ?"),
    chapter: db.prepare("SELECT chars, blocks FROM chapters WHERE book = ? AND idx = ?"),
    image: db.prepare("SELECT type, bytes FROM images WHERE book = ? AND ref = ?"),
    remove: db.prepare("DELETE FROM books WHERE workspace = ? AND id = ?"),
    places: db.prepare("SELECT p.book, p.chapter, p.pos, p.at FROM places p JOIN books b ON b.id = p.book WHERE p.sub = ? AND b.workspace = ?"),
    place: db.prepare("SELECT chapter, pos, at FROM places WHERE book = ? AND sub = ?"),
    setPlace: db.prepare(
      "INSERT INTO places (book, sub, chapter, pos, at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (book, sub) DO UPDATE SET chapter = excluded.chapter, pos = excluded.pos, at = excluded.at WHERE excluded.at > places.at",
    ),
    notes: db.prepare("SELECT * FROM notes WHERE book = ? AND sub = ? ORDER BY chapter, start, at, id"),
    note: db.prepare("SELECT * FROM notes WHERE book = ? AND id = ?"),
    putNote: db.prepare(
      "INSERT INTO notes (book, id, sub, chapter, start, stop, text, note, color, at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (book, id) DO UPDATE SET chapter = excluded.chapter, start = excluded.start, stop = excluded.stop, text = excluded.text, note = excluded.note, color = excluded.color, at = excluded.at WHERE excluded.at > notes.at AND notes.sub = excluded.sub",
    ),
    removeNote: db.prepare("DELETE FROM notes WHERE book = ? AND id = ? AND sub = ?"),
    setting: db.prepare("SELECT value FROM photo_settings WHERE key = ?"),
    setSetting: db.prepare("INSERT INTO photo_settings (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value"),
    photo: db.prepare("SELECT * FROM photo_items WHERE id = ?"),
    putPhoto: db.prepare(`INSERT OR REPLACE INTO photo_items (${PHOTO_COLUMNS.join(", ")}) VALUES (${PHOTO_COLUMNS.map(() => "?").join(", ")})`),
    seePhoto: db.prepare("UPDATE photo_items SET seen = ?, album = ? WHERE id = ?"),
    removePhoto: db.prepare("DELETE FROM photo_items WHERE id = ?"),
    photosOfRoot: db.prepare("SELECT id, path, dir, album, seen FROM photo_items WHERE root = ?"),
    photosUnder: db.prepare("SELECT id, path, dir, album, seen FROM photo_items WHERE root = ? AND (dir = ? OR substr(dir, 1, length(?)) = ?)"),
    photosOfAlbum: db.prepare("SELECT id, path, dir, album, seen FROM photo_items WHERE album = ?"),
    newestDay: db.prepare("SELECT max(day) AS day FROM photo_items"),
    hasDay: db.prepare("SELECT 1 AS one FROM photo_items WHERE day = ? LIMIT 1"),
    daysOlder: db.prepare("SELECT DISTINCT day FROM photo_items WHERE day < ? ORDER BY day DESC LIMIT ?"),
    daysNewer: db.prepare("SELECT DISTINCT day FROM photo_items WHERE day > ? ORDER BY day ASC LIMIT ?"),
    photosOn: db.prepare("SELECT * FROM photo_items WHERE day = ? ORDER BY taken DESC, id"),
    albums: db.prepare("SELECT album, count(*) AS count FROM photo_items GROUP BY album"),
    cover: db.prepare("SELECT id FROM photo_items WHERE album = ? ORDER BY taken DESC, id LIMIT 1"),
    byHash: db.prepare("SELECT id FROM photo_items WHERE sha256 = ? ORDER BY id LIMIT 1"),
    unhashed: db.prepare("SELECT * FROM photo_items WHERE thumbhash IS NULL ORDER BY taken DESC LIMIT ?"),
    setThumbhash: db.prepare("UPDATE photo_items SET thumbhash = ? WHERE id = ? AND mtime = ? AND size = ?"),
  };
  const photoOf = (r: Row): PhotoRow => r as PhotoRow;
  type Placed = { id: string; path: string; dir: string; album: string; seen: number };

  return {
    /// The book at `root`/`path` in the workspace, if it was imported.
    bookAt(workspace: string, root: string, path: string): { id: string; size: number; mtime: number } | undefined {
      return q.byPath.get(workspace, root, path) as { id: string; size: number; mtime: number } | undefined;
    },

    /// Keeps a parsed book: new under `id`, or in place of what `id` had (its chapters and images; places and notes
    /// stay). Answers its table of contents.
    saveBook(b: { id: string; workspace: string; root: string; path: string; size: number; mtime: number; added: number; parsed: Parsed }, replace: boolean): TocEntry[] {
      const p = b.parsed;
      const chapters = p.chapters.map((c, index) => ({ ...c, index, chars: chapterChars(c.blocks) }));
      const toc: TocEntry[] = chapters.map((c) => ({ index: c.index, title: c.title, level: c.level, chars: c.chars }));
      tx(() => {
        if (replace) {
          q.updateBook.run(p.title, p.author, p.format, b.size, b.mtime, p.cover, JSON.stringify(toc), b.id);
          q.clearChapters.run(b.id);
          q.clearImages.run(b.id);
        } else {
          q.insertBook.run(b.id, b.workspace, p.title, p.author, p.format, b.root, b.path, b.size, b.mtime, b.added, p.cover, JSON.stringify(toc));
        }
        for (const c of chapters) q.insertChapter.run(b.id, c.index, c.title, c.chars, JSON.stringify(c.blocks));
        for (const [ref, img] of p.images) q.insertImage.run(b.id, ref, img.type, img.bytes);
      });
      return toc;
    },

    books(workspace: string): BookRow[] {
      return (q.books.all(workspace) as Row[]).map(bookOf);
    },

    book(workspace: string, id: string): BookRow | undefined {
      const r = q.book.get(workspace, id) as Row | undefined;
      return r ? bookOf(r) : undefined;
    },

    /// A chapter: its chars, and its blocks as the JSON kept (sent as it is).
    chapter(book: string, index: number): { chars: number; blocks: string } | undefined {
      return q.chapter.get(book, index) as { chars: number; blocks: string } | undefined;
    },

    image(book: string, ref: string): { type: string; bytes: Uint8Array } | undefined {
      return q.image.get(book, ref) as { type: string; bytes: Uint8Array } | undefined;
    },

    removeBook(workspace: string, id: string): boolean {
      return Number(q.remove.run(workspace, id).changes) > 0;
    },

    /// The account's places in the workspace's books, by book.
    places(sub: string, workspace: string): Map<string, Place> {
      return new Map((q.places.all(sub, workspace) as Row[]).map((r) => [r.book as string, placeOf(r)]));
    },

    place(book: string, sub: string): Place | null {
      const r = q.place.get(book, sub) as Row | undefined;
      return r ? placeOf(r) : null;
    },

    /// Keeps `p` unless the place kept is as new or newer. Answers the place kept, and whether it is `p`.
    setPlace(book: string, sub: string, p: Place): { place: Place; changed: boolean } {
      const changed = Number(q.setPlace.run(book, sub, p.chapter, p.offset, p.at).changes) > 0;
      return { place: this.place(book, sub)!, changed };
    },

    notes(book: string, sub: string): Note[] {
      return (q.notes.all(book, sub) as Row[]).map(noteOf);
    },

    /// Keeps a note of the account's: new, or over its own older one. `mine: false` when the id is another's note.
    putNote(book: string, sub: string, n: Note): { mine: boolean; note: Note; changed: boolean } {
      const owner = q.note.get(book, n.id) as Row | undefined;
      if (owner && owner.sub !== sub) return { mine: false, note: n, changed: false };
      const changed = Number(q.putNote.run(book, n.id, sub, n.chapter, n.start, n.end, n.text, n.note ?? null, n.color, n.at).changes) > 0;
      return { mine: true, note: noteOf(q.note.get(book, n.id) as Row), changed };
    },

    /// Removes a note of the account's: `missing` when there is none by that id, `theirs` when it is another's.
    removeNote(book: string, sub: string, id: string): "removed" | "missing" | "theirs" {
      const owner = q.note.get(book, id) as Row | undefined;
      if (!owner) return "missing";
      if (owner.sub !== sub) return "theirs";
      q.removeNote.run(book, id, sub);
      return "removed";
    },

    /// A photo library setting (JSON or a header, as kept).
    photoSetting(key: string): string | undefined {
      return (q.setting.get(key) as { value: string } | undefined)?.value;
    },

    setPhotoSetting(key: string, value: string) {
      q.setSetting.run(key, value);
    },

    photo(id: string): PhotoRow | undefined {
      const r = q.photo.get(id) as Row | undefined;
      return r ? photoOf(r) : undefined;
    },

    putPhoto(p: PhotoRow) {
      q.putPhoto.run(...PHOTO_COLUMNS.map((c) => p[c]));
    },

    /// Found again by the pass `seen`, in `album`.
    seePhoto(id: string, seen: number, album: string) {
      q.seePhoto.run(seen, album, id);
    },

    removePhotos(ids: string[]) {
      if (ids.length > 0) tx(() => ids.forEach((id) => q.removePhoto.run(id)));
    },

    /// What the library has in the folder `dir` of `root` and below ("": all of the root).
    photosUnder(root: string, dir: string): Placed[] {
      return (dir === "" ? q.photosOfRoot.all(root) : q.photosUnder.all(root, dir, `${dir}/`, `${dir}/`)) as Placed[];
    },

    photosOfAlbum(album: string): Placed[] {
      return q.photosOfAlbum.all(album) as Placed[];
    },

    newestDay(): string | null {
      return (q.newestDay.get() as { day: string | null }).day;
    },

    hasDay(day: string): boolean {
      return q.hasDay.get(day) !== undefined;
    },

    /// Up to `n` days with photos before `day` (newest first), or after it (oldest first).
    days(day: string, n: number, older: boolean): string[] {
      return ((older ? q.daysOlder : q.daysNewer).all(day, n) as { day: string }[]).map((r) => r.day);
    },

    photosOn(day: string): PhotoRow[] {
      return (q.photosOn.all(day) as Row[]).map(photoOf);
    },

    /// Each album's count and newest item.
    photoAlbums(): { album: string; count: number; cover: string }[] {
      return (q.albums.all() as { album: string; count: number }[]).map((a) => ({ ...a, cover: (q.cover.get(a.album) as { id: string }).id }));
    },

    photoByHash(sha256: string): string | undefined {
      return (q.byHash.get(sha256) as { id: string } | undefined)?.id;
    },

    /// Up to `n` of the photos whose thumbnail was not made yet, newest first.
    unhashed(n: number): PhotoRow[] {
      return (q.unhashed.all(n) as Row[]).map(photoOf);
    },

    /// The ThumbHash of the item as it was (`mtime`, `size`) when its thumbnail was made; "" when none could be.
    setThumbhash(id: string, hash: string, mtime: number, size: number): boolean {
      return Number(q.setThumbhash.run(hash, id, mtime, size).changes) > 0;
    },

    close() {
      db.close();
    },
  };
}
