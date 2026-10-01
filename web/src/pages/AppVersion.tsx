// The desktop app's own version, and looking for a newer build now rather than at the next check (apps/desktop/src/main.ts).
import { useState } from "react";
import { useAppUpdate } from "../brand.tsx";
import type { UpdateCheck } from "../core/client.ts";
import { Button, MobileBack, Section } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as css from "./AppVersion.css.ts";

import { NAME } from "../channel.ts";
/** Only the desktop app has a version of its own to show. */
export const HAS_VERSION = typeof window !== "undefined" && !!window.stillfailDesktop?.version;

export function AppVersionPage({ back }: { back: string }) {
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label="设置" />
      <header className={pagesCss.pageHead}><div><h1>版本</h1></div></header>
      <Section title={`${NAME} 桌面版`} description="启动时和每 4 小时自动检查一次，有新版本时侧栏顶上会出现「更新」">
        <AppVersion />
      </Section>
    </div>
  );
}

function AppVersion() {
  const desktop = window.stillfailDesktop;
  const update = useAppUpdate();
  const [checking, setChecking] = useState(false);
  const [found, setFound] = useState<UpdateCheck | null>(null);
  const check = desktop?.appUpdate?.check;
  const run = () => {
    if (!check) return;
    setChecking(true);
    void check().then(setFound, (error: Error) => setFound({ current: desktop?.version ?? "", error: error.message })).finally(() => setChecking(false));
  };
  const note = update?.phase === "downloading" ? `正在下载 ${update.version}：${update.percent}%`
    : update?.phase === "installing" ? `${update.version} 下好了，正在重启`
    : update?.phase === "failed" ? `更新到 ${update.version} 失败：${update.message}`
    : update ? `有新版本 ${update.version}`
    : checking ? "正在检查…"
    : found?.error ? `检查失败：${found.error}`
    : found ? "已是最新版本"
    : null;
  const bad = update?.phase === "failed" || (!update && !checking && !!found?.error);
  const busy = update?.phase === "downloading" || update?.phase === "installing";
  return (
    <div className={css.row}>
      <div className={css.text}>
        <span>{desktop?.version}</span>
        {note && <span className={bad ? css.failed : css.note}>{note}</span>}
      </div>
      {update
        ? <Button variant="primary" busy={busy} onClick={() => desktop?.appUpdate?.start()}>{update.phase === "failed" ? "重试" : `更新到 ${update.version}`}</Button>
        : check && <Button busy={checking} onClick={run}>检查更新</Button>}
    </div>
  );
}
