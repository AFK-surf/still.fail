// The still.fail station, in TypeScript. This file is the composition root: every part is a layer
// made here and given what it needs (src/services.ts); nothing registers itself anywhere. Stopping the station is
// interrupting it: every part's scope closes, and with it what it opened. Commands as the Rust station takes them:
//
//   run --app DIR [--port N] [--data DIR] [--with-parent] [--launcher-fds a,b,c]
//   enroll <cloud> <token> [--provider stillfail|comma] [--lock HASH] [--rig HASH] [--join | --stay] [--data DIR]   status [--data DIR]   id [--data DIR]
//   channel [stable|beta] [--app DIR] [--data DIR]   update [--beta|--stable] --app DIR [--data DIR]
//   lock status|reset [--workspace ID] [--data DIR]
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { type AddressInfo, setDefaultAutoSelectFamilyAttemptTimeout } from "node:net";
import { PerformanceObserver, monitorEventLoopDelay } from "node:perf_hooks";
import { join } from "node:path";
import { Effect, Fiber, Layer, SubscriptionRef } from "effect";
import { enroll, id, isRig, joinWorkspace, lockCommand, staysIn, status } from "./cli.ts";
import { readState } from "./cloud/state.ts";
import { loadKey } from "./cloud/key.ts";
import { shortCode } from "./cloud/lock.ts";
import { MeshLive } from "./mesh/mesh.ts";
import { AwakeLive } from "./ops/awake.ts";
import { AgentsLive } from "./sessions/agents.ts";
import { Browser } from "./browser/service.ts";
import { dataDir, flag, ownData, positionals } from "./ops/files.ts";
import { setStationLang, stationLang, tr } from "./ops/i18n.ts";
import { type Control, launcher } from "./ops/launcher.ts";
import { hearErrors, hearLines, log } from "./ops/log.ts";
import { stationLog } from "./ops/log-export.ts";
import { ConfigFile } from "./ops/config.ts";
import { InvalidJsonFile } from "./ops/json-file.ts";
import { ErrorReports, builtKey } from "./ops/telemetry.ts";
import { answer, langOfBrowser } from "./ops/loopback.ts";
import { ownPorts } from "./ops/own.ts";
import { version } from "./ops/version.ts";
import { AdminApi, AgentsSide, AdminHost, CheckpointsLive, ControlPlane, DeviceSources, Events, Grants, Helper, HelperFolders, Key, MeshNative, MeshSide, Own, Parts, Paths, Peers, Previous, Readers, ReadersAndStore, ScreenRegistry, StationConfig, StationDrive, Up } from "./services.ts";
import { VaultLive } from "./vault/module.ts";
import { AdbLive } from "./adb/module.ts";
import { BrowserLive } from "./browser/module.ts";
import { LinksLive } from "./links/module.ts";
import { FeedbackLive } from "./feedback/module.ts";
import { AgentHomeLive } from "./agenthome/module.ts";
import { LoginsLive } from "./logins/module.ts";
import { DriveTransfersLive } from "./drive/module.ts";
import { UsageLive } from "./usage/module.ts";
import { ElevationLive } from "./elevation/module.ts";
import { ResourcesLive } from "./resources/module.ts";
import { SearchLive } from "./search/module.ts";
import { SlackLive } from "./slack/module.ts";
import { FeishuLive } from "./feishu/module.ts";
import { CommaLive } from "./comma/module.ts";
import { WorkspaceConnectsLive } from "./connects/workspace.ts";
import { ModelsLive } from "./models/module.ts";
import { CopiesLive } from "./replica/module.ts";
import { takeBackSoon } from "./replica/restore.ts";
import { PROVIDERS, type Provider } from "./cloud/provider.ts";
import { wall } from "./ops/fibers.ts";
import { answerHeapRequests, heapCommand } from "./ops/heap.ts";
import { timeFiles, timeProcesses } from "./ops/file-waits.ts";
import { longestWaits } from "./ops/waits.ts";
import { takeQueries } from "./store/timed.ts";
import { platform } from "./platform/index.ts";
import { keepRunnerIn } from "./platform/processes.ts";
import { becomeOther } from "./ops/restart.ts";
import { RigLive, RigMeshLive, RigSide } from "./rig/main.ts";
import { RigsLive } from "./rigs/module.ts";
import { DevicesLive } from "./devices/module.ts";
import { StatusLive } from "./api/status.ts";

