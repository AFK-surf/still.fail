// The shortcuts that belong to no page (keymap.ts), and ⌘K's switcher: a chat found by typing part of its title, a
// message by its words, or something to do here by its name (↑/↓ pick, ↩ opens, Esc closes, as everywhere; nothing
// says so).
import { Dialog as RDialog } from "radix-ui";
import { memo, useEffect, useRef, useState, useSyncExternalStore, type ComponentType } from "react";
import { useNavigate } from "react-router";
import { useGo } from "./go.ts";
import { useSearch, type ChatItem } from "./api.ts";
import type { FoundMessage, SearchItem } from "./core/shapes.ts";
import { Marked } from "./Marked.tsx";
import { jumpTo } from "./jumpTo.ts";
import { Mark, useAppUpdate } from "./brand.tsx";
import { commands, useCommands, type Command } from "./commands.ts";
import { webUpdates } from "./core/webUpdates.ts";
import { Archive, ArrowLeft, Brain, Command as CommandIcon, Compose, Download, File, Folder, More, PanelOpen, Quota, Refresh, Server, Settings, Sparks, Stop, Thread, Web, type IconProps } from "@stillfail/ui/icons.tsx";
import { ACTIONS, availableActions, labelOf, runAction, shortcutOf, useShortcut, type Action } from "./keymap.ts";
import { ShortcutsDialog } from "./Shortcuts.tsx";
import { stationBase } from "./station.tsx";
import { fileOpen } from "./searchOpen.ts";
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
      <ChatSwitcher scope={scope} settings={settings} open={switching} onClose={() => setSwitching(false)} />
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

function ChatSwitcher({ scope, settings, open, onClose }: { scope: string; settings: string; open: boolean; onClose(): void }) {
  // What is picked is done once the list has closed and given the focus back to where it was, so what it opens
  // (rename's field) keeps it.
  const picked = useRef<Listed | null>(null);
  const done = (command: Listed) => { picked.current = command; onClose(); };
  // Esc in one kind's list goes back to all of them (Finder says whether it did), else closes.
  const escape = useRef<(() => boolean) | null>(null);
  return (
    <RDialog.Root open={open} onOpenChange={(next) => { if (!next) onClose(); }}>
      <RDialog.Portal>
        <RDialog.Overlay className={css.overlay} />
        <RDialog.Content className={css.switcher} aria-describedby={undefined}
          onEscapeKeyDown={(e) => { if (escape.current?.()) e.preventDefault(); }}
          onCloseAutoFocus={() => {
            const command = picked.current;
            picked.current = null;
            if (command) setTimeout(() => command.run());
          }}>
          <RDialog.Title className={css.hidden}>{t("web-main.switcher.title")}</RDialog.Title>
          {open && <Finder scope={scope} settings={settings} onClose={onClose} onCommand={done} escape={escape} />}
        </RDialog.Content>
      </RDialog.Portal>
    </RDialog.Root>
  );
}

