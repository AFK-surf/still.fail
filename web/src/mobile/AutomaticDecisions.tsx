import { t } from "../i18n.ts";
import { Fragment, type ReactNode } from "react";
import { useParams } from "react-router";
import { useAutomaticDecisionForm, usePolicyDraft, usePolicyForm } from "../AutomaticDecisions.tsx";
import { useStations } from "../api.ts";
import type { ArchiveOptionView, ArchivePolicyView, AutomaticDecisionView } from "../core/shapes.ts";
import { ChevronRight, Refresh } from "../icons.tsx";
import { stationBase } from "../station.tsx";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { Button, FailedMark, Field, LargeTitle, LinkButton, ListCard, ListRow, NavButton, SectionHeader, Seg, Spinner, TopBack } from "./parts.tsx";
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
      {view.policy && <ListRow onClick={()=>app.push(app.at(`/settings/automatic-decisions/completion/${encodeURIComponent(station)}`))}>
        <span className={`${parts.mGrow} ${lists.mRowText}`}><span className={lists.mRowTitle}>{t("web-pages.archivePolicy.title")}</span><span className={`${lists.mRowNote} ${view.policy.failed ? parts.mRed : ""}`}>{t("web-pages.archivePolicy.optionCount",{n:view.policy.options.length})}{view.policy.summaryText ? ` · ${view.policy.summaryText}` : ""}</span></span>
        <ChevronRight size={14} className={parts.mSubtle} />
      </ListRow>}
    </ListCard>
    {d.dirty && <div className={settings.mProfileTools}><Button label={t("web-pages.automaticDecisions.save")} primary busy={saving} enabled={!busy} onClick={save} />{saveFailed && <FailedMark error={saveFailed} size={14} />}</div>}
  </>;
}

/** A station's archive policy, on a screen of its own (from its row under the station's rule). */
export function AutomaticDecisionPolicyScreen() {
  const app=useApp();
  const {station=""}=useParams();
  const stations=useStations(app.entry.id);
  const s=stations.value?.find(x=>x.station===station);
  const view=s?.online ? s.overview?.automaticDecisions : undefined;
  return <div className={`${pages.mScreen} ${pages.mScroll}`}>
    <TopBack label={t("web-pages.automaticDecisions.completion")} onBack={app.pop} />
    <LargeTitle small={s?.name ?? ""} big={t("web-pages.archivePolicy.title")} />
    {view?.policy && view.canEdit ? <PolicySection station={station} policy={view.policy} />
      : <p className={settings.mPageNote}>{stations.error?.message ?? (!stations.value ? t("web-pages.automaticDecisions.reading")
        : !s?.online ? t("web-pages.automaticDecisions.offlineNote") : !s.overview ? t("web-pages.automaticDecisions.connecting")
        : view && !view.canEdit ? t("web-pages.automaticDecisions.adminOnly") : t("web-pages.automaticDecisions.upgrade"))}</p>}
    <div style={{height:30}} />
  </div>;
}


/** The station's archive policy: its words and its options in their two groups, each with how many chats the checks
 *  put there. A tap edits what it is on, in a sheet: the words, an option (with the chats it got), a new option. */
function PolicySection({station,policy}:{station:string;policy:ArchivePolicyView}) {
  const app=useApp();
  const form=usePolicyForm(station);
  const busy=!form.d || form.d.pending;
  const group=(archive:boolean)=>t(archive ? "web-pages.archivePolicy.archive" : "web-pages.archivePolicy.keep");
  const sheet=(edit:PolicyEdit)=>app.sheet({height:0.85,content:()=><PolicySheet station={station} form={form.form} edit={edit} days={policy.days} close={()=>app.sheet(null)} />});
  const open=(edit:PolicyEdit)=>{void form.reset().then(()=>sheet(edit));};
  const add=(archive:boolean)=>{void form.add(archive).then(key=>{if(key)sheet({kind:"option",key});});};
  return <>
    <div className={css.stationHead}><div className={css.stationName}><p className={settings.mPageNote}>{t("web-pages.archivePolicy.textLead")}</p></div>{form.saving ? <Spinner size={16} /> : form.saveFailed && <FailedMark error={form.saveFailed} size={14} />}</div>
    <ListCard><ListRow onClick={busy ? undefined : ()=>open({kind:"text"})}>
      <span className={`${parts.mGrow} ${css.policyWords}`}>{policy.text}</span>
    </ListRow></ListCard>
    {[true,false].map(archive=><Fragment key={String(archive)}>
      <SectionHeader title={group(archive)} start={24} />
      <ListCard>
        {policy.options.filter(o=>o.archive===archive).map(o=><ListRow key={o.id} onClick={busy ? undefined : ()=>open({kind:"option",id:o.id,view:o})}>
          <span className={`${parts.mGrow} ${lists.mRowText}`}><span className={lists.mRowTitle}>{o.name}</span><span className={`${lists.mRowNote} ${settings.mWrap}`}>{o.rubric}</span></span>
          <span className={css.count}>{o.count}</span>
        </ListRow>)}
        <ListRow onClick={busy ? undefined : ()=>add(archive)}><span className={parts.mLink}>{t("web-pages.archivePolicy.add")}</span></ListRow>
      </ListCard>
    </Fragment>)}
    <p className={settings.mPageNote}>{policy.changeText ? `${policy.changeText} · ` : ""}<span className={policy.failed ? parts.mRed : undefined}>{policy.summaryText}</span></p>
  </>;
}

