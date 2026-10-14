// A chat made public (docs/public-share.md; the core's views/publish.ts): what a snapshot would hold, drawn as the chat
// draws its messages (both screens), and on the wide screen the dialog that publishes it and the links in its info.
// The phone's sheet is in mobile/Chat.tsx, with these same messages.
import { useEffect, useState, type ReactNode } from "react";
import { stationApi, useStationCall, type Attachment } from "./api.ts";
import type { ChatPublished, PublishMessage, PublishPreview } from "./core/shapes.ts";
import { AgentAvatar, MessageName, OthersMessage, PersonWords } from "./Chat.tsx";
import { Prose } from "./Prose.tsx";
import { Avatar, Button, Confirm, Dialog, Loading, Switch, Time } from "./ui.tsx";
import { Copy, File, ShieldCheck } from "./icons.tsx";
import { useDoing } from "./doing.ts";
import { failure, useAct, useToast } from "./toast.tsx";
import * as css from "./Publish.css.ts";
import * as chatCss from "./Chat.css.ts";
import * as chatCss2 from "./styles/chat.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import { t } from "./i18n.ts";

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

/** The attachments a preview's panel publishes: all but those unticked and those too big; whether they are too big together. */
export function tickedOf(preview: PublishPreview, off: ReadonlySet<string>): { files: string[]; over: boolean } {
  const ticked = preview.files.filter((f) => !f.over && !off.has(f.k));
  return { files: ticked.map((f) => f.k), over: ticked.reduce((n, f) => n + f.size, 0) > preview.most };
}

/** Puts a link on the clipboard, saying so. */
export function useCopyLink(): (link: string) => void {
  const toast = useToast();
  return (link) => void navigator.clipboard.writeText(link).then(() => toast(t("common.link.copied")), (e: unknown) => toast(t("common.link.copyFailed", { error: failure(e) })));
}

/**
 * A snapshot's messages as the chat draws others' (each one's head in line with its avatar, the phone's way): an
 * agent's in Markdown, a person's as written; under one with something hidden, how many. Its attachments are names
 * only (the preview has no file to show): one its words place is a chip there, the rest a line under it. `whole`: all
 * of it, in what scrolls around it (the phone's sheet), rather than a box of its own that scrolls.
 */
export function PublishMessages({ messages, whole = false }: { messages: PublishMessage[]; whole?: boolean }) {
  return (
    <div className={`${css.preview} ${chatCss.inlineHeads}`} data-whole={whole || undefined}>
      {messages.map((m) => <PreviewMessage key={m.n} message={m} />)}
    </div>
  );
}

function PreviewMessage({ message: m }: { message: PublishMessage }) {
  const named = new Map(m.files.map((name) => [name, { name, path: "", size: 0 } satisfies Attachment]));
  const placed = m.agent ? m.files.filter((name) => m.text.includes(`](${name})`) || m.text.includes(`](${encodeURI(name)})`)) : [];
  const under = m.files.filter((name) => !placed.includes(name));
  const avatar = m.agent
    ? <AgentAvatar maker={null} runtime={null} />
    : <span className={chatCss2.msgAvatar}><Avatar id={m.author} name={m.author} size={18} /></span>;
  return (
    <OthersMessage avatar={avatar} name={<MessageName>{m.author}</MessageName>} time={m.time?.createdAt}>
      {m.agent
        ? <div className={conversationCss.markdown}><Prose files={named} file={(f) => <FileChip name={f.name} />}>{m.text}</Prose></div>
        : <PersonWords text={m.text} />}
      {under.length > 0 && <div className={css.note}>{under.map((name) => <FileChip key={name} name={name} />)}</div>}
      {m.hiddenText && <div className={css.note}><ShieldCheck size={13} />{m.hiddenText}</div>}
    </OthersMessage>
  );
}

function FileChip({ name }: { name: string }) {
  return <span className={css.fileChip}><File size={12} />{name}</span>;
}

/**
 * Publishes the chat (wide screen): what it would hold, the attachments to tick (all at first; one too big is shown,
 * never ticked), who can read it, 「发布」. Published, its link with a way to copy it; the info lists it from then on.
 */
export function PublishDialog({ station, thread, onClose }: { station: string; thread: number; onClose(): void }) {
  const api = stationApi(useStationCall(station));
  const toast = useToast();
  const copy = useCopyLink();
  const preview = usePublishPreview(station, thread);
  const [off, setOff] = useState<ReadonlySet<string>>(() => new Set());
  const [made, setMade] = useState<ChatPublished | null>(null);
  const publishing = useDoing("chat.publish", { station, thread });
  const p = "ok" in preview ? preview.ok : null;
  const ticked = p ? tickedOf(p, off) : null;
  const toggle = (k: string) => setOff((was) => { const next = new Set(was); if (next.has(k)) next.delete(k); else next.add(k); return next; });
  const go = () => {
    if (!p || !ticked) return;
    api.publish(thread, p.upto, ticked.files).then(setMade, (e: unknown) => toast(t("web-main.act.failed", { what: t("web-pages.chat.publish.verb"), error: failure(e) })));
  };
  let body: ReactNode;
  if (made) body = <span className={css.madeLink} title={made.link}>{made.link}</span>; else if ("reading" in preview) body = <Loading label={t("web-pages.chat.publish.reading")} fill={false} />;
  else if ("error" in preview) body = <p className={css.problem} role="alert">{preview.error}</p>;
  else if (p!.messages.length === 0) body = <p className={css.note}>{t("web-pages.chat.publish.empty")}</p>;
  else {
    body = (
      <>
        <PublishMessages messages={p!.messages} />
        {p!.files.length > 0 && (
          <ul className={css.files} aria-label={t("web-pages.chat.publish.files")}>
            {p!.files.map((f) => (
              <li key={f.k} className={css.fileRow} data-off={f.over || undefined}>
                <File size={14} />
                <span className={css.fileName}>{f.name}</span>
                <span className={css.fileSize}>{f.over ? t("web-pages.chat.publish.tooBig") : f.sizeText}</span>
                <Switch small checked={!f.over && !off.has(f.k)} disabled={f.over} onChange={() => toggle(f.k)} label={f.name} />
              </li>
            ))}
          </ul>
        )}
        {ticked!.over && <p className={css.problem} role="alert">{t("web-pages.chat.publish.overTotal", { most: p!.mostText })}</p>}
      </>
    );
  }
  return (
    <Dialog open wide onClose={onClose} title={made ? t("web-pages.chat.publish.made") : t("web-pages.chat.publish")} description={t("web-pages.chat.publish.lead")}
      footer={made
        ? <>
            <Button variant="ghost" onClick={onClose}>{t("common.done")}</Button>
            <Button variant="primary" icon={Copy} onClick={() => copy(made.link)}>{t("web-pages.chat.publish.copyLink")}</Button>
          </>
        : <>
            {p?.hiddenText && <span className={css.footNote}><ShieldCheck size={14} />{p.hiddenText}</span>}
            <Button variant="primary" busy={publishing} disabled={!p || p.messages.length === 0 || ticked!.over} onClick={go}>{t("web-pages.chat.publish.go")}</Button>
          </>}>
      {body}
    </Dialog>
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
