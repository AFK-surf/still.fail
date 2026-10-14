// The rail at the wide screen's left, of the sidebar's own ground: at its top what opens and closes the sidebar (under
// the window's buttons in the desktop app on macOS), then the places the person chose for it on this device (prefs
// `rail`, 外观's 侧边条: which, in what order; RAIL_DEFAULT when none was chosen): 对话 and the lists of chats beside it
// (我参与的, 监控中, the archive), 奏 (the word, as the desktop has always had it, with how many wait for the viewer),
// 待处理 (what wants them in every workspace, as the sidebar's top has it), 文件, the stations' glyph, Profile, 连接, 用量,
// the workspaces to switch to (each with what waits in it); at its foot the settings and the workspace's switcher. It is
// changed where it is: its menu's 自定义侧边条 (or 外观's) has its places dragged up and down, taken out with their −,
// added from a panel beside it by kind; a place's own menu takes it out. Each
// place is what the sidebar beside it shows: the chats (or 奏, one of their lists), the folders the stations lend
// (FilesNav, cloud/workspace.tsx), the settings. On a narrow screen there is none: the sidebar's foot keeps the switcher
// and the settings.
import { useRef, useState, useSyncExternalStore, type ComponentType, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { ContextMenu, Popover } from "radix-ui";
import { NavLink, useLocation, useNavigate } from "react-router";
import { Archive, Bell, Chart, Chats, Folder, Im, Minus, PanelClose, Plus, PanelOpen, Quota, Settings, User, Users, Watch, type IconProps } from "./icons.tsx";
import { Button, Tip } from "./ui.tsx";
import { lastChatOf, useLastChat, useWorkspaceMarks } from "./lastChat.ts";
import { useSidebarMode, type SidebarMode } from "./station.tsx";
import { AttentionEntry } from "./Attention.tsx";
import { useWorkspaces } from "./cloud/api.ts";
import * as chatMarkCss from "./ChatMark.css.ts";
import { setPrefs, usePrefs } from "./prefs.ts";
import * as controlsCss from "./styles/controls.css.ts";
import { RailStations } from "./Sidebar.tsx";
import { openedAt } from "./DecisionDesk.tsx";
import { useSidebarToggle } from "./brand.tsx";
import * as css from "./Rail.css.ts";
import { t } from "./i18n.ts";

/** Every place the rail can show, in the order the settings list them when none was chosen. */
export const RAIL_ITEMS = ["chats", "mine", "watching", "archive", "decisions", "attention", "files", "stations", "profiles", "connects", "usage", "workspaces"] as const;
export type RailItem = (typeof RAIL_ITEMS)[number];
/** What it shows when none was chosen. */
export const RAIL_DEFAULT: readonly RailItem[] = ["chats", "decisions", "files", "stations", "profiles", "connects", "usage"];

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
    case "workspaces": return t("web-main.rail.workspaces");
  }
}

