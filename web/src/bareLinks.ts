// Web addresses written bare in text, found as a reader sees them: Prose.tsx and a person's words (Chat.tsx) link
// them, and the Android app finds the same (ui/Links.kt). An address is http(s):// and the characters addresses are
// made of; it ends at a space or at a letter outside ASCII (Chinese words, full-width marks such as `）` `，` `。`),
// and gives back the marks that close a sentence after it (`.` `,` `:` `!` `?` …) and a closing bracket it did not
// open. GFM's own finding ends only at a space: `（https://…/2854）已改到` became one link, its words with it.

const ADDRESS = /(?<![A-Za-z0-9])https?:\/\/[A-Za-z0-9\-._~:/?#[\]@!$&'()*+,;=%]+/gi;

/** `text` cut into its words and the addresses in it, in order. */
export function bareLinks(text: string): (string | { url: string })[] {
  const parts: (string | { url: string })[] = [];
  let at = 0;
  for (const m of text.matchAll(ADDRESS)) {
    const url = trimmed(m[0]);
    const end = m.index + url.length;
    // A host, not the scheme alone; one cut short (`https://github.com/…`) is no address to open.
    if (!/^https?:\/\/[A-Za-z0-9]/i.test(url) || text[m.index + m[0].length] === "…") continue;
    if (m.index > at) parts.push(text.slice(at, m.index));
    parts.push({ url });
    at = end;
  }
  if (at < text.length) parts.push(text.slice(at));
  return parts;
}

/** An address without what closes the sentence or the bracket it is written in. */
function trimmed(address: string): string {
  let url = address;
  for (;;) {
    const last = url.at(-1)!;
    if (".,:;!?'*_~".includes(last)) url = url.slice(0, -1);
    else if ((last === ")" || last === "]") && count(url, last === ")" ? "(" : "[") < count(url, last)) url = url.slice(0, -1);
    else return url;
  }
}

const count = (text: string, mark: string) => text.split(mark).length - 1;
