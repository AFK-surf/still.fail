// Prototype: the core's chat list in TypeScript, ported from the Rust core: client/core/src/views.rs (`chats`, `days`),
// present.rs, decisions.rs, format.rs, client/shapes/src/model.rs and client/i18n. Each function says what it ports
// and keeps its shape, so the two can be read side by side; ../rust is the original over the same input, and their
// outputs must be equal. A plain script with erasable types: Node strips them, QuickJS runs the result with the
// catalog (CATALOG, the words of client/i18n/catalog/zh) put before it.

declare const CATALOG: Record<string, string | { one?: string; other: string }>;
declare const host: {
  now(): number;
  log(text: string): void;
  emit(topic: string, value: string): void;
  save(text: string): void;
  connect(addr: string): Promise<string>;
  request(conn: number, body: string): Promise<string>;
};

type Json = any;

// ---- serde_json's reading of a value ----

const isObj = (v: Json): boolean => v !== null && typeof v === "object" && !Array.isArray(v);
const str = (v: Json): string | undefined => (typeof v === "string" ? v : undefined);
const u64 = (v: Json): number | undefined => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : undefined);
const i64 = (v: Json): number | undefined => (typeof v === "number" && Number.isInteger(v) ? v : undefined);
const f64 = (v: Json): number | undefined => (typeof v === "number" ? v : undefined);
const arr = (v: Json): Json[] => (Array.isArray(v) ? v : []);
const get = (v: Json, k: string): Json => (isObj(v) ? v[k] : undefined);
const nonempty = (s: string | undefined): string | undefined => (s !== undefined && s !== "" ? s : undefined);
const trimmed = (s: string | undefined): string | undefined => nonempty(s?.trim());
// Rust's `str::lines`, then the first line not blank, trimmed.
const firstLine = (text: string): string => text.split("\n").map((l) => l.trim()).find((l) => l !== "") ?? "";

// ---- client/i18n ----

function tr(key: string, args: Record<string, string | number> = {}): string {
  const found = CATALOG[key];
  let text: string;
  if (typeof found === "string") text = found;
  else if (found && typeof found === "object") {
    const one = "n" in args && String(args.n).trim() === "1";
    text = (one ? found.one : found.other) ?? found.other ?? key;
  } else text = key;
  return fill(text, args);
}

function fill(text: string, args: Record<string, string | number>): string {
  if (Object.keys(args).length === 0 || !text.includes("{")) return text;
  let out = "";
  let rest = text;
  for (let open = rest.indexOf("{"); open >= 0; open = rest.indexOf("{")) {
    out += rest.slice(0, open);
    const after = rest.slice(open + 1);
    const close = after.indexOf("}");
    if (close >= 0 && /^[A-Za-z0-9_]*$/.test(after.slice(0, close))) {
      const name = after.slice(0, close);
      out += name in args ? String(args[name]) : rest.slice(open, open + close + 2);
      rest = after.slice(close + 1);
    } else {
      out += "{";
      rest = after;
    }
  }
  return out + rest;
}

// ---- client/shapes/src/model.rs ----

function modelKey(id: string): string {
  let whole = id.trim().toLowerCase();
  const bracket = whole.indexOf("[");
  const context = bracket >= 0 ? whole.slice(bracket) : "";
  whole = bracket >= 0 ? whole.slice(0, bracket) : whole;
  let m = whole.split("/").pop() ?? whole;
  m = m.split("@")[0];
  for (let dot = m.indexOf("."); dot >= 0; dot = m.indexOf(".")) {
    const head = m.slice(0, dot);
    const rest = m.slice(dot + 1);
    if (head === "" || !/^[a-zA-Z]+$/.test(head) || rest === "") break;
    m = rest;
  }
  const v = m.lastIndexOf("-v");
  if (v >= 0 && stamp(m.slice(v + 2))) m = m.slice(0, v);
  const parts = m.split("-");
  const digits = (s: string, n: number) => s.length === n && /^[0-9]+$/.test(s);
  const n = parts.length;
  if (n > 1 && digits(parts[n - 1], 8)) m = parts.slice(0, n - 1).join("-");
  else if (n > 3 && digits(parts[n - 3], 4) && digits(parts[n - 2], 2) && digits(parts[n - 1], 2)) m = parts.slice(0, n - 3).join("-");
  return m + context;
}

