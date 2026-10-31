// An agent's execution history as the clients show it (history.rs): what actually ran, put together here so every
// client draws the same thing. Messages in and out, state marks and the agent's own words are boundaries; the tool
// calls and thinking between two boundaries fold into one group, named by its latest call (shapes: HistoryView).
import { args, doing, epochMs, importantCall, kindOf, type Known, tasksOf, told, toolName } from "./activity.ts";
import * as format from "./format.ts";
import * as brand from "./brand.ts";
import { t } from "./i18n.ts";
import { lineOf, markdown, type MdStore } from "./markdown.ts";
import * as present from "./present.ts";
import { money } from "./views/usage.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// What a history is read with besides its transcript.
export type Context = {
  threads: J[];
  members: J[];
  slackUsers: string[];
  botUserId: string | null;
  botName: string;
  /// The Slack people the station's agents heard from, by Slack id: what their mentions are shown as.
  slackNames?: [string, string][];
  runtime: string;
  started: boolean;
  offsetMin: number;
  workspaces: Map<string, format.SlackWorkspace>;
  /// Now, for the day a turn's time is said with (a turn of today says only its clock); absent: every turn says its clock alone.
  now?: number;
  /// The workspace's stations' names by id, for the calls that work on one (station_task); absent: none known.
  stations?: ReadonlyMap<string, string>;
  /// Where the trees of its Markdown are kept on the device (markdown.ts); absent: read here only.
  md?: MdStore;
};

function kindKey(kind: string): string {
  return ["read", "search", "edit", "command", "web", "agent", "thread"].includes(kind) ? kind : "other";
}

function did(kind: string, n: number): string {
  return t(`core-logic.history.did.${kindKey(kind)}`, { n });
}

function line(text: string, max: number): string {
  return Array.from(text.split("\n")[0] ?? "").slice(0, max).join("");
}

export function hint(text: string): string {
  const a = args(text);
  if (!a) return line(text, 160);
  const key = ["command", "cmd", "file_path", "path", "pattern", "url", "query", "description", "prompt"].find((k) => a[k] !== undefined && a[k] !== null);
  const value = key !== undefined ? a[key] : undefined;
  const s = typeof value === "string" ? value : Array.isArray(value) ? value.map((p) => (typeof p === "string" ? p : "")).join(" ") : "";
  return line(s, 160);
}

function describe(text: string): string | null {
  const d = args(text)?.description;
  if (typeof d !== "string" || d.trim() === "") return null;
  return line(d.trim(), 160);
}

function fileOf(text: string): string | null {
  const a = args(text);
  if (!a) return null;
  for (const k of ["file_path", "path", "notebook_path"]) if (a[k] !== undefined) return typeof a[k] === "string" ? a[k] : null;
  return null;
}

/// A message a prompt carried; `station`: a notice of the station's own (via="ember"), not a person's; `agent`: an
/// agent's (marked `bot`: another session's letter, a bot in the thread), its words Markdown.
export type Sourced = { user: string; name: string | null; ts: string; text: string; thread: string | null; slack: boolean; station: boolean; agent: boolean };

/// What a station notice told its agent, read back from the words it was given (jobs.ts `named` and its notices,
/// opened.ts `notice`): a job's own words (`said`), or an event of a job's or of a chat it opened, in a line with what
/// more it carried (a job's last lines, its error, the chat's words); null for words of any other kind.
export type Notice =
  | { kind: "said"; name: string; said: string }
  | { kind: "event"; line: string; failed: boolean; chat: boolean; more: string | null; output: boolean };

const CHAT_ENDS: Record<string, [string, boolean]> = {
  "ended its turn all_done": ["done", false],
  "needs a person": ["human", false],
  "stopped with an error": ["failed", true],
  "was stopped by a person": ["stopped", false],
};

