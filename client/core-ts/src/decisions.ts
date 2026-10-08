// Cards (decisions.rs): what an agent's post asks people to answer it with (options to pick from, or a field to write
// in), for the viewer: a row's card and line (奏 · …), how each card in a chat's messages stands, the options in the
// order they are shown (the recommended one last), and the 奏 page's day. Setting one aside is kept with the prefs
// (`decisionsDeferred`); dismissing one is kept by the station for the viewer.
import * as format from "./format.ts";
import { t } from "./i18n.ts";
import * as present from "./present.ts";
import { arr as arrU, get as getU, isObject, str, u64 } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const trimmed = (v: unknown): string | null => (typeof v === "string" && v.trim() !== "" ? v.trim() : null);
const lines = (text: string): string[] => text.split("\n").map((l) => l.replace(/\r$/, "").trim());

export function deferralKey(station: string, thread: number, seq: number): string {
  return `${station}\t${thread}\t${seq}`;
}

export function deferredAt(prefs: J, station: string, thread: number, seq: number): number | null {
  const v = get(get(prefs, "decisionsDeferred"), deferralKey(station, thread, seq));
  return typeof v === "number" ? v : null;
}

/// The answers an options card offers, as shown: labelled ones, the recommended moved last.
export function optionsShown(options: J): J[] {
  const all: J[] = [];
  for (const o of arr(options)) {
    const label = trimmed(get(o, "label"));
    if (label === null) continue;
    const shown: J = { label };
    const detail = trimmed(get(o, "detail"));
    if (detail !== null) shown.detail = detail;
    if (get(o, "recommended") === true) shown.recommended = true;
    all.push(shown);
  }
  return [...all.filter((o) => o.recommended === undefined), ...all.filter((o) => o.recommended !== undefined)];
}

export function kind(card: J): string {
  return str(get(card, "type")) ?? "";
}

function optionsCard(options: J): J {
  return { type: "options", options: options ?? null };
}

export function ofMessage(m: J): J | null {
  const card = get(m, "card");
  if (card !== undefined && typeof get(card, "type") === "string") return structuredClone(card);
  const options = get(m, "options");
  return Array.isArray(options) && options.length > 0 ? optionsCard(structuredClone(options)) : null;
}

/// A card as the clients show it (`MessageCard`).
export function cardShown(card: J): J {
  const v: J = { type: kind(card) };
  for (const field of ["assignee", "assigneeText"]) if (get(card, field) !== undefined) v[field] = card[field];
  if (kind(card) === "options") v.options = optionsShown(get(card, "options"));
  else if (kind(card) === "text") {
    const p = trimmed(get(card, "placeholder"));
    if (p !== null) v.placeholder = p;
  }
  return v;
}

/// Who decides a card: its assignee, else whoever started its chat.
export function decider(card: J, creator: J): string | null {
  return trimmed(get(card, "assignee")) ?? trimmed(get(creator, "email")) ?? trimmed(get(creator, "id"));
}

export function forViewer(row: J, me: J): J | null {
  const d = asked(row);
  if (d === null || dismissed(d)) return null;
  const who = decider(d.card, get(row, "creator"));
  return who !== null && present.isViewer(me, who, []) ? d : null;
}

/// What waits for the viewer in a chat, for the bar above its composer (`ChatView.waiting`): the post it is about,
/// whether it is a card (its options are on that post), and in a line what is wanted: the agent's need as it said it,
/// else the post's first line.
export function waitingOf(row: J, d: J): J {
  const need = arr(get(row, "agents"))
    .map((a) => get(get(a, "lastTurn"), "need"))
    .find((n) => typeof n === "string" && n.trim() !== "");
  const text = typeof need === "string" ? need.trim() : line(str(get(d.message, "text")) ?? "").replace(/^奏 · /, "");
  return { seq: d.seq, card: ofRow(row) !== null, text };
}

export function asked(row: J): J | null {
  const card = ofRow(row);
  if (card !== null) return card;
  const need = get(row, "need");
  if (u64(get(need, "seq")) === undefined || !isObject(get(need, "message"))) return null;
  const v = structuredClone(need);
  v.card = { type: "text" };
  return v;
}

export function labelAssignee(card: J, me: J, members: J[], creator: J): void {
  const who = decider(card, creator);
  let text: string;
  if (who !== null) {
    if (present.isViewer(me, who, [])) text = t("core-logic.decisions.assignee.you");
    else {
      const started = creator !== undefined && creator !== null && typeof get(card, "assignee") !== "string" ? str(get(creator, "name")) || null : null;
      text = t("core-logic.decisions.assignee", { name: present.memberName(members, who) ?? started ?? who });
    }
  } else text = t("core-logic.decisions.assignee.none");
  card.assigneeText = text;
}

export function line(text: string): string {
  const first = firstLine(text);
  return first === "" ? t("core-logic.decisions.line.empty") : t("core-logic.decisions.line", { text: first });
}

