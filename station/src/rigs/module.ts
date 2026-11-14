// The workspace's rigs as a part of the station (a station that only runs tasks, 2026-11-10; parts.ts): machines that only run what stations
// send them, each its person's (cloud/state.ts `Rig`; the rig's own side is rig/). This station sends them tasks as
// it sends another station's (jobs/remote.ts, by the rig's name), asks their person for a chat's grant (requests.ts,
// `station_use`), carries what that person signs to the rig (grants, settings, a grant taken back, the rig taken into a
// workspace in security mode: adds.ts), and shows how each rig is to the agents (`station_list`) and the app.
//
// How a rig is, is the rig's own word: it tells every station as it comes on the mesh and as it changes (`rig.hello`,
// `rig.changed`); this station asks once as it starts or first hears of a rig (`rig.describe`), never on a timer. What
// could not be brought to a rig that was away waits here (`rig_outbox`, a granted request not delivered) until the
// rig is next heard.
import { Effect, Layer } from "effect";
import type { Route } from "../api/admin.ts";
import { type Answer, type Request, error, json } from "../api/request.ts";
import type { Device, GrantBody, Timeout } from "../../../client/core-ts/src/rig-form.ts";
import { wellFormed } from "../../../client/core-ts/src/rig-form.ts";
import { grantChatTitle } from "../adb/title.ts";
import { shortCode } from "../cloud/lock.ts";
import type { Rig } from "../cloud/state.ts";
import { Refused as PeerRefused } from "../mesh/bus.ts";
import { managesStation } from "../mesh/credential.ts";
import { nameOf } from "../mesh/peer-http.ts";
import { personChainsOf } from "../mesh/serve.ts";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { ControlPlane, type DeviceEntry, DeviceSources, Events, Parts, Store } from "../services.ts";
import { Agents } from "../sessions/agents.ts";
import type { Json } from "../store/store.ts";
import { RigAdds } from "./adds.ts";
import { Refused, type RigRequest, RigRequests, lasting, said } from "./requests.ts";
import { rigTools } from "./tool.ts";

/// What a rig says of itself (rig/module.ts `described`): who may use it.
type Described = {
  owner: string; person: string; open: boolean; settings: number; owner_email?: string; owner_name?: string; proof?: boolean;
  grants: { request: string; station: string; session: string; chat: string; title: string; by: string; timeout: Timeout; exp: number; until: number; device?: string }[];
  /// Its devices (rig/grants.ts), each with its own 免批准; none from a rig from before devices.
  devices?: (Device & { open: boolean; settings: number })[];
};
/// A rig as this station last heard it (`rig`: null, it answered as no rig), and whether it was reached then.
type Heard = { workspace: string; rig: Described | null; load?: Json; at: number; reached: boolean };

const SCHEMA = `CREATE TABLE IF NOT EXISTS rig_outbox (
  n INTEGER PRIMARY KEY AUTOINCREMENT,
  ws TEXT NOT NULL,
  rig TEXT NOT NULL,
  kind TEXT NOT NULL,
  body TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS rig_outbox_by_rig ON rig_outbox (ws, rig, n);`;

/// How a rig said a grant ended, in the chat's words.
const ENDED: Record<string, string> = { expired: "授权已到期", idle: "闲置超时", revoked: "所有者已收回", released: "agent 已交还", closed: "所有者已关闭免批准" };
/// A rig asked how it is answers within this, or is shown as not reached (as station_list's stations: jobs/remote.ts).
const ASK_MS = 5000;
/// The most a statement with its person's lock takes (bytes of JSON).
const SIGNED_MAX = 512 * 1024;

const describedOf = (answer: Json): Described | null => {
  const r = answer?.rig;
  return r !== null && typeof r === "object" && typeof r.owner === "string" && Array.isArray(r.grants) ? (r as Described) : null;
};