export function readNotice(text: string): Notice | null {
  const chat = /^The chat you opened, "(.+?)"(?: \(\S+\))?, (ended its turn all_done|needs a person|stopped with an error|was stopped by a person)(?:: ([\s\S]*?))?(?:\. They are asked there; help if you can, or wait)?\. Read it with chat_read; write to its agent with session_send to its link\.$/.exec(text);
  if (chat) {
    const [how, failed] = CHAT_ENDS[chat[2]];
    return { kind: "event", line: t(`core-logic.history.notice.chat.${how}`, { name: chat[1] }), failed, chat: true, more: chat[3] || null, output: false };
  }
  const restarted = text.startsWith("The station restarted; ");
  const job = /^(Job|Service) "(.+?)" \([^()\s,]+(?:, port \d+)?\) ([\s\S]*)$/.exec(restarted ? text.slice("The station restarted; ".length) : text);
  if (!job) return null;
  const [, kind, name, rest] = job;
  const what = t(kind === "Service" ? "core-logic.history.notice.service" : "core-logic.history.notice.job");
  const event = (key: string, failed: boolean, more: string | null = null, output = false, args: Record<string, string | number> = {}): Notice =>
    ({ kind: "event", line: t(`core-logic.history.notice.${key}`, { what, name, ...args }), failed, chat: false, more, output });
  if (!restarted && rest.startsWith("says: ")) return { kind: "said", name, said: rest.slice("says: ".length) };
  if (restarted && rest === "was started again.") return event("restarted", false);
  const unstarted = /^could not be started again: ([\s\S]*)$/.exec(rest);
  if (unstarted) return event("unstarted", true, unstarted[1]);
  const stopped = /^was stopped by (.+) from still\.fail's page\.$/.exec(rest);
  if (stopped) return event("stopped", false, null, false, { who: stopped[1] });
  const ended = /^ended with (?:exit code (-?\d+)|a signal)(; the station starts it again(?: in [\d.]+ s)?)?\.(?:\nIts last lines:\n```\n([\s\S]*)\n```)?$/.exec(rest);
  if (ended) {
    const again = ended[2] !== undefined ? "Again" : "";
    const code = ended[1] !== undefined ? Number(ended[1]) : null;
    return code !== null ? event(`exited${again}`, code !== 0, ended[3] ?? null, true, { code }) : event(`signaled${again}`, true, ended[3] ?? null, true);
  }
  return null;
}

function attr(attrs: string, name: string): string | null {
  const key = `${name}="`;
  let from = 0;
  for (;;) {
    const at = attrs.indexOf(key, from);
    if (at < 0) return null;
    if (at === 0 || attrs[at - 1] === " ") {
      const rest = attrs.slice(at + key.length);
      const end = rest.indexOf('"');
      return end < 0 ? null : rest.slice(0, end);
    }
    from = at + key.length;
  }
}

/// Whether a tag's attributes carry `name` bare (`bot`), not inside a quoted value.
function bare(attrs: string, name: string): boolean {
  return attrs.replace(/"[^"]*"/g, '""').split(/\s+/).includes(name);
}

function tagEnd(text: string, open: number): number | null {
  let quoted = false;
  for (let i = open; i < text.length; i++) {
    const c = text[i];
    if (c === '"') quoted = !quoted;
    else if (c === ">" && !quoted) return i;
  }
  return null;
}

const unescape = (v: string) => v.replaceAll("&quot;", '"').replaceAll("&amp;", "&");

/// How the station ends words it cut to its length (station/src/read/transcript.ts `clip`).
const CLIPPED = /\n… \(\d+ more characters\)$/;

/// A message's words up to its closing tag; a prompt the station cut short before it, to the end.
function body(text: string, openEnd: number, closeTag: string): [string, number] | null {
  const start = text.startsWith("\n", openEnd) ? openEnd + 1 : openEnd;
  const at = text.indexOf(closeTag, start);
  if (at < 0) return CLIPPED.test(text) ? [text.slice(start), text.length] : null;
  const inner = text.slice(start, at);
  return [inner.endsWith("\n") ? inner.slice(0, -1) : inner, at + closeTag.length];
}

/// Splits a prompt still.fail built into the chat messages it carried and still.fail's own words around them.
export function parsePrompt(text: string): [Sourced[], string] {
  const messages: Sourced[] = [];
  let rest = "";
  let at = 0;
  for (;;) {
    const open = text.indexOf("<message ", at);
    if (open < 0) break;
    // still.fail's instructions given to a session continued from a terminal (station instructions.ts
    // `continuedHere`) show the shape of a message (thread="CHANNEL/THREAD_TS"): they carry none.
    const told = text.indexOf("<stillfail-instructions>", at);
    if (told >= 0 && told < open) {
      const end = text.indexOf("</stillfail-instructions>", told);
      const past = end < 0 ? text.length : end + "</stillfail-instructions>".length;
      rest += text.slice(at, past);
      at = past;
      continue;
    }
    const headEnd = tagEnd(text, open);
    if (headEnd === null) break;
    const b = body(text, headEnd + 1, "</message>");
    if (!b) break;
    const attrs = text.slice(open + 9, headEnd);
    const from = unescape(attr(attrs, "from") ?? "");
    let named: [string, string] | null = null;
    if (from.endsWith(")")) {
      const inner = from.slice(0, -1);
      const cut = inner.lastIndexOf(" (");
      if (cut >= 0) {
        const id = inner.slice(cut + 2);
        if (id !== "" && !/[() ]/.test(id)) named = [inner.slice(0, cut), id];
      }
    }
    messages.push({
      user: named ? named[1] : from,
      name: named ? named[0] : null,
      ts: attr(attrs, "ts") ?? "",
      text: b[0],
      thread: attr(attrs, "thread"),
      // A person in a Feishu chat is told as one in Slack is (docs/feishu.md).
      slack: attr(attrs, "via") === "slack" || attr(attrs, "via") === "feishu",
      station: ["ember", "stillfail"].includes(attr(attrs, "via") ?? ""),
      agent: bare(attrs, "bot"),
    });
    rest += text.slice(at, open);
    at = b[1];
  }
  rest += text.slice(at);
  const second = rest;
  rest = "";
  at = 0;
  for (;;) {
    const open = second.indexOf('<slack user="', at);
    if (open < 0) break;
    const headEnd = tagEnd(second, open);
    if (headEnd === null) break;
    const b = body(second, headEnd + 1, "</slack>");
    if (!b) break;
    const attrs = second.slice(open + 7, headEnd);
    messages.push({ user: attr(attrs, "user") ?? "", name: null, ts: attr(attrs, "ts") ?? "", text: b[0], thread: null, slack: true, station: false, agent: bare(attrs, "bot") });
    rest += second.slice(at, open);
    at = b[1];
  }
  rest += second.slice(at);
  const note = rest
    .split("\n")
    .filter((l) => !(l.startsWith("(Thread ") && l.endsWith(")") && l.includes(" had messages before you were brought in;")))
    .join("\n");
  return [messages, note.trim()];
}

