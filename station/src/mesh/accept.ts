// An endpoint's connections, taken as they come: each served in a fiber of its own while the others are, and closed
// once it is served no more. Which protocol a connection speaks, what serves it and what is said when serving it fails
// are given to it: the station's are mesh/mesh.ts's and rig/main.ts's; another program's server gives its door
// (door.ts) with its own admission. scripts/mesh-base.ts keeps it so.
import { Effect, FiberSet, type Scope } from "effect";
import { log } from "../ops/log.ts";
import type { Connection, Endpoint } from "./endpoint.ts";

/// How an endpoint's connections are served.
export type Taken = {
  /// Called as a connection is accepted, before it is served and before the next is accepted: what watches it.
  arrived?(conn: Connection): void;
  /// One connection, served until it ends. What it fails with (what it throws too) is given to `failed`.
  serve(conn: Connection): Promise<void>;
  /// What is said of a connection whose serving failed: by default, the log's "connection ended" with the error.
  failed?(error: unknown, conn: Connection): void;
  /// The reason a connection is closed with, code 0, as soon as it is served no more: however `serve` ended (it
  /// returned, it failed), and where the fibers' scope closes meanwhile (the program stopping), which is what the
  /// reason is to say. A connection `serve` closed itself before it ended keeps that close. One it left open to be
  /// closed later does not: a door's refused hello (door.ts `Refusal`) fails at once, its own close set for a while
  /// after the refusal's line, so that connection is closed here, at once, with code 0 and this reason, and the
  /// refusal's code and reason are never the other end's.
  closing: string;
  /// Where the connections' fibers are kept, for one whose connections are to end at another moment of its stopping
  /// than this effect's own scope closes at: by default a set of that scope.
  connections?: FiberSet.FiberSet;
};

/// Takes the endpoint's connections until it gives no more (closed: `accept` answers null), then returns, the
/// connections still served until their fibers' scope closes. An `accept` that fails is a defect: it is not asked again.
export const accept = (endpoint: Pick<Endpoint, "accept">, how: Taken): Effect.Effect<void, never, Scope.Scope> =>
  Effect.gen(function* () {
    const connections = how.connections ?? (yield* FiberSet.make());
    for (;;) {
      const conn = yield* Effect.promise(() => endpoint.accept());
      if (!conn) return;
      how.arrived?.(conn);
      yield* FiberSet.run(
        connections,
        Effect.tryPromise(() => how.serve(conn)).pipe(
          Effect.catch((e) => Effect.sync(() => {
            const error = (e as Error).cause ?? e;
            if (how.failed) how.failed(error, conn);
            else log.info("mesh", "connection ended", { error: String(error) });
          })),
          Effect.ensuring(Effect.sync(() => conn.close(0, how.closing))),
        ),
      );
    }
  });
