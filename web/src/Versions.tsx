// A station's software and whether newer versions are out (the station's updates.rs): the station itself, Claude Code
// and Codex, each updated (or a runtime installed) from here by whoever may. Grey but for what wants doing.
import type { SoftwareVersion } from "./core/shapes.ts";
import { stationApi, useAction, useStationCall } from "./api.ts";
import { Tip } from "./ui.tsx";
import * as css from "./Versions.css.ts";

/**
 * `updates`: the station's overview's (none from a station older than them: nothing shows); `manager`: may update;
 * `rows`: one to a line.
 */
export function Versions({ station, updates, manager, rows = false }: { station: string; updates: SoftwareVersion[] | undefined; manager: boolean; rows?: boolean }) {
  const { update, check } = useSoftware(station);
  if (!updates?.length) return null;
  const checked = updates[0]?.checkedAt;
  return (
    <div className={`${css.versions}${rows ? ` ${css.rows}` : ""}`}>
      {updates.map((v) => <Item key={v.id} v={v} manager={manager} busy={update.busy && update.args?.[0] === v.id} onUpdate={() => void update.run(v.id)} />)}
      {checked == null ? <span>正在检查版本…</span>
        : <Tip label={`上次检查：${new Date(checked).toLocaleString()}`}>
          <button type="button" className={css.check} disabled={check.busy} onClick={() => void check.run()}>{check.busy ? "正在检查…" : "检查更新"}</button>
        </Tip>}
      {update.error && <span className={css.failed}>{update.error.message}</span>}
    </div>
  );
}

/** Updating a station's software and checking for newer versions, as both screens do (the phone's: ./mobile/Versions.tsx). */
export function useSoftware(station: string) {
  const api = stationApi(useStationCall(station));
  const update = useAction((id: string) => api.updateSoftware<SoftwareVersion[]>(id));
  const check = useAction(() => api.checkSoftware<SoftwareVersion[]>());
  return { update, check };
}

/** How a piece of software is said: its version as shown, what updating it is called, what is said about it on hover. */
export function describe(v: SoftwareVersion): { shown: string; verb: string; tip: string; updating: string } {
  return {
    shown: v.installed ? (v.version ?? (v.id === "station" ? "开发版" : "版本未知")) : "未安装",
    verb: v.installed ? "更新" : "安装",
    tip: [v.note, v.installed && !v.newer && v.latest ? "已是最新" : null, v.installed && !v.latest && v.checkedAt ? "查不到最新版本" : null].filter(Boolean).join("；"),
    updating: v.installed ? `正在更新${v.id === "station" ? "（等 agent 这一轮跑完）" : ""}…` : "正在安装…",
  };
}

function Item({ v, manager, busy, onUpdate }: { v: SoftwareVersion; manager: boolean; busy: boolean; onUpdate(): void }) {
  const { shown, verb, tip, updating } = describe(v);
  const button = (label: string) => manager && v.updatable && (
    <button type="button" className={css.action} disabled={busy} onClick={onUpdate}>{label}</button>
  );
  let rest;
  if (v.state === "updating") rest = <span className={css.newer}>{updating}</span>;
  else if (v.state === "failed") rest = <><Tip label={v.message ?? ""}><span className={css.failed}>{verb}失败</span></Tip>{button("重试")}</>;
  else if (!v.installed) rest = button("安装");
  else if (v.newer && v.latest) rest = <><span className={css.newer}>→ {v.latest}</span>{button("更新")}</>;
  return (
    <span className={css.item}>
      <Tip label={tip}><span>{v.name} <span className={css.version}>{shown}</span></span></Tip>
      {rest}
    </span>
  );
}