type Found =
  | { chat: ChatItem; message?: undefined; command?: undefined; item?: undefined }
  | { chat: ChatItem; message: FoundMessage; command?: undefined; item?: undefined }
  | { command: Listed; chat?: undefined; item?: undefined }
  | { item: SearchItem; chat?: undefined; command?: undefined }
  | { more: string; chat?: undefined; command?: undefined; item?: undefined }
  | { back: true; chat?: undefined; command?: undefined; item?: undefined };

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
 * What a few words find in the workspace (the core's `search`, docs/search.md): its chats as the sidebar lists them, the
 * messages, and what every station finds besides (execution history, services and tasks, skills, memory, profiles,
 * stations), each kind under its heading, a few of each; 查看更多 lists that kind alone (Esc back to all). With nothing
 * typed, the latest chats. What can be done here (the keys' actions the page answers now, and what it offers:
 * commands.ts) is listed too: under the chats with nothing typed, over them once its name has what was typed.
 */
function Finder({ scope, settings, onClose, onCommand, escape }: { scope: string; settings: string; onClose(): void; onCommand(command: Listed): void; escape: { current: (() => boolean) | null } }) {
  const navigate = useNavigate();
  const [query, setQuery] = useState("");
  const [kind, setKind] = useState<string | null>(null);
  const search = useSearch({ scope, query, kind });
  const view = search.value;
  const typed = !!query.trim();
  const actions = kind ? [] : commandsFor(query);
  const chats = view?.items ?? [];
  const messages = typed ? view?.messages ?? [] : [];
  const groups = typed ? view?.groups ?? [] : [];
  escape.current = () => {
    if (kind === null) return false;
    setKind(null);
    return true;
  };
  // The list as it is drawn: headings between the rows (each row a number, what the keys move through).
  type Line = { heading: string } | { found: Found; key: string };
  const lines: Line[] = [];
  const add = (found: Found, key: string) => lines.push({ found, key });
  const heading = (text: string) => lines.push({ heading: text });
  if (kind) add({ back: true }, "back");
  if (typed) actions.forEach((command, k) => {
    if (command.group !== actions[k - 1]?.group) heading(t(`web-main.switcher.group.${command.group}`));
    add({ command }, command.id);
  });
  if (chats.length > 0 && (actions.length > 0 || typed)) heading(t("web-main.switcher.chats"));
  for (const chat of chats) add({ chat }, `c\u0001${chat.station}\u0001${chat.id}`);
  if (typed && !kind && view?.chatsMore) add({ more: "chat" }, "more:chat");
  if (!typed) actions.forEach((command, k) => {
    if (command.group !== actions[k - 1]?.group) heading(t(`web-main.switcher.group.${command.group}`));
    add({ command }, command.id);
  });
  if (messages.length > 0) heading(t("web-main.switcher.messages"));
  for (const message of messages) add({ chat: message.chat, message }, `m\u0001${message.station}\u0001${message.thread}\u0001${message.seq}`);
  if (typed && !kind && view?.messagesMore) add({ more: "message" }, "more:message");
  for (const group of groups) {
    heading(group.title);
    for (const item of group.items) add({ item }, `i\u0001${item.key}`);
    if (!kind && group.more) add({ more: group.kind }, `more:${group.kind}`);
  }
  const found = lines.flatMap((l) => ("found" in l ? [l.found] : []));
  const [at, setAt] = useState(0);
  const list = useRef<HTMLDivElement>(null);
  // Brought into view when the keys or a new query choose it, not when the pointer does: it is in view under the
  // pointer already, and scrolling it there (the list keeps clear of its corner, scroll-padding) moved the next row
  // under the pointer, which chose that one, and the list scrolled on by itself.
  const pointed = useRef(false);
  // A kind alone starts at its first find, under 全部结果.
  useEffect(() => setAt(kind ? 1 : 0), [query, kind]);
  useEffect(() => {
    if (pointed.current) { pointed.current = false; return; }
    list.current?.querySelector(`[data-at="${at}"]`)?.scrollIntoView({ block: "nearest" });
  }, [at]);
  const go = (pick: Found | undefined) => {
    if (!pick) return;
    if (pick.command) return onCommand(pick.command);
    if ("back" in pick) return setKind(null);
    if ("more" in pick) return setKind(pick.more);
    if (pick.item) {
      const to = openOf(pick.item, settings);
      if (to === null) return;
      onClose();
      return navigate(to);
    }
    onClose();
    if (pick.message) jumpTo({ station: pick.message.station, thread: pick.message.thread, seq: pick.message.seq, words: view?.words });
    navigate(`${stationBase(pick.chat.station)}/chats/${encodeURIComponent(pick.chat.id)}`);
  };
  let n = 0;
  const option = (i: number) => ({
    role: "option", "aria-selected": i === at, "data-at": i,
    onMouseMove: () => { if (i !== at) { pointed.current = true; setAt(i); } }, onClick: () => go(found[i]),
  });
  const note = typed ? [view?.wait?.text, view?.note].filter((w): w is string => !!w).join(" · ") : "";
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
        {view && found.length === 0 && !view.wait?.reading && <p className={css.none}>{query ? t("web-main.switcher.noMatch") : t("web-main.switcher.none")}</p>}
        {lines.map((line) => {
          if ("heading" in line) return <div key={`h\u0001${line.heading}\u0001${n}`} className={css.section} role="presentation">{line.heading}</div>;
          const i = n++;
          const pick = line.found;
          if ("back" in pick) return (
            <div key={line.key} className={css.row} {...option(i)}>
              <span className={`${css.picture} ${css.actionMark}`} aria-hidden="true"><ArrowLeft size={16} /></span>
              <span className={css.title}>{t("web-main.switcher.back")}</span>
            </div>
          );
          if ("more" in pick) return (
            <div key={line.key} className={`${css.row} ${css.more}`} {...option(i)}>
              <span className={`${css.picture} ${css.actionMark}`} aria-hidden="true"><More size={16} /></span>
              <span className={css.title}>{t("web-main.switcher.more")}</span>
            </div>
          );
          if (pick.command) {
            const command = pick.command;
            return (
              <div key={line.key} className={css.row} {...option(i)}>
                <span className={`${css.picture} ${css.actionMark}`} aria-hidden="true"><command.icon size={16} /></span>
                <span className={css.title}>{command.label}</span>
                {command.keys && <span className={css.meta}>{command.keys}</span>}
              </div>
            );
          }
          if (pick.item) return <ItemRow key={line.key} item={pick.item} {...option(i)} />;
          if (pick.message) {
            const message = pick.message;
            return (
              <div key={line.key} className={`${css.row} ${css.said}`} {...option(i)}>
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
            );
          }
          const item = pick.chat;
          return (
            <div key={line.key} className={css.row} {...option(i)}>
              <ChatPicture item={item} />
              <span className={css.title} data-unread={item.unread || undefined}>{item.title}</span>
              <span className={css.meta}>
                {item.archived && <span>{t("web-main.switcher.archived")}</span>}
                <span>{(item.stationEmoji || item.stationIcon) && <StationMark emoji={item.stationEmoji} icon={item.stationIcon} size={12} className={markCss.inline} />}{item.stationName}</span>
                <Time stamp={item.time?.lastActiveAt} fixed />
              </span>
            </div>
          );
        })}
        {note && <p className={css.note}>{note}</p>}
      </div>
    </>
  );
}

