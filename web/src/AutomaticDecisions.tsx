import { t } from "./i18n.ts";
import { useEffect, useId, useState } from "react";
import { Link } from "react-router";
import { useStations } from "./api.ts";
import { useCall, useTopic } from "./core/react.ts";
import type { ArchiveOptionDraft, ArchiveOptionView, ArchivePolicyDraft, ArchivePolicyView, AutomaticDecisionDraft, AutomaticDecisionView } from "./core/shapes.ts";
import { useAct, useToast } from "./toast.tsx";
import { useDoing, useDoingFailed } from "./doing.ts";
import { Button, IconButton, StatusDot, Switch } from "./ui.tsx";
import { ModelTriple } from "./ModelTriple.tsx";
import type { Picking } from "./pick.ts";
import { ArrowDown, ArrowUp, ChevronRight, Edit, Plus, Trash } from "./icons.tsx";
import * as controlsCss from "./styles/controls.css.ts";
import { stationBase } from "./station.tsx";
import * as pages from "./styles/pages.css.ts";
import * as css from "./AutomaticDecisions.css.ts";

/** Start with the decision point; each point opens the stations that configure it. */
export function AutomaticDecisions({ workspace }: { workspace: string }) {
  const stations = useStations(workspace).value;
  const on = stations?.filter(s => s.overview?.automaticDecisions?.settings.completion?.enabled).length ?? 0;
  return <div className={css.content}><ul className={pages.list}><li>
    <Link className={pages.listRow} to={`/w/${workspace}/settings/automatic-decisions/completion`}>
      <span className={pages.listRowText}><span className={pages.listRowTitle}>{t("web-pages.automaticDecisions.completion")}</span><span className={css.note}>{t("web-pages.automaticDecisions.completionNote")}</span></span>
      {stations && <span className={css.note}>{on ? t("web-pages.automaticDecisions.stationsOn", {n: on}) : t("web-pages.automaticDecisions.off")}</span>}
      <ChevronRight size={16} className={css.note} />
    </Link>
  </li></ul></div>;
}

export function AutomaticDecisionCompletion({ workspace }: { workspace: string }) {
  const stations = useStations(workspace);
  return <div className={css.content}>
    {!stations.value && <p className={css.note}>{stations.error?.message ?? t("web-pages.automaticDecisions.reading")}</p>}
    {stations.value?.length === 0 && <p className={css.note}>{t("web-pages.automaticDecisions.addStation")}</p>}
    <ul className={pages.list}>{stations.value?.map(s => s.online && s.overview?.automaticDecisions
      ? <AutomaticDecisionPanel key={s.station} station={s.station} name={s.name} view={s.overview.automaticDecisions} />
      : <li key={s.station} className={pages.listRow}><StatusDot state={s.online ? "online" : "offline"} /><span className={pages.listRowText}><span className={pages.listRowTitle}>{s.name}</span><span className={css.note}>{!s.online ? t("web-pages.automaticDecisions.offline") : !s.overview ? t("web-pages.automaticDecisions.connecting") : t("web-pages.automaticDecisions.upgrade")}</span></span></li>)}</ul>
  </div>;
}

function AutomaticDecisionPanel({ station, name, view }: { station: string; name: string; view: AutomaticDecisionView }) {
  const {d, state, saving, saveFailed, reviewing, reviewFailed, canReview, edit, save, review} = useAutomaticDecisionForm(station, view);
  const status = (text: string) => <li className={pages.listRow}><StatusDot state="online" /><span className={pages.listRowText}><span className={pages.listRowTitle}>{name}</span><span className={css.note}>{text}</span></span></li>;
  if (!view.canEdit) return status(t("web-pages.automaticDecisions.adminOnly"));
  if (!d) return status(state.error?.message ?? t("web-pages.automaticDecisions.readingConfig"));
  const busy = d.pending || saving;
  const chosen = view.models.find(m => m.id === d.model);
  return <li>
    <div className={pages.listRow}>
      <StatusDot state="online" label={t("web-pages.automaticDecisions.online")} />
      <span className={pages.listRowText}>
        <span className={pages.listRowTitle}>{name}</span>
        <span className={css.note}>{d.enabled ? t("web-pages.automaticDecisions.enabledWith", {model: chosen?.name ?? t("web-pages.automaticDecisions.noModels")}) : t("web-pages.automaticDecisions.disabled")}</span>
      </span>
      <span className={css.controls}>
      {d.pick ? <ModelTriple modelOnly pick={{view:d.pick, saving:busy,
        set: patch => edit(patch.open ? {pickOpen:true} : {pickModel:patch.model}),
        save: async () => {await edit({pickConfirm:true});return {saved:true};},
      } satisfies Picking} onConfirm={() => edit({pickConfirm:true})} />
        : <span className={css.note}>{chosen?.name ?? t("web-pages.automaticDecisions.noModels")}</span>}
      <Switch id={`decision-${station}`} label={t("web-pages.automaticDecisions.enableOn",{station:name})} checked={d.enabled} disabled={busy} onChange={enabled => edit({enabled})} />
      {d.dirty && <Button variant="primary" busy={saving} disabled={busy} onClick={save}>{t("web-pages.automaticDecisions.save")}</Button>}
      {canReview && <Button variant="ghost" busy={reviewing} disabled={busy || reviewing} onClick={review}>{t("web-pages.automaticDecisions.review")}</Button>}
      </span>
    </div>
    {saveFailed && <p className={css.error} role="alert">{saveFailed}</p>}
    {reviewFailed && <p className={css.error} role="alert">{reviewFailed}</p>}
    {view.policy && <ArchivePolicy station={station} policy={view.policy} />}
  </li>;
}

