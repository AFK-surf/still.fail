// What was said in a chat besides words (the core's `chatThings` view, client/core-ts/src/things.ts): its pictures and
// videos, its other files, the web links in its messages and the pull requests among them, each once and the latest
// first. The same on the wide screen (a tab beside the chat, pages/ChatPage.tsx) and the phone (a sheet,
// mobile/Chat.tsx): the kinds it has to choose from, a field finding among the chosen kind's by their words, then that
// kind's: the pictures a grid, the rest a row each. A picture or a file opens in the preview (an image stepping through
// the chat's), a link or a pull request in the browser; 在对话中查看 at a row's end (a picture's menu) goes to the
// message it was last said in. The chat's info names its pull requests itself (ThingsPulls).
import { useState, type ReactNode } from "react";
import { ContextMenu } from "radix-ui";
import { useTopic } from "./core/react.ts";
import type { ChatThing, ChatThingsView } from "./core/shapes.ts";
import { FilePreview, fileSize, Gallery, kindOf, useFileShown, useVideoStill } from "./FilePreview.tsx";
import { Empty, IconButton, Time } from "./ui.tsx";
import { Segmented } from "@stillfail/ui/parts.tsx";
import { Spinner, Waiting } from "@stillfail/ui/waiting.tsx";
import { Chat, Copy, File, Link, PlayMark } from "@stillfail/ui/icons.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import { LinkHover } from "./Peeks.tsx";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import { t } from "./i18n.ts";
import * as css from "./Things.css.ts";

const KINDS = ["media", "files", "links", "pulls"] as const;
type Kind = (typeof KINDS)[number];

/** A chat's things, as the core has them now (those with the words `q`). */
export function useChatThings(station: string, thread: number | null, q = ""): ChatThingsView | undefined {
  return useTopic<ChatThingsView>(thread === null ? null : { topic: "chatThings", station, thread, ...(q.trim() ? { q } : {}) }).value;
}

/** What a pull request is called: its title once its card is read, else its repository and number. */
export function pullTitle(p: ChatThing): string {
  return p.title || `${p.repository ?? ""} #${p.number ?? ""}`;
}

/** Whether something is wrong with a pull request: closed without being merged, a check failed (its mark in red). */
const wrong = (p: ChatThing) => p.state === "closed" || (p.checks?.failed ?? 0) > 0;

/** A pull request's mark: GitHub's octicon for how it stands, grey while it stands as it should, red where something is wrong. */
export function PullMark({ pull, size = 14 }: { pull: ChatThing; size?: number }) {
  return (
    <svg className={css.pullMark} data-wrong={wrong(pull) || undefined} width={size} height={size} viewBox="0 0 16 16" aria-hidden="true">
      <path d={PULL_GLYPH[pull.state ?? "open"] ?? PULL_GLYPH.open} fill="currentColor" />
    </svg>
  );
}

const STATE_KEY: Record<string, string> = { merged: "web-main.preview.pr.merged", closed: "web-main.preview.pr.closed", draft: "web-main.preview.pr.draft", open: "web-main.preview.pr.open" };

export function Things({ station, thread, keeper, onShow, initial }: { station: string; thread: number;
  /** The session that keeps the chat's files where a file does not say. */
  keeper: string;
  /** 在对话中查看: the chat shown at message `seq`. */
  onShow(seq: number): void;
  /** The kind shown first (the info's 全部 N 个 PR). */
  initial?: Kind | undefined }) {
  const [q, setQ] = useState("");
  const [chosen, choose] = useState<Kind | null>(initial ?? null);
  const view = useChatThings(station, thread, q);
  const has = view ? KINDS.filter((k) => view.counts[k] > 0) : [];
  if (!view || (has.length === 0 && !view.whole)) return <Waiting fill sample={<div className={css.things}><SampleRows /></div>} />;
  if (has.length === 0) return <Empty><p>{t("web-main.things.none")}</p></Empty>;
  const kind = chosen !== null && has.includes(chosen) ? chosen : has[0]!;
  const shown = view[kind];
  return (
    <Gallery.Provider value={{ chat: { thread } }}>
      <div className={css.things}>
        <div className={css.thingsHead}>
          {has.length > 1
            ? <Segmented<Kind> label={t("web-main.things.title")} value={kind} onChange={(k) => choose(k)} options={has.map((k) => ({ value: k, label: `${t(`web-main.things.${k}`)} ${view.counts[k]}` }))} />
            : <span className={css.thingsKind}>{t(`web-main.things.${kind}`)}</span>}
          <input className={controlsCss.input} type="search" value={q} placeholder={t("web-main.things.find")} aria-label={t("web-main.things.find")} onChange={(e) => setQ(e.target.value)} />
        </div>
        {shown.length === 0 && <p className={css.thingsNone}>{t("web-main.find.none")}</p>}
        {kind === "media"
          ? <div className={css.thingsGrid}>{shown.map((m) => <MediaTile key={m.key} thing={m} keeper={keeper} onShow={onShow} />)}</div>
          : <div className={css.thingsRows}>{shown.map((m) => <ThingRow key={m.key} kind={kind} thing={m} keeper={keeper} onShow={onShow} />)}</div>}
        {!view.whole && <div className={css.thingsMore}><Spinner /></div>}
      </div>
    </Gallery.Provider>
  );
}

