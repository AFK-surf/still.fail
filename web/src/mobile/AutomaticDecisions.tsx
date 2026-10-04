import { t } from "../i18n.ts";
import { Fragment, useState } from "react";
import { useAutomaticDecisionForm, usePolicyForm } from "../AutomaticDecisions.tsx";
import { useStations } from "../api.ts";
import type { ArchivePolicyView, AutomaticDecisionView } from "../core/shapes.ts";
import { ChevronRight, Edit, Refresh } from "../icons.tsx";
import { stationBase } from "../station.tsx";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { Button, FailedMark, Field, LargeTitle, LinkButton, ListCard, ListRow, NavButton, SectionHeader, Spinner, TopBack } from "./parts.tsx";
import { ModelList } from "./History.tsx";
import { GoRow } from "./Settings.tsx";
import * as css from "./AutomaticDecisions.css.ts";
import * as pages from "./styles/pages.css.ts";
import * as parts from "./styles/parts.css.ts";
import * as lists from "./styles/lists.css.ts";
import * as settings from "./styles/settings.css.ts";
import * as connects from "./Connects.css.ts";

export function AutomaticDecisionsScreen() {
  const app=useApp();
  return <div className={`${pages.mScreen} ${pages.mScroll}`}>
    <TopBack label={t("web-pages.settings.title")} onBack={app.pop} />
    <LargeTitle small="" big={t("web-pages.automaticDecisions.title")} />
    <ListCard><ListRow onClick={()=>app.push(app.at("/settings/automatic-decisions/completion"))}>
      <span className={`${parts.mGrow} ${lists.mRowText}`}><span className={lists.mRowTitle}>{t("web-pages.automaticDecisions.completion")}</span><span className={`${lists.mRowNote} ${settings.mWrap}`}>{t("web-pages.automaticDecisions.completionShort")}</span></span>
      <ChevronRight size={14} className={parts.mSubtle} />
    </ListRow></ListCard>
  </div>;
}
export function AutomaticDecisionCompletionScreen() {
  const app=useApp();
  const stations=useStations(app.entry.id);
  return <div className={`${pages.mScreen} ${pages.mScroll}`}>
    <TopBack label={t("web-pages.automaticDecisions.title")} onBack={app.pop} />
    <LargeTitle small="" big={t("web-pages.automaticDecisions.completion")} />
    {!stations.value && <p className={settings.mPageNote}>{stations.error?.message ?? t("web-pages.automaticDecisions.reading")}</p>}
    {stations.value?.length===0 && <p className={settings.mPageNote}>{t("web-pages.automaticDecisions.addStation")}</p>}
    {stations.value?.map(s => <Fragment key={s.station}>
      {s.online && s.overview?.automaticDecisions
        ? <DecisionPanel station={s.station} name={s.name} view={s.overview.automaticDecisions} />
        : <><SectionHeader title={s.name} start={24} /><p className={settings.mPageNote}>{!s.online ? t("web-pages.automaticDecisions.offlineNote") : !s.overview ? t("web-pages.automaticDecisions.connecting") : t("web-pages.automaticDecisions.upgrade")}</p></>}
    </Fragment>)}
    <div style={{height:30}} />
  </div>;
}
function DecisionPanel({station,name,view}:{station:string;name:string;view:AutomaticDecisionView}) {
  const app=useApp();
  const {d,state,saving,refreshing,saveFailed,refreshFailed,reviewing,reviewFailed,canReview,edit,save,refresh,review}=useAutomaticDecisionForm(station,view);
  if (!view.canEdit) return <p className={settings.mPageNote}>{t("web-pages.automaticDecisions.adminOnly")}</p>;
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
        <span className={`${parts.mGrow} ${lists.mRowText}`}><span className={lists.mRowTitle}>{t("web-pages.automaticDecisions.enabled")}</span></span>
        <span className={connects.mSwitch} data-on={d.enabled || undefined} />
      </ListRow>
      <GoRow title={t("web-pages.automaticDecisions.model")} value={chosen?.name ?? (d.model ? t("web-pages.automaticDecisions.unavailable", {model:d.model}) : t("web-pages.automaticDecisions.pickModel"))} onClick={()=>{if(!busy)pick();}} />
      {canReview && <ListRow onClick={busy || reviewing ? undefined : review}>
        <span className={`${parts.mGrow} ${lists.mRowText}`}><span className={lists.mRowTitle}>{t("web-pages.automaticDecisions.review")}</span></span>
        {reviewing ? <Spinner size={16} /> : reviewFailed && <FailedMark error={reviewFailed} size={14} />}
      </ListRow>}
    </ListCard>
    {d.dirty && <div className={settings.mProfileTools}><Button label={t("web-pages.automaticDecisions.save")} primary busy={saving} enabled={!busy} onClick={save} />{saveFailed && <FailedMark error={saveFailed} size={14} />}</div>}
    {view.policy && <PolicySection station={station} policy={view.policy} />}

  </>;
}


