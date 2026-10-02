// The new-chat action and the lists' menu above the sidebar's lists (the chats', 奏).
import { NavLink } from "react-router";
import { t } from "./i18n.ts";
import { Compose } from "./icons.tsx";
import { ICON } from "./ui.tsx";
import { MineFilter } from "./components.tsx";
import { useComposerMove } from "./dock.tsx";
import * as nav from "./Sidebar.css.ts";

export function SidebarActions({ newChat, archive, workspace, showFilter = true }: {
  newChat: string; archive: string; workspace: string; showFilter?: boolean;
}) {
  const move = useComposerMove();
  return (
    <div className={nav.navNew}>
      <NavLink className={nav.navRow} to={newChat} onClick={(e) => move(e, newChat, "new")}><Compose {...ICON} />{t("web-main.sidebar.newChat")}</NavLink>
      {showFilter && <MineFilter compact archive={archive} watching
        decisions={{ to: `${workspace}/decisions`, chats: workspace }} />}
    </div>
  );
}
