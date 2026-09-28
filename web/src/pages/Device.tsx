// The machine this station runs on.
import { useHost, useOverview } from "../api.ts";
import { AppearanceSetting, DeviceCard } from "../components.tsx";
import { About, MobileBack, Section } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as chatCss from "../styles/chat.css.ts";

export function DevicePage() {
  const host = useHost("local");
  const overview = useOverview("local");
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to="/settings" label="设置" />
      <header className={pagesCss.pageHead}><div><h1>设备<About>这台 station 所在的机器，每 15 秒更新。</About></h1></div></header>
      <div className={pagesCss.card}><DeviceCard host={host.value} processes={overview.value?.processesText} /></div>
      <Section title="外观" description="浅色、深色，或跟着系统走。只对这个浏览器生效。">
        <div className={chatCss.appearanceSetting}><AppearanceSetting /></div>
      </Section>
    </div>
  );
}
