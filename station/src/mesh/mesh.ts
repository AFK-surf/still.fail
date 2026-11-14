// The station on the mesh, once it is in a workspace (cloud.json there): its endpoint, its relays, its presence at
// its control plane, members' connections, and the control plane's gateways' (the device tools, mesh/tools.ts). Everything here lives in the layer's scope: stopping the station closes
// the endpoint and every connection and loop it started.
import { Cause, Effect, FiberSet, Layer, Option, Stream } from "effect";
import { log } from "../ops/log.ts";
import { stationLog } from "../ops/log-export.ts";
import { AdminApi, ControlPlane, Events, Key, MeshNative, MeshSide, Own, Parts, Peers, Previous, ScreenRegistry, StationConfig, Store, Up } from "../services.ts";
import { DeviceTools, accessOf } from "../device/tools.ts";
import { TOOLS_ALPN, adminSessions, presenceTools, serveTools } from "./tools.ts";
import { PEER_ALPN, PEER_BYTES_ALPN, peerCall, servePeer } from "./peer.ts";
import { DeviceRefused, PEER_HTTP_ALPN, PeerHttp, serveHttp } from "./peer-http.ts";
import { followLock } from "./lock-sync.ts";
import { followPersons } from "./person-sync.ts";
import { tellLocks } from "./lock-events.ts";
import { followMarks, stationMarksOf, tellMarks } from "./station-marks.ts";
import { followWays, tellWays, waysOf } from "./ways.ts";
import { personChainsOf } from "./serve.ts";
import { deviceBuildsOf } from "./device-builds.ts";
import { Traces } from "./traces.ts";
import { SubscriptionRef } from "effect";
import { keepRelays } from "./relays.ts";
import { ALPN, serve } from "./serve.ts";
import { accept } from "./accept.ts";
import { congestionOf } from "./settings.ts";
import { bindStation, type Endpoint } from "./native.ts";
import { lanAddrs, tailnetAddrs } from "./lan.ts";
import { Superseded } from "./superseded.ts";
import { Storms } from "./storms.ts";
import { Fibers } from "../ops/fibers.ts";