export const RigsLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const plane = yield* ControlPlane;
    const cloud = plane.state;
    const parts = yield* Parts;
    const store = yield* Store;
    const events = yield* Events;
    const { hub, cardOutcomes, remote, forwards } = yield* Agents;
    const sources = yield* DeviceSources;
    const db = store.db;
    db.exec(SCHEMA);
    const self = () => cloud.state?.station ?? "";
    const secs = () => Math.floor(wall.now() / 1000);

    // Security mode: a rig is the workspace's once its person signed for it (adds.ts).
    const adds = new RigAdds({ db, cloud, chain: (genesis) => personChainsOf(cloud).kept(genesis), now: secs });
    cloud.rigVouched = (ws, rig) => adds.holds(ws, rig);
    yield* Effect.addFinalizer(() => Effect.sync(() => (cloud.rigVouched = () => false)));

    const heard = new Map<string, Heard>();
    const key = (ws: string, rig: string) => `${ws}\0${rig}`;
    const ask = (rig: string, request: Json): Promise<Json> => remote.ask(rig, request);

    // What waits for a rig that was away: brought in order as it is heard, each gone once the rig took or refused it.
    const queue = (ws: string, rig: string, kind: "revoke" | "release" | "settings" | "added" | "device", body: Json) => {
      // The settings are whole each time: only the latest are brought.
      if (kind === "settings") db.prepare("DELETE FROM rig_outbox WHERE ws = ? AND rig = ? AND kind = 'settings'").run(ws, rig);
      db.prepare("INSERT INTO rig_outbox (ws, rig, kind, body) VALUES (?, ?, ?, ?)").run(ws, rig, kind, JSON.stringify(body));
    };
    const flushing = new Map<string, Promise<boolean>>();
    /// Whether everything waiting for the rig got there.
    const flush = (ws: string, rig: string): Promise<boolean> => {
      const k = key(ws, rig);
      let going = flushing.get(k);
      if (going === undefined) {
        going = (async () => {
          for (;;) {
            const row = db.prepare("SELECT n, kind, body FROM rig_outbox WHERE ws = ? AND rig = ? ORDER BY n LIMIT 1").get(ws, rig) as { n: number; kind: string; body: string } | undefined;
            if (row === undefined) return true;
            try {
              await ask(rig, { method: `rig.${row.kind}`, workspace: ws, ...JSON.parse(row.body) });
            } catch (error) {
              // Refused: it heard, and will not take it however often it is brought.
              if (!(error instanceof PeerRefused)) return false;
              log.warn("rigs", "a rig refused what its person signed", { rig: rig.slice(0, 12), kind: row.kind, error: (error as Error).message });
            }
            db.prepare("DELETE FROM rig_outbox WHERE n = ?").run(row.n);
          }
        })().finally(() => flushing.delete(k));
        flushing.set(k, going);
      }
      return going;
    };

    const requests = new RigRequests({
      db, hub: hub as any, cardOutcomes, home: () => cloud.home(), self, now: () => wall.now(),
      title: (r) => grantChatTitle(store, r as any),
      bring: async (r) => {
        try {
          const got = await ask(r.rig, { method: "rig.grant", workspace: r.ws, signed: r.signed as unknown as Json, chain: (r.chain ?? null) as Json });
          return { until: Number.isSafeInteger(got?.until) ? got.until : (r.signed?.body.exp ?? 0) };
        } catch (error) {
          if (error instanceof PeerRefused) throw new Refused(error.message);
          throw error;
        }
      },
      release: (r, revoke) => {
        queue(r.ws, r.rig, revoke === null ? "release" : "revoke", (revoke === null ? { request: r.id } : { signed: revoke.signed, chain: revoke.chain ?? null }) as unknown as Json);
        void flush(r.ws, r.rig);
      },
      told: (r) => {
        // A chat's grant of a device (or of the rig, with its devices) over: its ports here close.
        if (r.status === "ended" || r.status === "denied") {
          if (r.device !== undefined) forwards.closeDevice(r.session, r.device, "its grant ended");
          else for (const d of heard.get(key(r.ws, r.rig))?.rig?.devices ?? []) if (requests.of(r.session, r.rig, d.id).length === 0) forwards.closeDevice(r.session, d.id, "its station's grant ended");
        }
        tell(r.ws);
      },
    });

    /// A workspace's rigs as the app shows them: what the control plane names, whether each is taken here (security
    /// mode), how it last said it is, and the requests of this station's chats still asked of its person.
    const listed = (ws: string): Json[] =>
      cloud.rigsNamed(ws).map((rig) => {
        const vouched = cloud.locked(ws === cloud.home() ? null : ws) === null ? undefined : adds.holds(ws, rig);
        const h = heard.get(key(ws, rig.id));
        const d = h?.rig ?? null;
        return {
          id: rig.id, name: rig.name, owner: rig.owner, owner_email: rig.owner_email, owner_name: rig.owner_name, code: shortCode(rig.id),
          ...(vouched === undefined ? {} : { vouched }),
          reached: h === undefined ? null : h.reached, at: h?.at ?? null,
          ...(d === null ? {} : { open: d.open, settings: d.settings, person: d.person, grants: d.grants.map((g) => ({ ...g, stationName: nameOf(cloud, g.station) })), devices: d.devices ?? [] }),
          requests: requests.ofRig(ws, rig.id).filter((r) => r.status === "pending" || r.delivered !== true)
            .map((r) => ({
              id: r.id, station: self(), session: r.session, chat: r.chat, title: r.title, by: r.by, reason: r.reason, timeout: r.signed?.body.timeout ?? r.timeout, at: r.at, status: r.status,
              ...(r.device !== undefined ? { device: r.device, deviceName: r.deviceName ?? "" } : {}),
            })),
        } as Json;
      });
    const tell = (ws: string) => events.tell("rigs", { workspace: ws, rigs: listed(ws) }, `rigs\0${ws}`, { workspace: ws });

    /// How a rig says it is (it told, or was asked): kept; what waited for it brought; this station's grants it no
    /// longer lists ended, with why when it said.
    const take = (ws: string, rig: string, answer: Json) => {
      const d = describedOf(answer);
      heard.set(key(ws, rig), { workspace: ws, rig: d, load: answer?.load ?? null, at: wall.now(), reached: true });
      const ended = answer?.ended;
      if (ended !== null && typeof ended === "object" && typeof ended.request === "string" && ended.station === self()) requests.endedThere(ended.request, ENDED[String(ended.why)] ?? "已结束");
      if (d !== null) {
        const mine = new Map(d.grants.filter((g) => g.station === self()).map((g) => [g.request, g]));
        for (const r of requests.ofRig(ws, rig)) {
          if (r.status !== "granted") continue;
          const there = mine.get(r.id);
          if (r.delivered === true && there === undefined) requests.endedThere(r.id, "已结束");
          else if (r.delivered === true && there !== undefined) requests.heldThere(r.id, there.until);
        }
      }
      void flush(ws, rig).then(async (through) => {
        if (through) for (const r of requests.undelivered(ws, rig)) await requests.deliver(r);
      });
      tell(ws);
    };

    /// A rig asked how it is, once: as this station starts, or first hears the control plane name it. In security mode
    /// one not signed for yet is asked what its person signed first (`rig.proof`), and for nothing else until that holds.
    const asked = new Set<string>();
    const look = () => {
      if (!cloud.peersCurrent) return;
      const now = new Set<string>();
      for (const m of cloud.memberships()) {
        for (const rig of cloud.rigsNamed(m.workspace)) {
          const k = key(m.workspace, rig.id);
          now.add(k);
          if (asked.has(k)) continue;
          asked.add(k);
          void meet(m.workspace, rig);
        }
      }
      for (const k of asked) {
        if (now.has(k)) continue;
        asked.delete(k);
        heard.delete(k);
      }
    };
    const meet = async (ws: string, rig: Rig) => {
      try {
        if (cloud.locked(ws === cloud.home() ? null : ws) !== null && !adds.holds(ws, rig)) {
          const got = await wall.within(ASK_MS, ask(rig.id, { method: "rig.proof", workspace: ws }), "the rig did not answer");
          const why = got?.add == null ? "it has none" : adds.take(ws, rig, got.add);
          if (why !== null) {
            log.info("rigs", "a rig the control plane names is not taken: its person has not signed for it here", { rig: rig.id.slice(0, 12), why });
            return tell(ws);
          }
        }
        take(ws, rig.id, await wall.within(ASK_MS, ask(rig.id, { method: "rig.describe", workspace: ws }), "the rig did not answer"));
      } catch (error) {
        const was = heard.get(key(ws, rig.id));
        heard.set(key(ws, rig.id), { workspace: ws, rig: was?.rig ?? null, at: was?.at ?? 0, reached: false });
        log.info("rigs", "a rig was not reached; it tells when it is back", { rig: rig.id.slice(0, 12), error: (error as Error).message });
        tell(ws);
      }
    };
    remote.bus.whenAttached(look);
    yield* Effect.acquireRelease(Effect.sync(() => cloud.listen(look)), (off) => Effect.sync(off));

    // What a rig tells of itself: taken only from a machine that is a rig of that workspace.
    remote.bus.on(["rig.hello", "rig.changed"], async (peer, request, workspace) => {
      const ws = workspace ?? "";
      if (cloud.rigOf(peer, ws) === null) throw new Error("not a rig of this workspace");
      asked.add(key(ws, peer));
      take(ws, peer, request);
      return { ok: true };
    });

    /// The rig an agent or the app names in workspace `ws`: by its id, or its name (as cased anywhere).
    const named = (ws: string, given: string): Rig => {
      const rigs = cloud.rigsNamed(ws);
      const lower = given.toLowerCase();
      const found = rigs.filter((r) => r.id === given);
      const same = found.length > 0 ? found : rigs.filter((r) => r.name.toLowerCase() === lower);
      if (same.length > 1) throw new Refused(`${same.length} tasks-only stations are named ${given}: give the id station_list shows for the one meant`);
      if (same.length === 0) throw new Refused(`no tasks-only station ${given} in this workspace${rigs.length > 0 ? `; those it has: ${rigs.map((r) => r.name || r.id).join(", ")}` : " (it has none; a whole station needs no grant)"}`);
      if (cloud.rigOf(same[0]!.id, ws) === null) throw new Refused(`the station ${given} is not taken into this workspace yet: its owner ${same[0]!.owner_email || same[0]!.owner} has to check its security code in still.fail first`);
      return same[0]!;
    };
    const workspaceOf = (session: string): string => {
      const row = store.getSession(session);
      if (!row) throw new Error("unknown session");
      const ws = row.ws ?? cloud.home();
      if (ws === null) throw new Refused("this station is in no workspace");
      return ws;
    };

    parts.tools(rigTools({
      ask: async (session, rigName, reason, timeout, signal) => {
        const ws = workspaceOf(session);
        const rig = named(ws, rigName);
        const h = heard.get(key(ws, rig.id));
        if (h?.rig?.open === true && requests.of(session, rig.id).length === 0) return `The station ${rig.name} takes every chat of this workspace with no grant (免批准 is on): use it as any station, by its name, with station_task, station_file, peer_forward and secret_use's station.`;
        return said(await requests.ask(session, rig, ws, reason, timeout, signal));
      },
      done: (session, rigName) => {
        const ws = workspaceOf(session);
        // (the rig's own grants: its devices' are device_use's to hand back)
        const ended = requests.release(session, rigName === "" ? null : named(ws, rigName).id, undefined);
        return ended.length === 0 ? "This chat holds no grant of a tasks-only station and asks for none." : `Handed back: ${ended.map((r) => `${r.rigName} (${r.id})`).join(", ")}. What this chat ran there is stopped.`;
      },
    }));

    // station_list: each rig after the stations, with whose it is, whether this chat may use it and who may.
    remote.setRigs(async (workspace, session, rig, answer) => {
      const d = answer === null ? heard.get(key(workspace, rig.id))?.rig ?? null : describedOf(answer);
      const whose = `${rig.owner_name || rig.owner_email || rig.owner}${rig.owner_name && rig.owner_email ? ` <${rig.owner_email}>` : ""}`;
      const mine = requests.of(session, rig.id);
      const pending = mine.find((r) => r.status === "pending");
      const granted = mine.find((r) => r.status === "granted");
      const access = d?.open === true
        ? "open to every chat of the workspace (免批准): use it as a station, by its name"
        : granted?.delivered === true ? `granted to this chat (${lasting(granted.signed?.body.timeout ?? granted.timeout)})`
        : granted !== undefined ? "approved for this chat; it has not taken the grant yet (it was away): you are told when it has"
        : pending !== undefined ? `asked: waits for its owner to approve request ${pending.id} on the card in your chat`
        : `no grant: ask with station_use {station: "${rig.name || rig.id}", reason}; its card goes to ${rig.owner_email || whose}`;
      const until = (u: number) => new Date(u * 1000).toISOString();
      return {
        mode: "tasks", owner: whose, thisChat: access,
        ...(d === null ? { hasAccess: "unknown: it was not reached" } : {
          hasAccess: d.open ? "every chat of the workspace" : d.grants.map((g) => `${g.title ? `"${g.title}"` : g.chat}${g.by ? ` (started by ${g.by})` : ""} on ${nameOf(cloud, g.station)}, ${g.timeout.kind} ${g.timeout.seconds / 60} min, until ${until(g.until)}`),
        }),
      } as Json;
    });

    // The devices attached to the rigs, as device_list shows them and device_use asks for them (devices/module.ts).
    const deviceEntries = (ws: string, session: string): DeviceEntry[] =>
      cloud.rigsNamed(ws).flatMap((rig) => {
        if (cloud.rigOf(rig.id, ws) === null) return [];
        const h = heard.get(key(ws, rig.id));
        const d = h?.rig ?? null;
        const whole = requests.of(session, rig.id).find((r) => r.status === "granted" && r.delivered === true);
        return (d?.devices ?? []).map((dev): DeviceEntry => {
          const mine = requests.of(session, rig.id, dev.id);
          const pending = mine.find((r) => r.status === "pending");
          const granted = mine.find((r) => r.status === "granted");
          const thisChat = d!.open || dev.open ? "open to every chat of the workspace (免批准): device_use gives it at once"
            : whole !== undefined ? `this chat holds a grant of ${rig.name}, its station: device_use gives it at once`
            : granted?.delivered === true ? `granted to this chat (${lasting(granted.signed?.body.timeout ?? granted.timeout)}): device_use gives it`
            : granted !== undefined ? "approved for this chat; its station has not taken the grant yet (it was away): you are told when it has"
            : pending !== undefined ? `asked: waits for its owner to approve request ${pending.id} on the card in your chat`
            : `no grant: ask with device_use {device: "${dev.name}", reason}; its card goes to ${rig.owner_email || rig.owner}`;
          const holders = d!.grants.filter((g) => g.device === undefined || g.device === dev.id).map((g) => `${g.title ? `"${g.title}"` : g.chat}${g.by ? ` (started by ${g.by})` : ""} on ${nameOf(cloud, g.station)}${g.device === undefined ? " (a grant of the station)" : ""}`);
          return {
            id: dev.id, name: dev.name, kind: dev.kind, target: dev.target, ...(dev.baud !== undefined ? { baud: dev.baud } : {}),
            via: "rig", station: rig.id, stationName: rig.name, owner: rig.owner, ownerEmail: rig.owner_email, ownerName: rig.owner_name,
            online: h?.reached === true, thisChat, hasAccess: d!.open || dev.open ? "every chat of the workspace" : holders,
          };
        });
      });
    const mayUse = (ws: string, session: string, e: DeviceEntry): boolean => {
      const d = heard.get(key(ws, e.station))?.rig ?? null;
      const dev = d?.devices?.find((x) => x.id === e.id);
      if (d === null || dev === undefined) return false;
      if (d.open || dev.open) return true;
      return [...requests.of(session, e.station), ...requests.of(session, e.station, e.id)].some((r) => r.status === "granted" && r.delivered === true);
    };
    sources.rigs = {
      list: async (ws, session) => deviceEntries(ws, session),
      use: async (ws, session, e, reason, timeout, signal) => {
        if (mayUse(ws, session, e)) {
          if (sources.forward === null) return "Devices cannot be forwarded on this station yet.";
          return sources.forward(session, e);
        }
        const rig = named(ws, e.station);
        const t = timeout !== null && typeof timeout === "object" ? ({ kind: (timeout as Json).kind, seconds: (timeout as Json).seconds } as Timeout) : undefined;
        return said(await requests.ask(session, rig, ws, reason, t, signal, { id: e.id, name: e.name }));
      },
      // (a grant of a rig itself is station_use's to hand back)
      done: (_ws, session, e) => requests.release(session, e === null ? null : e.station, e === null ? "*" : e.id).map((r) => r.deviceName ?? r.device ?? ""),
    };
    yield* Effect.addFinalizer(() => Effect.sync(() => void (sources.rigs = null)));

    // A rig its person signed for here is signed for at the workspace's other stations too: each checks it itself.
    const vouchedElsewhere = (ws: string, rig: string, signed: Json) => {
      for (const p of cloud.membership(ws)?.peers ?? []) {
        if (typeof p?.id !== "string" || p.id === self()) continue;
        void ask(p.id, { method: "rig.add", workspace: ws, rig, signed }).catch(() => {
          // Away, or from before rigs: it asks the rig itself as it next starts (`rig.proof`).
        });
      }
    };
    remote.bus.on("rig.add", async (_peer, request, workspace) => {
      const ws = workspace ?? "";
      const rig = cloud.rigsNamed(ws).find((r) => r.id === request?.rig);
      if (rig === undefined) throw new Error("no such rig in this workspace");
      const why = adds.take(ws, rig, request.signed);
      if (why !== null) throw new Error(why);
      asked.delete(key(ws, rig.id));
      look();
      tell(ws);
      return { vouched: true };
    });

    // What a member's app asks of the rigs (the admin API: a read-only member reads, and changes nothing).
    const body = (r: Request): Json => {
      try {
        const parsed = JSON.parse(r.body.toString("utf8") || "{}");
        return parsed !== null && typeof parsed === "object" ? parsed : {};
      } catch {
        return {};
      }
    };
    const answered = (value: unknown): Answer => json(200, JSON.stringify(value));
    const refusing = async (run: () => Promise<Answer>): Promise<Answer> => {
      try {
        return await run();
      } catch (e) {
        if (e instanceof Refused) return error(422, e.message);
        throw e;
      }
    };
    const routes: Route[] = [
      { method: "GET", pattern: /^\/rigs$/, handle: async (r) => answered({ workspace: r.viewer.workspace, rigs: listed(r.viewer.workspace) }) },
      {
        // What the rig was told to run, the last of it (kept on the rig, read through this station).
        method: "GET", pattern: /^\/rigs\/([0-9a-f]{64})\/log$/,
        handle: (r, [id]) => refusing(async () => {
          const ws = r.viewer.workspace;
          const rig = named(ws, id!);
          const limit = Number(r.query.find(([k]) => k === "limit")?.[1] ?? 50);
          let got: Json;
          try {
            got = await wall.within(ASK_MS, ask(rig.id, { method: "rig.log", workspace: ws, limit: Number.isSafeInteger(limit) ? limit : 50 }), "the rig did not answer");
          } catch (e) {
            return error(504, (e as Error).message);
          }
          return answered({ commands: (Array.isArray(got?.commands) ? got.commands : []).map((c: Json) => ({ ...c, stationName: nameOf(cloud, String(c?.station ?? "")) })) });
        }),
      },
      {
        // A chat's request decided by the rig's person: `{allow, signed, chain}` (what their device signed, with their
        // own lock); refused with `allow: false`.
        method: "POST", pattern: /^\/rigs\/requests\/([^/]+)\/decide$/,
        handle: (r, [id]) => refusing(async () => {
          const op = body(r);
          if (r.body.length > SIGNED_MAX) return error(413, "too large");
          const why = await requests.decide(r.viewer.sub, id!, r.viewer.workspace, op.allow === true ? op.signed : null, op.chain);
          return why === null ? answered({ request: publicOf(requests.get(id!)) }) : error(422, why);
        }),
      },
      {
        // A grant taken back by the rig's person: `{rig, signed, chain}`. One of another station's chat is carried
        // to the rig all the same, which tells that station.
        method: "POST", pattern: /^\/rigs\/requests\/([^/]+)\/revoke$/,
        handle: (r, [id]) => refusing(async () => {
          const op = body(r);
          const ws = r.viewer.workspace;
          if (r.body.length > SIGNED_MAX) return error(413, "too large");
          const local = requests.get(id!);
          if (local !== null && local.ws === ws) {
            const why = requests.revoke(r.viewer.sub, id!, ws, op.signed, op.chain);
            return why === null ? answered({ request: publicOf(requests.get(id!)) }) : error(422, why);
          }
          const rig = named(ws, String(op.rig ?? ""));
          if (rig.owner !== r.viewer.sub) return error(403, "only the rig's owner takes a grant of it back");
          if (!wellFormed("revoke", op.signed) || op.signed.body.rig !== rig.id || op.signed.body.ws !== ws || op.signed.body.request !== id) return error(422, "not this grant's revoke");
          queue(ws, rig.id, "revoke", { signed: op.signed, chain: op.chain ?? null });
          return answered({ delivered: await flush(ws, rig.id) });
        }),
      },
      {
        // The rig's settings as its person signed them (免批准): `{signed, chain}`. Kept for a rig that is away.
        method: "POST", pattern: /^\/rigs\/([0-9a-f]{64})\/settings$/,
        handle: (r, [id]) => refusing(async () => {
          const op = body(r);
          const ws = r.viewer.workspace;
          if (r.body.length > SIGNED_MAX) return error(413, "too large");
          const rig = named(ws, id!);
          if (rig.owner !== r.viewer.sub) return error(403, "only the rig's owner changes its settings");
          if (!wellFormed("settings", op.signed) || op.signed.body.rig !== rig.id || op.signed.body.ws !== ws || op.signed.body.sub !== r.viewer.sub) return error(422, "not this rig's settings");
          queue(ws, rig.id, "settings", { signed: op.signed, chain: op.chain ?? null });
          return answered({ delivered: await flush(ws, rig.id) });
        }),
      },
      {
        // A device attached to the rig, or taken off it, as its person signed it: `{signed, chain}`. Kept for a rig
        // that is away; the rig checks it itself.
        method: "POST", pattern: /^\/rigs\/([0-9a-f]{64})\/devices$/,
        handle: (r, [id]) => refusing(async () => {
          const op = body(r);
          const ws = r.viewer.workspace;
          if (r.body.length > SIGNED_MAX) return error(413, "too large");
          const rig = named(ws, id!);
          if (rig.owner !== r.viewer.sub) return error(403, "only the station's owner attaches devices to it");
          if (!wellFormed("device", op.signed) || op.signed.body.rig !== rig.id || op.signed.body.ws !== ws || op.signed.body.sub !== r.viewer.sub) return error(422, "not this station's device");
          queue(ws, rig.id, "device", { signed: op.signed, chain: op.chain ?? null });
          return answered({ delivered: await flush(ws, rig.id) });
        }),
      },
      {
        // Security mode: the rig taken into the workspace by its person, who compared its code: `{signed}`.
        method: "POST", pattern: /^\/rigs\/([0-9a-f]{64})\/add$/,
        handle: async (r, [id]) => {
          const op = body(r);
          const ws = r.viewer.workspace;
          const rig = cloud.rigsNamed(ws).find((x) => x.id === id);
          if (rig === undefined) return error(404, "no such rig in this workspace");
          if (rig.owner !== r.viewer.sub) return error(403, "only the rig's owner takes it into the workspace");
          const why = adds.take(ws, rig, op.signed);
          if (why !== null) return error(422, why);
          queue(ws, rig.id, "added", { signed: op.signed });
          vouchedElsewhere(ws, rig.id, op.signed);
          asked.delete(key(ws, rig.id));
          look();
          tell(ws);
          return answered({ vouched: true });
        },
      },
      {
        // A rig made a whole station again by its person, where they are one of the workspace's managers: `{signed,
        // chain}`, carried to the rig, which keeps it until the control plane lists it as a station (the app asks that
        // next).
        method: "POST", pattern: /^\/rigs\/([0-9a-f]{64})\/full$/,
        handle: (r, [id]) => refusing(async () => {
          const op = body(r);
          const ws = r.viewer.workspace;
          if (r.body.length > SIGNED_MAX) return error(413, "too large");
          const rig = named(ws, id!);
          if (rig.owner !== r.viewer.sub) return error(403, "only its owner makes it a whole station");
          if (!managesStation(r.viewer)) return error(403, "only the workspace's owners and admins add a whole station");
          if (!wellFormed("full", op.signed) || op.signed.body.rig !== rig.id || op.signed.body.ws !== ws || op.signed.body.sub !== r.viewer.sub) return error(422, "not signed for this station");
          try {
            await wall.within(ASK_MS, ask(rig.id, { method: "rig.full", workspace: ws, signed: op.signed, chain: op.chain ?? null }), "it did not answer");
          } catch (e) {
            if (e instanceof PeerRefused) throw new Refused(e.message);
            return error(504, (e as Error).message);
          }
          return answered({ ok: true });
        }),
      },
      {
        // This station to run only tasks from now on (`{mode: "tasks", person}`), asked of it by a member's device:
        // `person` their own lock's hash, which it will pin. Whose a station is (who added it) the machine does not
        // know: the control plane does, and lets only that member list it so (cloud/src/directory.ts
        // `setStationMode`). So the ask is kept as theirs until the control plane lists it as that same person's rig
        // (the app asks that next; cloud/presence.ts): neither alone makes it one. A station in one workspace only, as
        // a rig is.
        method: "POST", pattern: /^\/mode$/,
        handle: async (r) => {
          const op = body(r);
          if (op.mode !== "tasks" || typeof op.person !== "string" || !/^[0-9a-f]{64}$/.test(op.person)) return error(400, "mode tasks, with its person's own lock");
          if (cloud.home() !== r.viewer.workspace || cloud.memberships().length !== 1) return error(409, "a station in several workspaces stays a whole one: take it out of the others first");
          const sub = r.viewer.sub;
          cloud.update((st) => {
            st.rig_pending = { owner: sub, owner_email: r.viewer.email, owner_name: r.viewer.name ?? "", person: op.person, at: Math.floor(wall.now() / 1000) };
            delete st.rig_due;
          });
          return answered({ ok: true });
        },
      },
    ];
    parts.routes(routes);
  }),
);

/// A request as its person's app is given it back: without the lock that came with what they signed.
function publicOf(r: RigRequest | null): unknown {
  if (r === null) return null;
  const { chain: _, signed, ...rest } = r;
  return { ...rest, ...(signed ? { timeout: (signed.body as GrantBody).timeout } : {}) };
}
