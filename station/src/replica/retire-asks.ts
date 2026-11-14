// station_retire on this station (tools/retire.ts): an agent of any chat of the workspace assists a station's
// retirement (retire.ts), this one's or another's of the workspace (asked over the mesh, `retire.ask`), and a person
// confirms it at its two moments, each with a card in the agent's chat (the user, 2026-11-14: 「迁移最好能 agent 辅助，
// 因为中途可能出问题，然后人应该只需要在关键节点点卡片来确认就行」): 开始迁移 (the retirement begins, its files sent while
// the chats work) and 暂停聊天并交接 (from `sent`, the chats stop and are handed over).
//
// A card is the generic options card, both its options closing it, with a `retire` field naming the ask it confirms;
// the station reads its outcome itself, never the agent: a choice counts only on the very entry the station posted for
// that ask (its thread and ts, kept in the ask: another card naming the same ask, whatever it says, counts for nothing),
// only as made in the still.fail app by a member who manages the station (an owner or admin of the workspace: `may`,
// asked by the route that closes a card before it closes it, admin.ts's `cardChoice`), never a message that says yes nor
// a reply on Slack or Feishu (which close no card), and only once (`chosen`). Which option confirms is the label the
// card was posted with (`confirm`), the station's words in its language (station.json's `station.retire.card.*`). A later message in the chat ends the card as any other, deciding nothing: the agent
// asks again (`start` or `hand_over` again posts it anew for the same ask; a confirmed one is not started twice). The
// one who confirmed is who the retirement is by. The choice is told the agent with what it is next handed (store.ts
// card_choices), and what came of it at once (`notify`, which wakes it); the agent that asked is the retirement's
// driver, told of each step after (retire.ts `#toDriver`).
import { readFileSync } from "node:fs";
import { mkdir, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { randomBytes } from "node:crypto";
import { Refused } from "../mesh/bus.ts";
import { managesStation } from "../mesh/credential.ts";
import { log } from "../ops/log.ts";
import { stationLang, tr } from "../ops/i18n.ts";
import type { CardAt } from "../parts.ts";
import { CARD_OCCUPIED, type CardHub, cardPlace, postCard } from "../sessions/card-place.ts";
import { STILLFAIL_SURFACE, type SessionThread } from "../store/rows.ts";
import type { Ask } from "./peers.ts";
import type { Retire } from "./retire.ts";
import { STATION } from "./format.ts";

type Json = any;

export type AskKind = "start" | "hand_over";
/// An ask a card confirms: whose (the session that asked, its workspace), of which station's retirement (`station`) and,
/// to start one, to which (`to`); where its card is (`thread`, `ts`; posted anew where a message ended it); how it went.
export type RetireAsk = {
  id: string; kind: AskKind; session: string; ws: string; station: string; stationName: string; to: string | null; toName: string;
  state: "asked" | "confirmed" | "declined" | "done" | "failed" | "dropped"; thread: number | null; ts: string | null; at: number; by: string | null; error: string | null;
  /// The label of the option that confirms it, as its card was last posted (in the station's language then).
  confirm?: string;
};

/// The station's words of each card's options: the one that confirms, then the one that does not.
const OPTION_KEYS: Record<AskKind, string> = { start: "station.retire.card.start", hand_over: "station.retire.card.handOver" };
export const confirmLabel = (kind: AskKind) => tr(stationLang(), `${OPTION_KEYS[kind]}.confirm`);
export const declineLabel = (kind: AskKind) => tr(stationLang(), `${OPTION_KEYS[kind]}.decline`);
/// The asks kept (the latest): what a card names, and which sessions drive a retirement.
const KEPT = 20;

export type AsksDeps = {
  data: string;
  here: () => string | null;
  /// The stations of `ws` with their names (null while not current).
  roster: (ws: string) => { id: string; name: string }[] | null;
  /// The workspace a session's chat is of (its own, else the home one's).
  wsOf: (session: string) => string | null;
  /// This station's own retirement.
  retire: Retire;
  ask: Ask;
  /// A card posted in the session's chat, as its agent (sessions/card-place.ts `postCard`; refused where the chat is
  /// not a still.fail one: a card there is not confirmed in the app), and whether that card still waits there
  /// (`same`), another does (`other`), or none (`none`).
  cards: {
    post(session: string, text: string, card: Json): Promise<{ thread: number; ts: string } | null>;
    state(session: string, thread: number, ts: string): "same" | "other" | "none" | null;
  };
  /// The session's agent told something by the station (hub.notify: it wakes it).
  notify: (session: string, text: string) => void;
  now: () => number;
  id?: () => string;
  /// Whether a retirement may be started (`start`) or handed over (`hand_over`) here at all (module.ts
  /// `RETIRE_STARTS`): off, both are refused before any card is posted, and a card from before confirms nothing.
  starts: boolean;
};

/// What an agent is told of `start` and `hand_over` while retiring is switched off (module.ts `RETIRE_STARTS`).
export const RETIRE_OFF = "retiring a station is switched off for now: it is being fixed after its first use lost files; nothing was started";

/// The cards of station_retire in a session's chat, as the station's other cards are posted (sessions/card-place.ts):
/// in its latest thread, as its agent, only a still.fail chat's (the app is where it is confirmed).
export function chatCards(hub: CardHub & {
  store: CardHub["store"] & { latestThreadIfReady(session: string): SessionThread | null | undefined; latestThread(session: string): SessionThread | null };
  prepareLatestThreads?: ((sessions: readonly string[]) => Promise<void>) | null;
}): AsksDeps["cards"] {
  return {
    post: async (session, text, card) => {
      let thread = hub.store.latestThreadIfReady(session);
      if (thread === undefined) {
        await hub.prepareLatestThreads?.([session]);
        thread = hub.store.latestThread(session);
      }
      if (thread === null) throw new Refused("this session has no chat to ask in");
      // (a card in a Slack or Feishu thread is not one the app confirms: as the station's other cards, a still.fail
      // chat's alone)
      if (thread.thread.surface !== STILLFAIL_SURFACE) throw new Refused("the confirmations are cards in the still.fail app, which a Slack or Feishu thread does not show: drive the retirement from a still.fail chat of this workspace (chat_create opens one), or a person retires the station from its page in the app");
      const ts = await postCard(hub, session, thread, text, card, (why) => new Refused(why));
      return ts === null ? null : { thread: thread.thread.id, ts };
    },
    state: (session, thread, ts) => {
      try {
        // (where the thread's cards are not read yet, as one waiting still: never posted twice)
        return cardPlace(hub.store, session, thread, ts)?.state ?? "same";
      } catch {
        return "none";
      }
    },
  };
}

const asksFile = (data: string) => join(data, "replica", "retire-asks.json");

const gbOf = (n: number) => `${(n / 1024 ** 3).toFixed(1)} GB`;

export class RetireAsks {
  readonly #d: AsksDeps;
  #asks: RetireAsk[];
  #writing: Promise<void> = Promise.resolve();
  /// The confirmed steps being taken (`#act`).
  readonly #acting = new Set<Promise<void>>();

  constructor(d: AsksDeps) {
    this.#d = d;
    let kept: RetireAsk[] = [];
    try {
      kept = JSON.parse(readFileSync(asksFile(d.data), "utf8")); // sync: read once, before the station serves
    } catch {}
    this.#asks = Array.isArray(kept) ? kept : [];
  }

  #save(): Promise<void> {
    const text = JSON.stringify(this.#asks.slice(-KEPT));
    this.#writing = this.#writing.then(async () => {
      const path = asksFile(this.#d.data);
      await mkdir(dirname(path), { recursive: true });
      await writeFile(`${path}.tmp`, text);
      await rename(`${path}.tmp`, path);
    }).catch((e) => log.warn("retire", "station_retire's asks not written", { error: (e as Error).message }));
    return this.#writing;
  }

  /// What is being taken and written, done (what a test waits for).
  async settle(): Promise<void> {
    while (this.#acting.size > 0) await Promise.all([...this.#acting]);
    await this.#writing;
  }

  /// Whether `session` here asked for `station`'s retirement and a person confirmed it: what that station tells of it is
  /// told its agent (retire.ts `retire.tell`).
  drives(station: string, session: string): boolean {
    return this.#asks.some((a) => a.station === station && a.session === session && (a.state === "confirmed" || a.state === "done"));
  }

  get(id: string): RetireAsk | null {
    return this.#asks.find((a) => a.id === id) ?? null;
  }

  // ── the tool ──

  /// station_retire: what the agent of `session` asked, answered as data with what it says in words (`say`).
  async tool(session: string, args: Record<string, unknown>): Promise<Json> {
    const action = String(args.action ?? "");
    // (switched off: refused before anything is asked or posted; what is under way is read and called off as before)
    if (!this.#d.starts && (action === "start" || action === "hand_over")) throw new Refused(RETIRE_OFF);
    const ws = this.#d.wsOf(session);
    const here = this.#d.here();
    if (ws === null || here === null) throw new Refused("this chat is of no workspace: no station of it to retire");
    const roster = this.#d.roster(ws) ?? [];
    const named = (v: unknown, what: string): { id: string; name: string } => {
      if (typeof v !== "string" || v.trim() === "") throw new Refused(`${what} is needed: a station of this workspace, by its name or id (station_list)`);
      const want = v.trim();
      const found = roster.filter((r) => r.id === want || r.name.toLowerCase() === want.toLowerCase() || (want.length >= 8 && r.id.startsWith(want)));
      if (found.length === 1) return found[0]!;
      if (found.length > 1) throw new Refused(`${what} ${want} names ${found.length} stations: give its id (station_list)`);
      if (STATION.test(want)) return { id: want, name: "" };
      throw new Refused(`${what} ${want} is no station of this workspace (station_list lists them)`);
    };
    const target = args.station === undefined || args.station === "" ? { id: here, name: roster.find((r) => r.id === here)?.name ?? "" } : named(args.station, "station");
    const ask = (request: { op: string; to?: string; by?: string }): Promise<Json> =>
      target.id === here
        ? this.#d.retire.agentAsk(ws, { ...request, driver: { station: here, session } })
        : this.#d.ask(target.id, { method: "retire.ask", workspace: ws, session, ...request }).catch((e) => {
          if (e instanceof Refused && /no such retire request|unknown/.test(e.message)) throw new Refused(`station ${target.name || target.id.slice(0, 12)} is from before station_retire: update it first, or retire it from the app`);
          throw e;
        });
    switch (action) {
      case "preview": {
        const to = args.to === undefined || args.to === "" ? null : named(args.to, "to");
        const r = await ask({ op: "preview", ...(to === null ? {} : { to: to.id }) });
        return { ...r, say: previewWords(r, to?.name ?? "") };
      }
      case "status": {
        const r = await ask({ op: "status" });
        return { ...r, say: statusWords(r) };
      }
      case "start": {
        const to = named(args.to, "to");
        if (to.id === target.id) throw new Refused("the chats go to another station than the one retired");
        const r = await ask({ op: "preview", to: to.id });
        if (r?.status?.retiring != null) throw new Refused(`station ${target.name || "it"} is being retired already (${r.status.retiring.step}): station_retire status says where it stands`);
        const ready = r?.to;
        if (ready?.reached === false) throw new Refused(`station ${to.name || to.id.slice(0, 12)} is not reached now (${ready.error}): start once it is up`);
        if (ready?.old === true) throw new Refused(`station ${to.name || to.id.slice(0, 12)} is from before stations could be retired: update it first`);
        const text = startCard(target.name, to.name, r);
        return await this.#asked(session, { kind: "start", ws, station: target.id, stationName: target.name, to: to.id, toName: to.name || ready?.name || "" }, text);
      }
      case "hand_over": {
        const r = await ask({ op: "status" });
        const s = r?.status?.retiring;
        if (s == null) throw new Refused(`station ${target.name || "it"} is not being retired: station_retire start first`);
        if (s.step !== "sent") throw new Refused(s.step === "sending" ? "the files are still being sent: you are told once they are all there" : `it is past that: ${s.step}`);
        return await this.#asked(session, { kind: "hand_over", ws, station: target.id, stationName: target.name, to: s.to, toName: s.toName }, handOverCard(target.name, s));
      }
      case "again": {
        const r = await ask({ op: "again" });
        return { ...r, say: "Tried again now: you are told as it goes on." };
      }
      case "cancel": {
        const r = await ask({ op: "cancel" });
        return { ...r, say: "Called off: the chats go on on the station they were on." };
      }
    }
    throw new Refused("action is one of preview, status, start, hand_over, again, cancel");
  }

  /// A card asking a person to confirm `kind`, posted in the session's chat; one already waiting for the same is not
  /// posted twice, one a message ended is posted anew for the same ask.
  async #asked(session: string, want: Omit<RetireAsk, "id" | "state" | "session" | "thread" | "ts" | "at" | "by" | "error">, text: string): Promise<Json> {
    let a = this.#asks.find((x) => x.session === session && x.kind === want.kind && x.station === want.station && x.state === "asked" && (want.kind !== "start" || x.to === want.to));
    if (a !== undefined && a.thread !== null && a.ts !== null) {
      const place = this.#d.cards.state(session, a.thread, a.ts);
      if (place === "same") return { ask: a.id, card: "waiting", say: `The card is in this chat already, waiting for an owner or admin of the workspace to choose ${a.confirm ?? confirmLabel(a.kind)} in the still.fail app. You are told when they do.` };
      if (place === "other") throw new Refused(CARD_OCCUPIED);
    }
    // (another ask of this session's for the same station, of another kind or target, is let go of: one at a time)
    for (const x of this.#asks) if (x !== a && x.session === session && x.station === want.station && x.state === "asked") x.state = "dropped";
    if (a === undefined) {
      a = { ...want, id: this.#d.id?.() ?? `r_${randomBytes(6).toString("hex")}`, session, state: "asked", thread: null, ts: null, at: this.#d.now(), by: null, error: null };
      this.#asks.push(a);
      this.#asks = this.#asks.slice(-KEPT);
    }
    const lang = stationLang();
    const confirm = tr(lang, `${OPTION_KEYS[a.kind]}.confirm`);
    const card = {
      type: "options",
      options: [
        { label: confirm, detail: tr(lang, `${OPTION_KEYS[a.kind]}.confirmDetail`), action: "close", recommended: true },
        { label: tr(lang, `${OPTION_KEYS[a.kind]}.decline`), detail: tr(lang, "station.retire.card.declineDetail"), action: "close" },
      ],
      retire: { ask: a.id, kind: a.kind, station: a.station, name: a.stationName, to: a.to, toName: a.toName },
    };
    // (no card of before counts once another is posted for the same ask: it is where the station posted last)
    a.thread = null;
    a.ts = null;
    const posted = await this.#d.cards.post(session, text, card);
    a.thread = posted?.thread ?? null;
    a.ts = posted?.ts ?? null;
    a.confirm = confirm;
    await this.#save();
    return { ask: a.id, card: "posted", say: `A card is in this chat: an owner or admin of the workspace confirms it (${confirm}) in the still.fail app; nothing happens until then, and a message in the chat ends the card without deciding (ask again then). You are told what they chose.` };
  }

  // ── a card's choice (admin.ts `cardChoice`) ──

  /// The ask whose card is the entry at `at`: the one the station posted for it, never another naming it.
  #askAt(card: Json, at: CardAt): RetireAsk | null {
    const a = this.get(String(card?.retire?.ask ?? ""));
    return a !== null && a.thread === at.thread && a.ts !== null && a.ts === at.ts ? a : null;
  }

  /// Why `viewer` may not choose on this card at `at` (null: they may): only an owner or admin of its workspace, from
  /// the app, on the card the station posted for the ask.
  may(viewer: { role: string; workspace: string | null; email: string }, card: Json, at: CardAt): string | null {
    const a = this.#askAt(card, at);
    if (a === null) return tr(stationLang(), "station.retire.askGone");
    if (!managesStation(viewer) || viewer.workspace !== a.ws) return tr(stationLang(), "station.retire.ownersOnly");
    return null;
  }

  /// `viewer` chose `option` on the card at `at` (it closed): confirmed, the step is taken as them; declined, nothing.
  /// Once, and only on the card the station posted for it.
  chosen(viewer: { email: string }, card: Json, option: string, at: CardAt): void {
    const a = this.#askAt(card, at);
    if (a === null || a.state !== "asked") return;
    const name = a.stationName || a.station.slice(0, 12);
    if (option.trim() !== (a.confirm ?? confirmLabel(a.kind))) {
      a.state = "declined";
      a.by = viewer.email;
      void this.#save();
      this.#tell(a, `${viewer.email} chose ${option.trim()} on the card: station ${name} is not ${a.kind === "start" ? "retired" : "handed over"}; nothing was done.`);
      return;
    }
    a.by = viewer.email;
    // (a card posted before retiring was switched off: confirmed, it starts or hands over nothing)
    if (!this.#d.starts) {
      a.state = "failed";
      a.error = RETIRE_OFF;
      void this.#save();
      this.#tell(a, `${viewer.email} confirmed it in the app, but ${RETIRE_OFF}.`);
      return;
    }
    a.state = "confirmed";
    void this.#save();
    const acting = this.#act(a, viewer.email);
    this.#acting.add(acting);
    void acting.finally(() => this.#acting.delete(acting));
  }

  async #act(a: RetireAsk, by: string): Promise<void> {
    const here = this.#d.here();
    const name = a.stationName || a.station.slice(0, 12);
    const request = a.kind === "start" ? { op: "start", to: a.to ?? "", by } : { op: "hand_over", by };
    try {
      if (here === null) throw new Error("this station is not in its workspace now");
      if (a.station === here) await this.#d.retire.agentAsk(a.ws, { ...request, driver: { station: here, session: a.session } });
      else await this.#d.ask(a.station, { method: "retire.ask", workspace: a.ws, session: a.session, ...request });
      a.state = "done";
      await this.#save();
      this.#tell(a, a.kind === "start"
        ? `${by} confirmed it in the app: station ${name} is being retired, its chats going to ${a.toName || "the other station"}. Its files are sent first while the chats work; you are told once they are all there, then call station_retire hand_over.`
        : `${by} confirmed the hand-over in the app: the chats of station ${name} stop now and go to ${a.toName || "the other station"}; you are told when they are taken there, or if it fails.`);
    } catch (e) {
      a.state = "failed";
      a.error = (e as Error).message;
      await this.#save();
      this.#tell(a, `${by} confirmed it in the app, but it did not ${a.kind === "start" ? "start" : "go"}: ${a.error}. Put that right, then call station_retire ${a.kind} again (a person confirms again).`);
    }
  }

  #tell(a: RetireAsk, text: string): void {
    try {
      this.#d.notify(a.session, text);
    } catch (e) {
      log.warn("retire", "station_retire's asker not told", { session: a.session, error: (e as Error).message });
    }
  }
}

