// What a message names, while it is pointed at: a web link (its page's title and icon; a GitHub pull request's or
// issue's state, author, size and checks) and a file on the station by its path (a few of its lines, its picture, a
// directory's entries), each as a small card (Hover.css.ts, Cue's card language). Read from the station as soon as
// its link is pointed at (`link.preview`, `file.peek`), and kept: shown at once when opened again, and read again
// behind it once a minute old. A file's chip opens the file itself over the window (`file.open`, FilePreview).
import { createContext, useContext, useEffect, useState, type ReactElement, type ReactNode } from "react";
import { HoverCard } from "radix-ui";
import { core, prime, useTopic } from "./core/react.ts";
import type { Attachment } from "./core/shapes.ts";
import { FilePreview, fileSize, type LocalFile } from "./FilePreview.tsx";
import { Chat, Check, Copy, File as FileIcon, Folder, Web } from "@stillfail/ui/icons.tsx";
import { GitHubMark } from "@stillfail/ui/brands.tsx";
import { t } from "./i18n.ts";
import { useStation } from "./station.tsx";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import * as css from "./Hover.css.ts";
import { Bones, sampleWords } from "@stillfail/ui/waiting.tsx";
import { panelEdge } from "@stillfail/ui/styles/controls.css.ts";
import { PanelButton, PanelIconButton } from "./ui.tsx";
import { chipPath, pathIn, shownPath } from "./paths.ts";

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
export function Hover({ children, content, tile = false, warm, side = "bottom" }: { children: ReactElement; content: ReactNode; tile?: boolean; warm?: (() => void) | undefined; side?: "bottom" | "left" }) {
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
        <HoverCard.Content className={`${css.card}${tile ? ` ${css.cardTile}` : ""}`} data-instant={instant || undefined} side={side} align="start" sideOffset={6} collisionPadding={8}>
          {content}
        </HoverCard.Content>
      </HoverCard.Portal>
    </HoverCard.Root>
  );
}

// ---- web links ----