/// Work the agent started on its own that told it how it ended (Claude Code's `<task-notification>`): a background command
/// or a sub-agent, its name, how it ended and, a sub-agent's, what it answered.
export type Task = { agent: boolean; name: string; status: string; code: number | null; result: string | null };

function inner(block: string, tag: string, last = false): string | null {
  const open = block.indexOf(`<${tag}>`);
  if (open < 0) return null;
  const from = open + tag.length + 2;
  const close = last ? block.lastIndexOf(`</${tag}>`) : block.indexOf(`</${tag}>`, from);
  return (close < from ? block.slice(from) : block.slice(from, close)).trim();
}

/// Takes the task notifications out of still.fail's words to the agent: what they told, and the words left.
export function parseTasks(note: string): [Task[], string] {
  const tasks: Task[] = [];
  let rest = "";
  let at = 0;
  for (;;) {
    const open = note.indexOf("<task-notification>", at);
    if (open < 0) break;
    const close = note.indexOf("</task-notification>", open);
    const end = close < 0 ? note.length : close + "</task-notification>".length;
    const block = note.slice(open, close < 0 ? note.length : close);
    const summary = inner(block, "summary") ?? "";
    // "Background command "…" completed (exit code 0)", "… failed with exit code 1", "Agent "…" finished".
    const said = /^(Background command|Agent) "([\s\S]*)" (?:completed|failed|finished|was stopped)/.exec(summary);
    const code = /exit code (\d+)\)?$/.exec(summary);
    tasks.push({
      agent: said ? said[1] === "Agent" : inner(block, "result") !== null,
      name: said ? said[2] : summary,
      status: inner(block, "status") ?? "",
      code: code ? Number(code[1]) : null,
      result: inner(block, "result", true) || null,
    });
    rest += note.slice(at, open);
    at = end;
  }
  rest += note.slice(at);
  return [tasks, rest.trim()];
}

function taskText(task: Task): string {
  const what = task.agent ? "agent" : "command";
  const how = task.status === "completed" ? "done" : task.status === "failed" ? (task.code !== null ? "failed_code" : "failed") : task.status === "killed" ? "stopped" : "other";
  return t(`core-logic.history.task.${what}.${how}`, { name: task.name, code: task.code ?? 0, status: task.status });
}

function mentions(text: string, cx: Context): string {
  const bots: [string, string][] = cx.botUserId !== null ? [[cx.botUserId, cx.botName]] : [];
  return present.mentions(text, bots.concat(cx.slackNames ?? []), cx.members);
}

type Step = { call: number; result: number | null };
type Item =
  | { kind: "received"; i: number }
  | { kind: "text"; i: number }
  | { kind: "post"; step: number }
  | { kind: "mark"; mark: string; seconds: number | null; what: string | null }
  | { kind: "group"; rows: Row[] };
/// A group's thinking and calls, in the order they came: a thought by its timeline index, a call by its step.
type Row = { thought: number } | { step: number };

