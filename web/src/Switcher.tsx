// The shortcuts that belong to no page (keymap.ts), and ⌘K's switcher: a chat found by typing part of its title, or a
// message by its words (↑/↓ pick, ↩ opens, Esc closes, as everywhere; nothing says so).
import { Dialog as RDialog } from "radix-ui";
import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router";
import { useChatSearch, type ChatItem } from "./api.ts";
import type { FoundMessage } from "./core/shapes.ts";
import { Marked } from "./Marked.tsx";
import { jumpTo } from "./jumpTo.ts";
import { Mark } from "./brand.tsx";
import { useShortcut } from "./keymap.ts";
import { ShortcutsDialog } from "./Shortcuts.tsx";
import { stationBase } from "./station.tsx";
import { ModelLogo, Time } from "./ui.tsx";
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
  return (
    <RDialog.Root open={open} onOpenChange={(next) => { if (!next) onClose(); }}>
      <RDialog.Portal>
        <RDialog.Overlay className={css.overlay} />
        <RDialog.Content className={css.switcher} aria-describedby={undefined}>
          <RDialog.Title className={css.hidden}>{t("web-main.switcher.title")}</RDialog.Title>
          {open && <Finder scope={scope} onClose={onClose} />}
        </RDialog.Content>
      </RDialog.Portal>
    </RDialog.Root>
  );
}

/** How many of the messages that have the words the switcher lists, under the chats. */
const MESSAGES = 30;

type Found = { chat: ChatItem; message?: undefined } | { chat: ChatItem; message: FoundMessage };

/**
 * Its chats as the sidebar lists them, newest first; typing narrows them to those whose title (or else where they are,
 * or what was said last) has it, and lists under them the messages that have it, newest first (the core's `chatSearch`):
 * one picked opens its chat at it.
 */
function Finder({ scope, onClose }: { scope: string; onClose(): void }) {
  const navigate = useNavigate();
  const [query, setQuery] = useState("");
  const search = useChatSearch({ scope, query, messages: MESSAGES });
  const view = search.value;
  const chats: Found[] = (view?.items ?? []).map((chat) => ({ chat }));
  const messages: Found[] = query.trim() ? (view?.messages ?? []).map((message) => ({ chat: message.chat, message })) : [];
  const found = [...chats, ...messages];
  const [at, setAt] = useState(0);
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => setAt(0), [query]);
  useEffect(() => {
    list.current?.querySelector(`[data-at="${at}"]`)?.scrollIntoView({ block: "nearest" });
  }, [at]);
  const go = (pick: Found | undefined) => {
    if (!pick) return;
    onClose();
    if (pick.message) jumpTo({ station: pick.message.station, thread: pick.message.thread, seq: pick.message.seq, words: view?.words });
    navigate(`${stationBase(pick.chat.station)}/chats/${encodeURIComponent(pick.chat.id)}`);
  };
  const option = (i: number) => ({
    role: "option", "aria-selected": i === at, "data-at": i,
    onMouseMove: () => { if (i !== at) setAt(i); }, onClick: () => go(found[i]),
  });
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
        {chats.map(({ chat: item }, i) => (
          <div key={`${item.station}/${item.id}`} className={css.row} {...option(i)}>
            <ChatPicture item={item} />
            <span className={css.title} data-unread={item.unread || undefined}>{item.title}</span>
            <span className={css.meta}>
              <span>{item.stationName}</span>
              <Time stamp={item.time?.lastActiveAt} fixed />
            </span>
          </div>
        ))}
        {messages.length > 0 && <div className={css.section} role="presentation">{t("web-main.switcher.messages")}</div>}
        {messages.map(({ chat: item, message }, j) => message && (
          <div key={`${message.station}/${message.thread}/${message.seq}`} className={`${css.row} ${css.said}`} {...option(chats.length + j)}>
            <ChatPicture item={item} />
            <span className={css.saidBody}>
              <span className={css.saidHead}>
                <span className={css.saidChat}>{item.title}</span>
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