function firstLine(text: string): string {
  const first = lines(text).find((l) => l !== "") ?? "";
  const clean = format.cleanText(first).replaceAll("**", "").replaceAll("__", "").replaceAll("`", "");
  return clean.replace(/^[#>\-* ]+/, "").trim();
}

export function asks(row: J, seq: number, text: string): string {
  const thread = u64(get(row, "thread")) ?? null;
  for (const a of arr(get(row, "agents"))) {
    if (present.shownStatus(a) !== "block") continue;
    const about = present.stateAbout(a, thread);
    if (about !== null && about !== seq) continue;
    const need = trimmed(get(get(a, "lastTurn"), "need"));
    if (need !== null) return need;
  }
  const first = firstLine(text);
  return first === "" ? line(text) : first;
}

export function question(text: string): string {
  const first = firstLine(text);
  return first === "" ? line(text) : first;
}

/// How the viewer answered a card.
export function answerText(a: J): string {
  const card = get(a, "card");
  const labels = arr(get(card, "options"));
  if (get(a, "closed") === true) {
    const closing = labels.filter((o) => get(o, "action") === "close").map((o) => get(o, "label")).filter((l) => typeof l === "string");
    return closing.length === 1 ? t("core-logic.decisions.answer.chose", { label: closing[0].trim() }) : t("core-logic.decisions.answer.handled");
  }
  const reply = (str(get(a, "reply")) ?? "").trim();
  if (get(a, "quoted") === true) {
    const label = labels.map((o) => get(o, "label")).find((l) => typeof l === "string" && l.trim() === reply);
    if (label !== undefined) return t("core-logic.decisions.answer.chose", { label: label.trim() });
  }
  const first = format.cleanText(lines(reply).find((l) => l !== "") ?? "");
  return first === "" ? t("core-logic.decisions.answer.replied") : t("core-logic.decisions.answer.reply", { text: first });
}

/// The 奏 page's day.
export function today(view: J, c: present.Clock): void {
  if (!isObject(view)) return;
  const day = format.localDay(c.now, c.offsetMin);
  const at = (v: J, k: string): number => (typeof get(v, k) === "number" ? v[k] : 0);
  const answered = arr(get(view, "answered")).filter((a) => format.localDay(at(a, "answeredAt"), c.offsetMin) === day);
  for (const a of answered) a.clock = format.clock(at(a, "answeredAt"), c.offsetMin);
  const waits = answered.map((a) => Math.max(at(a, "answeredAt") - at(a, "askedAt"), 0));
  const working = get(view, "working");
  const todayV: J = { count: answered.length, working: Array.isArray(working) ? working.length : 0 };
  if (waits.length > 0) todayV.waited = waitedText(waits.reduce((x, y) => x + y, 0) / waits.length);
  (view as J).answered = answered;
  (view as J).today = todayV;
}

export function waitedText(ms: number): string {
  const m = format.round(ms / 60_000);
  if (m < 1) return t("core-logic.decisions.waited.under_minute");
  if (m < 60) return t("core-logic.jobs.span.minutes", { n: m });
  if (m < 24 * 60) return m % 60 === 0 ? t("core-logic.jobs.span.hours", { n: m / 60 }) : t("core-logic.format.duration.hm", { h: Math.trunc(m / 60), m: m % 60 });
  return t("core-logic.jobs.span.days", { n: Math.trunc(m / (24 * 60)) });
}

/// The card a row waits on, as its station gives it.
export function ofRow(row: J): J | null {
  const hasSeq = (v: J) => u64(get(v, "seq")) !== undefined;
  const card = get(row, "card");
  if (card !== undefined && hasSeq(card) && isObject(get(card, "card"))) return structuredClone(card);
  const decision = get(row, "decision");
  if (decision === undefined || !hasSeq(decision)) return null;
  const v = structuredClone(decision);
  if (!isObject(v.card)) v.card = optionsCard(structuredClone(decision.options ?? null));
  return v;
}

export function dismissed(card: J): boolean {
  return get(card, "dismissed") === true;
}

export function pending(row: J): J | null {
  const c = ofRow(row);
  return c !== null && !dismissed(c) ? c : null;
}

export function waits(row: J): boolean {
  return pending(row) !== null;
}

/// A row's mark, the most urgent first.
export function tone(row: J): string | null {
  const state = str(get(row, "state"));
  if (state === "failed") return "alert";
  if (waits(row) || state === "block") return "wait";
  if (state === "run") return "busy";
  return get(row, "unread") === true ? "done" : null;
}

/// A row's card as the clients show it (`RowDecision`).
export function shown(card: J): J {
  const s = cardShown(get(card, "card"));
  const v: J = { seq: card.seq ?? null, options: s.options ?? [], card: s };
  if (dismissed(card)) v.dismissed = true;
  else v.text = line(str(get(get(card, "message"), "text")) ?? "");
  return v;
}

export function presentRow(row: J): void {
  const card = ofRow(row);
  if (isObject(row)) {
    delete (row as J).card;
    delete (row as J).decision;
  }
  if (card !== null) row.decision = shown(card);
  const t0 = tone(row);
  if (t0 !== null) row.tone = t0;
}

/// Where each card in a chat's messages stands. `pending`: undefined when the row is not known; null when none waits.
/// `sending`: what the viewer sent into the chat that has not come back as its entries yet (the outbox, not failed): it
/// answers the last card at once, as the chat shows it sent, rather than when the station has it.
export function inMessages(messages: J[], pendingOf: [number, boolean] | null | undefined, sending: J[] = []): void {
  const cards: [number, J][] = [];
  for (let i = 0; i < messages.length; i++) {
    const c = ofMessage(messages[i]);
    if (c !== null) cards.push([i, c]);
  }
  cards.forEach(([i, card], at) => {
    const seq = u64(get(messages[i], "seq")) ?? 0;
    const ts = str(get(messages[i], "ts")) ?? "";
    const s = cardShown(card);
    const options: J[] = s.options ?? [];
    const replaced = at + 1 < cards.length;
    const answer = messages.slice(i + 1).find((m) => get(m, "authorKind") === "person")
      ?? (replaced || sending.length === 0 ? undefined : { ...sending[0], authorKind: "person", mine: true });
    let isWaiting: boolean;
    let isDismissed: boolean;
    if (pendingOf === undefined) {
      isWaiting = answer === undefined && !replaced;
      isDismissed = false;
    } else if (pendingOf === null) {
      isWaiting = false;
      isDismissed = false;
    } else {
      isWaiting = pendingOf[0] === seq;
      isDismissed = pendingOf[0] === seq && pendingOf[1];
    }
    const decision: J = { resolved: !isWaiting };
    if (isDismissed) decision.dismissed = true;
    if (!isWaiting) {
      if (answer !== undefined) {
        const name = get(answer, "mine") === true ? t("core-logic.decisions.you") : (str(get(get(answer, "by"), "name")) ?? "");
        const quoted = arr(get(answer, "quotes")).some((q) => {
          const qt = str(get(q, "ts"));
          return qt !== undefined && ts !== "" && qt === ts;
        });
        const saidText = (str(get(answer, "text")) ?? "").trim();
        const chosen = options.map((o) => str(get(o, "label"))).find((l) => l !== undefined && quoted && l === saidText);
        decision.answeredBy = name;
        if (chosen !== undefined) {
          decision.chosen = chosen;
          decision.text = t("core-logic.decisions.chose", { name, label: chosen });
        } else decision.text = t("core-logic.decisions.replied", { name });
      } else if (replaced) decision.text = t("core-logic.decisions.replaced");
    }
    const m = messages[i];
    if (!isObject(m)) return;
    if (kind(card) === "options") (m as J).options = options;
    else delete (m as J).options;
    (m as J).card = s;
    (m as J).decision = decision;
  });
}

function quoteOf(card: J): J[] | null {
  const message = get(card, "message");
  if (!isObject(message)) return null;
  const text = str(message.text) ?? "";
  const author = str(message.authorName) || "agent";
  const quote: J = { author, text, comment: "", role: "agent" };
  const ts = str(message.ts);
  if (ts) quote.ts = ts;
  return [quote];
}

/// The text and quote a picked option sends.
export function answer(card: J, option: string): [string, J[]] | null {
  if (kind(get(card, "card")) !== "options") return null;
  const label = optionsShown(get(get(card, "card"), "options")).map((o) => o.label as string).find((l) => l === option.trim());
  if (label === undefined) return null;
  const q = quoteOf(card);
  return q === null ? null : [label, q];
}

/// Only an explicit agent-provided action closes silently.
export function closes(card: J, option: string): boolean {
  return kind(get(card, "card")) === "options" && arr(get(get(card, "card"), "options")).some((o) => typeof get(o, "label") === "string" && o.label.trim() === option.trim() && get(o, "action") === "close");
}

export function reply(card: J, text: string, hasExtras: boolean): [string, J[]] | null {
  const k = kind(get(card, "card"));
  if (!(k === "text" || k === "options") || (text.trim() === "" && !hasExtras)) return null;
  const q = quoteOf(card);
  return q === null ? null : [text.trim(), q];
}

/// The order of the 奏 page: not set aside first (oldest asked first), then set aside (latest last).
export function order<T>(items: [T, number, number | null][]): void {
  items.sort((a, b) => {
    const sa = a[2] !== null ? 1 : 0;
    const sb = b[2] !== null ? 1 : 0;
    if (sa !== sb) return sa - sb;
    if ((a[2] ?? 0) !== (b[2] ?? 0)) return (a[2] ?? 0) - (b[2] ?? 0);
    return a[1] - b[1];
  });
}