export function presentHistory(live: J, cx: Context): J {
  const timeline: J[] = Array.isArray(live?.timeline) ? live.timeline : [];
  const base = typeof live?.first === "number" ? live.first : 0;
  const s = (e: J, k: string): string => (typeof e?.[k] === "string" ? e[k] : "");
  const flag = (e: J, k: string): boolean => e?.[k] === true;

  const items: [Item, number, number][] = [];
  const { steps, stepAt } = pair(timeline);
  const known: Known = { stations: cx.stations, tasks: tasksOf(timeline) };
  let grouping = false;
  const cover = (i: number) => {
    const last = items[items.length - 1];
    if (last) last[2] = i;
  };
  timeline.forEach((e, i) => {
    const kind = s(e, "kind");
    if (kind === "tool_result") {
      cover(i);
    } else if (kind === "tool_call") {
      const step = stepAt.get(i)!;
      const a = args(s(e, "text"));
      const arg = (k: string) => (typeof a?.[k] === "string" ? (a[k] as string) : null);
      const sub = flag(e, "subagent");
      const name = toolName(s(e, "tool"));
      if (name === "chat_post" && arg("text") !== null && !sub) {
        items.push([{ kind: "post", step }, i, i]);
        grouping = false;
      } else if (name === "chat_state" && arg("kind") !== null && !sub) {
        const sec = a?.seconds;
        const what = arg("for")?.trim() || null;
        items.push([{ kind: "mark", mark: arg("kind") ?? "", seconds: typeof sec === "number" ? Math.trunc(Math.max(sec, 0)) : null, what }, i, i]);
        grouping = false;
      } else {
        if (!grouping) {
          items.push([{ kind: "group", rows: [] }, i, i]);
          grouping = true;
        }
        const last = items[items.length - 1];
        if (last[0].kind === "group") {
          last[0].rows.push({ step });
          last[2] = i;
        }
      }
    } else if (kind === "thinking") {
      if (!grouping) {
        items.push([{ kind: "group", rows: [] }, i, i]);
        grouping = true;
      }
      const last = items[items.length - 1];
      if (last[0].kind === "group") {
        last[0].rows.push({ thought: i });
        last[2] = i;
      }
    } else {
      grouping = false;
      items.push([kind === "user" ? { kind: "received", i } : { kind: "text", i }, i, i]);
    }
  });

  const failedOf = (step: Step) => step.result !== null && timeline[step.result]?.ok === false;
  const place = (address: string | null, message: string | null = null) => (address === null ? null : format.place(cx.threads, address, cx.offsetMin, cx.workspaces, message));
  const shown = items.map(([item, first, last]) => {
    let v: J;
    switch (item.kind) {
      case "received": {
        const [messages, said] = parsePrompt(s(timeline[item.i], "text"));
        const [tasks, note] = parseTasks(said);
        // The station's own notices: an event of a job's or of a chat it opened, in a line as background work's end is.
        const notices = messages.map((m) => (m.station ? readNotice(m.text) : null));
        const events = notices.flatMap((n) => (n?.kind === "event" ? [n] : []));
        v = {
          kind: "received",
          note: note !== "" ? note : null,
          tasks: tasks.map((task) => answered({
            text: taskText(task),
            agent: task.agent,
            failed: task.status === "failed" || task.status === "killed",
            result: task.result,
            md: task.result !== null ? markdown(task.result, cx.md) : null,
          })).concat(events.map((n) => answered({
            text: n.line,
            agent: n.chat,
            failed: n.failed,
            result: n.more,
            // A job's output is a block of code, all of it.
            md: n.more === null ? null : n.output ? (n.more === "" ? [] : [["pre", { code: [0, n.more.length] }]]) : markdown(n.more, cx.md),
          }))),
          messages: messages.flatMap((m, k): J[] => {
            // A job's own words, as it wrote them (drawn in a monospaced font); still.fail's of any other kind, as they are.
            const notice = notices[k];
            if (notice?.kind === "event") return [];
            if (notice?.kind === "said") return [{ key: `${m.ts}.${k}`, from: { name: notice.name, slackUser: null, bound: false }, text: notice.said, place: null, notice: "job" }];
            if (m.station) return [{ key: `${m.ts}.${k}`, from: { name: brand.name(), slackUser: null, bound: false }, text: m.text, place: null, notice: "stillfail" }];
            let from: J;
            if (m.slack) {
              const bound = cx.slackUsers.includes(m.user);
              const name = bound ? t("core-logic.history.you") : m.name !== null && m.name !== "" ? m.name : m.user;
              from = { name, slackUser: m.user, bound };
            } else {
              const name = present.memberName(cx.members, m.user) ?? (m.name !== null && m.name !== "" ? m.name : m.user);
              from = { name, slackUser: null, bound: false };
            }
            // A person's words are drawn as they wrote them; an agent's are Markdown, as a chat's page reads them.
            const said = mentions(m.text, cx);
            return [{ key: m.ts, from, text: said, place: place(m.thread, m.slack ? m.ts : null), ...(m.agent ? { md: markdown(said, cx.md) } : {}) }];
          }),
        };
        break;
      }
      case "text": {
        const said = s(timeline[item.i], "text");
        const md = markdown(said, cx.md);
        v = { kind: "text", text: said, md, line: lineOf(md, said), subagent: flag(timeline[item.i], "subagent") };
        break;
      }
      case "post": {
        const a = args(s(timeline[steps[item.step].call], "text")) ?? {};
        const text = (k: string): string | null => (typeof a[k] === "string" ? a[k] : null);
        const kind = text("kind");
        const said = mentions(text("text") ?? "", cx);
        v = { kind: "post", text: said, md: markdown(said, cx.md), place: place(text("to")), block: kind === "block" || kind === "need_help" || kind === "need_decision", failed: failedOf(steps[item.step]) };
        const ends = endsOf(kind);
        if (ends !== null && ends !== "waiting") v.ends = ends;
        break;
      }
      case "mark":
        if (item.mark === "waiting") {
          const at = (i: number): number | null => {
            const v = timeline[i]?.at;
            const ms = typeof v === "string" ? epochMs(v) : null;
            return ms === null ? null : Math.trunc(ms);
          };
          const since = at(first);
          let until: number | null = null;
          if (since !== null) {
            // The wait is over at what moves the agent on: a prompt bringing it back, or a call of its own after the
            // mark (it went on working instead; a later state stands in its place). Words it posts as its turn ends
            // are part of the ending, not more work.
            for (let j = first + 1; j < timeline.length; j++) {
              const e = timeline[j];
              if (flag(e, "subagent")) continue;
              const kind = s(e, "kind");
              const posting = kind === "tool_call" && toolName(s(e, "tool")) === "chat_post" && typeof args(s(e, "text"))?.kind !== "string";
              if (kind === "user" || (kind === "tool_call" && !posting)) {
                until = at(j) ?? since;
                break;
              }
            }
          }
          const waited = since !== null && until !== null ? (() => {
            const w = Math.trunc(Math.max(until - since, 0) / 1000);
            return item.seconds === null ? w : Math.min(w, item.seconds);
          })() : null;
          const how =
            waited !== null && item.seconds !== null
              ? t("core-logic.history.waited_most", { waited: span(waited), most: span(item.seconds) })
              : waited !== null
                ? t("core-logic.history.waited", { waited: span(waited) })
                : item.seconds !== null
                  ? t("core-logic.history.waiting_most", { most: span(item.seconds) })
                  : t("core-logic.history.waiting");
          // What it waited for (chat_state's `for`) leads, as the activity line says it.
          const text = item.what !== null ? `${item.what} · ${how}` : how;
          v = { kind: "mark", text, wait: since !== null ? { since, until, seconds: item.seconds, what: item.what } : null, ends: "waiting" };
        } else {
          const m = item.mark;
          v = {
            kind: "mark",
            text:
              m === "final" || m === "all_done"
                ? t("core-logic.history.mark.final")
                : m === "need_human"
                  ? t("core-logic.history.mark.human")
                  : m === "block" || m === "need_help"
                    ? t("core-logic.history.mark.block")
                    : m === "need_decision"
                      ? t("core-logic.history.mark.decision")
                      : t("core-logic.history.mark.other", { mark: m }),
          };
          const ends = endsOf(m);
          if (ends !== null) v.ends = ends;
        }
        break;
      case "group":
        v = group(timeline, steps, item.rows, base, known, cx.md);
        break;
    }
    const kind = v.kind ?? null;
    delete v.kind;
    const out: J = { key: `e${base + first}`, entries: [base + first, base + last], body: { kind, content: v } };
    // Its own work (its steps and thoughts, and the words it says to itself): what 只看收发 leaves out.
    if (kind === "group" || kind === "text") out.work = true;
    return out;
  });

  // Turns: each prompt that woke the agent (not one of a sub-agent's) begins one, on its item, saying when and what the
  // turn did up to the next: how many calls, how many messages it sent (or that it sent none). Items before the first
  // loaded one belong to a turn that began on an earlier page.
  type Turn = { at: number | null; steps: number; posts: number; item: J };
  let turn: Turn | null = null;
  const turns: Turn[] = [];
  items.forEach(([item, first], n) => {
    if (item.kind === "received" && !flag(timeline[item.i], "subagent")) {
      const at = typeof timeline[first]?.at === "string" ? epochMs(timeline[first].at) : null;
      turn = { at: at === null ? null : Math.trunc(at), steps: 0, posts: 0, item: shown[n] };
      turns.push(turn);
    } else if (turn !== null) {
      if (item.kind === "group") turn.steps += item.rows.filter((r) => "step" in r).length;
      else if (item.kind === "post") turn.posts++;
    }
  });
  for (const { at, steps: n, posts, item } of turns) {
    const did = [
      ...(n > 0 ? [t("core-logic.history.turn.steps", { n })] : []),
      posts > 0 ? t("core-logic.history.turn.posts", { n: posts }) : t("core-logic.history.turn.silent"),
    ].join(" · ");
    item.turn = {
      ...(at !== null ? { at, time: cx.now !== undefined ? format.dayClock(at, cx.now, cx.offsetMin) : format.clock(at, cx.offsetMin) } : {}),
      text: did,
    };
  }

  const pushedNow = pushed(live, cx.runtime);
  const liveSteps = pushedNow.liveSteps.map(({ id, text }) => ({ id, text }));
  const phase = pushedNow.phase;
  const { usage, usageLine } = usageOf(live?.usage);
  const loaded = flag(live, "loaded");
  let edge: string;
  let empty: boolean;
  if (!loaded && shown.length === 0) [edge, empty] = [t("core-logic.history.edge.loading"), true];
  else if (shown.length === 0 && liveSteps.length === 0 && phase === null && base === 0) {
    const why = flag(live, "offline") ? "core-logic.history.edge.offline" : cx.started ? "core-logic.history.edge.missing" : "core-logic.history.edge.not_started";
    [edge, empty] = [t(why), true];
  } else if (base > 0) [edge, empty] = [t("core-logic.history.edge.earlier"), false];
  else [edge, empty] = [t("core-logic.history.edge.start"), false];
  return { items: shown, live: liveSteps, phase, usage, usageLine, edge, empty, loaded, more: base > 0 };
}

