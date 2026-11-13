// The door of a mesh protocol whose connections are let in by their first line. The first bidirectional stream is the
// control stream, one JSON line each way at a time: the hello and its answer, then any later line (a renewal) and its
// answer. Every other stream is one request (wire.ts `request`), served only once the hello was let in. Who is let in,
// what the lines say and what a request is answered are given to it (`Admit`): it knows nothing of still.fail's
// credentials, locks or routes, which are mesh/serve.ts's; another program is served by it with its own.
// scripts/mesh-base.ts keeps it so.
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { Connection } from "./native.ts";
import { type Asked, Reader, request, writeLine } from "./wire.ts";

/// How long after a refusal's line the connection is closed: the line is to reach the other end first.
const REFUSED_CLOSE_MS = 200;

/// A hello refused: the line it is answered, the code and reason the connection is closed with after it, and what
/// serving the connection fails with.
export type Refusal = { line: unknown; code: number; reason: string; error: unknown };

/// A connection let in.
export type In = {
  /// The line its hello is answered.
  line: unknown;
  /// Called once that line is written, before anything more is read of the connection: what is said of it, and where
  /// what may end it later starts (a timer, a listener: each closes the connection itself, with its code and reason).
  opened?(): void;
  /// A later line on the control stream: the line it is answered. What it throws is answered `{error}`, its message,
  /// and closes nothing.
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
    await writeLine(first, line).catch(() => {});
    await first.finish().catch(() => {});
    wall.after(REFUSED_CLOSE_MS, () => conn.close(code, reason));
    throw error;
  }
  await writeLine(first, said.line);
  said.opened?.();
  // Later lines on the control stream.
  (async () => {
    for (let line = await control.line().catch(() => null); line !== null; line = await control.line().catch(() => null)) {
      let reply;
      try {
        reply = said.renew(line);
      } catch (e) {
        reply = { error: (e as Error).message };
      }
      await writeLine(first, reply).catch(() => {});
    }
    await first.finish().catch(() => {});
  })();

  try {
    for (let stream = await conn.acceptBi(); stream; stream = await conn.acceptBi()) {
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
}