const listed = (xs: { name: string }[]) => xs.map((x) => x.name).join(stationLang() === "en" ? ", " : "、");

/// Card one's words (the station's, in its language): what would move and what would not, from the preview.
function startCard(name: string, toName: string, r: Json): string {
  const lang = stationLang();
  const w = (key: string, args: Record<string, unknown> = {}) => tr(lang, `station.retire.card.${key}`, args);
  const p = r?.preview ?? {};
  const to = r?.to ?? {};
  const accounts: { name: string }[] = p.accounts ?? [];
  const stay: { name: string }[] = p.accountsStay ?? [];
  return [
    w("start.title", { name: name || w("thisStation"), to: toName || to.name || w("otherStation") }),
    w("start.moves", {
      chats: p.chats ?? 0, connects: (p.connects ?? []).length,
      archived: p.archived ? w("start.archived", { n: p.archived }) : "",
      accounts: accounts.length > 0 ? w("start.accounts", { n: accounts.length, names: listed(accounts) }) : "",
    }),
    w("start.stays", { outside: p.outside ? w("start.outside", { n: p.outside }) : "", accountsStay: stay.length > 0 ? w("start.accountsStay", { names: listed(stay) }) : "" }),
    ...(typeof to.free === "number" ? [w(to.git === false ? "start.roomNoGit" : "start.room", { free: gbOf(to.free) })] : []),
    `${w("start.next")}${lang === "en" ? " " : ""}${w("owners")}`,
  ].join("\n\n");
}

