// The shortcuts that belong to no page (keymap.ts), and ⌘K's switcher: a chat found by typing part of its title, a
// message by its words, or something to do here by its name (↑/↓ pick, ↩ opens, Esc closes, as everywhere; nothing
// says so).
import { Dialog as RDialog } from "radix-ui";
import { Fragment, memo, useEffect, useRef, useState, useSyncExternalStore, type ComponentType } from "react";
import { useNavigate } from "react-router";
import { useGo } from "./go.ts";
import { useChatSearch, type ChatItem } from "./api.ts";
import type { FoundMessage } from "./core/shapes.ts";
import { Marked } from "./Marked.tsx";
import { jumpTo } from "./jumpTo.ts";
import { Mark, useAppUpdate } from "./brand.tsx";
import { commands, useCommands, type Command } from "./commands.ts";
import { webUpdates } from "./core/webUpdates.ts";
import { Archive, Command as CommandIcon, Compose, Download, File, PanelOpen, Refresh, Settings, Stop, Thread, Web, type IconProps } from "@stillfail/ui/icons.tsx";
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
export const GlobalShortcuts = memo(function GlobalShortcuts({ scope, newChat, settings }: { scope: string; newChat: string; settings: string }) {
  const navigate = useGo();
  const [switching, setSwitching] = useState(false);
  const [listing, setListing] = useState(false);
  useShortcut("chat.switch", () => setSwitching((s) => !s));
  useShortcut("shortcuts", () => setListing((s) => !s));
  useShortcut("chat.new", () => navigate(newChat));
  useShortcut("settings", () => navigate(settings));
  useShortcut("nav.back", () => history.back());
  useShortcut("nav.forward", () => history.forward());
  useCommands(useUpdateCommands(settings));
  return (
    <>
      <ChatSwitcher scope={scope} open={switching} onClose={() => setSwitching(false)} />
      <ShortcutsDialog open={listing} onClose={() => setListing(false)} settings={`${settings}/shortcuts`} />
    </>
  );
});

/**
 * Updating what runs here: the page to a newer build of it (as the sidebar's foot offers), the desktop app to its newer
 * build (as 更新 beside the buddy does), or looking for one now (its version page, looking as it opens).
 */
function useUpdateCommands(settings: string): Command[] {
  const navigate = useGo();
  const page = useSyncExternalStore(webUpdates.subscribe, webUpdates.snapshot, () => null);
  const app = useAppUpdate();
  const updates = window.stillfailDesktop?.appUpdate;
  return [
    ...(page ? [{ id: "update.page", group: "update" as const, words: "update refresh", label: t("web-main.webUpdate.foundRefresh"), icon: Refresh, run: webUpdates.refresh }] : []),
    ...(updates && app && (app.phase === "available" || app.phase === "failed")
      ? [{ id: "update.app", group: "update" as const, words: "update", label: t("web-pages.version.updateTo", { version: app.version }), icon: Download, run: () => updates.start() }] : []),
    ...(updates?.check && !app ? [{ id: "update.check", group: "update" as const, words: "check update", label: t("web-pages.version.check"), icon: Refresh, typed: true, run: () => navigate(`${settings}/version?check`) }] : []),
  ];
}

function ChatSwitcher({ scope, open, onClose }: { scope: string; open: boolean; onClose(): void }) {
  // What is picked is done once the list has closed and given the focus back to where it was, so what it opens
  // (rename's field) keeps it.
  const picked = useRef<Listed | null>(null);
  const done = (command: Listed) => { picked.current = command; onClose(); };
  return (
    <RDialog.Root open={open} onOpenChange={(next) => { if (!next) onClose(); }}>
      <RDialog.Portal>
        <RDialog.Overlay className={css.overlay} />
        <RDialog.Content className={css.switcher} aria-describedby={undefined}
          onCloseAutoFocus={() => {
            const command = picked.current;
            picked.current = null;
            if (command) setTimeout(() => command.run());
          }}>
          <RDialog.Title className={css.hidden}>{t("web-main.switcher.title")}</RDialog.Title>
          {open && <Finder scope={scope} onClose={onClose} onCommand={done} />}
        </RDialog.Content>
      </RDialog.Portal>
    </RDialog.Root>
  );
}

/** How many of the messages that have the words the switcher lists, under the chats. */
const MESSAGES = 30;

type Found =
  | { chat: ChatItem; message?: undefined; command?: undefined }
  | { chat: ChatItem; message: FoundMessage; command?: undefined }
  | { command: Listed };

/** A command as the list shows it: under its part, with the keys that do it too when it is a key's action. */
type Listed = Omit<Command, "group"> & { group: Group; keys?: string | null };

/** The parts of what can be done, in the list's order: this chat's, updates, the app's, settings' pages. */
type Group = "chat" | "update" | "global" | "settings";
const GROUPS: Group[] = ["chat", "update", "global", "settings"];

