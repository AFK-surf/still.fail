import { appendFileSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";

/** Local, bounded JSON lines. Diagnostics must never prevent the app from starting or quitting. */
export class DiagnosticLog {
  readonly file: string;
  readonly marker: string;
  readonly run = `${Date.now()}-${process.pid}`;
  readonly dir: string;
  readonly maxBytes: number;
  constructor(dir: string, maxBytes = 2 * 1024 * 1024) {
    this.dir = dir;
    this.maxBytes = maxBytes;
    this.file = join(dir, "desktop.log");
    this.marker = join(dir, "running.json");
  }

  write(event: string, details: Record<string, unknown> = {}): void {
    try {
      mkdirSync(this.dir, { recursive: true });
      const line = JSON.stringify({ at: new Date().toISOString(), run: this.run, pid: process.pid, event, ...details }, (_key, value) => {
        if (value instanceof Error) return { name: value.name, message: value.message, stack: value.stack };
        return typeof value === "string" ? value.slice(0, 16_384) : value;
      }) + "\n";
      if (existsSync(this.file) && statSync(this.file).size + Buffer.byteLength(line) > this.maxBytes) {
        rmSync(`${this.file}.2`, { force: true });
        if (existsSync(`${this.file}.1`)) renameSync(`${this.file}.1`, `${this.file}.2`);
        renameSync(this.file, `${this.file}.1`);
      }
      appendFileSync(this.file, line, { encoding: "utf8", flush: true });
    } catch { /* A full or unwritable disk must not cause another failure. */ }
  }

  /** Call only after obtaining the single-instance lock. */
  start(details: Record<string, unknown>): void {
    try {
      if (existsSync(this.marker)) {
        let previous: unknown;
        try { previous = JSON.parse(readFileSync(this.marker, "utf8")); } catch { previous = "unreadable marker"; }
        this.write("previous-run-incomplete", { previous });
      }
      this.write("start", details);
      writeFileSync(this.marker, JSON.stringify({ run: this.run, pid: process.pid, at: new Date().toISOString(), ...details }), { encoding: "utf8", flush: true });
    } catch { /* See write. */ }
  }

  finish(code: number): void {
    this.write("quit", { code });
    if (code !== 0) return;
    try { rmSync(this.marker, { force: true }); } catch { /* Detected on the next start. */ }
  }
}
