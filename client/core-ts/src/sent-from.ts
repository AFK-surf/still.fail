// The heading a station writes on what one chat's agent sends another (session_send, chat_create), as the chat's page
// and an agent's history read it.

/// What a message another chat's agent sent (session_send, or the first of a chat it opened with chat_create) is headed
/// with: its chat's title and link, and the message.
export function sentFrom(text: string): [string, string, string] | null {
  const sent = sentHead(text);
  return sent === null ? null : [sent.title, sent.link, sent.rest];
}

/// What sentFrom reads, and whether it heads the first message of a chat that agent opened (`由 … 开的 chat：`) rather
/// than one it wrote to (`来自 …：`).
export function sentHead(text: string): { title: string; link: string; rest: string; opened: boolean } | null {
  const at = text.indexOf("\n\n");
  if (at < 0) return null;
  const head = text.slice(0, at);
  const rest = text.slice(at + 2);
  let named: string | null = null;
  let opened = false;
  if (head.startsWith("来自 ") && head.endsWith("：")) named = head.slice(3, -1);
  else if (head.startsWith("From ") && head.endsWith(":")) named = head.slice(5, -1);
  else if (head.startsWith("由 ") && head.endsWith(" 开的 chat：")) [named, opened] = [head.slice(2, -" 开的 chat：".length), true];
  else if (head.startsWith("Opened by ") && head.endsWith(":")) [named, opened] = [head.slice(10, -1), true];
  if (named === null) return null;
  let title: string;
  let link: string;
  if (named.startsWith("[") && named.endsWith(")")) {
    const md = named.slice(1, -1);
    const cut = md.indexOf("](");
    if (cut < 0) return null;
    title = md.slice(0, cut);
    link = md.slice(cut + 2);
  } else if (named.startsWith("<") && named.endsWith(">")) {
    const inner = named.slice(1, -1);
    const cut = inner.indexOf("|");
    if (cut < 0) return null;
    link = inner.slice(0, cut);
    title = inner.slice(cut + 1);
  } else return null;
  if (title === "" || !link.startsWith("http") || /\s/.test(link)) return null;
  return { title, link, rest, opened };
}