/**
 * The keys' actions not offered in the list: ⌘K itself, Esc (which closes the list), and the moves that are only worth
 * a key (back, forward, the chat above or below, the composer, the latest message).
 */
const UNLISTED: Action[] = ["chat.switch", "panel.close", "nav.back", "nav.forward", "chat.prev", "chat.next", "composer.focus", "chat.latest"];

const ACTION_ICON: Partial<Record<Action, ComponentType<IconProps>>> = {
  "chat.new": Compose, "settings": Settings, "shortcuts": CommandIcon, "sidebar.toggle": PanelOpen,
  "composer.file": File, "chat.stop": Stop, "chat.history": Thread, "chat.jobs": Web, "chat.archive": Archive,
};

const keyCommand = (action: Action): Listed => ({
  id: action, group: ACTIONS[action].group, label: labelOf(action), icon: ACTION_ICON[action] ?? CommandIcon, keys: shortcutOf(action), run: () => runAction(action),
});

/**
 * What can be done now whose name (or its id, "chat.archive", or its other words) has what was typed, part by part
 * (GROUPS); with nothing typed, all but what is only found by typing (a settings page).
 */
function commandsFor(query: string): Listed[] {
  const q = query.trim().toLowerCase();
  const all: Listed[] = [...availableActions().filter((a) => !UNLISTED.includes(a)).map(keyCommand), ...commands()];
  const found = q ? all.filter((c) => [c.label, c.id, c.words ?? ""].some((w) => w.toLowerCase().includes(q))) : all.filter((c) => !c.typed);
  return GROUPS.flatMap((group) => found.filter((c) => c.group === group));
}

/**
 * Its chats as the sidebar lists them, newest first; typing narrows them to those whose title (or else where they are,
 * or what was said last) has it, and lists under them the messages that have it, newest first (the core's `chatSearch`):
 * one picked opens its chat at it. What can be done here (the keys' actions the page answers now, and what it offers:
 * commands.ts) is listed too: under the chats with nothing typed, over them once its name has what was typed.
 */
function Finder({ scope, onClose, onCommand }: { scope: string; onClose(): void; onCommand(command: Listed): void }) {
  const navigate = useNavigate();
  const [query, setQuery] = useState("");
  const search = useChatSearch({ scope, query, messages: MESSAGES });
  const view = search.value;
  const typed = !!query.trim();
  const actions = commandsFor(query);
  const chats = view?.items ?? [];
  const messages = typed ? view?.messages ?? [] : [];
  const found: Found[] = [
    ...(typed ? actions.map((command) => ({ command })) : []),
    ...chats.map((chat) => ({ chat })),
    ...(typed ? [] : actions.map((command) => ({ command }))),
    ...messages.map((message) => ({ chat: message.chat, message })),
  ];
  const firstChat = typed ? actions.length : 0;
  const firstAction = typed ? 0 : chats.length;
  const firstMessage = actions.length + chats.length;
  const [at, setAt] = useState(0);
  const list = useRef<HTMLDivElement>(null);
  // Brought into view when the keys or a new query choose it, not when the pointer does: it is in view under the
  // pointer already, and scrolling it there (the list keeps clear of its corner, scroll-padding) moved the next row
  // under the pointer, which chose that one, and the list scrolled on by itself.
  const pointed = useRef(false);
  useEffect(() => setAt(0), [query]);
  useEffect(() => {
    if (pointed.current) { pointed.current = false; return; }
    list.current?.querySelector(`[data-at="${at}"]`)?.scrollIntoView({ block: "nearest" });
  }, [at]);
  const go = (pick: Found | undefined) => {
    if (!pick) return;
    if (pick.command) return onCommand(pick.command);
    onClose();
    if (pick.message) jumpTo({ station: pick.message.station, thread: pick.message.thread, seq: pick.message.seq, words: view?.words });
    navigate(`${stationBase(pick.chat.station)}/chats/${encodeURIComponent(pick.chat.id)}`);
  };
  const option = (i: number) => ({
    role: "option", "aria-selected": i === at, "data-at": i,
    onMouseMove: () => { if (i !== at) { pointed.current = true; setAt(i); } }, onClick: () => go(found[i]),
  });
  const actionRows = actions.map((command, k) => (
    <Fragment key={command.id}>
      {command.group !== actions[k - 1]?.group && <div className={css.section} role="presentation">{t(`web-main.switcher.group.${command.group}`)}</div>}
      <div className={css.row} {...option(firstAction + k)}>
        <span className={`${css.picture} ${css.actionMark}`} aria-hidden="true"><command.icon size={16} /></span>
        <span className={css.title}>{command.label}</span>
        {command.keys && <span className={css.meta}>{command.keys}</span>}
      </div>
    </Fragment>
  ));
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
        {chats.length > 0 && actions.length > 0 && <div className={css.section} role="presentation">{t("web-main.switcher.chats")}</div>}
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
