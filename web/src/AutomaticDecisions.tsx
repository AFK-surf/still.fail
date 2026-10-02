import { useEffect, useId } from "react";
import { Link } from "react-router";
import { useStations } from "./api.ts";
import { useCall, useTopic } from "./core/react.ts";
import type { AutomaticDecisionDraft, AutomaticDecisionView } from "./core/shapes.ts";
import { useAct } from "./toast.tsx";
import { useDoing } from "./doing.ts";
import { Button, Field, Select, SwitchRow } from "./ui.tsx";
import { stationBase } from "./station.tsx";
import * as css from "./AutomaticDecisions.css.ts";

export function AutomaticDecisions({ workspace }: { workspace: string }) {
  const stations = useStations(workspace);
  return <div className={css.stations}>
    {!stations.value && <p className={css.note}>{stations.error?.message ?? "正在读取…"}</p>}
    {stations.value?.length === 0 && <p className={css.note}>添加 station 后可配置自动决策</p>}
    {stations.value?.map(s => <section key={s.station}>
      <h2 className={css.stationName}>{s.name}</h2>
      {!s.online ? <p className={css.note}>station 上线后可配置和查看记录</p>
        : !s.overview ? <p className={css.note}>正在连接…</p>
        : !s.overview.automaticDecisions ? <p className={css.note}>更新这台 station 后可使用自动决策</p>
        : <AutomaticDecisionPanel station={s.station} view={s.overview.automaticDecisions} />}
    </section>)}
  </div>;
}
function AutomaticDecisionPanel({ station, view }: { station: string; view: AutomaticDecisionView }) {
  const form = useId(); const call = useCall(); const act = useAct();
  const state = useTopic<AutomaticDecisionDraft | null>({ topic: "decisionForm", station, form });
  const d = state.value;
  const saving = useDoing("automaticDecisions.form.save", { station, form });
  const refreshing = useDoing("automaticDecisions.refresh", { station });
  useEffect(() => {
    if (!view.canEdit) return;
    act(call("automaticDecisions.form.open", { station, form }), "读取自动决策配置");
    return () => { act(call("automaticDecisions.form.drop", { station, form }), "关闭配置"); };
  }, [call, station, form, view.canEdit, act]);
  const edit = (input: Record<string, unknown>) => act(call("automaticDecisions.form.edit", { station, form, input }), "修改配置");
  if (!view.canEdit) return <p className={css.note}>只有 workspace 管理员可以配置自动决策和查看记录</p>;
  if (!d) return <p className={css.note}>{state.error?.message ?? "正在读取配置…"}</p>;
  const busy = d.pending || saving;
  const chosen = view.models.find(m => m.id === d.model);
  const options = [{ value: "", label: "选择决策模型" }, ...view.models.map(m => ({value:m.id,label:m.name}))];
  if (d.model && !chosen) options.push({ value:d.model, label:`${d.model} · 暂不可用` });
  return <>
    <section className={css.rule}>
      <SwitchRow title="完成检查" description="agent 宣告完成时，检查是否还有未完成的工作或需要关注的信息" checked={d.enabled} disabled={busy} onChange={enabled => edit({enabled})} />
      <div className={css.model}>
        <Field label="决策模型" htmlFor={`${form}-model`}>
          <Select id={`${form}-model`} label="完成检查使用的模型" value={d.model} disabled={busy} options={options} onChange={model => edit({model})} />
        </Field>
        <div className={css.source}>
          <span>{chosen ? `复用 ${chosen.profiles.join("、")}` : view.models.length ? "模型自动从现有 Profile 识别" : "现有 Profile 暂无可用决策模型"}</span>
          <Button busy={refreshing} disabled={refreshing} onClick={() => act(call("automaticDecisions.refresh", {station}), "刷新决策模型", "已刷新模型")}>刷新模型</Button>
        </div>
      </div>
      <p className={css.note}>{d.enabled ? "发现仍需处理的事项时，阻止误结束并让 agent 继续处理" : "未启用 · 由 agent 自己判断是否完成"}</p>
      <div className={css.actions}>
        <Button variant="primary" busy={saving} disabled={busy || !d.dirty} onClick={() => act(call("automaticDecisions.form.save", {station,form}), "保存自动决策", "已保存自动决策")}>保存</Button>
        <span className={css.note}>{d.dirty ? "有未保存的修改" : "配置已保存"}</span>
      </div>
    </section>
    <section className={css.history}>
      <h3 className={css.sectionName}>最近决策</h3>
      {!view.recent.length ? <p className={css.note}>还没有记录 · 启用后，每次完成检查会显示在这里</p> : <ol className={css.records}>
        {view.recent.map(row => <li key={row.id} className={css.record}>
          <div className={css.recordHead}><Link to={`${stationBase(station)}/chats/${encodeURIComponent(row.session)}`}>{row.title}</Link><span className={css.result} data-bad={!row.accepted || undefined}>{row.label}</span></div>
          <div className={css.recordMeta}><span>完成检查 · {row.model}</span><span>{row.accepted ? "已放行" : "未结束"} · {row.elapsedMs} ms</span></div>
          {row.error && <p className={css.error}>{row.error}</p>}
        </li>)}
      </ol>}
    </section>
  </>;
}
