// What a chat's agent may do over its connection to the station's browser (docs/remote-screens.md, "A chat's own
// environment"): the browser is one Chrome for every chat, each chat's pages in a browser context of its own (in memory:
// browsers.ts), and the gate between the agent's connection and Chrome's DevTools lets through only what touches that
// context. It reads every message the agent sends: one on a target session goes only to a session of a target of its
// own; one to the browser itself only when its method is among those below, its targets its own and its context
// (cookies, permissions, downloads, new tabs) put as its own. Of what Chrome sends, it reads only the browser's own news
// of targets (small) and the answers it asked to look at: news of another chat's target never reaches the agent, and a
// target it was attached to on its own (auto-attach) is let go of at once. What it refuses is answered as an error, as
// Chrome answers a method it does not know. A tab asked for is opened in a window of its own behind the others, and one
// asked to be brought forward is answered as done (BEHIND, FRONT).
/// How a tab is opened: in a window of its own, behind the person's (measured on a Mac, Edge 156, 2026-10-29: a tab
/// opened so leaves the app in front where it is, and is drawn; a tab behind another in its window is not, and a tab
/// brought forward or opened in front makes the browser the front app). Headless, it has no window to show anyway.
export const BEHIND = { newWindow: true, background: true } as const;

/// Methods on the browser's own target, and what of them is the agent's: `target` names a target of its own in
/// params.targetId, `context` puts the chat's context as params.browserContextId (or one the agent made), `answer` is
/// answered here, `pass` goes as it is.
const BROWSER_METHODS: Record<string, "target" | "context" | "pass" | "answer" | "own"> = {
  "Browser.getVersion": "pass",
  "Browser.getWindowForTarget": "target",
  "Browser.getWindowBounds": "pass",
  "Browser.setWindowBounds": "pass",
  "Browser.setDownloadBehavior": "context",
  "Browser.grantPermissions": "context",
  "Browser.resetPermissions": "context",
  "Browser.setPermission": "context",
  "Schema.getDomains": "pass",
  "Storage.getCookies": "context",
  "Storage.setCookies": "context",
  "Storage.clearCookies": "context",
  "Target.setDiscoverTargets": "pass",
  "Target.setAutoAttach": "pass",
  "Target.setRemoteLocations": "pass",
  "Target.getTargets": "pass",
  "Target.getTargetInfo": "target",
  "Target.attachToTarget": "target",
  "Target.detachFromTarget": "own",
  "Target.closeTarget": "target",
  "Target.activateTarget": "answer",
  "Target.exposeDevToolsProtocol": "target",
  "Target.autoAttachRelated": "target",
  "Target.sendMessageToTarget": "own",
  "Target.createTarget": "context",
  "Target.createBrowserContext": "pass",
  "Target.disposeBrowserContext": "context",
  "Target.getBrowserContexts": "answer",
};

/// Target sessions' methods answered here: they would bring the browser in front.
const FRONT = new Set(["Page.bringToFront"]);
/// A context's cookies: gated as on the browser's target wherever they are asked (they name a context).
const COOKIES = new Set(["Storage.getCookies", "Storage.setCookies", "Storage.clearCookies"]);

/// The browser's news of targets the gate reads (with a target's info, or its id).
const NEWS = new Set(["Target.targetCreated", "Target.targetInfoChanged", "Target.targetDestroyed", "Target.targetCrashed", "Target.attachedToTarget", "Target.detachedFromTarget", "Target.receivedMessageFromTarget"]);

/// Ids of what the gate itself asks of Chrome (letting go of a target): far from any a client counts to.
const OWN_IDS = 2_000_000_000;

export type GateParts = {
  /// The chat's context.
  context: string;
  /// The context of a target, as the station knows it (tabs.ts), when it does.
  contextOf(targetId: string): string | undefined;
  /// A tab the agent asked for, opened (its id).
  opened?(targetId: string): void;
};

/// What to do with a message: send these to Chrome, these back to the agent.
export type Passed = { up: string[]; down: string[] };

const error = (id: unknown, sessionId: unknown, message: string) =>
  JSON.stringify({ id, ...(typeof sessionId === "string" ? { sessionId } : {}), error: { code: -32601, message } });

