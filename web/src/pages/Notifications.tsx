// Whether this client tells its person about their chats (notify.ts, docs/notifications.md).
import { useState } from "react";
import { setNotify, useNotifyState } from "../notify.ts";
import { MobileBack, SwitchRow } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";

export function NotificationsPage({ back }: { back: string }) {
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label="设置" />
      <header className={pagesCss.pageHead}><div><h1>通知</h1></div></header>
      <NotifySwitch />
    </div>
  );
}

export function NotifySwitch() {
  const state = useNotifyState();
  const [busy, setBusy] = useState(false);
  const desktop = !!window.stillfailDesktop;
  const note = state === "unsupported" ? "这个浏览器不支持通知"
    : state === "denied" ? "浏览器拦下了通知，要在浏览器的网站设置里打开"
    : `你参与的 chat 里 agent 做完、需要处理、出错，或者有人说话时提醒你。正在看的 chat 不提醒，只对这个${desktop ? "设备" : "浏览器"}生效${desktop ? "（系统设置里也要允许 still.fail 发通知）" : ""}`;
  return (
    <SwitchRow title="聊天通知" description={note} checked={state === "on"} disabled={busy || state === "denied" || state === "unsupported"}
      onChange={(on) => { setBusy(true); void setNotify(on).finally(() => setBusy(false)); }} />
  );
}
