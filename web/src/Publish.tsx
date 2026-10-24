// A chat made public (docs/public-share.md; the core's views/publish.ts): what a snapshot would hold, drawn as the chat
// draws its messages (both screens), and on the wide screen the dialog that publishes it and the links in its info.
// The phone's sheet is in mobile/Chat.tsx, with these same messages.
import { useEffect, useState, type ReactNode } from "react";
import { stationApi, useStationCall } from "./api.ts";
import type { ChatPublished, PublishFile, PublishMessage, PublishPreview } from "./core/shapes.ts";
import { AgentAvatar, FileLook, MessageName, OthersMessage, PersonWords } from "./Chat.tsx";
import { Prose } from "./Prose.tsx";
import { Dialog as RDialog } from "radix-ui";
import { Avatar, Button, Confirm, Dialog, Time, Tip, WaitLine } from "./ui.tsx";
import { Close, Copy, ShieldCheck } from "@stillfail/ui/icons.tsx";
import { useBackClose } from "@stillfail/ui/backClose.ts";
import * as fpCss from "./FilePreview.css.ts";
import { useDoing } from "./doing.ts";
import { failure, useAct, useToast } from "@stillfail/ui/toast.tsx";
import * as css from "./Publish.css.ts";
import * as chatCss from "./Chat.css.ts";
import * as chatCss2 from "./styles/chat.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import { t } from "./i18n.ts";
import * as pageCss from "@stillfail/ui/styles/page.css.ts";

/** A preview as asked (`chat.publishPreview`): being read, read, or why not. */
export type Previewed = { reading: true } | { ok: PublishPreview } | { error: string };

/** What a snapshot of the chat would hold now, asked once as the panel opens (nothing is kept until it is published). */
export function usePublishPreview(station: string, thread: number): Previewed {
  const call = useStationCall(station);
  const [shown, setShown] = useState<Previewed>({ reading: true });
  useEffect(() => {
    let gone = false;
    stationApi(call).publishPreview(thread).then((ok) => { if (!gone) setShown({ ok }); }, (e: unknown) => { if (!gone) setShown({ error: failure(e) }); });
    return () => { gone = true; };
  }, [call, thread]);
  return shown;
}

/** The attachments a preview's panel publishes: all but those unticked. */
export function tickedOf(preview: PublishPreview, off: ReadonlySet<string>): string[] {
  return preview.files.filter((f) => !off.has(f.k)).map((f) => f.k);
}

/** Puts a link on the clipboard, saying so. */
export function useCopyLink(): (link: string) => void {
  const toast = useToast();
  return (link) => void navigator.clipboard.writeText(link).then(() => toast(t("common.link.copied")), (e: unknown) => toast(t("common.link.copyFailed", { error: failure(e) })));
}

/** Which attachments a panel leaves out (all are in at first), and how one is ticked or unticked. */
export type Ticking = { off: ReadonlySet<string>; toggle(k: string): void };

/** The attachments left out, one more ticked or unticked. */
export function useTicking(): Ticking {
  const [off, setOff] = useState<ReadonlySet<string>>(() => new Set());
  return { off, toggle: (k) => setOff((was) => { const next = new Set(was); if (next.has(k)) next.delete(k); else next.add(k); return next; }) };
}

/**
 * A snapshot's messages as the chat draws others' (each one's head in line with its avatar, the phone's way): an
 * agent's in Markdown, a person's as written; under one with something hidden, how many. Its attachments are where the
 * message has them, drawn as the chat draws them, each ticked to go with it or not: one its words place is there, the
 * rest under it. `whole`: all of it, in what scrolls around it (the phone's
 * sheet), rather than a box of its own that scrolls.
 */
export function PublishMessages({ messages, ticking, whole = false }: { messages: PublishMessage[]; ticking: Ticking; whole?: boolean }) {
  return (
    <div className={`${css.preview} ${chatCss.inlineHeads}`} data-whole={whole || undefined}>
      {messages.map((m) => <PreviewMessage key={m.n} message={m} ticking={ticking} />)}
    </div>
  );
}

function PreviewMessage({ message: m, ticking }: { message: PublishMessage; ticking: Ticking }) {
  const named = new Map(m.files.map((f) => [f.name, f.file]));
  // Which of them its words place is the core's (placed.ts): drawn there, the rest under it.
  const placed = m.files.filter((f) => m.placed?.includes(f.name) ?? false);
  const under = m.files.filter((f) => !placed.includes(f));
  const toggle = (name: string) => {
    const f = m.files.find((x) => x.name === name);
    return f ? <FileToggle file={f} ticking={ticking} /> : null;
  };
  // As the chat draws them (Chat.tsx MessageAvatar): an agent by its maker's mark, a person by their picture.
  const avatar = m.agent
    ? <AgentAvatar maker={m.maker ?? null} runtime={m.runtime === "claude" || m.runtime === "codex" || m.runtime === "dsh" || m.runtime === "grok" || m.runtime === "cursor" || m.runtime === "devin" ? m.runtime : null} />
    : m.picture
      ? <img className={chatCss2.msgAvatar} src={m.picture} alt="" width={18} height={18} referrerPolicy="no-referrer" />
      : <span className={chatCss2.msgAvatar}><Avatar id={m.author} name={m.author} size={18} /></span>;
  return (
    <OthersMessage avatar={avatar} name={<MessageName>{m.author}</MessageName>} time={m.time?.createdAt}>
      {m.agent
        ? <div className={conversationCss.markdown}><Prose files={named} file={(f) => toggle(f.name)}>{m.text}</Prose></div>
        : <PersonWords text={m.text} />}
      {under.length > 0 && <div className={css.files}>{under.map((f) => <FileToggle key={f.k} file={f} ticking={ticking} />)}</div>}
      {m.hiddenText && <div className={css.note}><ShieldCheck size={13} />{m.hiddenText}</div>}
    </OthersMessage>
  );
}

