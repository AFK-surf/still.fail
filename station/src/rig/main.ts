// A rig's process (a station that only runs tasks, 2026-11-10): the composition root of a machine that joined its workspace as a rig
// (`enroll --rig`, cloud.json's `rig`), in the place of the station's (main.ts). The same release, launcher and
// updates; of a station's parts only those that are asked by another station: the mesh's station transport (no
// members' links, no gateway's tools), the jobs, the tasks other stations send (jobs/remote.ts), a command run with
// a secret a station sends along (vault/incoming.ts), and the rig's own say over who may use it (rig/module.ts). No
// agents, sessions, chats, connects, accounts, vault or drive are made here: there is nothing in this process that
// could run one.
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { Cause, Context, Effect, Layer, Option, Stream, SubscriptionRef } from "effect";
import { Jobs, notifyEndpoint, screenEndpoint } from "../jobs/jobs.ts";
import { measure } from "../jobs/load.ts";
import { liveMemory } from "../jobs/memory.ts";
import { Remote, followRoster } from "../jobs/remote.ts";
import { accept } from "../mesh/accept.ts";
import { lanAddrs } from "../mesh/lan.ts";
import { applyNetwork } from "../mesh/mesh.ts";
import { bindStation } from "../mesh/native.ts";
import { PEER_ALPN, PEER_BYTES_ALPN, peerCall, servePeer } from "../mesh/peer.ts";
import { DeviceRefused, PEER_HTTP_ALPN, serveHttp } from "../mesh/peer-http.ts";
import { keepRelays } from "../mesh/relays.ts";
import { congestionOf } from "../mesh/settings.ts";
import { DISK_EVERY_MS, DISK_LOW_BYTES, diskFree } from "../ops/disk.ts";
import { Fibers } from "../ops/fibers.ts";
import { mcpPortFile, ownData, portsToTry, rememberedMcpPort } from "../ops/files.ts";
import type { Control } from "../ops/launcher.ts";
import { log } from "../ops/log.ts";
import { becomeOther } from "../ops/restart.ts";
import { stationLog } from "../ops/log-export.ts";
import { AdminHost, ControlPlane, Key, MeshNative, MeshSide, Paths, Peers, Previous, StationConfig, Store, Up } from "../services.ts";
import { type AgentsDoor, openAgentsDoor } from "../tools/http.ts";
import { McpEndpoint } from "../tools/mcp.ts";
import { makeUpdates } from "../updates/updates.ts";
import { Incoming } from "../vault/incoming.ts";
import { Proxy } from "../vault/proxy.ts";
import { Rig } from "./module.ts";

/// The rig, once made: what the mesh asks of it.
export class RigSide extends Context.Service<RigSide, { current: Rig | null }>()("stillfail/RigSide") {
  static readonly layer = Layer.sync(RigSide, () => ({ current: null }));
}

/// `remote:<workspace>:<station>:<session>`: whose a task's job is (jobs/remote.ts `owner`). A session's key has
/// colons of its own; a workspace's id and a station's have none.
const ownerOf = (workspace: string, station: string, session: string) => `remote:${workspace}:${station}:${session}`;
function owned(sessionKey: string): { workspace: string; station: string; session: string } | null {
  const m = /^remote:([^:]*):([^:]*):(.*)$/s.exec(sessionKey);
  return m === null ? null : { workspace: m[1]!, station: m[2]!, session: m[3]! };
}

