// The decisions page on a narrow screen (奏, a place of the bottom bar): its head, then the decisions one at a time
// (../Decisions.tsx), swiped left for 待定 and right for 不再提醒.
import { DecisionDeck } from "../Decisions.tsx";
import { useApp } from "./app.tsx";
import { PlaceHead } from "./parts.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as rootCss from "./styles/root.css.ts";
import { t } from "../i18n.ts";

export function DecisionsScreen() {
  const app = useApp();
  return (
    <div className={pagesCss.mScreen}>
      <PlaceHead title={t("web-mobile.decisions.title")} back={t("web-mobile.nav.chats")} onBack={app.pop} />
      <DecisionDeck workspace={app.entry.id} inline className={rootCss.wide} onOpen={(path) => app.push(path)} />
    </div>
  );
}
