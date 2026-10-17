// What another app shares, on a wide screen (shareIn.ts; docs/share-in.md): one panel over the workspace's page, as ⌘K's
// is (Switcher.tsx). What is shared at the top; 发到, the chats it can go to (the one picked lit and checked; the one the
// same site's things went to last first, saying so), the last row 新 chat (then which station it starts on, when there
// are several); at the foot what the person adds (补一句, optional) and send. Sent, the panel goes at once and a toast
// says where it went, with 打开. The phone's is a sheet of its own (mobile/ShareIn.tsx).
import { Dialog as RDialog } from "radix-ui";
import { useEffect, useRef, useState } from "react";
import { useBackClose } from "@stillfail/ui/backClose.ts";
import { ArrowUp, Check, Compose, Server, Text, Web } from "@stillfail/ui/icons.tsx";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import type { ChatItem, ShareInView } from "./core/shapes.ts";
import { useGo } from "./go.ts";
import { dismissShare, isPicked, offerShare, pickShare, sendShare, sentPath, useShared, useShareIn, type Shared } from "./shareIn.ts";
import { Mark } from "./brand.tsx";
import { ModelLogo, SkeletonRows, Time } from "./ui.tsx";
import * as switcherCss from "./Switcher.css.ts";
import * as css from "./ShareIn.css.ts";
import { NAME } from "./channel.ts";
import { t } from "./i18n.ts";

export function ShareInPanel({ scope }: { scope: string }) {
  const shared = useShared();
  const field = useRef<HTMLInputElement>(null);
  const close = () => { if (shared) dismissShare(shared); };
  useBackClose(!!shared, close);
  return (
    <RDialog.Root open={!!shared} onOpenChange={(open) => { if (!open) close(); }}>
      <RDialog.Portal>
        <RDialog.Overlay className={switcherCss.overlay} />
        <RDialog.Content className={css.panel} aria-describedby={undefined}
          onOpenAutoFocus={(e) => { e.preventDefault(); field.current?.focus(); }}>
          <RDialog.Title className={switcherCss.hidden}>{t("web-main.shareIn.title", { name: NAME })}</RDialog.Title>
          {shared && <Body key={shared.source} scope={scope} shared={shared} field={field} />}
        </RDialog.Content>
      </RDialog.Portal>
    </RDialog.Root>
  );
}

function Body({ scope, shared, field }: { scope: string; shared: Shared; field: React.RefObject<HTMLInputElement | null> }) {
  const view = useShareIn(scope, shared).value;
  const toast = useToast();
  const go = useGo();
  const [note, setNote] = useState(shared.note ?? "");
  const pick = (station: string, id?: string) => { pickShare(scope, shared, station, id).catch((e: unknown) => toast(t("web-main.pick.failed", { error: failure(e) }))); };
  const ready = !!view?.picked;
  const send = () => {
    const picked = view?.picked;
    if (!picked) return;
    // Gone at once: the core has it in the chat's outbox as it answers, and goes on from there.
    offerShare(null);
    sendShare(scope, shared, note).then(
      (sent) => toast(t("web-main.shareIn.sent", { title: sent.title }), { label: t("web-main.shareIn.open"), run: () => go(sentPath(sent, picked)) }),
      (e: unknown) => {
        const unconfirmed = (e as { code?: unknown } | null)?.code === "unconfirmed";
        toast(t(unconfirmed ? "web-main.act.unconfirmed" : "web-main.act.failed", { what: t("web-main.shareIn.sending"), error: failure(e) }));
        // Not known to have gone: back, with what was added, to send again.
        if (!unconfirmed) offerShare({ ...shared, note });
      },
    );
  };
  return (
    <>
      <What shared={shared} site={view?.site} />
      <div className={css.section}>{t("web-main.shareIn.to")}</div>
      <div className={css.list}>{view && !view.loading ? <Places view={view} onPick={pick} /> : <SkeletonRows count={3} />}</div>
      <form className={css.composer} onSubmit={(e) => { e.preventDefault(); if (ready) send(); }}>
        <input ref={field} className={css.field} value={note} placeholder={t("web-main.shareIn.note")} aria-label={t("web-main.shareIn.note")}
          spellCheck={false} onChange={(e) => setNote(e.target.value)} />
        <button type="submit" className={css.send} disabled={!ready} aria-label={t("web-main.shareIn.send")}><ArrowUp size={16} /></button>
      </form>
    </>
  );
}

