// What only this client (browser, desktop app) keeps: how the pages look here.
import { AppearanceSetting } from "../components.tsx";
import { MobileBack, Section } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as chatCss from "../styles/chat.css.ts";

export function AppearancePage({ back }: { back: string }) {
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label="设置" />
      <header className={pagesCss.pageHead}><div><h1>外观</h1></div></header>
      <Section title="主题" description="浅色、深色，或跟着系统走。只对这个浏览器生效。">
        <div className={chatCss.appearanceSetting}><AppearanceSetting /></div>
      </Section>
    </div>
  );
}
