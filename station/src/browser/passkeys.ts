// Passkeys in a chat's browser (docs/vault.md 登录态, docs/remote-screens.md "Passkeys of the vault"): each tab of a
// chat's context has an authenticator of Chrome's own (DevTools' WebAuthn domain, a virtual one: internal, with resident
// keys and the person verified, presence given without asking), so a site's "add a passkey" makes one there and a
// site's sign-in with a passkey is signed there, as a phone's or a laptop's would be, with no window. A context's
// passkeys are kept here by context, in memory only (as its cookies are in Chrome's): each made in a tab is heard and
// kept, each tab made after has them all, and a sign-in of the vault puts its passkeys in and takes them out again, as
// its cookies. An authenticator lasts as long as the connection that made it: the station's own to the browser, so a
// station process after this one has the vault's put in again (secrets.ts signInAgain) and those not kept are gone.
import { log } from "../ops/log.ts";
import type { Cdp, CdpEvent } from "./cdp.ts";
import { ofSites } from "./signins.ts";

/// A passkey as the vault keeps it and DevTools takes it (WebAuthn.Credential): its id, the site it is for (relying
/// party), its private key (PKCS#8), the user handle, how many times it signed (all base64 but signCount).
export type Passkey = { credentialId: string; rpId: string; privateKey: string; userHandle?: string; signCount: number };

/// What DevTools says when a tab's page is in another environment than the one asked of (it navigated).
const MOVED = /not been enabled|matching the ID/;

const OPTIONS = {
  protocol: "ctap2", ctap2Version: "ctap2_1", transport: "internal", hasResidentKey: true, hasUserVerification: true, isUserVerified: true,
  automaticPresenceSimulation: true,
};

/// A passkey of `read` (a DevTools credential) as kept; null when it is not one.
export function passkeyOf(read: any): Passkey | null {
  if (read === null || typeof read !== "object" || typeof read.credentialId !== "string" || typeof read.rpId !== "string" || typeof read.privateKey !== "string") return null;
  return {
    credentialId: read.credentialId, rpId: read.rpId, privateKey: read.privateKey,
    ...(typeof read.userHandle === "string" && read.userHandle !== "" ? { userHandle: read.userHandle } : {}),
    signCount: Number.isSafeInteger(read.signCount) && read.signCount >= 0 ? read.signCount : 0,
  };
}

/// The passkeys of `sites` (a relying party is a site's when it is the site or under it, as a cookie's domain).
export function sitePasskeys(all: Passkey[], sites: string[]): Passkey[] {
  return all.filter((p) => ofSites(p.rpId, sites));
}

/// The authenticators of the chats' tabs, on the station's connection to the browser.
export class Authenticators {
  readonly #cdp: Cdp;
  readonly #chat: (ctx: string) => boolean;
  /// Each tab with an authenticator: its context, its session on the station's connection, its authenticator.
  readonly #tabs = new Map<string, { ctx: string; session: string; id: string }>();
  // (`id` "" until it has one)
  /// Tabs being given one, by target id.
  readonly #making = new Map<string, Promise<void>>();
  /// Each context's passkeys, by credential id.
  readonly #keys = new Map<string, Map<string, Passkey>>();
  #unlisten: () => void = () => {};
  #closed = false;

  constructor(cdp: Cdp, chat: (ctx: string) => boolean) {
    this.#cdp = cdp;
    this.#chat = chat;
  }

  /// Starts: every chat's tab there now, and each after, given an authenticator.
  async start() {
    this.#unlisten = this.#cdp.on((e) => this.#heard(e));
    const { targetInfos } = await this.#cdp.send("Target.getTargets").catch(() => ({ targetInfos: [] }));
    for (const info of targetInfos ?? []) this.#tab(info);
  }

  close() {
    this.#closed = true;
    this.#unlisten();
    this.#tabs.clear();
  }

  #heard(e: CdpEvent) {
    if (e.sessionId === undefined) {
      if (e.method === "Target.targetCreated" || e.method === "Target.targetInfoChanged") this.#tab(e.params?.targetInfo);
      else if (e.method === "Target.targetDestroyed") this.#tabs.delete(e.params?.targetId);
      return;
    }
    const found = [...this.#tabs.entries()].find(([, t]) => t.session === e.sessionId);
    if (found === undefined) return;
    const [targetId, tab] = found;
    if (e.method === "Page.frameNavigated" && e.params?.frame?.parentId === undefined) {
      void this.#authenticator(targetId).catch((err) => log.warn("browser", "a chat's tab has no authenticator", { error: (err as Error).message }));
      return;
    }
    if (e.params?.authenticatorId !== tab.id) return;
    // One made in the tab (a site's "add a passkey"), or one that signed (its count): kept for the context.
    if (e.method === "WebAuthn.credentialAdded" || e.method === "WebAuthn.credentialAsserted" || e.method === "WebAuthn.credentialUpdated") {
      const p = passkeyOf(e.params?.credential);
      if (p === null) return;
      const keys = this.#keys.get(tab.ctx) ?? new Map<string, Passkey>();
      const had = keys.has(p.credentialId);
      keys.set(p.credentialId, p);
      this.#keys.set(tab.ctx, keys);
      if (!had) {
        log.info("browser", "a passkey made in a chat's tab", { rpId: p.rpId });
        void this.#everywhere(tab.ctx, [p], tab.session);
      }
    }
  }

