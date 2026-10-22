/** A page's Blob: false wherever there is none (Hermes on Android, whose picked files are FileSources). */
export function isBlob(v: unknown): v is Blob {
  const B = (globalThis as { Blob?: typeof Blob }).Blob;
  return typeof B === "function" && v instanceof B;
}

/** A selected file read in parts by the core; its host owns the bytes until the upload ends. */
export class FileSource {
  readonly size: number;
  readonly type: string;
  /** Its content's SHA-256 (hex), where its host names it itself (a phone's, read there at its own speed). */
  readonly hash: (() => Promise<string | null>) | undefined;
  #read: (start: number, end: number) => Promise<ArrayBuffer>;
  #release: () => void;
  constructor(size: number, type: string, read: (start: number, end: number) => Promise<ArrayBuffer>, release: () => void, hash?: () => Promise<string | null>) {
    this.size = size; this.type = type; this.#read = read; this.#release = release; this.hash = hash;
  }
  slice(start: number, end: number): { arrayBuffer(): Promise<ArrayBuffer> } {
    return { arrayBuffer: () => this.#read(start, Math.min(end, this.size)) };
  }
  close(): void { this.#release(); }
}

