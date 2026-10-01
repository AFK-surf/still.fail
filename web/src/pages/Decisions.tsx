// The decisions page on the wide screen (奏, from the sidebar's foot): its bar, then the decisions one at a time
// (../Decisions.tsx), 待定 and 不再提醒 as words under the options and as ← →.
import { useNavigate } from "react-router";
import { DecisionDeck } from "../Decisions.tsx";
import { MobileBack } from "../ui.tsx";
import * as css from "../Decisions.css.ts";
import * as sidebarCss from "../styles/sidebar.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";

export function DecisionsPage({ scope, back }: { scope: string; back: string }) {
  const navigate = useNavigate();
  return (
    <div className={css.page}>
      <header className={sidebarCss.pageBar}>
        <MobileBack to={back} label="对话" />
        <div className={conversationCss.pageBarTitle}><h1>奏</h1></div>
      </header>
      <DecisionDeck workspace={scope} swipe={false} inline={false} onEmpty={() => {
        if (((window.history.state as { idx?: number } | null)?.idx ?? 0) > 0) navigate(-1);
        else navigate(back, { replace: true });
      }} onOpen={(path) => navigate(path)} />
    </div>
  );
}
