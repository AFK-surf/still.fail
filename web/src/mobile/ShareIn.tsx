// What another app shares, on a narrow screen (../shareIn.ts; docs/share-in.md): one sheet over the workspace's page, as
// the Android app's ShareActivity has it. What is shared at the top; 发到, the chats it can go to (the one the same
// site's things went to last first, saying so; 搜索 from six), the last row 新 chat (then the stations it can start on,
// when there are several). A tap puts it in that chat's composer and opens the chat, where the person adds to it and
// sends it: the sheet has no field of its own. From a window the extension opened, the chat opens in the browser's
// still.fail tab instead, and the window closes.
import { useEffect, useRef, useState } from "react";
import { Compose, Server, Text, Web } from "@stillfail/ui/icons.tsx";
import { failure } from "@stillfail/ui/toast.tsx";
import type { ChatItem, ChatsView, ShareInView } from "../core/shapes.ts";
import { topicNow } from "../core/react.ts";
import { NO_KEY as NEW_KEY } from "../draft.ts";
import { dismissShare, offerShare, openFromPopup, openShare, SEARCH_FROM, useShared, useShareIn, type Shared } from "../shareIn.ts";
import { SheetGrab, useApp } from "./app.tsx";
import { Field, ModelMark, PickRow } from "./parts.tsx";
import { Waiting } from "@stillfail/ui/waiting.tsx";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as workspacesCss from "./Workspaces.css.ts";
import * as css from "./ShareIn.css.ts";
import { t } from "../i18n.ts";
import { sampleChats } from "../samples.ts";

/** Puts the sheet up when something is shared (over whatever page the workspace has open), and keeps it as pages change. */
export function ShareInSheet() {
  const app = useApp();
  const shared = useShared();
  useEffect(() => {
    if (!shared) return;
    app.sheet({ height: sheetHeight(app.entry.id), draggable: true, keep: true, onClose: () => dismissShare(shared), content: () => <Sheet shared={shared} /> });
  }, [app, shared]);
  return null;
}

/**
 * As tall as what it will hold, of the screen: its head, a row for each chat (as many as the workspace's list has, up
 * to seven; more scroll, or it is dragged up) and 新 chat.
 */
function sheetHeight(scope: string): number {
  const chats = topicNow<ChatsView>({ topic: "chats", scope, mine: false })?.days.reduce((n, d) => n + d.items.length, 0) ?? 4;
  const px = 25 + 64 + 30 + Math.min(Math.max(chats, 1), 7) * 62 + 46 + 24;
  return Math.min(0.86, Math.max(0.5, px / window.innerHeight));
}

function Sheet({ shared }: { shared: Shared }) {
  const app = useApp();
  const scope = app.entry.id;
  // Searching (the field open under 发到) and what is typed there: the chats the core finds for it.
  const [query, setQuery] = useState<string | null>(null);
  const view = useShareIn(scope, shared, query ?? "");
  // A chat (by its row's `id`), or a new chat on `station`: it goes into that composer, and the chat opens. The sheet
  // goes at once (the core answers from the device); should it fail, it comes back with why.
  const open = (station: string, id?: string) => {
    offerShare(null);
    app.sheet(null);
    // Opened here, a new chat is the phone's, its words kept by the key it has before it is made; from a window the
    // extension opened, the browser's tab opens it on the wide screen, by its station's.
    openShare(scope, shared, station, id, shared.popup ? undefined : NEW_KEY).then(
      (path) => (shared.popup ? openFromPopup(shared, path) : app.push(path)),
      (e: unknown) => { app.toast(t("web-main.act.failed", { what: t("web-main.shareIn.opening"), error: failure(e) })); offerShare(shared); },
    );
  };
  return (
    <>
      <SheetGrab />
      <What shared={shared} site={view?.site} />
      <div className={`${sheetsCss.mSheetScroll} ${css.mShareList}`}>
        <div className={css.mShareLabel}>
          <span>{t("web-main.shareIn.to")}</span>
          {(query !== null || (view && !view.loading && view.items.length >= SEARCH_FROM)) && (
            <button type="button" className={css.mShareSearch} onClick={() => setQuery(query === null ? "" : null)}>
              {query === null ? t("web-main.shareIn.search") : t("common.cancel")}
            </button>
          )}
        </div>
        {query !== null && <SearchField query={query} onQuery={setQuery} />}
        {view ? <Places view={view} searching={!!query?.trim()} onOpen={open} /> : <Waiting sample={<Places view={SAMPLE_PLACES} searching={false} onOpen={() => undefined} />} />}
      </div>
    </>
  );
}

