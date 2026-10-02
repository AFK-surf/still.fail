import { t } from "../i18n.ts";
import { Fragment } from "react";
import { useAutomaticDecisionForm } from "../AutomaticDecisions.tsx";
import { useStations } from "../api.ts";
import type { AutomaticDecisionView } from "../core/shapes.ts";
import { Refresh } from "../icons.tsx";
import { stationBase } from "../station.tsx";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { Button, FailedMark, LargeTitle, ListCard, ListRow, NavButton, SectionHeader, Spinner, TopBack } from "./parts.tsx";
import { ModelList } from "./History.tsx";
import { GoRow } from "./Settings.tsx";
import { Time } from "../ui.tsx";
import * as css from "./AutomaticDecisions.css.ts";
import * as pages from "./styles/pages.css.ts";
import * as parts from "./styles/parts.css.ts";
import * as lists from "./styles/lists.css.ts";
import * as settings from "./styles/settings.css.ts";
import * as connects from "./Connects.css.ts";

export function AutomaticDecisionsScreen() {
  const app = useApp();
  const stations = useStations(app.entry.id);
  return <div className={`${pages.mScreen} ${pages.mScroll}`}>
    <TopBack label={t("web-pages.settings.title")} onBack={app.pop} />
    <LargeTitle small="" big={t("web-pages.automaticDecisions.title")} />
    {!stations.value && <p className={settings.mPageNote}>{stations.error?.message ?? t("web-pages.automaticDecisions.reading")}</p>}
    {stations.value?.map(s => <Fragment key={s.station}>
      {s.online && s.overview?.automaticDecisions ? <DecisionPanel station={s.station} name={s.name} view={s.overview.automaticDecisions} />
        : <p className={settings.mPageNote}>{!s.online ? t("web-pages.automaticDecisions.offlineNote") : !s.overview ? t("web-pages.automaticDecisions.connecting") : t("web-pages.automaticDecisions.upgrade")}</p>}
    </Fragment>)}
    <div style={{height:30}} />
  </div>;
}
function DecisionPanel({station,name,view}:{station:string;name:string;view:AutomaticDecisionView}) {
  const app=useApp();
  const {d,state,saving,refreshing,saveFailed,refreshFailed,edit,save,refresh}=useAutomaticDecisionForm(station,view);
  if (!view.canEdit) return <p className={settings.mPageNote}>只有管理员可以配置和查看记录</p>;
  if (!d) return <p className={settings.mPageNote}>{state.error?.message ?? t("web-pages.automaticDecisions.readingConfig")}</p>;
  const busy=d.pending || saving;
  const chosen=view.models.find(m=>m.id===d.model);
  const pick=()=>app.sheet({height:0.5,content:()=><>
    <SheetGrab /><SheetHead title={t("web-pages.automaticDecisions.model")} />
    {d.pick && <ModelList models={d.pick.options} runtime="codex" picked={d.model} onPick={model=>{app.sheet(null);edit({model});}} />}
  </>});
  return <>
    <div className={css.stationHead}><div className={css.stationName}><SectionHeader title={name} start={24} /></div>{refreshing ? <Spinner size={16} /> : <NavButton icon={Refresh} label={t("web-pages.automaticDecisions.refresh")} onClick={refresh} />}</div>
    {refreshFailed && <p className={`${settings.mPageNote} ${parts.mRed}`}>{refreshFailed}</p>}
    <ListCard>
      <ListRow onClick={busy ? undefined : ()=>edit({enabled:!d.enabled})}>
        <span className={`${parts.mGrow} ${lists.mRowText}`}><span className={lists.mRowTitle}>{t("web-pages.automaticDecisions.completion")}</span><span className={`${lists.mRowNote} ${settings.mWrap}`}>{t("web-pages.automaticDecisions.completionShort")}</span></span>
        <span className={connects.mSwitch} data-on={d.enabled || undefined} />
      </ListRow>
      <GoRow title={t("web-pages.automaticDecisions.model")} value={chosen?.name ?? (d.model ? t("web-pages.automaticDecisions.unavailable", {model:d.model}) : t("web-pages.automaticDecisions.pickModel"))} onClick={()=>{if(!busy)pick();}} />
    </ListCard>
    {d.dirty && <div className={settings.mProfileTools}><Button label={t("web-pages.automaticDecisions.save")} primary busy={saving} enabled={!busy} onClick={save} />{saveFailed && <FailedMark error={saveFailed} size={14} />}</div>}
    <SectionHeader title={t("web-pages.automaticDecisions.recent")} start={24} />
    <ListCard>
      {!view.recent.length && <ListRow><span className={parts.mMuted}>{t("web-pages.automaticDecisions.noRecords")}</span></ListRow>}
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
