// The shortcuts that belong to no page (keymap.ts), and ⌘K's switcher: a chat found by typing part of its title, a
// message by its words, or something to do here by its name (↑/↓ pick, ↩ opens, Esc closes, as everywhere; nothing
// says so).
import { Dialog as RDialog } from "radix-ui";
import { memo, useEffect, useRef, useState, useSyncExternalStore, type ComponentType } from "react";
import { useNavigate } from "react-router";
import { useGo } from "./go.ts";
import { useSearch, type ChatItem } from "./api.ts";
import type { CommandGroup, CommandsFound, FoundMessage, SearchItem, SearchOpen } from "./core/shapes.ts";
import { useCall } from "./core/react.ts";
import { Marked } from "./Marked.tsx";
import { jumpTo } from "./jumpTo.ts";
import { Mark } from "./brand.tsx";
import { commands, useCommands, type Command } from "./commands.ts";
import { webUpdates } from "./core/webUpdates.ts";
import { Archive, ArrowDown, ArrowLeft, ArrowRight, ChevronDown, ChevronUp, Close, Command as CommandIcon, Compose, Edit, File, Folder, Keyboard, Monitor, More, PanelOpen, Refresh, Search, Server, Settings, Stop, Thread, User, Web, type IconProps } from "@stillfail/ui/icons.tsx";
import { availableActions, runAction, shortcutOf, useShortcut, type Action } from "./keymap.ts";
import { ShortcutsDialog } from "./Shortcuts.tsx";
import { RelayHost } from "./Relay.tsx";
import { stationBase } from "./station.tsx";
import { filesPath } from "./searchOpen.ts";
import { Keys, ModelLogo, Time, capsOf } from "./ui.tsx";
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
  useCommands(useUpdateCommands());
  return (
    <>
      <ChatSwitcher scope={scope} settings={settings} open={switching} onClose={() => setSwitching(false)} />
      <ShortcutsDialog open={listing} onClose={() => setListing(false)} />
      <RelayHost />
    </>
  );
});