/** A picture or a video, a square tile covered by its picture (a video's still, its play mark over it); pressed, the preview. */
function MediaTile({ thing, keeper, onShow }: { thing: ChatThing; keeper: string; onShow(seq: number): void }) {
  const file = thing.file!;
  const owner = file.owner ?? keeper;
  const video = kindOf(file.name).kind === "video";
  const picture = useFileShown(owner, file, !video, true);
  const still = useVideoStill(owner, file, video);
  const [open, setOpen] = useState(false);
  const url = video ? still.url : picture.url;
  return (
    <>
      <ThingMenu thing={thing} onShow={onShow}>
        <button type="button" className={css.tile} onClick={() => setOpen(true)} aria-label={t(video ? "web-main.file.play" : "web-main.file.view", { name: file.name })}>
          {url && (video && !still.poster ? <video className={css.tilePicture} src={url} muted playsInline preload="auto" aria-hidden="true" /> : <img className={css.tilePicture} src={url} alt="" />)}
          {video && <span className={css.tilePlay} aria-hidden="true"><PlayMark size={22} /></span>}
        </button>
      </ThingMenu>
      <FilePreview open={open} onClose={() => setOpen(false)} sessionKey={owner} file={file} />
    </>
  );
}

/** A file, a link or a pull request, a row: its mark, what it is called and what else is known of it; 在对话中查看 at its end. */
function ThingRow({ kind, thing, keeper, onShow }: { kind: Kind; thing: ChatThing; keeper: string; onShow(seq: number): void }) {
  const [open, setOpen] = useState(false);
  const toast = useToast();
  const times = thing.count && thing.count > 1 ? `×${thing.count}` : "";
  const [name, meta, mark] = kind === "files"
    ? [thing.file!.name, [fileSize(thing.file!.size), thing.by], <File size={16} />]
    : kind === "pulls"
      ? [pullTitle(thing), [thing.state && thing.state !== "open" ? t(STATE_KEY[thing.state] ?? STATE_KEY.open!) : "", thing.checks?.failed ? t("web-main.preview.checks.failed", { count: thing.checks.failed }) : "", `${thing.repository} #${thing.number}`], <PullMark pull={thing} size={16} />]
      : [thing.title || thing.site || "", [thing.title ? thing.site ?? "" : "", times], <Link size={16} />];
  const when = kind === "pulls" ? thing.time?.updatedAt ?? thing.time?.createdAt : thing.time?.createdAt;
  const words = (
    <>
      <span className={css.rowMark} aria-hidden="true">{mark}</span>
      <span className={css.rowWords}>
        <span className={css.rowName}>{name}</span>
        <span className={css.rowMeta}>{meta.filter((s) => s !== "").join(" · ")}{when && <>{meta.some((s) => s !== "") && " · "}<Time stamp={when} /></>}</span>
      </span>
    </>
  );
  return (
    <ThingMenu thing={thing} onShow={onShow}>
      <div className={css.row}>
        {kind === "files"
          ? <button type="button" className={css.rowOpen} onClick={() => setOpen(true)}>{words}</button>
          // (pointed at, the link's card: a pull request's as a message's link to it shows it)
        : <LinkHover href={thing.url!} label={name} side="left"><a className={css.rowOpen} href={thing.url} target="_blank" rel="noopener noreferrer">{words}</a></LinkHover>}
        {/* What is done with it at once: a link's copied, then 在对话中查看. */}
      {thing.url && <IconButton label={t("common.link.copy")} icon={Copy} onClick={() => void navigator.clipboard.writeText(thing.url!).then(() => toast(t("common.link.copied")))} />}
      <IconButton label={t("web-main.things.show")} icon={Chat} onClick={() => onShow(thing.seq)} />
        {kind === "files" && <FilePreview open={open} onClose={() => setOpen(false)} sessionKey={thing.file!.owner ?? keeper} file={thing.file!} />}
      </div>
    </ThingMenu>
  );
}

