import { useEffect, useId } from "react";
import { Link } from "react-router";
import { useStations } from "./api.ts";
import { useCall, useTopic } from "./core/react.ts";
import type { AutomaticDecisionDraft, AutomaticDecisionView } from "./core/shapes.ts";
import { useAct } from "./toast.tsx";
import { useDoing } from "./doing.ts";
import { Button, Field, Select, SwitchRow, Section } from "./ui.tsx";
import { stationBase } from "./station.tsx";
import * as pages from "./styles/pages.css.ts";
import * as shell from "./styles/shell.css.ts";
import * as controls from "./styles/controls.css.ts";

export function AutomaticDecisions({ workspace }: { workspace: string }) {
  const stations = useStations(workspace);
  return <div>
    {!stations.value && <p className={shell.muted}>{stations.error?.message ?? "正在读取…"}</p>}
    {stations.value?.length === 0 && <p className={shell.muted}>添加 station 后可配置自动决策</p>}
    {stations.value?.map(s => <Section key={s.station} title={s.name}>
      {!s.online ? <p className={shell.muted}>station 上线后可配置和查看记录</p>
        : !s.overview ? <p className={shell.muted}>正在连接…</p>
        : !s.overview.automaticDecisions ? <p className={shell.muted}>更新这台 station 后可使用自动决策</p>
        : <AutomaticDecisionPanel station={s.station} view={s.overview.automaticDecisions} />}
    </Section>)}
  </div>;
}
function AutomaticDecisionPanel({ station, view }: { station: string; view: AutomaticDecisionView }) {
  const {d, state, saving, refreshing, edit, save, refresh} = useAutomaticDecisionForm(station, view);
  if (!view.canEdit) return <p className={shell.muted}>只有 workspace 管理员可以配置自动决策和查看记录</p>;
  if (!d) return <p className={shell.muted}>{state.error?.message ?? "正在读取配置…"}</p>;
  const busy = d.pending || saving;
  const chosen = view.models.find(m => m.id === d.model);
  const options = [{ value: "", label: "选择决策模型" }, ...view.models.map(m => ({value:m.id,label:m.name}))];
  if (d.model && !chosen) options.push({ value:d.model, label:`${d.model} · 暂不可用` });
  return <>
    <div className={pages.card}>
      <SwitchRow title="完成检查" description="agent 宣告完成时，检查是否还有未完成的工作或需要关注的信息" checked={d.enabled} disabled={busy} onChange={enabled => edit({enabled})} />
      <div>
        <Field label="决策模型" >
          <Select label="完成检查使用的模型" value={d.model} disabled={busy} options={options} onChange={model => edit({model})} />
        </Field>
        <div className={pages.cardRow}>
          <span>{chosen ? `复用 ${chosen.profiles.join("、")}` : view.models.length ? "模型自动从现有 Profile 识别" : "现有 Profile 暂无可用决策模型"}</span>
          <Button busy={refreshing} disabled={refreshing} onClick={refresh}>刷新模型</Button>
        </div>
      </div>
      <p className={shell.muted}>{d.enabled ? "发现仍需处理的事项时，阻止误结束并让 agent 继续处理" : "未启用 · 由 agent 自己判断是否完成"}</p>
      <div className={pages.cardActions}>
        <Button variant="primary" busy={saving} disabled={busy || !d.dirty} onClick={save}>保存</Button>
        {d.dirty && <span className={shell.muted}>有未保存的修改</span>}
      </div>
    </div>
    <Section title="最近决策">
      {!view.recent.length ? <p className={shell.muted}>还没有记录 · 启用后，每次完成检查会显示在这里</p> : <ul className={pages.list}>
        {view.recent.map(row => <li key={row.id}>
          <Link className={pages.listRow} to={`${stationBase(station)}/chats/${encodeURIComponent(row.session)}`}>
            <span className={pages.listRowText}><span className={pages.listRowTitle}>{row.title}</span><span className={shell.muted}>{row.model}{row.error ? ` · ${row.error}` : ""}</span></span>
            <span className={row.accepted ? shell.muted : controls.fieldError}>{row.label}</span>
          </Link>
        </li>)}
      </ul>}
    </Section>
  </>;
}

/** Both layouts render the same core-owned draft and named actions. */
export function useAutomaticDecisionForm(station: string, view: AutomaticDecisionView) {
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
  return {d, state, saving, refreshing, edit,
    save: () => act(call("automaticDecisions.form.save", {station,form}), "保存自动决策", "已保存自动决策"),
    refresh: () => act(call("automaticDecisions.refresh", {station}), "刷新决策模型", "已刷新模型")};
}