  /// A page of a chat's context, not given one yet: given one, with the context's passkeys.
  #tab(info: any) {
    if (this.#closed || info?.type !== "page" || typeof info.targetId !== "string" || typeof info.browserContextId !== "string") return;
    if (this.#tabs.has(info.targetId) || this.#making.has(info.targetId) || !this.#chat(info.browserContextId)) return;
    const ctx: string = info.browserContextId;
    const made = (async () => {
      const { sessionId } = await this.#cdp.send("Target.attachToTarget", { targetId: info.targetId, flatten: true });
      // (its main frame's navigations heard: one may come into an environment of Chrome's other than the one the
      // authenticator was put into, 2026-11-01, a page Playwright opened, through the gate: given one there too)
      await this.#cdp.send("Page.enable", {}, sessionId);
      this.#tabs.set(info.targetId, { ctx, session: sessionId, id: "" });
      await this.#authenticator(info.targetId);
    })()
      .catch((e) => log.warn("browser", "a chat's tab has no authenticator", { error: (e as Error).message }))
      .finally(() => this.#making.delete(info.targetId));
    this.#making.set(info.targetId, made);
  }

  /// Tab `targetId` given an authenticator in the environment its page is in now, with its context's passkeys; none
  /// where it has one there (Chrome takes one internal authenticator an environment).
  async #authenticator(targetId: string) {
    // (the page may move into another environment meanwhile, as it navigates: what was enabled is then another's, an
    // authenticator another's; asked again in the one it is in)
    for (let tries = 1; ; tries++) {
      const tab = this.#tabs.get(targetId);
      if (tab === undefined) return;
      try {
        await this.#cdp.send("WebAuthn.enable", { enableUI: false }, tab.session);
        const { authenticatorId } = await this.#cdp.send("WebAuthn.addVirtualAuthenticator", { options: OPTIONS }, tab.session);
        tab.id = authenticatorId;
        for (const p of this.#keys.get(tab.ctx)?.values() ?? []) await this.#add(tab.session, authenticatorId, p);
        return;
      } catch (e) {
        const why = (e as Error).message;
        if (/one internal authenticator/.test(why)) return;
        if (tries >= 3 || !MOVED.test(why)) throw e;
      }
    }
  }

  async #add(session: string, id: string, p: Passkey) {
    await this.#cdp.send("WebAuthn.addCredential", {
      authenticatorId: id,
      credential: { credentialId: p.credentialId, isResidentCredential: true, rpId: p.rpId, privateKey: p.privateKey, signCount: p.signCount, ...(p.userHandle ? { userHandle: p.userHandle } : {}) },
    }, session);
  }

  /// `keys` put into every tab of `ctx` (but `but`'s, which has them); a tab whose page moved to another environment
  /// given an authenticator there, with all of the context's.
  async #everywhere(ctx: string, keys: Passkey[], but?: string) {
    await Promise.all([...this.#making.values()]);
    for (const [targetId, t] of this.#tabs) {
      if (t.ctx !== ctx || t.id === "" || t.session === but) continue;
      try {
        for (const p of keys) await this.#add(t.session, t.id, p);
      } catch (e) {
        if (!MOVED.test((e as Error).message)) {
          log.warn("browser", "a passkey not put into a tab", { error: (e as Error).message });
          continue;
        }
        await this.#authenticator(targetId).catch((err) => log.warn("browser", "a chat's tab has no authenticator", { error: (err as Error).message }));
      }
    }
  }

  /// The passkeys of `sites` in `ctx`, as they are now (their counts read again).
  async read(ctx: string, sites: string[]): Promise<Passkey[]> {
    await Promise.all([...this.#making.values()]);
    const keys = this.#keys.get(ctx) ?? new Map<string, Passkey>();
    for (const t of this.#tabs.values()) {
      if (t.ctx !== ctx || t.id === "") continue;
      const { credentials } = await this.#cdp.send("WebAuthn.getCredentials", { authenticatorId: t.id }, t.session).catch(() => ({ credentials: [] }));
      for (const c of credentials ?? []) {
        const p = passkeyOf(c);
        if (p === null) continue;
        const had = keys.get(p.credentialId);
        if (had === undefined || p.signCount >= had.signCount) keys.set(p.credentialId, p);
      }
    }
    this.#keys.set(ctx, keys);
    return sitePasskeys([...keys.values()], sites);
  }

  /// `keys` put into `ctx`: kept for it, in each of its tabs.
  async put(ctx: string, keys: Passkey[]) {
    if (keys.length === 0) return;
    const held = this.#keys.get(ctx) ?? new Map<string, Passkey>();
    for (const p of keys) held.set(p.credentialId, p);
    this.#keys.set(ctx, held);
    await this.#everywhere(ctx, keys);
  }

  /// The passkeys of `sites` taken out of `ctx` (each of its tabs, and what is kept for it): what they were.
  async takeOut(ctx: string, sites: string[]): Promise<Passkey[]> {
    const out = await this.read(ctx, sites);
    const held = this.#keys.get(ctx);
    for (const p of out) held?.delete(p.credentialId);
    for (const t of this.#tabs.values()) {
      if (t.ctx !== ctx || t.id === "") continue;
      for (const p of out) await this.#cdp.send("WebAuthn.removeCredential", { authenticatorId: t.id, credentialId: p.credentialId }, t.session).catch(() => {});
    }
    return out;
  }

  /// Whether `ctx` has a passkey for relying party `rpId` (a page's sign-in it can sign itself).
  has(ctx: string, rpId: string): boolean {
    const rp = rpId.toLowerCase().replace(/\.$/, "");
    for (const p of this.#keys.get(ctx)?.values() ?? []) if (p.rpId.toLowerCase() === rp) return true;
    return false;
  }

  /// A context gone (its chat's, archived, or Chrome's ended): its passkeys forgotten.
  forget(ctx: string) {
    this.#keys.delete(ctx);
  }
}