export const MeshLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const plane = yield* ControlPlane;
    const cloud = plane;
    const store = yield* Store;
    const key = yield* Key;
    const native = yield* MeshNative;
    const admin = yield* AdminApi;
    const up = yield* Up;
    // What it shares with the agents' side (services.ts MeshSide), filled by the one that has it.
    const side = yield* MeshSide;
    const own = yield* Own;
    const previous = yield* Previous;
    const peers = yield* Peers;
    const parts = yield* Parts;
    const config = yield* StationConfig;
    const screens = yield* ScreenRegistry;
    const events = yield* Events;
    const run = Effect.gen(function* () {
      // Not in a workspace yet: on the mesh once `enroll` writes cloud.json.
      if (!cloud.state.state) yield* cloud.changes.pipe(Stream.filter(() => cloud.state.state !== null), Stream.runHead);
      // The launcher starts this process before stopping the old one. Its fixed UDP socket cannot be shared;
      // wait in this background fiber (not layer construction, which must signal ready to start the handover).
      // An unset address or port 0 gets a fresh port and can bind alongside the old process.
      // (Kept by the front, the endpoint is bound once and stays: taken over as it is.)
      if (!process.env.STILLFAIL_MESH_FRONT && Number(process.env.STILLFAIL_MESH_BIND_ADDR?.split(":").at(-1)) > 0) {
        yield* Effect.promise(() => previous.gone);
      }
      // The order is the one the endpoint prefers: a station asking for web requests offers the station transport's
      // protocol after it (to tell a station from before it), and is to be answered in the first (peer-http.ts).
      const bind = Effect.tryPromise(() => bindStation(native, { secretKey: key.seed, alpns: [ALPN, PEER_HTTP_ALPN, PEER_BYTES_ALPN, PEER_ALPN, TOOLS_ALPN], relayUrls: cloud.state.relays(), discovery: process.env.STILLFAIL_NO_DISCOVERY !== "1", congestion: congestionOf(config.raw()) }));
      const acquire = Effect.acquireRelease(
        bind,
        // iroh closes gracefully, waiting on every connection (the keepers' too): up to ~12 s. A station stopping or
        // handing over doesn't wait that long: a second, then it is gone (clients reconnect, as they do anyway).
        (endpoint) => Effect.ignore(Effect.timeoutOption(Effect.promise(() => endpoint.close()), "1 second")),
      );
      let endpoint = yield* acquire.pipe(Effect.catch((error) => {
        // A front introduced during this handover has no endpoint yet: the old Node may still hold its fixed port.
        // A front already holding the endpoint can bind at once, keeping its connections across the handover.
        if (!process.env.STILLFAIL_MESH_FRONT || previous.pid === null || !(Number(process.env.STILLFAIL_MESH_BIND_ADDR?.split(":").at(-1)) > 0)) return Effect.fail(error);
        log.warn("mesh", "the front could not bind; trying again after the previous station exits", { error: String(error.cause ?? error) });
        return Effect.succeed(null);
      }));
      if (!endpoint) {
        // Wait outside acquireRelease's uninterruptible acquisition so shutdown never waits on the old process.
        yield* Effect.promise(() => previous.exited);
        endpoint = yield* acquire;
      }
      log.info("mesh", "mesh listening", { station: endpoint.id(), workspace: cloud.state.state!.workspace_name, sockets: endpoint.sockets() });
      // The advanced network settings as they are saved, on the running endpoint (no restart needed).
      yield* Effect.acquireRelease(Effect.sync(() => applyNetwork(endpoint, config)), (off) => Effect.sync(off));
      // What other stations are told of this one's relay (jobs/load.ts), while it is on the mesh.
      yield* Effect.acquireRelease(Effect.sync(() => side.net.attach(() => endpoint.home())), (off) => Effect.sync(off));
      yield* Effect.forkScoped(keepRelays(endpoint, side.net));
      // Online at the cloud only once a relay can reach the station: a device that saw "online" and connected before
      // the relay link was up had its first packets dropped (~3 s of retransmits). Its members' connections are taken
      // meanwhile (below): those that reach it already (on its LAN, or by a relay it is on) are not kept waiting. Taken
      // only after this, every device lost the station some 7 s at each update (a station, 2026-10-24: its relay link took
      // that long, 32 updates that day).
      yield* Effect.forkScoped(
        Effect.gen(function* () {
          const online = yield* Effect.timeoutOption(Effect.promise(() => endpoint.online()), "15 seconds");
          if (Option.isNone(online)) log.warn("mesh", `no relay link after 15 s; going online at ${plane.spec().name} anyway`);
          yield* plane.presence;
        }),
      );
      // The workspace's other stations: asked through this endpoint, their tasks stopped once they are not in it.
      // And the stations of other workspaces chats are shared with or from (xshare/index.ts).
      const call = peerCall(endpoint, cloud.state, undefined, { reaches: (target, workspace) => side.outside?.reaches(target, workspace) === true });
      peers.attach(call);
      // The agents' door's way to the other stations' web services (peer-http.ts).
      yield* Effect.acquireRelease(
        Effect.sync(() => {
          const http = new PeerHttp(endpoint, cloud.state);
          side.peers.route = http;
          return http;
        }),
        (http) => Effect.sync(() => {
          if (side.peers.route === http) side.peers.route = null;
          http.close();
        }),
      );
      // The workspace lock, kept level with the other stations it names (lock-sync.ts).
      yield* Effect.acquireRelease(
        Effect.sync(() => followLock(cloud.state, call)),
        (stop) => Effect.sync(stop),
      );
      // Each person's own lock, kept level with the stations of the workspaces it was heard in (person-sync.ts), and
      // the locks' changes told to the devices (lock-events.ts).
      yield* Effect.acquireRelease(
        Effect.sync(() => followPersons(cloud.state, personChainsOf(cloud.state), call)),
        (stop) => Effect.sync(stop),
      );
      yield* Effect.acquireRelease(
        Effect.sync(() => tellLocks(cloud.state, personChainsOf(cloud.state), (event, data, of, to) => events.tell(event, data, of, to))),
        (stop) => Effect.sync(stop),
      );
      // The workspaces' ways (mesh/ways.ts): kept level with their other stations, and their changes told to the devices.
      yield* Effect.acquireRelease(
        Effect.sync(() => followWays(waysOf(cloud.state), call)),
        (stop) => Effect.sync(stop),
      );
      yield* Effect.acquireRelease(
        Effect.sync(() => tellWays(waysOf(cloud.state), (event, data, of, to) => events.tell(event, data, of, to))),
        (stop) => Effect.sync(stop),
      );
      // The stations' names and marks (mesh/station-marks.ts): a copy kept by each station of a workspace, and their
      // changes told to the devices.
      yield* Effect.acquireRelease(
        Effect.sync(() => followMarks(stationMarksOf(cloud.state), call)),
        (stop) => Effect.sync(stop),
      );
      yield* Effect.acquireRelease(
        Effect.sync(() => tellMarks(stationMarksOf(cloud.state), (event, data, of, to) => events.tell(event, data, of, to))),
        (stop) => Effect.sync(stop),
      );
      const connections = yield* FiberSet.make();
      // The mesh's spans, when the config turns traces on (read at start, as the Rust does).
      const traces = yield* Effect.acquireRelease(
        Effect.sync(() => new Traces(config.raw()?.telemetry?.traces === true)),
        (traces) => Effect.promise(() => traces.close()),
      );
      if (traces.enabled) traces.exportTo((spans) => Effect.runPromise(plane.traces(spans)));
      // The station's log, waiting since it started (ops/log-export.ts).
      stationLog.sendWith((body) => Effect.runPromise(plane.logs(body)));
      // (the devices' builds kept in the store, made before the first request asks for them)
      deviceBuildsOf(cloud.state, store);
      const members = { cloud: cloud.state, admin, up: () => SubscriptionRef.getUnsafe(up), streams: (head: any) => parts.streamOf(head), screens, traces, accepted: plane.credential, lan: () => lanAddrs(endpoint.sockets()), tailnet: () => tailnetAddrs(endpoint.sockets()), connected: () => parts.connected() };
      // The control plane's gateways: the device tools, as far as the station's own setting lets them.
      const device = yield* Effect.acquireRelease(
        Effect.sync(() =>
          new DeviceTools({
            // Never reachable: the station's data (its key, cloud.json, the profiles' homes), its config, the machine's
            // runtime logins.
            protect: () => own.paths(),
            sessions: adminSessions(
              () => admin,
              () => store,
              () => side.runtimes(),
              () => cloud.state.state?.workspace ?? "",
              endpoint.id(),
            ),
          }),
        ),
        (tools) => Effect.sync(() => tools.close()),
      );
      const gateways = { cloud: cloud.state, tools: device, access: () => accessOf(config.raw()), enabled: () => plane.spec().tools };
      // The same tools for requests Comma pushes on the presence socket.
      cloud.state.toolCalls = presenceTools(gateways);
      yield* Effect.addFinalizer(() => Effect.sync(() => (cloud.state.toolCalls = null)));
      // A member's device connecting again: its connections left by a process that died are found and closed.
      const superseded = new Superseded();
      // Connections trading only packets that carry nothing, thousands a second: said, and closed (storms.ts).
      const { storms } = yield* Effect.acquireRelease(
        Effect.sync(() => {
          const fibers = new Fibers("mesh");
          const storms = new Storms(fibers);
          storms.start();
          return { storms, fibers };
        }),
        ({ fibers }) => Effect.promise(() => fibers.close()),
      );
      // Its connections (accept.ts), each served by its protocol's own. Their fibers are of the set made above, before
      // the traces, the device tools and the storms' watch: as the station stops they end after those have.
      yield* accept(endpoint, {
        connections,
        arrived: (conn) => {
          storms.watch(conn);
          if (conn.alpn().equals(ALPN)) void superseded.arrived(conn);
        },
        serve: (conn) =>
          conn.alpn().equals(PEER_BYTES_ALPN) || conn.alpn().equals(PEER_ALPN) ? servePeer(conn, cloud.state, peers)
          : conn.alpn().equals(PEER_HTTP_ALPN) ? serveHttp(conn, cloud.state, {
              forwarded: (port) => side.forwarded(port),
              device: (peer, workspace, session, device, probe) => side.device == null ? Promise.reject(new DeviceRefused(404, "no devices here yet")) : side.device(peer, workspace, session, device, probe),
            })
          : conn.alpn().equals(TOOLS_ALPN) ? serveTools(gateways, conn)
          : serve(members, conn),
        closing: "station stopping",
      });
    });
    yield* Effect.forkScoped(Effect.scoped(run).pipe(Effect.tapCause((cause) => Effect.sync(() => {
      if (!Cause.hasInterruptsOnly(cause)) log.error("mesh", "mesh stopped", { error: Cause.pretty(cause) });
    }))));
  }),
);

/// Follows the saved network settings on a running endpoint: a congestion controller chosen applies to the connections
/// made from then on. Gives what stops following.
export function applyNetwork(endpoint: Pick<Endpoint, "setCongestion">, config: { raw(): any; listen(f: (raw: any) => void): () => void }): () => void {
  let congestion = congestionOf(config.raw());
  return config.listen((raw) => {
    const nextCongestion = congestionOf(raw);
    if (nextCongestion !== congestion) {
      congestion = nextCongestion;
      try { endpoint.setCongestion?.(congestion); }
      catch (e) { log.warn("mesh", "congestion controller not changed", { error: (e as Error).message }); }
      log.info("mesh", "congestion controller for new connections", { congestion });
    }
  });
}
