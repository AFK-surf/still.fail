// The rail at the wide screen's left, of the sidebar's own ground: at its top what opens and closes the sidebar (under
// the window's buttons in the desktop app on macOS), then the workspace's places as the person chose them on this device
// (prefs `rail`, 外观 in the settings: which, in what order; all of them, so, by default): 对话, 奏 (the word, as the
// desktop has always had it, with how many wait for the viewer), 文件, the stations' glyph, Profile, 连接, 用量; at its
// foot the settings and the workspace's switcher. Each place is what the sidebar beside it shows: the chats (or 奏, one of
// their lists), the folders the stations lend (FilesNav, cloud/workspace.tsx), the settings. On a narrow screen there is
// none: the sidebar's foot keeps the switcher and the settings.
import type { ComponentType, ReactNode } from "react";
import { NavLink, useLocation, useNavigate } from "react-router";
import { Chart, Chats, Folder, Key, PanelClose, PanelOpen, Plug, Settings, type IconProps } from "./icons.tsx";
import { Tip } from "./ui.tsx";
import { useLastChat, useWorkspaceMarks } from "./lastChat.ts";
import { useSidebarMode } from "./station.tsx";
import { usePrefs } from "./prefs.ts";
import { RailStations } from "./Sidebar.tsx";
import { openedAt } from "./DecisionDesk.tsx";
import { useSidebarToggle } from "./brand.tsx";
import * as css from "./Rail.css.ts";
import { t } from "./i18n.ts";

/** The places the rail can show, in the order they come in when none was chosen. */
export const RAIL_ITEMS = ["chats", "decisions", "files", "stations", "profiles", "connects", "usage"] as const;
export type RailItem = (typeof RAIL_ITEMS)[number];

/** What the rail shows, in its order: as kept (what this build does not know left out), the chats always among them. */
export function railItems(kept: readonly string[] | null | undefined): RailItem[] {
  if (!kept) return [...RAIL_ITEMS];
  const items = [...new Set(kept.filter((k): k is RailItem => (RAIL_ITEMS as readonly string[]).includes(k)))];
  return items.includes("chats") ? items : ["chats", ...items];
}

/** A place's name, as the rail's tip and the settings say it. */
export function railLabel(item: RailItem): string {
  switch (item) {
    case "chats": return t("web-main.rail.chats");
    case "decisions": return t("web-main.rail.decisions");
    case "files": return t("web-pages.drive.title");
    case "stations": return "Station";
    case "profiles": return "Profile";
    case "connects": return t("web-pages.settings.nav.connects");
    case "usage": return t("web-pages.settings.nav.usage");
  }
}

/** The icons of the places drawn as one (the stations' is their glyph, 奏 its word). */
export const RAIL_ICONS: Partial<Record<RailItem, ComponentType<IconProps>>> = { chats: Chats, files: Folder, profiles: Key, connects: Plug, usage: Chart };

/** Which place the page is in, by its path: the files' and the settings' pages have the sidebar of their own. */
export type Place = RailItem | "settings";

export function placeOf(path: string): Place {
  if (/^\/w\/[^/]+\/(files|s\/[^/]+\/files)(\/|$)/.test(path)) return "files";
  if (/^\/w\/[^/]+\/settings\/stations(\/|$)/.test(path)) return "stations";
  if (/^\/w\/[^/]+\/(settings\/profiles|s\/[^/]+\/settings\/accounts)(\/|$)/.test(path)) return "profiles";
  if (/^\/w\/[^/]+\/(settings\/connects|s\/[^/]+\/connects)(\/|$)/.test(path)) return "connects";
  if (/^\/w\/[^/]+\/settings\/usage(\/|$)/.test(path)) return "usage";
  if (/^\/w\/[^/]+\/(settings|s\/[^/]+\/settings)(\/|$)/.test(path)) return "settings";
  return "chats";
}

export function Rail({ scope, workspace }: { scope: string; workspace: ReactNode }) {
  const place = placeOf(useLocation().pathname);
  const [mode, setMode] = useSidebarMode();
  const navigate = useNavigate();
  const last = useLastChat(scope, `/w/${scope}/new`) ?? `/w/${scope}`;
  const waiting = useWorkspaceMarks(scope)?.workspaces[scope]?.decisions ?? 0;
  const items = railItems(usePrefs((p) => p.rail));
  const sidebar = useSidebarToggle();
  const settings = `/w/${scope}/settings`;
  const on = (item: RailItem) => item === "decisions" ? place === "chats" && mode === "decisions"
    : item === "chats" ? place === "chats" && (mode !== "decisions" || !items.includes("decisions"))
    : place === item;
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
      case "chats": return (
        <Tip key={item} label={railLabel(item)} side="right">
          <button type="button" className={css.item} data-on={on(item) || undefined} aria-label={railLabel(item)}
            onClick={() => { if (mode === "decisions") setMode("all"); if (place !== "chats") navigate(last); }}>
            <Chats size={20} />
          </button>
        </Tip>
      );
      case "decisions": return (
        <Tip key={item} label={waiting > 0 ? t("web-main.decisions.entry", { n: waiting }) : railLabel(item)} side="right">
          <button type="button" className={css.item} data-on={on(item) || undefined} aria-label={railLabel(item)}
            onClick={(e) => { openedAt(e.currentTarget); setMode("decisions"); navigate(`/w/${scope}/decisions`); }}>
            <span className={css.zou} aria-hidden="true">奏</span>
            {waiting > 0 && <span className={css.count}>{waiting > 99 ? "99+" : waiting}</span>}
          </button>
        </Tip>
      );
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
        <NavLink className={css.item} to={settings} data-on={place === "settings" || (place !== "chats" && !items.includes(place)) || undefined} aria-label={t("web-pages.settings.title")}><Settings size={20} /></NavLink>
      </Tip>
      {workspace}
    </nav>
  );
}
