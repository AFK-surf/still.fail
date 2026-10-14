// The rail at the wide screen's left, of the sidebar's own ground: the workspace's places as icons, 对话, 奏 (with how
// many wait for the viewer), 文件 and the stations' glyph, and at its foot the settings and the workspace's switcher.
// Each place is what the sidebar beside it shows: the chats (or 奏, one of their lists), the folders the stations lend
// (FilesNav, cloud/workspace.tsx), the settings. On a narrow screen there is none: the sidebar's foot keeps them.
import type { ReactNode } from "react";
import { NavLink, useLocation, useNavigate } from "react-router";
import { Chats, Folder, Settings, Zou } from "./icons.tsx";
import { Tip } from "./ui.tsx";
import { useLastChat, useWorkspaceMarks } from "./lastChat.ts";
import { useSidebarMode } from "./station.tsx";
import { RailStations } from "./Sidebar.tsx";
import { openedAt } from "./DecisionDesk.tsx";
import * as css from "./Rail.css.ts";
import { t } from "./i18n.ts";

/** Which place the page is in, by its path: the files' and the settings' pages have the sidebar of their own. */
export type Place = "chats" | "files" | "stations" | "settings";

export function placeOf(path: string): Place {
  if (/^\/w\/[^/]+\/(files|s\/[^/]+\/files)(\/|$)/.test(path)) return "files";
  if (/^\/w\/[^/]+\/settings\/stations(\/|$)/.test(path)) return "stations";
  if (/^\/w\/[^/]+\/(settings|s\/[^/]+\/(connects|settings))(\/|$)/.test(path)) return "settings";
  return "chats";
}

export function Rail({ scope, workspace }: { scope: string; workspace: ReactNode }) {
  const place = placeOf(useLocation().pathname);
  const [mode, setMode] = useSidebarMode();
  const navigate = useNavigate();
  const last = useLastChat(scope, `/w/${scope}/new`) ?? `/w/${scope}`;
  const waiting = useWorkspaceMarks(scope)?.workspaces[scope]?.decisions ?? 0;
  const chats = place === "chats" && mode !== "decisions";
  const decisions = place === "chats" && mode === "decisions";
  return (
    <nav className={css.rail} aria-label={t("web-main.rail.label")}>
      <div className={css.top} />
      <Tip label={t("web-main.rail.chats")} side="right">
        <button type="button" className={css.item} data-on={chats || undefined} aria-label={t("web-main.rail.chats")}
          onClick={() => { if (mode === "decisions") setMode("all"); if (place !== "chats") navigate(last); }}>
          <Chats size={20} />
        </button>
      </Tip>
      <Tip label={waiting > 0 ? t("web-main.decisions.entry", { n: waiting }) : t("web-main.rail.decisions")} side="right">
        <button type="button" className={css.item} data-on={decisions || undefined} aria-label={t("web-main.rail.decisions")}
          onClick={(e) => { openedAt(e.currentTarget); setMode("decisions"); navigate(`/w/${scope}/decisions`); }}>
          <Zou size={20} />
          {waiting > 0 && <span className={css.count}>{waiting > 99 ? "99+" : waiting}</span>}
        </button>
      </Tip>
      <Tip label={t("web-pages.drive.title")} side="right">
        <NavLink className={css.item} to={`/w/${scope}/files`} data-on={place === "files" || undefined} aria-label={t("web-pages.drive.title")}><Folder size={20} /></NavLink>
      </Tip>
      <RailStations scope={scope} to={`/w/${scope}/settings/stations`} on={place === "stations"} className={css.item} />
      <div className={css.grow} />
      <Tip label={t("web-pages.settings.title")} side="right">
        <NavLink className={css.item} to={`/w/${scope}/settings`} data-on={place === "settings" || undefined} aria-label={t("web-pages.settings.title")}><Settings size={20} /></NavLink>
      </Tip>
      {workspace}
    </nav>
  );
}
