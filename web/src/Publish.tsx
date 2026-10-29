// A chat shared as a picture (2026-10-26: 「静态分享功能改成分享图片吧，把内容直接渲染成一张长图」; the core's
// views/publish.ts reads what it would hold): the chat's name, its messages drawn as the chat's list draws them (its
// rows: 「渲染跟消息列表完全不一样」 of a picture that drew them apart), its attachments to tick, still.fail's mark at
// its foot; on the wide screen the dialog it is made in and, in its info, the public links made of it before pictures
// (docs/public-share.md: they still open). The phone's sheet is in mobile/Chat.tsx, with this same picture.
import { useEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { stationApi, useStationCall } from "./api.ts";
import type { ChatPublished, PublishFile, PublishPreview } from "./core/shapes.ts";
import { FileLook, FileTick, StaticMessage } from "./Chat.tsx";
import { Mark } from "./brand.tsx";
import { longPicture } from "./longPicture.ts";
import { Dialog as RDialog } from "radix-ui";
import { Button, Confirm, Time, Tip, WaitLine } from "./ui.tsx";
import { Close, ShieldCheck, Web } from "@stillfail/ui/icons.tsx";
import { ViewerBar } from "@stillfail/ui/viewer/ViewerBar.tsx";
import { useNarrow } from "./mobile/narrow.ts";
import { useBackClose } from "@stillfail/ui/backClose.ts";
import * as fpCss from "./FilePreview.css.ts";
import { failure, useAct, useToast } from "@stillfail/ui/toast.tsx";
import * as css from "./Publish.css.ts";
import * as chatCss from "./Chat.css.ts";
import { t } from "./i18n.ts";
import { PersonNamed } from "./components.tsx";
import * as pageCss from "@stillfail/ui/styles/page.css.ts";

/** A preview as asked (`chat.publishPreview`): being read, read, or why not. */
export type Previewed = { reading: true } | { ok: PublishPreview } | { error: string };

/**
 * What a snapshot of the chat would hold now, asked once as the panel opens (nothing is kept until it is published);
 * with `turn` (a message's n), that message's turn alone.
 */
export function usePublishPreview(station: string, thread: number, turn?: number): Previewed {
  const call = useStationCall(station);
  const [shown, setShown] = useState<Previewed>({ reading: true });
  useEffect(() => {
    let gone = false;
    stationApi(call).publishPreview(thread, turn).then((ok) => { if (!gone) setShown({ ok }); }, (e: unknown) => { if (!gone) setShown({ error: failure(e) }); });
    return () => { gone = true; };
  }, [call, thread, turn]);
  return shown;
}

/** Puts a link on the clipboard, saying so. */
export function useCopyLink(): (link: string) => void {
  const toast = useToast();
  return (link) => void navigator.clipboard.writeText(link).then(() => toast(t("common.link.copied")), (e: unknown) => toast(t("common.link.copyFailed", { error: failure(e) })));
}

/** Which attachments and messages the picture leaves out (all are in at first: an attachment by its `k`, a message by
 * messageKey), and how one is ticked or unticked. */
export type Ticking = { off: ReadonlySet<string>; toggle(k: string): void };

/** The attachments left out, one more ticked or unticked. */
export function useTicking(): Ticking {
  const [off, setOff] = useState<ReadonlySet<string>>(() => new Set());
  return { off, toggle: (k) => setOff((was) => { const next = new Set(was); if (next.has(k)) next.delete(k); else next.add(k); return next; }) };
}

/** What leaves message `seq` out of the picture in Ticking's `off`. */
const messageKey = (seq: number) => `m:${seq}`;

/** How many of the preview's messages go in the picture (none ticked: nothing to take). */
export function keptCount(preview: PublishPreview, ticking: Ticking): number {
  return preview.list.filter((m) => !ticking.off.has(messageKey(m.seq))).length;
}

/**
 * The picture as it would be, on the page's ground: the chat's name, its messages as the chat's list draws them (its
 * rows, as a message out of its chat is drawn: StaticMessage; the viewer's own in their bubbles at the end, an agent's
 * cards as cards; their heads in line with their pictures where the list has them so, `inline`: the phone's), still.fail's
 * mark and name at its foot. What is only for the one sharing it (each message's box to tick in a column before its
 * words, an attachment's ✕, one left out, how much was hidden in a message) is marked `data-shot-off`: the picture taken
 * (takePicture) leaves it out, and the room of that column (TICKS).
 */
export function PublishPicture({ preview, ticking, paper, inline = false }: { preview: PublishPreview; ticking: Ticking; paper: RefObject<HTMLDivElement | null>; inline?: boolean }) {
  const hidden = new Map(preview.messages.map((m) => [m.n, m.hiddenText]));
  return (
    <div ref={paper} className={css.paper} data-inline={inline || undefined}>
      {preview.title && <h2 className={css.title}>{preview.title}</h2>}
      <div className={`${css.list} ${chatCss.chatMessages} ${inline ? chatCss.inlineHeads : ""}`} data-inline={inline || undefined}>
        {preview.list.map((m) => {
          const off = ticking.off.has(messageKey(m.seq));
          return (
            <div key={m.seq} className={css.said} data-off={off || undefined} data-shot-off={off ? "" : undefined}>
              {/* Lit while its box is pointed at: a band across the picture, behind it. */}
              <span className={css.lit} data-shot-off="" />
              {/* Its box to tick, in a column of its own before the words (before the pictures out in the margin), on the
                  middle of its first line: its head's, or the viewer's own bubble's first line. */}
              <input type="checkbox" className={css.messageTick} data-bubble={bubbleFirst(m) || undefined} checked={!off} onChange={() => ticking.toggle(messageKey(m.seq))}
                aria-label={t("web-pages.chat.publish.message")} data-shot-off="" />
              {/* Its files each to tick, as it has them (by its n and where each is: the preview's `files`). */}
              <FileTick.Provider value={(file, sessionKey) => {
                const f = preview.files.find((x) => x.n === m.seq && x.file.path === file.path);
                return f ? <FileToggle file={f} sessionKey={sessionKey} ticking={ticking} /> : <FileLook sessionKey={sessionKey} file={file} />;
              }}>
                <StaticMessage message={m} keeper={m.by.agent ?? preview.files[0]?.file.owner ?? ""} />
              </FileTick.Provider>
              {hidden.get(m.seq) && <div className={css.note} data-mine={m.mine || undefined} data-shot-off=""><ShieldCheck size={13} />{hidden.get(m.seq)}</div>}
            </div>
          );
        })}
      </div>
      <div className={css.foot}><Mark size={16} />still.fail</div>
    </div>
  );
}

/**
 * The picture `paper` shows, taken whole however long it is (longPicture), at the screen's pixels: without what is
 * marked `data-shot-off`, its times said as dates (how long ago it was is not so for long).
 */
export function takePicture(paper: HTMLElement): Promise<Blob> {
  return longPicture(paper, {
    scale: Math.min(Math.max(window.devicePixelRatio || 1, 1), 3),
    background: getComputedStyle(paper).backgroundColor,
    // (the column of the messages' boxes to tick before its words: the page's, not the picture's)
    start: css.TICKS,
    // (the copy's nodes are another window's: not this one's Element)
    keep: (node) => node.nodeType !== Node.ELEMENT_NODE || !(node as Element).hasAttribute("data-shot-off"),
    copied: (node) => {
      if (node.nodeType !== Node.ELEMENT_NODE) return;
      const full = (node as Element).getAttribute("data-full");
      if ((node as Element).tagName === "TIME" && full) node.textContent = full;
    },
  });
}

/** Whether message `m` begins with the viewer's own words in their bubble (its box on the bubble's first line). */
function bubbleFirst(m: PublishPreview["list"][number]): boolean {
  return m.mine && m.text !== "" && m.quotes.length === 0 && m.attachments.length === 0;
}

/**
 * An attachment in the picture, as the chat shows it, with what waits to go in the composer has: a ✕ hung on its top
 * right corner takes it out (pressed anywhere on it too); out, it fades and its ✕ turns into a ＋ that puts it back.
 */
function FileToggle({ file: f, sessionKey, ticking }: { file: PublishFile; sessionKey: string | null; ticking: Ticking }) {
  const on = !ticking.off.has(f.k);
  return (
    <div className={css.file} data-off={!on || undefined} data-shot-off={!on ? "" : undefined} onClick={() => ticking.toggle(f.k)}>
      <div className={css.fileLook}><FileLook sessionKey={sessionKey ?? f.file.owner ?? null} file={f.file} /></div>
      <button type="button" className={css.hung} data-shot-off="" onClick={(e) => { e.stopPropagation(); ticking.toggle(f.k); }}
        aria-label={t(on ? "web-pages.chat.publish.leaveOut" : "web-pages.chat.publish.putBack")}><Close size={12} /></button>
    </div>
  );
}

/**
 * Hands the picture out on the wide screen: on the clipboard, copied whole. What a browser cannot put there (no
 * ClipboardItem) is saved as a file instead. True once it is there.
 */
export function useCopyPicture(): (paper: HTMLElement) => Promise<boolean> {
  const toast = useToast();
  return async (paper) => {
    try {
      if (typeof ClipboardItem === "undefined" || !navigator.clipboard?.write) {
        savePicture(await takePicture(paper));
        return true;
      }
      // (the picture as it is made: Safari takes a clipboard's item only within the press, as a promise)
      await navigator.clipboard.write([new ClipboardItem({ "image/png": takePicture(paper) })]);
      return true;
    } catch (e) {
      toast(t("web-pages.chat.shareImage.failed", { error: failure(e) }));
      return false;
    }
  };
}

/** The picture saved as a file (where the browser keeps downloads). */
export function savePicture(png: Blob): void {
  const url = URL.createObjectURL(png);
  const a = document.createElement("a");
  a.href = url;
  a.download = "still.fail.png";
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
}

/**
 * Shares the chat as a picture (wide screen), as a file is previewed (FilePreview.tsx): over the whole window, the
 * picture as it would be, its attachments ticked in their messages (all at first), under the bar a file opened has
 * (with a mouse on a wide screen across the top, back to the chat by its name; else floating, with close): 分享图片, how
 * much was hidden, and at its end the button 复制图片 in words (已复制 a moment after; 2026-10-26: 「pc 也用文字按钮，不要用
 * 图标」).
 */
export function PublishDialog({ station, thread, turn, onClose }: { station: string; thread: number; turn?: number; onClose(): void }) {
  const preview = usePublishPreview(station, thread, turn);
  const ticking = useTicking();
  const paper = useRef<HTMLDivElement | null>(null);
  const copy = useCopyPicture();
  const docked = !useNarrow();
  const [taking, setTaking] = useState(false);
  const [copied, setCopied] = useState(false);
  useBackClose(true, onClose);
  const p = "ok" in preview ? preview.ok : null;
  const go = () => {
    if (!paper.current || taking || !p || keptCount(p, ticking) === 0) return;
    setTaking(true);
    void copy(paper.current).then((done) => {
      if (done) {
        setCopied(true);
        setTimeout(() => setCopied(false), 1600);
      }
    }).finally(() => setTaking(false));
  };
  let body: ReactNode;
  if ("reading" in preview) body = <div className={fpCss.fpNote}><WaitLine text={t("web-pages.chat.publish.reading")} /></div>;
  else if ("error" in preview) body = <div className={fpCss.fpNote}><span className={css.problem} role="alert">{preview.error}</span></div>;
  else if (p!.list.length === 0) body = <div className={fpCss.fpNote}>{t("web-pages.chat.publish.empty")}</div>;
  else {
    body = (
      <div className={fpCss.fpPage}>
        <div className={css.page}><PublishPicture preview={p!} ticking={ticking} paper={paper} /></div>
      </div>
    );
  }
  const tool = (
    <Button variant="primary" busy={taking} disabled={!p || keptCount(p, ticking) === 0} onClick={go}>
      {copied ? t("common.copied") : t("desktop.contextMenu.copyImage")}
    </Button>
  );
  return (
    <RDialog.Root open onOpenChange={(o) => { if (!o) onClose(); }}>
      <RDialog.Portal>
        <RDialog.Content className={fpCss.fp} aria-describedby={undefined} data-awake="">
          {docked ? (
            <ViewerBar back={{ label: p?.title || t("common.close"), onClick: onClose }}
              name={<RDialog.Title asChild><span>{t("web-pages.chat.shareImage")}</span></RDialog.Title>}
              meta={p?.hiddenText} tools={tool} />
          ) : (
            <header className={fpCss.fpHead}>
              <div className={fpCss.fpTitle}>
                <RDialog.Title className={fpCss.fpName}>{t("web-pages.chat.shareImage")}</RDialog.Title>
                {p?.hiddenText && <span className={`${fpCss.fpMeta} ${css.headNote}`}><ShieldCheck size={14} />{p.hiddenText}</span>}
              </div>
              {tool}
              <Tip label={t("web-main.preview.closeKey")}><RDialog.Close className={pageCss.iconBtn} aria-label={t("common.close")}><Close size={18} /></RDialog.Close></Tip>
            </header>
          )}
          <div className={fpCss.fpBody}>{body}</div>
        </RDialog.Content>
      </RDialog.Portal>
    </RDialog.Root>
  );
}

/**
 * The chat's public links in its info (wide screen), made before pictures, under 「分享图片」: each with a link's mark
 * (the web's globe), when and by whom it was published, 复制, and 撤销 for those who may (who published it, an owner
 * or admin), which `onRevoke` asks about first.
 */
export function PublishedLinks({ links, onRevoke }: { links: ChatPublished[]; onRevoke(id: string): void }) {
  const copy = useCopyLink();
  return (
    <>
      {links.map((l) => (
        <div key={l.id} className={css.link}>
          <Web size={14} className={css.linkMark} />
          <span className={css.linkText}><Time stamp={l.time?.createdAt} /> · <PersonNamed name={l.byName} picture={l.byPicture} size={14} /></span>
          <button type="button" className={css.linkAction} onClick={() => copy(l.link)}>{t("common.copy")}</button>
          {l.mayRevoke && <button type="button" className={css.linkAction} onClick={() => onRevoke(l.id)}>{t("web-pages.chat.publish.revoke")}</button>}
        </div>
      ))}
    </>
  );
}

/** Asks before a public link is revoked (it cannot be undone); revoked, it is gone from the info at once. */
export function RevokeConfirm({ station, thread, id, onClose }: { station: string; thread: number; id: string | null; onClose(): void }) {
  const api = stationApi(useStationCall(station));
  const act = useAct();
  const revoke = () => {
    onClose();
    if (id !== null) act(api.unpublish(thread, id), t("web-pages.chat.publish.revokeVerb"));
  };
  return (
    <Confirm open={id !== null} title={t("web-pages.chat.publish.revokeAsk")} description={t("web-pages.chat.publish.revokeNote")}
      action={t("web-pages.chat.publish.revoke")} onConfirm={revoke} onClose={onClose} />
  );
}