/** What is shared: its title (or its link's site), over what it is (the link, the text). */
function What({ shared, site }: { shared: Shared; site: string | undefined }) {
  const head = shared.title ?? site;
  return (
    <div className={css.what}>
      <span className={css.whatMark}>{site ? <Web size={16} /> : <Text size={16} />}</span>
      <span className={css.whatText}>
        {head && <span className={css.whatTitle}>{head}</span>}
        <span className={css.whatSource} data-alone={head ? undefined : true}>{shared.source}</span>
      </span>
    </div>
  );
}

/** The chats it can go to, 新 chat, and the stations a new chat can start on. */
function Places({ view, onPick }: { view: ShareInView; onPick: (station: string, id?: string) => void }) {
  const fresh = !!view.picked && view.picked.id === undefined;
  // 新 chat starts where the chat picked is, or on the first station up.
  const first = view.stations.find((s) => s.station === view.picked?.station)?.station ?? view.stations[0]?.station;
  // 新 chat picked here (not as it opens): the stations it can start on come into sight under it.
  const startOn = useRef<HTMLDivElement>(null);
  const was = useRef(fresh);
  useEffect(() => {
    if (fresh && !was.current) startOn.current?.scrollIntoView({ block: "nearest", behavior: "smooth" });
    was.current = fresh;
  }, [fresh]);
  return (
    <>
      {view.note && <p className={css.none}>{view.note}</p>}
      {view.items.map((item) => <ChatRow key={`${item.station}/${item.id}`} item={item} view={view} onPick={onPick} />)}
      {first && (
        <Row picture={<Compose size={16} />} title={t("web-main.shareIn.newChat")} picked={fresh} onClick={() => onPick(first)} />
      )}
      {fresh && view.stations.length > 1 && <>
        <div ref={startOn} className={css.section}>{t("web-main.shareIn.startOn")}</div>
        {view.stations.map((s) => (
          <Row key={s.station} picture={<Server size={16} />} title={s.name} picked={isPicked(view.picked, s.station)} onClick={() => onPick(s.station)} />
        ))}
      </>}
    </>
  );
}

/** A chat: its title over the last thing said in it, or (the one the same site's things went to last) why it is first. */
function ChatRow({ item, view, onPick }: { item: ChatItem; view: ShareInView; onPick: (station: string, id?: string) => void }) {
  const kept = view.kept?.station === item.station && view.kept.id === item.id ? view.kept.text : undefined;
  const agent = item.agents[0];
  return (
    <Row picture={agent ? <ModelLogo maker={agent.maker} runtime={agent.runtime} size={18} /> : <Mark size={16} />}
      title={item.title} line={kept ?? item.last?.preview} meta={<Time stamp={item.time?.lastActiveAt} fixed />}
      picked={isPicked(view.picked, item.station, item.id)} onClick={() => onPick(item.station, item.id)} />
  );
}

function Row({ picture, title, line, meta, picked, onClick }: { picture: React.ReactNode; title: string; line?: string | undefined; meta?: React.ReactNode; picked: boolean; onClick: () => void }) {
  return (
    <button type="button" className={css.row} aria-pressed={picked} onClick={onClick}>
      <span className={css.picture} aria-hidden="true">{picture}</span>
      <span className={css.rowText}>
        <span className={css.rowTitle}>{title}</span>
        {line && <span className={css.rowLine}>{line}</span>}
      </span>
      {meta && <span className={css.rowMeta}>{meta}</span>}
      {picked && <Check size={16} className={css.check} />}
    </button>
  );
}
