// Cards: what an agent's post asks people to answer it with (options to pick from, or a field to write
// in), for the viewer: a row's card and line (待处理 · …), how each card in a chat's messages stands, the options in the
// order they are shown (the recommended one last). Dismissing one is kept by the station for the viewer.
import * as format from "./format.ts";
import { t } from "./i18n.ts";
import * as present from "./present.ts";
import { aboutText, describeText, howText } from "./vault-words.ts";
import { arr as arrU, get as getU, isObject, str, u64 } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const trimmed = (v: unknown): string | null => (typeof v === "string" && v.trim() !== "" ? v.trim() : null);
const lines = (text: string): string[] => text.split("\n").map((l) => l.replace(/\r$/, "").trim());

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
    // Answered with, the card closes without a message from the viewer (decision.close): an app has nothing come in for it.
    if (get(o, "action") === "close") shown.closes = true;
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
  // An agent's request for a vault item: its id, for an app to approve it.
  const request = trimmed(get(get(card, "vault"), "request"));
  if (request !== null) v.vault = request;
  const ask = vaultAsk(get(card, "vault"));
  if (ask !== null) v.vaultAsk = ask;
  // An agent's ask to sign in to a site ( 登录态): which, why, on which tab, how it goes.
  const signin = signinAsk(get(card, "signin"));
  if (signin !== null) v.signinAsk = signin;
  // An agent's request for its person's phone: what it asks, and once decided, how.
  const phone = phoneAsk(get(card, "adb"));
  if (phone !== null) v.phoneAsk = phone;
  // An agent's request for a rig of the workspace: which, why, for how long, and once its person decided, how.
  const rig = rigAsk(get(card, "rig"));
  if (rig !== null) v.rigAsk = rig;
  if (kind(card) === "options") v.options = optionsShown(get(card, "options"));
  else if (kind(card) === "text") {
    const p = trimmed(get(card, "placeholder"));
    if (p !== null) v.placeholder = p;
  } else if (kind(card) === "login") {
    // A login a person finishes from the card: its id, and its station when another's.
    const login = trimmed(get(card, "login"));
    const station = trimmed(get(card, "station"));
    if (login !== null) v.login = login;
    if (station !== null) v.station = station;
  }
  return v;
}

/// A card's fields that stand for an ask living beyond its post (inMessages: one card on screen for each).
const LIVE_ASK_FIELDS = ["login", "station", "vault", "vaultAsk", "signinAsk", "phoneAsk", "rigAsk"];

/// Which ask living beyond its post a shown card is (cardShown's), or null: the same one twice is one ask.
function liveAsk(s: J): string | null {
  if (s.login !== undefined) return `login ${s.station ?? ""} ${s.login}`;
  if (s.vault !== undefined) return `vault ${s.vault}`;
  if (s.signinAsk !== undefined) return `signin ${s.signinAsk.id}`;
  if (s.phoneAsk !== undefined) return `phone ${s.phoneAsk.request}`;
  if (s.rigAsk !== undefined) return `rig ${s.rigAsk.request}`;
  return null;
}

/// A vault request as its card says it (station/src/vault/secrets.ts): which item, why, the command, how (or, one to
/// keep a secret, what it is); and once decided, how. Null for a card from before it said so (its post's words say it).
function vaultAsk(v: J): J | null {
  const name = trimmed(get(v, "name"));
  const mode = trimmed(get(v, "mode"));
  if (name === null || mode === null) return null;
  const hosts = arr(get(v, "hosts")).filter((h): h is string => typeof h === "string");
  const out: J = { name, reason: str(get(v, "reason")) ?? "", mode, hosts };
  const timeoutKind = get(get(v, "timeout"), "kind");
  const timeoutSeconds = get(get(v, "timeout"), "seconds");
  if ((timeoutKind === "idle" || timeoutKind === "fixed") && typeof timeoutSeconds === "number") {
    out.timeoutKind = timeoutKind;
    out.timeoutSeconds = timeoutSeconds;
  }
  const command = trimmed(get(v, "command"));
  if (command !== null) out.command = command;
  // Another station its commands run on (or a secret to keep was read on), by name.
  const station = trimmed(get(v, "station"));
  if (station !== null) out.station = station;
  const status = trimmed(get(get(v, "outcome"), "status"));
  if (status !== null) out.status = status;
  const scope = trimmed(get(get(v, "outcome"), "scope"));
  if (scope !== null) out.scope = scope;
  const approved = get(get(v, "outcome"), "timeout");
  if ((get(approved, "kind") === "idle" || get(approved, "kind") === "fixed") && typeof get(approved, "seconds") === "number") {
    out.approvedTimeoutKind = get(approved, "kind");
    out.approvedTimeoutSeconds = get(approved, "seconds");
  }
  // A request to keep a secret (secret_save): what kind, the account it is for, whether the person types it in (or
  // signs in to a service for it: `oauth`).
  const kind = trimmed(get(get(v, "save"), "kind"));
  if (kind !== null) {
    const username = trimmed(get(get(v, "save"), "username"));
    const filename = trimmed(get(get(v, "save"), "filename"));
    const oauth = trimmed(get(get(v, "save"), "oauth"));
    out.save = { kind, ...(username !== null ? { username } : {}), ...(filename !== null ? { filename } : {}), ...(get(get(v, "save"), "typed") === true ? { typed: true } : {}), ...(oauth !== null ? { oauth } : {}) };
  } else if (isObject(get(v, "describe")) && typeof get(get(v, "describe"), "name") === "string") {
    // A request to rename the item or change its about (secret_describe): as they would be, and its about as it was.
    const d = get(v, "describe");
    out.describe = { name: d.name, about: str(d.about) ?? "", wasAbout: str(d.wasAbout) ?? "" };
    out.howText = describeText(name, out.describe);
  } else if (isObject(get(v, "remove"))) {
    // A request to delete the item (secret_delete): its name and why say it all.
    out.remove = true;
  } else {
    out.howText = howText(mode, hosts);
  }
  // What a secret to keep is for and how it is used, as the agent said it: said where how it is given would be.
  const about = trimmed(get(v, "about"));
  if (about !== null && out.save !== undefined) out.howText = aboutText(about);
  return out;
}

