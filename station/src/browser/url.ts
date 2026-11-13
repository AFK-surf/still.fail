// Web addresses a person opens in the station's browser: bare hosts (`mail.proton.me`, `localhost:3000`) or full
// `http(s)://` links (including the first link inside pasted prose or an email), checked so non-web schemes and bare
// email addresses (`alice@proton.me`) are refused.

const MAX_URL_LENGTH = 8192;
const TRAILING_PUNCT = /[.,;:!?]+$/;

function validHttpUrl(raw: string): URL | null {
  try {
    const u = new URL(raw);
    if ((u.protocol !== "http:" && u.protocol !== "https:") || u.hostname === "") return null;
    if (u.username !== "" || u.password !== "") return null;
    return u;
  } catch {
    return null;
  }
}

function plausibleBareHost(hostname: string): boolean {
  const h = hostname.toLowerCase();
  if (h === "localhost" || h.endsWith(".localhost") || h.startsWith("[")) return true;
  if (/^\d{1,3}(?:\.\d{1,3}){3}$/.test(h)) return true;
  if (h.startsWith(".") || h.endsWith(".") || h.includes("..")) return false;
  const dot = h.lastIndexOf(".");
  return dot > 0 && h.length - dot - 1 >= 2;
}

/// The first valid `http(s)://` URL inside `raw` (a copied link or a block of email text), or null.
export function extractFirstHttpUrl(raw: string): string | null {
  if (typeof raw !== "string" || raw.length === 0) return null;
  const text = raw.slice(0, MAX_URL_LENGTH * 2);
  const re = /https?:\/\/[^\s<>"'`)\]}]+/gi;
  for (let m = re.exec(text); m !== null; m = re.exec(text)) {
    const candidate = m[0].replace(TRAILING_PUNCT, "");
    if (candidate.length > MAX_URL_LENGTH) continue;
    const parsed = validHttpUrl(candidate);
    if (parsed !== null) return parsed.toString();
  }
  return null;
}

/// A web address normalized to `http(s)://…`: accepts a full URL, text containing an `http(s)://` link, or a bare
/// host (`mail.proton.me`, `localhost:3000/app`); null for empty strings, non-HTTP schemes or email addresses.
export function normalizeBrowserUrl(raw: string): string | null {
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  if (trimmed === "" || trimmed.length > MAX_URL_LENGTH) return null;
  if (/^https?:\/\//i.test(trimmed) && !/\s/.test(trimmed)) {
    return validHttpUrl(trimmed)?.toString() ?? null;
  }
  const embedded = extractFirstHttpUrl(trimmed);
  if (embedded !== null) return embedded;
  if (/[\s\p{Cc}]/u.test(trimmed)) return null;
  // Reject non-HTTP schemes (`javascript:`, `mailto:`, `file:`, `about:`, `chrome://`); allow `host:port` where `:` is followed by digits.
  if (trimmed.includes("://")) return null;
  const slash = trimmed.search(/[/?#]/);
  const authority = slash < 0 ? trimmed : trimmed.slice(0, slash);
  if (authority === "" || authority.includes("@")) return null;
  if (!authority.startsWith("[")) {
    const colon = authority.indexOf(":");
    if (colon >= 0 && !/^\d+$/.test(authority.slice(colon + 1))) return null;
  }
  const hostOnly = authority.startsWith("[") ? authority.slice(0, authority.indexOf("]") + 1) : authority.split(":")[0]!;
  const local = hostOnly.toLowerCase() === "localhost" || hostOnly.toLowerCase().endsWith(".localhost") || hostOnly === "127.0.0.1" || hostOnly === "[::1]";
  const parsed = validHttpUrl(`${local ? "http" : "https"}://${trimmed}`);
  if (parsed === null || !plausibleBareHost(parsed.hostname)) return null;
  return parsed.toString();
}

/// The site (`hostname[:port]`) of a browser tab's URL, without path, query or hash; undefined for `about:blank`.
export function siteOfBrowserUrl(raw: string): string | undefined {
  const u = validHttpUrl(raw);
  return u ? u.host.toLowerCase() : undefined;
}

/// A URL worth persisting for a sleeping user tab (`http:` or `https:`, never `about:blank` or `chrome-error://`).
export function persistableBrowserUrl(raw: string): string | null {
  return validHttpUrl(raw)?.toString() ?? null;
}
