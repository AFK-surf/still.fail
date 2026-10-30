// The still.fail station, in TypeScript (docs/station-ts.md). This file is the composition root: every part is a layer
// made here and given what it needs (src/services.ts); nothing registers itself anywhere. Stopping the station is
// interrupting it: every part's scope closes, and with it what it opened. Commands as the Rust station takes them:
//
//   run --app DIR [--port N] [--data DIR] [--with-parent] [--launcher-fds a,b,c]
//   enroll <cloud> <token> [--provider stillfail|comma] [--lock HASH] [--join | --stay] [--data DIR]   status [--data DIR]   id [--data DIR]
//   channel [stable|beta] [--app DIR] [--data DIR]   update [--beta|--stable] --app DIR [--data DIR]
//   lock status|reset [--data DIR]
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { PerformanceObserver, monitorEventLoopDelay } from "node:perf_hooks";
import { join } from "node:path";
import { Effect, Fiber, Layer, SubscriptionRef } from "effect";
import { enroll, id, joinWorkspace, lockCommand, staysIn, status } from "./cli.ts";
import { readState } from "./cloud/state.ts";
import { loadKey } from "./cloud/key.ts";
import { shortCode } from "./cloud/lock.ts";
import { MeshLive } from "./mesh/mesh.ts";
import { AwakeLive } from "./ops/awake.ts";
import { AgentsLive } from "./sessions/agents.ts";
import { Browser } from "./browser/service.ts";
import { dataDir, flag, ownData } from "./ops/files.ts";
import { setStationLang, stationLang, tr } from "./ops/i18n.ts";
import { type Control, launcher } from "./ops/launcher.ts";
import { hearErrors, hearLines, log } from "./ops/log.ts";
import { stationLog } from "./ops/log-export.ts";
import { ConfigFile } from "./ops/config.ts";
import { ErrorReports, builtKey } from "./ops/telemetry.ts";
import { answer, langOfBrowser } from "./ops/loopback.ts";
import { ownPorts } from "./ops/own.ts";
import { version } from "./ops/version.ts";
import { AdminApi, AgentsSide, AdminHost, CheckpointsLive, ControlPlane, Events, Grants, Helper, HelperFolders, Key, MeshNative, MeshSide, ModulePackages, Modules, Own, Parts, Paths, Peers, Previous, Readers, ScreenRegistry, StationConfig, StationDrive, Store, Up } from "./services.ts";
import { ModulesLive } from "./modules/live.ts";
import { VaultLive } from "./vault/module.ts";
import { AdbLive } from "./adb/module.ts";
import { BrowserLive } from "./browser/module.ts";
import { LinksLive } from "./links/module.ts";
import { FeedbackLive } from "./feedback/module.ts";
import { AgentHomeLive } from "./agenthome/module.ts";
import { PublishLive } from "./publish/module.ts";
import { LoginsLive } from "./logins/module.ts";
import { DriveTransfersLive } from "./drive/module.ts";
import { UsageLive } from "./usage/module.ts";
import { OutflowLive } from "./outflow/module.ts";
import { ElevationLive } from "./elevation/module.ts";
import { ResourcesLive } from "./resources/module.ts";
import { SearchLive } from "./search/module.ts";
import { SlackLive } from "./slack/module.ts";
import { FeishuLive } from "./feishu/module.ts";
import { ModelsLive } from "./models/module.ts";
import { PROVIDERS, type Provider } from "./cloud/provider.ts";
import { wall } from "./ops/fibers.ts";
import { answerHeapRequests, heapCommand } from "./ops/heap.ts";
import { timeFiles } from "./ops/file-waits.ts";
import { longestWaits } from "./ops/waits.ts";
import { takeQueries } from "./store/timed.ts";
import { platform } from "./platform/index.ts";
import { keepRunnerIn } from "./platform/processes.ts";

// What reads HOME (the machine's logins, its transcripts) finds the user's home there, where the machine names it
// otherwise (Windows: USERPROFILE).
if (!process.env.HOME && platform.home(process.env)) process.env.HOME = platform.home(process.env);

const args = process.argv.slice(2);
const data = dataDir(args);
const command = args.find((a, i) => !a.startsWith("--") && !(i > 0 && args[i - 1].startsWith("--") && args[i - 1] !== "--with-parent"));
/// Flags that take a value: what follows them is no command's argument.
const VALUED = ["--data", "--provider", "--lock"];
/// How often the main thread's longest hold is looked at, and from how long a hold is said.
const HELD_EVERY_MS = 10_000;
const HELD_MS = 1_000;