const KIND_ICON: Record<string, ComponentType<IconProps>> = { folder: Folder, file: File, history: Thread, job: Web, skill: Sparks, memory: Brain, profile: Quota, station: Server };

/** Something found besides a chat or a message: what it is, where (its station, when), and its line that has the words. */
function ItemRow({ item, ...rest }: { item: SearchItem } & Record<string, unknown>) {
  const Icon = KIND_ICON[item.kind === "file" && item.dir ? "folder" : item.kind] ?? CommandIcon;
  return (
    <div className={`${css.row} ${css.said}`} {...rest}>
      <span className={`${css.picture} ${css.actionMark}`} aria-hidden="true">
        {item.kind === "station" && (item.stationEmoji || item.stationIcon) ? <StationMark emoji={item.stationEmoji} icon={item.stationIcon} size={16} /> : <Icon size={16} />}
      </span>
      <span className={css.saidBody}>
        <span className={css.saidHead}>
          <span className={css.saidChat}>{item.title}</span>
          <span className={css.meta}>
            {item.kind !== "station" && <span>{(item.stationEmoji || item.stationIcon) && <StationMark emoji={item.stationEmoji} icon={item.stationIcon} size={12} className={markCss.inline} />}{item.stationName}</span>}
            <Time stamp={item.time?.createdAt} fixed />
          </span>
        </span>
        {item.text && <span className={css.saidText}><Marked text={item.text} marks={item.marks} className={css.hit} /></span>}
      </span>
    </div>
  );
}

/** Where something found opens: its chat (at a step of its history, a service, a task), a station's memory, a page of the settings. */
export function openOf(item: SearchItem, settings: string): string | null {
  const at = item.station.indexOf("/");
  const id = encodeURIComponent(at < 0 ? item.station : item.station.slice(at + 1));
  const chat = item.chat ? `${stationBase(item.station)}/chats/${encodeURIComponent(item.chat)}` : null;
  switch (item.kind) {
    case "history":
      return chat && item.session ? `${chat}?history=${encodeURIComponent(item.session)}&entry=${item.index ?? 0}` : chat;
    case "job":
      return chat && item.job ? `${chat}?${item.port != null ? "service" : "job"}=${encodeURIComponent(item.job)}` : chat;
    case "skill":
      return item.skill ? `${settings}/memory/${id}/skill/${encodeURIComponent(item.skill)}` : `${settings}/memory`;
    case "memory":
      return `${settings}/memory/${id}/global`;
    case "profile":
      return `${settings}/profiles`;
    case "station":
      return `${settings}/stations/${id}`;
    case "file":
      return item.path ? fileOpen(stationBase(item.station), item) : null;
    default:
      return chat;
  }
}


function ChatPicture({ item }: { item: ChatItem }) {
  return (
    <span className={css.picture} aria-hidden="true">
      {item.agents[0] ? <ModelLogo maker={item.agents[0].maker} runtime={item.agents[0].runtime} size={18} /> : <Mark size={16} />}
    </span>
  );
}
