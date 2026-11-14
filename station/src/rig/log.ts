// What a rig was told to run (a station that only runs tasks): a line for each command a station prepared on it and each one run with a
// secret, with the chat that asked, kept on the rig itself (<data>/rig/commands.log), where no station or agent
// writes. Its person reads the last of it from their app (through a station); `stillfail status` names the file.
import { appendFileSync, closeSync, existsSync, fstatSync, mkdirSync, openSync, readSync, renameSync, statSync } from "node:fs";
import { dirname } from "node:path";

/// `device`: a chat's connection to one of the rig's devices (`name` the device's, `command` how it was reached).
export type Command = { at: number; station: string; session: string; key: string; name: string; command: string; kind: "task" | "secret" | "device" };

/// The file goes to `.1` past this, the one before it gone.
const FILE_MAX = 4 * 1024 * 1024;
/// A line's command is cut to this (what was run in full is in the task's own record).
const COMMAND_MAX = 2000;
/// The most of the file's end read for its last lines.
const TAIL_BYTES = 256 * 1024;

export class CommandLog {
  readonly #path: string;

  constructor(path: string) {
    this.#path = path;
    mkdirSync(dirname(path), { recursive: true });
  }

  add(c: Command): void {
    try {
      if (existsSync(this.#path) && statSync(this.#path).size > FILE_MAX) renameSync(this.#path, `${this.#path}.1`);
      appendFileSync(this.#path, JSON.stringify({ ...c, command: c.command.slice(0, COMMAND_MAX) }) + "\n", { mode: 0o600 });
    } catch {
      // A full disk does not stop the task: the station's own log says what it ran too.
    }
  }

  /// Its last `limit` lines, newest first.
  last(limit: number): Command[] {
    let fd: number;
    try {
      fd = openSync(this.#path, "r");
    } catch {
      return [];
    }
    try {
      const size = fstatSync(fd).size;
      const from = Math.max(0, size - TAIL_BYTES);
      const buffer = Buffer.alloc(size - from);
      readSync(fd, buffer, 0, buffer.length, from);
      const lines = buffer.toString("utf8").split("\n");
      // Read from the middle of the file: its first line is the end of one.
      if (from > 0) lines.shift();
      const out: Command[] = [];
      for (let i = lines.length - 1; i >= 0 && out.length < limit; i--) {
        if (lines[i] === "") continue;
        try {
          out.push(JSON.parse(lines[i]!));
        } catch {}
      }
      return out;
    } finally {
      closeSync(fd);
    }
  }
}
