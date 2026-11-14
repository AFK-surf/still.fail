// Phones lent to the station over members' links (adb/link.ts) as a part of the station (parts.ts): the offers and asks
// that come on a member's link, the agents' tool that lists them, with the station's page for them in the app.
import { Effect, Layer } from "effect";
import { writeLine } from "../mesh/serve.ts";
import { readOnly } from "../mesh/credential.ts";
import { Agents } from "../sessions/agents.ts";
import type { Json } from "../store/store.ts";
import { wall } from "../ops/fibers.ts";
import { AndroidScreens } from "../screens/android.ts";
import { createHash } from "node:crypto";
import { ControlPlane, type DeviceEntry, DeviceSources, Events, Parts, Paths, Previous, ScreenRegistry, Store } from "../services.ts";
import { join } from "node:path";
import { runnerId } from "../agents/process.ts";
import { runnerOf } from "../agents/runner.ts";
import { RUNTIME_KINDS } from "../agents/runtime.ts";
import { watchedJobs } from "../jobs/memory.ts";
import { platform } from "../platform/index.ts";
import { gate } from "./door.ts";
import { type PhoneRequest, PhoneGrants, type Scope, isScope, said, scopeSaid } from "./grants.ts";
import { GrantServers } from "./servers.ts";
import { PhoneDisplays } from "./displays.ts";
import { grantChatTitle } from "./title.ts";
import { PHONE_SEND, adbTools, phoneTools, reached } from "./tool.ts";
import { fetchOnPhone, staged } from "./send.ts";
import { Shares, adbPath, answerAdb } from "./link.ts";

