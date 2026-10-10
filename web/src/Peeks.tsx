// What a message names, while it is pointed at: a web link (its page's title and icon; a GitHub pull request's or
// issue's state, author, size and checks) and a file on the station by its path (a few of its lines, its picture, a
// directory's entries), each as a small card (Hover.css.ts, Cue's card language). Read from the station as soon as
// its link is pointed at (`link.preview`, `file.peek`), and kept: shown at once when opened again, and read again
// behind it once a minute old. A file's chip opens the file itself over the window (`file.open`, FilePreview).
import { createContext, useCallback, useContext, useEffect, useState, useSyncExternalStore, type ReactElement, type ReactNode } from "react";
import { HoverCard } from "radix-ui";
import { stationApi, useStationCall } from "./api.ts";
import type { Attachment } from "./core/shapes.ts";
import { FilePreview, fileSize, type LocalFile } from "./FilePreview.tsx";
import { Check, Copy, File as FileIcon, Folder, Web } from "./icons.tsx";
import { lang, t } from "./i18n.ts";
import { useStation } from "./station.tsx";
import { failure, useToast } from "./toast.tsx";
import * as css from "./Hover.css.ts";
import { pathIn } from "./paths.ts";

export { pathIn };

// ---- the card ----

/** Cards open: while one is, the next opens with no animation (moving along links, it reads as one card moving). */
let openCards = 0;
let lastClosed = 0;

/**
 * A card over `children` (the link, the chip) while it is pointed at: `content` is mounted only while the card shows.
 * `warm`: what it reads, asked for as soon as the pointer comes onto it (during the card's delay), so the card mostly
 * opens with it already there. `tile`: a narrower card.
 */
export function Hover({ children, content, tile = false, warm }: { children: ReactElement; content: ReactNode; tile?: boolean; warm?: (() => void) | undefined }) {
  const [instant, setInstant] = useState(false);
  return (
    <HoverCard.Root openDelay={320} closeDelay={120} onOpenChange={(open) => {
      if (open) {
        setInstant(openCards > 0 || Date.now() - lastClosed < 260);
        openCards++;
      } else {
        openCards = Math.max(0, openCards - 1);
        lastClosed = Date.now();
      }
    }}>
      <HoverCard.Trigger asChild onPointerEnter={warm} onFocus={warm}>{children}</HoverCard.Trigger>
      <HoverCard.Portal>
        <HoverCard.Content className={`${css.card}${tile ? ` ${css.cardTile}` : ""}`} data-instant={instant || undefined} side="bottom" align="start" sideOffset={6} collisionPadding={8}>
          {content}
        </HoverCard.Content>
      </HoverCard.Portal>
    </HoverCard.Root>
  );
}

/** Bars where a card's lines will be, while it is read. */
export function CardSkeleton() {
  return (
    <div className={css.rich} aria-busy="true">
      <span className={css.bar} data-bar="meta" />
      <span className={css.bar} data-bar="title" />
      <span className={css.bar} data-bar="detail" />
    </div>
  );
}

/** When, in words, relative while it is recent ("3 小时前"), else the day. */
export function ago(at: number | null | undefined): string | null {
  if (at == null) return null;
  const rtf = new Intl.RelativeTimeFormat(lang() === "zh" ? "zh-CN" : "en", { numeric: "auto" });
  const s = Math.round((at - Date.now()) / 1000);
  const a = Math.abs(s);
  if (a < 60) return rtf.format(s, "second");
  if (a < 3600) return rtf.format(Math.round(s / 60), "minute");
  if (a < 86400) return rtf.format(Math.round(s / 3600), "hour");
  if (a < 7 * 86400) return rtf.format(Math.round(s / 86400), "day");
  return new Date(at).toLocaleDateString(lang() === "zh" ? "zh-CN" : "en", { year: new Date(at).getFullYear() === new Date().getFullYear() ? undefined : "numeric", month: "short", day: "numeric" });
}

