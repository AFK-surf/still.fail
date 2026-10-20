// The station's logins to command-line tools (docs/remote-login.md) as a part of the station (parts.ts): each told on
// the event streams as it changes, its screen followed by the pages; one an agent started tells that agent as it asks
// something and as it ends, its cards closed. Its routes (machine-logins) and the agents' `login` tool.
import { Effect, Layer } from "effect";
import { routes } from "../api/routes/logins.ts";
import { readOnly } from "../mesh/credential.ts";
import { log } from "../ops/log.ts";
import { Agents } from "../sessions/agents.ts";
import { sender } from "../sessions/messages.ts";
import { ControlPlane, Events, Parts, Paths, Readers, Store } from "../services.ts";
import { endedNotice, loginTools, promptNotice } from "../tools/login.ts";
import { Logins } from "./index.ts";

export const LoginsLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const events = yield* Events;
    const readers = yield* Readers;
    const plane = yield* ControlPlane;
    const parts = yield* Parts;
    const { hub, place } = yield* Agents;
    const logins = yield* Effect.acquireRelease(Effect.sync(() => new Logins({ data, clock: hub.clock })), (l) => Effect.promise(() => l.close()));
    const loginLink = (session: string | null, id: string) => {
      const s = place();
      if (!s || !plane.spec().pages) return null;
      const ws = (session ? store.getSession(session)?.ws : null) ?? s.workspace;
      return `${s.origin}/w/${ws}/s/${s.station}/login/${encodeURIComponent(id)}`;
    };
    /// The logins whose agent was told they ask something (once a time they do).
    const asking = new Set<string>();
    const unlisten = [
      logins.changes((change) => {
        const login = logins.get(change.login);
        if (!login) return;
        events.machineLogins({ login }, { login: Logins.limited(login) }, readOnly, `login\0${login.id}`);
        // Asking something again after its person's browser step (az picking a subscription, say): its agent answers.
        const asks = login.waiting && login.paste !== true && login.endedAt === undefined && logins.hadBrowserStep(login.id);
        if (asks && !asking.has(login.id) && login.chat) {
          try {
            hub.notify(login.chat, promptNotice(logins, login, loginLink(login.chat, login.id)));
          } catch (error) {
            log.warn("logins", "an agent was not told its login asks something", { login: login.id, error: (error as Error).message });
          }
        }
        if (asks) asking.add(login.id);
        else asking.delete(login.id);
      }),
      // Told: the agent that started it, and each that posted its card (one may post a card for a login under way).
      logins.onEnded((login, starter) => {
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
    parts.tools(
      loginTools({
        logins: () => logins,
        // The chat's starter: whom the agent works for.
        starter: (session) => {
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
        },
        link: (session, id) => loginLink(session, id),
      }),
    );
  }),
);