function stamp(s: string): boolean {
  const colon = s.indexOf(":");
  if (colon < 0) return false;
  const [major, minor] = [s.slice(0, colon), s.slice(colon + 1)];
  return /^[0-9]+$/.test(major) && /^[0-9]+$/.test(minor);
}

function modelName(id: string): string {
  const k = modelKey(id);
  const at = k.indexOf("[");
  const base = at >= 0 ? k.slice(0, at) : k;
  const context = at >= 0 ? k.slice(at + 1).replace(/\]+$/, "").toUpperCase() : "";
  const named = namedModel(base);
  if (named === undefined) return id.trim();
  return context === "" ? named : `${named} ${context}`;
}

const CLAUDE = ["fable", "opus", "sonnet", "haiku"];
const allDigits = (w: string) => /^[0-9]*$/.test(w);

function namedModel(base: string): string | undefined {
  const words = base.split("-").filter((w) => w !== "");
  const first = words[0];
  if (first === undefined) return undefined;
  if (first === "claude" || CLAUDE.includes(first)) {
    const family = words.find((w) => CLAUDE.includes(w));
    if (family === undefined) return undefined;
    const version = words.filter((w) => allDigits(w));
    const rest = words.filter((w) => w !== "claude" && w !== family && !allDigits(w)).map(word);
    const out = [word(family)];
    if (version.length > 0) out.push(version.join("."));
    return [...out, ...rest].join(" ");
  }
  const dashed = first === "gpt" ? "GPT" : first === "glm" ? "GLM" : undefined;
  if (dashed !== undefined && words[1] !== undefined) {
    return [`${dashed}-${words[1]}`, ...words.slice(2).map(word)].join(" ");
  }
  const oSeries = first.length > 1 && first.startsWith("o") && allDigits(first.slice(1));
  const known = ["gpt", "glm", "codex", "deepseek", "qwen", "qwq", "gemini", "gemma", "kimi", "moonshot", "minimax", "grok", "mistral", "devstral", "codestral", "llama", "doubao", "hunyuan", "ernie"];
  const family = first.replace(/[0-9.]+$/, "");
  if (!oSeries && !known.includes(family)) return undefined;
  return words.map((w, i) => (i === 0 && oSeries ? w : word(w))).join(" ");
}

const BRANDS: Record<string, string> = {
  deepseek: "DeepSeek", minimax: "MiniMax", qwq: "QwQ", glm: "GLM", gpt: "GPT", oss: "OSS", moonshot: "Moonshot",
  devstral: "Devstral", codestral: "Codestral", llama: "Llama", ernie: "ERNIE", vl: "VL", r1: "R1", it: "IT",
};

function word(w: string): string {
  if (w in BRANDS) return BRANDS[w];
  return w === "" ? "" : w[0].toUpperCase() + w.slice(1);
}

// ---- client/core/src/format.rs ----

const MINUTE = 60_000;
const DAY = 86_400_000;

function local(ms: number, offsetMin: number) {
  const at = ms + offsetMin * MINUTE;
  const days = Math.floor(at / DAY);
  const z = days + 719_468;
  const era = Math.floor(z / 146_097);
  const doe = z - era * 146_097;
  const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36_524) - Math.floor(doe / 146_096)) / 365);
  const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
  const mp = Math.floor((5 * doy + 2) / 153);
  const d = doy - Math.floor((153 * mp + 2) / 5) + 1;
  const m = mp < 10 ? mp + 3 : mp - 9;
  const weekday = (((days + 4) % 7) + 7) % 7;
  return { month: m, day: d, weekday };
}

const localDay = (ms: number, offsetMin: number) => Math.floor((ms + offsetMin * MINUTE) / DAY);

function dayLabel(ms: number, now: number, offsetMin: number): string {
  const diff = localDay(now, offsetMin) - localDay(ms, offsetMin);
  if (diff === 0) return tr("core-logic.format.day.today");
  if (diff === 1) return tr("core-logic.format.day.yesterday");
  const { month, day, weekday } = local(ms, offsetMin);
  if (diff < 7) return tr(`core-logic.format.weekday.${weekday}`);
  return tr(`core-logic.format.date.${month}`, { day });
}