/** The archive policy: its words, then its options in their two groups, each with the chats the checks put there. */
function ArchivePolicy({ station, policy }: { station: string; policy: ArchivePolicyView }) {
  const form = usePolicyForm(station);
  const [editing, setEditing] = useState(false);
  const [open, setOpen] = useState<string | null>(null);
  const d = form.d;
  if (editing && d) return <div className={css.policy}>
    <div className={css.policyHead}><span className={css.policyTitle}>{t("web-pages.archivePolicy.title")}</span></div>
    <textarea className={`${controlsCss.input} ${css.policyText}`} rows={4} value={d.policy} disabled={d.pending} aria-label={t("web-pages.archivePolicy.title")}
      onChange={(e) => form.edit({ policy: e.target.value })} />
    {[true, false].map((archive) => <div key={String(archive)} className={css.policyGroup}>
      <span className={css.policyGroupName}>{t(archive ? "web-pages.archivePolicy.archive" : "web-pages.archivePolicy.keep")}</span>
      {d.options.filter((o) => o.archive === archive).map((o) => <OptionEditor key={o.key} option={o} pending={d.pending} edit={form.edit} />)}
      <Button variant="ghost" icon={Plus} disabled={d.pending} onClick={() => form.edit({ add: archive })}>{t("web-pages.archivePolicy.add")}</Button>
    </div>)}
    {form.saveFailed && <p className={css.error} role="alert">{form.saveFailed}</p>}
    <div className={css.policyFoot}>
      <Button variant="ghost" disabled={d.pending} onClick={() => { form.edit({ reset: true }); setEditing(false); }}>{t("web-pages.archivePolicy.cancel")}</Button>
      <Button variant="primary" busy={form.saving} disabled={!d.dirty || d.pending} onClick={() => form.save().then(() => setEditing(false), () => {})}>{t("web-pages.archivePolicy.save")}</Button>
    </div>
  </div>;
  return <div className={css.policy}>
    <div className={css.policyHead}>
      <span className={css.policyTitle}>{t("web-pages.archivePolicy.title")}</span>
      <Button variant="ghost" icon={Edit} disabled={!d} onClick={() => setEditing(true)}>{t("web-pages.archivePolicy.edit")}</Button>
    </div>
    <p className={css.policyWords}>{policy.text}</p>
    {[true, false].map((archive) => <div key={String(archive)} className={css.policyGroup}>
      <span className={css.policyGroupName}>{t(archive ? "web-pages.archivePolicy.archive" : "web-pages.archivePolicy.keep")}</span>
      {policy.options.filter((o) => o.archive === archive).map((o) => <OptionRow key={o.id} station={station} option={o} open={open === o.id} toggle={() => setOpen(open === o.id ? null : o.id)} />)}
    </div>)}
    <p className={css.note}>{policy.changeText ? `${policy.changeText} · ` : ""}<span className={policy.failed ? css.bad : undefined}>{policy.summaryText}</span></p>
  </div>;
}

