// What a viewer (Reader.tsx, Player.tsx) opens: a file as the page has it. One of a station's drive (the app's
// web/src/drive/viewerFile.ts: read a part at a time, streamed, where it was left kept), or one here already (`blob`:
// a chat's file a preview has fetched, blobFile).

/** How much of it has come. */
export interface Got { loaded: number; total: number }

/** Where it was left: a text's offset, a video's time in ms (`at`), of how much (`of`). */
export interface Place { at: number; of?: number | undefined }

/** A file beside it in its folder, as the folder lists it (a playlist's others, a video's subtitle). */
export interface ViewerEntry {
  name: string;
  size: number;
  mtime: number;
  /** Its media type (empty: not known). */
  type: string;
  /** What it is, as the station says: "video", "audio", "text", "markdown"… */
  kind: string;
  dir: boolean;
}

export interface ViewerFile {
  name: string;
  size: number;
  mtime: number;
  type: string;
  kind: string;
  /** Where it is, said on hover over its name (its path). */
  title?: string | undefined;
  /** Who it is while unchanged, to keep what was read of it (none: not kept). */
  key?: string | undefined;
  /** The bytes, here already: shown from them, not read. */
  blob?: Blob | undefined;
  /** Read whole (at most `max`), its progress told. */
  read(opts: { max?: number; type?: string; onProgress?: (got: Got) => void }): Promise<Blob>;
  /** A URL to play it from as it comes (none: read whole instead); `ahead` says how far reading is welcome. */
  stream?: ((type: string, ahead: () => number | null) => Promise<{ url: string; close: () => void } | null>) | undefined;
  /** A file beside it read (a subtitle). */
  beside?: ((entry: ViewerEntry, type: string) => Promise<Blob>) | undefined;
  /** Where it was left on this device: undefined while not known, null before it was opened (a hook). */
  usePlace(): Place | null | undefined;
  /** Where it is left now. */
  keepPlace(at: number, of?: number): void;
  /** Saved to the device. */
  save(): void;
}

/** A file here already (a chat's, fetched by its preview): nothing kept of where it was left. */
export function blobFile(blob: Blob, file: { name: string; size: number; type?: string; kind?: string }, save: () => void): ViewerFile {
  return {
    name: file.name, size: file.size, mtime: 0, type: file.type ?? blob.type, kind: file.kind ?? "", blob,
    read: async ({ max }) => (max !== undefined ? blob.slice(0, max) : blob),
    usePlace: () => null,
    keepPlace: () => undefined,
    save,
  };
}