/// Card two's words: what was sent, and what confirming it does.
function handOverCard(name: string, s: Json): string {
  const lang = stationLang();
  const w = (key: string, args: Record<string, unknown> = {}) => tr(lang, `station.retire.card.${key}`, args);
  const minutes = typeof s.sentAt === "number" && typeof s.at === "number" ? Math.max(0, Math.round((s.sentAt - s.at) / 60_000)) : null;
  const names = { name: name || w("thisStation"), to: s.toName || w("otherStation") };
  return [
    w(minutes === null ? "handOver.sent" : "handOver.sentIn", { ...names, files: s.files ?? 0, size: gbOf(Number(s.total ?? 0)), minutes }),
    w("handOver.what", names),
    w("owners"),
  ].join("\n\n");
}

/// What is left for a person once a retirement is done.
const REMOVE_WORDS = "Taking the retired station out of the workspace is a person's own step in the still.fail app: the retired station's page (设置 → Stations → it) offers 移出工作区 once it is done.";

/// The preview, in words an agent acts on.
function previewWords(r: Json, toName: string): string {
  const p = r?.preview ?? {};
  const out = [
    `Station ${r?.station?.name || "this one"} would move ${p.chats ?? 0} chats (${p.archived ?? 0} archived besides), ${(p.connects ?? []).length} connects${(p.accounts ?? []).length > 0 ? ` and ${p.accounts.length} accounts` : ""}; running jobs (${(p.jobs ?? []).length}) are started again there. ${p.outside ?? 0} chats work in a directory that is not the station's own and stays.`,
  ];
  if ((p.accountsStay ?? []).length > 0) out.push(`Accounts that stay (it is not its home workspace): ${listed(p.accountsStay)}.`);
  const to = r?.to;
  if (to != null) {
    if (to.reached === false) out.push(`${toName || to.name || "That station"} is not reached now: ${to.error}.`);
    else if (to.old === true) out.push(`${toName || to.name || "That station"} is from before stations could be retired: update it first.`);
    else out.push(`${toName || to.name || "That station"} is reached; git ${to.git ? "is there" : "is NOT there (worktrees cannot be made again: install it first)"}; ${typeof to.free === "number" ? `${gbOf(to.free)} free (what is sent is known once sending starts; it needs about as much again, twice where its disk makes no clones)` : "its free room is not known"}.`);
  }
  if (r?.status?.retiring != null) out.push(`It is being retired already: ${r.status.retiring.step}.`);
  out.push("Not moved by anything: tools installed on the machine, and config.json's machine settings (sandboxes, agentEnv). Check them on the target with station_task before start.");
  return out.join(" ");
}

