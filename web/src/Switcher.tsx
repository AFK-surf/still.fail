// The shortcuts that belong to no page (keymap.ts), and ⌘K's switcher: a chat found by typing part of its title, a
// message by its words, or something to do here by its name (↑/↓ pick, ↩ opens, Esc closes, as everywhere; nothing
// says so).
import { Dialog as RDialog } from "radix-ui";
import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router";
import { useChatSearch, type ChatItem } from "./api.ts";
import type { FoundMessage } from "./core/shapes.ts";
import { Marked } from "./Marked.tsx";
import { jumpTo } from "./jumpTo.ts";
import { Mark } from "./brand.tsx";
import { Command } from "./icons.tsx";
import { ACTIONS, availableActions, labelOf, runAction, shortcutOf, useShortcut, type Action } from "./keymap.ts";
import { ShortcutsDialog } from "./Shortcuts.tsx";
import { stationBase } from "./station.tsx";
import { ModelLogo, Time } from "./ui.tsx";
import { StationMark } from "./StationMark.tsx";
import * as markCss from "./StationMark.css.ts";
import * as css from "./Switcher.css.ts";

import { NAME } from "./channel.ts";
import { t } from "./i18n.ts";
/** Mounted once under a scope's pages (a workspace's): its new chat and settings are at these paths. */
export function GlobalShortcuts({ scope, newChat, settings }: { scope: string; newChat: string; settings: string }) {
  const navigate = useNavigate();
  const [switching, setSwitching] = useState(false);
  const [listing, setListing] = useState(false);
  useShortcut("chat.switch", () => setSwitching((s) => !s));
  useShortcut("shortcuts", () => setListing((s) => !s));
  useShortcut("chat.new", () => navigate(newChat));
  useShortcut("settings", () => navigate(settings));
  useShortcut("nav.back", () => history.back());
  useShortcut("nav.forward", () => history.forward());
  return (
    <>
      <ChatSwitcher scope={scope} open={switching} onClose={() => setSwitching(false)} />
      <ShortcutsDialog open={listing} onClose={() => setListing(false)} settings={`${settings}/shortcuts`} />
    </>
  );
}

function ChatSwitcher({ scope, open, onClose }: { scope: string; open: boolean; onClose(): void }) {
  // An action picked is done once the list has closed and given the focus back to where it was, so what the action
  // opens (rename's field) keeps it.
  const picked = useRef<Action | null>(null);
  const done = (action: Action) => { picked.current = action; onClose(); };
  return (
    <RDialog.Root open={open} onOpenChange={(next) => { if (!next) onClose(); }}>
      <RDialog.Portal>
        <RDialog.Overlay className={css.overlay} />
        <RDialog.Content className={css.switcher} aria-describedby={undefined}
          onCloseAutoFocus={() => {
            const action = picked.current;
            picked.current = null;
            if (action) setTimeout(() => runAction(action));
          }}>
          <RDialog.Title className={css.hidden}>{t("web-main.switcher.title")}</RDialog.Title>
          {open && <Finder scope={scope} onClose={onClose} onAction={done} />}
        </RDialog.Content>
      </RDialog.Portal>
    </RDialog.Root>
  );
}

/** How many of the messages that have the words the switcher lists, under the chats. */
const MESSAGES = 30;

type Found =
  | { chat: ChatItem; message?: undefined; action?: undefined }
  | { chat: ChatItem; message: FoundMessage; action?: undefined }
  | { action: Action };

/**
 * Not offered in the list: ⌘K itself, Esc (which closes the list), and the moves that are only worth a key (back,
 * forward, the chat above or below, the composer, the latest message).
 */
const UNLISTED: Action[] = ["chat.switch", "panel.close", "nav.back", "nav.forward", "chat.prev", "chat.next", "composer.focus", "chat.latest"];

/** The actions that can be done now whose name (or its id, "chat.archive") has what was typed: the chat's first. */
function actionsFor(query: string): Action[] {
  const q = query.trim().toLowerCase();
  const found = availableActions().filter((a) => !UNLISTED.includes(a) && (!q || labelOf(a).toLowerCase().includes(q) || a.includes(q)));
  return [...found.filter((a) => ACTIONS[a].group === "chat"), ...found.filter((a) => ACTIONS[a].group !== "chat")];
}

/**
 * Its chats as the sidebar lists them, newest first; typing narrows them to those whose title (or else where they are,
 * or what was said last) has it, and lists under them the messages that have it, newest first (the core's `chatSearch`):
 * one picked opens its chat at it. The actions that can be done here (those whose keys the page answers now) are
 * listed too: under the chats with nothing typed, over them once their name has what was typed.
 */