export const AdbLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const plane = yield* ControlPlane;
    const parts = yield* Parts;
    const { hub, cardOutcomes } = yield* Agents;
    const store = yield* Store;
    const events = yield* Events;
    const screens = yield* ScreenRegistry;
    const sources = yield* DeviceSources;
    // The emulators and phones on this machine's own adb, each a screen while it is.
    yield* Effect.acquireRelease(
      Effect.sync(() => {
        const androids = new AndroidScreens({ screens, adb: adbPath });
        // Followed as the screens are asked for (`refresh`), not from the start.
        const unrefresh = screens.refresher(() => androids.refresh());
        return () => (unrefresh(), androids.close());
      }),
      (stop) => Effect.sync(stop),
    );
    const { data } = yield* Paths;
    const previous = yield* Previous;
    // Who may use a grant's adb server: its session, by the machine's processes (door.ts). None read on Windows.
    let sessionOf = (_grant: string): string | null => null;
    const admit = platform.os === "windows" ? null : (grant: string, holders: number[]) => gate({
      session: (id) => {
        const key = sessionOf(id);
        return key === null ? null : { workspace: store.getSession(key)?.workspace ?? null };
      },
      table: () => platform.processTable(false),
      runners: async (id) => {
        const key = sessionOf(id);
        if (key === null) return [];
        const found = await Promise.all(RUNTIME_KINDS.map((kind) => runnerOf(data, runnerId(kind, key))));
        return found.flatMap((r) => (r === undefined ? [] : [r.runner, r.pid]));
      },
      jobs: () => watchedJobs(store, hub.processJobLookup()).map((j) => ({ pgid: j.pgid, mine: (id: string) => j.session === sessionOf(id) })),
      cwds: (pids) => platform.cwds(pids),
      self: process.pid,
    }, grant, holders);
    const servers = yield* Effect.acquireRelease(Effect.sync(() => new GrantServers(adbPath, join(data, "run", "adb-servers.json"), admit)), (s) => Effect.promise(() => s.close()));
    void servers.reap(previous.gone).catch(() => undefined);
    // Chats' grants of people's phones: told to the owner's devices, their phones connected anew in
    // the grants' adb servers, a grant's server stopped as it ends.
    let shares: Shares | null = null;
    // The chats' own screens on the phones (displays.ts): their phones' offers say which chats have one up.
    let grantsOf: PhoneGrants | null = null;
    const displays = yield* Effect.acquireRelease(
      Effect.sync(() =>
        new PhoneDisplays({
          adb: adbPath,
          usedAt: (id) => {
            const r = grantsOf?.get(id) ?? null;
            return r === null || r.status !== "granted" ? null : (r.lastUsedAt ?? 0);
          },
          changed: (owner) => shares?.screens(owner, displays.titles(owner)),
        }),
      ),
      (d) => Effect.sync(() => d.closeAll()),
    );
    const grants = new PhoneGrants({
      db: store.db, hub: hub as any, cardOutcomes, home: () => plane.state.home(), now: () => wall.now(),
      title: (r) => grantChatTitle(store, r),
      told: (r: PhoneRequest, workspace, change) => {
        if (workspace !== null) events.tell("adb-grant", r, `adb-grant\0${r.id}`, { workspace, email: r.owner });
        if (change === "grant") sources.changed?.(workspace);
        if (change !== "grant") return;
        if (r.status === "denied" || r.status === "ended") {
          // (its display's apps closed through the grant's adb server first)
          void displays.close(r.id).then(() => servers.stop(r.id));
        }
        shares?.regrant(r.owner);
        // (granted while the phone is offered here already: its card says at once how it is held)
        const held = r.status === "granted" ? [...(shares?.byKey.values() ?? [])].find((s) => s.owner.email.toLowerCase() === r.owner) : undefined;
        if (held !== undefined) grants.linked(r.owner, held.state);
      },
    });
    grantsOf = grants;
    sessionOf = (id) => grants.get(id)?.session ?? null;
    shares = yield* Effect.acquireRelease(
      Effect.sync(
        () =>
          new Shares({
            cloud: plane.state,
            servers,
            granted: (email) => grants.grantedOfOwner(email).map((r) => r.id),
            stated: (email, state) => {
              grants.linked(email, state);
              // (the members' list of devices says the phones lent here: devices/module.ts)
              sources.changed?.(null);
            },
            used: (id, force) => grants.used(id, force),
          }),
      ),
      (s) => Effect.promise(() => s.close()),
    );
    const lent = shares;
    // An offer or an ask (its send side came finished, what it hears goes down the stream).
    parts.streams("adb", async ({ conn, viewer, head, stream, reader }) => {
      // Lending a phone is a change a read-only member does not make.
      if (readOnly(viewer)) {
        await writeLine(stream, { status: 403, headers: { "content-type": "application/json" } });
        await stream.write(Buffer.from(JSON.stringify({ error: "read-only members cannot lend or use phones" })));
        return stream.finish();
      }
      // A grant decided, taken back, or the owner's grants listed (from their app).
      const ask = head.adb ?? {};
      if (ask.op === "decide" || ask.op === "revoke" || ask.op === "grants" || ask.op === "lasts" || ask.op === "sign") {
        const reply = async (status: number, body: unknown) => {
          await writeLine(stream, { status, headers: { "content-type": "application/json" } });
          await stream.write(Buffer.from(JSON.stringify(body)));
          await stream.finish();
        };
        const email = viewer.email.toLowerCase();
        // (`lasts`, and the `lasts` op answered with it: for cores from before, whose 默认最长授权 capped a card's
        // lengths; nothing caps them now. Goes 7 days after this ships.)
        if (ask.op === "grants") return reply(200, { grants: grants.ofOwner(email, viewer.workspace), lasts: "chat", signs: true });
        if (ask.op === "lasts") return reply(200, { lasts: "chat" });
        const id = typeof ask.request === "string" ? ask.request : "";
        const scope = isScope(ask.scope) ? (ask.scope as Scope) : null;
        const why = ask.op === "sign" ? grants.sign(email, id, ask.signed, viewer.workspace) : ask.op === "decide" ? grants.decide(email, id, scope, viewer.workspace, ask.signed) : grants.revoke(email, id, viewer.workspace);
        const request = grants.get(id);
        return why === null ? reply(200, { request: request === null ? null : grants.shown(request) }) : reply(422, { message: why });
      }
      return answerAdb(lent, conn, viewer, head, stream, reader);
    });
    // What the phone's notification names a chat by: its title, else what its agent asked the phone for.
    const nameOf = (grant: string) => {
      const r = grants.get(grant);
      return r === null ? "" : grants.shown(r).chatTitle || r.reason.slice(0, 40);
    };
    const reach = async (owner: string, grant: string) => {
      const phones = lent.list().filter((p) => p.owner.email.toLowerCase() === owner);
      const server = phones.length > 0 ? await servers.ensure(grant) : null;
      // Its own screen, made once the phone is in the grant's server (the first phone: one person lends one).
      const phone = phones.find((p) => p.adb === "connected");
      const display = server === null || phone === undefined ? null
        : await displays.open(grant, owner, nameOf(grant), server.port, phone.serial).catch((error) => ({ failed: (error as Error).message }));
      return reached(phones, server?.port ?? null, lent.gone.get(owner) ?? null, display);
    };
    parts.tools(phoneTools(grants, reach));
    // The phones among the workspace's devices (devices/module.ts): those lent to this station now, any member's, each
    // its person's to grant (device_use asks them, as phone_use asks the person the chat's agent works for).
    const phoneId = (email: string, serial: string) => createHash("sha256").update(`${email.toLowerCase()}\0${serial}`).digest("hex").slice(0, 16);
    const phoneEntries = (session: string): DeviceEntry[] => {
      const self = plane.state.state?.station ?? "";
      return lent.list().map((p): DeviceEntry => {
        const email = String(p.owner?.email ?? "").toLowerCase();
        const mine = grants.held(session).find((r) => r.owner === email);
        const shared = grants.grantedOfOwner(email).length === 0;
        const pending = grants.ofOwner(email).find((r) => r.session === session && r.status === "pending");
        return {
          id: phoneId(email, String(p.serial)), name: `${p.owner?.name || email} 的 ${p.device || "手机"}`, kind: "adb", target: String(p.serial),
          via: "phone", station: self, stationName: "", owner: email, ownerEmail: email, ownerName: String(p.owner?.name ?? ""), online: p.adb === "connected",
          thisChat: mine !== undefined ? `granted to this chat (${scopeSaid(mine.scope)}): device_use gives it`
            : pending !== undefined ? `asked: waits for ${email} to approve request ${pending.id} on the card in your chat`
            : shared ? "shared with every agent of this station by its app: adb -s <target> on this machine's own adb"
            : `no grant: ask with device_use {device: "<its name>", reason}; its card goes to ${email}`,
          hasAccess: shared ? "every agent of this station" : grants.ofOwner(email).filter((r) => r.status === "granted").map((r) => r.chatTitle ? `"${r.chatTitle}"` : r.chat),
        };
      });
    };
    sources.phones = {
      list: async (_ws, session) => phoneEntries(session),
      use: async (_ws, session, e, reason, _timeout, signal) => {
        const owner = e.ownerEmail.toLowerCase();
        let r = await grants.ask(session, reason, false, signal, owner === "" ? undefined : owner);
        if (r.status === "pending") {
          const pending = await grants.cardPending(r, signal);
          r = grants.get(r.id) ?? r;
          if (r.status === "pending" && pending === false) return `The phone request ${r.id} is still pending, but its card is no longer pending. If it is still needed, call phone_use again with the same reason and reask: true.`;
        }
        if (r.status === "granted") return await reach(r.owner, r.id);
        return said(r);
      },
      done: (_ws, session, e) => grants.release(session, e === null ? undefined : e.ownerEmail).map((r) => `${r.owner} 的手机`),
      // What the members are shown: each phone lent here, whose, and the chats of this workspace that hold it.
      shown: (ws) => lent.list().map((p) => {
        const email = String(p.owner?.email ?? "").toLowerCase();
        const held = grants.ofOwner(email, ws).filter((r) => r.status === "granted");
        return {
          id: phoneId(email, String(p.serial)), name: `${p.owner?.name || email} 的 ${p.device || "手机"}`, target: String(p.serial), ownerEmail: email,
          ownerName: String(p.owner?.name ?? ""), online: p.adb === "connected", open: grants.grantedOfOwner(email).length === 0,
          grants: held.map((r) => ({
            request: r.id, session: r.session, chat: r.chat, title: r.chatTitle ?? "", by: grants.starter(r.session) ?? "",
            timeoutKind: r.scope === "idle" ? "idle" : r.scope === "chat" ? "chat" : "fixed", timeoutSeconds: r.scope === "hour" ? 3600 : r.scope === "eight" ? 28800 : r.scope === "idle" ? 3600 : 0, exp: r.exp ?? 0,
            until: r.scope === "idle" ? Math.min(r.exp ?? 0, Math.floor((r.lastUsedAt ?? 0) / 1000) + 3600) : (r.exp ?? 0),
          })),
        } as unknown as Json;
      }),
    };
    yield* Effect.addFinalizer(() => Effect.sync(() => void (sources.phones = null)));
    parts.tools([
      {
        ...PHONE_SEND,
        run: async (session, args, signal) => {
          const grant = grants.held(session)[0];
          if (grant === undefined) return "This chat holds no phone grant: ask for the phone with phone_use first.";
          const share = [...lent.byKey.values()].find((s) => s.owner.email.toLowerCase() === grant.owner);
          if (share === undefined) return "Granted, but the phone is not lent to this station right now: call phone_use to see why.";
          const workspace = store.getSession(session)?.workspace;
          if (workspace === undefined) throw new Error(`unknown session ${session}`);
          const { name, size } = await staged(workspace, typeof args.path === "string" ? args.path : "");
          grants.used(grant.id, true);
          const r = await fetchOnPhone(share.conn, session, name, size, () => grants.used(grant.id, true), signal);
          if ("path" in r) return `On the phone at ${r.path} (${size} bytes). pm cannot read that folder: to install an APK, adb … shell 'cp ${r.path} /data/local/tmp/a.apk && pm install -r /data/local/tmp/a.apk'.`;
          if (r.old) return "The still.fail app on the phone is too old to take files this way: use adb push, or ask its person to update the app.";
          return `Not all there: the phone has ${r.at} of ${size} bytes (${r.error}). Call phone_send again to go on from there.`;
        },
      },
    ]);
    parts.tools(
      // Phones lent with an app's switch (from before grants): any agent's. A phone granted to chats is theirs alone.
      adbTools(() => lent.list().filter((p) => grants.grantedOfOwner(p.owner.email).length === 0)),
    );
  }),
);
