// References to other chats in what is written (ChatRef.tsx): in the composer a short mark, `@[its title]`, drawn as a
// chip; sent, a link, `[its title](its page)`, which the agent reads the chat by and a message draws as the same chip.
// The core makes the mark of a chat picked and keeps its link until it is sent (`chat.ref`, client/core/src/refs.rs).

/** A reference as the composer holds it. */
export const REF_MARK = /@\[([^\]\n]{1,120})\]/g;
/** A reference as sent: a link to a chat's page. */
export const REF_LINK = /\[([^\]\n]{1,120})\]\((\S*?\/chats\/[^\s)]+)\)/g;

/** Text split into its plain runs and the parts `pattern` finds (with its groups). */
export function splitBy(text: string, pattern: RegExp): (string | RegExpExecArray)[] {
  const parts: (string | RegExpExecArray)[] = [];
  let at = 0;
  for (const m of text.matchAll(new RegExp(pattern.source, "g"))) {
    if (m.index > at) parts.push(text.slice(at, m.index));
    parts.push(m as RegExpExecArray);
    at = m.index + m[0].length;
  }
  if (at < text.length) parts.push(text.slice(at));
  return parts;
}

/** A link to a chat's page (…/chats/<key>, or ember cloud's /o/<workspace>/<station>/<key>). */
export function isChatLink(href: string | undefined): boolean {
  return !!href && (/\/chats\/[^/?#\s]+\/?(?:[?#]|$)/.test(href) || /^https?:\/\/[^/]+\/o\/[^/]+\/[^/]+\/[^/?#]+\/?(?:#|$)/.test(href));
}