/// A site's sign-in as its card says it (station/src/vault/signin.ts): its id, site, why, tab, and how it goes.
function signinAsk(v: J): J | null {
  const id = trimmed(get(v, "id"));
  const site = trimmed(get(v, "site"));
  const screen = trimmed(get(v, "screen"));
  if (id === null || site === null || screen === null) return null;
  const out: J = { id, site, reason: str(get(v, "reason")) ?? "", screen };
  const outcome = get(v, "outcome");
  for (const field of ["status", "why", "said", "save", "kept"]) {
    const said = trimmed(get(outcome, field));
    if (said !== null) out[field] = said;
  }
  const keep = get(outcome, "keep");
  if (typeof keep === "boolean") out.keep = keep;
  return out;
}

/// A request for a person's phone as its card says it (station/src/adb/grants.ts): its id, why, and once decided how.
function phoneAsk(v: J): J | null {
  const request = trimmed(get(v, "request"));
  if (request === null) return null;
  const out: J = { request, reason: str(get(v, "reason")) ?? "" };
  for (const field of ["status", "scope", "why", "link", "lasts"]) {
    const said = trimmed(field === "lasts" ? get(v, field) : get(get(v, "outcome"), field));
    if (said !== null) out[field] = said;
  }
  return out;
}

/// A request for a rig as its card says it (station/src/rigs/requests.ts): what its person's device signs to grant it,
/// and once decided how.
function rigAsk(v: J): J | null {
  const request = trimmed(get(v, "request"));
  const rig = trimmed(get(v, "rig"));
  if (request === null || rig === null) return null;
  const text = (field: string) => str(get(v, field)) ?? "";
  const seconds = (t: J) => (typeof get(t, "seconds") === "number" ? get(t, "seconds") : 0);
  const out: J = {
    request, rig, name: text("name"), owner: text("owner"), reason: text("reason"),
    timeoutKind: str(get(get(v, "timeout"), "kind")) ?? "idle", timeoutSeconds: seconds(get(v, "timeout")),
    session: text("session"), chat: text("chat"), title: text("title"), by: text("by"),
  };
  const outcome = get(v, "outcome");
  for (const field of ["status", "why"]) {
    const said = trimmed(get(outcome, field));
    if (said !== null) out[field] = said;
  }
  const device = trimmed(get(v, "device"));
  if (device !== null) {
    out.device = device;
    out.deviceName = text("deviceName");
  }
  if (typeof get(outcome, "delivered") === "boolean") out.delivered = get(outcome, "delivered");
  if (typeof get(outcome, "until") === "number") out.until = get(outcome, "until");
  const granted = get(outcome, "timeout");
  if (str(get(granted, "kind")) !== null && out.status === "granted") {
    out.grantedKind = str(get(granted, "kind"));
    out.grantedSeconds = seconds(granted);
  }
  return out;
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

/// What a chat asks that no one has decided and the viewer has not let go, the oldest first: its card still waiting,
/// else the message one of its agents needs a person with. A station gives one at most.
export function undecided(row: J): J[] {
  const d = asked(row);
  return d === null || dismissed(d) ? [] : [d];
}

/// One of them for the bar above the chat's composer (`ChatView.asks`): the post it is about, whether it is a card
/// (its options are on that post), whether the viewer is the one to decide it, and in a line what is wanted: the
/// agent's need as it said it, else the post's first line.
export function askOf(row: J, d: J, me: J): J {
  const need = arr(get(row, "agents"))
    .map((a) => get(get(a, "lastTurn"), "need"))
    .find((n) => typeof n === "string" && n.trim() !== "");
  const text = typeof need === "string" ? need.trim() : question(str(get(d.message, "text")) ?? "");
  const who = decider(d.card, get(row, "creator"));
  return { seq: d.seq, card: ofRow(row) !== null, mine: who !== null && present.isViewer(me, who, []), text };
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

export function labelAssignee(card: J, me: J, members: J[], creator: J): J {
  const who = decider(card, creator);
  let text: string;
  if (who !== null) {
    if (present.isViewer(me, who, [])) text = t("core-logic.decisions.assignee.you");
    else {
      const started = creator !== undefined && creator !== null && typeof get(card, "assignee") !== "string" ? str(get(creator, "name")) || null : null;
      text = t("core-logic.decisions.assignee", { name: present.memberName(members, who) ?? started ?? who });
    }
  } else text = t("core-logic.decisions.assignee.none");
  return { ...card, assigneeText: text };
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

export function question(text: string): string {
  const first = firstLine(text);
  return first === "" ? line(text) : first;
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

/// The viewer let go of what the chat asks (its card, or what its agent needs a person for): nothing in it waits for
/// them, though its agent still stands asking.
export function letGo(row: J): boolean {
  const d = asked(row);
  return d !== null && dismissed(d);
}

/// `row` with what it asks let go (its card, or what its agent needs a person for), as its station says it once told
/// (`dismissed`): the viewer's 忽略 said at once.
export function withLetGo(row: J): J {
  const v = structuredClone(row);
  // (the one ofRow and asked read: a card, else a decision, else what its agent needs)
  if (isObject(v.card) && u64(v.card.seq) !== undefined && isObject(v.card.card)) v.card.dismissed = true;
  else if (isObject(v.decision) && u64(v.decision.seq) !== undefined) v.decision.dismissed = true;
  else if (isObject(v.need)) v.need.dismissed = true;
  return v;
}

/// A row's mark, the most urgent first.
export function tone(row: J): string | null {
  const state = str(get(row, "state"));
  if (state === "failed") return "alert";
  if (waits(row) || (state === "block" && !letGo(row))) return "wait";
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

export function presentRow(row: J): J {
  if (!isObject(row)) return row;
  const card = ofRow(row);
  const { card: _card, decision: _decision, ...out } = row as J;
  // Let go by the viewer: its agent asking is not its state for them (no mark, no 要你帮忙).
  if (out.state === "block" && letGo(row)) delete out.state;
  if (card !== null) out.decision = shown(card);
  const t0 = tone(out);
  if (t0 !== null) out.tone = t0;
  return out;
}

/// Where each card in a chat's messages stands. `pending`: undefined when the row is not known; null when none waits.
/// `sending`: what the viewer sent into the chat that has not come back as its entries yet (the outbox, not failed): it
/// answers the last card at once, as the chat shows it sent, rather than when the station has it.
export function inMessages(messages: J[], pendingOf: [number, boolean] | null | undefined, sending: J[] = []): J[] {
  const out = [...messages];
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
    // Whatever a card asks that lives beyond it (a login, a vault request, a sign-in, a phone request) asked again in a
    // later post is that post's card alone: the ask is one card on screen, its field (a login's code, a secret typed in)
    // one editor, and this post says how it went as any replaced card does. Not one kind at a time: #3798 took a login
    // alone and a vault request asked again (secret_reask) still drew two cards of one field (2026-11-04).
    const ask = liveAsk(s);
    if (ask !== null && cards.slice(at + 1).some(([, c]) => liveAsk(cardShown(c)) === ask)) {
      for (const field of LIVE_ASK_FIELDS) delete s[field];
    }
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
      // (an answer from here on its way settles it at once, as when the row is not known: its station's row says so
      // only once it has it)
      const sentHere = !replaced && sending.length > 0 && answer !== undefined;
      isWaiting = pendingOf[0] === seq && !sentHere;
      isDismissed = pendingOf[0] === seq && pendingOf[1] && !sentHere;
    }
    const decision: J = { resolved: !isWaiting };
    if (isDismissed) {
      decision.dismissed = true;
      decision.text = t("core-logic.decisions.dismissed");
    }
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
    const { options: _options, ...rest } = m as J;
    out[i] = { ...rest, ...(kind(card) === "options" ? { options } : {}), card: s, decision };
  });
  return out;
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
