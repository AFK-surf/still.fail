// What the player reads a file of a drive through (drive/DriveSource.kt, zdrive's QuicDataSource, over the core): ranged
// reads (`drive.read`), never the whole file first. The window starts small (an MP4's index is a few KB, often at its
// end), doubles while reads run on from each other (playing: fewer, bigger reads are the throughput) up to a part of the
// core's, and drops back to small on a jump, so a seek answers in one small read. Bytes already in the window are served
// from it (the extractor hops between tracks and reopens around seeks). The player's loading thread calls it (open, read,
// close, as media3's DataSource); here each is a promise the native side waits on (Player.tsx says what is missing).
import { DRIVE_PART, type StationApi } from "../data/Calls";

const TAG = "drive-stream";

/** media3's C.LENGTH_UNSET and C.RESULT_END_OF_INPUT. */
export const LENGTH_UNSET = -1;
export const RESULT_END_OF_INPUT = -1;

/** A file of the drive as the player names it: `stillfail-drive:///<path under its root>`. */
export const DriveUri = {
  SCHEME: "stillfail-drive",
  of(path: string): string {
    return `${DriveUri.SCHEME}:///${path.split("/").map(encodeURIComponent).join("/")}`;
  },
  pathOf(uri: string): string {
    const prefix = `${DriveUri.SCHEME}:`;
    if (!uri.startsWith(prefix)) throw new Error(`not a ${DriveUri.SCHEME} uri: ${uri}`);
    // The path after the (empty) authority: `stillfail-drive:///a/b` is `/a/b`.
    const rest = uri.substring(prefix.length).replace(/^\/\/[^/]*/, "");
    const path = decodeURIComponent(rest.split(/[?#]/)[0] ?? "").replace(/^\/+|\/+$/g, "");
    if (!path) throw new Error(`${DriveUri.SCHEME} uri names no file: ${uri}`);
    return path;
  },
};

/** What the player pulled off the drive, counted where it happened. */
export class StreamStats {
  #bytes = 0;
  #reads = 0;
  #millis = 0;
  #window = 0;

  record(n: number, asked: number, ms: number): void {
    this.#bytes += n; this.#reads++; this.#millis += ms; this.#window = asked;
  }

  get bytesRead(): number { return this.#bytes; }
  get readCount(): number { return this.#reads; }
  /** Bytes per second while reading (the time spent in the reads themselves). */
  get rate(): number { return this.#millis > 0 ? (this.#bytes * 1000) / this.#millis : 0; }
  get windowBytes(): number { return this.#window; }
}

/** How many bytes one read asks for: small first, doubling while reads run on, a core's part at most. */
export const ReadWindow = {
  FIRST: 256 * 1024,
  MAX: DRIVE_PART,
  grow: (current: number) => Math.min(current * 2, DRIVE_PART),
};

/** What is asked to be opened (media3's DataSpec): which file, from where, how much (LENGTH_UNSET: to its end). */
export interface DataSpec { uri: string; position: number; length: number }

export class DriveSource {
  #uri: string | null = null;
  #path = "";
  #fileSize = -1;
  #position = 0;
  #remaining = 0;

  /** The window held: [windowStart, windowStart + windowValid). */
  #window: Uint8Array = new Uint8Array(0);
  #windowStart = 0;
  #windowValid = 0;
  #cursor = 0;
  #windowPath = "";
  #planned = ReadWindow.FIRST;
  #announced = false;

  constructor(private readonly api: StationApi, private readonly root: string, private readonly sizes: ReadonlyMap<string, number>, private readonly stats: StreamStats) {}

  async open(dataSpec: DataSpec): Promise<number> {
    this.#path = DriveUri.pathOf(dataSpec.uri);
    this.#uri = dataSpec.uri;
    if (this.#windowPath !== this.#path) { this.#windowPath = this.#path; this.#windowValid = 0; this.#fileSize = -1; }
    if (this.#fileSize < 0) this.#fileSize = this.sizes.get(this.#path) ?? -1;
    const start = dataSpec.position;
    this.#position = start;
    // A reopen inside the window is served from it (the extractor does this around every seek).
    if (start < this.#windowStart || start >= this.#windowStart + this.#windowValid) { this.#windowStart = start; this.#windowValid = 0; }
    this.#cursor = start - this.#windowStart;
    // The size not known (not in the listing): the first read says it.
    if (this.#fileSize < 0 && !(await this.#fill())) this.#fileSize = start;
    if (start > this.#fileSize) throw new Error(`${this.#path} is ${this.#fileSize} bytes, asked to open at ${start}`);
    this.#remaining = dataSpec.length === LENGTH_UNSET ? this.#fileSize - start : Math.min(dataSpec.length, this.#fileSize - start);
    this.#announced = true;
    return this.#remaining;
  }

  async read(buffer: Uint8Array, offset: number, length: number): Promise<number> {
    if (length <= 0) return 0;
    if (this.#remaining <= 0) return RESULT_END_OF_INPUT;
    if (this.#cursor >= this.#windowValid && !(await this.#fill())) return RESULT_END_OF_INPUT;
    const count = Math.min(length, this.#windowValid - this.#cursor, this.#remaining);
    buffer.set(this.#window.subarray(this.#cursor, this.#cursor + count), offset);
    this.#cursor += count;
    this.#position += count;
    this.#remaining -= count;
    return count;
  }

  get uri(): string | null { return this.#uri; }

  /** The window is kept: the extractor closes and reopens around seeks, and comes back for what is in it. */
  close(): void {
    if (this.#announced) this.#announced = false;
  }

  /** Reads the window from `position`; false at the file's end. */
  async #fill(): Promise<boolean> {
    if (this.#fileSize >= 0 && this.#fileSize <= this.#position) return false;
    const contiguous = this.#windowValid > 0 && this.#position === this.#windowStart + this.#windowValid;
    this.#planned = contiguous ? ReadWindow.grow(this.#planned) : ReadWindow.FIRST;
    const want = this.#fileSize >= 0 ? Math.min(this.#fileSize - this.#position, this.#planned) : this.#planned;
    if (want <= 0) return false;
    const began = Date.now();
    let got;
    try {
      got = await this.api.driveRead(this.root, this.#path, this.#position, want);
    } catch (e) {
      throw new Error(`reading ${this.#path} at ${this.#position} (${want} bytes): ${e instanceof Error ? e.message : String(e)}`);
    }
    const ms = Date.now() - began;
    this.#fileSize = got.total;
    if (got.bytes.length === 0) return false;
    this.#window = got.bytes;
    this.#windowStart = this.#position;
    this.#windowValid = got.bytes.length;
    this.#cursor = 0;
    this.stats.record(got.bytes.length, want, ms);
    console.info(TAG, `read ${this.#path} @${this.#position} ${got.bytes.length}B in ${ms}ms (${(ms > 0 ? got.bytes.length / 1048.576 / ms : 0).toFixed(1)} MB/s) total ${this.stats.bytesRead}B of ${this.#fileSize}`);
    return true;
  }

  static Factory = class {
    constructor(private readonly api: StationApi, private readonly root: string, private readonly sizes: ReadonlyMap<string, number>, private readonly stats: StreamStats) {}
    createDataSource(): DriveSource { return new DriveSource(this.api, this.root, this.sizes, this.stats); }
  };
}
