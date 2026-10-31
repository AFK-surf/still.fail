// The station's logins to command-line tools (docs/remote-login.md) as a part of the station (parts.ts): each told on
// the event streams as it changes, its screen followed by the pages; one an agent started tells that agent as it asks
// something and as it ends, its cards closed. Its routes (machine-logins) and the agents' `login` tool. A login on
// another station of the workspace (the tool's `station`) is that station's, asked over the station transport
// (`login.call`); it tells the agent here as it asks something and as it ends (`login.told`). A login's page, and a
// profile's sign-in's, opened in the station's own browser for a person to finish there (pages.ts).
import { Effect, Layer } from "effect";
import { pageRoutes, routes } from "../api/routes/logins.ts";
import { Browser } from "../browser/service.ts";
import { Refused } from "../mesh/bus.ts";
import { nameOf, peerNamed } from "../mesh/peer-http.ts";
import { log } from "../ops/log.ts";
import { Agents } from "../sessions/agents.ts";
import { sender } from "../sessions/messages.ts";
import { ControlPlane, Events, Parts, Paths, Peers, Readers, ScreenRegistry, Store } from "../services.ts";
import { act, endedNotice, loginTools, promptNotice, type Where } from "./tool.ts";
import { Logins, type Starter } from "./index.ts";
import { LoginPages } from "./pages.ts";

