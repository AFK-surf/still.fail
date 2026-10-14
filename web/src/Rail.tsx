// The rail at the wide screen's left, of the sidebar's own ground: at its top what opens and closes the sidebar (under
// the window's buttons in the desktop app on macOS), then the places the person chose for it on this device (prefs
// `rail`, 外观's 侧边条: which, in what order; RAIL_DEFAULT when none was chosen): 对话 and the lists of chats beside it
// (我参与的, 监控中, the archive), 奏 (the word, as the desktop has always had it, with how many wait for the viewer),
// 待处理 (what wants them in every workspace, as the sidebar's top has it), 文件, the stations' glyph, Profile, 连接, 用量,
// the workspaces to switch to (each with what waits in it); at its foot the settings and the workspace's switcher. Each
// place is what the sidebar beside it shows: the chats (or 奏, one of their lists), the folders the stations lend
// (FilesNav, cloud/workspace.tsx), the settings. On a narrow screen there is none: the sidebar's foot keeps the switcher
// and the settings.
import type { ComponentType, ReactNode } from "react";
import { NavLink, useLocation, useNavigate } from "react-router";
import { Archive, Bell, Chart, Chats, Folder, Im, PanelClose, PanelOpen, Quota, Settings, User, Users, Watch, type IconProps } from "./icons.tsx";
import { Tip } from "./ui.tsx";
import { lastChatOf, useLastChat, useWorkspaceMarks } from "./lastChat.ts";
import { useSidebarMode, type SidebarMode } from "./station.tsx";
import { AttentionEntry } from "./Attention.tsx";
import { useWorkspaces } from "./cloud/api.ts";
import * as chatMarkCss from "./ChatMark.css.ts";
import { usePrefs } from "./prefs.ts";
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

export function Rail({ scope, workspace }: { scope: string; workspace: ReactNode }) {
  const place = placeOf(useLocation().pathname);
  const [mode, setMode] = useSidebarMode();
  const navigate = useNavigate();
  const last = useLastChat(scope, `/w/${scope}/new`) ?? `/w/${scope}`;
  const waiting = useWorkspaceMarks(scope)?.workspaces[scope]?.decisions ?? 0;
  const items = railItems(usePrefs((p) => p.rail));
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
  return (
    <nav className={css.rail} aria-label={t("web-main.rail.label")}>
      <div className={css.top}>
        <Tip label={sidebar.label} side="right">
          <button type="button" className={css.item} onClick={sidebar.toggle} aria-label={sidebar.closed ? t("web-main.sidebar.open") : t("web-main.sidebar.close")}>
            <Panel size={20} className={css.mirrored} />
          </button>
        </Tip>
      </div>
      {items.map(drawn)}
      <div className={css.grow} />
      {/* A place left out of the rail is reached in the settings: they are lit while in it. */}
      <Tip label={t("web-pages.settings.title")} side="right">
        <NavLink className={css.item} to={settings} data-on={place === "settings" || (place !== "chats" && !items.includes(place as RailItem)) || undefined} aria-label={t("web-pages.settings.title")}><Settings size={20} /></NavLink>
      </Tip>
      {/* Among the workspaces when they are in the rail. */}
      {!items.includes("workspaces") && workspace}
    </nav>
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