/// What a rig runs and answers: the jobs, other stations' tasks, its grants, its own updates, and the door its jobs
/// reach it by (`stillfail-job`).
export const RigLive = (control: Control) =>
  Layer.effectDiscard(
    Effect.gen(function* () {
      const { data, app } = yield* Paths;
      const store = yield* Store;
      const plane = yield* ControlPlane;
      const cloud = plane.state;
      const config = yield* StationConfig;
      const host = yield* AdminHost;
      const up = yield* Up;
      const bus = yield* Peers;
      const previous = (yield* Previous).gone;
      const side = yield* RigSide;
      const net = (yield* MeshSide).net;
      const time = new Fibers("rig");
      const run = join(data, "run");

      const jobs = new Jobs({
        store, data,
        // No agent here to tell: what a task says is its record's, read by the station that sent it.
        notify: () => {},
        link: () => null,
      });
      const remote = new Remote({ data, store, jobs, notify: () => {}, bus });
      const rig = new Rig({
        data, cloud, bus, fibers: time,
        busy: (workspace, station, session) => store.runningJobsAtLeast(ownerOf(workspace, station, session), 1),
        stop: async (workspace, station, session) => {
          for (const id of store.upJobIds(ownerOf(workspace, station, session))) {
            await jobs.stop(id).catch((error) => log.warn("rig", "a task of a chat that lost this rig was not stopped", { job: id, error: (error as Error).message }));
          }
        },
        running: () => store.jobsRunning().flatMap((j) => owned(j.sessionKey) ?? []),
      });
      side.current = rig;
      remote.setDescribed(() => rig.described());
      const gpus = host.gpus;
      void gpus.read().catch(() => null);
      remote.setLoad(() =>
        measure({
          host, gpus,
          running: () => {
            const j = store.runningJobs();
            return { remoteTasks: j.remote, jobs: j.jobs, services: j.services, turns: 0 };
          },
          relay: () => net.seen(),
        }),
      );
      // A command a station sends to run with a secret one of its chats was granted: run here, the secret in no file.
      const runs = new Incoming({ proxy: new Proxy(join(data, "vault"), () => time.now()), now: () => time.now(), ask: (station, request) => bus.ask(station, request), workOf: (ws, peer, session) => remote.work(ws, peer, session) });
      bus.on("vault.", (peer, request, workspace) => runs.heard(peer, workspace ?? cloud.home() ?? "", request));
      // Tasks of stations no longer in the workspace stop, as on a station.
      let roster: (() => void) | null = null;
      bus.whenAttached(() => void (roster = followRoster(cloud, remote, config)));

      const memory = liveMemory({ data, store, jobs, notify: () => {}, clock: time.clock });
      memory.start();

      // Its own release, read at start and as the cloud says one is out; updated by itself while nothing runs.
      const updates = makeUpdates({ app, data, config, origin: () => plane.releaseBase(), running: () => 0, stationOnly: true });
      updates.start();
      plane.told("release", () => void updates.check().catch((error) => log.warn("updates", "the release not read", { error: String(error) })));
      control.on("hup", () => updates.answerChannelAsk());

      // In its workspace or out of it, as cloud.json says: out of it, what it runs for the stations stops.
      const bound = () => rig.self() !== null;
      let inWorkspace = bound();
      let giving = false;
      const follow = async () => {
        // No longer a rig (enrolled again as a station, from another process): this process ends, and the launcher
        // starts the station's in its place.
        if (cloud.state !== null && cloud.state.rig === undefined && cloud.state.workspace && !cloud.removed()) {
          log.warn("rig", "this machine is a station now: the rig's process gives way to the station's");
          if (!giving) becomeOther(data);
          giving = true;
          return;
        }
        const now = bound();
        if (now === inWorkspace) return;
        inWorkspace = now;
        if (now) jobs.relaunch();
        else await jobs.stopAll(cloud.removed() ? "the rig was removed from its workspace" : "the rig is in no workspace");
      };
      yield* plane.changes.pipe(Stream.runForEach(() => Effect.promise(follow)), Effect.forkScoped);

      // The door its jobs reach it by (`stillfail-job notify`, `screen`): this machine's own, with no tool behind it.
      let door: AgentsDoor | null = null;
      const start = async () => {
        await Effect.runPromise(Effect.gen(function* () {
          if (!(yield* SubscriptionRef.get(up))) yield* SubscriptionRef.changes(up).pipe(Stream.filter((now) => now), Stream.runHead);
        }));
        await previous;
        mkdirSync(run, { recursive: true });
        const mcp = new McpEndpoint(() => undefined, []);
        const notified = (authorization: string | undefined, body: Buffer) => notifyEndpoint(jobs, authorization, body);
        const screened = (authorization: string | undefined, body: Buffer) => screenEndpoint(jobs, authorization, body);
        if (control.mcpFd !== undefined) door = await openAgentsDoor({ fd: control.mcpFd }, mcp, notified, () => null, () => [], screened);
        else if (control.ports) door = await openAgentsDoor({ port: 0, shown: control.ports.mcp }, mcp, notified, () => null, () => [], screened);
        else {
          const tries = portsToTry(undefined, rememberedMcpPort(data), 4750, ownData(data));
          for (const [i, port] of tries.entries()) {
            try {
              door = await openAgentsDoor({ port }, mcp, notified, () => null, () => [], screened);
              break;
            } catch (error) {
              if ((error as NodeJS.ErrnoException).code !== "EADDRINUSE" || i === tries.length - 1) throw error;
            }
          }
          writeFileSync(mcpPortFile(data), `{"port":${door!.port}}\n`);
        }
        jobs.setNotifyUrl(door!.url.replace(/\/mcp$/, "/jobs/notify"));
        control.serving("mcp", door!.port);
        if (inWorkspace) jobs.relaunch();
        else if (cloud.removed()) await jobs.stopAll("the rig was removed from its workspace");
      };
      yield* Effect.forkScoped(Effect.promise(() => start().catch((e) => {
        log.error("rig", "the rig did not start", { error: (e as Error).message });
        control.failed(`the rig did not start: ${(e as Error).message}`);
      })));

      // Room made on a disk running low: other stations' mirrors unused the longest go first (jobs/remote.ts).
      const relieving = async () => {
        try {
          if (diskFree(data) < DISK_LOW_BYTES) await remote.relieve(time.now());
        } catch (error) {
          log.warn("rig", "making room on the disk failed", { error: (error as Error).message });
        }
        // A sample of this machine (its disk), looked at again later.
        time.after(DISK_EVERY_MS, relieving);
      };
      time.after(DISK_EVERY_MS, relieving);

      // Nothing here to hand over turn by turn: drained at once.
      control.on("drain", () => {
        writeFileSync(join(run, "drained"), "idle\n");
        control.drained("idle");
      });

      yield* Effect.addFinalizer(() =>
        Effect.promise(async () => {
          side.current = null;
          roster?.();
          await door?.close(5_000);
          await memory.close();
          await rig.close();
          await remote.close();
          await jobs.shutdown();
          await updates.close();
          await time.close();
        }),
      );
    }),
  );

