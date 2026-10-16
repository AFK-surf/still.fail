// What a login command's output and the page it opens say (docs/remote-login.md, 网址和端口的解析): the pages it names,
// whether one of them comes back to a loopback port on this machine (and to which path, with which state), a device
// code to enter, a prompt that asks for Enter. Pure: read from text, nothing run.

/// Drops what a terminal is told rather than shown: CSI sequences (colours, cursor moves), OSC (titles, colour
/// queries) and the two-character escapes; a carriage return is a line's end here.
export function plainText(text: string): string {
  let out = "";
  for (let i = 0; i < text.length; i++) {
    const c = text[i]!;
    if (c === "\u001b") {
      const next = text[i + 1];
      if (next === "[") {
        i += 2;
        while (i < text.length && !/[@-~]/.test(text[i]!)) i++;
      } else if (next === "]") {
        i += 2;
        while (i < text.length && text[i] !== "\u0007" && !(text[i] === "\u001b" && text[i + 1] === "\\")) i++;
        if (text[i] === "\u001b") i++;
      } else i += 1;
      continue;
    }
    if (c === "\r") {
      if (text[i + 1] !== "\n") out += "\n";
      continue;
    }
    if (c === "\b" || c === "\u0007" || c === "\u000f" || c === "\u000e") continue;
    out += c;
  }
  return out;
}

