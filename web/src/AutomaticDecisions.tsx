import { useEffect, useId } from "react";
import { Link } from "react-router";
import { useStations } from "./api.ts";
import { useCall, useTopic } from "./core/react.ts";
import type { AutomaticDecisionDraft, AutomaticDecisionView } from "./core/shapes.ts";
import { useAct } from "./toast.tsx";
import { useDoing, useDoingFailed } from "./doing.ts";
import { Button, Chooser, ChooserItem, IconButton, Section, StatusDot, Switch, Time, Tip } from "./ui.tsx";
import { Refresh } from "./icons.tsx";
import { stationBase } from "./station.tsx";
import * as pages from "./styles/pages.css.ts";
import * as css from "./AutomaticDecisions.css.ts";

export function AutomaticDecisions({ workspace }: { workspace: string }) {
  const stations = useStations(workspace);
  return <div className={css.content}>
    {!stations.value && <p className={css.note}>{stations.error?.message ?? "正在读取…"}</p>}
    {stations.value?.length === 0 && <p className={css.note}>添加 station 后可配置自动决策</p>}
    {stations.value?.map(s => s.online && s.overview?.automaticDecisions
      ? <AutomaticDecisionPanel key={s.station} station={s.station} name={s.name} view={s.overview.automaticDecisions} />
      : <Section key={s.station} title={s.name}><p className={css.note}>{!s.online ? "station 离线" : !s.overview ? "正在连接…" : "更新这台 station 后可使用自动决策"}</p></Section>)}
  </div>;
}
function AutomaticDecisionPanel({ station, name, view }: { station: string; name: string; view: AutomaticDecisionView }) {
  const {d, state, saving, refreshing, saveFailed, refreshFailed, edit, save, refresh} = useAutomaticDecisionForm(station, view);
  if (!view.canEdit) return <Section title={name}><p className={css.note}>只有管理员可以配置自动决策和查看记录</p></Section>;
  if (!d) return <Section title={name}><p className={css.note}>{state.error?.message ?? "正在读取配置…"}</p></Section>;
  const busy = d.pending || saving;
  const chosen = view.models.find(m => m.id === d.model);
  return <Section title={<span className={css.tools}><StatusDot state="online" label="在线" />{name}</span>} actions={<>
    {d.dirty && <Button variant="primary" busy={saving} disabled={busy} onClick={save}>保存修改</Button>}
    <IconButton label="重新发现模型" icon={Refresh} busy={refreshing} failed={refreshFailed} onClick={refresh} />
  </>}>
    <div className={css.rule}>
      <div className={css.ruleText}><label className={css.ruleTitle} htmlFor={`decision-${station}`}>完成检查</label><span className={css.note}>agent 结束前，检查是否还有遗漏和待处理事项</span></div>
      <div className={css.controls}>
        {view.models.length ? <Tip label={chosen ? `来自 ${chosen.profiles.join("、")}` : "选择完成检查使用的模型"}>
          <span><Chooser disabled={busy} label={chosen?.name ?? (d.model ? `${d.model} · 暂不可用` : "选择模型")}>
            {view.models.map(m => <ChooserItem key={m.id} checked={m.id === d.model} onSelect={() => edit({model:m.id})}>
              <span className={pages.listRowText}><span>{m.name}</span><span className={css.note}>{m.profiles.join("、")}</span></span>
            </ChooserItem>)}
          </Chooser></span>
        </Tip> : <Link className={css.note} to={`${stationBase(station)}/settings/accounts`}>暂无可用模型</Link>}
        <Switch id={`decision-${station}`} label="完成检查" checked={d.enabled} disabled={busy} onChange={enabled => edit({enabled})} />
      </div>
    </div>
    {saveFailed && <p className={css.error} role="alert">{saveFailed}</p>}
    <div className={css.records}><Section title="最近检查">
      {!view.recent.length ? <p className={css.note}>启用完成检查后，结果会显示在这里</p> : <ul className={pages.list}>
        {view.recent.map(row => <li key={row.id}>
          <Link className={pages.listRow} to={`${stationBase(station)}/chats/${encodeURIComponent(row.session)}`}>
            <span className={pages.listRowText}>
              <span className={css.recordHead}><span className={pages.listRowTitle}>{row.title}</span><Time stamp={row.stamp} className={css.time} /></span>
              <span className={css.meta}><span className={row.accepted ? undefined : css.bad}>{row.label}</span><span>·</span><span>{row.model}</span></span>
              {row.error && <span className={css.error}>{row.error}</span>}
            </span>
          </Link>
        </li>)}
      </ul>}
    </Section></div>
  </Section>;
}

/** Both layouts render the same core-owned draft and named actions. */
export function useAutomaticDecisionForm(station: string, view: AutomaticDecisionView) {
  const form = useId(); const call = useCall(); const act = useAct();
  const state = useTopic<AutomaticDecisionDraft | null>({ topic: "decisionForm", station, form });
  const d = state.value;
  const saving = useDoing("automaticDecisions.form.save", { station, form });
  const refreshing = useDoing("automaticDecisions.refresh", { station });
  const saveFailed = useDoingFailed("automaticDecisions.form.save", {station,form});
  const refreshFailed = useDoingFailed("automaticDecisions.refresh", {station});
  useEffect(() => {
    if (!view.canEdit) return;
    act(call("automaticDecisions.form.open", { station, form }), "读取自动决策配置");
    return () => { act(call("automaticDecisions.form.drop", { station, form }), "关闭配置"); };
  }, [call, station, form, view.canEdit, act]);
  const edit = (input: Record<string, unknown>) => act(call("automaticDecisions.form.edit", { station, form, input }), "修改配置");
  return {d, state, saving, refreshing, saveFailed, refreshFailed, edit,
    save: () => act(call("automaticDecisions.form.save", {station,form}), "保存自动决策", "已保存自动决策"),
    refresh: () => act(call("automaticDecisions.refresh", {station}), "刷新决策模型", "已刷新模型")};
}
