// Observe adb's unencrypted transport (the phone's own adb session, docs/adb-share.md) without keeping its contents.
// A station's adb server holds one connection while many commands run over it. A connection or its CNXN is not use:
// OPEN starts a service; WRTE/OKAY on that service show a long-running one still in use. The two services the station
// opens itself to keep lending enabled are excluded. An older phone's STLS makes the rest opaque, so stop observing.

const OPEN = 0x4e45504f;
const WRTE = 0x45545257;
const OKAY = 0x59414b4f;
const CLSE = 0x45534c43;
const STLS = 0x534c5453;
const HEADER = 24;
const MAX_PAYLOAD = 16 * 1024 * 1024;
const MAX_SERVICE = 8192;

// Mark our own maintenance so the same command run by an agent still counts as use.
export const KEEP_LENDING = "STILLFAIL_ADB_KEEP=1";

export class AdbActivity {
  readonly #package: string;
  readonly #used: (force: boolean) => void;
  readonly #header = Buffer.alloc(HEADER);
  readonly #active = new Set<number>();
  #headerBytes = 0;
  #remaining = 0;
  #service: Buffer | null = null;
  #serviceBytes = 0;
  #serviceId = 0;
  #opaque = false;

  constructor(packageName: string, used: (force: boolean) => void) {
    this.#package = packageName;
    this.#used = used;
  }

  /// The bytes sent by this grant's adb server. They are passed through unchanged by the caller.
  take(bytes: Buffer): void {
    let at = 0;
    while (at < bytes.length && !this.#opaque) {
      if (this.#remaining > 0) {
        const n = Math.min(this.#remaining, bytes.length - at);
        if (this.#service !== null) {
          bytes.copy(this.#service, this.#serviceBytes, at, at + n);
          this.#serviceBytes += n;
        }
        this.#remaining -= n;
        at += n;
        if (this.#remaining === 0) this.#opened();
        continue;
      }
      const n = Math.min(HEADER - this.#headerBytes, bytes.length - at);
      bytes.copy(this.#header, this.#headerBytes, at, at + n);
      this.#headerBytes += n;
      at += n;
      if (this.#headerBytes < HEADER) continue;
      this.#headerBytes = 0;
      const command = this.#header.readUInt32LE(0);
      const id = this.#header.readUInt32LE(4);
      const size = this.#header.readUInt32LE(12);
      if (this.#header.readUInt32LE(20) !== (~command >>> 0) || size > MAX_PAYLOAD || command === STLS) {
        this.#opaque = true;
        continue;
      }
      this.#remaining = size;
      if (command === OPEN) {
        this.#serviceId = id;
        this.#serviceBytes = 0;
        if (size <= MAX_SERVICE) this.#service = Buffer.alloc(size);
        else {
          // An unusually long service cannot be either of our two maintenance commands.
          this.#active.add(id);
          this.#used(true);
        }
        if (size === 0) this.#opened();
      } else if (this.#active.has(id)) {
        if (command === CLSE) {
          this.#active.delete(id);
          this.#used(true);
        } else if (command === WRTE || command === OKAY) this.#used(false);
      }
    }
  }

  #opened(): void {
    if (this.#service === null) return;
    const service = this.#service.toString("utf8").replace(/\0+$/, "");
    this.#service = null;
    const command = /^shell(?:,[^:]*)?:(.*)$/.exec(service)?.[1];
    const ours = this.#package !== "" && (command === `${KEEP_LENDING} pm grant ${this.#package} android.permission.WRITE_SECURE_SETTINGS` || command === `${KEEP_LENDING} cmd deviceidle whitelist +${this.#package}`);
    if (ours) return;
    this.#active.add(this.#serviceId);
    this.#used(true);
  }
}
