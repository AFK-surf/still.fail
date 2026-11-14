// A rig on the station transport (a station that only runs tasks, 2026-11-10): what it answers the workspace's stations, and what it tells
// them. A rig is the half of a station that is asked: it runs the tasks stations send it (jobs/remote.ts, as a
// station does for another), and nothing else of a station is in its process (no agents, chats, vault or connects:
// rig/main.ts). Every request passes its grants first (`guard`): what starts or writes something here needs the chat
// it is for to hold a grant its person signed, or 免批准 on; what only reads back or stops what a chat ran here does
// not (a chat that lost its grant still learns how its task ended and takes its results).
//
// It asks nothing of a station. It tells them: what became of a task (jobs/remote.ts `task.changed`), that it is
// here (`rig.hello`, as it comes on the mesh and as the roster changes) and that its grants or settings changed
// (`rig.changed`), each with what `describe` says of it, so a station shows it without asking again.
import { join } from "node:path";
import type { Duplex } from "node:stream";
import { reachDevice } from "../devices/connect.ts";
import { DeviceRefused } from "../mesh/peer-http.ts";
import type { Json } from "../store/store.ts";
import type { Cloud } from "../cloud/state.ts";
import { Refused, type PeerBus } from "../mesh/bus.ts";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { CommandLog } from "./log.ts";
import { type Ended, Refusal, RigGrants, type Self } from "./grants.ts";

/// What a station asks of a rig without a grant: how it is and who may use it, what its person signed, and what reads
/// back, stops or clears what a chat of that station ran here (keyed by that station and session: jobs/remote.ts).
const UNGATED: ReadonlySet<string> = new Set([
  "describe", "task.get", "task.gets", "task.log", "task.list", "task.stop", "task.files", "task.collected", "task.mirrors", "task.clean",
  "file.get", "sync.changes", "session.close", "session.size", "vault.capabilities", "vault.revoke",
]);

/// A station not told is told again after this, then twice as long each time, a minute apart at most, for an hour: one
/// back later asks for itself (rigs/module.ts, as it starts).
const AGAIN_MS = 1000;
const AGAIN_MAX_MS = 60_000;
const AGAIN_FOR_MS = 3_600_000;
/// The most lines of the command log a station is given at once.
const LOG_MAX = 200;

export type RigDeps = {
  data: string;
  cloud: Cloud;
  bus: PeerBus;
  /// Whether a chat (a station's session) has something running here, stopping it, and all that have (jobs/remote.ts's
  /// tasks: the jobs owned by `remote:<workspace>:<station>:<session>`).
  busy: (workspace: string, station: string, session: string) => boolean;
  stop: (workspace: string, station: string, session: string) => void | Promise<void>;
  running: () => { workspace: string; station: string; session: string }[];
  fibers?: Fibers;
};

export class Rig {
  readonly grants: RigGrants;
  readonly commands: CommandLog;
  readonly #d: RigDeps;
  readonly #fibers: Fibers;
  /// The stations not told the last change yet: when to tell each again, and until when it is tried.
  readonly #untold = new Map<string, { wait: number; until: number; stop: () => void }>();
  #unlisten: (() => void) | null = null;
  #known = new Set<string>();
  /// The chats' connections to this rig's devices open now.
  readonly #wired = new Set<{ device: string; station: string; session: string; socket: Duplex }>();