/// A rig on the mesh: its endpoint with the station transport alone, its presence at the control plane, and the
/// workspace's stations' connections, each request of theirs through the rig's grants.
export const RigMeshLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const plane = yield* ControlPlane;
    const cloud = plane.state;
    const key = yield* Key;
    const native = yield* MeshNative;
    const previous = yield* Previous;
    const peers = yield* Peers;
    const config = yield* StationConfig;
    const side = yield* MeshSide;
    const rig = yield* RigSide;
    const run = Effect.gen(function* () {
      if (!cloud.state) yield* plane.changes.pipe(Stream.filter(() => cloud.state !== null), Stream.runHead);
      if (Number(process.env.STILLFAIL_MESH_BIND_ADDR?.split(":").at(-1)) > 0) yield* Effect.promise(() => previous.gone);
      const endpoint = yield* Effect.acquireRelease(
        Effect.promise(() => bindStation(native, { secretKey: key.seed, alpns: [PEER_HTTP_ALPN, PEER_BYTES_ALPN, PEER_ALPN], relayUrls: cloud.relays(), discovery: process.env.STILLFAIL_NO_DISCOVERY !== "1", congestion: congestionOf(config.raw()) })),
        (endpoint) => Effect.ignore(Effect.timeoutOption(Effect.promise(() => endpoint.close()), "1 second")),
      );
      log.info("mesh", "rig listening", { rig: endpoint.id(), workspace: cloud.state!.workspace_name, sockets: endpoint.sockets(), lan: lanAddrs(endpoint.sockets()) });
      yield* Effect.acquireRelease(Effect.sync(() => applyNetwork(endpoint, config)), (off) => Effect.sync(off));
      yield* Effect.acquireRelease(Effect.sync(() => side.net.attach(() => endpoint.home())), (off) => Effect.sync(off));
      yield* Effect.forkScoped(keepRelays(endpoint, side.net));
      yield* Effect.forkScoped(
        Effect.gen(function* () {
          const online = yield* Effect.timeoutOption(Effect.promise(() => endpoint.online()), "15 seconds");
          if (Option.isNone(online)) log.warn("mesh", `no relay link after 15 s; going online at ${plane.spec().name} anyway`);
          yield* plane.presence;
        }),
      );
      // What it tells the stations (rig/module.ts), and nothing it asks of them.
      peers.attach(peerCall(endpoint, cloud));
      stationLog.sendWith((body) => Effect.runPromise(plane.logs(body)));
      yield* accept(endpoint, {
        serve: (conn) =>
          conn.alpn().equals(PEER_HTTP_ALPN)
            ? serveHttp(conn, cloud, {
                allowed: (peer, workspace) => rig.current?.stationRefusal(peer, workspace) ?? "the rig is starting",
                device: (peer, workspace, session, device, probe) => rig.current === null ? Promise.reject(new DeviceRefused(503, "the rig is starting")) : rig.current.device(peer, workspace, session, device, probe),
              })
            : servePeer(conn, cloud, peers),
        closing: "rig stopping",
      });
    });
    yield* Effect.forkScoped(Effect.scoped(run).pipe(Effect.tapCause((cause) => Effect.sync(() => {
      if (!Cause.hasInterruptsOnly(cause)) log.error("mesh", "mesh stopped", { error: Cause.pretty(cause) });
    }))));
  }),
);