function Finder({ scope, onClose, onAction }: { scope: string; onClose(): void; onAction(action: Action): void }) {
  const navigate = useNavigate();
  const [query, setQuery] = useState("");
  const search = useChatSearch({ scope, query, messages: MESSAGES });
  const view = search.value;
  const typed = !!query.trim();
  const actions = actionsFor(query);
  const chats = view?.items ?? [];
  const messages = typed ? view?.messages ?? [] : [];
  const found: Found[] = [
    ...(typed ? actions.map((action) => ({ action })) : []),
    ...chats.map((chat) => ({ chat })),
    ...(typed ? [] : actions.map((action) => ({ action }))),
    ...messages.map((message) => ({ chat: message.chat, message })),
  ];
  const firstChat = typed ? actions.length : 0;
  const firstAction = typed ? 0 : chats.length;
  const firstMessage = actions.length + chats.length;
  const [at, setAt] = useState(0);
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => setAt(0), [query]);
  useEffect(() => {
    list.current?.querySelector(`[data-at="${at}"]`)?.scrollIntoView({ block: "nearest" });
  }, [at]);
  const go = (pick: Found | undefined) => {
    if (!pick) return;
    if (pick.action) return onAction(pick.action);
    onClose();
    if (pick.message) jumpTo({ station: pick.message.station, thread: pick.message.thread, seq: pick.message.seq, words: view?.words });
    navigate(`${stationBase(pick.chat.station)}/chats/${encodeURIComponent(pick.chat.id)}`);
  };
  const option = (i: number) => ({
    role: "option", "aria-selected": i === at, "data-at": i,
    onMouseMove: () => { if (i !== at) setAt(i); }, onClick: () => go(found[i]),
  });
  const actionRows = actions.length > 0 && (
    <>
      <div className={css.section} role="presentation">{t("web-main.switcher.actions")}</div>
      {actions.map((action, k) => (
        <div key={action} className={css.row} {...option(firstAction + k)}>
          <span className={`${css.picture} ${css.actionMark}`} aria-hidden="true"><Command size={16} /></span>
          <span className={css.title}>{labelOf(action)}</span>
          <span className={css.meta}>{shortcutOf(action)}</span>
        </div>
      ))}
    </>
  );
  return (
    <>
      <input className={css.search} autoFocus placeholder={t("web-main.switcher.search")} aria-label={t("web-main.switcher.search")} value={query} spellCheck={false}
        onChange={(e) => setQuery(e.target.value)}
        onKeyDown={(e) => {
          if (e.nativeEvent.isComposing) return;
          const step = e.key === "ArrowDown" || e.ctrlKey && e.key === "n" ? 1 : e.key === "ArrowUp" || e.ctrlKey && e.key === "p" ? -1 : 0;
          if (step) { e.preventDefault(); setAt((a) => Math.max(0, Math.min(found.length - 1, a + step))); }
          else if (e.key === "Enter") { e.preventDefault(); go(found[at]); }
        }} />
      <div className={css.results} ref={list} role="listbox" aria-label={t("web-main.chat.label")}>
        {search.error && !view && <p className={css.none}>{t("web-main.switcher.update", { app: NAME })}</p>}
        {view && found.length === 0 && <p className={css.none}>{query ? t("web-main.switcher.noMatch") : t("web-main.switcher.none")}</p>}
        {typed && actionRows}
        {typed && chats.length > 0 && actions.length > 0 && <div className={css.section} role="presentation">{t("web-main.switcher.chats")}</div>}
        {chats.map((item, i) => (
          <div key={`${item.station}/${item.id}`} className={css.row} {...option(firstChat + i)}>
            <ChatPicture item={item} />
            <span className={css.title} data-unread={item.unread || undefined}>{item.title}</span>
            <span className={css.meta}>
              <span>{(item.stationEmoji || item.stationIcon) && <StationMark emoji={item.stationEmoji} icon={item.stationIcon} size={12} className={markCss.inline} />}{item.stationName}</span>
              <Time stamp={item.time?.lastActiveAt} fixed />
            </span>
          </div>
        ))}
        {!typed && actionRows}
        {messages.length > 0 && <div className={css.section} role="presentation">{t("web-main.switcher.messages")}</div>}
        {messages.map((message, j) => (
          <div key={`${message.station}/${message.thread}/${message.seq}`} className={`${css.row} ${css.said}`} {...option(firstMessage + j)}>
            <ChatPicture item={message.chat} />
            <span className={css.saidBody}>
              <span className={css.saidHead}>
                <span className={css.saidChat}>{message.chat.title}</span>
                <span className={css.meta}>
                  {message.by && <span>{message.by}</span>}
                  <Time stamp={message.time?.createdAt} fixed />
                </span>
              </span>
              <span className={css.saidText}><Marked text={message.text} marks={message.marks} className={css.hit} /></span>
            </span>
          </div>
        ))}
      </div>
    </>
  );
}

function ChatPicture({ item }: { item: ChatItem }) {
  return (
    <span className={css.picture} aria-hidden="true">
      {item.agents[0] ? <ModelLogo maker={item.agents[0].maker} runtime={item.agents[0].runtime} size={18} /> : <Mark size={16} />}
    </span>
  );
}
