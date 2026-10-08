// An agent's execution history as the clients show it (history.rs): what actually ran, put together here so every
// client draws the same thing. Messages in and out, state marks and the agent's own words are boundaries; the tool
// calls and thinking between two boundaries fold into one group, named by its latest call (shapes: HistoryView).
import { epochMs, kindOf, toolName } from "./activity.ts";
import * as format from "./format.ts";
import { t } from "./i18n.ts";
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
  runtime: string;
  started: boolean;
  offsetMin: number;
  workspaces: Map<string, format.SlackWorkspace>;
};

function kindKey(kind: string): string {
  return ["read", "search", "edit", "command", "web", "agent", "thread"].includes(kind) ? kind : "other";
}

function did(kind: string, n: number): string {
  return t(`core-logic.history.did.${kindKey(kind)}`, { n });
}

function parseObject(text: string): Record<string, J> | null {
  try {
    const v = JSON.parse(text);
    return v !== null && typeof v === "object" && !Array.isArray(v) ? v : null;
  } catch {
    return null;
  }
}

export function args(text: string): Record<string, J> | null {
  try {
    const v = JSON.parse(text);
    return v !== null && typeof v === "object" && !Array.isArray(v) ? v : null;
  } catch {
    // Not whole: read below.
  }
  // A long call is kept to its first characters, then `… (n more characters)`: read what is there.
  const at = text.lastIndexOf("\n… (");
  if (at < 0) return null;
  const tail = text.slice(at + 4);
  if (!tail.endsWith(" more characters)")) return null;
  return parseObject(close(text.slice(0, at)));
}