/** Updating what runs here: the page to a newer build of it (as the sidebar's foot offers). */
function useUpdateCommands(): Command[] {
  const page = useSyncExternalStore(webUpdates.subscribe, webUpdates.snapshot, () => null);
  return page ? [{ id: "update.page", icon: Refresh, run: webUpdates.refresh }] : [];
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

/** What can be done, as offered here: with the keys that do it too when it is a key's action. */
type Offered = Command & { keys?: string | null };

/** A command as the list shows it: its name and its part (`group`, headed `heading`), as the core says. */
type Listed = { id: string; group: string; heading: string; label: string; icon: ComponentType<IconProps>; keys?: string | null; run(): void };

const ACTION_ICON: Partial<Record<Action, ComponentType<IconProps>>> = {
  "chat.new": Compose, "settings": Settings, "shortcuts": Keyboard, "sidebar.toggle": PanelOpen,
  "chat.prev": ChevronUp, "chat.next": ChevronDown, "nav.back": ArrowLeft, "nav.forward": ArrowRight,
  "composer.focus": Edit, "composer.file": File, "chat.stop": Stop, "chat.history": Thread, "chat.jobs": Web, "chat.screen": Monitor,
  "chat.latest": ArrowDown, "chat.find": Search, "chat.archive": Archive, "panel.close": Close,
};

/** What can be done now: the keys' actions the page answers (which of them are worth listing is the core's), and what it offers. */
function offered(): Offered[] {
  return [...availableActions().map((action) => ({ id: action, icon: ACTION_ICON[action] ?? CommandIcon, keys: shortcutOf(action), run: () => runAction(action) })), ...commands()];
}

/** The last answer, so the list opened again has it at once while the core answers anew. */
let kept: { asked: string; groups: CommandGroup[] } | null = null;

/**
 * What of what can be done now the core lists for what was typed (`commands.find`: by name, id or other words, part by
 * part; with nothing typed all but what is only found by typing), each with its name; while it answers anew, what it
 * listed last.
 */
function useFoundCommands(query: string, all: Offered[]): Listed[] {
  const call = useCall();
  const asked = JSON.stringify({ query, offered: all.map(({ id, label, group, words, typed, version, station }) => ({ id, label, group, words, typed, version, station })) });
  const [groups, setGroups] = useState<CommandGroup[]>(() => (kept?.asked === asked ? kept.groups : []));
  useEffect(() => {
    let live = true;
    call("commands.find", JSON.parse(asked)).then((found) => {
      const got = (found as CommandsFound).groups;
      kept = { asked, groups: got };
      if (live) setGroups(got);
    }, () => undefined);
    return () => { live = false; };
  }, [asked, call]);
  const byId = new Map(all.map((c) => [c.id, c]));
  return groups.flatMap((group) => group.commands.flatMap((found) => {
    const c = byId.get(found.id);
    return c ? [{ id: c.id, group: group.group, heading: group.title, label: found.label, icon: c.icon, keys: c.keys ?? null, run: c.run }] : [];
  }));
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
  const listed = useFoundCommands(query, offered());
  const actions = kind ? [] : listed;
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
    if (command.group !== actions[k - 1]?.group) heading(command.heading);
    add({ command }, command.id);
  });
  if (chats.length > 0 && (actions.length > 0 || typed)) heading(t("web-main.switcher.chats"));
  for (const chat of chats) add({ chat }, `c\u0001${chat.station}\u0001${chat.id}`);
  if (typed && !kind && view?.chatsMore) add({ more: "chat" }, "more:chat");
  if (!typed) actions.forEach((command, k) => {
    if (command.group !== actions[k - 1]?.group) heading(command.heading);
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
      const to = pick.item.open ? pathOf(pick.item.open, settings) : null;
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
      <label className={css.searchBar}>
        <Search size={18} className={css.searchMark} aria-hidden="true" />
        <input className={css.search} autoFocus placeholder={t("web-main.switcher.search")} aria-label={t("web-main.switcher.search")} value={query} spellCheck={false}
        onChange={(e) => setQuery(e.target.value)}
        onKeyDown={(e) => {
          if (e.nativeEvent.isComposing) return;
          const step = e.key === "ArrowDown" || e.ctrlKey && e.key === "n" ? 1 : e.key === "ArrowUp" || e.ctrlKey && e.key === "p" ? -1 : 0;
          if (step) { e.preventDefault(); setAt((a) => Math.max(0, Math.min(found.length - 1, a + step))); }
          else if (e.key === "Enter") { e.preventDefault(); go(found[at]); }
        }} />
      </label>
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
                {command.keys && <Keys caps={capsOf(command.keys)} />}
              </div>
            );
          }
          if (pick.item) return <ItemRow key={line.key} item={pick.item} {...option(i)} />;
          // A message found: what it says with the words first, the chat it is in under it.
          if (pick.message) {
            const message = pick.message;
            return (
              <div key={line.key} className={`${css.row} ${css.said}`} {...option(i)}>
                <ChatPicture item={message.chat} />
                <span className={css.saidBody}>
                  <span className={css.saidHead}>
                    <span className={css.saidChat}><Marked text={message.text} marks={message.marks} className={css.hit} /></span>
                    <span className={css.meta}>
                      {message.by && <span>{message.by}</span>}
                      <Time stamp={message.time?.createdAt} fixed />
                    </span>
                  </span>
                  <span className={css.saidText}>{message.chat.title}</span>
                </span>
              </div>
            );
          }
          const item = pick.chat;
          const meta = (
            <span className={css.meta}>
              {item.archived && <span>{t("web-main.switcher.archived")}</span>}
              <span>{(item.stationEmoji || item.stationIcon) && <StationMark emoji={item.stationEmoji} icon={item.stationIcon} size={12} className={markCss.inline} />}{item.stationName}</span>
              <Time stamp={item.time?.lastActiveAt} fixed />
            </span>
          );
          // Found by words its title shows late or not at all: the part of it that has them first, its title under it.
          if (item.foundText) {
            return (
              <div key={line.key} className={`${css.row} ${css.said}`} {...option(i)}>
                <ChatPicture item={item} />
                <span className={css.saidBody}>
                  <span className={css.saidHead}>
                    <span className={css.saidChat}><Marked text={item.foundText} marks={item.foundMarks ?? []} className={css.hit} /></span>
                    {meta}
                  </span>
                  <span className={css.saidText} data-unread={item.unread || undefined}>{item.title}</span>
                </span>
              </div>
            );
          }
          return (
            <div key={line.key} className={css.row} {...option(i)}>
              <ChatPicture item={item} />
              <span className={css.title} data-unread={item.unread || undefined}>{item.title}</span>
              {meta}
            </div>
          );
        })}
        {note && <p className={css.note}>{note}</p>}
      </div>
      <div className={css.foot} aria-hidden="true">
        <span className={css.hint}><Keys caps={["↑", "↓"]} />{t("web-main.switcher.hint.move")}</span>
        <span className={css.hint}><Keys caps={["↩"]} />{t("web-main.switcher.hint.open")}</span>
        <span className={css.hint}><Keys caps={["Esc"]} />{t("web-main.switcher.hint.close")}</span>
      </div>
    </>
  );
}

const KIND_ICON: Record<string, ComponentType<IconProps>> = { folder: Folder, file: File, job: Web, station: Server, member: User };

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

/** The page where something found opens (`SearchItem.open`, the core's): its chat (a service's page over it, a task
 *  picked), a station's page, the workspace's members, a place in a station's files. */
export function pathOf(open: SearchOpen, settings: string): string | null {
  const at = open.station.indexOf("/");
  const id = encodeURIComponent(at < 0 ? open.station : open.station.slice(at + 1));
  const chat = open.chat ? `${stationBase(open.station)}/chats/${encodeURIComponent(open.chat)}` : null;
  switch (open.to) {
    case "service":
    case "task":
      return chat && open.job ? `${chat}?${open.to === "service" ? "service" : "job"}=${encodeURIComponent(open.job)}` : chat;
    case "station":
      return `${settings}/stations/${id}`;
    case "members":
      return `${settings}/workspace`;
    case "files":
      return filesPath(stationBase(open.station), open);
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
