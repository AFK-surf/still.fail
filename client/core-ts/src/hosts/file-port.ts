import { FileSource } from "../file-source.ts";
// Electron's renderer and Node utility process cannot share a browser Blob. Keep it in the page and read only
// the part the uploader asks for over their MessagePort. These messages never go through the JSON core protocol.
type Send = (message: unknown) => void;
type Message = Record<string, any>;
const object = (value: unknown): value is Message => typeof value === "object" && value !== null;
export const FILE_PART = 4 * 1024 * 1024;

export class PageFiles {
  #files = new Map<number, Blob>();
  #next = 0;
  #send: Send;
  constructor(send: Send) { this.#send = send; }
  prepare(message: unknown): unknown {
    if (!object(message) || message.call !== "composer.add" || !Array.isArray(message.params?.files)) return message;
    return { ...message, params: { ...message.params, files: message.params.files.map((file: Message) => {
      if (!object(file) || !(file.blob instanceof Blob)) return file;
      const id = ++this.#next;
      this.#files.set(id, file.blob);
      return { ...file, blob: { desktopFile: id, size: file.blob.size, type: file.blob.type } };
    }) } };
  }
  receive(message: unknown): boolean {
    if (!object(message)) return false;
    if (message.filePort === "release") { this.#files.delete(message.file); return true; }
    if (message.filePort !== "read") return false;
    const { request, file, start, end } = message;
    void Promise.resolve().then(async () => {
      const blob = this.#files.get(file);
      if (!blob) throw new Error("The selected file is no longer available");
      if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || end < start || end > blob.size || end - start > FILE_PART) throw new Error("Invalid file part");
      return blob.slice(start, end).arrayBuffer();
    }).then(
      (bytes) => this.#send({ filePort: "part", request, bytes }),
      (error: unknown) => this.#send({ filePort: "part", request, error: error instanceof Error ? error.message : String(error) }),
    ).catch(() => { /* The port closed while the file was being read. */ });
    return true;
  }
  close(): void { this.#files.clear(); }
}

export class CoreFiles {
  #send: Send;
  #next = 0;
  #closed = false;
  #pending = new Map<number, { resolve: (bytes: ArrayBuffer) => void; reject: (error: Error) => void }>();
  constructor(send: Send) { this.#send = send; }
  prepare(message: unknown): unknown {
    if (!object(message) || message.call !== "composer.add" || !Array.isArray(message.params?.files)) return message;
    return { ...message, params: { ...message.params, files: message.params.files.map((file: Message) => {
      if (!object(file)) return file;
      const b = file.blob;
      if (!object(b) || !Number.isSafeInteger(b.desktopFile) || !Number.isSafeInteger(b.size) || b.size < 0 || typeof b.type !== "string") return file;
      const blob = new FileSource(b.size, b.type, (start, end) => new Promise<ArrayBuffer>((resolve, reject) => {
        if (this.#closed) { reject(new Error("The file's page closed")); return; }
        const request = ++this.#next;
        this.#pending.set(request, { resolve, reject });
        try { this.#send({ filePort: "read", request, file: b.desktopFile, start, end }); }
        catch (error) { this.#pending.delete(request); reject(error); }
      }), () => {
        try { if (!this.#closed) this.#send({ filePort: "release", file: b.desktopFile }); }
        catch { /* The page closed; it no longer holds the file either. */ }
      });
      return { ...file, blob };
    }) } };
  }
  receive(message: unknown): boolean {
    if (!object(message) || message.filePort !== "part") return false;
    const waiting = this.#pending.get(message.request);
    if (waiting) {
      this.#pending.delete(message.request);
      if (message.bytes instanceof ArrayBuffer) waiting.resolve(message.bytes);
      else waiting.reject(new Error(typeof message.error === "string" ? message.error : "Could not read file part"));
    }
    return true;
  }
  close(): void {
    this.#closed = true;
    for (const p of this.#pending.values()) p.reject(new Error("The file's page closed"));
    this.#pending.clear();
  }
}
