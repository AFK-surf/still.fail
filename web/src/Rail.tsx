// The rail at the wide screen's left, in one block with the sidebar (styles/shell.css.ts dock), whose edge (SidebarEdge,
// in the page's gutter by it) drags the sidebar's width and, pressed, closes or opens it (no button for it; its shortcut
// still). In it the places the
// person chose on this device (prefs `rail`, 外观's 侧边条: which, in what order; RAIL_DEFAULT when none was chosen):
// 对话 and the lists of chats beside it (我参与的, 监控中, the archive), 奏 (the word, as the desktop has always had it,
// a dot while some wait for the viewer), 待处理 (what wants them in every workspace), 文件, the stations' glyph, Profile,
// 连接, 用量; at its foot every workspace to switch to (each with what waits in it; a ＋ over them, as the pointer comes,
// for making one, another account, invitations) and under them the settings, which are not among what is chosen. It is
// changed where it is: its menu's 自定义侧边条 (or 外观's) has its places dragged up and down (any time, held with ⌘), taken out with their −,
// added from a panel beside it by kind; a place's own menu takes it out. Its menu goes to those left out too, the one in
// view shown at the foot of its places while it is (useRailItems). Station, 连接 and 用量 in it are pages of their
// own beside the chats, Profile its list in the sidebar (ProfilesNav.tsx) and the one picked beside; left out of it,
// they are among the settings. The sidebar beside shows the chats (or 奏, one of their lists), the folders the stations
// lend (FilesNav, cloud/workspace.tsx), the profiles or the settings; coming to the last three with it closed opens it.
// On a narrow screen there is none: the sidebar's foot keeps the switcher and the settings.
import { useEffect, useLayoutEffect, useRef, useState, useSyncExternalStore, type ComponentType, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { DropdownMenu, Popover } from "radix-ui";
import { NavLink, useLocation, useNavigate } from "react-router";
import { Archive, Bell, Chart, Chats, Download, Folder, Im, Minus, Plus, Quota, Retry, Settings, Sliders, User, Watch, type IconProps } from "./icons.tsx";
import { ICON, PanelGroup, PanelHead, PanelNote, PanelRow, setKeptWidth, Tip, usePointerTip } from "./ui.tsx";
import { lastChatOf, useLastChat, useWorkspaceMarks } from "./lastChat.ts";
import { useSidebarMode, type SidebarMode } from "./station.tsx";
import { AttentionEntry } from "./Attention.tsx";
import { useWorkspaces } from "./cloud/api.ts";
import * as chatMarkCss from "./ChatMark.css.ts";
import { setPrefs, usePrefs } from "./prefs.ts";
import * as controlsCss from "./styles/controls.css.ts";
import { RailStations } from "./Sidebar.tsx";
import { isPicture } from "./StationMark.tsx";
import { marked, WorkspaceMark } from "./WorkspaceMark.tsx";
import { openedAt } from "./DecisionDesk.tsx";
import { moveSidebar, onSidebarChosen, showSidebar, useSidebarToggle } from "./brand.tsx";
import * as shellCss from "./styles/shell.css.ts";
import { reducedMotion } from "./motion.ts";
import * as css from "./Rail.css.ts";
import * as uiCss from "./ui.css.ts";
import { androidQr, download, downloadsOffered } from "./downloads.ts";
import { t } from "./i18n.ts";

/** Every place the rail can show, in the order the settings list them when none was chosen. */
export const RAIL_ITEMS = ["chats", "mine", "watching", "archive", "decisions", "attention", "files", "stations", "profiles", "connects", "usage"] as const;
export type RailItem = (typeof RAIL_ITEMS)[number];
/** What it shows when none was chosen. */
export const RAIL_DEFAULT: readonly RailItem[] = ["attention", "chats", "files", "stations", "profiles", "connects", "usage"];

/** What the rail shows, in its order: as kept (what this build does not know left out). */
export function railItems(kept: readonly string[] | null | undefined): RailItem[] {
  if (!kept) return [...RAIL_DEFAULT];
  return [...new Set(kept.filter((k): k is RailItem => (RAIL_ITEMS as readonly string[]).includes(k)))];
}

/** A place's name, as the rail's tip and the settings say it. */
export function railLabel(item: RailItem): string {
  switch (item) {
    case "chats": return t("web-main.rail.chats");
    case "mine": return t("web-main.filter.chats.mine");
    case "watching": return t("web-main.filter.watching");
    case "archive": return t("web-main.filter.archived");
    case "decisions": return t("web-main.rail.decisions");
    case "attention": return t("web-main.attention.entry");
    case "files": return t("web-pages.drive.title");
    case "stations": return "Station";
    case "profiles": return "Profile";
    case "connects": return t("web-pages.settings.nav.connects");
    case "usage": return t("web-pages.settings.nav.usage");
  }
}

/** The icons of the places drawn as one (the stations' is their glyph, 奏 its word, the workspaces each its letter). */
export const RAIL_ICONS: Partial<Record<RailItem, ComponentType<IconProps>>> = {
  chats: Chats, mine: User, watching: Watch, archive: Archive, attention: Bell, files: Folder, profiles: Quota, connects: Im, usage: Chart,
};

/** Which place the page is in, by its path: the files' and the settings' pages have the sidebar of their own. */
export type Place = "chats" | "archive" | "files" | "stations" | "profiles" | "connects" | "usage" | "settings";

export function placeOf(path: string): Place {
  if (/^\/w\/[^/]+\/(files|s\/[^/]+\/files)(\/|$)/.test(path)) return "files";
  if (/^\/w\/[^/]+\/archive$/.test(path)) return "archive";
  if (/^\/w\/[^/]+\/settings\/stations(\/|$)/.test(path)) return "stations";
  if (/^\/w\/[^/]+\/(settings\/profiles|s\/[^/]+\/settings\/accounts)(\/|$)/.test(path)) return "profiles";
  if (/^\/w\/[^/]+\/(settings\/connects|s\/[^/]+\/connects)(\/|$)/.test(path)) return "connects";
  if (/^\/w\/[^/]+\/settings\/usage(\/|$)/.test(path)) return "usage";
  if (/^\/w\/[^/]+\/(settings|s\/[^/]+\/settings)(\/|$)/.test(path)) return "settings";
  return "chats";
}

/** The lists of chats the rail can lead to, by the sidebar's mode they are. */
const LISTS: Partial<Record<RailItem, SidebarMode>> = { chats: "all", mine: "mine", watching: "watching", decisions: "decisions" };

/** What can be put in the rail, by its kind, as the panel that adds them groups them. */
const KINDS: { title: string; items: RailItem[] }[] = [
  { title: "web-main.rail.kind.places", items: ["files", "stations", "profiles", "connects", "usage"] },
  { title: "web-main.rail.kind.lists", items: ["chats", "mine", "watching", "archive", "decisions"] },
  { title: "web-main.rail.kind.attention", items: ["attention"] },
];

/** Whether the rail is being changed (Rail's own menu, or 外观's button): the page's, not kept. */
let editing = false;
const editors = new Set<() => void>();
export function editRail(on: boolean): void {
  editing = on;
  for (const f of editors) f();
}
function useEditing(): boolean {
  return useSyncExternalStore((f) => { editors.add(f); return () => editors.delete(f); }, () => editing, () => false);
}

/**
 * A place left out of the rail but in view, shown at the foot of its places as one of them until the page goes elsewhere:
 * picked from the rail's menu, or (a list of chats, 奏, the archive, the files) come to some other way. The page's, not
 * kept.
 */
let extra: RailItem | null = null;
const extraWatchers = new Set<() => void>();
function setExtra(item: RailItem | null): void {
  if (extra === item) return;
  extra = item;
  for (const f of extraWatchers) f();
}
function useExtra(): RailItem | null {
  return useSyncExternalStore((f) => { extraWatchers.add(f); return () => extraWatchers.delete(f); }, () => extra, () => null);
}

/** What the rail has now, as the pages in it go by: the places kept, and the one left out of it in view. */
export function useRailItems(): RailItem[] {
  const items = railItems(usePrefs((p) => p.rail));
  const shown = useExtra();
  return shown && !items.includes(shown) ? [...items, shown] : items;
}

export function Rail({ scope, workspace }: { scope: string; workspace: ReactNode }) {
  const location = useLocation();
  const place = placeOf(location.pathname);
  const [mode, setMode] = useSidebarMode();
  const navigate = useNavigate();
  const last = useLastChat(scope, `/w/${scope}/new`) ?? `/w/${scope}`;
  const here = useWorkspaceMarks(scope)?.workspaces[scope];
  const waiting = here?.decisions ?? 0;
  // What wants the person in each list of chats (the core's marks), on its icon while the sidebar is closed.
  const tones: Partial<Record<RailItem, string | undefined>> = { chats: here?.tone, mine: here?.mineTone, watching: here?.watchingTone };
  const kept = usePrefs((p) => p.rail);
  // The places kept (what is changed), and with them the one left out in view (what the pages go by).
  const items = railItems(kept);
  const railed = useRailItems();
  const added = railed.find((i) => !items.includes(i)) ?? null;
  const changing = useEditing();
  // Dragged in the rail: the order as it would be let go of now (and, let go of, until the kept order is it: no frame of
  // the old one between).
  const [dragged, setDragged] = useState<{ item: RailItem | null; order: RailItem[] } | null>(null);
  useEffect(() => { if (dragged && !dragged.item && dragged.order.join() === items.join()) setDragged(null); }, [dragged, items]);
  const slots = useRef(new Map<RailItem, HTMLElement>());
  // Right-clicked: the place under the pointer, to take out.
  // Right-clicked: the place under the pointer (to take out) and where the menu stands, by the place (or the rail), not
  // the pointer.
  const [menu, setMenu] = useState<{ item: RailItem | null; box: { left: number; top: number; width: number; height: number } } | null>(null);
  const pointed = menu?.item ?? null;
  const keep = (next: RailItem[]) => setPrefs({ rail: next });
  // The place dragged under the pointer, lifted; the others moving out of its way (each from where it was drawn to its
  // new place), and it, let go of, to its own. Its place among them by their places, not where they are drawn moving.
  const pointerY = useRef(0);
  const grabbed = useRef(0);
  const drawnAt = useRef(new Map<RailItem, number>());
  // What moves: the place's slot while the rail is changed; otherwise (held with ⌘) the place itself, its slot being
  // nothing of its own in the layout.
  const box = (item: RailItem) => {
    const el = slots.current.get(item);
    return changing ? el : (el?.firstElementChild as HTMLElement | null | undefined);
  };
  const follow = (item: RailItem) => {
    const el = box(item);
    if (el) el.style.transform = `translateY(${pointerY.current - grabbed.current - el.offsetTop}px) scale(1.06)`;
  };
  const drawnChanging = useRef(changing);
  useLayoutEffect(() => {
    // Changed or no longer: other boxes (the slots, or the places), not where these were.
    const was = drawnChanging.current === changing ? drawnAt.current : new Map<RailItem, number>();
    drawnChanging.current = changing;
    const now = new Map<RailItem, number>();
    for (const item of slots.current.keys()) {
      const el = box(item);
      if (!el) continue;
      now.set(item, el.offsetTop);
      if (item === dragged?.item) continue;
      const from = was.get(item);
      // Only while they are moved about (or changed): the rail's own changes of length move them too.
      if ((changing || dragged) && from !== undefined && from !== el.offsetTop && !reducedMotion()) {
        el.animate([{ transform: `translateY(${from - el.offsetTop}px)` }, { transform: "none" }], { duration: 220, easing: "cubic-bezier(.2, .7, .2, 1)" });
      }
    }
    drawnAt.current = now;
    if (dragged?.item) follow(dragged.item);
  });
  // While the rail is changed, a place pressed is dragged; otherwise one pressed with ⌘ held, once the pointer has moved
  // (⌘ pressed and let go of where it was is the place's own ⌘-press), and then let go of it is not pressed.
  const drag = (item: RailItem) => (e: ReactPointerEvent) => {
    if (e.button !== 0 || !(changing || e.metaKey)) return;
    if (changing) e.preventDefault();
    let order = items;
    const el = box(item);
    const top = (el?.offsetParent as HTMLElement | null)?.getBoundingClientRect().top ?? 0;
    pointerY.current = e.clientY - top;
    grabbed.current = pointerY.current - (el?.offsetTop ?? 0);
    let started = changing;
    if (started) setDragged({ item, order });
    const move = (ev: PointerEvent) => {
      if (!started) {
        if (Math.abs(ev.clientY - e.clientY) < 4) return;
        started = true;
        // Not left focused by the press (its ring round it as it moves).
        if (el?.contains(document.activeElement)) (document.activeElement as HTMLElement).blur();
        setDragged({ item, order });
      }
      pointerY.current = ev.clientY - top;
      follow(item);
      // Where the pointer is among the others' middles.
      const rest = order.filter((i) => i !== item);
      let at = rest.length;
      for (let i = 0; i < rest.length; i++) {
        const other = box(rest[i]!);
        if (other && pointerY.current < other.offsetTop + other.offsetHeight / 2) { at = i; break; }
      }
      const next = [...rest.slice(0, at), item, ...rest.slice(at)];
      if (next.join() !== order.join()) { order = next; setDragged({ item, order }); }
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      if (!started) return;
      if (!changing) {
        const swallow = (ev: MouseEvent) => { ev.preventDefault(); ev.stopPropagation(); };
        window.addEventListener("click", swallow, { capture: true, once: true });
        setTimeout(() => window.removeEventListener("click", swallow, { capture: true }));
      }
      const held = box(item);
      if (held) {
        const from = held.style.transform;
        held.style.transform = "";
        if (from && !reducedMotion()) held.animate([{ transform: from }, { transform: "none" }], { duration: 200, easing: "cubic-bezier(.2, .7, .2, 1)" });
      }
      if (order.join() !== items.join()) { setDragged({ item: null, order }); keep(order); } else setDragged(null);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };
  // Holds the sidebar's shortcut (its toggle, as the edge's, is the person's choice: kept for the place's sidebar).
  const sidebar = useSidebarToggle();
  const shut = () => document.documentElement.dataset.sidebar === "closed";
  // The place's sidebar as its tab was left: open, or folded (shown a while over the page as its tab is pressed or
  // pointed at, then folded again: peekSidebar). A page in the rail with none of its own (连接, 用量) or the archive has it
  // closed: the page the whole width. Only on a wide screen: on a narrow one the sidebar is a page of its own.
  const own = place === "settings" || place === "files" || place === "stations" || place === "profiles" || place === "chats" || !railed.includes(place as RailItem);
  // Which sidebar it is, each as wide as it was made and open or folded as it was left.
  const group: SidebarGroup = place === "files" ? "files" : place === "profiles" && railed.includes("profiles") ? "profiles"
    : place === "stations" && railed.includes("stations") ? "stations"
    : place === "chats" || place === "archive" || railed.includes(place as RailItem) ? "chats" : "settings";
  const now = useRef({ own, group });
  now.current = { own, group };
  useEffect(() => {
    onSidebarChosen((closed) => { foldGroup(now.current.group, closed); if (!closed) endPeek(); });
    return () => onSidebarChosen(null);
  }, []);
  const cameFrom = useRef<Place | null>(null);
  useEffect(() => {
    const moved = cameFrom.current !== null && cameFrom.current !== place;
    cameFrom.current = place;
    if (!matchMedia("(min-width: 701px)").matches) return;
    if (moved) endPeek();
    // A page with no sidebar of its own: none to open (its edge gone, its shortcut nothing; brand.tsx).
    if (own) delete document.documentElement.dataset.sidebarNone;
    else document.documentElement.dataset.sidebarNone = "";
    // Pressed into a folded sidebar from an open one, it is shown a while from the start: the block stays out over the
    // page as the page takes the room back, not closing to the bar and opening again.
    const pressed = asked.current;
    asked.current = false;
    const open = own && !folded(group);
    const peeks = pressed && own && !open && !("sidebarPeek" in document.documentElement.dataset);
    // Its width with it, in the same move (or by itself, gliding if shown).
    const width = widthFor(group);
    const apply = () => { width?.(); if (peeks) markPeek(); };
    if (shut() !== open) { if (width || peeks) (peeks || (moved && !shut()) ? moveSidebar(apply) : apply()); }
    else showSidebar(open, apply);
  }, [place, own, group]); // eslint-disable-line react-hooks/exhaustive-deps
  // Its tab pressed or pointed at, the place's own sidebar shown: open as it is, or a while if folded. Pressed, once its
  // place has come (the effect above), or soon if it was already there.
  const reveal = () => { if (now.current.own && folded(now.current.group)) peekSidebar(); };
  const asked = useRef(false);
  const revealPressed = () => {
    asked.current = true;
    setTimeout(() => { if (asked.current) { asked.current = false; reveal(); } }, 60);
  };
  const settings = `/w/${scope}/settings`;
  // The settings lit (in them, or a place left out of the rail), pressed again, go back to where they were come to from:
  // the page last shown with them unlit, the last chat when the settings were where the page was opened.
  const inSettings = place === "settings" || (place !== "chats" && !railed.includes(place as RailItem));
  const before = useRef<string | null>(null);
  useEffect(() => { if (!inSettings) before.current = location.pathname + location.search; }, [inSettings, location.pathname, location.search]);
  // A list of chats lit while the sidebar shows it; 对话 for one not in the rail.
  const shownList = (Object.keys(LISTS) as RailItem[]).find((i) => LISTS[i] === mode && railed.includes(i)) ?? "chats";
  const on = (item: RailItem) => LISTS[item] ? place === "chats" && shownList === item : place === item;
  const toList = (item: RailItem) => () => { setMode(LISTS[item]!); if (place !== "chats") navigate(last); revealPressed(); };
  // A place left out of the rail in view: a list of chats or 奏 shown, the archive, the files. Station, Profile, 连接 and
  // 用量 left out are among the settings, so only as picked from the menu (go); gone once the page is elsewhere.
  const inView: RailItem | null = place === "chats" ? (Object.keys(LISTS) as RailItem[]).find((i) => LISTS[i] === mode) ?? null
    : place === "archive" || place === "files" ? place : null;
  const at = `${place} ${mode}`;
  const wasAt = useRef(at);
  useEffect(() => {
    const moved = wasAt.current !== at;
    wasAt.current = at;
    if (inView && !items.includes(inView)) setExtra(inView);
    else if (moved && extra && !(LISTS[extra] ? place === "chats" && mode === LISTS[extra] : place === extra)) setExtra(null);
  }, [at, inView, items.join()]); // eslint-disable-line react-hooks/exhaustive-deps
  // Picked from the rail's menu, one left out of it: there, and it at the rail's foot while it is.
  const go = (item: RailItem) => {
    setExtra(item);
    switch (item) {
      case "chats": case "mine": case "watching": return toList(item)();
      case "decisions": setMode("decisions"); navigate(`/w/${scope}/decisions`); return revealPressed();
      case "archive": case "files": return navigate(`/w/${scope}/${item}`);
      case "stations": case "profiles": case "connects": case "usage": return navigate(`${settings}/${item}`);
      case "attention": return;
    }
  };
  // What the menu offers to go to: what is left out of the rail, but the attention (a panel, not a place).
  const away = RAIL_ITEMS.filter((i) => !items.includes(i) && i !== "attention" && i !== added);
  const link = (item: RailItem, to: string) => {
    const Icon = RAIL_ICONS[item]!;
    return (
      <Tip key={item} label={railLabel(item)} side="right">
        <NavLink className={css.item} to={to} data-on={on(item) || undefined} aria-label={railLabel(item)}><Icon size={20} /></NavLink>
      </Tip>
    );
  };
  const drawn = (item: RailItem): ReactNode => {
    switch (item) {
      case "chats": case "mine": case "watching": {
        const Icon = RAIL_ICONS[item]!;
        return (
          <Tip key={item} label={railLabel(item)} side="right">
            <button type="button" className={css.item} data-on={on(item) || undefined} aria-label={railLabel(item)} onClick={toList(item)}>
              <Icon size={20} />
              {tones[item] && <span className={css.listMark}><span className={chatMarkCss.chatMarkInline} data-tone={tones[item]} /></span>}
            </button>
          </Tip>
        );
      }
      case "decisions": return (
        <Tip key={item} label={waiting > 0 ? t("web-main.decisions.entry", { n: waiting }) : railLabel(item)} side="right">
          <button type="button" className={css.item} data-on={on(item) || undefined} aria-label={railLabel(item)}
            onClick={(e) => { openedAt(e.currentTarget); setMode("decisions"); navigate(`/w/${scope}/decisions`); revealPressed(); }}>
            <span className={css.zou} aria-hidden="true">奏</span>
            {waiting > 0 && <span className={css.count} />}
          </button>
        </Tip>
      );
      case "archive": return link(item, `/w/${scope}/archive`);
      case "attention": return <AttentionEntry key={item} scope={scope} rail={{ item: css.item, count: css.count, label: railLabel(item) }} />;
      case "files": return link(item, `/w/${scope}/files`);
      case "stations": return <RailStations key={item} scope={scope} to={`${settings}/stations`} on={on(item)} className={css.item} />;
      case "profiles": return link(item, `${settings}/profiles`);
      case "connects": return link(item, `${settings}/connects`);
      case "usage": return link(item, `${settings}/usage`);
    }
  };
  const hidden = KINDS.map((k) => ({ ...k, items: k.items.filter((i) => !items.includes(i)) })).filter((k) => k.items.length > 0);
  const rail = (
    <nav className={css.rail} aria-label={t("web-main.rail.label")} data-editing={changing || undefined}
      // A tab pressed (after its place has come), or the lit one pointed at: its sidebar shown (reveal).
      onClickCapture={(e) => {
        const pressed = changing ? null : (e.target as Element).closest(`.${css.item}`);
        if (!pressed) return;
        // The lit place pressed again (not 待处理, a panel): its sidebar opened or closed, as by the edge, not gone to.
        const slot = pressed.closest("[data-rail-item]");
        if (pressed.hasAttribute("data-on") && slot && slot.getAttribute("data-rail-item") !== "attention" && now.current.own) {
          e.preventDefault();
          e.stopPropagation();
          asked.current = false;
          sidebar.toggle();
          return;
        }
        revealPressed();
      }}
      onPointerOver={(e) => { if (!changing && e.pointerType === "mouse" && (e.target as Element).closest(`.${css.item}[data-on]`)) reveal(); }}
      onContextMenu={(e) => {
        if (changing) return;
        e.preventDefault();
        const slot = (e.target as HTMLElement).closest("[data-rail-item]");
        // Off a place, by the first (the rail's top). A place's slot is laid out by what is in it (display: contents):
        // its box is its first child's.
        const by = slot ?? e.currentTarget.querySelector("[data-rail-item]");
        const at = (by?.firstElementChild ?? e.currentTarget).getBoundingClientRect();
        setMenu({ item: (slot?.getAttribute("data-rail-item") as RailItem | null) ?? null, box: { left: at.left, top: at.top, width: at.width, height: at.height } });
      }}>
      <div className={css.top} />
      {(dragged?.order ?? items).map((item) => changing ? (
        <div key={item} ref={(el) => { if (el) slots.current.set(item, el); else slots.current.delete(item); }} className={css.editing}
          data-dragged={dragged?.item === item || undefined} onPointerDown={drag(item)} title={railLabel(item)}>
          <div className={css.still}>{drawn(item)}</div>
          <button type="button" className={css.remove} aria-label={t("web-main.rail.remove", { name: railLabel(item) })}
            onPointerDown={(e) => e.stopPropagation()} onClick={() => keep(items.filter((i) => i !== item))}><Minus size={12} strokeWidth={2.5} /></button>
        </div>
      ) : (
        <div key={item} ref={(el) => { if (el) slots.current.set(item, el); else slots.current.delete(item); }} data-rail-item={item}
          className={css.slot} data-dragged={dragged?.item === item || undefined} onPointerDown={drag(item)}
          onDragStart={(e) => { if (e.metaKey) e.preventDefault(); }}>{drawn(item)}</div>
      ))}
      {/* Left out of it but in view: at the foot of the places, not moved or taken out (it is not kept). */}
      {!changing && added && <div key={`added-${added}`} data-rail-item={added} className={css.slot}>{drawn(added)}</div>}
      <div className={css.grow} />
      {/* Every workspace at the foot, always, not one of the places chosen: the one in view its switcher. */}
      <RailWorkspaces scope={scope} current={workspace} />
      {/* In a browser, the apps to download (the desktop app has itself). */}
      {downloadsOffered() && <RailDownload />}
      {/* A place left out of the rail is reached in the settings: they are lit while in it. */}
      <Tip label={t("web-pages.settings.title")} side="right">
        <NavLink className={css.item} to={settings} data-on={inSettings || undefined} aria-label={t("web-pages.settings.title")}
          onClick={(e) => { if (inSettings) { e.preventDefault(); navigate(before.current ?? last); } }}><Settings size={20} /></NavLink>
      </Tip>
    </nav>
  );
  return (
    <Popover.Root open={changing} onOpenChange={(open) => { if (!open) editRail(false); }}>
      <Popover.Anchor asChild>{rail}</Popover.Anchor>
      <DropdownMenu.Root modal={false} open={menu !== null} onOpenChange={(open) => { if (!open) setMenu(null); }}>
        <DropdownMenu.Trigger asChild>
          <span aria-hidden="true" tabIndex={-1} style={{ position: "fixed", pointerEvents: "none", ...(menu?.box ?? { left: 0, top: 0, width: 0, height: 0 }) }} />
        </DropdownMenu.Trigger>
        <DropdownMenu.Portal>
          <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList}`} side="right" align="start" sideOffset={8}
            collisionPadding={{ top: 52, right: 8, bottom: 8, left: 8 }}
            // Not back to its anchor (by the rail, not in it): the change it opens would take that for going elsewhere.
            onCloseAutoFocus={(e) => e.preventDefault()}>
            {away.length > 0 && <>
              <DropdownMenu.Label className={controlsCss.menuLabel}>{t("web-main.rail.away")}</DropdownMenu.Label>
              {away.map((i) => {
                const Icon = RAIL_ICONS[i];
                return (
                  <DropdownMenu.Item key={i} className={controlsCss.menuItem} onSelect={() => go(i)}>
                    {Icon ? <Icon {...ICON} /> : i === "decisions" ? <span className={css.zouSmall}>奏</span> : <span style={{ width: ICON.size }} />}{railLabel(i)}
                  </DropdownMenu.Item>
                );
              })}
              <DropdownMenu.Separator className={controlsCss.menuSep} />
            </>}
            {pointed && items.includes(pointed) && (
              <DropdownMenu.Item className={controlsCss.menuItem} onSelect={() => keep(items.filter((i) => i !== pointed))}><Minus {...ICON} />{t("web-main.rail.remove", { name: railLabel(pointed) })}</DropdownMenu.Item>
            )}
            <DropdownMenu.Item className={controlsCss.menuItem} onSelect={() => editRail(true)}><Sliders {...ICON} />{t("web-main.rail.customize")}</DropdownMenu.Item>
            {kept && <DropdownMenu.Item className={controlsCss.menuItem} onSelect={() => setPrefs({ rail: null })}><Retry {...ICON} />{t("web-main.rail.reset")}</DropdownMenu.Item>}
          </DropdownMenu.Content>
        </DropdownMenu.Portal>
      </DropdownMenu.Root>
      <Popover.Portal>
        {/* Beside the rail while it is changed: what can be added, by kind. Pressing in the rail does not close it; anywhere
            else (or Esc) ends the change, there is no button for it. 恢复默认 is in the rail's menu. */}
        <Popover.Content className={`${controlsCss.popover} ${css.adder}`} side="right" align="start" sideOffset={8}
          // Clear of the top row: the macOS window's buttons are in it.
          collisionPadding={{ top: 52, right: 8, bottom: 8, left: 8 }}
          onOpenAutoFocus={(e) => e.preventDefault()}
          onInteractOutside={(e) => { if ((e.target as HTMLElement | null)?.closest(`.${css.rail}`)) e.preventDefault(); }}>
          <PanelHead title={t("web-main.rail.customize")} note={t("web-main.rail.customizeLead")} />
          {hidden.length === 0 && <PanelNote>{t("web-main.rail.allIn")}</PanelNote>}
          {hidden.map((k) => (
            <PanelGroup key={k.title} label={t(k.title)}>
              {k.items.map((i) => {
                const Icon = RAIL_ICONS[i];
                return <PanelRow key={i} icon={Icon ? <Icon size={18} /> : i === "decisions" ? <span className={css.zouSmall}>奏</span> : null}
                  label={railLabel(i)} end={<Plus size={14} />} onClick={() => keep([...items, i])} />;
              })}
            </PanelGroup>
          ))}
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}

/**
 * 下载客户端, over the settings in a browser: this channel's apps (downloads.ts), as the site's card has them: the Mac's
 * and Windows' to download, a code to scan for Android.
 */
function RailDownload() {
  const label = t("web-main.download.title");
  const [open, setOpen] = useState(false);
  const app = (href: string, name: string, note: string) => (
    <a className={`${uiCss.panelRow} ${css.downloadRow}`} href={href}>
      <span className={uiCss.panelRowLabel}><span className={css.downloadName}>{name}</span><span className={css.downloadNote}>{note}</span></span>
      <span className={uiCss.panelRowEnd}><Download size={16} /></span>
    </a>
  );
  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Tip label={label} side="right">
        <Popover.Trigger asChild>
          <button type="button" className={css.item} data-on={open || undefined} aria-label={label}><Download size={20} /></button>
        </Popover.Trigger>
      </Tip>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${css.download}`} side="right" align="end" sideOffset={8} collisionPadding={8}>
          <PanelHead title={label} />
          {app(download("mac"), "Mac", t("web-main.download.mac"))}
          {app(download("win"), "Windows", t("web-main.download.windows"))}
          <div className={`${uiCss.panelRow} ${css.downloadScan}`}>
            <img className={css.downloadQr} src={androidQr()} alt="" width={72} height={72} />
            <span className={uiCss.panelRowLabel}><span className={css.downloadName}>Android</span><br /><span className={css.downloadNote}>{t("web-main.download.android")}</span></span>
          </div>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}

/**
 * Every workspace of the viewer's accounts, each its mark or else its first letter, the one in view marked; the others with what waits in
 * them (the core's marks: red, something went wrong; amber, someone waits for them; blue, new), its words on hover.
 * Pressed, the chat last open there. Above them `current`'s ＋ (making one, another account, invitations), shown as the
 * pointer comes over them.
 */
function RailWorkspaces({ scope, current }: { scope: string; current: ReactNode }) {
  const all = (useWorkspaces().value ?? []).flatMap(({ account, workspaces }) => workspaces.map((w) => ({ account, w })));
  const marks = useWorkspaceMarks(scope);
  const navigate = useNavigate();
  return (
    <div className={css.workspaces}>
      {/* Making one, another account, invitations (the switcher's menu, cloud/workspace.tsx): shown as the pointer comes
          over the workspaces, or while an invitation waits. */}
      {current}
      {all.map(({ account, w }) => {
        const here = w.id === scope;
        const mark = marks?.workspaces[w.id];
        return (
          <Tip key={`${account.sub}/${w.id}`} label={!here && mark?.label ? `${w.name} · ${mark.label}` : w.name} side="right">
            <button type="button" className={css.workspaceItem} data-on={here || undefined} data-marked={marked(w) || undefined} data-picture={isPicture(w.icon) || undefined}
              aria-current={here || undefined} aria-label={w.name} onClick={() => { if (!here) navigate(lastChatOf(marks, w.id) ?? `/w/${w.id}`); }}>
              <WorkspaceMark w={w} size={18} picture={22} />
              {!here && mark?.tone && <span className={css.mark}><span className={chatMarkCss.chatMarkInline} data-tone={mark.tone} /></span>}
            </button>
          </Tip>
        );
      })}
    </div>
  );
}

/** Whether `group`'s sidebar was left folded (its own, on this device). */
function folded(group: SidebarGroup): boolean {
  try { return localStorage.getItem(`stillfail.sidebar.${group}`) === "closed"; } catch { return false; }
}
// The chats' as the one sidebar was left, before each had its own: read once, as the page loads, before a place without
// a sidebar closes it (brand.tsx keeps that one for the page's first frame).
try {
  if (localStorage.getItem("stillfail.sidebar.chats") === null && localStorage.getItem("stillfail.sidebar") === "closed") {
    localStorage.setItem("stillfail.sidebar.chats", "closed");
  }
} catch { /* private mode */ }
function foldGroup(group: SidebarGroup, closed: boolean): void {
  try { localStorage.setItem(`stillfail.sidebar.${group}`, closed ? "closed" : "open"); } catch { /* private mode */ }
}

/**
 * A folded sidebar shown a while over the page (shell.css.ts dock, data-sidebar-peek on the root): until the pointer has
 * been off it (and its edge, and a menu from it) a moment (PEEK_LEAVE).
 */
let leaving: ReturnType<typeof setTimeout> | undefined;
/** How long off it before it folds again. */
const PEEK_LEAVE = 400;
function onPeekMove(e: PointerEvent) {
  const on = e.target instanceof Element && e.target.closest(`.${shellCss.dock}, .${css.edge}, [data-radix-popper-content-wrapper]`);
  if (on) { clearTimeout(leaving); leaving = undefined; } else if (!leaving) leaving = setTimeout(endPeek, PEEK_LEAVE);
}
function onPeekAway() { if (!leaving) leaving = setTimeout(endPeek, PEEK_LEAVE); }
export function peekSidebar(): void {
  const root = document.documentElement;
  if (root.dataset.sidebar === "closed" && !("sidebarPeek" in root.dataset)) moveSidebar(markPeek);
}
/** Shown a while, closed or about to be (in the move that closes it). */
function markPeek(): void {
  const root = document.documentElement;
  root.dataset.sidebarPeek = "";
  document.addEventListener("pointermove", onPeekMove, { passive: true });
  root.addEventListener("pointerleave", onPeekAway);
}
function endPeek(): void {
  clearTimeout(leaving);
  leaving = undefined;
  if ("sidebarPeek" in document.documentElement.dataset) moveSidebar(() => { delete document.documentElement.dataset.sidebarPeek; });
  document.removeEventListener("pointermove", onPeekMove);
  document.documentElement.removeEventListener("pointerleave", onPeekAway);
}

/** The sidebar's width, its least and most (the sidebar's own, styles' --sidebar-w). */
const SIDEBAR = { min: 180, max: 480, own: 240, stations: 280 } as const;

/** The sidebars, each its own width: the chats' (and the pages beside them), the settings', the files', the profiles', the stations'. */
type SidebarGroup = "chats" | "settings" | "files" | "profiles" | "stations";
/** The one shown, whose width the edge drags. */
let shownGroup: SidebarGroup = "chats";
/** Where each is kept: the chats' where the one sidebar's was. */
const widthKey = (group: SidebarGroup) => group === "chats" ? "--sidebar-w" : `--sidebar-w.${group}`;
/** What makes the sidebar as wide as `group`'s was made (its own width, none made); null if it is already. */
function widthFor(group: SidebarGroup): (() => void) | null {
  shownGroup = group;
  const root = document.documentElement.style;
  const saved = Number(localStorage.getItem(`stillfail.width.${widthKey(group)}`));
  // The stations' a little wider by itself: each row has a line of meters.
  const px = saved ? `${Math.min(SIDEBAR.max, Math.max(SIDEBAR.min, saved))}px` : group === "stations" ? `${SIDEBAR.stations}px` : "";
  if (root.getPropertyValue("--sidebar-w") === px) return null;
  return () => { if (px) root.setProperty("--sidebar-w", px); else root.removeProperty("--sidebar-w"); };
}

/**
 * The sidebar's edge, as Cue's rail handle: a strip in the page's gutter by the sidebar's block (shell.css.ts dock), a
 * short bar at its middle shown as the pointer is over the sidebar and longer on the strip itself. Dragged, the sidebar's
 * width; pressed without moving, the sidebar closes, and by the closed bar, opens (its bar shown only with the pointer
 * on the strip). Its words follow the pointer along it.
 */
export function SidebarEdge() {
  const sidebar = useSidebarToggle(undefined, { keys: false });
  const tip = usePointerTip();
  const [dragging, setDragging] = useState(false);
  const ref = useRef<HTMLButtonElement>(null);
  const words = sidebar.closed ? t("web-main.sidebar.open") : `${t("web-pages.workspace.resizeSidebar")} · ${t("web-main.sidebar.close")}`;
  return (
    <>
      <button ref={ref} type="button" className={css.edge} data-closed={sidebar.closed || undefined} data-active={dragging || undefined}
        aria-label={words} aria-expanded={!sidebar.closed} {...tip.on}
        // From the keyboard (no pointer): its press.
        onClick={(e) => { if (e.detail === 0) sidebar.toggle(); }}
        onPointerDown={(e) => {
          if (e.button !== 0) return;
          tip.hide();
          const from = e.clientX;
          const start = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--sidebar-w")) || SIDEBAR.own;
          const handle = e.currentTarget;
          let moved = false;
          handle.setPointerCapture(e.pointerId);
          const move = (ev: PointerEvent) => {
            if (sidebar.closed || (!moved && Math.abs(ev.clientX - from) < 3)) return;
            if (!moved) { moved = true; setDragging(true); document.body.dataset.resizing = "true"; }
            setKeptWidth("--sidebar-w", Math.round(Math.min(SIDEBAR.max, Math.max(SIDEBAR.min, start + ev.clientX - from))), widthKey(shownGroup));
          };
          const up = () => {
            handle.removeEventListener("pointermove", move);
            handle.removeEventListener("pointerup", up);
            delete document.body.dataset.resizing;
            setDragging(false);
            if (!moved) sidebar.toggle();
          };
          handle.addEventListener("pointermove", move);
          handle.addEventListener("pointerup", up);
          e.preventDefault();
        }} />
      {!dragging && tip.draw(words, "right")}
    </>
  );
}
