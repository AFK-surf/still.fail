// What another app shares, on a narrow screen (../shareIn.ts; docs/share-in.md): one sheet over the workspace's page, as
// the Android app's ShareActivity has it. What is shared at the top; 发到, the chats it can go to (the one picked
// checked; the one the same site's things went to last first, saying so), the last row 新 chat (then which station it
// starts on, when there are several); at the foot a composer (补一句, optional) and its send button. Sent, the sheet
// goes at once and a toast says where it went, with 打开; a window the extension opened closes itself after it.
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { ArrowUp, Compose, Server, Text, Web } from "@stillfail/ui/icons.tsx";
import { failure, type ToastAction } from "@stillfail/ui/toast.tsx";
import type { ChatItem, ChatsView, ShareInView } from "../core/shapes.ts";
import { topicNow } from "../core/react.ts";
import { dismissShare, isPicked, offerShare, openFromPopup, pickShare, POPUP_STAYS_MS, SEARCH_FROM, sendShare, sentPath, useShared, useShareIn, type Shared } from "../shareIn.ts";
import { SheetGrab, useApp } from "./app.tsx";
import { Field, ModelMark, PickRow } from "./parts.tsx";
import { PlaceholderRows } from "./Loading.tsx";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as workspacesCss from "./Workspaces.css.ts";
import * as chatCss from "./Chat.css.ts";
import * as css from "./ShareIn.css.ts";
import { t } from "../i18n.ts";

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
 * to seven; more scroll, or it is dragged up), 新 chat and the composer.
 */
function sheetHeight(scope: string): number {
  const chats = topicNow<ChatsView>({ topic: "chats", scope, mine: false })?.days.reduce((n, d) => n + d.items.length, 0) ?? 4;
  const px = 25 + 64 + 30 + Math.min(Math.max(chats, 1), 7) * 62 + 46 + 24 + 72;
  return Math.min(0.86, Math.max(0.5, px / window.innerHeight));
}

function Sheet({ shared }: { shared: Shared }) {
  const app = useApp();
  const scope = app.entry.id;
  // Searching (the field open under 发到) and what is typed there: the chats the core finds for it.
  const [query, setQuery] = useState<string | null>(null);
  const view = useShareIn(scope, shared, query ?? "");
  const [note, setNote] = useState(shared.note ?? "");
  const pick = (station: string, id?: string) => { pickShare(scope, shared, station, id).catch((e: unknown) => app.toast(t("web-main.pick.failed", { error: failure(e) }))); };
  const send = () => {
    const picked = view?.picked;
    if (!picked) return;
    // Gone at once: the core has it in the chat's outbox as it answers, and goes on from there.
    offerShare(null);
    app.sheet(null);
    sendShare(scope, shared, note).then((sent) => {
      const path = sentPath(sent, picked);
      const open: ToastAction = { label: t("web-main.shareIn.open"), run: () => (shared.popup ? openFromPopup(path) : app.push(path)) };
      app.toast(t("web-main.shareIn.sent", { title: sent.title }), open);
      if (shared.popup) setTimeout(() => window.close(), POPUP_STAYS_MS);
    }, (e: unknown) => {
      app.toast(t((e as { code?: unknown } | null)?.code === "unconfirmed" ? "web-main.act.unconfirmed" : "web-main.act.failed", { what: t("web-main.shareIn.sending"), error: failure(e) }));
      // Not known to have gone: back, with what was added, to send again.
      if ((e as { code?: unknown } | null)?.code !== "unconfirmed") offerShare({ ...shared, note });
    });
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
        {view ? <Places view={view} searching={!!query?.trim()} onPick={pick} /> : <PlaceholderRows count={3} />}
      </div>
      <Composer note={note} onNote={setNote} ready={!!view?.picked} onSend={send} />
    </>
  );
}

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
 * The chats it can go to, 新 chat, and the stations a new chat can start on; `searching`, only the chats found (or that
 * none is).
 */
function Places({ view, searching, onPick }: { view: ShareInView; searching: boolean; onPick: (station: string, id?: string) => void }) {
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
  if (view.loading) return <PlaceholderRows count={3} />;
  return (
    <>
      {view.note && <p className={workspacesCss.mSheetNone}>{view.note}</p>}
      {view.items.map((item) => <ChatRow key={`${item.station}/${item.id}`} item={item} view={view} onPick={onPick} />)}
      {searching && view.items.length === 0 && <p className={workspacesCss.mSheetNone}>{t("web-main.chatRef.noMatch")}</p>}
      {first && !searching && (
        <PickRow label={t("web-main.shareIn.newChat")} leading={<span className={css.mShareLead}><Compose size={20} /></span>} checked={fresh}
          onClick={() => onPick(first)} />
      )}
      {fresh && !searching && view.stations.length > 1 && <>
        <div ref={startOn} className={workspacesCss.mSheetLabel}>{t("web-main.shareIn.startOn")}</div>
        {view.stations.map((s) => (
          <PickRow key={s.station} label={s.name} leading={<span className={css.mShareLead}><Server size={20} /></span>}
            checked={isPicked(view.picked, s.station)} onClick={() => onPick(s.station)} />
        ))}
      </>}
    </>
  );
}

/** A chat, by its title over the last thing said in it, or (the one the same site's things went to last) why it is first. */
function ChatRow({ item, view, onPick }: { item: ChatItem; view: ShareInView; onPick: (station: string, id?: string) => void }) {
  const kept = view.kept?.station === item.station && view.kept.id === item.id ? view.kept.text : undefined;
  const agent = item.agents[0];
  return (
    <PickRow label={item.title} sub={kept ?? item.last?.preview} checked={isPicked(view.picked, item.station, item.id)}
      leading={agent ? <ModelMark maker={agent.maker} runtime={agent.runtime} size={36} /> : <span className={css.mShareLead}><Compose size={20} /></span>}
      onClick={() => onPick(item.station, item.id)} />
  );
}

/** What the person adds (one line, growing to a few), and send: as the chat's composer is, at the sheet's foot. */
function Composer({ note, onNote, ready, onSend }: { note: string; onNote: (note: string) => void; ready: boolean; onSend: () => void }) {
  const input = useRef<HTMLTextAreaElement>(null);
  useLayoutEffect(() => {
    const el = input.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${el.scrollHeight}px`;
  }, [note]);
  return (
    <div className={css.mShareFoot}>
      <div className={`${css.mShareComposer} ${pagesCss.mFloating}`}>
        <textarea ref={input} className={css.mShareField} rows={1} value={note} placeholder={t("web-main.shareIn.note")} aria-label={t("web-main.shareIn.note")}
          onChange={(e) => onNote(e.target.value)}
          onKeyDown={(e) => {
            // Enter sends with a keyboard of its own (a window the extension opened); a touch keyboard's starts a line.
            if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing && window.matchMedia("(hover: hover)").matches) { e.preventDefault(); if (ready) onSend(); }
          }} />
        <button type="button" className={chatCss.mSend} data-ready={ready || undefined} disabled={!ready} onClick={onSend} aria-label={t("web-main.shareIn.send")}>
          <ArrowUp size={18} />
        </button>
      </div>
    </div>
  );
}
