import { t } from "./i18n.ts";
import { useEffect, useId } from "react";
import { Link } from "react-router";
import { useStations } from "./api.ts";
import { useCall, useTopic } from "./core/react.ts";
import type { AutomaticDecisionCheck, AutomaticDecisionDraft, AutomaticDecisionView } from "./core/shapes.ts";
import { useAct } from "./toast.tsx";
import { useDoing, useDoingFailed } from "./doing.ts";
import { Button, Section, StatusDot, Switch, Time } from "./ui.tsx";
import { ModelTriple } from "./ModelTriple.tsx";
import type { Picking } from "./pick.ts";
import { ChevronRight } from "./icons.tsx";
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

/** Check history has its own page, separate from the decision point's settings. */
export function AutomaticDecisionLogs({ workspace }: { workspace: string }) {
  const stations = useStations(workspace);
  return <div className={css.content}>
    {!stations.value && <p className={css.note}>{stations.error?.message ?? t("web-pages.automaticDecisions.reading")}</p>}
    {stations.value?.map(s => <Section key={s.station} title={s.name}>
      {!s.online ? <p className={css.note}>{t("web-pages.automaticDecisions.offline")}</p>
        : !s.overview ? <p className={css.note}>{t("web-pages.automaticDecisions.connecting")}</p>
        : !s.overview.automaticDecisions ? <p className={css.note}>{t("web-pages.automaticDecisions.upgrade")}</p>
        : !s.overview.automaticDecisions.canEdit ? <p className={css.note}>{t("web-pages.automaticDecisions.adminOnly")}</p>
        : <DecisionRecords station={s.station} view={s.overview.automaticDecisions} />}
    </Section>)}
  </div>;
}
/** Red only where the check itself failed; a station from before `outcome` knew only whether it was suggested. */
export const failed = (row: AutomaticDecisionCheck) => row.outcome ? row.outcome === "failed" : !row.accepted;
function DecisionRecords({station,view}:{station:string;view:AutomaticDecisionView}) {
  return !view.recent.length ? <p className={css.note}>{t("web-pages.automaticDecisions.empty")}</p> : <ul className={pages.list}>
    {view.recent.map(row => <li key={row.id}>
      <Link className={pages.listRow} to={`${stationBase(station)}/chats/${encodeURIComponent(row.session)}`}>
        <span className={pages.listRowText}>
          <span className={css.recordHead}><span className={pages.listRowTitle}>{row.title}</span><Time stamp={row.stamp} className={css.time} /></span>
          <span className={css.meta}><span className={failed(row) ? css.bad : undefined}>{row.label}</span></span>
          {row.error && <span className={css.error}>{row.error}</span>}
        </span>
      </Link>
    </li>)}
  </ul>;
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
  </li>;
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