// ---- what is read, kept (stale while it is read again) ----

type Read<T> = { state: "loading" } | { state: "ready"; value: T } | { state: "error"; message: string };
/**
 * What cards read, by what they read, the latest 300: what was read shows at once, every time; once it is a minute
 * old (a pull request's state moves, a file changes) it is read again behind it and the card follows. A failed read
 * is tried again the next time.
 */
type Entry = { value?: unknown; has: boolean; error?: string | undefined; at: number; reading: boolean; version: number };
const entries = new Map<string, Entry>();
const watchers = new Map<string, Set<() => void>>();
const FRESH_MS = 60 * 1000;

function changed(key: string, e: Entry) {
  e.version++;
  for (const w of watchers.get(key) ?? []) w();
}

/** Reads `key` (with `read`) unless it is read already, or was within the minute (a failure: within a few seconds). */
export function warm(key: string, read: () => Promise<unknown>): void {
  let e = entries.get(key);
  if (e && (e.reading || Date.now() - e.at < (e.error !== undefined && !e.has ? 3000 : FRESH_MS))) return;
  if (!e) {
    e = { has: false, at: 0, reading: false, version: 0 };
    entries.set(key, e);
    while (entries.size > 300) entries.delete(entries.keys().next().value!);
  }
  const entry = e;
  entry.reading = true;
  read().then(
    (value) => { entry.value = value; entry.has = true; entry.error = undefined; },
    (err: unknown) => { entry.error = failure(err); },
  ).finally(() => { entry.at = Date.now(); entry.reading = false; changed(key, entry); });
}

/** Follows what is kept of `key`, reading nothing. */
function useEntry(key: string): Entry | undefined {
  useSyncExternalStore(
    useCallback((on: () => void) => {
      let set = watchers.get(key);
      if (!set) watchers.set(key, (set = new Set()));
      set.add(on);
      return () => { set.delete(on); if (set.size === 0) watchers.delete(key); };
    }, [key]),
    () => entries.get(key)?.version ?? -1,
  );
  return entries.get(key);
}

function useRead<T>(key: string, read: () => Promise<T>): Read<T> {
  const e = useEntry(key);
  useEffect(() => warm(key, read), [key]); // eslint-disable-line react-hooks/exhaustive-deps
  if (e?.has) return { state: "ready", value: e.value as T };
  if (e?.error !== undefined && !e.reading) return { state: "error", message: e.error };
  return { state: "loading" };
}

// ---- web links ----

type Person = { login: string; avatar?: string };
type LinkPreview =
  | { kind: "none" }
  | { kind: "page"; url: string; title: string; description?: string; site?: string; icon?: string }
  | {
      kind: "github_pull_request"; url: string; repository: string; number: number; title: string; state: "open" | "closed" | "merged" | "draft";
      author: Person | null; additions: number | null; deletions: number | null; changedFiles: number | null; updatedAt: number | null;
      checks?: { passed: number; failed: number; pending: number };
    }
  | {
      kind: "github_issue"; url: string; repository: string; number: number; title: string; state: "open" | "completed" | "not_planned" | "closed";
      author: Person | null; comments: number | null; labels: string[]; updatedAt: number | null;
    };

/** Where a link goes, as a card says it: its host and path. */
function destination(href: string): string {
  try {
    const url = new URL(href);
    return `${url.host}${url.pathname.replace(/\/$/, "")}`;
  } catch {
    return href;
  }
}