type Person = { login: string; avatar?: string };
/** When a pull request or an issue last changed, in words, as the core says it (the `linkPreview` topic). */
type Changed = { updatedAt?: { ago: string } };
type LinkPreview =
  | { kind: "none" }
  | { kind: "page"; url: string; title: string; description?: string; site?: string; icon?: string; image?: string }
  | {
      kind: "github_pull_request"; url: string; repository: string; number: number; title: string; state: "open" | "closed" | "merged" | "draft";
      author: Person | null; additions: number | null; deletions: number | null; changedFiles: number | null; updatedAt: number | null; time?: Changed;
      checks?: { passed: number; failed: number; pending: number };
    }
  | {
      kind: "github_issue"; url: string; repository: string; number: number; title: string; state: "open" | "completed" | "not_planned" | "closed";
      author: Person | null; comments: number | null; labels: string[]; updatedAt: number | null; time?: Changed;
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

/** A web link in a message, and its card: what the core reads of it (the `linkPreview` topic, kept), asked for as the
 *  pointer comes onto the link. */
export function LinkHover({ href, label, children, side }: { href: string; label: string; children: ReactElement;
  /** Beside it, where under it the card would cover a list's next rows (a chat's things'). */
  side?: "left" | undefined }) {
  const station = useStation();
  return <Hover side={side ?? "bottom"} tile={!RICH.test(href)} warm={() => prime({ topic: "linkPreview", station: station.address, url: href })} content={<LinkCard href={href} label={label} />}>{children}</Hover>;
}

/** A web link's address to copy, on its card (the user, 2026-10-29: 快捷操作放 hover 的卡片上; 丑: a row of words of its
 *  own under it, gone for a mark at the card's end): 已复制 a moment once copied, as a file's path (PathActions). */
function LinkCopy({ href }: { href: string }) {
  const toast = useToast();
  const [copied, setCopied] = useState(false);
  const copy = () => void navigator.clipboard.writeText(href).then(() => {
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }, (e: unknown) => toast(t("web-main.copyFailed", { error: failure(e) })));
  return <PanelIconButton className={css.copy} label={copied ? t("common.copied") : t("common.link.copy")} onClick={copy}>{copied ? <Check size={14} /> : <Copy size={14} />}</PanelIconButton>;
}

function LinkCard({ href, label }: { href: string; label: string }) {
  const station = useStation();
  const read = useTopic<LinkPreview | null>({ topic: "linkPreview", station: station.address, url: href });
  // (read first: the card it will be, made up, in its bones)
  if (read.value === undefined && read.error === null && RICH.test(href)) return <Bones>{/\/pull\//.test(href) ? <PullRequestCard preview={SAMPLE_PR} /> : <IssueCard preview={SAMPLE_ISSUE} />}</Bones>;
  const preview = read.value ?? null;
  if (preview?.kind === "github_pull_request") return <PullRequestCard preview={preview} copy={<LinkCopy href={href} />} />;
  if (preview?.kind === "github_issue") return <IssueCard preview={preview} copy={<LinkCopy href={href} />} />;
  const page = preview?.kind === "page" ? preview : null;
  const github = /^https:\/\/(?:[\w-]+\.)?github\.com\//.test(href);
  const tile = (
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
  // (its copy in its foot's end corner, as a file's card's is)
  const foot = <div className={`${css.fileFoot} ${panelEdge}`}><span className={css.actions}><LinkCopy href={href} /></span></div>;
  // A page's picture (its og:image, a video's frame) over the tile, as the page shows itself when shared.
  if (!page?.image) return <>{tile}{foot}</>;
  return (
    <>
      <div className={css.tileWithPicture}>
        <img className={css.picture} src={page.image} alt="" />
        {tile}
      </div>
      {foot}
    </>
  );
}

/** A pull request's and an issue's cards made up, for what shows while one is read (in their bones). */
const SAMPLE_PR: Extract<LinkPreview, { kind: "github_pull_request" }> = {
  kind: "github_pull_request", url: "", repository: sampleWords(9), number: 0, title: sampleWords(22), state: "open", author: { login: sampleWords(6) },
  additions: 0, deletions: 0, changedFiles: 0, updatedAt: null, time: { updatedAt: { ago: sampleWords(3) } },
};
const SAMPLE_ISSUE: Extract<LinkPreview, { kind: "github_issue" }> = {
  kind: "github_issue", url: "", repository: sampleWords(9), number: 0, title: sampleWords(22), state: "open", author: { login: sampleWords(6) },
  comments: 2, labels: [sampleWords(3)], updatedAt: null, time: { updatedAt: { ago: sampleWords(3) } },
};

const PR_STATE = { open: "web-main.preview.pr.open", merged: "web-main.preview.pr.merged", closed: "web-main.preview.pr.closed", draft: "web-main.preview.pr.draft" } as const;
const ISSUE_STATE = { open: "web-main.preview.issue.open", completed: "web-main.preview.issue.completed", not_planned: "web-main.preview.issue.notPlanned", closed: "web-main.preview.issue.closed" } as const;

function PersonFact({ person }: { person: Person | null }) {
  if (!person) return null;
  return <span className={css.person}>{person.avatar ? <img className={css.avatar} src={person.avatar} alt="" /> : <span className={css.avatar} />}{person.login}</span>;
}

function PullRequestCard({ preview: p, copy }: { preview: Extract<LinkPreview, { kind: "github_pull_request" }>; copy?: ReactNode }) {
  const checks = p.checks;
  return (
    <div className={css.rich}>
      <div className={css.meta}>
        <span className={css.state} data-state={p.state}><StateGlyph d={PR_GLYPH[p.state]} />{t(PR_STATE[p.state])}</span>
        <span className={css.ref}>{p.repository} #{p.number}</span>
        <span className={css.time}>{p.time?.updatedAt?.ago ?? null}</span>
      </div>
      <span className={css.title} title={p.title}>{p.title}</span>
      <div className={css.factsLine}>
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
      {copy}
      </div>
    </div>
  );
}

function IssueCard({ preview: p, copy }: { preview: Extract<LinkPreview, { kind: "github_issue" }>; copy?: ReactNode }) {
  return (
    <div className={css.rich}>
      <div className={css.meta}>
        <span className={css.state} data-state={p.state}><StateGlyph d={ISSUE_GLYPH[p.state]} />{t(ISSUE_STATE[p.state])}</span>
        <span className={css.ref}>{p.repository} #{p.number}</span>
        <span className={css.time}>{p.time?.updatedAt?.ago ?? null}</span>
      </div>
      <span className={css.title} title={p.title}>{p.title}</span>
      <div className={css.factsLine}>
      <div className={css.facts}>
        <PersonFact person={p.author} />
        {p.labels.map((l) => <span key={l} className={css.chip}>{l}</span>)}
        {p.comments !== null && p.comments > 0 && <span className={css.chip}>{t("web-main.preview.comments", { count: p.comments })}</span>}
      </div>
      {copy}
      </div>
    </div>
  );
}

// GitHub's own octicons (MIT, primer/octicons), so a pull request or an issue reads as it does on GitHub.
const PR_GLYPH = {
  open: "M1.5 3.25a2.25 2.25 0 1 1 3 2.122v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.25 2.25 0 0 1 1.5 3.25Zm5.677-.177L9.573.677A.25.25 0 0 1 10 .854V2.5h1A2.5 2.5 0 0 1 13.5 5v5.628a2.251 2.251 0 1 1-1.5 0V5a1 1 0 0 0-1-1h-1v1.646a.25.25 0 0 1-.427.177L7.177 3.427a.25.25 0 0 1 0-.354ZM3.75 2.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm0 9.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm8.25.75a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0Z",
  draft: "M3.25 1A2.25 2.25 0 0 1 4 5.372v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.251 2.251 0 0 1 3.25 1Zm9.5 14a2.25 2.25 0 1 1 0-4.5 2.25 2.25 0 0 1 0 4.5ZM2.5 3.25a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0ZM3.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm9.5 0a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5ZM14 7.5a1.25 1.25 0 1 1-2.5 0 1.25 1.25 0 0 1 2.5 0Zm0-4.25a1.25 1.25 0 1 1-2.5 0 1.25 1.25 0 0 1 2.5 0Z",
  merged: "M5.45 5.154A4.25 4.25 0 0 0 9.25 7.5h1.378a2.251 2.251 0 1 1 0 1.5H9.25A5.734 5.734 0 0 1 5 7.123v3.505a2.25 2.25 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.95-.218ZM4.25 13.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Zm8.5-4.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM5 3.25a.75.75 0 1 0 0 .005V3.25Z",
  closed: "M3.25 1A2.25 2.25 0 0 1 4 5.372v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.251 2.251 0 0 1 3.25 1Zm9.5 5.5a.75.75 0 0 1 .75.75v3.378a2.251 2.251 0 1 1-1.5 0V7.25a.75.75 0 0 1 .75-.75Zm-2.03-5.273a.75.75 0 0 1 1.06 0l.97.97.97-.97a.748.748 0 0 1 1.265.332.75.75 0 0 1-.205.729l-.97.97.97.97a.751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018l-.97-.97-.97.97a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734l.97-.97-.97-.97a.75.75 0 0 1 0-1.06ZM2.5 3.25a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0ZM3.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm9.5 0a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Z",
} as const;
const ISSUE_RING = "M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Z";
const ISSUE_DONE = "M11.28 6.78a.75.75 0 0 0-1.06-1.06L7.25 8.69 5.78 7.22a.75.75 0 0 0-1.06 1.06l2 2a.75.75 0 0 0 1.06 0l3.5-3.5ZM16 8A8 8 0 1 1 0 8a8 8 0 0 1 16 0Zm-1.5 0a6.5 6.5 0 1 0-13 0 6.5 6.5 0 0 0 13 0Z";
const ISSUE_GLYPH = {
  open: `M8 9.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z${ISSUE_RING}`,
  completed: ISSUE_DONE,
  closed: ISSUE_DONE,
  not_planned: `${ISSUE_RING}m9.78-2.22-5.5 5.5a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734l5.5-5.5a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042Z`,
} as const;

/** A state's glyph in its pill, drawn in the pill's colour. */
function StateGlyph({ d }: { d: string }) {
  return (
    <svg width="12" height="12" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
      <path d={d} />
    </svg>
  );
}

// ---- files named by their path ----

/**
 * The session whose files a message's paths name (its agent's, or another chat's agent that wrote here), and its
 * station's address when that is not this page's; null: none, they stay code.
 */
export const PathSession = createContext<{ key: string; station?: string } | null>(null);

/** What a file a message names is, as the core reads it (the `filePeek` topic), its last change in words. */
type Peek = {
  path: string; name: string; size: number; mtime: number; type: string;
  kind: "text" | "image" | "binary" | "dir";
  lines?: { start: number; text: string[]; at?: number };
  image?: { type: string; data: string };
  entries?: string[]; count?: number;
  time?: { mtime?: { ago: string } };
};
/** The `filePeek` topic of a file named in a session's message. */
const peekTopic = (station: string, session: string, path: string, line: number | null) =>
  ({ topic: "filePeek", station, key: session, path, ...(line !== null ? { line } : {}) }) as const;
type Opened = { name: string; path: string; type: string; size: number };

/**
 * A file a message names by its path: a chip with its icon and the path as written (chipPath; a directory's once its
 * card has read it as one, written with a `/` or not), its card on hover, the file itself on a click. Copied with the text around it, it is the path as written, whole (`data-copy`, copied below).
 */
export function FileRef({ path, line, children, words }: { path: string; line: number | null; children: ReactNode; /** A link's own words, shown instead of the file's name. */ words?: ReactNode }) {
  const owner = useContext(PathSession);
  const session = owner?.key ?? null;
  const here = useStation().address;
  const station = { address: owner?.station ?? here };
  const toast = useToast();
  const topic = session === null ? null : peekTopic(station.address, session, path, line);
  const [opened, setOpened] = useState<{ file: Attachment; local: LocalFile } | null>(null);
  useEffect(() => () => { if (opened) URL.revokeObjectURL(opened.local.url); }, [opened]);
  const name = path.replace(/\/$/, "").split("/").at(-1) || path;
  const peek = () => { if (topic) prime(topic); };
  // A name with no extension is as often a directory's as a file's: read at once, so the chip is drawn as what it is.
  const peeked = useTopic<Peek | null>(!path.endsWith("/") && !/\.[A-Za-z0-9]{1,10}$/.test(name) ? topic : null).value ?? null;
  if (session === null) return <code>{children}</code>;
  const dir = path.endsWith("/") || peeked?.kind === "dir";
  const whole = typeof children === "string" ? children.trim() : `${path}${line !== null ? `:${line}` : ""}`;
  const open = () => {
    if (dir) return;
    // Its bytes beside the answer.
    void core().callBytes("file.open", { station: station.address, key: session, path }).then((got) => {
      const f = got.value as Opened;
      const blob = new Blob(got.bytes ? [got.bytes as Uint8Array<ArrayBuffer>] : [], { type: f.type });
      setOpened({ file: { name: f.name, path: f.path, size: f.size }, local: { blob, url: URL.createObjectURL(blob) } });
    }, (e: unknown) => toast(t("web-main.preview.openFailed", { name, error: failure(e) })));
  };
  const Icon = dir ? Folder : FileIcon;
  return (
    <>
      <Hover warm={peek} content={<FileCard session={session} station={station.address} path={path} line={line} />}>
        <button type="button" className={css.fileChip} onClick={open} data-dir={dir || undefined} data-opens={!dir || undefined} data-copy={words === undefined ? whole : undefined}>
          <Icon size={12} className={css.fileChipIcon} />
          <span className={css.fileChipName}>{words ?? `${chipPath(path)}${dir && !path.endsWith("/") ? "/" : ""}`}</span>
          {line !== null && words === undefined && <span className={css.fileChipLine}>:{line}</span>}
        </button>
      </Hover>
      {opened && <FilePreview open onClose={() => setOpened(null)} sessionKey={session} file={opened.file} local={opened.local} />}
    </>
  );
}

/** A file's whole path, to copy. */
function PathActions({ path }: { path: string }) {
  const toast = useToast();
  const [copied, setCopied] = useState(false);
  const copy = () => void navigator.clipboard.writeText(path).then(() => {
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }, (e: unknown) => toast(t("web-main.copyFailed", { error: failure(e) })));
  return (
    <span className={css.actions}>
      <PanelButton tone="quiet" onClick={copy}>{copied ? <Check size={12} /> : <Copy size={12} />}{copied ? t("common.copied") : t("web-main.preview.copyPath")}</PanelButton>
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

function FileCard({ session, station, path, line }: { session: string; station: string; path: string; line: number | null }) {
  const read = useTopic<Peek | null>(peekTopic(station, session, path, line));
  // (read first: its card with its name and made-up lines, in its bones)
  if (read.value == null && read.error === null) return <Bones><FileShown p={samplePeek(path)} /></Bones>;
  if (read.value == null) return (
    <>
      <div className={css.rich}>
        <FileHead name={path.replace(/\/$/, "").split("/").at(-1) || path} dir={path.endsWith("/")} path={path} />
        <p className={css.note}>{read.error?.message}</p>
      </div>
      <div className={`${css.fileFoot} ${panelEdge}`}><PathActions path={path} /></div>
    </>
  );
  return <FileShown p={read.value} />;
}

/** A file named by `path` as its card shows it while it is read (in its bones): its name, a few lines made up. */
const samplePeek = (path: string): Peek => ({
  path, name: path.replace(/\/$/, "").split("/").at(-1) || path, size: 0, mtime: 0, type: "", kind: path.endsWith("/") ? "dir" : "text",
  lines: { start: 1, text: [18, 30, 24, 12, 27].map(sampleWords) }, entries: [8, 12, 6].map(sampleWords), time: { mtime: { ago: sampleWords(3) } },
});

/** A file's card (`p`): its head, its lines, picture or entries, and at its foot its size and what can be done with it. */
function FileShown({ p }: { p: Peek }) {
  const dir = p.kind === "dir";
  return (
    <>
      <div className={css.rich}>
        <FileHead name={`${p.name}${p.lines?.at ? `:${p.lines.at}` : ""}`} dir={dir} path={p.path} time={p.time?.mtime?.ago ?? null} />
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
      </div>
      <div className={`${css.fileFoot} ${panelEdge}`}>
        {dir && <span>{t("web-main.preview.items", { count: p.count ?? p.entries?.length ?? 0 })}</span>}
        {!dir && <span>{fileSize(p.size)}</span>}
        {p.kind === "binary" && <span>{t("web-main.preview.binary")}</span>}
        <PathActions path={p.path} />
      </div>
    </>
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
