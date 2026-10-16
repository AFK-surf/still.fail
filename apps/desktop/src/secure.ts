// What the core keeps sealed (client/core-ts host.ts `secureGet`; docs/vault.md, "设备上的钥匙"), in the main process:
// Electron's safeStorage is the main process's, so the core's utility process asks here (core.ts `sealer`). A value is
// a file of its own in `dir`, sealed by safeStorage (its key in the macOS keychain; Windows' DPAPI; on Linux the
// secret service, and none when there is only its plain-text fallback: `canSeal`). One kept with `user: true` is read
// only after `ask` (Touch ID on a Mac that has it); where nothing can ask (Windows, Linux, a Mac without Touch ID) it is
// as safe as the system's login, no more.
//
// A file: "SFS1", a byte for `user` (1 or 0), then safeStorage's sealing of "<user>:<the value in base64url>". `user`
// is in the sealed part too, so a file whose outer byte was changed to skip the prompt does not open.
import { mkdir, open, readFile, rename, rm } from "node:fs/promises";
import { join } from "node:path";

/// safeStorage, or a test's stand-in.
export interface Seal {
  encryptString(text: string): Buffer;
  decryptString(sealed: Buffer): string;
}

/// Asks the person (Touch ID): resolves once they said yes, rejects when they did not. Null: nothing can ask here.
export type Ask = ((reason: string) => Promise<void>) | null;

const MAGIC = Buffer.from("SFS1", "ascii");

/// A value as its file holds it.
export function sealBlob(seal: Seal, value: Uint8Array, user: boolean): Buffer {
  const flag = user ? 1 : 0;
  return Buffer.concat([MAGIC, Buffer.from([flag]), seal.encryptString(`${flag}:${Buffer.from(value).toString("base64url")}`)]);
}

/// Whether a file's value needs the person (read before it is opened, to ask first); null when it is no such file.
export function blobUser(blob: Buffer): boolean | null {
  if (blob.length < MAGIC.length + 1 || !blob.subarray(0, MAGIC.length).equals(MAGIC)) return null;
  const flag = blob[MAGIC.length];
  return flag === 1 ? true : flag === 0 ? false : null;
}

/// A file's value, opened; it fails when it is no such file or its two `user` differ.
export function openBlob(seal: Seal, blob: Buffer): { value: Uint8Array; user: boolean } {
  const user = blobUser(blob);
  if (user === null) throw new Error("not a sealed value");
  const text = seal.decryptString(blob.subarray(MAGIC.length + 1));
  const at = text.indexOf(":");
  if (text.slice(0, at) !== (user ? "1" : "0")) throw new Error("a sealed value whose `user` was changed");
  return { value: new Uint8Array(Buffer.from(text.slice(at + 1), "base64url")), user };
}

/// A key as a file name: letters, digits, `-` and `_` as they are, the rest `%XX`.
export const fileName = (key: string) => Array.from(Buffer.from(key, "utf8"), (b) => (/[A-Za-z0-9_-]/.test(String.fromCharCode(b)) ? String.fromCharCode(b) : `%${b.toString(16).toUpperCase().padStart(2, "0")}`)).join("");

export class SealedFiles {
  readonly #dir: string;
  readonly #seal: Seal;
  readonly #ask: Ask;
  /// One prompt at a time.
  #asking: Promise<unknown> = Promise.resolve();

  constructor(dir: string, seal: Seal, ask: Ask) {
    this.#dir = dir;
    this.#seal = seal;
    this.#ask = ask;
  }

  #path(key: string): string {
    return join(this.#dir, fileName(key));
  }

  /// The value kept under `key`, or null; one kept with `user` only after the person said yes.
  async get(key: string, user: boolean, reason: string): Promise<Uint8Array | null> {
    let blob: Buffer;
    try {
      blob = await readFile(this.#path(key));
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === "ENOENT") return null;
      throw e;
    }
    const kept = blobUser(blob);
    if (kept === null) throw new Error(`${key}: not a sealed value`);
    if (kept !== user) throw new Error(`${key}: kept with user: ${kept}, asked with user: ${user}`);
    const ask = this.#ask;
    if (kept && ask) {
      const turn = this.#asking.then(() => ask(reason));
      this.#asking = turn.catch(() => {});
      await turn;
    }
    return openBlob(this.#seal, blob).value;
  }

  /// Kept sealed: written aside and renamed over, so a crash leaves the old value or the new one.
  async set(key: string, value: Uint8Array, user: boolean): Promise<void> {
    await mkdir(this.#dir, { recursive: true, mode: 0o700 });
    const path = this.#path(key);
    const partial = `${path}.partial`;
    const file = await open(partial, "w", 0o600);
    try {
      await file.writeFile(sealBlob(this.#seal, value, user));
      await file.sync();
    } finally {
      await file.close();
    }
    await rename(partial, path);
  }

  async delete(key: string): Promise<void> {
    await rm(this.#path(key), { force: true });
  }
}
