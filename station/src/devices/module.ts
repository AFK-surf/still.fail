// The workspace's devices as a part of the station (设备, 2026-11-10; parts.ts): one list of what agents use that runs no
// station, each its person's, lent to chats one way. Three kinds of where one is:
//
// - attached to a whole station (registry.ts, kept here when here): open to every chat, as the station is;
// - attached to a station that only runs tasks (rig/grants.ts keeps them; rigs/module.ts carries what its owner
//   signs and asks for a chat's grant): a chat uses one by its owner's grant of it or of the rig, or 免批准;
// - a person's phone, lent by its app (adb/): a chat uses it by their grant.
//
// An agent finds them with device_list and asks with device_use (tool.ts). What it is given is a port of 127.0.0.1 on
// its own station, which only its own processes connect to (adb/door.ts's gate), carried to the device by the station
// it is attached to (connect.ts) over the mesh (mesh/peer-http.ts, a tunnel's `device`).
import { Effect, Layer } from "effect";
import type { Route } from "../api/admin.ts";
import { type Answer, type Request, error, json } from "../api/request.ts";
import { gate } from "../adb/door.ts";
import { runnerId } from "../agents/process.ts";
import { runnerOf } from "../agents/runner.ts";
import { RUNTIME_KINDS } from "../agents/runtime.ts";
import { watchedJobs } from "../jobs/memory.ts";
import { Refused as PeerRefused } from "../mesh/bus.ts";
import { managesStation } from "../mesh/credential.ts";
import { DeviceRefused, nameOf } from "../mesh/peer-http.ts";
import type { DeviceTarget } from "../mesh/peer-forward.ts";
import { wall } from "../ops/fibers.ts";
import { platform } from "../platform/index.ts";
import { ControlPlane, type DeviceEntry, DeviceSources, Events, MeshSide, Parts, Paths, Store } from "../services.ts";
import { Agents } from "../sessions/agents.ts";
import type { Json } from "../store/store.ts";
import { reachDevice } from "./connect.ts";
import { DeviceRegistry, type Kept } from "./registry.ts";
import { deviceTools, reachedAt } from "./tool.ts";

/// Another station asked for its devices answers within this, or is left out of the list (as station_list's).
const ASK_MS = 2000;

export class DeviceAsk extends Error {}