/// What a session's calls used (views/brief.ts `usageNow`), as its history shows it: label and value rows, and in a
/// line; and on their own, what its card shows of it (views/brief.ts): the context it carries (how full its window is,
/// when known) and the cost. Nothing before the station has counted any.
export function usageOf(u: J): { usage: J[] | null; usageLine: string | null; context: string | null; contextPercent: number | null; cost: string | null } {
  const isUsage = u !== null && typeof u === "object" && !Array.isArray(u);
  const n = (k: string): number => (isUsage && typeof u[k] === "number" ? u[k] : 0);
  // The context and the cost come from stations since; an older one's usage has neither.
  const has = (k: string): boolean => isUsage && typeof u[k] === "number";
  const contextPercent = has("contextTokens") && n("modelCalls") > 0 && n("contextWindow") > 0 ? format.round((n("contextTokens") / n("contextWindow")) * 100) : null;
  const context = has("contextTokens") && n("modelCalls") > 0
    ? contextPercent !== null
      ? t("core-logic.history.usage.context.of", { n: format.compactNumber(n("contextTokens")), window: format.compactNumber(n("contextWindow")), percent: contextPercent })
      : format.compactNumber(n("contextTokens"))
    : null;
  const cost = has("cost") && n("modelCalls") > 0
    ? n("unpricedCalls") >= n("modelCalls")
      ? t("core-logic.history.usage.cost.unpriced")
      : `${n("unpricedCalls") > 0 ? "≥" : ""}${money(n("cost"))}`
    : null;
  const usage = isUsage
    ? (() => {
        const input = n("inputTokens");
        const cached = n("cachedTokens");
        const rate = input > 0 ? `${format.round((cached / input) * 100)}%` : t("core-logic.history.usage.unreported");
        return [
          { label: t("core-logic.history.usage.calls"), value: t("core-logic.history.usage.calls.value", { n: n("modelCalls") }) },
          { label: t("core-logic.history.usage.input"), value: format.compactNumber(input) },
          { label: t("core-logic.history.usage.cached"), value: format.compactNumber(cached) },
          { label: t("core-logic.history.usage.output"), value: format.compactNumber(n("outputTokens")) },
          { label: t("core-logic.history.usage.hit_rate"), value: rate },
          ...(context !== null ? [{ label: t("core-logic.history.usage.context"), value: context }] : []),
          ...(cost !== null ? [{ label: t("core-logic.history.usage.cost"), value: cost }] : []),
        ];
      })()
    : null;
  const usageLine = isUsage
    ? (() => {
        const input = n("inputTokens");
        const cached = n("cachedTokens");
        const rate = input > 0 ? t("core-logic.history.usage.line.rate", { rate: format.round((cached / input) * 100) }) : "";
        const line = t("core-logic.history.usage.line", { n: n("modelCalls"), input: format.compactNumber(input), rate, output: format.compactNumber(n("outputTokens")) });
        const more = [
          ...(has("contextTokens") && n("modelCalls") > 0 ? [t("core-logic.history.usage.line.context", { n: format.compactNumber(n("contextTokens")) })] : []),
          ...(cost !== null ? [t("core-logic.history.usage.line.cost", { cost })] : []),
        ];
        return [line, ...more].join(" · ");
      })()
    : null;
  return { usage, usageLine, context, contextPercent, cost };
}