/// Where a retirement stands, in words an agent acts on.
function statusWords(r: Json): string {
  const s = r?.status?.retiring;
  const out: string[] = [];
  if (s == null) out.push(`Station ${r?.station?.name || "this one"} is not being retired.`);
  else {
    const steps: Record<string, string> = {
      sending: `sending its files (${gbOf(Number(s.done ?? 0))} of ${gbOf(Number(s.total ?? 0))}) while the chats work`,
      sent: s.error ? `back at sent: the chats work again here after the hand-over failed (${s.reason}: ${s.error}); call hand_over again once that is put right` : "all of it sent; waiting for the hand-over to be confirmed (hand_over)",
      quiet: "the chats stopped; what changed is being sent",
      handing: `${s.toName || "the other station"} is putting the chats in (it restarts for it)`,
      accounts: "taken there; its accounts move",
      connects: "taken there; its connects move",
      done: "done",
    };
    out.push(`Retiring to ${s.toName || s.to}: ${steps[s.step] ?? s.step}.`);
    if (s.error && s.step !== "sent") out.push(`Last failure (${s.reason}): ${s.error}${s.retriable ? " (it tries again by itself; again tries it now)" : ""}.`);
    if (Array.isArray(s.jobsThere) && s.jobsThere.length > 0) out.push(`Jobs there: ${s.jobsThere.map((j: Json) => `${j.name} ${j.started ? "started again" : `not started (${j.why ?? "from a station before jobs moved"})`}`).join("; ")}.`);
    if (Array.isArray(s.accountsLeft) && s.accountsLeft.length > 0) out.push(`Accounts left on the retired station: ${s.accountsLeft.map((a: Json) => `${a.name}: ${a.error}`).join("; ")}.`);
    if (s.step === "done") out.push(REMOVE_WORDS);
  }
  for (const t of r?.status?.taking ?? []) out.push(`Taking the chats of ${t.name || t.origin}: ${t.step}${t.error ? ` (${t.error})` : ""}.`);
  // (a retired station is answered by the one that took its place, as any request naming it: that one says it)
  for (const t of r?.status?.taken ?? []) out.push(`This station took the chats of station ${t.name || t.origin} (${t.chats} chats) and is that station too now; jobs: ${t.jobs.length === 0 ? "none" : t.jobs.map((j: Json) => `${j.name} ${j.started ? "started again" : `not started (${j.why ?? "from a station before jobs moved"})`}`).join("; ")}. Its accounts and connects follow as it finishes. ${REMOVE_WORDS}`);
  return out.join(" ");
}