/// The http(s) addresses in some text, in order, without the punctuation that ends a sentence around them.
export function urlsIn(text: string): string[] {
  const found: string[] = [];
  for (const m of text.matchAll(/https?:\/\/[^\s"'<>`]+/g)) {
    let url = m[0];
    while (/[.,;:!?)\]}'"…]$/.test(url) && !(url.endsWith(")") && url.includes("("))) url = url.slice(0, -1);
    url = url.replace(/\.\.\.$/, "");
    if (url.length > "https://".length) found.push(url);
  }
  return found;
}

/// Where a login's browser comes back to on this machine: `redirect_uri` (or a parameter like it) at localhost,
/// 127.0.0.1 or [::1] with a port; the page's `state`; `post` when the callback is a form posted to it (response_mode
/// form_post, az's).
export type Loopback = { host: string; port: number; path: string; state: string | null; post: boolean };

const REDIRECTS = ["redirect_uri", "redirect_url", "redirecturi", "redirect", "callback", "callback_url", "return_to"];
const LOOPBACK = new Set(["localhost", "127.0.0.1", "[::1]", "::1"]);

function parsed(text: string): URL | null {
  try {
    return new URL(text);
  } catch {
    return null;
  }
}

/// A URL's loopback callback, looked for in its own parameters and one level of addresses inside them (a sign-in page
/// handing on to an authorize URL); none when it comes back elsewhere, or names no port.
export function loopbackOf(url: string, depth = 0): Loopback | null {
  const page = parsed(url);
  if (page === null) return null;
  const post = page.searchParams.get("response_mode") === "form_post";
  const state = page.searchParams.get("state");
  for (const [name, value] of page.searchParams) {
    if (!REDIRECTS.includes(name.toLowerCase())) continue;
    const back = parsed(value);
    if (back === null || back.protocol !== "http:" || !LOOPBACK.has(back.hostname)) continue;
    const port = Number(back.port);
    if (!Number.isInteger(port) || port <= 0 || port > 65535) continue;
    return { host: back.hostname === "::1" ? "[::1]" : back.hostname, port, path: back.pathname === "" ? "/" : back.pathname, state, post };
  }
  if (depth > 0) return null;
  for (const [, value] of page.searchParams) {
    if (!/^https?:\/\//.test(value)) continue;
    const inner = loopbackOf(value, depth + 1);
    if (inner !== null) return { ...inner, state: inner.state ?? state, post: inner.post || post };
  }
  return null;
}

/// A page's host, as shown beside its button (github.com).
export function domainOf(url: string): string | null {
  return parsed(url)?.host ?? null;
}

/// A device code in some output: by the service's own pattern (its first group, if it has one), else one like
/// ABCD-1234 (four capitals or digits, a dash, four to six more), else on a line that says "code", a word of six to ten
/// capitals and digits with a digit in it or right after the word "code".
export function deviceCodeIn(text: string, pattern?: string | null): string | null {
  if (pattern) {
    let re: RegExp;
    try {
      re = new RegExp(pattern);
    } catch {
      re = /$^/;
    }
    const m = re.exec(text);
    if (m) return m[1] ?? m[0];
    return null;
  }
  for (const word of text.split(/[^A-Za-z0-9_-]/)) {
    const parts = word.split("-");
    const code = (s: string, min: number, max: number) => s.length >= min && s.length <= max && /^[A-Z0-9]+$/.test(s);
    for (let i = 0; i + 1 < parts.length; i++) if (code(parts[i]!, 4, 4) && code(parts[i + 1]!, 4, 6)) return `${parts[i]}-${parts[i + 1]}`;
  }
  for (const line of text.split("\n")) {
    if (!/code/i.test(line)) continue;
    const after = /code[^A-Za-z0-9]{1,3}([A-Z0-9]{6,10})\b/i.exec(line);
    if (after && /^[A-Z0-9]+$/.test(after[1]!)) return after[1]!;
    for (const word of line.split(/[^A-Za-z0-9]+/)) if (/^[A-Z0-9]{6,10}$/.test(word) && /[0-9]/.test(word) && /[A-Z]/.test(word)) return word;
  }
  return null;
}

/// Where a device code is entered, of the pages named: one whose path says device, activate or verify first, else the
/// first that comes back to no loopback port; and the one with the code in it, where one has (`user_code=`).
export function deviceUrls(urls: string[], code: string): { url: string | null; codeUrl: string | null } {
  const pages = urls.filter((u) => u.startsWith("https://") && loopbackOf(u) === null);
  const withCode = pages.find((u) => u.includes(code) || /[?&](user_code|code)=/.test(u)) ?? null;
  const verify = pages.find((u) => /device|activate|verif/i.test(parsed(u)?.pathname ?? "")) ?? pages[0] ?? null;
  return { url: verify, codeUrl: withCode };
}

/// Whether a line asks for Enter to go on (gh, npm, docker: "Press Enter to open … in your browser").
export const asksEnter = (line: string) => /press\s+(enter|return)\b/i.test(line);

/// Whether a line looks like a question waiting for an answer (ends in :, ?, >, a (Y/n), or a choice's arrow).
export const prompts = (line: string) => /(\?|:|>|\)|\]|＞|：|？)\s*$/.test(line.trim()) || /\([yY]\/[nN]\)|\[[yY]\/[nN]\]/.test(line) || /^\s*[>❯]\s/.test(line);

/// Whether a prompt asks for a secret (its input is then not echoed).
export const secretAsked = (line: string) => /password|passphrase|token|secret|密码/i.test(line);

/// A command line in words (`vercel login --scope "my team"`): split as a POSIX shell would split plain words and
/// quotes (no variables, no globs); null when a quote is left open.
export function commandWords(line: string): string[] | null {
  const words: string[] = [];
  let word = "";
  let has = false;
  let quote: '"' | "'" | null = null;
  for (let i = 0; i < line.length; i++) {
    const c = line[i]!;
    if (quote === "'") {
      if (c === "'") quote = null;
      else word += c;
    } else if (quote === '"') {
      if (c === '"') quote = null;
      else if (c === "\\" && i + 1 < line.length && /["\\$`]/.test(line[i + 1]!)) word += line[++i];
      else word += c;
    } else if (c === "'" || c === '"') {
      quote = c;
      has = true;
    } else if (c === "\\" && i + 1 < line.length) {
      word += line[++i];
      has = true;
    } else if (/\s/.test(c)) {
      if (has || word !== "") words.push(word);
      word = "";
      has = false;
    } else word += c;
  }
  if (quote !== null) return null;
  if (has || word !== "") words.push(word);
  return words;
}