/** What a sheet edits: the words; an option of the station's (by its id, with what the checks put there); a new one (its draft key). */
type PolicyEdit = { kind: "text" } | { kind: "option"; id: string; view: ArchiveOptionView } | { kind: "option"; key: string };

function PolicySheet({station,form,edit,days,close}:{station:string;form:string;edit:PolicyEdit;days:number;close:()=>void}) {
  const app=useApp();
  const draft=usePolicyDraft(station,form);
  const d=draft.d;
  if (!d) return null;
  // Closed at once; the save goes on beside the policy's title (a spinner, or what went wrong).
  const save=()=>{close();void draft.save().catch(()=>{});};
  const cancel=()=>{close();void draft.reset();};
  const tools=(extra?:ReactNode)=><div className={css.sheetTools}>
    {extra}<span className={parts.mGrow} />
    <Button label={t("web-pages.archivePolicy.cancel")} primary={false} onClick={cancel} />
    <Button label={t("web-pages.archivePolicy.save")} primary enabled={d.dirty} onClick={save} />
  </div>;
  if (edit.kind==="text") return <>
    <SheetGrab /><SheetHead title={t("web-pages.archivePolicy.title")} />
    <div className={css.sheetBody}>
      <p className={lists.mRowNote}>{t("web-pages.archivePolicy.textLead")}</p>
      <textarea className={`${lists.mField} ${css.policyText}`} rows={9} value={d.policy} aria-label={t("web-pages.archivePolicy.title")} onChange={e=>draft.edit({policy:e.target.value})} />
      {tools()}
    </div>
  </>;
  const isNew="key" in edit;
  const o=d.options.find(x=>isNew ? x.key===edit.key : x.id===edit.id);
  if (!o) return null;
  const view=isNew ? null : edit.view;
  const remove=()=>{close();void draft.change({remove:o.key}).then(()=>draft.save()).catch(()=>{});};
  return <>
    <SheetGrab /><SheetHead title={isNew ? t("web-pages.archivePolicy.newOption") : view!.name} />
    <div className={css.sheetBody}>
      <Field value={o.name} placeholder={t("web-pages.archivePolicy.name")} onChange={name=>draft.edit({option:o.key,name})} />
      <textarea className={lists.mField} rows={3} value={o.rubric} placeholder={t("web-pages.archivePolicy.rubric")} aria-label={t("web-pages.archivePolicy.rubric")} onChange={e=>draft.edit({option:o.key,rubric:e.target.value})} />
      <Seg fill options={[t("web-pages.archivePolicy.archive"),t("web-pages.archivePolicy.keep")]} selected={o.archive ? 0 : 1} onSelect={i=>draft.edit({option:o.key,archive:i===0})} />
      {view && view.count>0 && <>
        <p className={lists.mRowNote}>{t("web-pages.archivePolicy.chats",{days})}</p>
        <ListCard>{view.chats.map(c=><ListRow key={c.session} onClick={()=>{cancel();app.push(`${stationBase(station)}/chats/${encodeURIComponent(c.session)}`);}}>
          <span className={`${parts.mGrow} ${css.chat}`}>{c.title}</span><ChevronRight size={14} className={parts.mSubtle} />
        </ListRow>)}</ListCard>
      </>}
      {tools(!isNew && <LinkButton label={t("web-pages.archivePolicy.remove")} className={parts.mRed} onClick={remove} />)}
    </div>
  </>;
}
