// Phones lent to the station over members' links (adb/link.ts) as a part of the station (parts.ts): the offers and asks
// that come on a member's link, the agents' tool that lists them, with the station's page for them in the app.
import { Effect, Layer } from "effect";
import { writeLine } from "../mesh/serve.ts";
import { readOnly } from "../mesh/credential.ts";
import { Agents } from "../sessions/agents.ts";
import { wall } from "../ops/fibers.ts";
import { AndroidScreens } from "../screens/android.ts";
import { ControlPlane, Events, Parts, Paths, Previous, ScreenRegistry, Store } from "../services.ts";
import { join } from "node:path";
import { runnerId } from "../agents/process.ts";
import { runnerOf } from "../agents/runner.ts";
import { RUNTIME_KINDS } from "../agents/runtime.ts";
import { watchedJobs } from "../jobs/memory.ts";
import { platform } from "../platform/index.ts";
import { gate } from "./door.ts";
import { type PhoneRequest, PhoneGrants, type Scope } from "./grants.ts";
import { GrantServers } from "./servers.ts";
import { PhoneDisplays } from "./displays.ts";
import { grantChatTitle } from "./title.ts";
import { adbTools, phoneTools, reached } from "./tool.ts";
import { Shares, adbPath, answerAdb } from "./link.ts";

export const AdbLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const plane = yield* ControlPlane;
    const parts = yield* Parts;
    const { hub, cardOutcomes } = yield* Agents;
    const store = yield* Store;
    const events = yield* Events;
    const screens = yield* ScreenRegistry;
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
      runners: (id) => {
        const key = sessionOf(id);
        return key === null ? [] : RUNTIME_KINDS.flatMap((kind) => {
          const r = runnerOf(data, runnerId(kind, key));
          return r === undefined ? [] : [r.runner, r.pid];
        });
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
            stated: (email, state) => grants.linked(email, state),
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
        if (ask.op === "grants") return reply(200, { grants: grants.ofOwner(email, viewer.workspace), lasts: grants.lastsOf(email), signs: true });
        if (ask.op === "lasts") {
          const why = grants.setLasts(email, ask.lasts, ask.at);
          return why === null ? reply(200, { lasts: grants.lastsOf(email) }) : reply(422, { message: why });
        }
        const id = typeof ask.request === "string" ? ask.request : "";
        const scope = ask.scope === "hour" || ask.scope === "chat" ? (ask.scope as Scope) : null;
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
    parts.tools(
      phoneTools(grants, async (owner, grant) => {
        const phones = lent.list().filter((p) => p.owner.email.toLowerCase() === owner);
        const server = phones.length > 0 ? await servers.ensure(grant) : null;
        // Its own screen, made once the phone is in the grant's server (the first phone: one person lends one).
        const phone = phones.find((p) => p.adb === "connected");
        const display = server === null || phone === undefined ? null
          : await displays.open(grant, owner, nameOf(grant), server.port, phone.serial).catch((error) => ({ failed: (error as Error).message }));
        return reached(phones, server?.port ?? null, lent.gone.get(owner) ?? null, display);
      }),
    );
    parts.tools(
      // Phones lent with an app's switch (from before grants): any agent's. A phone granted to chats is theirs alone.
      adbTools(() => lent.list().filter((p) => grants.grantedOfOwner(p.owner.email).length === 0)),
    );
  }),
);