function cleanText(text: string): string {
  let out = "";
  let rest = text;
  for (let at = rest.indexOf("<@"); at >= 0; at = rest.indexOf("<@")) {
    out += rest.slice(0, at);
    const tail = rest.slice(at + 2);
    const id = tail.search(/[^A-Z0-9]/);
    const len = id < 0 ? tail.length : id;
    if (len > 0 && tail.slice(len).startsWith(">")) {
      rest = tail.slice(len + 1);
    } else {
      out += "<@";
      rest = tail;
    }
  }
  out += rest;
  return out.split(/\s+/).filter((w) => w !== "").join(" ");
}

function makerOf(model: string): [string, string] | undefined {
  const m = model.toLowerCase();
  const has = (words: string[]) => words.some((w) => m.includes(w));
  const oSeries = m.startsWith("o") && /^[0-9]/.test(m.slice(1));
  if (has(["claude", "opus", "sonnet", "haiku", "fable"])) return ["anthropic", "Anthropic"];
  if (has(["gpt", "codex", "openai"]) || oSeries) return ["openai", "OpenAI"];
  if (has(["deepseek"])) return ["deepseek", "DeepSeek"];
  if (has(["qwen", "qwq"])) return ["qwen", "Qwen"];
  if (has(["glm", "zhipu"])) return ["zhipu", tr("core-logic.format.maker.zhipu")];
  if (has(["gemini", "gemma"])) return ["gemini", "Google"];
  if (has(["kimi", "moonshot"])) return ["kimi", "Kimi"];
  if (has(["minimax", "abab"])) return ["minimax", "MiniMax"];
  if (has(["grok"])) return ["xai", "xAI"];
  return undefined;
}

function agentLabel(model: string | undefined, effort: string | undefined): string {
  const named = nonempty(model) !== undefined ? modelName(model!) : tr("core-logic.format.default_model");
  const e = nonempty(effort);
  return e !== undefined ? `${named} · ${e}` : named;
}

const efforts = (runtime: string) => (runtime === "codex" ? ["minimal", "low", "medium", "high", "xhigh"] : ["low", "medium", "high", "xhigh", "max"]);
const runtimeLabel = (runtime: string) => (runtime === "codex" ? "Codex" : "Claude Code");

function failureText(detail: string): string {
  const reason = detail.split(":")[0].trim();
  const known = ["rate_limit", "auth", "model", "exited"];
  return tr(`core-logic.format.failure.${known.includes(reason) ? reason : "other"}`);
}

function statusText(status: string): [string, string] {
  const tones: Record<string, string> = { running: "accent", queued: "accent", final: "green", block: "blue", decision: "blue", failed: "red", unexpected: "red", aborted: "neutral" };
  return status in tones ? [tr(`core-logic.format.status.${status}`), tones[status]] : [tr("core-logic.format.status.idle"), "neutral"];
}

function processText(process: string): string {
  return tr(`core-logic.format.process.${process === "running" || process === "warm" ? process : "released"}`);
}

// ---- client/core/src/present.rs ----

function ending(s: Json): string | undefined {
  const turn = get(s, "lastTurn");
  if (!isObj(turn)) return undefined;
  const said = str(turn.ending) ?? str(turn.declared);
  if (said === undefined) return undefined;
  return said === "final" ? "all_done" : said === "block" || said === "need_decision" ? "need_help" : said;
}

function sessionStatus(s: Json): string {
  if (get(s, "process") === "running") return "running";
  if ((u64(get(s, "pending")) ?? 0) > 0) return "queued";
  const turn = get(s, "lastTurn");
  if (!isObj(turn)) return "idle";
  switch (ending(s)) {
    case "all_done": return "final";
    case "need_help": return "block";
    case "waiting": return "running";
  }
  const outcome = str(turn.outcome);
  return outcome === "failed" ? "failed" : outcome === "aborted" ? "aborted" : "unexpected";
}

function waiting(s: Json): Json {
  const turn = isObj(get(s, "lastTurn")) ? s.lastTurn : undefined;
  const since = turn !== undefined && ending(s) === "waiting" ? i64(turn.endedAt) : undefined;
  if (since !== undefined && sessionStatus(s) === "running" && get(s, "process") !== "running") {
    const what = trimmed(str(turn.waitFor));
    return {
      since, seconds: turn.waitSeconds === undefined ? null : turn.waitSeconds,
      text: what !== undefined ? tr("core-views.present.waiting_for", { what }) : tr("core-views.present.waiting"),
    };
  }
  return null;
}

