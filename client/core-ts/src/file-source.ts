/** A selected file read in parts by the core; its host owns the bytes until the upload ends. */
export class FileSource {
  readonly size: number;
  readonly type: string;
  #read: (start: number, end: number) => Promise<ArrayBuffer>;
  #release: () => void;
  constructor(size: number, type: string, read: (start: number, end: number) => Promise<ArrayBuffer>, release: () => void) {
    this.size = size; this.type = type; this.#read = read; this.#release = release;
  }
  slice(start: number, end: number): { arrayBuffer(): Promise<ArrayBuffer> } {
    return { arrayBuffer: () => this.#read(start, Math.min(end, this.size)) };
  }
  close(): void { this.#release(); }
}