/** The station's archive policy: its words and its options in their two groups, each with the chats the checks put there. */
function PolicySection({station,policy}:{station:string;policy:ArchivePolicyView}) {
  const app=useApp();
  const form=usePolicyForm(station);
  const [editing,setEditing]=useState(false);
  const [open,setOpen]=useState<string|null>(null);
  const d=form.d;
  const group=(archive:boolean)=>t(archive ? "web-pages.archivePolicy.archive" : "web-pages.archivePolicy.keep");
  if (editing && d) return <>
    <SectionHeader title={t("web-pages.archivePolicy.title")} start={24} />
    <div className={css.policyPad}><textarea className={`${lists.mField} ${css.policyText}`} rows={5} value={d.policy} disabled={d.pending} aria-label={t("web-pages.archivePolicy.title")} onChange={e=>form.edit({policy:e.target.value})} /></div>
    {[true,false].map(archive=><Fragment key={String(archive)}>
      <SectionHeader title={group(archive)} start={24} />
      <div className={css.policyPad}>
        {d.options.filter(o=>o.archive===archive).map(o=><div key={o.key} className={css.optionEdit}>
          <Field value={o.name} placeholder={t("web-pages.archivePolicy.name")} onChange={name=>form.edit({option:o.key,name})} />
          <textarea className={lists.mField} rows={2} value={o.rubric} placeholder={t("web-pages.archivePolicy.rubric")} aria-label={t("web-pages.archivePolicy.rubric")} onChange={e=>form.edit({option:o.key,rubric:e.target.value})} />
          <div className={css.optionTools}>
            <LinkButton label={t(o.archive ? "web-pages.archivePolicy.toKeep" : "web-pages.archivePolicy.toArchive")} enabled={!d.pending} onClick={()=>form.edit({option:o.key,archive:!o.archive})} />
            <LinkButton label={t("web-pages.archivePolicy.remove")} className={parts.mRed} enabled={!d.pending} onClick={()=>form.edit({remove:o.key})} />
          </div>
        </div>)}
        <LinkButton label={t("web-pages.archivePolicy.add")} enabled={!d.pending} onClick={()=>form.edit({add:archive})} />
      </div>
    </Fragment>)}
    {form.saveFailed && <p className={`${settings.mPageNote} ${parts.mRed}`}>{form.saveFailed}</p>}
    <div className={settings.mProfileTools}>
      <Button label={t("web-pages.archivePolicy.cancel")} primary={false} enabled={!d.pending} onClick={()=>{form.edit({reset:true});setEditing(false);}} />
      <Button label={t("web-pages.archivePolicy.save")} primary busy={form.saving} enabled={d.dirty && !d.pending} onClick={()=>{form.save().then(()=>setEditing(false),()=>{});}} />
    </div>
  </>;
  return <>
    <div className={css.stationHead}><div className={css.stationName}><SectionHeader title={t("web-pages.archivePolicy.title")} start={24} /></div>{d && <NavButton icon={Edit} label={t("web-pages.archivePolicy.edit")} onClick={()=>setEditing(true)} />}</div>
    <p className={`${settings.mPageNote} ${css.policyWords}`}>{policy.text}</p>
    {[true,false].map(archive=><Fragment key={String(archive)}>
      <SectionHeader title={group(archive)} start={24} />
      <ListCard>{policy.options.filter(o=>o.archive===archive).map(o=><Fragment key={o.id}>
        <ListRow onClick={o.count ? ()=>setOpen(open===o.id ? null : o.id) : undefined}>
          <span className={`${parts.mGrow} ${lists.mRowText}`}><span className={lists.mRowTitle}>{o.name}</span><span className={`${lists.mRowNote} ${settings.mWrap}`}>{o.rubric}</span></span>
          <span className={css.count}>{o.count}</span>
        </ListRow>
        {open===o.id && o.chats.map(c=><ListRow key={c.session} onClick={()=>app.push(`${stationBase(station)}/chats/${encodeURIComponent(c.session)}`)}>
          <span className={`${parts.mGrow} ${css.chat}`}>{c.title}</span><ChevronRight size={14} className={parts.mSubtle} />
        </ListRow>)}
      </Fragment>)}</ListCard>
    </Fragment>)}
    <p className={settings.mPageNote}>{policy.changeText ? `${policy.changeText} · ` : ""}<span className={policy.failed ? parts.mRed : undefined}>{policy.summaryText}</span></p>
  </>;
}
