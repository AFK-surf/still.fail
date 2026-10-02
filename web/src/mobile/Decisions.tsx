// The decisions page on a narrow screen (奏 N, from the list's foot): back, then the decisions one at a time
// (../Decisions.tsx), swiped left for 待定 and right for 不再提醒.
import { DecisionDeck } from "../Decisions.tsx";
import { useApp } from "./app.tsx";
import { NavBar } from "./parts.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as rootCss from "./styles/root.css.ts";

export function DecisionsScreen() {
  const app = useApp();
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back="会话" onBack={app.pop} title="奏" />
      <DecisionDeck workspace={app.entry.id} inline className={rootCss.wide} onOpen={(path) => app.push(path)} />
    </div>
  );
}