function rowWatch(agents: Json[]): Json {
  const names: string[] = agents.filter((a) => isObj(get(a, "watch"))).flatMap((a) => arr(a.watch.names).filter((n) => typeof n === "string"));
  if (names.length === 0) return undefined;
  const separator = tr("core-views.list_separator");
  const named = names.map((text) => tr("core-views.quoted", { text })).join(separator);
  return { text: tr("core-views.present.watching_names", { names: names.join(separator) }), ask: tr("core-views.present.watch_ask", { names: named }) };
}

const watching = (s: Json) => isObj(get(s, "watch")) && waiting(s) !== null;
const shownStatus = (s: Json) => (watching(s) ? "idle" : sessionStatus(s));
const markOf = (s: Json) => badge(shownStatus(s));

function badge(status: string): string | undefined {
  if (status === "running" || status === "queued") return "run";
  if (status === "block" || status === "decision") return "block";
  if (status === "failed" || status === "unexpected") return "failed";
  return undefined;
}

function rowState(agents: Json[]): string | undefined {
  const marks = agents.map(markOf).filter((m) => m !== undefined);
  return ["block", "run", "failed"].find((b) => marks.includes(b));
}

function settled(row: Json): boolean {
  const agents = arr(get(row, "agents"));
  return agents.length > 0 && agents.every((a) => shownStatus(a) === "final") && !waits(row) && get(row, "unread") !== true;
}

const pinned = (row: Json) => typeof get(row, "pinned") === "number" || get(row, "pinned") === true;

function stateAbout(agent: Json, thread: number | undefined): number | undefined {
  const about = get(get(agent, "lastTurn"), "about");
  if (!isObj(about)) return undefined;
  return u64(about.thread) === thread || thread === undefined ? u64(about.seq) : undefined;
}

function rowStateLine(row: Json): [string, number | undefined] | undefined {
  const thread = u64(get(row, "thread"));
  const c = pending(row);
  const card: [string, number | undefined] | undefined = c === undefined ? undefined : [str(c.text) ?? line(str(get(c.message, "text")) ?? ""), u64(c.seq)];
  const agents = arr(get(row, "agents"));
  const textOf = (a: Json) => str(get(a, "statusText"));
  const atWork = agents.some((a) => shownStatus(a) === "queued" || (shownStatus(a) === "running" && waiting(a) === null));
  if (!atWork) {
    const blocked = agents.find((a) => shownStatus(a) === "block");
    if (blocked !== undefined) {
      const need = trimmed(str(get(get(blocked, "lastTurn"), "need"))) !== undefined;
      if (card !== undefined && !need) return card;
      const t = textOf(blocked);
      return t === undefined ? undefined : [t, stateAbout(blocked, thread) ?? card?.[1]];
    }
    const wrong = agents.find((a) => ["failed", "unexpected", "aborted"].includes(shownStatus(a)));
    if (wrong !== undefined) {
      const t = textOf(wrong);
      return t === undefined ? undefined : [t, stateAbout(wrong, thread)];
    }
  }
  if (card !== undefined) return card;
  if (atWork) return undefined;
  const waits = agents.find((a) => waiting(a) !== null);
  if (waits !== undefined) {
    const t = textOf(waits);
    return t === undefined ? undefined : [t, stateAbout(waits, thread)];
  }
  if (!settled(row)) return undefined;
  const done = agents.find((a) => trimmed(str(get(get(a, "lastTurn"), "need"))) !== undefined);
  const text = (done !== undefined ? textOf(done) : undefined) ?? tr("core-views.present.done");
  let about = done !== undefined ? stateAbout(done, thread) : undefined;
  if (about === undefined) {
    for (const a of agents) {
      about = stateAbout(a, thread);
      if (about !== undefined) break;
    }
  }
  return [text, about];
}

function isViewer(me: Json, person: string, slackUsers: string[]): boolean {
  const id = str(get(me, "id"));
  const email = str(get(me, "email"));
  return id === person || (email !== undefined && email.toLowerCase() === person.toLowerCase()) || slackUsers.includes(person);
}

const memberOf = (members: Json[], email: string) => members.find((m) => str(get(m, "email"))?.toLowerCase() === email.toLowerCase());

function person(p: Json, me: Json, members: Json[]) {
  if (!isObj(p)) return;
  const strOf = (k: string) => nonempty(str(p[k]));
  const id = strOf("id") ?? "";
  const email = strOf("email");
  const key = email ?? id;
  const member = memberOf(members, key);
  const memberName = nonempty(str(get(member, "name")));
  const name = id === "local" ? tr("core-views.present.local_page") : memberName ?? strOf("name") ?? email ?? id;
  const mine = isViewer(me, id, []) || (email !== undefined && isViewer(me, email, []));
  const picture = nonempty(str(get(member, "picture"))) ?? null;
  p.shown = { name, display: mine ? tr("core-views.present.you") : name, picture, mine };
}

