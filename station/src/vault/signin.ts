// Signing in to a site from a card (docs/vault.md 登录态, "Signing in from a card"; chat EMBER/1793439516.811000,
// 2026-11-01: 「agent 那边只剩一个动作」). An agent that needs a site signed in to in its chat's browser asks once
// (`sign_in {site, reason}`): a sign-in the vault keeps for the site is asked for as any secret is (secret_use, mode
// browser); none, a card asks the person it works for to sign in. On the card their app asks their own password manager
// (1Password, the system's autofill) for the site's login, and what it gives comes here (`fill`): the station types it
// into the tab's sign-in form step by step (signin-form.ts: an account, a password, a one-time code) and sends each. A
// step only a person can take (a captcha, a page that took none of it) gives them the tab's screen from the same card;
// one asking a code it was not given asks it on the card. The page left its sign-in, the agent is told and looks; signed
// in, it says so (`done`), and the sign-in is kept in the person's vault if they chose so on the card, with no card of
// its own (the app that signed in approves it in place). What the app gave is held in memory only, for the sign-in, and
// never logged; the asks are kept in the station's database (`signin_asks`), never a password.
import type { DatabaseSync } from "node:sqlite";
import { UNDECIDED, threadAddress } from "../agents/instructions.ts";
import { log } from "../ops/log.ts";
import { CARD_OCCUPIED, cardPlace } from "../sessions/card-place.ts";
import { STILLFAIL_SURFACE, type SessionThread } from "../store/store.ts";
import type { Driven, FormAsks, FormField, FormValues } from "../browser/signin-form.ts";
import type { Request } from "./crypto.ts";

const SCHEMA = `CREATE TABLE IF NOT EXISTS signin_asks (
  id TEXT PRIMARY KEY,
  session TEXT NOT NULL,
  owner TEXT NOT NULL,
  status TEXT NOT NULL,
  body TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS signin_asks_by_session ON signin_asks (session, status);`;

/// Where an ask is: waiting for the person (`pending`), being filled (`filling`), waiting for a code (`code`), given to
/// the person on its screen (`person`), the page past its sign-in for the agent to look at (`left`), signed in
/// (`done`), refused (`denied`), or let go (`expired`: a day undecided; `ended`: its chat archived).
export type Status = "pending" | "filling" | "code" | "person" | "left" | "done" | "denied" | "expired" | "ended";
const OPEN: Status[] = ["pending", "filling", "code", "person", "left"];

export type SignInAsk = {
  id: string; session: string; chat: string; owner: string; site: string; tab: string; reason: string; at: number; status: Status;
  /// Given to the person: why (signin-form.ts Driven's, or `agent`: the agent said what is left, `said`).
  why?: string; said?: string;
  /// Whether the person chose to keep it in their vault; the request that keeps it, once asked.
  keep?: boolean; save?: string; kept?: Request["status"];
  thread?: number; cardTs?: string;
};

/// What an undecided ask lasts, and what the app's login is held for after its last use.
const PENDING_SECS = 86400;
const HELD_MS = 15 * 60_000;

