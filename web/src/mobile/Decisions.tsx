// The decisions page on a narrow screen (奏 N, from the list's foot): back, then the decisions one at a time
// (../Decisions.tsx), swiped left for 待定 and right for 不再提醒.
import { DecisionDeck } from "../Decisions.tsx";
import { useApp } from "./app.tsx";
import { NavBar } from "./parts.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as rootCss from "./styles/root.css.ts";
import { t } from "../i18n.ts";

export function DecisionsScreen() {
  const app = useApp();
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={t("web-mobile.nav.chats")} onBack={app.pop} title={t("web-mobile.decisions.title")} />
      <DecisionDeck workspace={app.entry.id} inline className={rootCss.wide} onOpen={(path) => app.push(path)} />
    </div>
  );
}
