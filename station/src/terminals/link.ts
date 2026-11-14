// A terminal's runner, as the station holds it (native/runner `--pty`): the one connection a runner takes, its output
// as it comes, with its offsets, given to whoever listens, and what is asked of it (typing, a new size, the screen as
// it is). Its output is acknowledged as it comes, nothing kept: the runner's copy of the screen (`screen`) is what one
// who opens the terminal, or opens it again, is given, not the bytes since it began.
import { createConnection, type Socket } from "node:net";
import type { RunnerInfo } from "../agents/runner.ts";
import { platform } from "../platform/index.ts";

/// Output from `at` (stdout's offset as the runner counts it).
export type Out = { at: number; bytes: Buffer };
/// The screen as it is, VT that makes it again in a new terminal of its size, and how much of the output made it.
export type Shown = { at: number; data: Buffer };
export type Ended = { code: number | null; signal: string | null };

/// What a link needs of a socket: the runner's, or a test's.
export type Wire = {
  write(line: string): void;
  end(): void;
  on(event: "line", f: (message: any) => void): void;
  on(event: "close", f: () => void): void;
};

/// A runner's socket, read as lines of JSON.
export function runnerWire(info: RunnerInfo): Wire {
  const socket: Socket = createConnection(info.socket);
  let carry = "";
  const lines: ((m: any) => void)[] = [];
  const closes: (() => void)[] = [];
  socket.on("data", (chunk) => {
    carry += chunk.toString("utf8");
    for (let i = carry.indexOf("\n"); i >= 0; i = carry.indexOf("\n")) {
      const line = carry.slice(0, i);
      carry = carry.slice(i + 1);
      let message: any;
      try {
        message = JSON.parse(line);
      } catch {
        continue;
      }
      for (const f of lines) f(message);
    }
  });
  socket.on("error", () => undefined);
  socket.on("close", () => {
    for (const f of closes) f();
  });
  return {
    write: (line) => void (socket.writable && socket.write(line)),
    end: () => {
      if (platform.runnerSaysLeave && socket.writable) socket.write(JSON.stringify({ op: "leave" }) + "\n");
      socket.end();
    },
    on: (event: "line" | "close", f: any) => void (event === "line" ? lines.push(f) : closes.push(f)),
  };
}

export class TerminalLink {
  readonly #wire: Wire;
  readonly #listeners = new Set<(out: Out) => void>();
  readonly #asked: ((shown: Shown | Error) => void)[] = [];
  readonly #ends = new Set<(ended: Ended | null) => void>();
  /// Where the output is up to, as the runner counts it.
  #at = 0;
  #ended: Ended | null | undefined;

  constructor(wire: Wire) {
    this.#wire = wire;
    wire.on("line", (m) => this.#take(m));
    // Gone without an exit: the runner went (killed); no more comes.
    wire.on("close", () => this.#end(null));
    this.#send({ op: "attach" });
  }

  #take(m: any) {
    switch (m?.op) {
      case "out": {
        if (m.stream !== "out" || typeof m.at !== "number" || typeof m.data !== "string") return;
        const bytes = Buffer.from(m.data, "base64");
        this.#at = m.at + bytes.length;
        // Nothing kept: what is shown again comes from the screen.
        this.#send({ op: "ack", out: this.#at, err: 0 });
        for (const f of this.#listeners) f({ at: m.at, bytes });
        return;
      }
      case "screen": {
        const ask = this.#asked.shift();
        if (ask && typeof m.at === "number" && typeof m.data === "string") ask({ at: m.at, data: Buffer.from(m.data, "base64") });
        return;
      }
      case "error": {
        // What failed is the oldest thing asked that waits for an answer (the runner answers in order).
        const ask = this.#asked.shift();
        ask?.(new Error(String(m.error ?? "the runner refused")));
        return;
      }
      case "exit":
        this.#end({ code: m.code ?? null, signal: m.signal ?? null });
        return;
    }
  }

  #end(ended: Ended | null) {
    if (this.#ended !== undefined) return;
    this.#ended = ended;
    for (const ask of this.#asked.splice(0)) ask(new Error("the terminal ended"));
    for (const f of this.#ends) f(ended);
  }

  #send(message: unknown) {
    this.#wire.write(JSON.stringify(message) + "\n");
  }

  /// Its output as it comes, until the returned function is called.
  listen(f: (out: Out) => void): () => void {
    this.#listeners.add(f);
    return () => this.#listeners.delete(f);
  }

  /// Once it ended: its exit (null: its runner went without one).
  ended(f: (ended: Ended | null) => void): () => void {
    if (this.#ended !== undefined) {
      f(this.#ended);
      return () => undefined;
    }
    this.#ends.add(f);
    return () => this.#ends.delete(f);
  }

  get over(): boolean {
    return this.#ended !== undefined;
  }

  /// The screen as it is now.
  screen(): Promise<Shown> {
    if (this.#ended !== undefined) return Promise.reject(new Error("the terminal ended"));
    return new Promise((resolve, reject) => {
      this.#asked.push((shown) => (shown instanceof Error ? reject(shown) : resolve(shown)));
      this.#send({ op: "screen" });
    });
  }

  type(bytes: Buffer) {
    if (bytes.length > 0) this.#send({ op: "write", data: bytes.toString("base64") });
  }

  resize(cols: number, rows: number) {
    this.#send({ op: "resize", cols, rows });
  }

  /// Ends its program (and what it started: its group), then lets the runner clean up.
  kill() {
    this.#send({ op: "signal", signal: "KILL", group: true });
    this.#send({ op: "done" });
  }

  /// The station lets go (stopping, handing over): the runner keeps the terminal for the next one.
  detach() {
    this.#wire.end();
  }
}

/// What of `out` is past `at`: the part of a piece the screen did not have yet (none where it had all of it).
export function pastScreen(out: Out, at: number): Buffer | null {
  const end = out.at + out.bytes.length;
  if (end <= at) return null;
  return out.at >= at ? out.bytes : out.bytes.subarray(at - out.at);
}