  constructor(deps: RigDeps) {
    this.#d = deps;
    this.#fibers = deps.fibers ?? new Fibers("rig");
    const { cloud, bus } = deps;
    const ws = () => cloud.state?.workspace ?? "";
    this.commands = new CommandLog(join(deps.data, "rig", "commands.log"));
    this.grants = new RigGrants({
      path: join(deps.data, "rig", "grants.json"),
      self: () => this.self(),
      busy: (station, session) => deps.busy(ws(), station, session),
      stop: (station, session) => deps.stop(ws(), station, session),
      running: () => deps.running().filter((r) => r.workspace === ws()),
      ended: (ended) => this.#tell(ended.station, { ended }),
      changed: () => this.#tellAll(),
      cut: (device, station, session) => this.#cut(device, station, session),
      fibers: this.#fibers,
    });
    bus.guarded((workspace, peer, request) => this.#guard(workspace, peer, request));
    bus.on("rig.", async (peer, request, workspace) => this.#heard(peer, request, workspace ?? ""));
    bus.whenAttached(() => {
      this.#tellAll(true);
      // A station new to the roster is told this rig is here; one gone is no longer tried.
      this.#unlisten = cloud.listen(() => this.#tellAll(true, true));
    });
  }

  /// What this machine is, while it is a rig in a workspace.
  self(): Self | null {
    const s = this.#d.cloud.state;
    if (s === null || s.rig === undefined || !s.workspace || this.#d.cloud.removed()) return null;
    return { id: s.station, workspace: s.workspace, owner: s.rig.owner, person: s.rig.person };
  }

  /// What `describe` says besides a station's own: that it is a rig, which of a station's things it has none of, and
  /// who may use it. (What the asking station's own chats hold is in `grants`, by their station.)
  described(): Json {
    const s = this.#d.cloud.state;
    const view = this.grants.view();
    return {
      sessions: false, messages: false, reads: false, chats: false,
      rig: view === null ? null : { ...view, owner_email: s?.rig?.owner_email ?? "", owner_name: s?.rig?.owner_name ?? "", ...(this.grants.proof() !== null ? { proof: true } : {}) },
    };
  }

  /// A connection to device `id` here for a chat (`session` of station `peer`): let through by a grant of the rig or of
  /// the device, or 免批准, else a DeviceRefused saying why. `probe`: only whether it would be (no use, nothing opened).
  async device(peer: string, workspace: string, session: string, id: string, probe: boolean): Promise<Duplex | null> {
    const why = this.grants.deviceRefusal(workspace, peer, session, id, !probe);
    if (why !== null) throw new DeviceRefused(/no such device/.test(why) ? 404 : 403, why);
    if (probe) return null;
    const d = this.grants.devices().find((x) => x.id === id);
    if (d === undefined) throw new DeviceRefused(404, "no such device on this rig");
    const socket = await reachDevice(d);
    const wire = { device: id, station: peer, session, socket };
    this.#wired.add(wire);
    socket.once("close", () => this.#wired.delete(wire));
    this.commands.add({ at: this.#fibers.now(), station: peer, session, key: id, name: d.name, command: `${d.kind} ${d.target}`, kind: "device" });
    return socket;
  }

  /// The connections to `device` (of one chat, or of all) looked at again: those no longer let through are cut.
  #cut(device: string, station: string | null, session: string | null): void {
    const self = this.self();
    for (const w of [...this.#wired]) {
      if (w.device !== device || (station !== null && w.station !== station) || (session !== null && w.session !== session)) continue;
      if (self !== null && this.grants.deviceRefusal(self.workspace, w.station, w.session, device, false) === null) continue;
      this.#wired.delete(w);
      w.socket.destroy();
    }
  }

  /// Why a station may not reach this rig's services now (mesh/peer-http.ts), or null.
  stationRefusal(peer: string, workspace: string): string | null {
    return this.grants.stationRefusal(workspace, peer);
  }

  #guard(workspace: string, peer: string, request: Json): void {
    const method = typeof request?.method === "string" ? request.method : "";
    if (UNGATED.has(method) || method.startsWith("rig.")) return;
    const session = typeof request?.session === "string" ? request.session : "";
    if (session === "") throw new Refused("a rig runs only what a chat asks of it (no session named)");
    const why = this.grants.refusal(workspace, peer, session);
    if (why !== null) throw new Refused(why);
    // What it is told to run, kept here (rig/log.ts).
    if (method === "task.prepare" && typeof request?.spec?.command === "string") {
      this.commands.add({ at: this.#fibers.now(), station: peer, session, key: String(request.key ?? ""), name: String(request.spec.name ?? ""), command: request.spec.command, kind: "task" });
    } else if ((method === "vault.run" || method === "vault.capture") && typeof request?.command === "string") {
      this.commands.add({ at: this.#fibers.now(), station: peer, session, key: String(request.id ?? ""), name: "", command: request.command, kind: "secret" });
    }
  }

  #heard(peer: string, request: Json, workspace: string): Json {
    const method = typeof request?.method === "string" ? request.method : "";
    const self = this.self();
    if (self === null || workspace !== self.workspace) throw new Refused("this rig is of another workspace");
    try {
      switch (method) {
        case "rig.describe":
          return this.described();
        case "rig.grant":
          return this.grants.grant(peer, request.signed, request.chain);
        case "rig.revoke":
          this.grants.revoke(request.signed, request.chain);
          return { ok: true };
        case "rig.release":
          return { released: this.grants.release(peer, String(request.request ?? "")) };
        case "rig.settings":
          this.grants.settings(request.signed, request.chain);
          return { ok: true };
        case "rig.device":
          this.grants.device(request.signed, request.chain);
          return { ok: true };
        case "rig.added":
          this.grants.added(request.signed);
          return { ok: true };
        case "rig.full": {
          // Its person signed it whole again: kept until the control plane lists it as a station (cloud/presence.ts),
          // which alone makes it one. A station's again: the control plane's word, as a station's enrollment is.
          const s = this.grants.full(request.signed, request.chain);
          this.#d.cloud.update((st) => void (st.full_pending = { at: s.body.at }));
          return { ok: true };
        }
        case "rig.proof":
          return { add: this.grants.proof() };
        case "rig.log": {
          const limit = Number.isSafeInteger(request.limit) ? Math.min(Math.max(1, request.limit), LOG_MAX) : 50;
          return { commands: this.commands.last(limit) as unknown as Json };
        }
        default:
          throw new Refused(`unknown method ${method}`);
      }
    } catch (error) {
      if (error instanceof Refusal) throw new Refused(error.message);
      throw error;
    }
  }

  /// The stations of the workspace now.
  #stations(): string[] {
    const self = this.self();
    if (self === null) return [];
    return (this.#d.cloud.membership(self.workspace)?.peers ?? []).flatMap((p) => (typeof p?.id === "string" && p.id !== self.id ? [p.id as string] : []));
  }

  /// Every station told how this rig is now. `hello`: as it comes on the mesh; `fresh`: only those new to the roster.
  #tellAll(hello = false, fresh = false): void {
    const stations = this.#stations();
    for (const [station, waiting] of this.#untold) {
      if (!stations.includes(station)) {
        waiting.stop();
        this.#untold.delete(station);
      }
    }
    for (const station of stations) if (!fresh || !this.#known.has(station)) this.#tell(station, {}, hello);
    this.#known = new Set(stations);
  }

  /// One station told how this rig is now (and what ended, when a grant of its own did); told again later when it was
  /// not reached.
  #tell(station: string, more: { ended?: Ended }, hello = false): void {
    const self = this.self();
    if (self === null || !this.#stations().includes(station)) return;
    this.#untold.get(station)?.stop();
    this.#untold.delete(station);
    const request = { method: hello ? "rig.hello" : "rig.changed", workspace: self.workspace, ...this.described(), ...more } as Json;
    const attempt = (wait: number, until: number) => {
      void this.#d.bus.ask(station, request).catch((error) => {
        // Refused: it heard (a station from before rigs, or one that takes this rig for none yet): nothing to try again.
        if (error instanceof Refused || this.#fibers.now() >= until) return;
        const entry = { wait: Math.min(wait * 2, AGAIN_MAX_MS), until, stop: () => {} };
        // A retry after a failure, with a backoff: the station was not reached.
        entry.stop = this.#fibers.after(wait, () => {
          if (this.#untold.get(station) !== entry) return;
          this.#untold.delete(station);
          // What it is told is how the rig is by then; what ended for it goes along still.
          const again = { ...request, ...this.described() } as Json;
          Object.assign(request, again);
          attempt(entry.wait, until);
        });
        this.#untold.set(station, entry);
        log.info("rig", "a station was not told of this rig; told again later", { station: station.slice(0, 12), error: (error as Error).message });
      });
    };
    attempt(AGAIN_MS, this.#fibers.now() + AGAIN_FOR_MS);
  }

  async close(): Promise<void> {
    this.#unlisten?.();
    for (const waiting of this.#untold.values()) waiting.stop();
    for (const w of this.#wired) w.socket.destroy();
    this.#wired.clear();
    this.#untold.clear();
    await this.grants.close();
    if (this.#d.fibers === undefined) await this.#fibers.close();
  }
}
