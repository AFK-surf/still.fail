// What a web link in a message is, for its preview card on the pages (GET /link-preview, src/api/routes/links.ts): a
// GitHub pull request or issue as GitHub says it (its state, author, size and checks; through `gh` where it is signed
// in, so private repositories too, else GitHub's public API), any other page by its title, description and icon.
// Only public addresses are fetched (a link in a chat is no way into the station's own network), a little of each, and
// what was found is kept a while, so a card opened again shows at once.
import { execFile } from "node:child_process";
import { lookup } from "node:dns/promises";
import { isIP } from "node:net";
import { wall } from "../ops/fibers.ts";

type Json = any;

export type Person = { login: string; avatar?: string };
export type LinkPreview =
  | { kind: "page"; url: string; title: string; description?: string; site?: string; icon?: string }
  | {
      kind: "github_pull_request";
      url: string;
      repository: string;
      number: number;
      title: string;
      state: "open" | "closed" | "merged" | "draft";
      author: Person | null;
      additions: number | null;
      deletions: number | null;
      changedFiles: number | null;
      updatedAt: number | null;
      checks?: { passed: number; failed: number; pending: number };
    }
  | {
      kind: "github_issue";
      url: string;
      repository: string;
      number: number;
      title: string;
      state: "open" | "completed" | "not_planned" | "closed";
      author: Person | null;
      comments: number | null;
      labels: string[];
      updatedAt: number | null;
    };

const UA = { "user-agent": "stillfail-station (link preview)" };
/// How long one fetch may take.
const TIMEOUT_MS = 6000;
/// The most of a page read for its head.
const PAGE_BYTES = 512 * 1024;
/// The most an icon or avatar may be (it goes across inline).
const ICON_BYTES = 48 * 1024;
/// How long a preview is kept; a pull request's state moves, so not long.
const KEEP_MS = 5 * 60 * 1000;
const KEPT = 300;

const kept = new Map<string, { at: number; value: Promise<LinkPreview | null> }>();

/// The preview of `href`, null when there is none to give (not a page, not reachable, not allowed).
export function linkPreview(href: string, now = wall.now()): Promise<LinkPreview | null> {
  const known = kept.get(href);
  if (known && now - known.at < KEEP_MS) return known.value;
  const value = find(href).catch(() => null);
  kept.delete(href);
  kept.set(href, { at: now, value });
  while (kept.size > KEPT) kept.delete(kept.keys().next().value!);
  return value;
}

