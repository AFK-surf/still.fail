// A station's software and whether newer versions are out (the station's updates.rs): the station itself, Claude Code
// and Codex, each updated (or a runtime installed) from here by whoever may. Grey but for what wants doing.
import type { SoftwareVersion } from "./core/shapes.ts";
import { stationApi, useAction, useStationCall } from "./api.ts";
import { EdgeChip } from "./components.tsx";
import { Switch, Tip } from "./ui.tsx";
import * as css from "./Versions.css.ts";

/**
 * `updates`: the station's overview's (none from a station older than them: nothing shows); `manager`: may update;
 * `beta`: the 测试版 switch is offered (the core's `betaOffered`); `rows`: one to a line.
 */
export function Versions({ station, updates, manager, beta = false, rows = false }: { station: string; updates: SoftwareVersion[] | undefined; manager: boolean; beta?: boolean; rows?: boolean }) {
  const { update, check, channel, auto } = useSoftware(station);
  if (!updates?.length) return null;
  const checked = updates[0]?.checkedAt;
  const on = onBeta(updates, channel);
  const autoOn = autoUpdating(updates, auto);
  const error = update.error ?? channel.error ?? auto.error ?? (check.error && new Error(`没能检查更新：${check.error.message}`));
  return (
    <div className={`${css.versions}${rows ? ` ${css.rows}` : ""}`}>
      {updates.map((v) => <Item key={v.id} v={v} manager={manager} busy={update.busy && update.args?.[0] === v.id} onUpdate={() => void update.run(v.id)} />)}
      {beta && manager && on != null && (
        <label className={css.channel}>
          测试版
          <Switch small checked={on} disabled={channel.busy} label="测试版" onChange={(next) => void channel.run(next ? "beta" : "stable")} />
        </label>
      )}
      {manager && autoOn != null && (
        <Tip label="有新版本时 station 自己更新，agent 不中断">
          <label className={css.channel}>
            自动更新
            <Switch small checked={autoOn} disabled={auto.busy} label="自动更新" onChange={(next) => void auto.run(next)} />
          </label>
        </Tip>
      )}
      {checked == null ? <span>正在检查版本…</span>
        : <Tip label={`上次检查：${new Date(checked).toLocaleString()}`}>
          <button type="button" className={css.check} disabled={check.busy} onClick={() => void check.run()}>{check.busy ? "正在检查…" : "检查更新"}</button>
        </Tip>}
      {error && <span className={css.failed}>{error.message}</span>}
    </div>
  );
}

/**
 * Whether the station is on the test channel, as its versions say (while a switch is going, as it was asked); null
 * when it cannot be put on one (a station older than channels, or one not updated from here).
 */
export function onBeta(updates: SoftwareVersion[], channel: ReturnType<typeof useSoftware>["channel"]): boolean | null {
  const now = updates.find((v) => v.id === "station")?.channel;
  if (now == null) return null;
  return channel.busy && channel.args ? channel.args[0] === "beta" : now === "beta";
}

/**
 * Whether the station updates itself, as its versions say (while it is being turned on or off, as it was asked); null
 * when it cannot (a station older than it, or one not updated from here).
 */
export function autoUpdating(updates: SoftwareVersion[], auto: ReturnType<typeof useSoftware>["auto"]): boolean | null {
  const now = updates.find((v) => v.id === "station")?.auto;
  if (now == null) return null;
  return auto.busy && auto.args ? auto.args[0] : now;
}

/** Updating a station's software and checking for newer versions, as both screens do (the phone's: ./mobile/Versions.tsx). */
export function useSoftware(station: string) {
  const api = stationApi(useStationCall(station));
  const update = useAction((id: string) => api.updateSoftware<SoftwareVersion[]>(id));
  const check = useAction(() => api.checkSoftware<SoftwareVersion[]>());
  const channel = useAction((to: "stable" | "beta") => api.setSoftwareChannel<SoftwareVersion[]>(to));
  const auto = useAction((on: boolean) => api.setSoftwareAuto<SoftwareVersion[]>(on));
  return { update, check, channel, auto };
}

/**
 * How a piece of software is said: its version as shown, what updating it is called, what is said about it on hover,
 * whether it is the test channel's (a 测试版 tag beside its version), and while it updates where that is (the station
 * says; one older than that, nothing more than 正在更新).
 */
export function describe(v: SoftwareVersion): { shown: string; verb: string; tip: string; updating: string; beta: boolean } {
  return {
    shown: v.installed ? (v.version ?? (v.id === "station" ? "开发版" : "版本未知")) : "未安装",
    verb: v.installed ? "更新" : "安装",
    tip: [v.note, v.installed && !v.newer && !v.downgrade && v.latest ? "已是最新" : null, v.installed && !v.latest && v.checkedAt ? "检查更新失败，点「检查更新」重试" : null].filter(Boolean).join("；"),
    beta: v.channel === "beta",
    updating: v.progress ?? (v.installed ? "正在更新…" : "正在安装…"),
  };
}

function Item({ v, manager, busy, onUpdate }: { v: SoftwareVersion; manager: boolean; busy: boolean; onUpdate(): void }) {
  const { shown, verb, tip, updating, beta } = describe(v);
  const button = (label: string) => manager && v.updatable && (
    <button type="button" className={css.action} disabled={busy} onClick={onUpdate}>{label}</button>
  );
  let rest;
  if (v.state === "updating") rest = <>{v.percent != null && <DownloadChip percent={v.percent} />}<span className={css.newer}>{updating}</span></>;
  else if (v.state === "failed") rest = <><Tip label={v.message ?? ""}><span className={css.failed}>{verb}失败</span></Tip>{button("重试")}</>;
  else if (!v.installed) rest = button("安装");
  else if (v.newer && v.latest) rest = <><span className={css.newer}>→ {v.latest}</span>{button("更新")}</>;
  else if (v.downgrade && v.latest) rest = <><span className={css.newer}>→ {v.latest}</span>{button("回到正式版")}</>;
  else if (v.done) rest = <span className={css.newer}>{v.done}</span>;
  return (
    <span className={css.item}>
      <Tip label={tip}><span>{v.name} <span className={css.version}>{shown}</span></span></Tip>
      {beta && <span className={css.betaTag}>测试版</span>}
      {rest}
    </span>
  );
}

/** How much of what a runtime's install downloads is in: the allowance's rounded box, its edge going round as it comes. */
export function DownloadChip({ percent }: { percent: number }) {
  return <EdgeChip fill={percent} level="progress" label={`已下载 ${percent}%`} bare />;
}