/// The state a post or a mark ended its turn in, as the clients colour it: done, waiting on a person, or waiting on work
/// it started; null for one that ended nothing (a progress post) or words the station no longer uses.
function endsOf(kind: string | null): "done" | "human" | "waiting" | null {
  if (kind === "all_done" || kind === "final") return "done";
  if (kind === "need_human" || kind === "block" || kind === "need_help" || kind === "need_decision") return "human";
  if (kind === "waiting") return "waiting";
  return null;
}

/// Work the agent started, as the history shows it: with the line its answer shows closed (lineOf its Markdown).
function answered(task: J): J {
  return { ...task, line: typeof task.result === "string" && Array.isArray(task.md) ? lineOf(task.md, task.result) : null };
}

/// A group of the history; `base`: the transcript entry its timeline starts at (what a step's or thought's `entries` count
/// from: what `history.detail` reads whole, of one in brief).
function group(timeline: J[], steps: Step[], rows: Row[], base: number, known: Known, store?: MdStore): J {
  const members = rows.flatMap((r) => ("step" in r ? [r.step] : []));
  const thinking = rows.flatMap((r) => ("thought" in r ? [r.thought] : []));
  const text = (i: number): string => (typeof timeline[i]?.text === "string" ? timeline[i].text : "");
  const tool = (i: number): string => (typeof timeline[i]?.tool === "string" ? timeline[i].tool : "");
  const failedOf = (st: Step) => st.result !== null && timeline[st.result]?.ok === false;
  const counts: [string, string[], number][] = [];
  for (const m of members) {
    const call = steps[m].call;
    const kind = kindOf(tool(call));
    const file = kind === "read" || kind === "edit" ? fileOf(text(call)) : null;
    let at = counts.findIndex(([k]) => k === kind);
    if (at < 0) {
      counts.push([kind, [], 0]);
      at = counts.length - 1;
    }
    if (file !== null) {
      if (!counts[at][1].includes(file)) counts[at][1].push(file);
    } else counts[at][2]++;
  }
  let title = counts.map(([k, files, n]) => did(k, files.length === 0 ? n : files.length)).join(t("core-logic.history.did.sep"));
  const chars = Array.from(title);
  if (chars.length > 0) title = chars[0].toUpperCase() + chars.slice(1).join("");
  const failed = members.filter((m) => failedOf(steps[m])).length;
  const pending = members.filter((m) => steps[m].result === null).length;
  // a thought's words, read as Markdown, and their first line without its marks
  const thought = (i: number) => {
    const md = markdown(text(i), store);
    return { md, first: lineOf(md, text(i)) };
  };
  let summary: string;
  const lastMember = members[members.length - 1];
  if (lastMember === undefined) {
    summary = t("core-logic.history.thinking", { text: thinking.length > 0 ? Array.from(thought(thinking[0]).first).slice(0, 80).join("") : "" });
  } else {
    const call = steps[lastMember].call;
    // Said as the chat's activity says the call while it runs (activity.ts doing).
    const now = doing(tool(call), text(call), known);
    summary = members.length === 1 ? now : t("core-logic.history.steps", { doing: now, n: members.length });
  }
  const step = (m: number) => {
    const st = steps[m];
    const call = timeline[st.call];
    const result = st.result !== null ? timeline[st.result] : null;
    const isFailed = failedOf(st);
    const b = result && typeof result.at === "string" ? epochMs(result.at) : null;
    const a = typeof call?.at === "string" ? epochMs(call.at) : null;
    const took = b !== null && a !== null && b - a >= 0 ? b - a : null;
    const meta = result === null ? t("core-logic.history.step.running") : isFailed ? t("core-logic.history.step.failed") : took !== null ? format.duration(took) : "";
    return {
      said: describe(text(st.call)) ?? told(tool(st.call), text(st.call), known),
      name: toolName(tool(st.call)),
      hint: hint(text(st.call)),
      meta,
      failed: isFailed,
      call: text(st.call),
      result: result === null ? null : (result.text ?? ""),
      entries: st.result !== null ? [base + st.call, base + st.result] : [base + st.call],
      brief: call?.brief === true || result?.brief === true,
    };
  };
  return {
    kind: "group",
    summary,
    title,
    failures: failed,
    pending,
    rows: rows.map((r) => ("thought" in r
      ? { kind: "thought", content: { text: text(r.thought), ...thought(r.thought), entries: [base + r.thought], brief: timeline[r.thought]?.brief === true } }
      : { kind: "step", content: step(r.step) })),
  };
}

