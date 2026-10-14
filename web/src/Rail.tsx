// The rail at the wide screen's left, in one block with the sidebar (styles/shell.css.ts dock), whose edge (SidebarEdge,
// in the page's gutter by it) drags the sidebar's width and, pressed, closes or opens it (no button for it; its shortcut
// still). In it the places the
// person chose on this device (prefs `rail`, 外观's 侧边条: which, in what order; RAIL_DEFAULT when none was chosen):
// 对话 and the lists of chats beside it (我参与的, 监控中, the archive), 奏 (the word, as the desktop has always had it,
// a dot while some wait for the viewer), 待处理 (what wants them in every workspace), 文件, the stations' glyph, Profile,
// 连接, 用量; at its foot every workspace to switch to (each with what waits in it; a ＋ over them, as the pointer comes,
// for making one, another account, invitations) and under them the settings, which are not among what is chosen. It is
// changed where it is: its menu's 自定义侧边条 (or 外观's) has its places dragged up and down, taken out with their −,
// added from a panel beside it by kind; a place's own menu takes it out. Station, 连接 and 用量 in it are pages of their
// own beside the chats, Profile its list in the sidebar (ProfilesNav.tsx) and the one picked beside; left out of it,
// they are among the settings. The sidebar beside shows the chats (or 奏, one of their lists), the folders the stations
// lend (FilesNav, cloud/workspace.tsx), the profiles or the settings; coming to the last three with it closed opens it.
// On a narrow screen there is none: the sidebar's foot keeps the switcher and the settings.
import { useEffect, useLayoutEffect, useRef, useState, useSyncExternalStore, type ComponentType, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { DropdownMenu, Popover } from "radix-ui";
import { NavLink, useLocation, useNavigate } from "react-router";
import { Archive, Bell, Chart, Chats, Folder, Im, Minus, Plus, Quota, Retry, Settings, Sliders, User, Watch, type IconProps } from "./icons.tsx";
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
import { moveSidebar, useSidebarToggle } from "./brand.tsx";
import { reducedMotion } from "./motion.ts";
import * as css from "./Rail.css.ts";
import { t } from "./i18n.ts";

/** Every place the rail can show, in the order the settings list them when none was chosen. */
export const RAIL_ITEMS = ["chats", "mine", "watching", "archive", "decisions", "attention", "files", "stations", "profiles", "connects", "usage"] as const;
export type RailItem = (typeof RAIL_ITEMS)[number];
/** What it shows when none was chosen. */
export const RAIL_DEFAULT: readonly RailItem[] = ["chats", "decisions", "attention", "files", "stations", "profiles", "connects", "usage"];

/** What the rail shows, in its order: as kept (what this build does not know left out), the chats always among them. */
export function railItems(kept: readonly string[] | null | undefined): RailItem[] {
  if (!kept) return [...RAIL_DEFAULT];
  const items = [...new Set(kept.filter((k): k is RailItem => (RAIL_ITEMS as readonly string[]).includes(k)))];
  return items.includes("chats") ? items : ["chats", ...items];
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
  { title: "web-main.rail.kind.lists", items: ["mine", "watching", "archive", "decisions"] },
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

export function Rail({ scope, workspace }: { scope: string; workspace: ReactNode }) {
  const location = useLocation();
  const place = placeOf(location.pathname);
  const [mode, setMode] = useSidebarMode();
  const navigate = useNavigate();
  const last = useLastChat(scope, `/w/${scope}/new`) ?? `/w/${scope}`;
  const waiting = useWorkspaceMarks(scope)?.workspaces[scope]?.decisions ?? 0;
  const kept = usePrefs((p) => p.rail);
  const items = railItems(kept);
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
  const follow = (item: RailItem) => {
    const el = slots.current.get(item);
    if (el) el.style.transform = `translateY(${pointerY.current - grabbed.current - el.offsetTop}px) scale(1.06)`;
  };
  useLayoutEffect(() => {
    const was = drawnAt.current;
    const now = new Map<RailItem, number>();
    for (const [item, el] of slots.current) {
      now.set(item, el.offsetTop);
      if (item === dragged?.item) continue;
      const from = was.get(item);
      if (from !== undefined && from !== el.offsetTop && !reducedMotion()) {
        el.animate([{ transform: `translateY(${from - el.offsetTop}px)` }, { transform: "none" }], { duration: 220, easing: "cubic-bezier(.2, .7, .2, 1)" });
      }
    }
    drawnAt.current = now;
    if (dragged?.item) follow(dragged.item);
  });
  const drag = (item: RailItem) => (e: ReactPointerEvent) => {
    if (e.button !== 0) return;
    e.preventDefault();
    let order = items;
    const el = slots.current.get(item);
    const top = (el?.offsetParent as HTMLElement | null)?.getBoundingClientRect().top ?? 0;
    pointerY.current = e.clientY - top;
    grabbed.current = pointerY.current - (el?.offsetTop ?? 0);
    setDragged({ item, order });
    const move = (ev: PointerEvent) => {
      pointerY.current = ev.clientY - top;
      follow(item);
      // Where the pointer is among the others' middles.
      const rest = order.filter((i) => i !== item);
      let at = rest.length;
      for (let i = 0; i < rest.length; i++) {
        const other = slots.current.get(rest[i]!);
        if (other && pointerY.current < other.offsetTop + other.offsetHeight / 2) { at = i; break; }
      }
      const next = [...rest.slice(0, at), item, ...rest.slice(at)];
      if (next.join() !== order.join()) { order = next; setDragged({ item, order }); }
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      const held = slots.current.get(item);
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
  const sidebar = useSidebarToggle();
  // By the page's root, not as last drawn: a list asked for from the rail opens it, and so may its place's change in
  // the same click, once.
  const shut = () => document.documentElement.dataset.sidebar === "closed";
  const openSidebar = () => { if (shut()) sidebar.toggle(); };
  // The places with a sidebar of their own (the settings, the files and the stations their way round, the profiles their
  // list, the chats their lists) open it, come to with it closed; a page in the rail (连接, 用量) or the archive has none
  // (only the chats beside it), and closes it: the page the whole width. On the page's load the chats as they were left.
  // Only on a wide screen: on a narrow one the sidebar is a page of its own.
  const own = place === "settings" || place === "files" || place === "stations" || place === "profiles" || place === "chats" || !items.includes(place as RailItem);
  // Which sidebar it is, each as wide as it was made.
  const group: SidebarGroup = place === "files" ? "files" : place === "profiles" && items.includes("profiles") ? "profiles"
    : place === "stations" && items.includes("stations") ? "stations"
    : place === "chats" || place === "archive" || items.includes(place as RailItem) ? "chats" : "settings";
  const cameFrom = useRef<Place | null>(null);
  useEffect(() => {
    const moved = cameFrom.current !== null && cameFrom.current !== place;
    cameFrom.current = place;
    if (!matchMedia("(min-width: 701px)").matches) return;
    widthFor(group, moved && !shut());
    if (own && (moved || place !== "chats")) openSidebar();
    else if (!own && !shut()) sidebar.toggle();
  }, [place, own, group]); // eslint-disable-line react-hooks/exhaustive-deps
  const settings = `/w/${scope}/settings`;
  // The settings lit (in them, or a place left out of the rail), pressed again, go back to where they were come to from:
  // the page last shown with them unlit, the last chat when the settings were where the page was opened.
  const inSettings = place === "settings" || (place !== "chats" && !items.includes(place as RailItem));
  const before = useRef<string | null>(null);
  useEffect(() => { if (!inSettings) before.current = location.pathname + location.search; }, [inSettings, location.pathname, location.search]);
  // A list of chats lit while the sidebar shows it; 对话 for one not in the rail.
  const shownList = (Object.keys(LISTS) as RailItem[]).find((i) => LISTS[i] === mode && items.includes(i)) ?? "chats";
  const on = (item: RailItem) => LISTS[item] ? place === "chats" && shownList === item : place === item;
  const toList = (item: RailItem) => () => { setMode(LISTS[item]!); openSidebar(); if (place !== "chats") navigate(last); };
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
            <button type="button" className={css.item} data-on={on(item) || undefined} aria-label={railLabel(item)} onClick={toList(item)}><Icon size={20} /></button>
          </Tip>
        );
      }
      case "decisions": return (
        <Tip key={item} label={waiting > 0 ? t("web-main.decisions.entry", { n: waiting }) : railLabel(item)} side="right">
          <button type="button" className={css.item} data-on={on(item) || undefined} aria-label={railLabel(item)}
            onClick={(e) => { openedAt(e.currentTarget); setMode("decisions"); openSidebar(); navigate(`/w/${scope}/decisions`); }}>
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
          {item !== "chats" && (
            <button type="button" className={css.remove} aria-label={t("web-main.rail.remove", { name: railLabel(item) })}
              onPointerDown={(e) => e.stopPropagation()} onClick={() => keep(items.filter((i) => i !== item))}><Minus size={12} strokeWidth={2.5} /></button>
          )}
        </div>
      ) : <div key={item} data-rail-item={item} className={css.slot}>{drawn(item)}</div>)}
      <div className={css.grow} />
      {/* Every workspace at the foot, always, not one of the places chosen: the one in view its switcher. */}
      <RailWorkspaces scope={scope} current={workspace} />
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
            {pointed && pointed !== "chats" && (
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

/** The sidebar's width, its least and most (the sidebar's own, styles' --sidebar-w). */
const SIDEBAR = { min: 180, max: 480, own: 240 } as const;

/** The sidebars, each its own width: the chats' (and the pages beside them), the settings', the files', the profiles', the stations'. */
type SidebarGroup = "chats" | "settings" | "files" | "profiles" | "stations";
/** The one shown, whose width the edge drags. */
let shownGroup: SidebarGroup = "chats";
/** Where each is kept: the chats' where the one sidebar's was. */
const widthKey = (group: SidebarGroup) => group === "chats" ? "--sidebar-w" : `--sidebar-w.${group}`;
/** The sidebar as wide as `group`'s was made (its own width, none made); moved there with the page, if `glide`. */
function widthFor(group: SidebarGroup, glide: boolean): void {
  shownGroup = group;
  const root = document.documentElement.style;
  const saved = Number(localStorage.getItem(`stillfail.width.${widthKey(group)}`));
  const px = saved ? `${Math.min(SIDEBAR.max, Math.max(SIDEBAR.min, saved))}px` : "";
  if (root.getPropertyValue("--sidebar-w") === px) return;
  const put = () => { if (px) root.setProperty("--sidebar-w", px); else root.removeProperty("--sidebar-w"); };
  if (glide) moveSidebar(put); else put();
}

/**
 * The sidebar's edge, as Cue's rail handle: a strip in the page's gutter by the sidebar's block (shell.css.ts dock), a
 * short bar at its middle shown as the pointer is over the sidebar and longer on the strip itself. Dragged, the sidebar's
 * width; pressed without moving, the sidebar closes, and by the closed bar, opens (its bar shown a second as the mouse
 * moves anywhere). Its words follow the pointer along it.
 */
export function SidebarEdge() {
  const sidebar = useSidebarToggle(undefined, { keys: false });
  const tip = usePointerTip();
  const [dragging, setDragging] = useState(false);
  const ref = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!sidebar.closed || !el) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const reveal = (e: PointerEvent) => {
      if (e.pointerType !== "mouse") return;
      el.dataset.moving = "";
      clearTimeout(timer);
      timer = setTimeout(() => { delete el.dataset.moving; }, 1000);
    };
    window.addEventListener("pointermove", reveal, { passive: true });
    return () => { window.removeEventListener("pointermove", reveal); clearTimeout(timer); delete el.dataset.moving; };
  }, [sidebar.closed]);
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