export const LoginsLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const events = yield* Events;
    const readers = yield* Readers;
    const plane = yield* ControlPlane;
    const parts = yield* Parts;
    const bus = yield* Peers;
    const cloud = plane.state;
    const { hub, place, accounts } = yield* Agents;
    const browser = yield* Browser;
    const screens = yield* ScreenRegistry;
    const pages = new LoginPages(browser.station, (changed) => screens.watch(() => changed()));
    const logins = yield* Effect.acquireRelease(Effect.sync(() => new Logins({ data, clock: hub.clock, pages })), (l) => Effect.promise(() => l.close()));
    accounts.logins.attach(pages);
    const loginLink = (session: string | null, id: string) => {
      const s = place();
      if (!s || !plane.spec().pages) return null;
      const ws = (session ? store.getSession(session)?.ws : null) ?? s.workspace;
      return `${s.origin}/w/${ws}/s/${s.station}/login/${encodeURIComponent(id)}`;
    };
    /// The logins whose agent was told they ask something (once a time they do).
    const asking = new Set<string>();
    /// This station as an agent on another one is told of a login here.
    const here = (): Where => {
      const id = place()?.station ?? "";
      return { station: id, name: nameOf(cloud, id) };
    };
    /// What a login another station's agent started tells it (its session there): as it asks something, as it ends.
    const tellPeer = (starter: Starter, id: string, text: string, ended: boolean) => {
      const peer = starter.peer;
      if (!peer) return;
      bus.ask(peer.station, { method: "login.told", workspace: starter.workspace, session: peer.session, login: id, ended, text }).catch((error) =>
        log.warn("logins", "another station's agent was not told of its login", { login: id, station: peer.station, error: (error as Error).message }),
      );
    };
    const unlisten = [
      logins.changes((change) => {
        const login = logins.get(change.login);
        if (!login) return;
        events.machineLogins({ login }, { login: Logins.limited(login) }, `login\0${login.id}`);
        // Asking something again after its person's browser step (az picking a subscription, say): its agent answers. An
        // agent whose call waits on it is told by that call.
        const asks = login.waiting && login.paste !== true && login.endedAt === undefined && logins.hadBrowserStep(login.id);
        const tell = asks && !asking.has(login.id) && !logins.heard(login.id);
        if (tell && login.chat) {
          try {
            hub.notify(login.chat, promptNotice(logins, login, loginLink(login.chat, login.id)));
          } catch (error) {
            log.warn("logins", "an agent was not told its login asks something", { login: login.id, error: (error as Error).message });
          }
        }
        const starter = logins.starterOf(login.id);
        if (tell && starter?.peer) tellPeer(starter, login.id, promptNotice(logins, login, loginLink(null, login.id), here()), false);
        if (asks) asking.add(login.id);
        else asking.delete(login.id);
      }),
      // Told: the agent that started it, and each that posted its card (one may post a card for a login under way).
      logins.onEnded((login, starter) => {
        // Another station's agent started it: told there, where its cards are.
        if (starter.peer) return tellPeer(starter, login.id, endedNotice(login, loginLink(null, login.id), here()), true);
        let carded: string[] = [];
        try {
          carded = store.closeLoginCards(login.id);
        } catch (error) {
          log.warn("logins", "a login's cards were not closed", { login: login.id, error: (error as Error).message });
        }
        for (const session of new Set([...(starter.chat ? [starter.chat] : []), ...carded])) {
          try {
            hub.notify(session, endedNotice(login, loginLink(session, login.id)));
          } catch (error) {
            log.warn("logins", "an agent was not told a login ended", { login: login.id, session, error: (error as Error).message });
          }
        }
      }),
    ];
    yield* Effect.addFinalizer(() => Effect.sync(() => unlisten.forEach((stop) => stop())));
    // A login's screen, followed on the event streams (`login=`).
    events.follow({ loginScreen: (id, send) => logins.follow(id, send) });
    parts.routes(routes(() => logins));
    parts.routes(pageRoutes(() => logins, () => accounts));
    // The chat's starter: whom the agent works for.
    const starterOf = (session: string): Starter => {
      const row = store.getSession(session);
      const email = row?.createdBy ?? "";
      // Its chat's name; one not named yet, by what was first said in it (as a shared chat is titled).
      let chatTitle: string | null = null;
      try {
        chatTitle = sender(hub, session)[0];
      } catch {}
      if (chatTitle === null || chatTitle === session) {
        const first = store.listThreads("", session, null)[0]?.firstText?.trim() ?? "";
        chatTitle = first !== "" ? Array.from(first.split(/\s+/u).join(" ")).slice(0, 80).join("") : null;
      }
      return { by: { email, name: readers.names.get(email) ?? "" }, workspace: row?.ws ?? place()?.workspace ?? null, chat: session, chatTitle };
    };
    // Another station's agent logging this one in: its call acted on here, on the logins it started; and a login of
    // this station's agents on another one telling them of it.
    bus.on("login.", async (peer, request, workspace) => {
      if (request?.method === "login.call") {
        const args = request.args && typeof request.args === "object" ? (request.args as Record<string, unknown>) : {};
        const session = typeof request.session === "string" ? request.session : "";
        const by = request.by && typeof request.by.email === "string" ? { email: String(request.by.email), name: String(request.by.name ?? "") } : { email: "", name: "" };
        const chatTitle = typeof request.chatTitle === "string" ? request.chatTitle : null;
        const starter = (): Starter => ({ by, workspace: workspace ?? null, chat: null, chatTitle, peer: { station: peer, session } });
        try {
          const text = await act(logins, args, { starter, link: (id) => loginLink(null, id), where: here(), mine: (id) => logins.starterOf(id)?.peer?.station === peer });
          return { text };
        } catch (error) {
          throw new Refused((error as Error).message);
        }
      }
      if (request?.method === "login.told") {
        const session = typeof request.session === "string" ? request.session : "";
        if (!store.getSession(session) || typeof request.text !== "string") throw new Refused("no such session");
        if (request.ended === true && typeof request.login === "string") {
          try {
            store.closeLoginCards(request.login);
          } catch (error) {
            log.warn("logins", "a login's cards were not closed", { login: request.login, error: (error as Error).message });
          }
        }
        hub.notify(session, request.text);
        return {};
      }
      throw new Refused(`unknown method ${String(request?.method)}`);
    });
    parts.tools(
      loginTools({
        logins: () => logins,
        starter: starterOf,
        link: (session, id) => loginLink(session, id),
        remote: async (station, session, args) => {
          const { id } = peerNamed(cloud, station);
          const starter = starterOf(session);
          const { station: _, ...rest } = args;
          try {
            const answer = await bus.ask(id, { method: "login.call", workspace: starter.workspace, session, by: starter.by, chatTitle: starter.chatTitle ?? null, args: rest });
            if (typeof answer?.text !== "string") throw new Error(`${nameOf(cloud, id)} gave no answer`);
            return answer.text;
          } catch (error) {
            // A station from before this has no `login.call`: told so, not as the login's own failure.
            if (error instanceof Refused && /unknown|not found|no such method/i.test(error.message) && /login/i.test(error.message)) throw new Error(`${nameOf(cloud, id)} runs a still.fail that cannot be logged in from another station yet: update it, or log in on it from a chat of its own`);
            throw error;
          }
        },
      }),
    );
  }),
);