// What reads HOME (the machine's logins, its transcripts) finds the user's home there, where the machine names it
// otherwise (Windows: USERPROFILE).
if (!process.env.HOME && platform.home(process.env)) process.env.HOME = platform.home(process.env);
// An adb server anything here starts (a chat's grant's, one an agent's command brings up) connects by itself to no phone
// it finds on the network: with this machine's key a phone lent to one chat would be in them all.
process.env.ADB_MDNS_AUTO_CONNECT = "0";
// The launcher's malloc setting (native/launcher/src/run.rs) is this process's: read by malloc as it started, it goes
// no further, to the agents and their tools.
delete process.env.MallocSpaceEfficient;
// Node tries a host's addresses one after another and gives up on each after this long, not keeping it going while the
// next is tried: its 250 ms is less than a connect over a slow line takes (a Tailscale exit across an ocean, IPv6 not
// reached), so every address failed and the station never reached still.fail cloud (user's 128, 2026-11-03). A
// family that is not there fails at once anyway; this only waits longer on one that says nothing. For the presence
// socket and every fetch alike, which take this default.
setDefaultAutoSelectFamilyAttemptTimeout(2_000);

const args = process.argv.slice(2);
const data = dataDir(args);
const command = args.find((a, i) => !a.startsWith("--") && !(i > 0 && args[i - 1].startsWith("--") && args[i - 1] !== "--with-parent"));
/// Flags that take a value: what follows them is no command's argument.
const VALUED = ["--data", "--provider", "--lock", "--rig", "--workspace"];
/// How often the main thread's longest hold is looked at, and from how long a hold is said.
const HELD_EVERY_MS = 10_000;
const HELD_MS = 1_000;

// What it says on this machine is in the station's language (config.json `language`).
try {
  const config = process.env.STILLFAIL_CONFIG || join(data, "config.json");
  setStationLang(JSON.parse(readFileSync(config, "utf8")).language);
} catch {}