function rowPeople(row: Json, me: Json, slackUsers: string[], members: Json[]) {
  if (get(row, "people") === undefined && get(row, "creator") === undefined) return;
  const shown = (p: Json) => {
    const q = structuredCopy(p);
    person(q, me, members);
    const id = str(get(q, "id"));
    if (id !== undefined && isViewer(me, id, slackUsers)) {
      q.shown.mine = true;
      q.shown.display = tr("core-views.present.you");
    }
    return q;
  };
  const creator = isObj(row.creator) ? shown(row.creator) : undefined;
  const keyOf = (p: Json) => (str(get(p, "email")) ?? str(get(p, "id")) ?? "").toLowerCase();
  const people: Json[] = creator !== undefined ? [creator] : [];
  for (const p of arr(row.people)) {
    if (!people.some((q) => keyOf(q) === keyOf(p))) people.push(shown(p));
  }
  const display = (p: Json) => str(get(get(p, "shown"), "display")) ?? "";
  const starter = creator === undefined ? -1 : people.findIndex((p) => isObj(p) && "id" in p && "id" in creator && sameJson(p.id, creator.id));
  const rest = people.filter((_, i) => i !== starter).map(display);
  const text = [...(starter >= 0 ? [tr("core-views.present.started_by", { name: display(people[starter]) })] : []), ...(rest.length > 0 ? [rest.join(tr("core-views.list_separator"))] : [])];
  row.peopleText = text.join(" · ");
  if (creator !== undefined) row.creator = creator;
  row.people = people;
}

function lastBy(row: Json, me: Json, slackUsers: string[], members: Json[]): Json {
  const last = get(row, "last");
  if (!isObj(last)) return undefined;
  const kind = str(last.authorKind) ?? "person";
  const author = str(last.author) ?? "";
  const saidName = nonempty(str(last.authorName));
  if (kind === "agent") {
    const agent = arr(get(row, "agents")).find((a) => str(get(a, "key")) === author);
    const identity = last.agentIdentity ?? null;
    const model = str(get(identity, "model")) ?? str(get(agent, "model"));
    const runtime = agent !== undefined && "runtime" in agent ? agent.runtime : "claude";
    return {
      kind: "agent", name: model !== undefined ? modelName(model) : saidName ?? "agent", model: model ?? null, runtime,
      mine: false, state: (agent !== undefined ? markOf(agent) : undefined) ?? null,
    };
  }
  if (kind === "ember" || kind === "stillfail") return { kind: "ember", name: "still.fail", mine: false };
  const mine = isViewer(me, author, slackUsers);
  const member = memberOf(members, author);
  const name = mine ? tr("core-views.present.you") : nonempty(str(get(member, "name"))) ?? saidName ?? author;
  return { kind: "person", id: author, name, picture: nonempty(str(get(member, "picture"))) ?? null, mine };
}

function session(s: Json) {
  if (!isObj(s)) return;
  const status = shownStatus(s);
  let [text, tone] = statusText(status);
  const turn = s.lastTurn ?? null;
  const said = (k: string) => trimmed(str(get(turn, k)));
  if (status === "block" && said("need") !== undefined) text = tr("core-views.present.need_help", { need: said("need")! });
  else if (status === "final" && said("need") !== undefined) text = tr("core-views.present.done_with", { done: said("need")! });
  else if (status === "failed") text = tr("core-views.present.failed", { why: failureText(said("detail") ?? "") });
  if (waiting(s) !== null) {
    const what = trimmed(str(get(s.lastTurn, "waitFor")));
    text = isObj(s.watch) ? tr("core-views.present.watching") : what !== undefined ? tr("core-views.present.waiting_for", { what }) : tr("core-views.present.waiting");
  }
  const runtime = str(s.runtime) ?? "claude";
  const model = str(s.model);
  const title = nonempty(str(s.title)) ?? nonempty(str(s.firstText) !== undefined ? cleanText(s.firstText) : undefined) ?? tr("core-views.no_messages");
  const mark = markOf(s);
  s.statusText = text;
  s.tone = tone;
  s.mark = mark ?? null;
  s.badgeText = mark !== undefined ? badgeText(mark) : null;
  s.titleText = title;
  s.agentText = agentLabel(model, str(s.effort));
  s.modelName = nonempty(model) !== undefined ? modelName(model!) : null;
  s.maker = maker(model);
  s.runtimeText = runtimeLabel(runtime);
  s.processText = str(s.process) !== undefined ? processText(s.process) : null;
  s.efforts = efforts(runtime);
}

