// The machine this station runs on.
import { useHost, useOverview } from "../api.ts";
import { DeviceCard } from "../components.tsx";
import { About, MobileBack } from "../ui.tsx";
import { Versions } from "../Versions.tsx";
import * as pagesCss from "../styles/pages.css.ts";

export function DevicePage() {
  const host = useHost("local");
  const overview = useOverview("local");
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to="/settings" label="设置" />
      <header className={pagesCss.pageHead}><div><h1>设备<About>这台 station 所在的机器，每 15 秒更新。</About></h1></div></header>
      <div className={pagesCss.card}><DeviceCard host={host.value} processes={overview.value?.processesText} /></div>
      {overview.value?.updates?.length ? <div className={pagesCss.card}><Versions station="local" updates={overview.value.updates} manager rows /></div> : null}
    </div>
  );
}
