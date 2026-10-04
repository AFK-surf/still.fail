import { t } from "./i18n.ts";
import { type ReactNode, useEffect, useId, useState } from "react";
import { Link } from "react-router";
import { useStations } from "./api.ts";
import { useCall, useTopic } from "./core/react.ts";
import type { ArchiveOptionView, ArchivePolicyDraft, ArchivePolicyView, AutomaticDecisionDraft, AutomaticDecisionView } from "./core/shapes.ts";
import { useAct, useToast } from "./toast.tsx";
import { useDoing, useDoingFailed } from "./doing.ts";
import { Button, Dialog, Field, Segmented, StatusDot, Switch } from "./ui.tsx";
import { ModelTriple } from "./ModelTriple.tsx";
import type { Picking } from "./pick.ts";
import { ChevronRight, Plus, Trash } from "./icons.tsx";
import * as waitingCss from "./styles/waiting.css.ts";
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

/** The archive policy: its words, then its options in their two groups, each with how many chats the checks put
 *  there. Each part is edited on its own, in a dialog: the words, an option (with the chats it got), a new option. */
function ArchivePolicy({ station, policy }: { station: string; policy: ArchivePolicyView }) {
  const form = usePolicyForm(station);
  const [editing, setEditing] = useState<PolicyEdit | null>(null);
  const busy = !form.d || form.d.pending;
  const open = (what: PolicyEdit) => { void form.reset().then(() => setEditing(what)); };
  const add = (archive: boolean) => { void form.add(archive).then((key) => { if (key) setEditing({ kind: "option", key }); }); };
  return <div className={css.policy}>
    <div className={css.policyHead}>
      <span className={css.policyTitle}>{t("web-pages.archivePolicy.title")}</span>
      {form.saving && <span className={`${waitingCss.spinner}`} aria-hidden="true" />}
      {form.saveFailed && <span className={css.error} role="alert">{form.saveFailed}</span>}
    </div>
    <button type="button" className={css.policyWords} disabled={busy} onClick={() => open({ kind: "text" })}>{policy.text}</button>
    {[true, false].map((archive) => <div key={String(archive)} className={css.policyGroup}>
      <span className={css.policyGroupName}>{t(archive ? "web-pages.archivePolicy.archive" : "web-pages.archivePolicy.keep")}</span>
      {policy.options.filter((o) => o.archive === archive).map((o) =>
        <button key={o.id} type="button" className={css.option} disabled={busy} onClick={() => open({ kind: "option", id: o.id, view: o })}>
          <span className={css.optionName}>{o.name}</span>
          <span className={css.optionRubric}>{o.rubric}</span>
          <span className={css.optionCount}>{o.count}</span>
        </button>)}
      <Button variant="ghost" icon={Plus} disabled={busy} onClick={() => add(archive)}>{t("web-pages.archivePolicy.add")}</Button>
    </div>)}
    <p className={css.note}>{policy.changeText ? `${policy.changeText} · ` : ""}<span className={policy.failed ? css.bad : undefined}>{policy.summaryText}</span></p>
    {editing && form.d && <PolicyDialog station={station} edit={editing} d={form.d} form={form} days={policy.days} onClose={() => setEditing(null)} />}
  </div>;
}

/** What a dialog edits: the words; an option of the station's (by its id, with what the checks put there); a new one (its draft key). */
type PolicyEdit = { kind: "text" } | { kind: "option"; id: string; view: ArchiveOptionView } | { kind: "option"; key: string };