function usage(): never {
  console.error("usage: stillfail-station run --app DIR [--port N] [--data DIR] | enroll <cloud> <token> [--provider stillfail|comma] [--lock HASH] [--rig HASH] [--join | --stay] | status | id | channel [stable|beta] | update [--beta|--stable] --app DIR | lock status | lock reset [--workspace ID] | heap");
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

/// A station's process whose machine is a rig now (made one in the app: sessions/agents.ts; or enrolled as one from
/// another process, `enroll --rig`) gives way to the rig's: its launcher asked to hand over, so its connections end
/// as a restart's do (a station that asks it next reaches the new process, not one gone without a word); with no
/// launcher, it ends for whoever started it to start it again.
const BecameRig = Layer.effectDiscard(
  Effect.gen(function* () {
    const cloud = (yield* ControlPlane).state;
    const { data } = yield* Paths;
    let asked = false;
    yield* Effect.acquireRelease(
      Effect.sync(() => cloud.listen((s) => {
        if (s?.rig === undefined || !s.workspace || cloud.removed() || asked) return;
        asked = true;
        log.warn("station", "this machine is a rig now: the station's process gives way to the rig's");
        becomeOther(data);
      })),
      (off) => Effect.sync(off),
    );
  }),
);

function run() {
  const app = flag(args, "--app");
  if (!app) usage();
  // Read the essential files before telling the launcher this process is ready. In particular, do not start with
  // defaults when another program has made config.json unreadable.
  const settings = new ConfigFile(data);
  settings.watch();
  readState(data);
  const control = launcher(args);
  // Runners (agents', jobs') from copies under the data directory on Windows, out of reach of the app's installer.
  keepRunnerIn(join(data, "run", "bin"));
  // Error lines to still.fail's error tracking, while config.json says so (telemetry.errors) and the build has a key.
  // The station's id as cloud.json says it, held here: read once before the station serves, then as the control plane's
  // state says it changed (`main`). Read from the disk at each of the log's batches (every 5 s), a file of 3 KB held the
  // main thread a second at a time on a station whose disk was kept busy (2026-11-02).
  let stationKey: string | null = null;
  try {
    stationKey = JSON.parse(readFileSync(join(data, "mesh", "cloud.json"), "utf8")).station ?? null; // sync: before it serves
  } catch {}
  const stationId = () => stationKey;
  const reports = new ErrorReports({
    key: builtKey(join(app, "dist", "admin")),
    enabled: () => settings.raw()?.telemetry?.errors === true,
    station: stationId,
  });
  hearErrors((line, error) => reports.report(line, error));
  // Every line to still.fail, scrubbed, unless config.json turns it off (telemetry.logs: false); sent once the mesh is up.
  stationLog.configure({ enabled: () => settings.raw()?.telemetry?.logs !== false, station: stationId, version });
  hearLines((line) => stationLog.add(line));
  // A lost station's chats brought here to take back (replica/restore.ts): put in before the store opens.
  const beforeStore = () => takeBackSoon(data, join(data, "stillfail.db"), wall.now()).then(
    (restored) => { if (restored !== null) log.info("copies", "a lost station's chats taken back", { station: restored.origin, from: restored.from }); },
    (e: Error) => log.error("copies", "a lost station's chats not taken back", { error: e.message }),
  );
  const paths = Layer.succeed(Paths)({ data, app, beforeStore });
  // still.fail Helper, one for the screens and the drive, and one look at its grants.
  const base = Layer.mergeAll(Key.layer, ReadersAndStore, MeshNative.layer, Up.layer, ScreenRegistry.layer.pipe(Layer.provideMerge(Grants.layer), Layer.provideMerge(Helper.layer))).pipe(Layer.provideMerge(Previous.layer), Layer.provideMerge(paths));
  const parts = ControlPlane.layer.pipe(Layer.provideMerge(base));
  // A rig (a station that only runs tasks: cloud.json's `rig`, written by `enroll --rig`) is another program of the same release: of a station's
  // parts only what another station asks of it (rig/main.ts). What a machine is, is read once, as it starts; enrolled
  // as the other meanwhile, the process ends and the launcher starts it again as that.
  const asRig = readState(data)?.rig !== undefined;
  const rigStation = Layer.mergeAll(RigMeshLive, Loopback(control), AwakeLive, CheckpointsLive).pipe(
    Layer.provideMerge(RigLive(control)),
    Layer.provideMerge(RigSide.layer),
    Layer.provideMerge(AdminHost.layer),
    Layer.provideMerge(StationConfig.layer),
    Layer.provideMerge(Peers.layer),
    Layer.provideMerge(MeshSide.layer),
    Layer.provideMerge(Parts.layer),
    Layer.provideMerge(parts),
  );
  const station = Layer.mergeAll(MeshLive, Loopback(control), StatusLive, AwakeLive, CheckpointsLive, BecameRig).pipe(
    // The station's parts in its own process (parts.ts), made before the mesh answers anyone: each says what it adds.
    Layer.provideMerge(Layer.mergeAll(VaultLive, AdbLive, BrowserLive, LinksLive, FeedbackLive, AgentHomeLive, LoginsLive, DriveTransfersLive, UsageLive, ElevationLive, ResourcesLive, SearchLive, SlackLive, FeishuLive, CommaLive, WorkspaceConnectsLive, ModelsLive, RigsLive, DevicesLive, CopiesLive)),
    Layer.provideMerge(AdminApi.layer),
    Layer.provideMerge(AgentsLive(control)),
    // The drive, the admin API's: the platform's, before the agents.
    Layer.provideMerge(StationDrive.layer),
    Layer.provideMerge(HelperFolders.layer),
    Layer.provideMerge(Events.layer),
    Layer.provideMerge(AdminHost.layer),
    // The station's browser, its tabs screens.
    Layer.provideMerge(Browser.layer),
    // config.json, what is the station's own, and the process before this one: the platform's, for every part.
    Layer.provideMerge(Own.layer),
    Layer.provideMerge(StationConfig.layer),
    // The requests between the stations of the workspace (mesh/bus.ts): the mesh attaches them, the parts answer.
    Layer.provideMerge(Peers.layer),
    // What the mesh and the agents' side share, each filling in its own (services.ts MeshSide).
    Layer.provideMerge(MeshSide.layer),
    // Where devices come from besides the whole stations' (services.ts DeviceSources): the rigs' and phones' parts.
    Layer.provideMerge(DeviceSources.layer),
    Layer.provideMerge(Parts.layer),
    // The agents' side, once made (the admin API asks for it as a request comes).
    Layer.provideMerge(AgentsSide.layer),
    Layer.provideMerge(parts),
  );
  // What the parts hold only in memory (the vault's grants), carried over to the next process at a handover.
  let carry = () => {};
  const running = Effect.gen(function* () {
    yield* SubscriptionRef.set(yield* Up, true);
    const stationParts = yield* Parts;
    const plane = yield* ControlPlane;
    stationKey = plane.state.state?.station ?? null;
    plane.state.listen((s) => void (stationKey = s?.station ?? null));
    control.carried((what) => stationParts.takeUp(what));
    carry = () => control.carry(stationParts.carried());
    control.ready(version());
    log.info("station", asRig ? "rig up" : "station up", { version: version(), data });
    // Where the memory goes, in MB: the main thread's (and resident), and each reader's heap. Every ten minutes, or
    // every ten seconds with STILLFAIL_MEMLOG (for measuring).
    const readers = yield* Readers;
    // `stillfail heap`: a snapshot of this thread's heap, asked for from the command line.
    answerHeapRequests(data);
    // The main thread held (a query of seconds, a long parse): said as it is let go, with how long (`heldMs`, the
    // longest one hold of the window). Every device's requests wait meanwhile. What may have held it is said two ways,
    // never to be added up against `heldMs`:
    // - the longest single wait of each kind in the window (`longestQueryMs`, `longestFileMs`, `longestProcessMs`,
    //   `gcLongestMs`): one of these as long as the hold was that hold, or in it;
    // - all of the window's (`window*`, over `windowMs`, some 10 s): the process's CPU (all its threads') and this
    //   thread's own, its garbage collected, pages of its memory read back from the disk, the times the system took its
    //   CPUs from it (`windowSwitches`: another process's work wanted them), its synchronous calls of node:fs and its
    //   statements (store/timed.ts) and the processes it waited on (ops/file-waits.ts), many short ones as much as a
    //   long one, with the longest by who made them.
    // Its own CPU near `heldMs` is work of its own; neither that nor a wait near it: it was not given a CPU, or waited on
    // what is timed nowhere.
    const files = timeFiles();
    const processes = timeProcesses();
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
    let ownCpu = process.threadCpuUsage();
    let usage = process.resourceUsage();
    let sampled = wall.now();
    wall.every(HELD_EVERY_MS, () => { // timer: a sample of this thread
      const ms = held.max / 1e6;
      const now = wall.now();
      const used = process.cpuUsage(cpu);
      const own = process.threadCpuUsage(ownCpu);
      const nowUsage = process.resourceUsage();
      const waited = files.take();
      const spawned = processes.take();
      const queried = takeQueries();
      if (ms >= HELD_MS) {
        log.warn("station", "the main thread was held", {
          heldMs: Math.round(ms),
          longestQueryMs: Math.round(queried.longest), longestFileMs: Math.round(waited.longest), longestProcessMs: Math.round(spawned.longest), gcLongestMs: Math.round(gc.longest),
          windowMs: now - sampled,
          windowCpuMs: Math.round((used.user + used.system) / 1000), windowThreadCpuMs: Math.round((own.user + own.system) / 1000),
          windowGcMs: Math.round(gc.ms), windowPageFaults: nowUsage.majorPageFault - usage.majorPageFault,
          windowSwitches: nowUsage.involuntaryContextSwitches - usage.involuntaryContextSwitches,
          windowFilesMs: Math.round(waited.ms), windowFiles: waited.calls, ...(waited.by.size > 0 ? { waitedOn: longestWaits(waited) } : {}),
          windowQueriesMs: Math.round(queried.ms), windowQueries: queried.calls, ...(queried.by.size > 0 ? { queriedBy: longestWaits(queried) } : {}),
          windowProcessesMs: Math.round(spawned.ms), windowProcesses: spawned.calls, ...(spawned.by.size > 0 ? { spawnedBy: longestWaits(spawned) } : {}),
        });
      }
      held.reset();
      cpu = process.cpuUsage();
      ownCpu = process.threadCpuUsage();
      usage = nowUsage;
      sampled = now;
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
  });
  const main = asRig ? running.pipe(Effect.provide(rigStation)) : running.pipe(Effect.provide(station));
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

async function commandMain() {
switch (command) {
  case "run":
    run();
    break;
  case "enroll": {
    const [, origin, token] = positionals(args, VALUED);
    const provider = (flag(args, "--provider") ?? "stillfail") as Provider;
    const lock = flag(args, "--lock");
    // A rig (a station that only runs tasks): its person's own lock's hash, which the command that adds it names.
    const rig = flag(args, "--rig");
    if (!origin || !token || !PROVIDERS.includes(provider) || (lock !== undefined && !/^[0-9a-f]{64}$/.test(lock)) || (rig !== undefined && !/^[0-9a-f]{64}$/.test(rig))) usage();
    // One more workspace, staying in those it is in: at the control plane it is enrolled with.
    // --stay (the installers'): joins when the station is in a workspace already, else enrolls; at the control plane it
    // is enrolled with whatever host the command names (the test channel's app.youdid.wtf is still.fail's API too), a
    // token that plane does not know refused there.
    // (a rig is in one workspace: it enrolls, which refuses a machine that is a station now, and the other way round)
    const stay = rig === undefined && !isRig(data) && !args.includes("--join") && args.includes("--stay") && staysIn(data);
    if (rig === undefined && (args.includes("--join") || stay)) {
      const now = readState(data);
      if (!stay && now !== null && now.origin !== origin.replace(/\/+$/, "")) {
        console.error(`this station is enrolled at ${now.origin}; it joins workspaces there only`);
        process.exit(1);
      }
      // On this machine: its person may set aside a lock kept here for that workspace by naming another.
      const joined = await joinWorkspace(data, token, lock, { atMachine: true }).catch((error) => {
        if (stay) console.error(`this station is in workspace ${now?.workspace_name || now?.workspace} (${now?.origin}): it was to join this one beside it, which did not go through. To move it here instead, remove it from that workspace first.`);
        throw error;
      });
      console.log(tr(stationLang(), "station.cli.joined", { workspace: joined.workspace_name, name: joined.name, id: loadKey(data).id.slice(0, 12) }));
      // A locked workspace: its owner confirms this station by its code, as one enrolled with `--lock`.
      if (lock !== undefined) console.log(tr(stationLang(), "station.cli.lock.pending", { code: shortCode(loadKey(data).id) }));
      break;
    }
    await enroll(data, origin.replace(/\/+$/, ""), token, provider, lock, rig);
    break;
  }
  // The workspace lock on this machine: what is pinned, or taking it away.
  case "lock": {
    const [, what] = positionals(args, VALUED);
    const workspace = flag(args, "--workspace");
    if ((what !== "status" && what !== "reset") || (workspace !== undefined && what !== "reset")) usage();
    console.log(lockCommand(data, what, workspace));
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
}

try {
  await commandMain();
} catch (error) {
  if (!(error instanceof InvalidJsonFile)) throw error;
  // A previous launcher only reports the exit code; the new release's installer reads this alongside that report.
  // No file contents are written here. Its installer clears the previous attempt's report before each handover.
  if (command === "run" && (flag(args, "--launcher-pipe") || flag(args, "--launcher-fds"))) {
    try { writeFileSync(join(data, "run", "handoff-error"), error.message + "\n", { mode: 0o600 }); } catch {}
  }
  console.error(error.message);
  process.exitCode = 1;
}