function OptionRow({ station, option, open, toggle }: { station: string; option: ArchiveOptionView; open: boolean; toggle: () => void }) {
  return <>
    <button type="button" className={css.option} aria-expanded={option.count ? open : undefined} disabled={!option.count} onClick={toggle}>
      <span className={css.optionName}>{option.name}</span>
      <span className={css.optionRubric}>{option.rubric}</span>
      <span className={css.optionCount}>{option.count}</span>
    </button>
    {open && <div className={css.optionChats}>{option.chats.map((c) =>
      <Link key={c.session} to={`${stationBase(station)}/chats/${encodeURIComponent(c.session)}`} className={css.optionChat}>{c.title}</Link>)}
      {option.count > option.chats.length && <span className={css.note}>{t("web-pages.archivePolicy.more", { n: option.count - option.chats.length })}</span>}
    </div>}
  </>;
}

function OptionEditor({ option, pending, edit }: { option: ArchiveOptionDraft; pending: boolean; edit: (patch: Record<string, unknown>) => void }) {
  return <div className={css.optionEdit}>
    <input className={`${controlsCss.input} ${css.optionNameInput}`} value={option.name} disabled={pending} placeholder={t("web-pages.archivePolicy.name")} aria-label={t("web-pages.archivePolicy.name")}
      onChange={(e) => edit({ option: option.key, name: e.target.value })} />
    <input className={controlsCss.input} value={option.rubric} disabled={pending} placeholder={t("web-pages.archivePolicy.rubric")} aria-label={t("web-pages.archivePolicy.rubric")}
      onChange={(e) => edit({ option: option.key, rubric: e.target.value })} />
    <IconButton icon={option.archive ? ArrowDown : ArrowUp} disabled={pending} label={t(option.archive ? "web-pages.archivePolicy.toKeep" : "web-pages.archivePolicy.toArchive")}
      onClick={() => edit({ option: option.key, archive: !option.archive })} />
    <IconButton icon={Trash} disabled={pending} label={t("web-pages.archivePolicy.remove")} onClick={() => edit({ remove: option.key })} />
  </div>;
}

/** The core's draft of a station's archive policy, for both layouts. */
export function usePolicyForm(station: string) {
  const form = useId(); const call = useCall(); const act = useAct(); const toast = useToast();
  const state = useTopic<ArchivePolicyDraft | null>({ topic: "policyForm", station, form });
  const saving = useDoing("automaticDecisions.policy.save", { station, form });
  const saveFailed = useDoingFailed("automaticDecisions.policy.save", { station, form });
  useEffect(() => {
    act(call("automaticDecisions.policy.open", { station, form }), t("web-pages.archivePolicy.readAction"));
    return () => { act(call("automaticDecisions.policy.drop", { station, form }), t("web-pages.archivePolicy.closeAction")); };
  }, [call, station, form, act]);
  const edit = (input: Record<string, unknown>) => act(call("automaticDecisions.policy.edit", { station, form, input }), t("web-pages.archivePolicy.editAction"));
  const save = () => call("automaticDecisions.policy.save", { station, form }).then(() => toast(t("web-pages.archivePolicy.saved")));
  return { d: state.value, saving, saveFailed, edit, save };
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
  const reviewing = useDoing("automaticDecisions.review", { station });
  const reviewFailed = useDoingFailed("automaticDecisions.review", {station});
  // Asked of the station as saved: only once the rule is on there, and nothing unsaved.
  const canReview = !!view.canReview && !!view.settings.completion?.enabled && !!d && !d.dirty;
  useEffect(() => {
    if (!view.canEdit) return;
    act(call("automaticDecisions.form.open", { station, form }), t("web-pages.automaticDecisions.readAction"));
    return () => { act(call("automaticDecisions.form.drop", { station, form }), t("web-pages.automaticDecisions.closeAction")); };
  }, [call, station, form, view.canEdit, act]);
  const edit = (input: Record<string, unknown>) => act(call("automaticDecisions.form.edit", { station, form, input }), t("web-pages.automaticDecisions.editAction"));
  return {d, state, saving, refreshing, saveFailed, refreshFailed, reviewing, reviewFailed, canReview, edit,
    review: () => act(call("automaticDecisions.review", {station}), t("web-pages.automaticDecisions.reviewAction"), t("web-pages.automaticDecisions.reviewStarted")),
    save: () => act(call("automaticDecisions.form.save", {station,form}), t("web-pages.automaticDecisions.saveAction"), t("web-pages.automaticDecisions.saved")),
    refresh: () => act(call("automaticDecisions.refresh", {station}), t("web-pages.automaticDecisions.refreshAction"), t("web-pages.automaticDecisions.refreshed"))};
}