function badgeText(b: string): string {
  return tr(`core-views.present.badge.${b === "block" || b === "run" ? b : "failed"}`);
}

function maker(model: string | undefined): Json {
  const m = model !== undefined ? makerOf(model) : undefined;
  return m === undefined ? null : { id: m[0], name: m[1] };
}

// ---- client/core/src/decisions.rs ----

function optionsShown(options: Json): Json[] {
  const all = arr(options).flatMap((o) => {
    const label = trimmed(str(get(o, "label")));
    if (label === undefined) return [];
    const shown: Json = { label };
    const detail = trimmed(str(get(o, "detail")));
    if (detail !== undefined) shown.detail = detail;
    if (get(o, "recommended") === true) shown.recommended = true;
    return [shown];
  });
  return [...all.filter((o) => !("recommended" in o)), ...all.filter((o) => "recommended" in o)];
}

const kind = (card: Json) => str(get(card, "type")) ?? "";

function cardShown(card: Json): Json {
  const v: Json = { type: kind(card) };
  for (const field of ["assignee", "assigneeText"]) {
    if (get(card, field) !== undefined) v[field] = card[field];
  }
  if (kind(card) === "options") v.options = optionsShown(card.options);
  else if (kind(card) === "text") {
    const p = trimmed(str(get(card, "placeholder")));
    if (p !== undefined) v.placeholder = p;
  }
  return v;
}

function line(text: string): string {
  const first = firstLineClean(text);
  return first === "" ? tr("core-logic.decisions.line.empty") : tr("core-logic.decisions.line", { text: first });
}