/** What a thing offers right clicked or held, as the app's: 在对话中查看, and a link's (a pull request's) copy. */
export function ThingMenu({ thing, onShow, children }: { thing: ChatThing; onShow(seq: number): void; children: ReactNode }) {
  const toast = useToast();
  const copy = (url: string) => void navigator.clipboard.writeText(url).then(() => toast(t("common.link.copied")));
  return (
    <ContextMenu.Root modal={false}>
      <ContextMenu.Trigger asChild>{children}</ContextMenu.Trigger>
      <ContextMenu.Portal>
        <ContextMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList}`} collisionPadding={8} onCloseAutoFocus={(e) => e.preventDefault()}>
          <ContextMenu.Item className={controlsCss.menuItem} onSelect={() => onShow(thing.seq)}><Chat size={14} />{t("web-main.things.show")}</ContextMenu.Item>
          {thing.url && <ContextMenu.Item className={controlsCss.menuItem} onSelect={() => copy(thing.url!)}><Copy size={14} />{t("common.link.copy")}</ContextMenu.Item>}
        </ContextMenu.Content>
      </ContextMenu.Portal>
    </ContextMenu.Root>
  );
}

/** Rows made up, for what the page shows while they are read (in their bones). */
function SampleRows() {
  return (
    <div className={css.thingsRows}>
      {[18, 24, 14, 20, 16].map((n) => (
        <div key={n} className={css.row}><span className={css.rowOpen}><span className={css.rowMark}><Link size={16} /></span>
          <span className={css.rowWords}><span className={css.rowName}>{"x".repeat(n)}</span><span className={css.rowMeta}>{"x".repeat(10)}</span></span></span></div>
      ))}
    </div>
  );
}

/** GitHub's octicons for a pull request's state (Peeks.tsx PR_GLYPH). */
const PULL_GLYPH: Record<string, string> = {
  draft: "M3.25 1A2.25 2.25 0 0 1 4 5.372v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.251 2.251 0 0 1 3.25 1Zm9.5 14a2.25 2.25 0 1 1 0-4.5 2.25 2.25 0 0 1 0 4.5ZM2.5 3.25a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0ZM3.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm9.5 0a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5ZM14 7.5a1.25 1.25 0 1 1-2.5 0 1.25 1.25 0 0 1 2.5 0Zm0-4.25a1.25 1.25 0 1 1-2.5 0 1.25 1.25 0 0 1 2.5 0Z",
  merged: "M5.45 5.154A4.25 4.25 0 0 0 9.25 7.5h1.378a2.251 2.251 0 1 1 0 1.5H9.25A5.734 5.734 0 0 1 5 7.123v3.505a2.25 2.25 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.95-.218ZM4.25 13.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Zm8.5-4.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM5 3.25a.75.75 0 1 0 0 .005V3.25Z",
  closed: "M3.25 1A2.25 2.25 0 0 1 4 5.372v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.251 2.251 0 0 1 3.25 1Zm9.5 5.5a.75.75 0 0 1 .75.75v3.378a2.251 2.251 0 1 1-1.5 0V7.25a.75.75 0 0 1 .75-.75Zm-2.03-5.273a.75.75 0 0 1 1.06 0l.97.97.97-.97a.748.748 0 0 1 1.265.332.75.75 0 0 1-.205.729l-.97.97.97.97a.751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018l-.97-.97-.97.97a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734l.97-.97-.97-.97a.75.75 0 0 1 0-1.06ZM2.5 3.25a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0ZM3.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm9.5 0a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Z",
  open: "M1.5 3.25a2.25 2.25 0 1 1 3 2.122v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.25 2.25 0 0 1 1.5 3.25Zm5.677-.177L9.573.677A.25.25 0 0 1 10 .854V2.5h1A2.5 2.5 0 0 1 13.5 5v5.628a2.251 2.251 0 1 1-1.5 0V5a1 1 0 0 0-1-1h-1v1.646a.25.25 0 0 1-.427.177L7.177 3.427a.25.25 0 0 1 0-.354ZM3.75 2.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm0 9.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm8.25.75a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0Z",
};
