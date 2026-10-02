import { Fragment } from "react";
import { useAutomaticDecisionForm } from "../AutomaticDecisions.tsx";
import { useStations } from "../api.ts";
import type { AutomaticDecisionView } from "../core/shapes.ts";
import { Refresh } from "../icons.tsx";
import { stationBase } from "../station.tsx";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { Button, FailedMark, LargeTitle, ListCard, ListRow, NavButton, PickRow, SectionHeader, Spinner, TopBack } from "./parts.tsx";
import { GoRow } from "./Settings.tsx";
import { Time } from "../ui.tsx";
import * as css from "./AutomaticDecisions.css.ts";
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
    {!stations.value && <p className={settings.mPageNote}>{stations.error?.message ?? "正在读取…"}</p>}
    {stations.value?.map(s => <Fragment key={s.station}>
      {s.online && s.overview?.automaticDecisions ? <DecisionPanel station={s.station} name={s.name} view={s.overview.automaticDecisions} />
        : <p className={settings.mPageNote}>{!s.online ? "station 上线后可配置和查看记录" : !s.overview ? "正在连接…" : "更新这台 station 后可使用自动决策"}</p>}
    </Fragment>)}
    <div style={{height:30}} />
  </div>;
}
function DecisionPanel({station,name,view}:{station:string;name:string;view:AutomaticDecisionView}) {
  const app=useApp();
  const {d,state,saving,refreshing,saveFailed,refreshFailed,edit,save,refresh}=useAutomaticDecisionForm(station,view);
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
    <div className={css.stationHead}><div className={css.stationName}><SectionHeader title={name} start={24} /></div>{refreshing ? <Spinner size={16} /> : <NavButton icon={Refresh} label="重新发现模型" onClick={refresh} />}</div>
    {refreshFailed && <p className={`${settings.mPageNote} ${parts.mRed}`}>{refreshFailed}</p>}
    <ListCard>
      <ListRow onClick={busy ? undefined : ()=>edit({enabled:!d.enabled})}>
        <span className={`${parts.mGrow} ${lists.mRowText}`}><span className={lists.mRowTitle}>完成检查</span><span className={`${lists.mRowNote} ${settings.mWrap}`}>结束前检查遗漏和待处理事项</span></span>
        <span className={connects.mSwitch} data-on={d.enabled || undefined} />
      </ListRow>
      <GoRow title="决策模型" value={chosen?.name ?? (d.model ? `${d.model} · 暂不可用` : "选择模型")} onClick={()=>{if(!busy)pick();}} />
    </ListCard>
    {d.dirty && <div className={settings.mProfileTools}><Button label="保存修改" primary busy={saving} enabled={!busy} onClick={save} />{saveFailed && <FailedMark error={saveFailed} size={14} />}</div>}
    <SectionHeader title="最近检查" start={24} />
    <ListCard>
      {!view.recent.length && <ListRow><span className={parts.mMuted}>还没有记录</span></ListRow>}
      {view.recent.map(row=><ListRow key={row.id} onClick={()=>app.push(`${stationBase(station)}/chats/${encodeURIComponent(row.session)}`)}>
        <span className={`${parts.mGrow} ${lists.mRowText}`}>
          <span className={css.rowHead}><span className={`${parts.mGrow} ${lists.mRowTitle}`}>{row.title}</span><Time stamp={row.stamp} className={css.time} /></span>
          <span className={css.meta}><span className={row.accepted ? undefined : parts.mRed}>{row.label}</span><span>·</span><span>{row.model}</span></span>
          {row.error && <span className={`${lists.mRowNote} ${parts.mRed}`}>{row.error}</span>}
        </span>
      </ListRow>)}
    </ListCard>
  </>;
}