export class Gate {
  readonly #p: GateParts;
  /// Contexts the agent made itself (Target.createBrowserContext): its own too.
  readonly #contexts = new Set<string>();
  /// Targets known to be the agent's (made by it, or told of in its contexts), and those known not to be.
  readonly #mine = new Set<string>();
  /// Target sessions of the agent's own targets, on this connection.
  readonly #sessions = new Set<string>();
  /// Target sessions Chrome attached on its own to targets not the agent's: let go of, and nothing of them passed.
  readonly #foreign = new Set<string>();
  /// The agent's requests whose answers are looked at, by their id: what to do with each.
  readonly #asked = new Map<string, (m: any) => string | null>();
  /// What the gate itself asked of Chrome and is not answered yet, by id: its answers are its own.
  readonly #own = new Set<number>();
  #ownId = OWN_IDS;

  constructor(p: GateParts) {
    this.#p = p;
  }

  /// Whether `ctx` is the agent's.
  #ours(ctx: unknown): boolean {
    return ctx === this.#p.context || (typeof ctx === "string" && this.#contexts.has(ctx));
  }

  /// Whether target `id` is the agent's (what its info says of its context, else what is known of it).
  #target(id: unknown, info?: { browserContextId?: string }): boolean {
    if (typeof id !== "string") return false;
    if (this.#mine.has(id)) return true;
    const ctx = info?.browserContextId ?? this.#p.contextOf(id);
    if (!this.#ours(ctx)) return false;
    this.#mine.add(id);
    return true;
  }

  /// A message from the agent.
  fromClient(text: string): Passed {
    let m: any;
    try {
      m = JSON.parse(text);
    } catch {
      return { up: [], down: [] };
    }
    if (m === null || typeof m !== "object" || typeof m.method !== "string") return { up: [], down: [error(m?.id, m?.sessionId, "a message is {id, method, params}")] };
    const params = m.params !== null && typeof m.params === "object" ? m.params : {};
    if (typeof m.sessionId === "string") {
      if (!this.#sessions.has(m.sessionId)) return { up: [], down: [error(m.id, m.sessionId, "No such session of this chat's.")] };
      if (FRONT.has(m.method)) return { up: [], down: [JSON.stringify({ id: m.id, sessionId: m.sessionId, result: {} })] };
      // What reaches past the page (other targets, the browser, the cookies of a context) is gated as on the browser's
      // own target; a page's own auto-attach to its frames and workers goes as it is (what it attaches is told, and
      // gated, as Target.attachedToTarget).
      if (m.method === "Target.setAutoAttach" || m.method === "Target.autoAttachRelated") return { up: [text], down: [] };
      if (m.method.startsWith("Target.") || m.method.startsWith("Browser.") || COOKIES.has(m.method)) return this.#browser(m, params, m.sessionId);
      return { up: [text], down: [] };
    }
    return this.#browser(m, params, undefined);
  }

  #browser(m: any, params: any, sessionId: string | undefined): Passed {
    const how = BROWSER_METHODS[m.method];
    const no = (why: string) => ({ up: [], down: [error(m.id, sessionId, why)] });
    if (how === undefined) return no(`${m.method} is not for one chat's browser.`);
    const key = `${sessionId ?? ""}\0${m.id}`;
    switch (how) {
      case "answer":
        if (m.method === "Target.getBrowserContexts") {
          // The chat's context is the agent's default one; those it made, its others.
          return { up: [], down: [JSON.stringify({ id: m.id, ...(sessionId ? { sessionId } : {}), result: { browserContextIds: [...this.#contexts], defaultBrowserContextId: this.#p.context } })] };
        }
        return { up: [], down: [JSON.stringify({ id: m.id, ...(sessionId ? { sessionId } : {}), result: {} })] };
      case "target":
        // Without one, the browser's own target (Target.getTargetInfo): nothing of a chat's.
        if (params.targetId === undefined && m.method !== "Target.attachToTarget" && m.method !== "Target.closeTarget") return { up: [JSON.stringify(m)], down: [] };
        if (!this.#target(params.targetId)) return no("No such target of this chat's.");
        if (m.method === "Target.attachToTarget") this.#asked.set(key, (a) => (typeof a.result?.sessionId === "string" && this.#sessions.add(a.result.sessionId), null));
        return { up: [JSON.stringify(m)], down: [] };
      case "own":
        if (typeof params.sessionId !== "string" || !this.#sessions.has(params.sessionId)) return no("No such session of this chat's.");
        return { up: [JSON.stringify(m)], down: [] };
      case "context": {
        const given = params.browserContextId;
        if (given !== undefined && !this.#ours(given)) return no("No such browser context of this chat's.");
        if (m.method === "Target.disposeBrowserContext") {
          if (given === undefined || given === this.#p.context) return no("This chat's own context is not disposed of from here.");
          this.#contexts.delete(given);
          return { up: [JSON.stringify(m)], down: [] };
        }
        const out = { ...m, params: { ...params, browserContextId: given ?? this.#p.context, ...(m.method === "Target.createTarget" ? BEHIND : {}) } };
        if (m.method === "Target.createTarget") {
          this.#asked.set(key, (a) => {
            const id = a.result?.targetId;
            if (typeof id === "string") {
              this.#mine.add(id);
              this.#p.opened?.(id);
            }
            return null;
          });
        }
        return { up: [JSON.stringify(out)], down: [] };
      }
      case "pass":
        if (m.method === "Target.createBrowserContext") this.#asked.set(key, (a) => (typeof a.result?.browserContextId === "string" && this.#contexts.add(a.result.browserContextId), null));
        if (m.method === "Target.getTargets") {
          this.#asked.set(key, (a) => {
            if (!Array.isArray(a.result?.targetInfos)) return null;
            return JSON.stringify({ ...a, result: { ...a.result, targetInfos: a.result.targetInfos.filter((t: any) => this.#target(t?.targetId, t)) } });
          });
        }
        return { up: [JSON.stringify(m)], down: [] };
    }
  }

  /// Whether a message from Chrome is one the gate reads: the browser's news of targets, or an answer it looks at.
  /// Others pass unread (a page's screenshot is large: it is never parsed).
  wants(text: string): boolean {
    if (text.length > 1 << 20) return false;
    if (text.startsWith('{"method":"Target.')) return true;
    if (this.#asked.size === 0 && this.#foreign.size === 0 && this.#own.size === 0) return false;
    return text.startsWith('{"id":');
  }

  /// A message from Chrome the gate reads (`wants`).
  fromChrome(text: string): Passed {
    let m: any;
    try {
      m = JSON.parse(text);
    } catch {
      return { up: [], down: [text] };
    }
    if (typeof m?.id === "number" && this.#own.delete(m.id)) return { up: [], down: [] };
    if (m?.id !== undefined) {
      const key = `${typeof m.sessionId === "string" ? m.sessionId : ""}\0${m.id}`;
      const look = this.#asked.get(key);
      if (look === undefined) return typeof m.sessionId === "string" && this.#foreign.has(m.sessionId) ? { up: [], down: [] } : { up: [], down: [text] };
      this.#asked.delete(key);
      return { up: [], down: [look(m) ?? text] };
    }
    if (typeof m?.sessionId === "string" && this.#foreign.has(m.sessionId)) return { up: [], down: [] };
    if (!NEWS.has(m?.method)) return { up: [], down: [text] };
    const p = m.params ?? {};
    switch (m.method) {
      case "Target.attachedToTarget": {
        if (this.#target(p.targetInfo?.targetId, p.targetInfo)) {
          if (typeof p.sessionId === "string") this.#sessions.add(p.sessionId);
          return { up: [], down: [text] };
        }
        // Not the agent's: let go of at once (which lets it run on, if it waited for its debuggers), and never told.
        if (typeof p.sessionId === "string") this.#foreign.add(p.sessionId);
        const detach = { id: this.#ownId++, method: "Target.detachFromTarget", params: { sessionId: p.sessionId }, ...(typeof m.sessionId === "string" ? { sessionId: m.sessionId } : {}) };
        this.#own.add(detach.id);
        return { up: [JSON.stringify(detach)], down: [] };
      }
      case "Target.detachedFromTarget":
      case "Target.receivedMessageFromTarget":
        if (typeof p.sessionId === "string" && this.#foreign.has(p.sessionId)) {
          if (m.method === "Target.detachedFromTarget") this.#foreign.delete(p.sessionId);
          return { up: [], down: [] };
        }
        if (m.method === "Target.detachedFromTarget" && typeof p.sessionId === "string") this.#sessions.delete(p.sessionId);
        return { up: [], down: [text] };
      case "Target.targetDestroyed":
      case "Target.targetCrashed":
        if (!this.#mine.has(p.targetId)) return { up: [], down: [] };
        if (m.method === "Target.targetDestroyed") this.#mine.delete(p.targetId);
        return { up: [], down: [text] };
      default:
        return this.#target(p.targetInfo?.targetId, p.targetInfo) ? { up: [], down: [text] } : { up: [], down: [] };
    }
  }
}