function PolicyDialog({ station, edit, d, form, days, onClose }: { station: string; edit: PolicyEdit; d: ArchivePolicyDraft; form: ReturnType<typeof usePolicyDraft>; days: number; onClose: () => void }) {
  // Closed at once; the save goes on under the policy's title (a spinner, or what went wrong).
  const save = () => { onClose(); void form.save().catch(() => {}); };
  const cancel = () => { onClose(); void form.reset(); };
  const foot = (extra?: ReactNode) => <>
    {extra}
    <span className={css.grow} />
    <Button variant="ghost" onClick={cancel}>{t("web-pages.archivePolicy.cancel")}</Button>
    <Button variant="primary" disabled={!d.dirty} onClick={save}>{t("web-pages.archivePolicy.save")}</Button>
  </>;
  if (edit.kind === "text") return <Dialog open title={t("web-pages.archivePolicy.title")} description={t("web-pages.archivePolicy.textLead")} onClose={cancel} footer={foot()} wide>
    <textarea className={`${controlsCss.input} ${css.policyText}`} rows={8} autoFocus value={d.policy} aria-label={t("web-pages.archivePolicy.title")}
      onChange={(e) => form.edit({ policy: e.target.value })} />
  </Dialog>;
  const isNew = "key" in edit;
  const o = d.options.find((x) => (isNew ? x.key === edit.key : x.id === edit.id));
  if (!o) return null;
  const view = isNew ? null : edit.view;
  const nameId = `${o.key}-name`; const rubricId = `${o.key}-rubric`;
  const remove = () => { onClose(); void form.change({ remove: o.key }).then(() => form.save()).catch(() => {}); };
  return <Dialog open title={isNew ? t("web-pages.archivePolicy.newOption") : view!.name} onClose={cancel}
    footer={foot(!isNew && <Button variant="danger" icon={Trash} onClick={remove}>{t("web-pages.archivePolicy.remove")}</Button>)}>
    <Field label={t("web-pages.archivePolicy.name")} htmlFor={nameId}>
      <input id={nameId} className={controlsCss.input} autoFocus={isNew} value={o.name} onChange={(e) => form.edit({ option: o.key, name: e.target.value })} />
    </Field>
    <Field label={t("web-pages.archivePolicy.rubric")} htmlFor={rubricId}>
      <textarea id={rubricId} className={`${controlsCss.input} ${css.policyText}`} rows={3} value={o.rubric} onChange={(e) => form.edit({ option: o.key, rubric: e.target.value })} />
    </Field>
    <Segmented label={t("web-pages.archivePolicy.counts")} value={o.archive ? "archive" : "keep"} onChange={(v) => form.edit({ option: o.key, archive: v === "archive" })}
      options={[{ value: "archive", label: t("web-pages.archivePolicy.archive") }, { value: "keep", label: t("web-pages.archivePolicy.keep") }]} />
    {view && view.count > 0 && <div className={css.optionChats}>
      <span className={css.policyGroupName}>{t("web-pages.archivePolicy.chats", { days })}</span>
      {view.chats.map((c) => <Link key={c.session} to={`${stationBase(station)}/chats/${encodeURIComponent(c.session)}`} className={css.optionChat} onClick={cancel}>{c.title}</Link>)}
      {view.count > view.chats.length && <span className={css.note}>{t("web-pages.archivePolicy.more", { n: view.count - view.chats.length })}</span>}
    </div>}
  </Dialog>;
}

/** The core's draft of a station's archive policy, for both layouts: opened while the page shows it. */
export function usePolicyForm(station: string) {
  const form = useId(); const call = useCall(); const act = useAct();
  useEffect(() => {
    act(call("automaticDecisions.policy.open", { station, form }), t("web-pages.archivePolicy.readAction"));
    return () => { act(call("automaticDecisions.policy.drop", { station, form }), t("web-pages.archivePolicy.closeAction")); };
  }, [call, station, form, act]);
  return usePolicyDraft(station, form);
}

/** A draft opened elsewhere (by usePolicyForm), read and changed here: a sheet over the page shows the same one. */
export function usePolicyDraft(station: string, form: string) {
  const call = useCall(); const act = useAct(); const toast = useToast();
  const state = useTopic<ArchivePolicyDraft | null>({ topic: "policyForm", station, form });
  const saving = useDoing("automaticDecisions.policy.save", { station, form });
  const saveFailed = useDoingFailed("automaticDecisions.policy.save", { station, form });
  const change = (input: Record<string, unknown>) => call("automaticDecisions.policy.edit", { station, form, input }) as Promise<ArchivePolicyDraft | null>;
  const edit = (input: Record<string, unknown>) => act(change(input), t("web-pages.archivePolicy.editAction"));
  // Back to the station's, before a part is edited: what an earlier dialog left unsaved is gone.
  const reset = () => change({ reset: true }).catch(() => null);
  // A new option at the end of its group, edited next: its key.
  const add = (archive: boolean) => reset().then(() => change({ add: archive })).then((v) => v?.options.at(-1)?.key ?? null, () => null);
  const save = () => call("automaticDecisions.policy.save", { station, form }).then(() => toast(t("web-pages.archivePolicy.saved")));
  return { form, d: state.value, saving, saveFailed, change, edit, reset, add, save };
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