/// Seconds in short, as the chat's activity says them: 45s, 3m 20s, 10m, 1h 5m.
function span(s: number): string {
  if (s < 60) return `${s}s`;
  if (s < 3600) return s % 60 === 0 ? `${s / 60}m` : `${Math.trunc(s / 60)}m ${s % 60}s`;
  const h = Math.trunc(s / 3600);
  const m = Math.trunc((s % 3600) / 60);
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

/// Each call with its result: a result by its call's id wherever that call stands (Claude Code can write a quick call's
/// result before the call), or (one without) the latest call before it with none yet.
function pair(timeline: J[]): { steps: Step[]; stepAt: Map<number, number> } {
  const steps: Step[] = [];
  const stepAt = new Map<number, number>();
  const byCall = new Map<string, number>();
  timeline.forEach((e, i) => {
    if (e?.kind !== "tool_call") return;
    const step = steps.length;
    steps.push({ call: i, result: null });
    stepAt.set(i, step);
    if (typeof e.callId === "string") byCall.set(e.callId, step);
  });
  let lastStep: number | null = null;
  timeline.forEach((e, i) => {
    if (e?.kind === "tool_call") lastStep = stepAt.get(i)!;
    else if (e?.kind === "tool_result") {
      const step = typeof e.callId === "string" ? byCall.get(e.callId) : lastStep !== null && steps[lastStep].result === null ? lastStep : undefined;
      if (step !== undefined) steps[step].result = i;
    }
  });
  return { steps, stepAt };
}

/// What the station pushes of the turn beyond its transcript, as the history shows it after its items: the steps in
/// flight (thinking, writing) and where the turn stands with the model.
function pushed(live: J, runtime: string): { liveSteps: { id: string; step: string; text: string }[]; phase: { phase: J; text: string; since: J } | null } {
  const s = (e: J, k: string): string => (typeof e?.[k] === "string" ? e[k] : "");
  const flag = (e: J, k: string): boolean => e?.[k] === true;
  const liveSteps = (Array.isArray(live?.steps) ? live.steps : [])
    .filter((st: J) => !flag(st, "subagent") && s(st, "step") !== "tool")
    .map((st: J) => ({ id: s(st, "id"), step: s(st, "step"), text: s(st, "step") === "text" ? t("core-logic.history.live.writing") : t("core-logic.history.live.thinking") }));
  const p = live?.phase;
  const phase =
    p !== null && typeof p === "object" && !Array.isArray(p)
      ? (() => {
          const name = typeof p.phase === "string" ? p.phase : "";
          const text =
            name === "starting"
              ? t("core-logic.history.phase.starting", { runtime: format.runtimeLabel(runtime) })
              : name === "requesting"
                ? t("core-logic.history.phase.requesting")
                : name === "working"
                  ? t("core-logic.history.phase.working")
                  : t("core-logic.activity.thinking");
          return { phase: p.phase ?? null, text, since: p.since ?? null };
        })()
      : null;
  return { liveSteps, phase };
}

/**
 * The chat's activity: the execution history's latest, in one line. The call it shows running (this turn's, said as
 * its row says it), else what is in flight (thinking, writing, a reply being written), else where the turn stands.
 * `stations`: the workspace's stations' names by id, for a call that works on one (station_task).
 */
export function activity(live: J, stations?: ReadonlyMap<string, string>): J {
  const timeline: J[] = Array.isArray(live?.timeline) ? live.timeline : [];
  const s = (e: J, k: string): string => (typeof e?.[k] === "string" ? e[k] : "");
  let turn = -1;
  timeline.forEach((e, i) => {
    if (s(e, "kind") === "user") turn = i;
  });
  let call: [string, string, boolean] | null = null;
  let replying = false;
  const known: Known = { stations, tasks: tasksOf(timeline) };
  for (const st of pair(timeline).steps) {
    const e = timeline[st.call];
    if (st.call < turn || st.result !== null || e?.subagent === true) continue;
    const name = toolName(s(e, "tool"));
    if (name === "chat_post") replying = true;
    else if (name !== "chat_state") {
      const important = importantCall(s(e, "tool"), s(e, "text"));
      // Of simultaneous steps, keep the most consequential; among equals, show the latest.
      if (call === null || important || !call[2]) call = [s(e, "callId") || `call:${st.call}`, doing(s(e, "tool"), s(e, "text"), known), important];
    }
  }
  const { liveSteps, phase } = pushed(live, "");
  // A reply being written comes as a step before its call is in the transcript.
  const steps: J[] = Array.isArray(live?.steps) ? live.steps : [];
  if (steps.some((st) => st?.subagent !== true && st?.ended !== true && s(st, "step") === "tool" && toolName(s(st, "tool")) === "chat_post")) replying = true;
  const rate = Number.isInteger(live?.rate) && live.rate > 0 ? (live.rate as number) : 0;
  const said = (key: string, word: string) => ({ key, text: rate > 0 ? `${t(word)} · ≈ ${rate} token/s` : t(word) });
  if (call && (!replying || call[2])) return { now: { key: call[0], text: call[1], mono: true, ...(call[2] ? { important: true } : {}) } };
  if (replying) return { now: { ...said("reply", "core-logic.activity.replying"), important: true } };
  const flight = liveSteps.at(-1);
  if (flight) return { now: flight.step === "text" ? said("write", "core-logic.activity.writing") : said("think", "core-logic.activity.thinking") };
  const at = typeof phase?.phase === "string" ? phase.phase : "";
  if (at === "starting") return { now: said("starting", "core-logic.activity.starting") };
  if (at === "requesting") return { now: said("requesting", "core-logic.activity.requesting") };
  if (at === "thinking") return { now: said("think", "core-logic.activity.thinking") };
  if (at === "responding") return { now: said("write", "core-logic.activity.writing") };
  return { now: said("busy", "core-logic.activity.busy") };
}
