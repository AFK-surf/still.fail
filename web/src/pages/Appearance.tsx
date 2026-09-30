// What only this client (browser, desktop app) keeps: how the pages look here.
import { AppearanceSetting, LayoutSetting, RowPictureSetting } from "../components.tsx";
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
      <Section title="布局" description="侧边栏：对话列表常驻在左边。搜索列表：没有侧边栏，对话列表是单独一页，顶上是搜索；在对话里点左上角回到列表。">
        <div className={chatCss.appearanceSetting}><LayoutSetting /></div>
      </Section>
      <Section title="侧栏头像" description="会话列表里每行以谁的头像为主。自动：只有你一个人时以 agent 为主，有别人参与才在旁边显示人；多人的 workspace 以人为主，agent 在旁边。发起的人带一圈描边。">
        <div className={chatCss.appearanceSetting}><RowPictureSetting /></div>
      </Section>
    </div>
  );
}