/** Where it can go made up, for what the sheet shows while that is read (in its bones): a few chats. */
const SAMPLE_PLACES: ShareInView = { items: sampleChats(3), stations: [], loading: false };

/** What is shared: its title (or its link's site), over what it is (the link, the text). */
function What({ shared, site }: { shared: Shared; site: string | undefined }) {
  const head = shared.title ?? site;
  return (
    <div className={css.mShareWhat}>
      <span className={css.mShareIcon}>{site ? <Web size={20} /> : <Text size={20} />}</span>
      <span className={css.mShareText}>
        {head && <b>{head}</b>}
        <small data-alone={head ? undefined : true}>{shared.source}</small>
      </span>
    </div>
  );
}

/** 找 chat: under 发到 once 搜索 is tapped, the keyboard up for it. */
function SearchField({ query, onQuery }: { query: string; onQuery: (query: string) => void }) {
  const at = useRef<HTMLDivElement>(null);
  useEffect(() => { at.current?.querySelector("input")?.focus(); }, []);
  return <div ref={at} className={css.mShareFind}><Field value={query} onChange={onQuery} placeholder={t("web-main.shareIn.find")} /></div>;
}

/**
 * The chats it can go to, then 新 chat (on the station new chats start on) and, with several stations, each to start
 * one on; `searching`, only the chats found (or that none is).
 */
function Places({ view, searching, onOpen }: { view: ShareInView; searching: boolean; onOpen: (station: string, id?: string) => void }) {
  if (view.loading) return <Waiting sample={<Places view={SAMPLE_PLACES} searching={false} onOpen={() => undefined} />} />;
  const on = view.newOn ?? view.stations[0]?.station;
  return (
    <>
      {view.note && <p className={workspacesCss.mSheetNone}>{view.note}</p>}
      {view.items.map((item) => <ChatRow key={`${item.station}/${item.id}`} item={item} view={view} onOpen={onOpen} />)}
      {searching && view.items.length === 0 && <p className={workspacesCss.mSheetNone}>{t("web-main.chatRef.noMatch")}</p>}
      {on && !searching && (
        <PickRow label={t("web-main.shareIn.newChat")} leading={<span className={css.mShareLead}><Compose size={20} /></span>} onClick={() => onOpen(on)} />
      )}
      {!searching && view.stations.length > 1 && <>
        <div className={workspacesCss.mSheetLabel}>{t("web-main.shareIn.startOn")}</div>
        {view.stations.map((s) => (
          <PickRow key={s.station} label={s.name} leading={<span className={css.mShareLead}><Server size={20} /></span>} onClick={() => onOpen(s.station)} />
        ))}
      </>}
    </>
  );
}

/** A chat, by its title over the last thing said in it, or (the one the same site's things went to last) why it is first. */
function ChatRow({ item, view, onOpen }: { item: ChatItem; view: ShareInView; onOpen: (station: string, id?: string) => void }) {
  const kept = view.kept?.station === item.station && view.kept.id === item.id ? view.kept.text : undefined;
  const agent = item.agents[0];
  return (
    <PickRow label={item.title} sub={kept ?? item.last?.preview}
      leading={agent ? <ModelMark maker={agent.maker} runtime={agent.runtime} size={36} /> : <span className={css.mShareLead}><Compose size={20} /></span>}
      onClick={() => onOpen(item.station, item.id)} />
  );
}
