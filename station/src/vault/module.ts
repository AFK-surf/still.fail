// The vault as a part of the station (parts.ts, docs/vault.md): its store in the station's database, the agents'
// requests for its secrets and the grants they hold, its routes (the vaults, by the lock pinned in the asker's
// workspace; the requests and grants), its tools for the agents and its events (`vault-request`), and its requests of
// the other stations (`vault.`: a command run there with a secret, a secret read there). A part of the agents' side: its
// requests are told in the agents' chats (the hub), its commands run in the remote tasks' session directories.
import { Effect, Layer } from "effect";
import { nameOf, peerNamed } from "../mesh/peer-http.ts";
import { routes as vaultRoutes } from "../api/routes/vault.ts";
import { routes as requestRoutes } from "../api/routes/vault-requests.ts";
import { wall } from "../ops/fibers.ts";
import { Browser } from "../browser/service.ts";
import { Agents } from "../sessions/agents.ts";
import { sender } from "../sessions/messages.ts";
import { ControlPlane, Events, Parts, Paths, Previous, Store } from "../services.ts";
import { vaultTools } from "./tool.ts";
import { SignIns } from "./signin.ts";
import { routes as signInRoutes } from "../api/routes/signins.ts";
import { drive } from "../browser/signin-form.ts";
import { ofSites } from "../browser/signins.ts";
import { plainStore, shown } from "./plain.ts";
import { Secrets } from "./secrets.ts";
import { vaultStore } from "./store.ts";

export const VaultLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const store = yield* Store;
    const events = yield* Events;
    const parts = yield* Parts;
    const plane = yield* ControlPlane;
    const cloud = plane.state;
    const { hub, remote } = yield* Agents;
    // A workspace's lock: the home workspace's is the station's own (null), another's by its id.
    const lock = (ws: string | null) => cloud.locked(ws === null || ws === cloud.home() ? null : ws)?.state ?? null;
    const vaults = vaultStore(store.db);
    // What the process before held may come until it is gone (it gives it as it begins to hand over).
    let coming = true;
    const previous = yield* Previous;
    const browsers = yield* Browser;
    // The vault's secrets, asked for by agents and granted from the members' apps.
    const secrets = new Secrets({
      db: store.db, vaults, plain: plainStore(store.db), hub, data, home: () => cloud.home(), lock, now: () => wall.now(),
      title: (session) => sender(hub, session)[0] ?? null,
      // Commands with a secret on another station of the workspace (docs/vault.md 在另一台 station 上用).
      peer: (given) => {
        if (given === cloud.state?.station || cloud.memberships().some((m) => m.name.toLowerCase() === given.toLowerCase())) return null;
        const { id } = peerNamed(cloud, given);
        return { id, name: nameOf(cloud, id) };
      },
      ask: (station, request) => remote.ask(station, request),
      workOf: (ws, peer, session) => remote.work(ws, peer, session),
      coming: () => coming,
      // Sign-ins (kind browser) go into each chat's own context in the station's browser (docs/vault.md 登录态).
      browsers: {
        cookies: (session, sites, station) => browsers.cookies(session, sites, station), signIn: (session, d) => browsers.signIn(session, d),
        passkeysIn: (session, d) => browsers.passkeysIn(session, d),
      },
    });
    browsers.onTakenOut((session, request, cookies) => secrets.renewed(session, request, cookies));
    browsers.onFresh((session) => secrets.signInAgain(session));
    browsers.onResumed((session) => secrets.passkeysAgain(session));
    // A site signed in to from a card (signin.ts): the vault's sign-in for it asked for, else the person's own
    // password manager filling the chat's tab.
    const covers = (hosts: string[], site: string) => ofSites(site, hosts) || hosts.some((h) => ofSites(h, [site]));
    const signIns = new SignIns({
      db: store.db, hub, now: () => wall.now(), after: (ms, f) => wall.after(ms, f),
      workspace: (session) => store.getSession(session)?.ws ?? cloud.home(),
      screenLink: (tab) => {
        const s = cloud.state;
        return s && s.workspace && plane.spec().pages ? `${s.origin}/w/${s.workspace}/s/${s.station}/screen/${encodeURIComponent(`browser:${tab}`)}` : null;
      },
      browser: {
        tabs: (session) => browsers.tabs(session),
        look: async (session, tab) => {
          const form = await browsers.form(session, tab);
          try {
            return await form.look();
          } finally {
            form.close();
          }
        },
        drive: async (session, tab, site, values, used) => {
          const form = await browsers.form(session, tab);
          try {
            return await drive(form, site, values, used, (ms) => wall.sleep(ms));
          } finally {
            form.close();
          }
        },
      },
      vault: {
        listed: (session, site) => secrets.listings(session).find((l) => l.listing.kind === "browser" && covers(l.listing.hosts, site))?.item ?? null,
        held: (session, site) => {
          const h = secrets.held(session).find((g) => g.grant.mode === "browser" && covers(g.grant.hosts, site));
          return h === undefined ? null : `A sign-in to ${h.grant.hosts.join(", ")} is granted to this chat already (grant ${h.request.id}, until ${new Date(h.grant.exp * 1000).toISOString()}): it is in this chat's browser.`;
        },
        use: (session, item, reason) => secrets.ask(session, { item, mode: "browser", reason }),
        keep: (session, site, reason, made) => {
          const on = secrets.status(session);
          return secrets.save(session, { name: `${site} 登录态`, kind: "browser", hosts: [site], reason, cwd: "", ...(on === "on" || on === "plain" ? { quiet: made } : {}) });
        },
      },
    });
    secrets.listen((r) => signIns.heard(r));
    secrets.onPlainWritten((i) => events.tell("vault-plain", shown(i), `vault-plain\0${i.id}`, { workspace: i.ws, email: i.owner }));
    // The grants, the boxes of requests waiting and the secrets to keep, only in memory: over to the next process at a
    // handover (an update), so no agent asks again.
    parts.carry("vault", () => secrets.carried(), (what) => {
      secrets.carry(what);
      came();
    });
    remote.bus.on("vault.", (peer, request, workspace) => secrets.heard(peer, workspace ?? cloud.home() ?? "", request));
    secrets.listen((r) => {
      const to = secrets.tells(r);
      if (to !== null) events.tell("vault-request", r, `vault-request\0${r.id}`, to);
    });
    events.follow({ inVault: (viewer, vault) => secrets.inVault(viewer, vault) });
    // Once nothing more comes, the requests still waiting whose boxes did not come (a restart) get new ones.
    function came() {
      if (!coming) return;
      coming = false;
      secrets.reboxed();
      // (the grants carried over or restored: their passkeys into the contexts taken up)
      browsers.passkeysAgain();
    }
    void previous.gone.then(came, came);
    parts.routes([
      ...vaultRoutes({ vaults, lock: (ws) => lock(ws), events, boxed: (l, cert) => secrets.boxed(l, cert) }),
      ...requestRoutes({ secrets, plain: secrets.plain, lock: (ws) => lock(ws), events }),
      ...signInRoutes(signIns),
    ]);
    parts.tools(vaultTools(secrets, (k) => store.getSession(k)?.workspace ?? null, signIns));
  }),
);
