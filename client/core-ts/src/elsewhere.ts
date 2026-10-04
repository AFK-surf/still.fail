// What a chat's agents sent to Slack (chat_post to a Slack thread, slack_api chat.postMessage), read from their
// transcripts as the device holds them: a chat shows these among its messages, at the time they were sent, without
// them being entries of the chat (shapes: ChatSentElsewhere).
import { epochMs, toolName } from "./activity.ts";
import { args } from "./history.ts";
import * as format from "./format.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// One thing sent: where to (a Slack thread's address, or a channel with no thread yet), when, its words, how it went.
export type Sent = {
  /// The transcript item of its call.
  i: number;
  at: number;
  text: string;
  /// `C0OPS/1727.0001`, or `C0OPS` before its message's ts is known.
  to: string;
  failed: boolean;
};

/// The transcript read so far: the items `min ..= max` held when it was, what was sent in them, and the calls still
/// waiting for their result (by call id, else the last one).
type Read = { min: number; max: number; sent: Sent[]; open: Map<string, number>; last: number | null };

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
function sending(tool: string, call: string): { to: string; text: string } | null {
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
function outcome(entry: J): { failed: boolean; ts: string | null } {
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

/// Reads the transcript items `items` into `read`.
function readInto(read: Read, items: Map<number, J>): void {
  for (const [i, e] of items) {
    if (e?.subagent === true) continue;
    if (e?.kind === "tool_call") {
      read.last = null;
      const s = sending(typeof e.tool === "string" ? e.tool : "", typeof e.text === "string" ? e.text : "");
      if (s === null) continue;
      const at = typeof e.at === "string" ? epochMs(e.at) : null;
      read.sent.push({ i, at: at ?? 0, text: s.text, to: s.to, failed: false });
      const index = read.sent.length - 1;
      if (typeof e.callId === "string") read.open.set(e.callId, index);
      read.last = index;
    } else if (e?.kind === "tool_result") {
      const index = typeof e.callId === "string" ? read.open.get(e.callId) : read.last ?? undefined;
      if (index === undefined) continue;
      if (typeof e.callId === "string") read.open.delete(e.callId);
      read.last = null;
      const sent = read.sent[index]!;
      const { failed, ts } = outcome(e);
      sent.failed = failed;
      // A message started a thread of its own: it is there.
      if (ts !== null && !sent.to.includes("/")) sent.to = `${sent.to}/${ts}`;
    }
  }
}

type Span = { min: number; max: number } | null;
type Range = (from: number, to: number) => Map<number, J>;

/// What sessions sent to Slack, by session, read again only where their transcripts grew.
export class Elsewhere {
  readonly #read = new Map<string, Read>();

  /// What session `key` (at `station`) sent, from the transcript held (`span`, read by `range`), and whether that
  /// changed since it was asked last.
  of(station: string, key: string, span: Span, range: Range): { sent: Sent[]; changed: boolean } {
    const id = `${station} ${key}`;
    const held = this.#read.get(id);
    if (span === null) {
      this.#read.delete(id);
      return { sent: [], changed: held !== undefined && held.sent.length > 0 };
    }
    if (held !== undefined && held.min === span.min && held.max === span.max) return { sent: held.sent, changed: false };
    const before = held === undefined ? "" : JSON.stringify(held.sent);
    let read: Read;
    if (held !== undefined && held.min === span.min && span.max > held.max) {
      read = held;
      readInto(read, range(held.max + 1, span.max));
      read.max = span.max;
    } else {
      read = { min: span.min, max: span.max, sent: [], open: new Map(), last: null };
      readInto(read, range(span.min, span.max));
    }
    read.sent = [...read.sent];
    this.#read.set(id, read);
    return { sent: read.sent, changed: JSON.stringify(read.sent) !== before };
  }
}