/// JSON cut short, closed where it stops: the string it was in ends with an ellipsis, and what was open is closed.
function close(json: string): string {
  const open: string[] = [];
  let quoted = false;
  let escaped = false;
  for (const c of json) {
    if (escaped) escaped = false;
    else if (quoted) {
      if (c === "\\") escaped = true;
      else if (c === '"') quoted = false;
    } else if (c === '"') quoted = true;
    else if (c === "{") open.push("}");
    else if (c === "[") open.push("]");
    else if (c === "}" || c === "]") open.pop();
  }
  let out = json;
  if (quoted) {
    if (escaped) out = out.slice(0, -1);
    out += '…"';
  }
  out = out.trimEnd();
  if (out.endsWith(":")) out += "null";
  else if (out.endsWith(",")) out = out.slice(0, -1);
  return out + open.reverse().join("");
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

/// A message a prompt carried.
export type Sourced = { user: string; name: string | null; ts: string; text: string; thread: string | null; slack: boolean };

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

function body(text: string, openEnd: number, closeTag: string): [string, number] | null {
  const start = text.startsWith("\n", openEnd) ? openEnd + 1 : openEnd;
  const at = text.indexOf(closeTag, start);
  if (at < 0) return null;
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
      slack: attr(attrs, "via") === "slack",
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
    messages.push({ user: attr(attrs, "user") ?? "", name: null, ts: attr(attrs, "ts") ?? "", text: b[0], thread: null, slack: true });
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

function mentions(text: string, cx: Context): string {
  const bots: [string, string][] = cx.botUserId !== null ? [[cx.botUserId, cx.botName]] : [];
  return present.mentions(text, bots, cx.members);
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
  const steps: Step[] = [];
  const byCall = new Map<string, number>();
  let lastStep: number | null = null;
  let grouping = false;
  const cover = (i: number) => {
    const last = items[items.length - 1];
    if (last) last[2] = i;
  };
  timeline.forEach((e, i) => {
    const kind = s(e, "kind");
    if (kind === "tool_result") {
      let step = typeof e.callId === "string" ? byCall.get(e.callId) : undefined;
      if (step === undefined && lastStep !== null && steps[lastStep].result === null) step = lastStep;
      if (step !== undefined) steps[step].result = i;
      cover(i);
    } else if (kind === "tool_call") {
      const step = steps.length;
      steps.push({ call: i, result: null });
      if (typeof e.callId === "string") byCall.set(e.callId, step);
      lastStep = step;
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
  const place = (address: string | null) => (address === null ? null : format.place(cx.threads, address, cx.offsetMin, cx.workspaces));
  const shown = items.map(([item, first, last]) => {
    let v: J;
    switch (item.kind) {
      case "received": {
        const [messages, note] = parsePrompt(s(timeline[item.i], "text"));
        v = {
          kind: "received",
          note: note !== "" ? note : null,
          messages: messages.map((m) => {
            let from: J;
            if (m.slack) {
              const bound = cx.slackUsers.includes(m.user);
              const name = bound ? t("core-logic.history.you") : m.name !== null && m.name !== "" ? m.name : m.user;
              from = { name, slackUser: m.user, bound };
            } else {
              const name = present.memberName(cx.members, m.user) ?? (m.name !== null && m.name !== "" ? m.name : m.user);
              from = { name, slackUser: null, bound: false };
            }
            return { key: m.ts, from, text: mentions(m.text, cx), place: place(m.thread) };
          }),
        };
        break;
      }
      case "text":
        v = { kind: "text", text: s(timeline[item.i], "text"), subagent: flag(timeline[item.i], "subagent") };
        break;
      case "post": {
        const a = args(s(timeline[steps[item.step].call], "text")) ?? {};
        const text = (k: string): string | null => (typeof a[k] === "string" ? a[k] : null);
        const kind = text("kind");
        v = { kind: "post", text: text("text") ?? "", place: place(text("to")), block: kind === "block" || kind === "need_help" || kind === "need_decision", failed: failedOf(steps[item.step]) };
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
            for (let j = first + 1; j < timeline.length; j++) {
              if (s(timeline[j], "kind") === "user" && !flag(timeline[j], "subagent")) {
                until = at(j);
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
          v = { kind: "mark", text, wait: since !== null ? { since, until, seconds: item.seconds, what: item.what } : null };
        } else {
          const m = item.mark;
          v = {
            kind: "mark",
            text:
              m === "final" || m === "all_done"
                ? t("core-logic.history.mark.final")
                : m === "block" || m === "need_help"
                  ? t("core-logic.history.mark.block")
                  : m === "need_decision"
                    ? t("core-logic.history.mark.decision")
                    : t("core-logic.history.mark.other", { mark: m }),
          };
        }
        break;
      case "group":
        v = group(timeline, steps, item.rows);
        break;
    }
    const kind = v.kind ?? null;
    delete v.kind;
    return { key: `e${base + first}`, entries: [base + first, base + last], body: { kind, content: v } };
  });

  const liveSteps = (Array.isArray(live?.steps) ? live.steps : [])
    .filter((st: J) => !flag(st, "subagent") && s(st, "step") !== "tool")
    .map((st: J) => ({ id: s(st, "id"), text: s(st, "step") === "text" ? t("core-logic.history.live.writing") : t("core-logic.history.live.thinking") }));
  const p = live?.phase;
  const phase =
    p !== null && typeof p === "object" && !Array.isArray(p)
      ? (() => {
          const name = typeof p.phase === "string" ? p.phase : "";
          const text =
            name === "starting"
              ? t("core-logic.history.phase.starting", { runtime: format.runtimeLabel(cx.runtime) })
              : name === "requesting"
                ? t("core-logic.history.phase.requesting")
                : name === "working"
                  ? t("core-logic.history.phase.working")
                  : "Thinking";
          return { phase: p.phase ?? null, text, since: p.since ?? null };
        })()
      : null;
  const u = live?.usage;
  const isUsage = u !== null && typeof u === "object" && !Array.isArray(u);
  const n = (k: string): number => (isUsage && typeof u[k] === "number" ? u[k] : 0);
  // The context and the cost come from stations since; an older one's usage has neither.
  const has = (k: string): boolean => isUsage && typeof u[k] === "number";
  const context = has("contextTokens") && n("modelCalls") > 0
    ? n("contextWindow") > 0
      ? t("core-logic.history.usage.context.of", { n: format.compactNumber(n("contextTokens")), window: format.compactNumber(n("contextWindow")), percent: format.round((n("contextTokens") / n("contextWindow")) * 100) })
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

function group(timeline: J[], steps: Step[], rows: Row[]): J {
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
  const firstLine = (s: string) => s.split("\n").find((l) => l.trim() !== "") ?? "";
  let summary: string;
  const lastMember = members[members.length - 1];
  if (lastMember === undefined) {
    summary = t("core-logic.history.thinking", { text: thinking.length > 0 ? Array.from(firstLine(text(thinking[0]))).slice(0, 80).join("") : "" });
  } else {
    const call = steps[lastMember].call;
    const name = tool(call);
    const kind = kindOf(name);
    const doing =
      describe(text(call)) ??
      (() => {
        const verb = kind === "other" ? toolName(name) : t(`core-logic.history.verb.${kindKey(kind)}`);
        return `${verb} ${hint(text(call))}`.trim();
      })();
    summary = members.length === 1 ? doing : t("core-logic.history.steps", { doing, n: members.length });
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
      said: describe(text(st.call)),
      name: toolName(tool(st.call)),
      hint: hint(text(st.call)),
      meta,
      failed: isFailed,
      call: text(st.call),
      result: result === null ? null : (result.text ?? ""),
    };
  };
  return {
    kind: "group",
    summary,
    title,
    failures: failed,
    pending,
    rows: rows.map((r) => ("thought" in r ? { kind: "thought", content: { text: text(r.thought), first: firstLine(text(r.thought)) } } : { kind: "step", content: step(r.step) })),
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
