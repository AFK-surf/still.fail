import { Fragment } from "react";
import { useAutomaticDecisionForm } from "../AutomaticDecisions.tsx";
import { useStations } from "../api.ts";
import type { AutomaticDecisionView } from "../core/shapes.ts";
import { ChevronRight } from "../icons.tsx";
import { stationBase } from "../station.tsx";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { Button, LargeTitle, ListCard, ListRow, PickRow, SectionHeader, TopBack } from "./parts.tsx";
import { GoRow } from "./Settings.tsx";
import * as pages from "./styles/pages.css.ts";
import * as parts from "./styles/parts.css.ts";
import * as lists from "./styles/lists.css.ts";
import * as settings from "./styles/settings.css.ts";
import * as sheets from "./styles/sheets.css.ts";
import * as connects from "./Connects.css.ts";

export function AutomaticDecisionsScreen() {
  const app = useApp();
  const stations = useStations(app.entry.id);
  return <div className={`${pages.mScreen} ${pages.mScroll}`}>
    <TopBack label="设置" onBack={app.pop} />
    <LargeTitle small="" big="自动决策" />
    <p className={settings.mPageNote}>选择自动判断的事项和模型</p>
    {!stations.value && <p className={settings.mPageNote}>{stations.error?.message ?? "正在读取…"}</p>}
    {stations.value?.map(s => <Fragment key={s.station}>
      <SectionHeader title={s.online ? s.name : `${s.name} · 离线`} start={24} />
      {s.online && s.overview?.automaticDecisions ? <DecisionPanel station={s.station} view={s.overview.automaticDecisions} />
        : <p className={settings.mPageNote}>{!s.online ? "station 上线后可配置和查看记录" : !s.overview ? "正在连接…" : "更新这台 station 后可使用自动决策"}</p>}
    </Fragment>)}
    <div style={{height:30}} />
  </div>;
}
function DecisionPanel({station,view}:{station:string;view:AutomaticDecisionView}) {
  const app=useApp();
  const {d,state,saving,refreshing,edit,save,refresh}=useAutomaticDecisionForm(station,view);
  if (!view.canEdit) return <p className={settings.mPageNote}>只有管理员可以配置和查看记录</p>;
  if (!d) return <p className={settings.mPageNote}>{state.error?.message ?? "正在读取配置…"}</p>;
  const busy=d.pending || saving;
  const chosen=view.models.find(m=>m.id===d.model);
  const pick=()=>app.sheet({height:0.5,content:()=><>
    <SheetGrab /><SheetHead title="决策模型" />
    <div className={sheets.mSheetScroll}>
      {!view.models.length && <p className={settings.mPageNote}>现有 Profile 暂无可用决策模型</p>}
      {view.models.map(m=><PickRow key={m.id} label={m.name} sub={m.profiles.join("、")} checked={m.id===d.model} onClick={()=>{app.sheet(null);edit({model:m.id});}} />)}
    </div>
  </>});
  return <>
    <ListCard>
      <ListRow onClick={busy ? undefined : ()=>edit({enabled:!d.enabled})}>
        <span className={`${parts.mGrow} ${lists.mRowText}`}><span className={lists.mRowTitle}>完成检查</span><span className={`${lists.mRowNote} ${settings.mWrap}`}>结束前检查未完成的工作和待处理事项</span></span>
        <span className={connects.mSwitch} data-on={d.enabled || undefined} />
      </ListRow>
      <GoRow title="决策模型" value={chosen?.name ?? (d.model ? `${d.model} · 暂不可用` : "选择模型")} onClick={()=>{if(!busy)pick();}} />
    </ListCard>
    <p className={settings.mPageNote}>{chosen ? `来自 ${chosen.profiles.join("、")}` : "自动识别现有 Profile 中可用的模型"}</p>
    <div className={settings.mProfileTools}>
      <Button label="保存" primary busy={saving} enabled={!busy && d.dirty} onClick={save} />
      <Button label="刷新模型" primary={false} busy={refreshing} enabled={!refreshing} onClick={refresh} />
    </div>
    <SectionHeader title="最近决策" start={24} />
    <ListCard>
      {!view.recent.length && <ListRow><span className={parts.mMuted}>还没有记录</span></ListRow>}
      {view.recent.map(row=><ListRow key={row.id} onClick={()=>app.push(`${stationBase(station)}/chats/${encodeURIComponent(row.session)}`)}>
        <span className={`${parts.mGrow} ${lists.mRowText}`}>
          <span className={lists.mRowTitle}>{row.title}</span>
          <span className={lists.mRowNote}>{row.model}</span>
          {row.error && <span className={`${lists.mRowNote} ${parts.mRed}`}>{row.error}</span>}
        </span>
        <span className={`${settings.mRowAside} ${row.accepted ? "" : parts.mRed}`}>{row.label}</span>
        <ChevronRight size={14} className={parts.mSubtle} />
      </ListRow>)}
    </ListCard>
  </>;
}
