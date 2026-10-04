// What a chat's agents said in Slack and heard from it: what they sent there (chat_post to a Slack thread, slack_api
// chat.postMessage) and the Slack messages they were given. Read from their transcripts as the sync brings them and
// kept, as Markdown, in the account's database (`slack_said`, db/account.ts): a chat shows these among its messages, at
// the time they were said, without them being entries of the chat (shapes: ChatSentElsewhere), and without its
// transcripts being read again to find them.
import { epochMs, toolName } from "./activity.ts";
import { args, parsePrompt } from "./history.ts";
import * as format from "./format.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// Slack's mrkdwn as Markdown, outside code: links (`<url|label>`), *bold*, ~struck~, • lists, and the escaped
/// `&lt; &gt; &amp;`.
export function markdownOf(mrkdwn: string): string {
  return mrkdwn
    .split(/(```[\s\S]*?```|`[^`\n]*`)/)
    .map((part, i) => {
      if (i % 2 === 1) return part.replaceAll("&lt;", "<").replaceAll("&gt;", ">").replaceAll("&amp;", "&");
      return part
        .replace(/<((?:https?|mailto):[^|>\s]+)\|([^>]+)>/g, "[$2]($1)")
        .replace(/<((?:https?|mailto):[^|>\s]+)>/g, "<$1>")
        .replace(/^([ \t]*)• /gm, "$1- ")
        .replace(/<#[A-Z0-9]+\|([^>]+)>/g, "#$1")
        .replace(/(^|[^\w*])\*(?! )([^*\n]+?)\*(?![\w*])/gm, "$1**$2**")
        .replace(/(^|[^\w~])~(?! )([^~\n]+?)~(?![\w~])/gm, "$1~~$2~~")
        .replaceAll("&lt;", "\\<").replaceAll("&gt;", ">").replaceAll("&amp;", "&");
    })
    .join("");
}

/// What a tool call sends to Slack, if anything: where to and its words.
export function sending(tool: string, call: string): { to: string; text: string } | null {
  const a = args(call);
  if (a === null) return null;
  const name = toolName(tool);
  if (name === "chat_post") {
    const to = typeof a.to === "string" ? a.to : null;
    const text = typeof a.text === "string" ? a.text : null;
    const split = to !== null ? format.splitThread(to) : null;
    if (to === null || text === null || text.trim() === "" || split === null) return null;
    if (split[0] === "EMBER" || split[0] === "STILLFAIL") return null;
    return { to, text };
  }
  if (name === "slack_api" && (a.method === "chat.postMessage" || a.method === "chat.scheduleMessage")) {
    const p = a.params;
    const channel = typeof p?.channel === "string" ? p.channel : null;
    const text = typeof p?.text === "string" ? p.text : null;
    if (channel === null || text === null || text.trim() === "") return null;
    const thread = typeof p.thread_ts === "string" ? p.thread_ts : null;
    const to = thread !== null ? `${channel}/${thread}` : channel;
    return { to, text };
  }
  return null;
}

/// How a call's result went: failed (the tool's or Slack's `ok: false`), and the ts Slack gave a new message.
export function outcome(entry: J): { failed: boolean; ts: string | null } {
  if (entry?.ok === false) return { failed: true, ts: null };
  const text = typeof entry?.text === "string" ? entry.text : "";
  let v: J = null;
  try {
    v = JSON.parse(text);
  } catch {
    // Not Slack's answer (chat_post's own words): it went.
  }
  if (v === null || typeof v !== "object") return { failed: false, ts: null };
  return { failed: v.ok === false, ts: typeof v.ts === "string" ? v.ts : null };
}

/// One thing said in Slack, as kept: its transcript item (`k`: which of the item's messages), `out` when the agent sent
/// it (its call's id) or else a person's it was given (`user`, `who`: their Slack id and name), when, where (a Slack
/// thread's address, or a channel before a message's ts is known), its words as Markdown, and whether it failed.
export type Said = {
  i: number; k: number; out: boolean; call: string | null; user: string | null; who: string | null; at: number; to: string;
  text: string; failed: boolean;
};

/// What a transcript item says of Slack: what the agent sends there or was given from there (`said`), or the result of
/// a call (`result`: its call's id, else none, then it is the item just before's).
export function readItem(i: number, e: J): { said: Said[] } | { result: { call: string | null; failed: boolean; ts: string | null } } | null {
  if (e?.subagent === true) return null;
  const at = typeof e?.at === "string" ? (epochMs(e.at) ?? 0) : 0;
  if (e?.kind === "tool_call") {
    const s = sending(typeof e.tool === "string" ? e.tool : "", typeof e.text === "string" ? e.text : "");
    if (s === null) return null;
    return { said: [{ i, k: 0, out: true, call: typeof e.callId === "string" ? e.callId : null, user: null, who: null, at, to: s.to, text: markdownOf(s.text), failed: false }] };
  }
  if (e?.kind === "tool_result") return { result: { call: typeof e.callId === "string" ? e.callId : null, ...outcome(e) } };
  if (e?.kind === "user" && typeof e.text === "string") {
    const said = parsePrompt(e.text)[0].flatMap((m, k): Said[] => {
      if (!m.slack || m.text.trim() === "") return [];
      // When it was said in Slack (its ts), else when the agent was given it.
      const ts = Number(m.ts);
      const to = m.thread ?? "";
      return [{ i, k, out: false, call: null, user: m.user || null, who: m.name, at: Number.isFinite(ts) && ts > 0 ? Math.trunc(ts * 1000) : at, to, text: markdownOf(m.text), failed: false }];
    });
    return said.length > 0 ? { said } : null;
  }
  return null;
}
