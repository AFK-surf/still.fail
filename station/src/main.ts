// The still.fail station, in TypeScript (docs/station-ts.md). This file is the composition root: every part is a layer
// made here and given what it needs (src/services.ts); nothing registers itself anywhere. Stopping the station is
// interrupting it: every part's scope closes, and with it what it opened. Commands as the Rust station takes them:
//
//   run --app DIR [--port N] [--data DIR] [--with-parent] [--launcher-fds a,b,c]
//   enroll <cloud> <token> [--data DIR]   status [--data DIR]   id [--data DIR]
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { join } from "node:path";
import { Effect, Fiber, Layer, SubscriptionRef } from "effect";
import { enroll, id, status } from "./cli.ts";
import { MeshLive } from "./mesh/mesh.ts";
import { dataDir, flag } from "./ops/files.ts";
import { setStationLang } from "./ops/i18n.ts";
import { type Control, launcher } from "./ops/launcher.ts";
import { log } from "./ops/log.ts";
import { version } from "./ops/version.ts";
import { AdminApi, Cloud, Key, MeshNative, Paths, Readers, Up } from "./services.ts";

const args = process.argv.slice(2);
const data = dataDir(args);
const command = args.find((a, i) => !a.startsWith("--") && !(i > 0 && args[i - 1].startsWith("--") && args[i - 1] !== "--with-parent"));

// What it says on this machine is in the station's language (config.json `language`).
try {
  const config = process.env.STILLFAIL_CONFIG || process.env.EMBER_CONFIG || join(data, "config.json");
  setStationLang(JSON.parse(readFileSync(config, "utf8")).language);
} catch {}

function usage(): never {
  console.error("usage: stillfail-station run --app DIR [--port N] [--data DIR] | enroll <cloud> <token> | status | id");
  process.exit(2);
}

/// The loopback port: whether the station answers (`/healthz`), for `bin/stillfail` and the desktop app.
const Loopback = (control: Control) =>
  Layer.effectDiscard(
    Effect.gen(function* () {
      const up = yield* Up;
      yield* Effect.acquireRelease(
        Effect.sync(() => {
          const server = createServer((req, res) => {
            const answering = SubscriptionRef.getUnsafe(up);
            if (req.url === "/healthz") res.writeHead(answering ? 200 : 503).end(answering ? "ok" : "starting");
            else res.writeHead(404).end();
          });
          if (control.loopbackFd !== undefined) server.listen({ fd: control.loopbackFd });
          else {
            // On its own (no launcher): 4760, or a free port when that is taken and none was named (local.rs).
            const named = flag(args, "--port");
            server.on("error", (e: NodeJS.ErrnoException) => {
              if (e.code === "EADDRINUSE" && !named) server.listen(0, "127.0.0.1");
              else log.error("station", "the loopback port is not had", { error: e.message });
            });
            server.listen(Number(named ?? 4760), "127.0.0.1");
          }
          return server;
        }),
        (server) => Effect.sync(() => server.close()),
      );
    }),
  );

function run() {
  const app = flag(args, "--app");
  if (!app) usage();
  const control = launcher(args);
  const paths = Layer.succeed(Paths)({ data, app });
  const parts = Layer.mergeAll(Cloud.layer, Key.layer, Readers.layer, MeshNative.layer, Up.layer).pipe(Layer.provide(paths));
  const station = Layer.mergeAll(MeshLive, Loopback(control)).pipe(
    Layer.provideMerge(AdminApi.layer),
    Layer.provideMerge(parts),
  );
  const main = Effect.gen(function* () {
    yield* SubscriptionRef.set(yield* Up, true);
    control.ready(version());
    log.info("station", "station up", { version: version(), data });
    return yield* Effect.never;
  }).pipe(Effect.provide(station));
  const fiber = Effect.runFork(main);

  let stopping = false;
  const stop = (why: string) => {
    if (stopping) return;
    stopping = true;
    log.info("station", "stopping", { why });
    Effect.runFork(Fiber.interrupt(fiber)).addObserver(() => process.exit(0));
  };
  control.on("stop", () => stop("asked to stop"));
  control.on("handover", () => stop("handed over to the next station process"));
  // Nothing runs yet that a drain would wait for.
  control.on("drain", () => control.drained("idle"));
  fiber.addObserver((exit) => {
    if (!stopping) {
      log.error("station", "the station stopped by itself", { exit: String(exit) });
      process.exit(1);
    }
  });
}

switch (command) {
  case "run":
    run();
    break;
  case "enroll": {
    const [, origin, token] = args.filter((a, i) => !a.startsWith("--") && !(i > 0 && args[i - 1] === "--data"));
    if (!origin || !token) usage();
    await enroll(data, origin.replace(/\/+$/, ""), token);
    break;
  }
  case "status":
    console.log(status(data));
    break;
  case "id":
    id(data);
    break;
  default:
    usage();
}