/** An attachment in the preview, as the chat shows it: ticked (its box in the corner), it goes with the snapshot; unticked, it fades. */
function FileToggle({ file: f, ticking }: { file: PublishFile; ticking: Ticking }) {
  const on = !ticking.off.has(f.k);
  return (
    <label className={css.file} data-off={!on || undefined}>
      <FileLook sessionKey={f.file.owner ?? null} file={f.file} />
      <input type="checkbox" className={css.tick} checked={on} onChange={() => ticking.toggle(f.k)} aria-label={f.name} />
    </label>
  );
}

/**
 * Publishes the chat (wide screen), as a file is previewed (FilePreview.tsx): over the whole window, what it would hold
 * laid out as the chat lays it out, its attachments ticked in their messages (all at first), a bar floating on top with
 * how much was hidden, 「发布」 and close. Published, a small dialog has its link to copy; the info lists it from then on.
 */
export function PublishDialog({ station, thread, onClose }: { station: string; thread: number; onClose(): void }) {
  const api = stationApi(useStationCall(station));
  const toast = useToast();
  const copy = useCopyLink();
  const preview = usePublishPreview(station, thread);
  const ticking = useTicking();
  const [made, setMade] = useState<ChatPublished | null>(null);
  const publishing = useDoing("chat.publish", { station, thread });
  useBackClose(made === null, onClose);
  const p = "ok" in preview ? preview.ok : null;
  const go = () => {
    if (!p) return;
    api.publish(thread, p.upto, tickedOf(p, ticking.off)).then(setMade, (e: unknown) => toast(t("web-main.act.failed", { what: t("web-pages.chat.publish.verb"), error: failure(e) })));
  };
  if (made) {
    return (
      <Dialog open wide onClose={onClose} title={t("web-pages.chat.publish.made")} description={t("web-pages.chat.publish.lead")}
        footer={<>
          <Button variant="ghost" onClick={onClose}>{t("common.done")}</Button>
          <Button variant="primary" icon={Copy} onClick={() => copy(made.link)}>{t("web-pages.chat.publish.copyLink")}</Button>
        </>}>
        <span className={css.madeLink} title={made.link}>{made.link}</span>
      </Dialog>
    );
  }
  let body: ReactNode;
  if ("reading" in preview) body = <div className={fpCss.fpNote}><WaitLine text={t("web-pages.chat.publish.reading")} /></div>;
  else if ("error" in preview) body = <div className={fpCss.fpNote}><span className={css.problem} role="alert">{preview.error}</span></div>;
  else if (p!.messages.length === 0) body = <div className={fpCss.fpNote}>{t("web-pages.chat.publish.empty")}</div>;
  else {
    body = (
      <div className={fpCss.fpPage}>
        <div className={css.page}>
          <p className={css.lead}>{t("web-pages.chat.publish.lead")}</p>
          <PublishMessages messages={p!.messages} ticking={ticking} whole />
        </div>
      </div>
    );
  }
  return (
    <RDialog.Root open onOpenChange={(o) => { if (!o) onClose(); }}>
      <RDialog.Portal>
        <RDialog.Content className={fpCss.fp} aria-describedby={undefined} data-awake="">
          <header className={`${fpCss.fpHead} ${css.head}`}>
            <div className={fpCss.fpTitle}>
              <RDialog.Title className={fpCss.fpName}>{t("web-pages.chat.publish")}</RDialog.Title>
              {p?.hiddenText && <span className={`${fpCss.fpMeta} ${css.headNote}`}><ShieldCheck size={14} />{p.hiddenText}</span>}
            </div>
            <Button variant="primary" busy={publishing} disabled={!p || p.messages.length === 0} onClick={go}>{t("web-pages.chat.publish.go")}</Button>
            <Tip label={t("web-main.preview.closeKey")}><RDialog.Close className={pageCss.iconBtn} aria-label={t("common.close")}><Close size={18} /></RDialog.Close></Tip>
          </header>
          <div className={fpCss.fpBody}>{body}</div>
        </RDialog.Content>
      </RDialog.Portal>
    </RDialog.Root>
  );
}

/**
 * The chat's public links in its info (wide screen), under 「公开分享」: each when and by whom it was published, 复制, and
 * 撤销 for those who may (who published it, an owner or admin), which `onRevoke` asks about first.
 */
export function PublishedLinks({ links, onRevoke }: { links: ChatPublished[]; onRevoke(id: string): void }) {
  const copy = useCopyLink();
  return (
    <>
      {links.map((l) => (
        <div key={l.id} className={css.link}>
          <span className={css.linkText}><Time stamp={l.time?.createdAt} /> · {l.byName}</span>
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