/** The icons of the places drawn as one (the stations' is their glyph, 奏 its word, the workspaces each its letter). */
export const RAIL_ICONS: Partial<Record<RailItem, ComponentType<IconProps>>> = {
  chats: Chats, mine: User, watching: Watch, archive: Archive, attention: Bell, files: Folder, profiles: Quota, connects: Im, usage: Chart, workspaces: Users,
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
  { title: "web-main.rail.kind.workspaces", items: ["workspaces"] },
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
  const place = placeOf(useLocation().pathname);
  const [mode, setMode] = useSidebarMode();
  const navigate = useNavigate();
  const last = useLastChat(scope, `/w/${scope}/new`) ?? `/w/${scope}`;
  const waiting = useWorkspaceMarks(scope)?.workspaces[scope]?.decisions ?? 0;
  const kept = usePrefs((p) => p.rail);
  const items = railItems(kept);
  const changing = useEditing();
  // Dragged in the rail: the order as it would be let go of now.
  const [dragged, setDragged] = useState<{ item: RailItem; order: RailItem[] } | null>(null);
  const slots = useRef(new Map<RailItem, HTMLElement>());
  // Right-clicked: the place under the pointer, to take out.
  const [pointed, setPointed] = useState<RailItem | null>(null);
  const keep = (next: RailItem[]) => setPrefs({ rail: next });
  const drag = (item: RailItem) => (e: ReactPointerEvent) => {
    if (e.button !== 0) return;
    e.preventDefault();
    let order = items;
    setDragged({ item, order });
    const move = (ev: PointerEvent) => {
      // Where the pointer is among the others' middles.
      const rest = order.filter((i) => i !== item);
      let at = rest.length;
      for (let i = 0; i < rest.length; i++) {
        const box = slots.current.get(rest[i]!)?.getBoundingClientRect();
        if (box && ev.clientY < box.top + box.height / 2) { at = i; break; }
      }
      const next = [...rest.slice(0, at), item, ...rest.slice(at)];
      if (next.join() !== order.join()) { order = next; setDragged({ item, order }); }
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      setDragged(null);
      if (order.join() !== items.join()) keep(order);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };
  const sidebar = useSidebarToggle();
  const settings = `/w/${scope}/settings`;
  // A list of chats lit while the sidebar shows it; 对话 for one not in the rail.
  const shownList = (Object.keys(LISTS) as RailItem[]).find((i) => LISTS[i] === mode && items.includes(i)) ?? "chats";
  const on = (item: RailItem) => LISTS[item] ? place === "chats" && shownList === item : place === item;
  const toList = (item: RailItem) => () => { setMode(LISTS[item]!); if (place !== "chats") navigate(last); };
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
            onClick={(e) => { openedAt(e.currentTarget); setMode("decisions"); navigate(`/w/${scope}/decisions`); }}>
            <span className={css.zou} aria-hidden="true">奏</span>
            {waiting > 0 && <span className={css.count}>{waiting > 99 ? "99+" : waiting}</span>}
          </button>
        </Tip>
      );
      case "archive": return link(item, `/w/${scope}/archive`);
      case "attention": return <AttentionEntry key={item} scope={scope} rail={{ item: css.item, count: css.count, label: railLabel(item) }} />;
      case "workspaces": return <RailWorkspaces key={item} scope={scope} current={workspace} />;
      case "files": return link(item, `/w/${scope}/files`);
      case "stations": return <RailStations key={item} scope={scope} to={`${settings}/stations`} on={on(item)} className={css.item} />;
      case "profiles": return link(item, `${settings}/profiles`);
      case "connects": return link(item, `${settings}/connects`);
      case "usage": return link(item, `${settings}/usage`);
    }
  };
  // The panel icons are drawn for a panel at the right: turned round for the sidebar at the left.
  const Panel = sidebar.closed ? PanelOpen : PanelClose;
  const hidden = KINDS.map((k) => ({ ...k, items: k.items.filter((i) => !items.includes(i)) })).filter((k) => k.items.length > 0);
  const rail = (
    <nav className={css.rail} aria-label={t("web-main.rail.label")} data-editing={changing || undefined}
      onContextMenu={(e) => setPointed(((e.target as HTMLElement).closest("[data-rail-item]")?.getAttribute("data-rail-item") as RailItem | null) ?? null)}>
      <div className={css.top}>
        <Tip label={sidebar.label} side="right">
          <button type="button" className={css.item} onClick={sidebar.toggle} aria-label={sidebar.closed ? t("web-main.sidebar.open") : t("web-main.sidebar.close")}>
            <Panel size={20} className={css.mirrored} />
          </button>
        </Tip>
      </div>
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
      {/* A place left out of the rail is reached in the settings: they are lit while in it. */}
      <Tip label={t("web-pages.settings.title")} side="right">
        <NavLink className={css.item} to={settings} data-on={place === "settings" || (place !== "chats" && !items.includes(place as RailItem)) || undefined} aria-label={t("web-pages.settings.title")}><Settings size={20} /></NavLink>
      </Tip>
      {/* Among the workspaces when they are in the rail. */}
      {!items.includes("workspaces") && workspace}
    </nav>
  );
  return (
    <Popover.Root open={changing} onOpenChange={(open) => { if (!open) editRail(false); }}>
      <ContextMenu.Root modal={false}>
        <ContextMenu.Trigger asChild disabled={changing}><Popover.Anchor asChild>{rail}</Popover.Anchor></ContextMenu.Trigger>
        <ContextMenu.Portal>
          <ContextMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList}`} collisionPadding={8}>
            {pointed && pointed !== "chats" && (
              <ContextMenu.Item className={controlsCss.menuItem} onSelect={() => keep(items.filter((i) => i !== pointed))}>{t("web-main.rail.remove", { name: railLabel(pointed) })}</ContextMenu.Item>
            )}
            <ContextMenu.Item className={controlsCss.menuItem} onSelect={() => editRail(true)}>{t("web-main.rail.customize")}</ContextMenu.Item>
          </ContextMenu.Content>
        </ContextMenu.Portal>
      </ContextMenu.Root>
      <Popover.Portal>
        {/* Beside the rail while it is changed: what can be added, by kind; pressing in the rail does not close it. */}
        <Popover.Content className={`${controlsCss.popover} ${css.adder}`} side="right" align="start" sideOffset={8} collisionPadding={8}
          onOpenAutoFocus={(e) => e.preventDefault()}
          onInteractOutside={(e) => { if ((e.target as HTMLElement | null)?.closest(`.${css.rail}`)) e.preventDefault(); }}>
          <div className={css.adderTitle}>{t("web-main.rail.customize")}</div>
          <p className={css.adderLead}>{t("web-main.rail.customizeLead")}</p>
          {hidden.length === 0 && <p className={css.adderLead}>{t("web-main.rail.allIn")}</p>}
          {hidden.map((k) => (
            <div key={k.title} className={css.adderGroup}>
              <div className={css.adderKind}>{t(k.title)}</div>
              {k.items.map((i) => {
                const Icon = RAIL_ICONS[i];
                return (
                  <button key={i} type="button" className={css.adderRow} onClick={() => keep([...items, i])}>
                    <span className={css.adderIcon}>{Icon ? <Icon size={18} /> : i === "decisions" ? <span className={css.zouSmall}>奏</span> : null}</span>
                    <span className={css.adderLabel}>{railLabel(i)}</span>
                    <Plus size={14} className={css.adderPlus} />
                  </button>
                );
              })}
            </div>
          ))}
          <div className={css.adderFoot}>
            {kept && <Button variant="ghost" onClick={() => setPrefs({ rail: null })}>{t("web-main.rail.reset")}</Button>}
            <Button variant="primary" onClick={() => editRail(false)}>{t("web-main.rail.done")}</Button>
          </div>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}

/**
 * Every workspace of the viewer's accounts, each its first letter, the one in view its switcher; the others with what waits in
 * them (the core's marks: red, something went wrong; amber, someone waits for them; blue, new), its words on hover.
 * Pressed, the chat last open there.
 */
function RailWorkspaces({ scope, current }: { scope: string; current: ReactNode }) {
  const all = (useWorkspaces().value ?? []).flatMap(({ account, workspaces }) => workspaces.map((w) => ({ account, w })));
  const marks = useWorkspaceMarks(scope);
  const navigate = useNavigate();
  return (
    <div className={css.workspaces}>
      {all.map(({ account, w }) => {
        const here = w.id === scope;
        // The one in view is the switcher (its menu: making one, another account, invitations).
        if (here) return <span key={`${account.sub}/${w.id}`} className={css.workspaceHere}>{current}</span>;
        const mark = marks?.workspaces[w.id];
        return (
          <Tip key={`${account.sub}/${w.id}`} label={!here && mark?.label ? `${w.name} · ${mark.label}` : w.name} side="right">
            <button type="button" className={css.workspaceItem} data-on={here || undefined} aria-current={here || undefined} aria-label={w.name}
              onClick={() => { if (!here) navigate(lastChatOf(marks, w.id) ?? `/w/${w.id}`); }}>
              {[...w.name.trim()][0]?.toUpperCase() ?? "·"}
              {!here && mark?.tone && <span className={css.mark}><span className={chatMarkCss.chatMarkInline} data-tone={mark.tone} /></span>}
            </button>
          </Tip>
        );
      })}
    </div>
  );
}