function firstLineClean(text: string): string {
  const clean = cleanText(firstLine(text)).split("**").join("").split("__").join("").split("`").join("");
  return clean.replace(/^[#>\-* ]+/, "").trim();
}

function ofRow(row: Json): Json {
  const hasSeq = (v: Json) => u64(get(v, "seq")) !== undefined;
  const card = get(row, "card");
  if (hasSeq(card) && isObj(card.card)) return structuredCopy(card);
  const decision = get(row, "decision");
  if (!hasSeq(decision)) return undefined;
  const v = structuredCopy(decision);
  if (!isObj(v.card)) v.card = { type: "options", options: decision.options ?? null };
  return v;
}

const dismissed = (card: Json) => get(card, "dismissed") === true;

function pending(row: Json): Json {
  const c = ofRow(row);
  return c !== undefined && !dismissed(c) ? c : undefined;
}

const waits = (row: Json) => pending(row) !== undefined;

function tone(row: Json): string | undefined {
  const state = str(get(row, "state"));
  if (state === "failed") return "alert";
  if (waits(row) || state === "block") return "wait";
  if (state === "run") return "busy";
  return get(row, "unread") === true ? "done" : undefined;
}

function shown(card: Json): Json {
  const s = cardShown(card.card);
  const v: Json = { seq: card.seq ?? null, options: s.options ?? [], card: s };
  if (dismissed(card)) v.dismissed = true;
  else v.text = line(str(get(card.message, "text")) ?? "");
  return v;
}

function presentDecision(row: Json) {
  const card = ofRow(row);
  delete row.card;
  delete row.decision;
  if (card !== undefined) row.decision = shown(card);
  const t = tone(row);
  if (t !== undefined) row.tone = t;
}

// ---- the view: views.rs `chats` (one station, online, its link up) and `days` ----

function chats(input: Json): Json {
  const me = input.me ?? null;
  const members = arr(input.members);
  const slackUsers: string[] = arr(input.slackUsers).filter((u) => typeof u === "string");
  const address = str(get(input.station, "address")) ?? "";
  const name = str(get(input.station, "name")) ?? "";
  const rows: Json[] = [];
  for (const original of arr(input.rows)) {
    const row = structuredCopy(original);
    row.station = address;
    row.stationName = name;
    const agents = arr(row.agents);
    const watch = rowWatch(agents);
    if (watch !== undefined) row.watch = watch;
    row.state = rowState(agents) ?? null;
    for (const agent of arr(row.agents)) session(agent);
    if (row.connect !== undefined && row.connect !== null) {
      const o = row.origin ?? null;
      const text = (k: string) => nonempty(str(get(o, k)));
      const channel = text("channel");
      const place = text("channelName") !== undefined ? `#${text("channelName")}` : channel !== undefined && channel.startsWith("D") ? tr("core-views.direct_message") : undefined;
      row.originText = ["Slack", text("teamName"), place].filter((p) => p !== undefined).join(" · ");
    }
    if (isObj(row.last)) {
      const text = cleanText(str(row.last.text) ?? "");
      row.last.preview = text === "" ? tr("core-views.file") : text;
    }
    rowPeople(row, me, slackUsers, members);
    const by = lastBy(row, me, slackUsers, members);
    if (by !== undefined) {
      row.last.by = by;
      const who = str(by.name) ?? "";
      const state = str(by.state);
      by.label = state !== undefined ? tr("core-views.by_label", { name: who, state: badgeText(state) }) : who;
      by.maker = maker(str(by.model));
    }
    presentDecision(row);
    if (settled(row) && !pinned(row) && row.archiveReminderDismissed !== true) {
      row.settled = true;
      row.archivable = true;
    }
    const stateLine = rowStateLine(row);
    if (stateLine !== undefined) {
      row.stateText = stateLine[0];
      if (stateLine[1] !== undefined) row.stateAbout = stateLine[1];
    }
    rows.push(row);
  }
  return { days: days(rows, f64(input.now) ?? 0, i64(input.offsetMin) ?? 0) };
}

function days(all: Json[], now: number, offset: number): Json[] {
  const at = (row: Json) => f64(row.lastActiveAt) ?? 0;
  const pinnedRows = all.filter((row) => typeof row.pinned === "number");
  const rows = all.filter((row) => typeof row.pinned !== "number");
  const pinnedAt = (row: Json) => f64(row.pinned) ?? 0;
  pinnedRows.sort((a, b) => pinnedAt(b) - pinnedAt(a) || at(b) - at(a));
  for (const row of pinnedRows) row.pinned = true;
  for (const row of rows) if ("pinned" in row) row.pinned = false;
  const day = (ms: number) => Math.floor((ms + offset * 60_000) / DAY);
  const isSettled = (row: Json) => row.settled === true;
  rows.sort((a, b) => day(at(b)) - day(at(a)) || Number(isSettled(a)) - Number(isSettled(b)) || at(b) - at(a));
  const today = day(now);
  const groups: [number, number, Json[]][] = [];
  for (const row of rows) {
    const [t, d] = [at(row), day(at(row))];
    const last = groups[groups.length - 1];
    if (last !== undefined && last[0] === d) last[2].push(row);
    else groups.push([d, t, [row]]);
  }
  const top = pinnedRows.length > 0 ? [{ daysAgo: -1, at: at(pinnedRows[0]), label: tr("core-views.pinned"), pinned: true, items: pinnedRows }] : [];
  return [...top, ...groups.map(([d, t, items]) => ({ daysAgo: today - d, at: t, label: dayLabel(t, now, offset), items }))];
}

// A copy of a JSON value (QuickJS has no structuredClone).
function structuredCopy(v: Json): Json {
  return v === undefined ? undefined : JSON.parse(JSON.stringify(v));
}

function sameJson(a: Json, b: Json): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

// ---- timing: the view `runs` times, each handed to the UI as text, as the core's emissions are ----

function bench(input: Json, runs: number) {
  const took: number[] = [];
  let text = "";
  for (let i = 0; i < runs; i++) {
    const started = host.now();
    text = JSON.stringify(chats(input));
    took.push(host.now() - started);
  }
  const rest = took.slice(1).sort((a, b) => a - b);
  return { rows: arr(input.rows).length, first: took[0], median: rest[Math.floor(rest.length / 2)] ?? took[0], text };
}

// In the client shell (../client-shell, `@<input>`): the input comes as a request's answer.
async function main(addr: string, runs: number) {
  const opened = JSON.parse(await host.connect(addr));
  const input = JSON.parse(await host.request(opened.id, JSON.stringify({ op: "chats" })));
  const { text, ...result } = bench(input, runs);
  host.save(text);
  host.emit("result", JSON.stringify({ engine: "quickjs", ...result }));
}