async function find(href: string): Promise<LinkPreview | null> {
  let url: URL;
  try {
    url = new URL(href);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return null;
  const gh = /^\/([\w.-]+)\/([\w.-]+)\/(pull|issues)\/(\d+)(?:[/?#]|$)/.exec(url.pathname);
  if (url.hostname === "github.com" && gh) {
    const found = await github(gh[1]!, gh[2]!, gh[3] === "pull", Number(gh[4]), href).catch(() => null);
    if (found) return found;
  }
  return page(url);
}

// ---- GitHub ----

/// A GitHub API path's answer: through `gh` (signed in, private repositories too), else the public API.
async function githubApi(path: string): Promise<Json> {
  const viaGh = await new Promise<Json | null>((resolve) => {
    execFile("gh", ["api", path], { timeout: TIMEOUT_MS, maxBuffer: 4 << 20 }, (error, stdout) => {
      if (error) return resolve(null);
      try {
        resolve(JSON.parse(stdout));
      } catch {
        resolve(null);
      }
    });
  });
  if (viaGh !== null) return viaGh;
  const res = await fetch(`https://api.github.com/${path}`, { headers: { ...UA, accept: "application/vnd.github+json" }, signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (!res.ok) throw new Error(`GitHub answered ${res.status}`);
  return res.json();
}

const when = (s: unknown): number | null => (typeof s === "string" && !Number.isNaN(Date.parse(s)) ? Date.parse(s) : null);
const count = (n: unknown): number | null => (typeof n === "number" && Number.isFinite(n) ? n : null);

async function person(user: Json): Promise<Person | null> {
  if (typeof user?.login !== "string") return null;
  const avatar = typeof user.avatar_url === "string" ? await image(`${user.avatar_url}${user.avatar_url.includes("?") ? "&" : "?"}s=48`) : null;
  return { login: user.login, ...(avatar ? { avatar } : {}) };
}

async function github(owner: string, repo: string, pull: boolean, number: number, href: string): Promise<LinkPreview | null> {
  const repository = `${owner}/${repo}`;
  if (pull) {
    const pr = await githubApi(`repos/${repository}/pulls/${number}`);
    const state = pr.merged_at ? "merged" : pr.state === "closed" ? "closed" : pr.draft ? "draft" : "open";
    const [author, checks] = await Promise.all([person(pr.user), typeof pr.head?.sha === "string" ? checksOf(repository, pr.head.sha) : null]);
    return {
      kind: "github_pull_request", url: href, repository, number, title: String(pr.title ?? ""), state, author,
      additions: count(pr.additions), deletions: count(pr.deletions), changedFiles: count(pr.changed_files), updatedAt: when(pr.updated_at),
      ...(checks ? { checks } : {}),
    };
  }
  const issue = await githubApi(`repos/${repository}/issues/${number}`);
  const state = issue.state === "open" ? "open" : issue.state_reason === "completed" ? "completed" : issue.state_reason === "not_planned" ? "not_planned" : "closed";
  const labels = (Array.isArray(issue.labels) ? issue.labels : []).flatMap((l: Json) => (typeof l?.name === "string" ? [l.name] : [])).slice(0, 3);
  return {
    kind: "github_issue", url: href, repository, number, title: String(issue.title ?? ""), state, author: await person(issue.user),
    comments: count(issue.comments), labels, updatedAt: when(issue.updated_at),
  };
}

/// A commit's checks, counted: passed, failed, still going. Null when it has none, or they cannot be read.
async function checksOf(repository: string, sha: string): Promise<{ passed: number; failed: number; pending: number } | null> {
  try {
    const runs = (await githubApi(`repos/${repository}/commits/${sha}/check-runs?per_page=100`))?.check_runs;
    if (!Array.isArray(runs) || runs.length === 0) return null;
    const out = { passed: 0, failed: 0, pending: 0 };
    for (const run of runs) {
      if (run.status !== "completed") out.pending++;
      else if (["success", "neutral", "skipped"].includes(run.conclusion)) out.passed++;
      else out.failed++;
    }
    return out;
  } catch {
    return null;
  }
}

// ---- any page ----

/// Whether an address is one of the internet's, not a private, loopback or link-local one.
export function isPublic(address: string): boolean {
  const v4 = isIP(address) === 4 ? address : /^::ffff:(\d+\.\d+\.\d+\.\d+)$/i.exec(address)?.[1];
  if (v4) {
    const [a, b] = v4.split(".").map(Number) as [number, number];
    return !(a === 0 || a === 10 || a === 127 || (a === 100 && b >= 64 && b < 128) || (a === 169 && b === 254) || (a === 172 && b >= 16 && b < 32) || (a === 192 && b === 168) || a >= 224);
  }
  const v6 = address.toLowerCase();
  return !(v6 === "::" || v6 === "::1" || /^f[cd]/.test(v6) || /^fe[89ab]/.test(v6) || v6.startsWith("ff"));
}

/// A fetch of a public address only, each redirect checked again; null for any other.
async function fetchPublic(start: URL, accept: string): Promise<Response | null> {
  let url = start;
  for (let hop = 0; hop < 4; hop++) {
    if (url.protocol !== "https:" && url.protocol !== "http:") return null;
    const host = url.hostname.replace(/^\[|\]$/g, "");
    const addresses = isIP(host) ? [{ address: host }] : await lookup(host, { all: true }).catch(() => []);
    if (addresses.length === 0 || !addresses.every((a) => isPublic(a.address))) return null;
    const res = await fetch(url, { headers: { ...UA, accept }, redirect: "manual", signal: AbortSignal.timeout(TIMEOUT_MS) });
    const next = res.status >= 300 && res.status < 400 ? res.headers.get("location") : null;
    if (next === null) return res;
    await res.body?.cancel();
    url = new URL(next, url);
  }
  return null;
}

/// The start of a body, at most `max` bytes.
async function bodyUpTo(res: Response, max: number): Promise<Buffer> {
  const parts: Buffer[] = [];
  let got = 0;
  const reader = res.body?.getReader();
  if (!reader) return Buffer.alloc(0);
  while (got < max) {
    const { done, value } = await reader.read();
    if (done) break;
    parts.push(Buffer.from(value));
    got += value.length;
  }
  await reader.cancel().catch(() => {});
  return Buffer.concat(parts).subarray(0, max);
}

/// An image as a data: URL (an icon, an avatar), small ones only.
async function image(href: string): Promise<string | null> {
  try {
    const res = await fetchPublic(new URL(href), "image/*");
    const type = res?.headers.get("content-type")?.split(";")[0]?.trim() ?? "";
    if (!res?.ok || !type.startsWith("image/")) return null;
    const bytes = await bodyUpTo(res, ICON_BYTES + 1);
    return bytes.length > ICON_BYTES || bytes.length === 0 ? null : `data:${type};base64,${bytes.toString("base64")}`;
  } catch {
    return null;
  }
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
/// Text out of HTML: its entities read, its spaces made one.
export function htmlText(s: string): string {
  return s
    .replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/gi, (m, e: string) => {
      if (e[0] === "#") {
        const code = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
        return Number.isFinite(code) && code > 0 && code < 0x110000 ? String.fromCodePoint(code) : m;
      }
      return ENTITIES[e.toLowerCase()] ?? m;
    })
    .replace(/\s+/g, " ")
    .trim();
}

/// What a page's head says of it: its title (og:title, else <title>), description, site and icon's address.
export function headOf(html: string, base: URL): { title?: string; description?: string; site?: string; icon?: string } {
  const end = html.search(/<\/head>/i);
  const head = end < 0 ? html : html.slice(0, end);
  const metas = [...head.matchAll(/<meta\b[^>]*>/gi)].map((m) => m[0]);
  const attr = (tag: string, name: string) => new RegExp(`\\b${name}\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s>]+))`, "i").exec(tag)?.slice(2).find((v) => v !== undefined);
  const meta = (...names: string[]) => {
    for (const name of names) {
      const tag = metas.find((t) => (attr(t, "property") ?? attr(t, "name"))?.toLowerCase() === name);
      const content = tag ? attr(tag, "content") : undefined;
      if (content) return htmlText(content);
    }
    return undefined;
  };
  const titleTag = /<title\b[^>]*>([^<]*)<\/title>/i.exec(head)?.[1];
  const title = meta("og:title", "twitter:title") ?? (titleTag ? htmlText(titleTag) : undefined);
  const description = meta("og:description", "description", "twitter:description");
  const site = meta("og:site_name");
  const links = [...head.matchAll(/<link\b[^>]*>/gi)].map((m) => m[0]);
  const iconTag = links.find((t) => /^(?:shortcut )?icon$/i.test(attr(t, "rel") ?? "")) ?? links.find((t) => /apple-touch-icon/i.test(attr(t, "rel") ?? ""));
  let icon: string | undefined;
  try {
    icon = new URL(iconTag ? (attr(iconTag, "href") ?? "/favicon.ico") : "/favicon.ico", base).toString();
  } catch {}
  const cut = (s: string | undefined, n: number) => (s === undefined || s === "" ? undefined : Array.from(s).length > n ? `${Array.from(s).slice(0, n).join("")}…` : s);
  return { ...(title ? { title: cut(title, 200)! } : {}), ...(description ? { description: cut(description, 300)! } : {}), ...(site ? { site: cut(site, 60)! } : {}), ...(icon ? { icon } : {}) };
}

async function page(url: URL): Promise<LinkPreview | null> {
  const res = await fetchPublic(url, "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1");
  if (!res?.ok) return null;
  const type = res.headers.get("content-type") ?? "";
  if (!/html/i.test(type)) {
    await res.body?.cancel();
    return null;
  }
  const html = (await bodyUpTo(res, PAGE_BYTES)).toString("utf8");
  const found = headOf(html, new URL(res.url || url.toString()));
  if (!found.title) return null;
  const icon = found.icon ? await image(found.icon) : null;
  return { kind: "page", url: url.toString(), title: found.title, ...(found.description ? { description: found.description } : {}), ...(found.site ? { site: found.site } : {}), ...(icon ? { icon } : {}) };
}
