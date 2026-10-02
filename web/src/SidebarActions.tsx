// The same new-chat action and list menu above chats and decisions.
import { NavLink } from "react-router";
import { t } from "./i18n.ts";
import { Ling } from "./icons.tsx";
import { ICON } from "./ui.tsx";
import { MineFilter } from "./components.tsx";
import { useComposerMove } from "./dock.tsx";
import * as nav from "./Sidebar.css.ts";

export function SidebarActions({ newChat, archive, workspace, decisions = false, showFilter = true }: {
  newChat: string; archive: string; workspace: string; decisions?: boolean; showFilter?: boolean;
}) {
  const move = useComposerMove();
  return (
    <div className={nav.navNew}>
      <NavLink className={nav.navRow} to={newChat} onClick={(e) => move(e, newChat, "new")}><Ling {...ICON} />{t("web-main.sidebar.newChat")}</NavLink>
      {showFilter && <MineFilter compact archive={archive} watching
        decisions={{ to: `${workspace}/decisions`, chats: workspace, active: decisions }} />}
    </div>
  );
}