export type SignInDeps = {
  db: DatabaseSync;
  hub: {
    store: {
      getSession(key: string): { archivedAt?: number | null } | null;
      starter(session: string): string | null;
      latestThread(session: string): SessionThread | null;
      sessionThreads(session: string): SessionThread[];
      pendingCard(thread: number): [{ ts: string }, unknown] | null;
      insertMessage(m: Record<string, unknown>): readonly unknown[];
      withdrawCard(agent: string, thread: number, ts: string): boolean;
      restateCard(agent: string, thread: number, ts: string, card: (was: any) => any): boolean;
      subscribe(f: (c: { type: string; key?: string }) => void): void;
    };
    chat(connect: string): { post(where: { channel: string; threadTs: string }, text: string, files: never[]): Promise<string> };
    shared(thread: number, n: number, session: string, text: string): void;
    notify(session: string, text: string): void;
  };
  /// The chat's browser: its tabs, a tab's sign-in form.
  browser: {
    tabs(session: string): { id: string; url: string }[];
    look(session: string, tab: string): Promise<FormAsks>;
    drive(session: string, tab: string, site: string, values: FormValues, used: Set<FormField>): Promise<Driven>;
  };
  /// The vault (secrets.ts): a sign-in it keeps for a site this session may ask for, asked for; one held already; a
  /// sign-in kept from the chat's browser with no card of its own (its request told to `made`).
  vault: {
    listed(session: string, site: string): string | null;
    held(session: string, site: string): string | null;
    use(session: string, item: string, reason: string): Promise<string>;
    keep(session: string, site: string, reason: string, made: (request: string) => void): Promise<string>;
  };
  /// The link that opens a tab's screen in the app, where the station has pages.
  screenLink(tab: string): string | null;
  /// The workspace a session's chat is in.
  workspace(session: string): string | null;
  now(): number;
  /// `f` once, `ms` from now (the machine's time); the returned function calls it off.
  after(ms: number, f: () => void): () => void;
  id?(): string;
};

export class Refused extends Error {}

/// What an ask's app gave and what of it was typed; let go HELD_MS after its last use (`drop`).
type Held = { values: FormValues; used: Set<FormField>; drop: () => void };

