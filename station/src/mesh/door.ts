// The door of a mesh protocol whose connections are let in by their first line. The first bidirectional stream is the
// control stream, one JSON line each way at a time: the hello and its answer, then any later line (a renewal) and its
// answer. Every other stream is one request (wire.ts `request`), served only once the hello was let in. Who is let in,
// what the lines say and what a request is answered are given to it (`Admit`): it knows nothing of still.fail's
// credentials, locks or routes, which are mesh/serve.ts's; another program is served by it with its own.
// scripts/mesh-base.ts keeps it so.
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { Connection } from "./endpoint.ts";
import { type Asked, Reader, request, writeLine } from "./wire.ts";

/// How long after a refusal the door closes the connection: the refusal's line is to reach the other end first, and
/// the other end, which has what it came for once it read the line, may well close it before.
const REFUSED_CLOSE_MS = 200;

/// A hello refused: the line it is answered, the code and reason the door closes the connection with
/// REFUSED_CLOSE_MS after it was refused (whether or not the other end has taken the line in by then), and what
/// serving the connection fails with, once it is closed: by that close, by the other end, or by whoever serves it
/// (accept.ts as its scope closes: the program stopping). Nothing is served on it meanwhile, no stream of it accepted.
/// So the door's close is the one the other end sees unless something closed the connection before it. Until
/// 2026-11-14 serving failed as soon as the line was written, the station's loop closed the connection at once with
/// code 0 and its own reason, and a line that had not all gone by then was cut: its device was told only that the
/// connection was lost.
export type Refusal = { line: unknown; code: number; reason: string; error: unknown };

/// Thrown by `renew` (or what its promise fails with) where the renewal's refusal ends the connection: the line it is
/// answered (`{error}`, its message, where none is given), and the code and reason the door closes the connection
/// with, REFUSED_CLOSE_MS after it was thrown, as it closes a refused hello's.
export class Ending extends Error {
  readonly code: number;
  readonly reason: string;
  readonly line: unknown;
  constructor(message: string, code: number, reason: string, line: unknown = { error: message }) {
    super(message);
    this.code = code;
    this.reason = reason;
    this.line = line;
  }
}

/// A connection let in.
export type In = {
  /// The line its hello is answered.
  line: unknown;
  /// Called once that line is written, before anything more is read of the connection: what is said of it, and where
  /// what may end it later starts (a timer, a listener: each closes the connection itself, with its code and reason).
  opened?(): void;
  /// A later line on the control stream: the line it is answered, or a promise of it (the next line is read once it
  /// is answered; a line given, not promised, is written in the turn it came). What it throws, or its promise fails
  /// with, is answered `{error}`, its message, and closes nothing; but an `Ending`, which is answered its line and ends
  /// the connection: no later line is read, no stream accepted from then on is served (each is reset; those accepted
  /// before go on until the close), and the connection is closed REFUSED_CLOSE_MS after it was thrown, with its code
  /// and reason, whether or not the other end has taken its line in by then. Serving the connection fails with it then.
  renew(line: any): unknown;
  /// Called as each request stream is accepted, before its head is read: what answers it; null where the connection is
  /// let in no longer (who says so has closed it), and nothing more is served on it.
  stream(): ((asked: Asked) => Promise<void>) | null;
  /// Called once no more streams are taken (the connection ended, `stream` said null, accepting one failed): what
  /// `opened` started stops.
  ended?(): void;
};

/// Who is let in: asked once, of the control stream's first line, and answers in that same turn.
export type Admit = (hello: any, conn: Connection) => In | { refused: Refusal };

/// One connection: its hello first, nothing served before it is let in; then a request a stream.
export async function door(conn: Connection, admit: Admit): Promise<void> {
  const first = await conn.acceptBi();
  if (!first) return;
  const control = new Reader(first);
  const hello = await control.line();
  if (hello === null) {
    await first.reset(0).catch(() => {});
    throw new Error("no credential");
  }
  const said = admit(hello, conn);
  if ("refused" in said) {
    const { line, code, reason, error } = said.refused;
    // Its close is set as it is refused, and its line not waited for: the other end may take in nothing of its
    // control stream, and would keep the connection for as long as it liked.
    const off = wall.after(REFUSED_CLOSE_MS, () => conn.close(code, reason));
    void writeLine(first, line).then(() => first.finish()).catch(() => {});
    // Kept until it is closed, by whichever closes it first; its serving fails then, not before: who serves it closes
    // it as that fails (accept.ts), which would be before the line has gone.
    await conn.closed().catch(() => {});
    off();
    throw error;
  }
  await writeLine(first, said.line);
  said.opened?.();
  // Later lines on the control stream, until one ends the connection (`ending`).
  let ending: Ending | null = null;
  (async () => {
    for (let line = await control.line().catch(() => null); line !== null; line = await control.line().catch(() => null)) {
      let reply;
      try {
        reply = said.renew(line);
        // (Waited for only where it is a promise: a line given is written in the turn it came.)
        if (typeof (reply as PromiseLike<unknown> | null)?.then === "function") reply = await reply;
      } catch (e) {
        if (e instanceof Ending) {
          // Its close is set now, not once its line is written: the other end may take in nothing of its control
          // stream, and that write, and the connection with it, would wait on it for good.
          ending = e;
          const { code, reason } = e;
          wall.after(REFUSED_CLOSE_MS, () => conn.close(code, reason));
          reply = e.line;
        } else reply = { error: (e as Error).message };
      }
      await writeLine(first, reply).catch(() => {});
      if (ending !== null) break;
    }
    await first.finish().catch(() => {});
  })();

  try {
    for (let stream = await conn.acceptBi(); stream; stream = await conn.acceptBi()) {
      if (ending !== null) {
        void stream.reset(0).catch(() => {});
        continue;
      }
      const answer = said.stream();
      if (answer === null) return;
      const failed = (e: unknown) => {
        log.info("mesh", "request failed", { error: (e as Error).message });
        void stream.reset(0).catch(() => {});
      };
      // (What answers is not waited for through the head's reading: its failure is said, and its stream reset, in the
      // turn it fails in.)
      request(stream, (asked) => void answer(asked).catch(failed)).catch(failed);
    }
  } finally {
    said.ended?.();
  }
  if (ending !== null) throw ending;
}