/** Links whose cards are rich (read before shown, bars meanwhile); any other shows its tile at once. */
const RICH = /^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/(?:pull|issues)\/\d+(?:[/?#]|$)/;

/** A web link in a message, and its card. */
export function LinkHover({ href, label, children }: { href: string; label: string; children: ReactElement }) {
  const station = useStation();
  const api = stationApi(useStationCall(station.address));
  const read = () => api.linkPreview<LinkPreview>(href);
  return <Hover tile={!RICH.test(href)} warm={() => warm(linkKey(station.address, href), read)} content={<LinkCard href={href} label={label} />}>{children}</Hover>;
}

const linkKey = (station: string, href: string) => `link ${station} ${href}`;
const peekKey = (station: string, session: string, path: string, line: number | null) => `peek ${station} ${session} ${path} ${line ?? ""}`;

function LinkCard({ href, label }: { href: string; label: string }) {
  const station = useStation();
  const api = stationApi(useStationCall(station.address));
  const read = useRead<LinkPreview>(linkKey(station.address, href), () => api.linkPreview<LinkPreview>(href));
  if (read.state === "loading" && RICH.test(href)) return <CardSkeleton />;
  const preview = read.state === "ready" ? read.value : null;
  if (preview?.kind === "github_pull_request") return <PullRequestCard preview={preview} />;
  if (preview?.kind === "github_issue") return <IssueCard preview={preview} />;
  const page = preview?.kind === "page" ? preview : null;
  const github = /^https:\/\/(?:[\w-]+\.)?github\.com\//.test(href);
  return (
    <div className={css.tile}>
      <span className={css.tileThumb} aria-hidden="true">
        {page?.icon ? <img className={css.tileIcon} src={page.icon} alt="" /> : github ? <GitHubMark size={20} /> : <Web size={18} />}
      </span>
      <span className={css.tileBody}>
        <span className={css.tileTitle}>{page?.title ?? label}</span>
        <span className={css.tileUrl} title={href}>{page?.site ? `${page.site} · ${destination(href)}` : destination(href)}</span>
      </span>
    </div>
  );
}

const PR_STATE = { open: "web-main.preview.pr.open", merged: "web-main.preview.pr.merged", closed: "web-main.preview.pr.closed", draft: "web-main.preview.pr.draft" } as const;
const ISSUE_STATE = { open: "web-main.preview.issue.open", completed: "web-main.preview.issue.completed", not_planned: "web-main.preview.issue.notPlanned", closed: "web-main.preview.issue.closed" } as const;

function PersonFact({ person }: { person: Person | null }) {
  if (!person) return null;
  return <span className={css.person}>{person.avatar ? <img className={css.avatar} src={person.avatar} alt="" /> : <span className={css.avatar} />}{person.login}</span>;
}

function PullRequestCard({ preview: p }: { preview: Extract<LinkPreview, { kind: "github_pull_request" }> }) {
  const checks = p.checks;
  return (
    <div className={css.rich}>
      <div className={css.meta}>
        <span className={css.state} data-state={p.state}><StateGlyph state={p.state} />{t(PR_STATE[p.state])}</span>
        <span className={css.ref}>{p.repository} #{p.number}</span>
        <span className={css.time}>{ago(p.updatedAt)}</span>
      </div>
      <span className={css.title} title={p.title}>{p.title}</span>
      <div className={css.facts}>
        <PersonFact person={p.author} />
        {(p.additions !== null || p.deletions !== null) && <span className={css.chip}><span className={css.add}>+{p.additions ?? 0}</span><span className={css.del}>−{p.deletions ?? 0}</span></span>}
        {p.changedFiles !== null && <span className={css.chip}>{t("web-main.preview.files", { count: p.changedFiles })}</span>}
        {checks && (
          <span className={css.state} data-state={checks.failed ? "failed" : checks.pending ? "pending" : "passed"}>
            {checks.failed ? t("web-main.preview.checks.failed", { count: checks.failed }) : checks.pending ? t("web-main.preview.checks.pending", { count: checks.pending }) : t("web-main.preview.checks.passed", { count: checks.passed })}
          </span>
        )}
      </div>
    </div>
  );
}

function IssueCard({ preview: p }: { preview: Extract<LinkPreview, { kind: "github_issue" }> }) {
  return (
    <div className={css.rich}>
      <div className={css.meta}>
        <span className={css.state} data-state={p.state}><StateGlyph state={p.state} />{t(ISSUE_STATE[p.state])}</span>
        <span className={css.ref}>{p.repository} #{p.number}</span>
        <span className={css.time}>{ago(p.updatedAt)}</span>
      </div>
      <span className={css.title} title={p.title}>{p.title}</span>
      <div className={css.facts}>
        <PersonFact person={p.author} />
        {p.labels.map((l) => <span key={l} className={css.chip}>{l}</span>)}
        {p.comments !== null && p.comments > 0 && <span className={css.chip}>{t("web-main.preview.comments", { count: p.comments })}</span>}
      </div>
    </div>
  );
}

/** A state's glyph in its pill: a ring for what is open, a check or a cross for what has ended. */
function StateGlyph({ state }: { state: string }) {
  const path = state === "merged" || state === "completed" ? "M3.5 8.5l3 3 6-7" : state === "closed" || state === "not_planned" ? "M4.5 4.5l7 7M11.5 4.5l-7 7" : null;
  return (
    <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {path ? <path d={path} /> : <circle cx="8" cy="8" r={state === "draft" ? 5 : 5.5} strokeDasharray={state === "draft" ? "2.5 2" : undefined} />}
    </svg>
  );
}

function GitHubMark({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

// ---- files named by their path ----

/**
 * The session whose files a message's paths name (its agent's, or another chat's agent that wrote here), and its
 * station's address when that is not this page's; null: none, they stay code.
 */
export const PathSession = createContext<{ key: string; station?: string } | null>(null);

type Peek = {
  path: string; name: string; size: number; mtime: number; type: string;
  kind: "text" | "image" | "binary" | "dir";
  lines?: { start: number; text: string[]; at?: number };
  image?: { type: string; data: string };
  entries?: string[]; count?: number;
};
type Opened = { name: string; path: string; type: string; size: number; bytes: string };

/**
 * A file a message names by its path: a chip with its icon and the path as written (chipPath; a directory's once its
 * card has read it as one, written with a `/` or not), its card on hover, the file itself on a click (a directory on
 * this machine: Finder). Copied with the text around it, it is the path as written, whole (`data-copy`, copied below).
 */
export function FileRef({ path, line, children, words }: { path: string; line: number | null; children: ReactNode; /** A link's own words, shown instead of the file's name. */ words?: ReactNode }) {
  const owner = useContext(PathSession);
  const session = owner?.key ?? null;
  const here = useStation().address;
  const station = { address: owner?.station ?? here };
  const api = stationApi(useStationCall(station.address));
  const toast = useToast();
  const local = useOnThisMachine(station.address);
  const key = peekKey(station.address, session ?? "", path, line);
  const kept = useEntry(key);
  const peeked = kept?.has ? (kept.value as Peek) : null;
  const [opened, setOpened] = useState<{ file: Attachment; local: LocalFile } | null>(null);
  useEffect(() => () => { if (opened) URL.revokeObjectURL(opened.local.url); }, [opened]);
  const name = path.replace(/\/$/, "").split("/").at(-1) || path;
  const peek = () => { if (session !== null) warm(key, () => api.filePeek<Peek>(session, path, line)); };
  // A name with no extension is as often a directory's as a file's: read at once, so the chip is drawn as what it is.
  useEffect(() => { if (!path.endsWith("/") && !/\.[A-Za-z0-9]{1,10}$/.test(name)) peek(); }, [key]); // eslint-disable-line react-hooks/exhaustive-deps
  if (session === null) return <code>{children}</code>;
  const dir = path.endsWith("/") || peeked?.kind === "dir";
  const whole = typeof children === "string" ? children.trim() : `${path}${line !== null ? `:${line}` : ""}`;
  const open = () => {
    if (dir) {
      if (local) void reveal(peeked?.path ?? path, toast);
      return;
    }
    void api.fileOpen<Opened>(session, path).then((f) => {
      const bin = atob(f.bytes);
      const bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      const blob = new Blob([bytes], { type: f.type });
      setOpened({ file: { name: f.name, path: f.path, size: f.size }, local: { blob, url: URL.createObjectURL(blob) } });
    }, (e: unknown) => toast(t("web-main.preview.openFailed", { name, error: failure(e) })));
  };
  const Icon = dir ? Folder : FileIcon;
  return (
    <>
      <Hover warm={peek} content={<FileCard session={session} station={station.address} path={path} line={line} local={local} />}>
        <button type="button" className={css.fileChip} onClick={open} data-dir={dir || undefined} data-opens={!dir || local || undefined} data-copy={words === undefined ? whole : undefined}>
          <Icon size={12} className={css.fileChipIcon} />
          <span className={css.fileChipName}>{words ?? `${chipPath(path)}${dir && !path.endsWith("/") ? "/" : ""}`}</span>
          {line !== null && words === undefined && <span className={css.fileChipLine}>:{line}</span>}
        </button>
      </Hover>
      {opened && <FilePreview open onClose={() => setOpened(null)} sessionKey={session} file={opened.file} local={opened.local} />}
    </>
  );
}

/** A path as it is shown: a home directory (/Users/<name>, /home/<name>) as `~`. */
function shownPath(path: string): string {
  return path.replace(/^\/(?:Users|home)\/[^/]+(?=\/|$)/, "~");
}

/** A path as a chip shows it, as the message wrote it (shownPath): a long one cut in its middle, its first two parts and last two kept. */
function chipPath(path: string): string {
  const short = shownPath(path);
  const slash = short.endsWith("/") ? "/" : "";
  const parts = short.replace(/\/$/, "").split("/");
  if (short.length <= 48 || parts.length <= 5) return short;
  return `${parts.slice(0, 2).join("/")}/…/${parts.slice(-2).join("/")}${slash}`;
}

// The station of the machine the desktop app is on ("<workspace>/<station>"), asked of it once; null in a browser, or an
// app that cannot show files.
let thisMachine: Promise<string | null> | null = null;

/** Whether `address` is the station of the machine the page is on (the desktop app's): its files can be shown in Finder. */
function useOnThisMachine(address: string): boolean {
  const [here, setHere] = useState<string | null>(null);
  useEffect(() => {
    const desktop = window.stillfailDesktop;
    if (!desktop?.reveal || !desktop.station) return;
    thisMachine ??= desktop.station.state().then((s) => (s?.workspace && s.station ? `${s.workspace}/${s.station}` : null), () => null);
    let live = true;
    void thisMachine.then((a) => { if (live) setHere(a); });
    return () => { live = false; };
  }, []);
  return here !== null && here === address;
}

/** What shows the machine's files: Finder on a Mac, Explorer on Windows. */
const FILES_APP = typeof navigator !== "undefined" && /Windows/.test(navigator.userAgent) ? "Explorer" : "Finder";

async function reveal(path: string, toast: (message: string) => void): Promise<void> {
  const shown = await window.stillfailDesktop?.reveal?.(path).catch(() => false);
  if (!shown) toast(t("web-main.preview.revealFailed", { path: shownPath(path), app: FILES_APP }));
}

/** A file's whole path, and showing it in Finder when it is on this machine (a relative one cannot be). */
function PathActions({ path, local }: { path: string; local: boolean }) {
  const toast = useToast();
  const [copied, setCopied] = useState(false);
  const copy = () => void navigator.clipboard.writeText(path).then(() => {
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }, (e: unknown) => toast(t("web-main.copyFailed", { error: failure(e) })));
  return (
    <span className={css.actions}>
      <button type="button" className={css.action} onClick={copy}>{copied ? <Check size={12} /> : <Copy size={12} />}{copied ? t("common.copied") : t("web-main.preview.copyPath")}</button>
      {local && (path.startsWith("/") || path.startsWith("~/")) && (
        <button type="button" className={css.action} onClick={() => void reveal(path, toast)}><Folder size={12} />{t("web-main.preview.reveal", { app: FILES_APP })}</button>
      )}
    </span>
  );
}

// Copying a stretch of a message: its file chips are their paths as written, not cut as they show.
if (typeof document !== "undefined") {
  document.addEventListener("copy", (e) => {
    const selection = document.getSelection();
    if (!selection || selection.isCollapsed || selection.rangeCount === 0 || !e.clipboardData) return;
    const part = selection.getRangeAt(0).cloneContents();
    const chips = part.querySelectorAll<HTMLElement>("[data-copy]");
    if (chips.length === 0) return;
    for (const chip of chips) chip.replaceWith(chip.dataset.copy ?? "");
    // Laid out (off the screen) for its text as it reads, its blocks on lines of their own.
    const box = document.createElement("div");
    box.style.cssText = "position:fixed;left:-100000px;top:0;";
    box.append(part);
    document.body.append(box);
    e.clipboardData.setData("text/plain", box.innerText);
    e.clipboardData.setData("text/html", box.innerHTML);
    box.remove();
    e.preventDefault();
  });
}

function FileCard({ session, station, path, line, local }: { session: string; station: string; path: string; line: number | null; local: boolean }) {
  const api = stationApi(useStationCall(station));
  const read = useRead<Peek>(peekKey(station, session, path, line), () => api.filePeek<Peek>(session, path, line));
  if (read.state === "loading") return <CardSkeleton />;
  if (read.state === "error") return (
    <div className={css.rich}>
      <FileHead name={path.replace(/\/$/, "").split("/").at(-1) || path} dir={path.endsWith("/")} path={path} />
      <p className={css.note}>{read.message}</p>
      <div className={css.facts}><PathActions path={path} local={local} /></div>
    </div>
  );
  const p = read.value;
  const dir = p.kind === "dir";
  return (
    <div className={css.rich}>
      <FileHead name={`${p.name}${p.lines?.at ? `:${p.lines.at}` : ""}`} dir={dir} path={p.path} time={ago(p.mtime)} />
      {p.kind === "text" && p.lines && p.lines.text.length > 0 && (
        <pre className={css.lines}>
          {p.lines.text.map((l, i) => {
            const n = p.lines!.start + i;
            return <span key={n} className={css.line} data-at={n === p.lines!.at || undefined}><span className={css.lineNo}>{n}</span><span className={css.lineText}>{l || " "}</span></span>;
          })}
        </pre>
      )}
      {p.kind === "image" && p.image && <img className={css.thumb} src={`data:${p.image.type};base64,${p.image.data}`} alt="" />}
      {dir && p.entries && p.entries.length > 0 && (
        <ul className={css.entries}>
          {p.entries.map((e) => {
            const EntryIcon = e.endsWith("/") ? Folder : FileIcon;
            return <li key={e} className={css.entry}><EntryIcon size={12} className={css.entryIcon} /><span className={css.entryName}>{e.replace(/\/$/, "")}</span></li>;
          })}
        </ul>
      )}
      <div className={css.facts}>
        {dir && <span>{t("web-main.preview.items", { count: p.count ?? p.entries?.length ?? 0 })}</span>}
        {!dir && <span className={css.chip}>{fileSize(p.size)}</span>}
        {p.kind === "binary" && <span className={css.chip}>{t("web-main.preview.binary")}</span>}
        <PathActions path={p.path} local={local} />
      </div>
    </div>
  );
}

/** A file's card's head: its icon, name and age; under them its whole path, to be read and selected. */
function FileHead({ name, dir, path, time }: { name: string; dir: boolean; path: string; time?: string | null }) {
  const Icon = dir ? Folder : FileIcon;
  return (
    <div className={css.fileHead}>
      <div className={css.fileTitle}>
        <Icon size={14} className={css.fileTitleIcon} />
        <span className={css.title}>{dir ? `${name}/` : name}</span>
        {time && <span className={css.fileTime}>{time}</span>}
      </div>
      <span className={css.filePath}>{shownPath(path)}</span>
    </div>
  );
}
