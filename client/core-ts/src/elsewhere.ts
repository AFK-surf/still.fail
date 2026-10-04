// What a chat's agents sent to Slack (chat_post to a Slack thread, slack_api chat.postMessage), read from their
// transcripts as the sync brings them and kept, as Markdown, in the account's database (`sent`, db/account.ts): a chat
// shows these among its messages, at the time they were sent, without them being entries of the chat (shapes:
// ChatSentElsewhere), and without its transcripts being read again to find them.
import { epochMs, toolName } from "./activity.ts";
import { args } from "./history.ts";
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

/// One thing sent, as kept: its transcript item, its call's id, when, where to (a Slack thread's address, or a channel
/// before its message's ts is known), its words as Markdown, and whether it failed.
export type Sent = { i: number; call: string | null; at: number; to: string; text: string; failed: boolean };

/// What a transcript item does to what was sent: a call that sends something (`sent`), or the result of a call (`result`:
/// its call's id, else none, then it is the item just before's).
export function readItem(i: number, e: J): { sent: Sent } | { result: { call: string | null; failed: boolean; ts: string | null } } | null {
  if (e?.subagent === true) return null;
  if (e?.kind === "tool_call") {
    const s = sending(typeof e.tool === "string" ? e.tool : "", typeof e.text === "string" ? e.text : "");
    if (s === null) return null;
    const at = typeof e.at === "string" ? epochMs(e.at) : null;
    return { sent: { i, call: typeof e.callId === "string" ? e.callId : null, at: at ?? 0, to: s.to, text: markdownOf(s.text), failed: false } };
  }
  if (e?.kind === "tool_result") return { result: { call: typeof e.callId === "string" ? e.callId : null, ...outcome(e) } };
  return null;
}
