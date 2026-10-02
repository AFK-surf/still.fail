import { AutomaticDecisions } from "../AutomaticDecisions.tsx";
import { useApp } from "./app.tsx";
import { LargeTitle, TopBack } from "./parts.tsx";
import * as pages from "./styles/pages.css.ts";
import * as root from "./styles/root.css.ts";
export function AutomaticDecisionsScreen() {
  const app = useApp();
  return <div className={`${pages.mScreen} ${pages.mScroll}`}>
    <TopBack label="设置" onBack={app.pop} />
    <LargeTitle small="" big="自动决策" />
    <div className={root.wide} style={{ padding: "12px 20px 32px" }}><AutomaticDecisions workspace={app.entry.id} /></div>
  </div>;
}
