// The machine this station runs on.
import { useHost, useOverview } from "../api.ts";
import { DeviceCard } from "../components.tsx";
import { MobileBack } from "../ui.tsx";

export function DevicePage() {
  const host = useHost();
  const overview = useOverview();
  return (
    <div className="page page-narrow">
      <MobileBack to="/settings" label="设置" />
      <header className="page-head"><div><h1>设备</h1><p className="page-sub">这台 station 所在的机器。每 15 秒更新。</p></div></header>
      <div className="card"><DeviceCard host={host.data} processes={overview.data?.processes} /></div>
    </div>
  );
}