// What it says on this machine is in the station's language (config.json `language`).
try {
  const config = process.env.STILLFAIL_CONFIG || process.env.EMBER_CONFIG || join(data, "config.json");
  setStationLang(JSON.parse(readFileSync(config, "utf8")).language);
} catch {}

function usage(): never {
  console.error("usage: stillfail-station run --app DIR [--port N] [--data DIR] | enroll <cloud> <token> [--provider stillfail|comma] [--lock HASH] [--join | --stay] | status | id | channel [stable|beta] | update [--beta|--stable] --app DIR | lock status|reset | heap");
  process.exit(2);
}

/// The loopback port (src/ops/loopback.ts): old page links sent on to still.fail cloud, `/healthz`. The port it got is
/// written to <data>/run/ports.json.
const Loopback = (control: Control) =>
  Layer.effectDiscard(
    Effect.gen(function* () {
      const up = yield* Up;
      const cloud = yield* ControlPlane;
      yield* Effect.acquireRelease(
        Effect.sync(() => {
          const server = createServer((req, res) => {
            const url = new URL(req.url ?? "/", "http://station");
            const s = cloud.state.state;
            const place = s ? { origin: s.origin, workspace: s.workspace, workspace_name: s.workspace_name, station: s.station, removed_at: s.removed_at } : null;
            const reply = answer(url.pathname, url.search ? url.search.slice(1) : null, SubscriptionRef.getUnsafe(up), place, langOfBrowser(req.headers));
            res.writeHead(reply.status, reply.headers).end(reply.body);
          });
          server.on("listening", () => {
            const port = (server.address() as AddressInfo).port;
            // Behind the launcher's entrance, the launcher's port is the one there is (the launcher wrote it too).
            const shown = control.ports?.admin ?? port;
            ownPorts.add(port).add(shown);
            mkdirSync(join(data, "run"), { recursive: true });
            writeFileSync(join(data, "run", "ports.json"), `{"admin":${shown}}\n`);
            control.serving("admin", port);
            log.info("station", "loopback port listening (old /admin links go to still.fail cloud)", { port: shown });
          });
          if (control.loopbackFd !== undefined) server.listen({ fd: control.loopbackFd });
          else if (control.ports) server.listen(0, "127.0.0.1");
          else {
            // On its own (no launcher): 4760 on the machine's own data directory, or a free port when that is taken
            // (or another data directory) and none was named (local.rs).
            const named = flag(args, "--port");
            server.on("error", (e: NodeJS.ErrnoException) => {
              if (e.code === "EADDRINUSE" && !named) server.listen(0, "127.0.0.1");
              else log.error("station", "the loopback port is not had", { error: e.message });
            });
            server.listen(Number(named ?? (ownData(data) ? 4760 : 0)), "127.0.0.1");
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
  // Runners (agents', jobs') from copies under the data directory on Windows, out of reach of the app's installer.
  keepRunnerIn(join(data, "run", "bin"));
  // Error lines to still.fail's error tracking, while config.json says so (telemetry.errors) and the build has a key.
  const settings = new ConfigFile(data);
  const stationId = () => {
    try {
      return JSON.parse(readFileSync(join(data, "mesh", "cloud.json"), "utf8")).station ?? null;
    } catch {
      return null;
    }
  };
  const reports = new ErrorReports({
    key: builtKey(join(app, "dist", "admin")),
    enabled: () => settings.raw()?.telemetry?.errors === true,
    station: stationId,
  });
  hearErrors((line, error) => reports.report(line, error));
  // Every line to still.fail, scrubbed, unless config.json turns it off (telemetry.logs: false); sent once the mesh is up.
  stationLog.configure({ enabled: () => settings.raw()?.telemetry?.logs !== false, station: stationId, version });
  hearLines((line) => stationLog.add(line));
  const paths = Layer.succeed(Paths)({ data, app });
  // still.fail Helper, one for the screens and the drive, and one look at its grants.
  const base = Layer.mergeAll(Key.layer, Readers.layer, Store.layer, MeshNative.layer, Up.layer, ScreenRegistry.layer.pipe(Layer.provideMerge(Grants.layer), Layer.provideMerge(Helper.layer))).pipe(Layer.provideMerge(paths));
  const parts = ControlPlane.layer.pipe(Layer.provideMerge(base));
  const station = Layer.mergeAll(MeshLive, Loopback(control), AwakeLive, ModulesLive, CheckpointsLive).pipe(
    // The station's parts in its own process (parts.ts), made before the mesh answers anyone: each says what it adds.
    Layer.provideMerge(Layer.mergeAll(VaultLive, AdbLive, BrowserLive, LinksLive, FeedbackLive, AgentHomeLive, PublishLive, LoginsLive, DriveTransfersLive, UsageLive, OutflowLive, ElevationLive, ResourcesLive, SearchLive, SlackLive, FeishuLive, ModelsLive)),
    Layer.provideMerge(AdminApi.layer),
    Layer.provideMerge(AgentsLive(control)),
    // The drive, the admin API's and the modules' local API's (modules/local.ts): the platform's, before the agents.
    Layer.provideMerge(StationDrive.layer),
    Layer.provideMerge(HelperFolders.layer),
    // The modules beside the station (docs/station-modules.md), started by ModulesLive.
    Layer.provideMerge(Modules.layer),
    // The packages of those the station installs itself (modules/packages.ts), read with its updates.
    Layer.provideMerge(ModulePackages.layer),
    Layer.provideMerge(Events.layer),
    Layer.provideMerge(AdminHost.layer),
    // The station's browser, its tabs screens (docs/remote-screens.md).
    Layer.provideMerge(Browser.layer),
    // config.json, what is the station's own, and the process before this one: the platform's, for every part.
    Layer.provideMerge(Own.layer),
    Layer.provideMerge(StationConfig.layer),
    Layer.provideMerge(Previous.layer),
    // The requests between the stations of the workspace (mesh/bus.ts): the mesh attaches them, the parts answer.
    Layer.provideMerge(Peers.layer),
    // What the mesh and the agents' side share, each filling in its own (services.ts MeshSide).
    Layer.provideMerge(MeshSide.layer),
    Layer.provideMerge(Parts.layer),
    // The agents' side, once made (the admin API asks for it as a request comes).
    Layer.provideMerge(AgentsSide.layer),
    Layer.provideMerge(parts),
  );
  // What the parts hold only in memory (the vault's grants), carried over to the next process at a handover.
  let carry = () => {};
  const main = Effect.gen(function* () {
    yield* SubscriptionRef.set(yield* Up, true);
    const stationParts = yield* Parts;
    control.carried((what) => stationParts.takeUp(what));
    carry = () => control.carry(stationParts.carried());
    control.ready(version());
    log.info("station", "station up", { version: version(), data });
    // Where the memory goes, in MB: the main thread's (and resident), and each reader's heap. Every ten minutes, or
    // every ten seconds with STILLFAIL_MEMLOG (for measuring).
    const readers = yield* Readers;
    // `stillfail heap`: a snapshot of this thread's heap, asked for from the command line.
    answerHeapRequests(data);
    // The main thread held (a query of seconds, a long parse): said as it is let go, with how long. Every device's
    // requests wait meanwhile; the slow queries say what held it (store/timed.ts). With no slow query, what the
    // process did meanwhile says whether it worked (`cpuMs`, all its threads'), collected its garbage (`gcMs`, this
    // thread's, and the longest pause), waited on pages of its memory read back from the disk (`pageFaults`), on files
    // (`filesMs`, its synchronous calls of node:fs: ops/file-waits.ts) or on its statements (`queriesMs`, all of them,
    // none slow: store/timed.ts); the longest of each by who made them.
    const files = timeFiles();
    const held = monitorEventLoopDelay({ resolution: 50 });
    held.enable();
    const gc = { ms: 0, longest: 0 };
    new PerformanceObserver((list) => {
      for (const e of list.getEntries()) {
        gc.ms += e.duration;
        gc.longest = Math.max(gc.longest, e.duration);
      }
    }).observe({ entryTypes: ["gc"] });
    let cpu = process.cpuUsage();
    let faults = process.resourceUsage().majorPageFault;
    wall.every(HELD_EVERY_MS, () => {
      const ms = held.max / 1e6;
      const used = process.cpuUsage(cpu);
      const faulted = process.resourceUsage().majorPageFault;
      const waited = files.take();
      const queried = takeQueries();
      if (ms >= HELD_MS) {
        log.warn("station", "the main thread was held", {
          ms: Math.round(ms), cpuMs: Math.round((used.user + used.system) / 1000), gcMs: Math.round(gc.ms), gcLongestMs: Math.round(gc.longest), pageFaults: faulted - faults,
          filesMs: Math.round(waited.ms), files: waited.calls, ...(waited.by.size > 0 ? { waitedOn: longestWaits(waited) } : {}),
          queriesMs: Math.round(queried.ms), queries: queried.calls, ...(queried.by.size > 0 ? { queriedBy: longestWaits(queried) } : {}),
        });
      }
      held.reset();
      cpu = process.cpuUsage();
      faults = faulted;
      gc.ms = 0;
      gc.longest = 0;
    });
    wall.every(process.env.STILLFAIL_MEMLOG ? 10_000 : 600_000, () => {
      const m = process.memoryUsage();
      const mb = (v: number) => Math.round(v / 1048576);
      void readers.heaps().then((heaps) =>
        log.info("memory", "now", { ...Object.fromEntries(Object.entries(m).map(([k, v]) => [k, mb(v)])), readers: heaps.map(mb) }),
      );
    });
    return yield* Effect.never;
  }).pipe(Effect.provide(station));
  const fiber = Effect.runFork(main);

  let stopping = false;
  const stop = (why: string) => {
    if (stopping) return;
    stopping = true;
    log.info("station", "stopping", { why });
    Effect.runFork(Fiber.interrupt(fiber)).addObserver(() => void Promise.all([reports.shutdown(), stationLog.shutdown()]).finally(() => process.exit(0)));
  };
  control.on("stop", () => stop("asked to stop"));
  control.on("handover", () => {
    if (!stopping) carry();
    stop("handed over to the next station process");
  });
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
    const [, origin, token] = args.filter((a, i) => !a.startsWith("--") && !(i > 0 && VALUED.includes(args[i - 1])));
    const provider = (flag(args, "--provider") ?? "stillfail") as Provider;
    const lock = flag(args, "--lock");
    if (!origin || !token || !PROVIDERS.includes(provider) || (lock !== undefined && !/^[0-9a-f]{64}$/.test(lock))) usage();
    // One more workspace, staying in those it is in (docs/multi-workspace.md): at the control plane it is enrolled with.
    // --stay (the installers'): joins when the station is in a workspace already, else enrolls; at the control plane it
    // is enrolled with whatever host the command names (the test channel's app.youdid.wtf is still.fail's API too), a
    // token that plane does not know refused there.
    const stay = !args.includes("--join") && args.includes("--stay") && staysIn(data);
    if (args.includes("--join") || stay) {
      const now = readState(data);
      if (!stay && now !== null && now.origin !== origin.replace(/\/+$/, "")) {
        console.error(`this station is enrolled at ${now.origin}; it joins workspaces there only`);
        process.exit(1);
      }
      const joined = await joinWorkspace(data, token, lock).catch((error) => {
        if (stay) console.error(`this station is in workspace ${now?.workspace_name || now?.workspace} (${now?.origin}): it was to join this one beside it, which did not go through. To move it here instead, remove it from that workspace first.`);
        throw error;
      });
      console.log(tr(stationLang(), "station.cli.joined", { workspace: joined.workspace_name, name: joined.name, id: loadKey(data).id.slice(0, 12) }));
      // A locked workspace: its owner confirms this station by its code, as one enrolled with `--lock`.
      if (lock !== undefined) console.log(tr(stationLang(), "station.cli.lock.pending", { code: shortCode(loadKey(data).id) }));
      break;
    }
    await enroll(data, origin.replace(/\/+$/, ""), token, provider, lock);
    break;
  }
  // The workspace lock on this machine (docs/workspace-lock.md): what is pinned, or taking it away.
  case "lock": {
    const [, what] = args.filter((a, i) => !a.startsWith("--") && !(i > 0 && VALUED.includes(args[i - 1])));
    if (what !== "status" && what !== "reset") usage();
    console.log(lockCommand(data, what));
    break;
  }
  case "status":
    console.log(status(data));
    break;
  case "id":
    id(data);
    break;
  // The channel the station is updated on (`stillfail update`): set when one is named, then said.
  case "channel": {
    const { channelCommand } = await import("./updates/channel.ts");
    const code = await channelCommand(args, data);
    if (code === 2) usage();
    process.exitCode = code;
    break;
  }
  // What `stillfail update` runs, its release verified (updates/command.ts): said, not run, here.
  case "update": {
    const { updateCommand } = await import("./updates/command.ts");
    const code = await updateCommand(args, data);
    if (code === 2) usage();
    process.exitCode = code;
    break;
  }
  // A heap snapshot of the running station (ops/heap.ts).
  case "heap":
    process.exitCode = await heapCommand(data);
    break;
  default:
    usage();
}
