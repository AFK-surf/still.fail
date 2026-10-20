// What another app shares, on a wide screen (shareIn.ts; docs/share-in.md): one panel over the workspace's page, as ⌘K's
// is (Switcher.tsx). What is shared at the top; 发到, the chats it can go to (the one the same site's things went to last
// first, saying so; 搜索 from six), the last row 新 chat (then the stations it can start on, when there are several). A
// click puts it in that chat's composer and opens the chat, where the person adds to it and sends it: the panel has no
// field of its own. The phone's is a sheet of its own (mobile/ShareIn.tsx).
import { Dialog as RDialog } from "radix-ui";
import { useState } from "react";
import { afterBack, useBackClose } from "@stillfail/ui/backClose.ts";
import { Compose, Server, Text, Web } from "@stillfail/ui/icons.tsx";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import type { ChatItem, ShareInView } from "./core/shapes.ts";
import { useGo } from "./go.ts";
import { dismissShare, offerShare, openFromPopup, openShare, SEARCH_FROM, useShared, useShareIn, type Shared } from "./shareIn.ts";
import { Mark } from "./brand.tsx";
import { ModelLogo, Time, Waiting } from "./ui.tsx";
import * as switcherCss from "./Switcher.css.ts";
import * as css from "./ShareIn.css.ts";
import { NAME } from "./channel.ts";
import { t } from "./i18n.ts";

export function ShareInPanel({ scope }: { scope: string }) {
  const shared = useShared();
  const close = () => { if (shared) dismissShare(shared); };
  useBackClose(!!shared, close);
  return (
    <RDialog.Root open={!!shared} onOpenChange={(open) => { if (!open) close(); }}>
      <RDialog.Portal>
        <RDialog.Overlay className={switcherCss.overlay} />
        {/* The panel itself takes the focus, not its first row (Tab goes on to them). */}
        <RDialog.Content className={css.panel} aria-describedby={undefined} tabIndex={-1}
          onOpenAutoFocus={(e) => { e.preventDefault(); (e.currentTarget as HTMLElement).focus(); }}>
          <RDialog.Title className={switcherCss.hidden}>{t("web-main.shareIn.title", { name: NAME })}</RDialog.Title>
          {shared && <Body key={shared.source} scope={scope} shared={shared} />}
        </RDialog.Content>
      </RDialog.Portal>
    </RDialog.Root>
  );
}

function Body({ scope, shared }: { scope: string; shared: Shared }) {
  // Searching (⌘K's field open under 发到) and what is typed there: the chats the core finds for it.
  const [query, setQuery] = useState<string | null>(null);
  const view = useShareIn(scope, shared, query ?? "");
  const toast = useToast();
  const go = useGo();
  // A chat (by its row's `id`), or a new chat on `station`: it goes into that composer, and the chat opens. The panel
  // goes at once (the core answers from the device); should it fail, it comes back with why.
  const open = (station: string, id?: string) => {
    offerShare(null);
    openShare(scope, shared, station, id).then(
      (path) => (shared.popup ? openFromPopup(shared, path) : afterBack(() => go(path))),
      (e: unknown) => { toast(t("web-main.act.failed", { what: t("web-main.shareIn.opening"), error: failure(e) })); offerShare(shared); },
    );
  };
  return (
    <>
      <What shared={shared} site={view?.site} />
      <div className={`${css.section} ${css.labelRow}`}>
        <span>{t("web-main.shareIn.to")}</span>
        {(query !== null || (view && !view.loading && view.items.length >= SEARCH_FROM)) && (
          <button type="button" className={css.search} onClick={() => setQuery(query === null ? "" : null)}>
            {query === null ? t("web-main.shareIn.search") : t("common.cancel")}
          </button>
        )}
      </div>
      {query !== null && (
        <input className={switcherCss.search} autoFocus placeholder={t("web-main.shareIn.find")} aria-label={t("web-main.shareIn.find")} value={query} spellCheck={false}
          onChange={(e) => setQuery(e.target.value)}
          // Esc lets go of the search first, then (pressed again) the panel.
          onKeyDown={(e) => { if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); setQuery(null); } }} />
      )}
      <div className={css.list}>{view && !view.loading ? <Places view={view} searching={!!query?.trim()} onOpen={open} /> : <Waiting shape="rows" dense count={3} />}</div>
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

/**
 * The chats it can go to, then 新 chat (on the station new chats start on) and, with several stations, each to start
 * one on; `searching`, only the chats found (or that none is).
 */
function Places({ view, searching, onOpen }: { view: ShareInView; searching: boolean; onOpen: (station: string, id?: string) => void }) {
  const on = view.newOn ?? view.stations[0]?.station;
  return (
    <>
      {view.note && <p className={css.none}>{view.note}</p>}
      {view.items.map((item) => <ChatRow key={`${item.station}/${item.id}`} item={item} view={view} onOpen={onOpen} />)}
      {searching && view.items.length === 0 && <p className={css.none}>{t("web-main.chatRef.noMatch")}</p>}
      {on && !searching && <Row picture={<Compose size={16} />} title={t("web-main.shareIn.newChat")} onClick={() => onOpen(on)} />}
      {!searching && view.stations.length > 1 && <>
        <div className={css.section}>{t("web-main.shareIn.startOn")}</div>
        {view.stations.map((s) => <Row key={s.station} picture={<Server size={16} />} title={s.name} onClick={() => onOpen(s.station)} />)}
      </>}
    </>
  );
}

/** A chat: its title over the last thing said in it, or (the one the same site's things went to last) why it is first. */
function ChatRow({ item, view, onOpen }: { item: ChatItem; view: ShareInView; onOpen: (station: string, id?: string) => void }) {
  const kept = view.kept?.station === item.station && view.kept.id === item.id ? view.kept.text : undefined;
  const agent = item.agents[0];
  return (
    <Row picture={agent ? <ModelLogo maker={agent.maker} runtime={agent.runtime} size={18} /> : <Mark size={16} />}
      title={item.title} line={kept ?? item.last?.preview} meta={<Time stamp={item.time?.lastActiveAt} fixed />}
      onClick={() => onOpen(item.station, item.id)} />
  );
}

function Row({ picture, title, line, meta, onClick }: { picture: React.ReactNode; title: string; line?: string | undefined; meta?: React.ReactNode; onClick: () => void }) {
  return (
    <button type="button" className={css.row} onClick={onClick}>
      <span className={css.picture} aria-hidden="true">{picture}</span>
      <span className={css.rowText}>
        <span className={css.rowTitle}>{title}</span>
        {line && <span className={css.rowLine}>{line}</span>}
      </span>
      {meta && <span className={css.rowMeta}>{meta}</span>}
    </button>
  );
}