/// A site as asked: its host, lower case, no scheme, path, port or `www.`.
export function siteOf(given: string): string {
  let s = given.trim().toLowerCase();
  s = s.replace(/^[a-z][a-z0-9+.-]*:\/\//, "").replace(/[/?#].*$/, "").replace(/:\d+$/, "").replace(/\.$/, "");
  return s.replace(/^www\./, "");
}

const onSite = (host: string, site: string): boolean => host === site || host.endsWith(`.${site}`);
const hostOf = (url: string): string => {
  try {
    return new URL(url).hostname.toLowerCase();
  } catch {
    return "";
  }
};

export class SignIns {
  readonly #d: SignInDeps;
  /// What each ask's app gave (by ask), and what of it was typed: in memory only, until done or HELD_MS unused.
  readonly #held = new Map<string, Held>();

  constructor(d: SignInDeps) {
    this.#d = d;
    d.db.exec(SCHEMA);
    d.hub.store.subscribe((c) => {
      if ((c.type === "sessionRemoved" || c.type === "session") && typeof c.key === "string") {
        const row = d.hub.store.getSession(c.key);
        if (row === null || row.archivedAt != null) for (const a of this.#bySession(c.key)) if (OPEN.includes(a.status)) this.#end(a, "ended");
      }
    });
  }

  #secs(): number {
    return Math.floor(this.#d.now() / 1000);
  }

  get(id: string): SignInAsk | null {
    const row = this.#d.db.prepare("SELECT body FROM signin_asks WHERE id = ?").get(id) as { body: string } | undefined;
    return row ? JSON.parse(row.body) : null;
  }

  #bySession(session: string): SignInAsk[] {
    return (this.#d.db.prepare("SELECT body FROM signin_asks WHERE session = ? ORDER BY rowid").all(session) as { body: string }[]).map((r) => JSON.parse(r.body));
  }

  #save(a: SignInAsk) {
    this.#d.db
      .prepare("INSERT INTO signin_asks (id, session, owner, status, body) VALUES (?, ?, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET status = excluded.status, body = excluded.body")
      .run(a.id, a.session, a.owner, a.status, JSON.stringify(a));
  }

  /// The person a session works for: whoever started its chat.
  #starter(session: string): string | null {
    return this.#d.hub.store.starter(session);
  }

  #tell(session: string, text: string) {
    try {
      this.#d.hub.notify(session, text);
    } catch {
      // The session is gone: nobody to tell.
    }
  }

  /// sign_in: the site signed in to in this session's chat's browser. A sign-in granted already, said; one the vault
  /// keeps, asked for (secret_use); none (or `again`: the one kept ran out), a card asks the person to sign in on the
  /// chat's tab on the site (`tab`, else the last one there). `done`: the agent looked and it is signed in; `stuck`: it
  /// is not, and what is left (given to the person on the tab's screen).
  async ask(session: string, a: { site: string; reason?: string; tab?: string; again?: boolean; reask?: boolean; done?: boolean; stuck?: string }): Promise<string> {
    const site = siteOf(a.site);
    if (site === "" || !site.includes(".")) throw new Refused("site is the site's host, e.g. github.com");
    const open = this.#bySession(session).filter((x) => x.site === site && OPEN.includes(x.status)).at(-1);
    if (open?.status === "pending" && open.at + PENDING_SECS < this.#secs()) {
      this.#end(open, "expired");
      throw new Refused(`The sign-in to ${site} expired. Ask for a new sign-in if it is still needed.`);
    }
    if (a.done || a.stuck !== undefined) {
      if (open === undefined) throw new Refused(`No sign-in to ${site} is under way in this chat: sign_in {site, reason} asks for one.`);
      return a.done ? this.#done(open) : this.#stuck(open, a.stuck ?? "");
    }
    // Asked again once it left its sign-in, the site asking for the password again (to add a passkey, a setting's
    // confirmation): typed in again from what the app gave, while it is held.
    const held = open === undefined ? undefined : this.#held.get(open.id);
    if (open?.status === "left" && held !== undefined) {
      held.used.clear();
      this.#set(open, "filling");
      void this.#drive(open, held).catch((e) => {
        log.warn("signin", "a sign-in could not be filled again", { id: open.id, site: open.site, error: (e as Error).message });
        if (this.get(open.id)?.status === "filling") this.#toPerson(this.get(open.id)!, "stuck");
      });
      return `Filling ${site}'s sign-in form on tab ${open.tab} again with what ${open.owner}'s password manager gave; you are told here when the page has left it.`;
    }
    if (open !== undefined) {
      const place = cardPlace(this.#d.hub.store, session, open.thread, open.cardTs);
      if (a.reask && open.status !== "left") {
        if (place?.state === "other") throw new Refused(CARD_OCCUPIED);
        if (place?.state === "none") {
          const posted = await this.#post(session, place.thread, open, true);
          const current = this.get(open.id);
          if (current === null || !OPEN.includes(current.status) || current.status === "left") {
            if (posted !== null) this.#d.hub.store.withdrawCard(session, place.thread.thread.id, posted);
            return current === null ? `The sign-in to ${site} is no longer pending.` : this.#waiting(current);
          }
          if (posted !== null) {
            current.thread = place.thread.thread.id;
            current.cardTs = posted;
            this.#save(current);
            this.#restate(current);
          }
          return this.#waiting(current);
        }
      }
      if (place !== null && place.state !== "same" && open.status !== "left") {
        return `The sign-in to ${site} (${open.id}) is ${open.status}, but its card is no longer pending. If it is still needed, call sign_in with site and reask: true.`;
      }
      return this.#waiting(open);
    }
    const reason = (a.reason ?? "").trim();
    if (reason === "") throw new Refused("reason is required: why you need to be signed in, for the person, in the language they use");
    if (!a.again) {
      const held = this.#d.vault.held(session, site);
      if (held !== null) return `${held} If the site still asks you to sign in there, its sign-in ran out: sign in with its passkey if it offers one (this chat's browser signs it itself), else call sign_in again with again: true.`;
      const item = this.#d.vault.listed(session, site);
      if (item !== null) return `${await this.#d.vault.use(session, item, reason)} Granted, the sign-in is put into this chat's browser; if the site still asks you to sign in then, call sign_in again with again: true.`;
    }
    const owner = this.#starter(session);
    if (owner === null) throw new Refused("No one started this chat: there is nobody to sign in.");
    const thread = this.#d.hub.store.latestThread(session);
    if (thread === null) throw new Refused("This session has no chat to ask in.");
    const tabs = this.#d.browser.tabs(session);
    const tab = a.tab !== undefined ? tabs.find((t) => t.id === a.tab) : tabs.filter((t) => onSite(hostOf(t.url), site)).at(-1);
    if (tab === undefined) throw new Refused(a.tab !== undefined ? `This chat's browser has no tab ${a.tab}.` : `This chat's browser has no tab on ${site}: open its sign-in page there first (the \`browser\` tool), then call sign_in.`);
    if (!onSite(hostOf(tab.url), site)) throw new Refused(`Tab ${tab.id} is on ${hostOf(tab.url) || tab.url}, not ${site}.`);
    const form = await this.#d.browser.look(session, tab.id);
    if (!form.username && !form.password && !form.code) throw new Refused(`Tab ${tab.id} (${tab.url}) shows no sign-in form: go to ${site}'s sign-in page there (its "Sign in" link), then call sign_in.`);
    const x: SignInAsk = {
      id: this.#d.id?.() ?? `g_${this.#d.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`,
      session, chat: threadAddress(thread.thread.channel, thread.thread.threadTs), owner, site, tab: tab.id, reason, at: this.#secs(), status: "pending",
    };
    this.#save(x);
    const posted = await this.#post(session, thread, x);
    if (posted !== null) {
      x.thread = thread.thread.id;
      x.cardTs = posted;
      this.#save(x);
    }
    return `Asked ${owner} to sign in to ${site} (sign-in ${x.id}): the card in your chat signs in on tab ${tab.id} from their own password manager, the station typing it in; you never see it. ${UNDECIDED} You are told here when the page has left its sign-in: then look, and say so with sign_in {site: "${site}", done: true} (or stuck: "what is left").`;
  }

  /// What the agent is told of an ask still under way.
  #waiting(x: SignInAsk): string {
    switch (x.status) {
      case "left":
        return `The sign-in to ${x.site} (${x.id}) left its sign-in page on tab ${x.tab}: look whether it is signed in, then sign_in {site: "${x.site}", done: true}, or stuck: "what is left".`;
      case "person":
        return `The sign-in to ${x.site} (${x.id}) is with ${x.owner}, on tab ${x.tab}'s screen. ${UNDECIDED} You are told when they are done.`;
      default:
        return `The sign-in to ${x.site} (${x.id}) waits for ${x.owner} on its card. ${UNDECIDED}`;
    }
  }

  async #post(session: string, thread: SessionThread, x: SignInAsk, requireEmpty = false): Promise<string | null> {
    const stillfail = thread.thread.surface === STILLFAIL_SURFACE;
    const link = this.#d.screenLink(x.tab);
    const text = [`要登录 ${x.site}：${x.reason}`, ...(stillfail ? [] : [link !== null ? `请在 still.fail 中打开此画面登录，登录后在此回复：\n${link}` : "请在 still.fail 客户端里登录。"])].join("\n\n");
    const card = stillfail
      ? {
          type: "options",
          options: [{ label: "在画面中登录", detail: "打开此网页，自行输入" }, { label: "用密码管理器登录", detail: "由 station 填入并提交", recommended: true }],
          assignee: x.owner,
          // The ask as the app draws it (its screen: the tab's), its state added as it goes (#restate).
          signin: { id: x.id, site: x.site, reason: x.reason, screen: `browser:${x.tab}` },
        }
      : null;
    const here = { channel: thread.thread.channel, threadTs: thread.thread.threadTs };
    const posted = await this.#d.hub.chat(thread.connect).post(here, text, []);
    if (requireEmpty && this.#d.hub.store.pendingCard(thread.thread.id) !== null) throw new Refused(CARD_OCCUPIED);
    const [n] = this.#d.hub.store.insertMessage({ thread: thread.thread.id, ts: posted, authorKind: "agent", author: session, text, attachments: [], declared: null, card });
    this.#d.hub.shared(thread.thread.id, n as number, session, text);
    return card !== null ? posted : null;
  }

  /// The ask's card as it stands now (`signin.outcome`): where it is, why a person is needed, whether it is kept.
  #restate(x: SignInAsk) {
    if (x.thread === undefined || x.cardTs === undefined) return;
    const outcome = {
      status: x.status, ...(x.why ? { why: x.why } : {}), ...(x.said ? { said: x.said } : {}), ...(x.keep !== undefined ? { keep: x.keep } : {}),
      ...(x.save ? { save: x.save } : {}), ...(x.kept ? { kept: x.kept } : {}),
    };
    this.#d.hub.store.restateCard(x.session, x.thread, x.cardTs, (card) => ({ ...card, signin: { ...card?.signin, outcome } }));
  }

  #set(x: SignInAsk, status: Status, why?: string) {
    x.status = status;
    if (why === undefined) delete x.why;
    else x.why = why;
    this.#save(x);
    this.#restate(x);
  }

  /// Its card no longer waits on anyone: withdrawn, but while its sign-in's keeping waits for the app to approve it.
  #end(x: SignInAsk, status: "done" | "denied" | "expired" | "ended") {
    this.#forget(x.id);
    this.#set(x, status);
    if (status === "done" && x.save !== undefined && (x.kept ?? "pending") === "pending") return;
    if (x.thread !== undefined && x.cardTs !== undefined) this.#d.hub.store.withdrawCard(x.session, x.thread, x.cardTs);
  }

  /// The ask `id` as its person may answer it (in their workspace's station), or why not.
  #theirs(email: string, ws: string, id: string): SignInAsk | string {
    const x = this.get(id);
    if (x === null || this.#d.workspace(x.session) !== ws) return "no such sign-in";
    if (x.owner !== email.toLowerCase()) return "only the person the chat's agent works for signs it in";
    if (!OPEN.includes(x.status)) return `the sign-in is ${x.status} already`;
    if (x.status === "pending" && x.at + PENDING_SECS < this.#secs()) {
      this.#end(x, "expired");
      return "the sign-in was let go (a day undecided)";
    }
    return x;
  }

  /// From the person's app (`email`): the login their password manager gave (`values`), typed into the tab's form; or,
  /// with a code alone, the one the page asks. `keep`: kept in their vault once signed in. Why not, or null; how it goes
  /// is said on the card.
  fill(email: string, ws: string, id: string, values: FormValues & { keep?: boolean }): string | null {
    const x = this.#theirs(email, ws, id);
    if (typeof x === "string") return x;
    if (x.status === "filling") return "the sign-in is being filled";
    const given: FormValues = {};
    for (const k of ["username", "password", "code"] as const) {
      const v = values[k];
      if (typeof v === "string" && v !== "" && v.length <= 4096) given[k] = v;
    }
    if (Object.keys(given).length === 0) return "nothing to fill: give username, password or code";
    const held: Held = this.#held.get(id) ?? { values: {}, used: new Set<FormField>(), drop: () => {} };
    // (a code is typed once; a new one may be asked again)
    if (given.code !== undefined) held.used.delete("code");
    held.values = { ...held.values, ...given };
    this.#hold(id, held);
    if (typeof values.keep === "boolean") x.keep = values.keep;
    this.#set(x, "filling");
    void this.#drive(x, held).catch((e) => {
      log.warn("signin", "a sign-in could not be filled", { id: x.id, site: x.site, error: (e as Error).message });
      const now = this.get(x.id);
      if (now?.status === "filling") this.#toPerson(now, "stuck");
    });
    return null;
  }

  /// `held` kept for ask `id`, let go HELD_MS from now.
  #hold(id: string, held: Held) {
    held.drop();
    held.drop = this.#d.after(HELD_MS, () => {
      if (this.#held.get(id) === held) this.#held.delete(id);
    });
    this.#held.set(id, held);
  }

  #forget(id: string) {
    this.#held.get(id)?.drop();
    this.#held.delete(id);
  }

  async #drive(x: SignInAsk, held: Held) {
    const driven = await this.#d.browser.drive(x.session, x.tab, x.site, held.values, held.used);
    const now = this.get(x.id);
    if (now === null || now.status !== "filling") return;
    this.#hold(x.id, held);
    log.info("signin", "a sign-in filled", { id: x.id, site: x.site, state: driven.state, ...(driven.why ? { why: driven.why } : {}) });
    if (driven.state === "code") return this.#set(now, "code");
    if (driven.state === "person") return this.#toPerson(now, driven.why ?? "stuck");
    this.#left(now, `The sign-in form of ${now.site} on tab ${now.tab} was filled from ${now.owner}'s password manager and sent, and the page has left its sign-in.`);
  }

  #toPerson(x: SignInAsk, why: string) {
    this.#set(x, "person", why);
  }

  #left(x: SignInAsk, said: string) {
    this.#set(x, "left");
    this.#tell(x.session, `${said} Look whether ${x.site} is signed in now (tab ${x.tab}): then call sign_in {site: "${x.site}", done: true}${x.keep !== false ? ", which keeps the sign-in in their vault as they chose on the card" : ""}; if a step is left that only they can take (a confirmation by mail, a new device's check), sign_in {site: "${x.site}", stuck: "what is left"}, in their language.`);
  }

  /// From the person's app: they sign in themselves on the tab's screen (`screen`), or say they did (`done`).
  self(email: string, ws: string, id: string, done: boolean): string | null {
    const x = this.#theirs(email, ws, id);
    if (typeof x === "string") return x;
    if (!done) {
      this.#set(x, "person", "self");
      return null;
    }
    this.#left(x, `${x.owner} says they signed in to ${x.site} themselves on tab ${x.tab}.`);
    return null;
  }

  /// From the person's app: they will not sign in.
  deny(email: string, ws: string, id: string): string | null {
    const x = this.#theirs(email, ws, id);
    if (typeof x === "string") return x;
    this.#end(x, "denied");
    this.#tell(x.session, `${x.owner} chose not to sign in to ${x.site} (${x.id}).`);
    return null;
  }

  /// The agent looked: signed in. Kept in the vault where the person chose so (the request told on the card, for their
  /// app to approve in place).
  async #done(x: SignInAsk): Promise<string> {
    this.#forget(x.id);
    if (x.keep === false) {
      this.#end(x, "done");
      return `Signed in to ${x.site}. ${x.owner} chose not to keep it in their vault: it lasts as long as this chat's browser does.`;
    }
    let made: string | null = null;
    let said: string;
    try {
      said = await this.#d.vault.keep(x.session, x.site, `登录 ${x.site} 后保存，下次 agent 申请使用就不用再登录`, (r) => (made = r));
    } catch (e) {
      this.#end(x, "done");
      return `Signed in to ${x.site}, but it could not be kept in the vault: ${(e as Error).message}`;
    }
    if (made !== null) x.save = made;
    this.#end(x, "done");
    return `Signed in to ${x.site}. ${said}`;
  }

  #stuck(x: SignInAsk, what: string): string {
    x.said = what.trim().slice(0, 500);
    this.#toPerson(x, "agent");
    return `The card now gives ${x.owner} tab ${x.tab}'s screen, saying what is left. ${UNDECIDED} You are told when they are done.`;
  }

  /// A request of the vault's decided (secrets.ts listen): a sign-in's keeping said on its card.
  heard(r: Request) {
    if (!r.save || r.status === "pending") return;
    const row = this.#d.db.prepare("SELECT body FROM signin_asks WHERE session = ? AND json_extract(body, '$.save') = ?").get(r.session, r.id) as { body: string } | undefined;
    if (row === undefined) return;
    const x = JSON.parse(row.body) as SignInAsk;
    if (x.kept === r.status) return;
    x.kept = r.status;
    this.#save(x);
    this.#restate(x);
    if (x.thread !== undefined && x.cardTs !== undefined) this.#d.hub.store.withdrawCard(x.session, x.thread, x.cardTs);
  }
}
