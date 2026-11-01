// Phones lent to the station over members' links (adb/link.ts) as a part of the station (parts.ts): the offers and asks
// that come on a member's link, the agents' tool that lists them, with the station's page for them in the app.
import { Effect, Layer } from "effect";
import { writeLine } from "../mesh/serve.ts";
import { readOnly } from "../mesh/credential.ts";
import { titleOf } from "../read/views.ts";
import { STILLFAIL_SURFACE } from "../store/store.ts";
import { Agents } from "../sessions/agents.ts";
import { wall } from "../ops/fibers.ts";
import { ControlPlane, Events, Parts, Store } from "../services.ts";
import { type PhoneRequest, PhoneGrants, type Scope } from "./grants.ts";
import { GrantServers } from "./servers.ts";
import { adbTools, phoneTools, reached } from "./tool.ts";
import { Shares, adbPath, answerAdb } from "./link.ts";

export const AdbLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const plane = yield* ControlPlane;
    const parts = yield* Parts;
    const { hub } = yield* Agents;
    const store = yield* Store;
    const events = yield* Events;
    const servers = yield* Effect.acquireRelease(Effect.sync(() => new GrantServers(adbPath)), (s) => Effect.promise(() => s.close()));
    // Chats' grants of people's phones (docs/adb-share.md): told to the owner's devices, their phones connected anew in
    // the grants' adb servers, a grant's server stopped as it ends.
    let shares: Shares | null = null;
    const grants = new PhoneGrants({
      db: store.db, hub: hub as any, home: () => plane.state.home(), now: () => wall.now(),
      title: (r) => {
        const slash = r.chat.indexOf("/");
        const own = slash < 0 ? null : store.sessionThread(r.session, r.chat.slice(0, slash), r.chat.slice(slash + 1))?.thread ?? null;
        const latest = store.sessionChat(r.session);
        const thread = own ?? latest?.thread;
        if (!thread) return null;
        const named = thread.title?.trim() || thread.autoTitle?.trim();
        if (named) return named;
        if (thread.surface === STILLFAIL_SURFACE) return null;
        return titleOf(thread, latest?.thread.id === thread.id ? latest.firstText : null, null);
      },
      told: (r: PhoneRequest, workspace, change) => {
        if (workspace !== null) events.tell("adb-grant", r, `adb-grant\0${r.id}`, { workspace, email: r.owner });
        if (change !== "grant") return;
        if (r.status === "denied" || r.status === "ended") void servers.stop(r.id);
        shares?.regrant(r.owner);
        // (granted while the phone is offered here already: its card says at once how it is held)
        const held = r.status === "granted" ? [...(shares?.byKey.values() ?? [])].find((s) => s.owner.email.toLowerCase() === r.owner) : undefined;
        if (held !== undefined) grants.linked(r.owner, held.state);
      },
    });
    shares = yield* Effect.acquireRelease(
      Effect.sync(
        () =>
          new Shares({
            cloud: plane.state,
            servers,
            granted: (email) => grants.ofOwner(email).filter((r) => r.status === "granted").map((r) => r.id),
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
      if (ask.op === "decide" || ask.op === "revoke" || ask.op === "grants" || ask.op === "lasts") {
        const reply = async (status: number, body: unknown) => {
          await writeLine(stream, { status, headers: { "content-type": "application/json" } });
          await stream.write(Buffer.from(JSON.stringify(body)));
          await stream.finish();
        };
        const email = viewer.email.toLowerCase();
        if (ask.op === "grants") return reply(200, { grants: grants.ofOwner(email, viewer.workspace), lasts: grants.lastsOf(email) });
        if (ask.op === "lasts") {
          const why = grants.setLasts(email, ask.lasts, ask.at);
          return why === null ? reply(200, { lasts: grants.lastsOf(email) }) : reply(422, { message: why });
        }
        const id = typeof ask.request === "string" ? ask.request : "";
        const scope = ask.scope === "hour" || ask.scope === "chat" ? (ask.scope as Scope) : null;
        const why = ask.op === "decide" ? grants.decide(email, id, scope, viewer.workspace) : grants.revoke(email, id, viewer.workspace);
        const request = grants.get(id);
        return why === null ? reply(200, { request: request === null ? null : grants.shown(request) }) : reply(422, { message: why });
      }
      return answerAdb(lent, conn, viewer, head, stream, reader);
    });
    parts.tools(
      phoneTools(grants, async (owner, grant) => {
        const phones = lent.list().filter((p) => p.owner.email.toLowerCase() === owner);
        const server = phones.length > 0 ? await servers.ensure(grant) : null;
        return reached(phones, server?.port ?? null, lent.gone.get(owner) ?? null);
      }),
    );
    parts.tools(
      // Phones lent with an app's switch (from before grants): any agent's. A phone granted to chats is theirs alone.
      adbTools(() => lent.list().filter((p) => !grants.ofOwner(p.owner.email).some((r) => r.status === "granted"))),
    );
  }),
);
