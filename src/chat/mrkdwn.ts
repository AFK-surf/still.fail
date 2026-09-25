// Markdown → Slack mrkdwn. Covers what agents actually write: code, bold,
// italics, strikethrough, links, headings and bullets.

export function toMrkdwn(markdown: string): string {
  // Split out fenced blocks and inline code; only prose is rewritten.
  const parts = markdown.split(/(```[\s\S]*?```|`[^`\n]+`)/g);
  return parts.map((part, i) => (i % 2 === 1 ? escapeCode(part) : prose(part))).join("");
}

function escapeCode(code: string): string {
  const fenced = /^```[^\n]*\n([\s\S]*?)```$/.exec(code);
  const body = fenced ? `\`\`\`\n${fenced[1]}\`\`\`` : code; // Slack ignores a language tag and would print it
  return escape(body);
}

function escape(text: string): string {
  return text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

function prose(text: string): string {
  const BOLD = "\u0000";
  return escape(text)
    .replace(/\[([^\]\n]+)\]\(([^)\s]+)\)/g, (_, label: string, url: string) => `<${url}|${label}>`)
    .replace(/^#{1,6}\s+(.+)$/gm, `${BOLD}$1${BOLD}`)
    .replace(/\*\*(.+?)\*\*|__(.+?)__/g, (_, a?: string, b?: string) => `${BOLD}${a ?? b}${BOLD}`)
    .replace(/(^|[^*\w])\*(?!\s)([^*\n]+?)\*(?!\w)/g, "$1_$2_")
    .replace(/~~(.+?)~~/g, "~$1~")
    .replace(/^(\s*)[-*]\s+/gm, "$1• ")
    .replaceAll(BOLD, "*");
}

/** Splits text for Slack's message size, preferring paragraph, then line boundaries. */
export function splitForSlack(text: string, limit = 3500): string[] {
  const chunks: string[] = [];
  let rest = text;
  while (rest.length > limit) {
    let cut = rest.lastIndexOf("\n\n", limit);
    if (cut < limit / 2) cut = rest.lastIndexOf("\n", limit);
    if (cut < limit / 2) cut = limit;
    chunks.push(rest.slice(0, cut));
    rest = rest.slice(cut).replace(/^\n+/, "");
  }
  if (rest.length > 0 || chunks.length === 0) chunks.push(rest);
  return chunks;
}
