// What a message names, while it is pointed at: a web link (its page's title and icon; a GitHub pull request's or
// issue's state, author, size and checks) and a file on the station by its path (a few of its lines, its picture, a
// directory's entries), each as a small card (Hover.css.ts, Cue's card language). Read from the station the first time
// a card opens (`link.preview`, `file.peek`), and kept, so it shows at once when opened again. A file's chip opens the
// file itself over the window (`file.open`, FilePreview).
import { createContext, useContext, useEffect, useState, type ReactElement, type ReactNode } from "react";
import { HoverCard } from "radix-ui";
import { stationApi, useStationCall } from "./api.ts";
import type { Attachment } from "./core/shapes.ts";
import { FilePreview, fileSize, type LocalFile } from "./FilePreview.tsx";
import { File as FileIcon, Web } from "./icons.tsx";
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
 * A card over `children` (the link, the chip) while it is pointed at: `content` is mounted only while the card shows,
 * so nothing is read until it first opens. `tile`: a narrower card.
 */
export function Hover({ children, content, tile = false }: { children: ReactElement; content: ReactNode; tile?: boolean }) {
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
      <HoverCard.Trigger asChild>{children}</HoverCard.Trigger>
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

// ---- what is read, kept ----

type Read<T> = { state: "loading" } | { state: "ready"; value: T } | { state: "error"; message: string };
/** What cards read, by what they read: kept a few minutes (a pull request's state moves), the latest 300. */
const kept = new Map<string, { at: number; value: Promise<unknown> }>();
const KEEP_MS = 3 * 60 * 1000;

function useRead<T>(key: string, read: () => Promise<T>): Read<T> {
  const [state, setState] = useState<{ key: string; read: Read<T> }>({ key, read: { state: "loading" } });
  useEffect(() => {
    let p = kept.get(key);
    if (!p || Date.now() - p.at > KEEP_MS) {
      p = { at: Date.now(), value: read() };
      kept.delete(key);
      kept.set(key, p);
      while (kept.size > 300) kept.delete(kept.keys().next().value!);
      p.value.catch(() => kept.delete(key));
    }
    let live = true;
    p.value.then((value) => { if (live) setState({ key, read: { state: "ready", value: value as T } }); },
      (e: unknown) => { if (live) setState({ key, read: { state: "error", message: failure(e) } }); });
    return () => { live = false; };
  }, [key]); // eslint-disable-line react-hooks/exhaustive-deps
  return state.key === key ? state.read : { state: "loading" };
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
  return <Hover tile={!RICH.test(href)} content={<LinkCard href={href} label={label} />}>{children}</Hover>;
}

function LinkCard({ href, label }: { href: string; label: string }) {
  const station = useStation();
  const api = stationApi(useStationCall(station.address));
  const read = useRead<LinkPreview>(`link ${station.address} ${href}`, () => api.linkPreview<LinkPreview>(href));
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

/** The session whose files a message's paths name (its agent's), for its file chips; null: none, they stay code. */
export const PathSession = createContext<string | null>(null);

type Peek = {
  path: string; name: string; size: number; mtime: number; type: string;
  kind: "text" | "image" | "binary" | "dir";
  lines?: { start: number; text: string[]; at?: number };
  image?: { type: string; data: string };
  entries?: string[]; count?: number;
};
type Opened = { name: string; path: string; type: string; size: number; bytes: string };

/** A file a message names by its path: a chip with its icon and name, its card on hover, the file itself on a click. */
export function FileRef({ path, line, children, words }: { path: string; line: number | null; children: ReactNode; /** A link's own words, shown instead of the file's name. */ words?: ReactNode }) {
  const session = useContext(PathSession);
  const station = useStation();
  const api = stationApi(useStationCall(station.address));
  const toast = useToast();
  const [opened, setOpened] = useState<{ file: Attachment; local: LocalFile } | null>(null);
  useEffect(() => () => { if (opened) URL.revokeObjectURL(opened.local.url); }, [opened]);
  if (session === null) return <code>{children}</code>;
  const dir = path.endsWith("/");
  const name = path.replace(/\/$/, "").split("/").at(-1) || path;
  const open = () => {
    if (dir) return;
    void api.fileOpen<Opened>(session, path).then((f) => {
      const bin = atob(f.bytes);
      const bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      const blob = new Blob([bytes], { type: f.type });
      setOpened({ file: { name: f.name, path: f.path, size: f.size }, local: { blob, url: URL.createObjectURL(blob) } });
    }, (e: unknown) => toast(t("web-main.preview.openFailed", { name, error: failure(e) })));
  };
  return (
    <>
      <Hover content={<FileCard session={session} path={path} line={line} />}>
        <button type="button" className={css.fileChip} onClick={open} data-dir={dir || undefined}>
          <FileIcon size={12} className={css.fileChipIcon} />
          <span className={css.fileChipName}>{words ?? (dir ? `${name}/` : name)}</span>
          {line !== null && words === undefined && <span className={css.fileChipLine}>:{line}</span>}
        </button>
      </Hover>
      {opened && <FilePreview open onClose={() => setOpened(null)} sessionKey={session} file={opened.file} local={opened.local} />}
    </>
  );
}

function FileCard({ session, path, line }: { session: string; path: string; line: number | null }) {
  const station = useStation();
  const api = stationApi(useStationCall(station.address));
  const read = useRead<Peek>(`peek ${station.address} ${session} ${path} ${line ?? ""}`, () => api.filePeek<Peek>(session, path, line));
  if (read.state === "loading") return <CardSkeleton />;
  if (read.state === "error") return (
    <div className={css.rich}>
      <div className={css.meta}><FileIcon size={12} /><span className={css.ref}>{path}</span></div>
      <p className={css.note}>{read.message}</p>
    </div>
  );
  const p = read.value;
  const folder = p.path.slice(0, p.path.length - p.name.length).replace(/\/$/, "");
  return (
    <div className={css.rich}>
      <div className={css.meta}>
        <span className={css.ref} title={p.path}><FileIcon size={12} className={css.refIcon} />{folder.split("/").slice(-3).join("/")}</span>
        <span className={css.time}>{ago(p.mtime)}</span>
      </div>
      <span className={css.title} title={p.path}>{p.kind === "dir" ? `${p.name}/` : p.name}{p.lines?.at ? `:${p.lines.at}` : ""}</span>
      {p.kind === "text" && p.lines && p.lines.text.length > 0 && (
        <pre className={css.lines}>
          {p.lines.text.map((l, i) => {
            const n = p.lines!.start + i;
            return <span key={n} className={css.line} data-at={n === p.lines!.at || undefined}><span className={css.lineNo}>{n}</span><span className={css.lineText}>{l || " "}</span></span>;
          })}
        </pre>
      )}
      {p.kind === "image" && p.image && <img className={css.thumb} src={`data:${p.image.type};base64,${p.image.data}`} alt="" />}
      {p.kind === "dir" && p.entries && (
        <ul className={css.entries}>
          {p.entries.map((e) => <li key={e}>{e}</li>)}
          {(p.count ?? 0) > p.entries.length && <li className={css.note}>{t("web-main.preview.more", { count: (p.count ?? 0) - p.entries.length })}</li>}
        </ul>
      )}
      <div className={css.facts}>
        {p.kind !== "dir" && <span className={css.chip}>{fileSize(p.size)}</span>}
        {p.kind === "binary" && <span className={css.chip}>{t("web-main.preview.binary")}</span>}
        {p.kind !== "dir" && <span>{t("web-main.preview.clickToOpen")}</span>}
      </div>
    </div>
  );
}