export const DevicesLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const plane = yield* ControlPlane;
    const cloud = plane.state;
    const parts = yield* Parts;
    const store = yield* Store;
    const events = yield* Events;
    const side = yield* MeshSide;
    const sources = yield* DeviceSources;
    const { data } = yield* Paths;
    const { hub, remote, forwards } = yield* Agents;
    const registry = new DeviceRegistry(store.db);
    const self = () => cloud.state?.station ?? "";

    const entryOf = (k: Kept, station: string): DeviceEntry => ({
      id: k.id, name: k.name, kind: k.kind, target: k.target, ...(k.baud !== undefined ? { baud: k.baud } : {}),
      via: "station", station, stationName: nameOf(cloud, station),
      owner: k.owner, ownerEmail: k.owner_email, ownerName: k.owner_name,
      thisChat: "open to every chat of the workspace: device_use gives it at once", hasAccess: "every chat of the workspace (it is on a whole station)",
    });
    /// What the app is told of this station's devices: as kept, with where.
    const listed = (ws: string): Json[] => registry.of(ws).map((k) => ({ ...k, station: self(), stationName: nameOf(cloud, self()) }) as unknown as Json);
    const phones = (ws: string): Json[] => sources.phones?.shown?.(ws) ?? [];
    const tell = (ws: string) => events.tell("devices", { workspace: ws, devices: listed(ws), phones: phones(ws) }, `devices\0${ws}`, { workspace: ws });
    sources.changed = (ws) => {
      for (const w of ws === null ? cloud.memberships().map((m) => m.workspace) : [ws]) tell(w);
    };

    // Another station's chat reaching a device here: a whole station's devices are its workspace's every chat's.
    side.device = async (_peer, workspace, _session, id, probe) => {
      const d = registry.get(workspace, id);
      if (d === null) throw new DeviceRefused(404, "no such device on this station");
      if (probe) return null;
      return reachDevice(d);
    };
    yield* Effect.addFinalizer(() => Effect.sync(() => void (side.device = null)));

    // The other stations ask what is attached here (device_list there).
    remote.bus.on("devices.list", async (_peer, _request, workspace) => ({ devices: registry.of(workspace ?? "") as unknown as Json }));

    const workspaceOf = (session: string): string => {
      const row = store.getSession(session);
      if (!row) throw new Error("unknown session");
      const ws = row.ws ?? cloud.home();
      if (ws === null) throw new DeviceAsk("this station is in no workspace");
      return ws;
    };

    /// Every device of the workspace this chat's agent can see: this station's, the other whole stations' (asked at
    /// once; one that does not answer in time, or is from before devices, is left out), the tasks-only stations' and
    /// the phones (their parts say).
    const all = async (ws: string, session: string): Promise<DeviceEntry[]> => {
      const own = registry.of(ws).map((k) => entryOf(k, self()));
      const peers = (cloud.membership(ws)?.peers ?? []).flatMap((p) => (typeof p?.id === "string" && p.id !== self() ? [p.id as string] : []));
      const theirs = await Promise.all(peers.map(async (id) => {
        try {
          const got = await wall.within(ASK_MS, remote.ask(id, { method: "devices.list", workspace: ws }), "no answer");
          return (Array.isArray(got?.devices) ? (got.devices as unknown as Kept[]) : []).map((k) => entryOf(k, id));
        } catch {
          return [];
        }
      }));
      const rigs = (await sources.rigs?.list(ws, session).catch(() => [])) ?? [];
      const phones = (await sources.phones?.list(ws, session).catch(() => [])) ?? [];
      return [...own, ...theirs.flat(), ...rigs, ...phones];
    };

    /// The device an agent names: by its id, or its name (any case).
    const named = (list: DeviceEntry[], given: string): DeviceEntry => {
      const byId = list.filter((d) => d.id === given);
      const lower = given.toLowerCase();
      const found = byId.length > 0 ? byId : list.filter((d) => d.name.toLowerCase() === lower);
      if (found.length > 1) throw new DeviceAsk(`${found.length} devices are named ${given}: give the id device_list shows for the one meant`);
      if (found.length === 0) throw new DeviceAsk(`no device ${given} in this workspace${list.length > 0 ? `; those it has: ${list.map((d) => d.name).join(", ")}` : ""}`);
      return found[0]!;
    };

    // Who may connect to a device's port here: the chat's processes, by the machine's (adb/door.ts). None read on
    // Windows: there the port is any local program's, as a forwarded port is.
    const admitFor = (session: string): DeviceTarget["admit"] => platform.os === "windows" ? null : (holders) => gate({
      session: () => ({ workspace: store.getSession(session)?.workspace ?? null }),
      table: () => platform.processTable(false),
      runners: async () => {
        const found = await Promise.all(RUNTIME_KINDS.map((kind) => runnerOf(data, runnerId(kind, session))));
        return found.flatMap((r) => (r === undefined ? [] : [r.runner, r.pid]));
      },
      jobs: () => watchedJobs(store, hub.processJobLookup()).map((j) => ({ pgid: j.pgid, mine: () => j.session === session })),
      cwds: (pids) => platform.cwds(pids),
      self: process.pid,
      elsewhere: "this device's port is another chat's: ask for the device with device_use in this chat",
    }, session, holders);

    /// The device forwarded to a port here for the chat: where it is, in words.
    const forward = async (session: string, e: DeviceEntry): Promise<string> => {
      const here = e.station === self();
      const kept = here ? registry.get(workspaceOf(session), e.id) : null;
      const target: DeviceTarget = { id: e.id, name: e.name, here: kept === null ? null : () => reachDevice(kept), admit: admitFor(session) };
      const v = await forwards.openDevice(session, e.station, target, here);
      return reachedAt(e, Number(v.local.split(":")[1]));
    };
    // The rigs' and phones' parts open a forward through this once a chat may use a device of theirs.
    sources.forward = forward;

    parts.tools(deviceTools({
      list: async (session) => all(workspaceOf(session), session),
      use: async (session, given, reason, timeout, signal) => {
        try {
          const ws = workspaceOf(session);
          const list = await all(ws, session);
          // A person's phone, by whose (none named: the person the agent works for), lent here now or not yet: its
          // app lends it once they grant it.
          if (given === "" || (given.includes("@") && !list.some((d) => d.name.toLowerCase() === given.toLowerCase()))) {
            const email = (given === "" ? (store.starter(session) ?? "") : given).toLowerCase();
            const phone = list.find((d) => d.via === "phone" && d.ownerEmail === email);
            if (sources.phones === null) return "Phones cannot be asked for on this station.";
            return sources.phones.use(ws, session, phone ?? { id: "", name: "", kind: "adb", target: "", via: "phone", station: self(), stationName: "", owner: email, ownerEmail: email, ownerName: "", thisChat: "", hasAccess: "" }, reason, timeout, signal);
          }
          const e = named(list, given);
          if (e.via === "station") return await forward(session, e);
          const source = e.via === "rig" ? sources.rigs : sources.phones;
          if (source === null) return `Devices of that kind cannot be used from this station.`;
          return await source.use(ws, session, e, reason, timeout, signal);
        } catch (e) {
          if (e instanceof DeviceAsk || e instanceof PeerRefused) return (e as Error).message;
          throw e;
        }
      },
      done: async (session, given) => {
        const ws = workspaceOf(session);
        let e: DeviceEntry | null = null;
        if (given !== "") {
          try {
            e = named(await all(ws, session), given);
          } catch (error) {
            if (error instanceof DeviceAsk) return error.message;
            throw error;
          }
        }
        forwards.closeDevice(session, e?.id ?? null, "handed back");
        const names = [
          ...(e === null || e.via === "rig" ? (sources.rigs?.done(ws, session, e) ?? []) : []),
          ...(e === null || e.via === "phone" ? (sources.phones?.done(ws, session, e) ?? []) : []),
        ];
        if (e !== null && e.via === "station") names.push(e.name);
        return names.length === 0 && e === null ? "This chat holds no device and asks for none." : `Handed back${names.length > 0 ? `: ${names.join(", ")}` : ""}. Its port here is closed.`;
      },
    }));

    // What a member's app asks of the devices attached here (the admin API: a read-only member only reads).
    const body = (r: Request): Json => {
      try {
        const parsed = JSON.parse(r.body.toString("utf8") || "{}");
        return parsed !== null && typeof parsed === "object" ? parsed : {};
      } catch {
        return {};
      }
    };
    const answered = (value: unknown): Answer => json(200, JSON.stringify(value));
    const routes: Route[] = [
      { method: "GET", pattern: /^\/devices$/, handle: async (r) => answered({ workspace: r.viewer.workspace, station: self(), devices: listed(r.viewer.workspace), phones: phones(r.viewer.workspace) }) },
      {
        // A device attached here by a member: `{name, kind, target, baud?}`, theirs.
        method: "POST", pattern: /^\/devices$/,
        handle: async (r) => {
          const ws = r.viewer.workspace;
          const made = registry.add(ws, r.viewer, body(r), Math.floor(wall.now() / 1000));
          if (typeof made === "string") return error(422, made);
          tell(ws);
          return answered({ device: { ...made, station: self(), stationName: nameOf(cloud, self()) } });
        },
      },
      {
        // A device taken off: by its owner, or by a workspace's owner or admin (this station does not know whether its
        // owner is still a member; what is on a whole station is every chat's anyway).
        method: "DELETE", pattern: /^\/devices\/([0-9a-f]{16})$/,
        handle: async (r, [id]) => {
          const ws = r.viewer.workspace;
          const d = registry.get(ws, id!);
          if (d === null) return error(404, "no such device on this station");
          if (d.owner !== r.viewer.sub && !managesStation(r.viewer)) return error(403, "only the device's owner, or the workspace's owners and admins, take it off");
          registry.remove(ws, id!);
          forwards.closeDevice(null, id!, "the device was taken off its station");
          tell(ws);
          return answered({ ok: true });
        },
      },
    ];
    parts.routes(routes);
  }),
);
