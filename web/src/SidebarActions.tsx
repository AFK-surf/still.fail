// The new-chat action and the lists' menu above the sidebar's lists (the chats', 奏).
import { t } from "./i18n.ts";
import { Compose } from "@stillfail/ui/icons.tsx";
import { ICON } from "./ui.tsx";
import { MineFilter } from "./components.tsx";
import { useComposerMove } from "./dock.tsx";
import { NavAction } from "./SidebarList.tsx";
import * as nav from "./Sidebar.css.ts";

export function SidebarActions({ newChat, archive, workspace, showFilter = true }: {
  newChat: string; archive: string; workspace: string; showFilter?: boolean;
}) {
  const move = useComposerMove();
  return (
    <NavAction icon={<Compose {...ICON} className={nav.navCompose} />} label={t("web-main.sidebar.newChat")} to={newChat} onClick={(e) => move(e, newChat, "new")}
      beside={showFilter && <MineFilter compact archive={archive} watching
        decisions={{ to: `${workspace}/decisions`, chats: workspace }} />} />
  );
}
